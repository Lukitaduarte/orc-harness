//! The daemon's iroh side: pairing and the main protocol for clients (the
//! app on desktop and phone). Only paired device keys get past the door.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use iroh::endpoint::Connection;
use iroh::{Endpoint, EndpointId, TransportAddr};
use orc_link::{ALPN_MAIN, ALPN_PAIR, PairRequest, PairResponse, Ticket, write_line};
use orc_protocol::{ClientMessage, DaemonMessage};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::broadcast::error::RecvError;

use crate::server::Daemon;

/// A pairing token lives this long and works once.
pub const PAIRING_TTL: Duration = Duration::from_secs(600);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub name: String,
    /// Unix seconds.
    pub paired_at: i64,
}

/// Paired device keys, persisted owner-only.
pub struct Devices {
    path: PathBuf,
    by_id: BTreeMap<String, Device>,
}

impl Devices {
    pub fn load(path: PathBuf) -> Self {
        let by_id = std::fs::read(&path)
            .ok()
            .and_then(|raw| serde_json::from_slice(&raw).ok())
            .unwrap_or_default();
        Self { path, by_id }
    }

    pub fn contains(&self, id: &EndpointId) -> bool {
        self.by_id.contains_key(&id.to_string())
    }

    pub fn add(&mut self, id: EndpointId, name: String) -> std::io::Result<()> {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
        self.by_id.insert(id.to_string(), Device { name, paired_at: now });
        self.save()
    }

    /// Revokes a device: its next connection is refused.
    pub fn remove(&mut self, id: &str) -> std::io::Result<bool> {
        let removed = self.by_id.remove(id).is_some();
        self.save()?;
        Ok(removed)
    }

    pub fn list(&self) -> &BTreeMap<String, Device> {
        &self.by_id
    }

    fn save(&self) -> std::io::Result<()> {
        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        std::fs::write(&self.path, serde_json::to_vec_pretty(&self.by_id)?)?;
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&self.path, std::fs::Permissions::from_mode(0o600))
    }
}

#[derive(Clone)]
pub struct Remote {
    pub endpoint: Endpoint,
    pub devices: Arc<Mutex<Devices>>,
    pairing: Arc<Mutex<Option<(String, Instant)>>>,
    /// Live connections by device key (closed on revoke).
    connected: Arc<Mutex<std::collections::HashMap<String, Connection>>>,
    /// A relay is configured: tickets wait for its address too.
    relay: bool,
}

impl Remote {
    pub fn new(endpoint: Endpoint, devices: Devices) -> Self {
        Self {
            endpoint,
            devices: Arc::new(Mutex::new(devices)),
            pairing: Arc::default(),
            connected: Arc::default(),
            relay: false,
        }
    }

    /// Tickets carry the relay address (reachable outside this network).
    pub fn with_relay(mut self, relay: bool) -> Self {
        self.relay = relay;
        self
    }

    /// Paired devices; `asking` is marked as `this`.
    pub fn device_list(&self, asking: Option<&str>) -> Vec<orc_protocol::DeviceInfo> {
        let connected = self.connected.lock().unwrap();
        self.devices
            .lock()
            .unwrap()
            .list()
            .iter()
            .map(|(id, d)| orc_protocol::DeviceInfo {
                id: id.clone(),
                name: d.name.clone(),
                paired_at: d.paired_at,
                connected: connected.contains_key(id),
                this: asking == Some(id.as_str()),
            })
            .collect()
    }

    /// Unpairs `id` and closes its connection now.
    pub fn revoke(&self, id: &str) -> std::io::Result<bool> {
        let removed = self.devices.lock().unwrap().remove(id)?;
        if let Some(conn) = self.connected.lock().unwrap().remove(id) {
            conn.close(403u32.into(), b"dispositivo revogado");
        }
        if removed {
            eprintln!("orcd: dispositivo revogado: {id}");
        }
        Ok(removed)
    }

