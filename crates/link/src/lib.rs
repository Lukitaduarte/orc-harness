//! What the daemon and its clients share to talk over iroh: protocol names,
//! the pairing ticket, device keys, the endpoint setup and line framing.
//!
//! Security model (from the plan):
//! - every connection is end-to-end encrypted QUIC (TLS 1.3, Ed25519 keys);
//! - the daemon accepts the main protocol only from paired device keys;
//! - pairing needs a one-time, short-lived token, shown only to the owner;
//! - no public relay or address publishing by default, so nothing about
//!   who talks to whom goes to third parties. Clients reach the daemon by
//!   the direct addresses in the ticket (same machine, LAN or a VPN).

use std::path::Path;

use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, RelayMode, SecretKey};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncWrite, AsyncWriteExt};

/// Pairing: the client presents the ticket's token and its name.
pub const ALPN_PAIR: &[u8] = b"orc/pair/1";
/// Everything else: newline-delimited JSON messages, both ways.
pub const ALPN_MAIN: &[u8] = b"orc/1";

const TICKET_PREFIX: &str = "orc1";

/// Shown by the daemon to pair a new device.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Ticket {
    pub addr: EndpointAddr,
    pub token: String,
}

impl Ticket {
    /// `orc1` + hex of the JSON: copyable, no padding or URL issues.
    pub fn encode(&self) -> String {
        let json = serde_json::to_vec(self).expect("ticket serializes");
        let mut out = String::with_capacity(TICKET_PREFIX.len() + json.len() * 2);
        out.push_str(TICKET_PREFIX);
        for b in json {
            out.push_str(&format!("{b:02x}"));
        }
        out
    }

    pub fn decode(s: &str) -> Result<Self, String> {
        let hex = s
            .trim()
            .strip_prefix(TICKET_PREFIX)
            .ok_or("ticket não começa com orc1")?;
        if hex.len() % 2 != 0 {
            return Err("ticket incompleto".into());
        }
        let bytes = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| "ticket com caracteres inválidos")?;
        serde_json::from_slice(&bytes).map_err(|e| format!("ticket inválido: {e}"))
    }
}

/// First line a client sends on the pairing protocol.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairRequest {
    pub token: String,
    pub device_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairResponse {
    pub ok: bool,
    pub message: String,
}

/// Loads a device key, creating it (owner-only file) the first time.
pub fn load_or_create_key(path: &Path) -> std::io::Result<SecretKey> {
    if let Ok(hex) = std::fs::read_to_string(path) {
        return key_from_hex(hex.trim()).map_err(std::io::Error::other);
    }
    let key = SecretKey::generate();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, key_to_hex(&key))?;
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(key)
}

pub fn key_to_hex(key: &SecretKey) -> String {
    key.to_bytes().iter().map(|b| format!("{b:02x}")).collect()
}

pub fn key_from_hex(hex: &str) -> Result<SecretKey, String> {
    if hex.len() != 64 {
        return Err("chave deve ter 32 bytes em hex".into());
    }
    let mut bytes = [0u8; 32];
    for (i, b) in bytes.iter_mut().enumerate() {
        *b = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).map_err(|e| e.to_string())?;
    }
    Ok(SecretKey::from_bytes(&bytes))
}

/// Which relay the daemon uses to be reachable outside its network. The
/// relay only forwards end-to-end encrypted packets; with none, apps reach
/// the daemon on the same network only.
#[derive(Debug, Clone, PartialEq)]
pub enum Relay {
    Off,
    /// n0's public relays.
    N0,
    /// Your own (iroh-relay), e.g. `https://relay.example.com`.
    Url(iroh::RelayUrl),
}

impl Relay {
    /// From config.json's `relay`: missing or "off", "n0", or a URL.
    pub fn parse(s: Option<&str>) -> Result<Self, String> {
        match s.map(str::trim) {
            None | Some("") | Some("off") => Ok(Self::Off),
            Some("n0") => Ok(Self::N0),
            Some(url) => url.parse().map(Self::Url).map_err(|e| format!("relay inválido {url}: {e}")),
        }
    }

    fn mode(&self) -> RelayMode {
        match self {
            Self::Off => RelayMode::Disabled,
            Self::N0 => RelayMode::Default,
            Self::Url(url) => RelayMode::Custom(iroh::RelayMap::from(url.clone())),
        }
    }
}

