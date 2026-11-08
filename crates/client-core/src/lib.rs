//! The app's side of the link: pair with a daemon once, then connect and
//! exchange protocol messages as JSON strings. Exposed to Dart through
//! flutter_rust_bridge, so the API sticks to strings and callbacks.

use iroh::{EndpointAddr, SecretKey};
use orc_link::{ALPN_FRAMED, ALPN_MAIN, ALPN_PAIR, PairRequest, PairResponse, Ticket, key_from_hex, key_to_hex, write_line};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;

/// What the app keeps (in the platform's secure storage) after pairing:
/// its own device key and the daemon's address.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Identity {
    pub device_key: String,
    pub daemon: EndpointAddr,
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Pairs this device with the daemon that issued `ticket`. Returns the
/// identity JSON to store.
pub async fn pair(ticket: &str, device_name: &str) -> Result<String, String> {
    let ticket = Ticket::decode(ticket)?;
    let key = SecretKey::generate();
    let endpoint = orc_link::endpoint(key.clone(), &[], orc_link::relay_for(&ticket.addr)).await.map_err(err)?;
    let conn = endpoint.connect(ticket.addr.clone(), ALPN_PAIR).await.map_err(err)?;
    let (mut send, recv) = conn.open_bi().await.map_err(err)?;
    write_line(
        &mut send,
        &PairRequest { token: ticket.token, device_name: device_name.into() },
    )
    .await
    .map_err(err)?;
    let line = BufReader::new(recv)
        .lines()
        .next_line()
        .await
        .map_err(err)?
        .ok_or("o daemon fechou a conexão")?;
    let response: PairResponse = serde_json::from_str(&line).map_err(err)?;
    conn.close(0u32.into(), b"ok");
    endpoint.close().await;
    if !response.ok {
        return Err(response.message);
    }
    serde_json::to_string(&Identity { device_key: key_to_hex(&key), daemon: ticket.addr })
        .map_err(err)
}

/// An open connection; drop it to disconnect.
pub struct Connection {
    tx: mpsc::Sender<String>,
    _task: tokio::task::JoinHandle<()>,
}

impl Connection {
    /// Sends one client message (JSON of `orc_protocol::ClientMessage`).
    pub async fn send(&self, json: String) -> Result<(), String> {
        self.tx.send(json).await.map_err(|_| "conexão encerrada".to_string())
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        self._task.abort();
    }
}

/// Connects with a stored identity. Every daemon message arrives as JSON in
/// `on_message`; `on_closed` runs once when the link drops (with the
/// reason), so the app can show it and reconnect.
pub async fn connect(
    identity_json: &str,
    on_message: impl Fn(String) + Send + 'static,
    on_closed: impl FnOnce(String) + Send + 'static,
) -> Result<Connection, String> {
    connect_with(
        identity_json,
        false,
        move |_, payload| on_message(String::from_utf8_lossy(&payload).into_owned()),
        on_closed,
    )
    .await
}

/// Like [`connect`], with grids in binary (ALPN orc/2): each message comes
/// as (kind, payload), `orc_protocol::wire::FRAME_JSON` with JSON or
/// `FRAME_GRID` with a binary grid. A daemon that predates it gets the
/// JSON link instead, every message then a JSON frame.
pub async fn connect_framed(
    identity_json: &str,
    on_frame: impl Fn(u8, Vec<u8>) + Send + 'static,
    on_closed: impl FnOnce(String) + Send + 'static,
) -> Result<Connection, String> {
    connect_with(identity_json, true, on_frame, on_closed).await
}

async fn connect_with(
    identity_json: &str,
    framed: bool,
    on_frame: impl Fn(u8, Vec<u8>) + Send + 'static,
    on_closed: impl FnOnce(String) + Send + 'static,
) -> Result<Connection, String> {
    let identity: Identity = serde_json::from_str(identity_json).map_err(err)?;
    let key = key_from_hex(&identity.device_key)?;
    let endpoint = orc_link::endpoint(key, &[], orc_link::relay_for(&identity.daemon)).await.map_err(err)?;
    let (conn, framed) = if framed {
        match endpoint.connect(identity.daemon.clone(), ALPN_FRAMED).await {
            Ok(c) => (c, true),
            // An older daemon: no orc/2.
            Err(_) => (endpoint.connect(identity.daemon, ALPN_MAIN).await.map_err(err)?, false),
        }
    } else {
        (endpoint.connect(identity.daemon, ALPN_MAIN).await.map_err(err)?, false)
    };
    let (mut send, recv) = conn.open_bi().await.map_err(err)?;
    // The daemon only accepts the stream once something is sent on it.
    write_line(&mut send, &serde_json::json!({ "type": "list_sessions" }))
        .await
        .map_err(err)?;
    let (tx, mut rx) = mpsc::channel::<String>(256);

    let task = tokio::spawn(async move {
        // Reading has its own task: a frame half read must not be dropped
        // when the app sends something.
        let (done_tx, mut done) = tokio::sync::oneshot::channel::<String>();
        let reader = tokio::spawn(async move {
            let mut recv = BufReader::new(recv);
            let reason = loop {
                let frame = if framed {
                    orc_link::read_frame(&mut recv).await
                } else {
                    let mut line = String::new();
                    match recv.read_line(&mut line).await {
                        Ok(0) => Ok(None),
                        Ok(_) => Ok(Some((0u8, line.trim_end_matches('\n').as_bytes().to_vec()))),
                        Err(e) => Err(e),
                    }
                };
                match frame {
                    Ok(Some((kind, payload))) => on_frame(kind, payload),
                    Ok(None) => break "o daemon encerrou a conexão".to_string(),
                    Err(e) => break e.to_string(),
                }
            };
            let _ = done_tx.send(reason);
        });
        let reason = loop {
            tokio::select! {
                r = &mut done => break r.unwrap_or_else(|_| "conexão encerrada".into()),
                out = rx.recv() => match out {
                    Some(json) => {
                        let mut bytes = json.into_bytes();
                        bytes.push(b'\n');
                        if let Err(e) = tokio::io::AsyncWriteExt::write_all(&mut send, &bytes).await {
                            break e.to_string();
                        }
                    }
                    None => break "conexão fechada pelo app".to_string(),
                },
            }
        };
        reader.abort();
        conn.close(0u32.into(), b"bye");
        endpoint.close().await;
        on_closed(reason);
    });
    Ok(Connection { tx, _task: task })
}
