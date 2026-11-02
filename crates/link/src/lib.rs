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

/// An endpoint with no relay and no address publishing (see module docs).
pub async fn endpoint(key: SecretKey, alpns: &[&[u8]]) -> std::io::Result<Endpoint> {
    Endpoint::builder(presets::Minimal)
        .secret_key(key)
        .relay_mode(RelayMode::Disabled)
        .alpns(alpns.iter().map(|a| a.to_vec()).collect())
        .bind()
        .await
        .map_err(std::io::Error::other)
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
}