/// A client's relay: the ones in the daemon's address (none: disabled).
pub fn relay_for(daemon: &EndpointAddr) -> RelayMode {
    let urls: Vec<iroh::RelayUrl> = daemon
        .addrs
        .iter()
        .filter_map(|a| match a {
            iroh::TransportAddr::Relay(url) => Some(url.clone()),
            _ => None,
        })
        .collect();
    if urls.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(urls.into_iter().collect()) }
}

/// A client endpoint, no address publishing (see module docs); `relay` from
/// [`relay_for`].
pub async fn endpoint(key: SecretKey, alpns: &[&[u8]], relay: RelayMode) -> std::io::Result<Endpoint> {
    Endpoint::builder(presets::Minimal)
        .secret_key(key)
        .relay_mode(relay)
        .alpns(alpns.iter().map(|a| a.to_vec()).collect())
        .bind()
        .await
        .map_err(std::io::Error::other)
}

/// The daemon's endpoint, on a fixed UDP `port` (0 picks one) on every
/// interface. Paired apps keep the daemon's addresses from the ticket and
/// there is no relay, so the port must survive restarts.
pub async fn endpoint_on(key: SecretKey, alpns: &[&[u8]], port: u16, relay: &Relay) -> std::io::Result<Endpoint> {
    use iroh::endpoint::BindOpts;
    Endpoint::builder(presets::Minimal)
        .secret_key(key)
        .relay_mode(relay.mode())
        .alpns(alpns.iter().map(|a| a.to_vec()).collect())
        .clear_ip_transports()
        .bind_addr(std::net::SocketAddr::from(([0, 0, 0, 0], port)))
        .map_err(std::io::Error::other)?
        .bind_addr_with_opts(
            std::net::SocketAddr::from((std::net::Ipv6Addr::UNSPECIFIED, port)),
            BindOpts::default().set_is_required(false),
        )
        .map_err(std::io::Error::other)?
        .bind()
        .await
        .map_err(std::io::Error::other)
}

/// The UDP port an endpoint got (IPv4).
pub fn bound_port(endpoint: &Endpoint) -> Option<u16> {
    endpoint.bound_sockets().iter().find(|a| a.is_ipv4()).map(|a| a.port())
}

/// Writes one message as a JSON line.
pub async fn write_line<W, T>(w: &mut W, msg: &T) -> std::io::Result<()>
where
    W: AsyncWrite + Unpin,
    T: Serialize,
{
    let mut line = serde_json::to_vec(msg)?;
    line.push(b'\n');
    w.write_all(&line).await?;
    w.flush().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ticket_round_trips_and_rejects_garbage() {
        let key = SecretKey::generate();
        let t = Ticket {
            addr: EndpointAddr::new(key.public()),
            token: "abc".into(),
        };
        let s = t.encode();
        assert!(s.starts_with("orc1"));
        assert_eq!(Ticket::decode(&s).unwrap(), t);
        assert!(Ticket::decode("xyz").is_err());
        assert!(Ticket::decode("orc1zz").is_err());
    }

    #[test]
    fn keys_persist_owner_only() {
        let dir = std::env::temp_dir().join(format!("orc-link-{}", std::process::id()));
        let path = dir.join("device.key");
        let _ = std::fs::remove_file(&path);
        let a = load_or_create_key(&path).unwrap();
        let b = load_or_create_key(&path).unwrap();
        assert_eq!(a.public(), b.public());
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[tokio::test]
    async fn the_daemon_binds_the_port_it_is_given() {
        let free = std::net::UdpSocket::bind("0.0.0.0:0").unwrap().local_addr().unwrap().port();
        let key = SecretKey::generate();
        let e = endpoint_on(key, &[], free, &Relay::Off).await.unwrap();
        assert_eq!(bound_port(&e), Some(free));
        e.close().await;
    }

    #[test]
    fn relay_from_config_and_from_the_daemon_address() {
        assert_eq!(Relay::parse(None).unwrap(), Relay::Off);
        assert_eq!(Relay::parse(Some("off")).unwrap(), Relay::Off);
        assert_eq!(Relay::parse(Some("n0")).unwrap(), Relay::N0);
        assert!(matches!(Relay::parse(Some("https://relay.example.com")).unwrap(), Relay::Url(_)));
        assert!(Relay::parse(Some("not a url")).is_err());

        let id = SecretKey::generate().public();
        let direct = EndpointAddr::new(id).with_ip_addr("127.0.0.1:1".parse().unwrap());
        assert!(matches!(relay_for(&direct), RelayMode::Disabled));
        let via = direct.with_relay_url("https://relay.example.com".parse().unwrap());
        assert!(matches!(relay_for(&via), RelayMode::Custom(_)));
    }
}
