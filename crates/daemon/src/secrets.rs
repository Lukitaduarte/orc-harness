//! Secrets live in the macOS Keychain, never in files, the catalog, plans,
//! logs or the app. The daemon reads them only to start a process: env
//! values go into the session's environment, the device key into iroh.
//!
//! Names: `env/<NAME>` for envs, `daemon-key` for the iroh key.

use std::collections::HashMap;
use std::sync::Mutex;

pub enum SecretStore {
    /// The login Keychain, items under one service name.
    #[cfg(target_os = "macos")]
    Keychain { service: String },
    /// For tests; nothing leaves the process.
    Memory(Mutex<HashMap<String, String>>),
}

impl SecretStore {
    #[cfg(target_os = "macos")]
    pub fn keychain() -> Self {
        Self::Keychain { service: "orc-harness".into() }
    }

    pub fn memory() -> Self {
        Self::Memory(Mutex::default())
    }

    pub fn get(&self, name: &str) -> Option<String> {
        match self {
            #[cfg(target_os = "macos")]
            Self::Keychain { service } => {
                security_framework::passwords::get_generic_password(service, name)
                    .ok()
                    .and_then(|b| String::from_utf8(b).ok())
            }
            Self::Memory(m) => m.lock().unwrap().get(name).cloned(),
        }
    }

    pub fn set(&self, name: &str, value: &str) -> std::io::Result<()> {
        match self {
            #[cfg(target_os = "macos")]
            Self::Keychain { service } => {
                security_framework::passwords::set_generic_password(service, name, value.as_bytes())
                    .map_err(std::io::Error::other)
            }
            Self::Memory(m) => {
                m.lock().unwrap().insert(name.into(), value.into());
                Ok(())
            }
        }
    }

    pub fn delete(&self, name: &str) -> std::io::Result<()> {
        match self {
            #[cfg(target_os = "macos")]
            Self::Keychain { service } => {
                match security_framework::passwords::delete_generic_password(service, name) {
                    Ok(()) => Ok(()),
                    // Deleting what is not there is fine.
                    Err(e) if e.code() == -25300 => Ok(()),
                    Err(e) => Err(std::io::Error::other(e)),
                }
            }
            Self::Memory(m) => {
                m.lock().unwrap().remove(name);
                Ok(())
            }
        }
    }
}

pub fn env_key(name: &str) -> String {
    format!("env/{name}")
}

/// Env names must be shell-safe identifiers; anything else is refused
/// before it reaches the Keychain or a process environment.
pub fn valid_env_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with(|c: char| c.is_ascii_digit())
        && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// The daemon's iroh key, from the Keychain. A key left in the old file
/// (`legacy`) is moved in and the file deleted.
pub fn daemon_key(store: &SecretStore, legacy: &std::path::Path) -> std::io::Result<iroh::SecretKey> {
    if let Some(hex) = store.get("daemon-key") {
        return orc_link::key_from_hex(&hex).map_err(std::io::Error::other);
    }
    let key = match std::fs::read_to_string(legacy) {
        Ok(hex) => orc_link::key_from_hex(hex.trim()).map_err(std::io::Error::other)?,
        Err(_) => iroh::SecretKey::generate(),
    };
    store.set("daemon-key", &orc_link::key_to_hex(&key))?;
    // Only after the Keychain has it.
    let _ = std::fs::remove_file(legacy);
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn env_names_are_identifiers() {
        assert!(valid_env_name("STAGING_DB_URL"));
        assert!(!valid_env_name("1ABC"));
        assert!(!valid_env_name("A B"));
        assert!(!valid_env_name("A=B"));
        assert!(!valid_env_name(""));
    }

    #[test]
    fn daemon_key_moves_from_the_file_into_the_store() {
        let dir = tempfile::tempdir().unwrap();
        let legacy = dir.path().join("daemon.key");
        let old = iroh::SecretKey::generate();
        std::fs::write(&legacy, orc_link::key_to_hex(&old)).unwrap();

        let store = SecretStore::memory();
        let key = daemon_key(&store, &legacy).unwrap();
        assert_eq!(key.public(), old.public());
        assert!(!legacy.exists(), "the file must be gone once migrated");
        // Next start reads it from the store.
        assert_eq!(daemon_key(&store, &legacy).unwrap().public(), old.public());
    }

    /// Touches the real login Keychain: `cargo test -p orc-daemon -- --ignored keychain`
    #[cfg(target_os = "macos")]
    #[test]
    #[ignore]
    fn keychain_round_trip() {
        let store = SecretStore::Keychain { service: "orc-harness-test".into() };
        store.set("env/ORC_TEST", "s3cret").unwrap();
        assert_eq!(store.get("env/ORC_TEST").as_deref(), Some("s3cret"));
        store.delete("env/ORC_TEST").unwrap();
        assert_eq!(store.get("env/ORC_TEST"), None);
        store.delete("env/ORC_TEST").unwrap();
    }
}