    /// A fresh one-time ticket; the previous one stops working. Waits (up
    /// to 5 s) until the endpoint knows its local addresses: right after
    /// binding they may not be there yet, and a ticket without them is
    /// useless with no relay.
    pub async fn new_ticket(&self) -> Ticket {
        let deadline = Instant::now() + Duration::from_secs(if self.relay { 15 } else { 5 });
        let mut addr = self.endpoint.addr();
        let has_relay = |a: &iroh::EndpointAddr| a.addrs.iter().any(|t| matches!(t, TransportAddr::Relay(_)));
        // (`addr` gains loopback entries below.)
        while (addr.addrs.is_empty() || (self.relay && !has_relay(&addr))) && Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(50)).await;
            addr = self.endpoint.addr();
        }
        // Loopback too: the app on this Mac then never crosses the macOS
        // firewall, which blocks inbound UDP to unsigned binaries.
        for socket in self.endpoint.bound_sockets() {
            let ip: std::net::IpAddr = if socket.is_ipv4() {
                std::net::Ipv4Addr::LOCALHOST.into()
            } else {
                std::net::Ipv6Addr::LOCALHOST.into()
            };
            addr.addrs.insert(TransportAddr::Ip(std::net::SocketAddr::new(ip, socket.port())));
        }
        let token = uuid::Uuid::new_v4().simple().to_string();
        *self.pairing.lock().unwrap() = Some((token.clone(), Instant::now() + PAIRING_TTL));
        Ticket { addr, token }
    }

    /// Takes the token if it matches and is still valid (single use).
    fn redeem(&self, token: &str) -> bool {
        let mut slot = self.pairing.lock().unwrap();
        match slot.as_ref() {
            Some((t, until)) if t == token && Instant::now() < *until => {
                *slot = None;
                true
            }
            _ => false,
        }
    }

    pub async fn serve(self, daemon: Daemon) {
        while let Some(incoming) = self.endpoint.accept().await {
            let (remote, daemon) = (self.clone(), daemon.clone());
            tokio::spawn(async move {
                let Ok(conn) = incoming.await else { return };
                let result = match conn.alpn() {
                    a if a == ALPN_PAIR => remote.pair(&conn).await,
                    a if a == ALPN_MAIN => remote.main(&conn, daemon).await,
                    _ => Ok(()),
                };
                if result.is_err() {
                    conn.close(1u32.into(), b"erro");
                }
            });
        }
    }

    async fn pair(&self, conn: &Connection) -> std::io::Result<()> {
        let (mut send, recv) = conn.accept_bi().await.map_err(std::io::Error::other)?;
        let mut lines = BufReader::new(recv).lines();
        let req: PairRequest = match lines.next_line().await? {
            Some(line) => serde_json::from_str(&line)?,
            None => return Ok(()),
        };
        let ok = self.redeem(&req.token);
        if ok {
            eprintln!("orcd: dispositivo pareado: {}", req.device_name);
            self.devices.lock().unwrap().add(conn.remote_id(), req.device_name)?;
        } else {
            eprintln!("orcd: pareamento recusado (token inválido ou expirado)");
        }
        let message = if ok { "pareado" } else { "token inválido ou expirado" };
        write_line(&mut send, &PairResponse { ok, message: message.into() }).await?;
        let _ = send.finish();
        conn.closed().await;
        Ok(())
    }

    async fn main(&self, conn: &Connection, daemon: Daemon) -> std::io::Result<()> {
        let name = self
            .devices
            .lock()
            .unwrap()
            .list()
            .get(&conn.remote_id().to_string())
            .map(|d| d.name.clone());
        let Some(name) = name else {
            eprintln!("orcd: conexão recusada de chave não pareada {}", conn.remote_id().fmt_short());
            conn.close(403u32.into(), b"dispositivo nao pareado");
            return Ok(());
        };
        eprintln!("orcd: {name} conectado");
        let me = conn.remote_id().to_string();
        self.connected.lock().unwrap().insert(me.clone(), conn.clone());
        let (mut send, recv) = conn.accept_bi().await.map_err(std::io::Error::other)?;
        let mut events = daemon.events.subscribe();
        for m in daemon.hello() {
            write_line(&mut send, &m).await?;
        }
        let (tx, mut rx) = tokio::sync::mpsc::channel::<DaemonMessage>(256);
        let (remote, me_reader) = (self.clone(), me.clone());

        // Requests from the client; replies go to this client only.
        let reader = tokio::spawn(async move {
            let mut lines = BufReader::new(recv).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if let Ok(msg) = serde_json::from_str::<ClientMessage>(&line) {
                    // Tool calls act as a session: only orc-mcp, locally.
                    let replies = match msg {
                        ClientMessage::McpCall { .. } => {
                            vec![DaemonMessage::Error { message: "McpCall só pelo socket local".into() }]
                        }
                        // A paired device may bring another one (it already
                        // controls everything; the ticket works once, 10 min).
                        ClientMessage::NewPairingTicket => {
                            vec![DaemonMessage::PairingTicket { ticket: remote.new_ticket().await.encode() }]
                        }
                        // The asking device knows which one it is.
                        ClientMessage::ListDevices => {
                            vec![DaemonMessage::Devices { devices: remote.device_list(Some(&me_reader)) }]
                        }
                        other => daemon.handle(other),
                    };
                    for reply in replies {
                        if tx.send(reply).await.is_err() {
                            return;
                        }
                    }
                }
            }
        });

        loop {
            let msg = tokio::select! {
                reply = rx.recv() => match reply { Some(m) => m, None => break },
                event = events.recv() => match event {
                    Ok(m) => m,
                    // Too slow: it missed diffs, so it must ask for snapshots.
                    Err(RecvError::Lagged(_)) => DaemonMessage::Error { message: "lagged".into() },
                    Err(RecvError::Closed) => break,
                },
            };
            if write_line(&mut send, &msg).await.is_err() {
                break;
            }
        }
        reader.abort();
        self.connected.lock().unwrap().remove(&me);
        Ok(())
    }
}
