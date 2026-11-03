//! `~/.orc/config.json`: the accounts and where `claude` is.
//!
//! ```json
//! { "claude": "claude",
//!   "accounts": [ { "id": "trabalho", "config_dir": "~/.claude-trabalho",
//!                   "gh_config_dir": "~/.config/gh-trabalho" },
//!                 { "id": "pessoal" } ] }
//! ```
//! An account without `config_dir` uses Claude Code's default folder.
//! Missing file: one account, `default`.

use std::path::{Path, PathBuf};

use crate::manager::Account;

pub struct Config {
    pub claude: String,
    pub accounts: Vec<Account>,
    /// `relay`: "off" (default: same network only), "n0" (public relays) or
    /// the URL of your own iroh-relay. Traffic stays end-to-end encrypted.
    pub relay: Option<String>,
}

/// `~/.orc`, or `ORC_HOME` (tests and side-by-side daemons). Never change
/// `HOME` for that: the Keychain and Claude Code's login live under it.
pub fn orc_home() -> PathBuf {
    if let Some(dir) = std::env::var_os("ORC_HOME") {
        return PathBuf::from(dir);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".orc")
}

fn expand(path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(rest),
        None => PathBuf::from(path),
    }
}

/// Adds account `id` to `config.json` with its own Claude Code and gh
/// folders under `home/accounts/<id>` (owner only). A missing file keeps
/// the implicit `default` account.
pub fn add_account(path: &Path, home: &Path, id: &str) -> std::io::Result<Account> {
    if !crate::workspaces::valid_id(id) {
        return Err(std::io::Error::other("id de conta: letras, números, - _"));
    }
    let mut v: serde_json::Value = match std::fs::read(path) {
        Ok(raw) => serde_json::from_slice(&raw)?,
        Err(_) => serde_json::json!({ "accounts": [{ "id": "default" }] }),
    };
    if !v["accounts"].is_array() {
        v["accounts"] = serde_json::json!([{ "id": "default" }]);
    }
    let list = v["accounts"].as_array_mut().expect("array");
    if list.iter().any(|a| a["id"] == id) {
        return Err(std::io::Error::other(format!("a conta {id} já existe")));
    }
    let dir = home.join("accounts").join(id);
    let gh = dir.join("gh");
    std::fs::create_dir_all(&gh)?;
    std::fs::set_permissions(&dir, std::os::unix::fs::PermissionsExt::from_mode(0o700))?;
    list.push(serde_json::json!({
        "id": id,
        "config_dir": dir.display().to_string(),
        "gh_config_dir": gh.display().to_string(),
    }));
    std::fs::write(path, serde_json::to_vec_pretty(&v)?)?;
    Ok(Account { id: id.into(), config_dir: Some(dir), gh_config_dir: Some(gh) })
}

/// Takes account `id` out of `config.json` (a missing file had only the
/// implicit `default`).
pub fn remove_account(path: &Path, id: &str) -> std::io::Result<()> {
    let mut v: serde_json::Value = match std::fs::read(path) {
        Ok(raw) => serde_json::from_slice(&raw)?,
        Err(_) => serde_json::json!({ "accounts": [{ "id": "default" }] }),
    };
    let list = v["accounts"].as_array_mut().ok_or_else(|| std::io::Error::other("config.json sem contas"))?;
    let before = list.len();
    list.retain(|a| a["id"] != id);
    if list.len() == before {
        return Err(std::io::Error::other(format!("conta desconhecida: {id}")));
    }
    if list.is_empty() {
        return Err(std::io::Error::other("a última conta fica"));
    }
    std::fs::write(path, serde_json::to_vec_pretty(&v)?)
}

pub fn load(path: &Path) -> std::io::Result<Config> {
    let default = || Config {
        claude: "claude".into(),
        accounts: vec![Account { id: "default".into(), config_dir: None, gh_config_dir: None }],
        relay: None,
    };
    let Ok(raw) = std::fs::read(path) else {
        return Ok(default());
    };
    let v: serde_json::Value = serde_json::from_slice(&raw)?;
    let accounts: Vec<Account> = v["accounts"]
        .as_array()
        .map(|list| {
            list.iter()
                .filter_map(|a| {
                    Some(Account {
                        id: a["id"].as_str()?.to_string(),
                        config_dir: a["config_dir"].as_str().map(expand),
                        gh_config_dir: a["gh_config_dir"].as_str().map(expand),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    let mut cfg = default();
    if let Some(c) = v["claude"].as_str() {
        cfg.claude = c.into();
    }
    cfg.relay = v["relay"].as_str().map(String::from);
    if !accounts.is_empty() {
        cfg.accounts = accounts;
    }
    Ok(cfg)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_accounts_and_defaults() {
        let dir = tempfile::tempdir().unwrap();
        let missing = load(&dir.path().join("none.json")).unwrap();
        assert_eq!(missing.accounts[0].id, "default");

        let file = dir.path().join("config.json");
        std::fs::write(
            &file,
            r#"{"accounts":[{"id":"trabalho","config_dir":"~/.claude-trabalho"},{"id":"pessoal"}]}"#,
        )
        .unwrap();
        let cfg = load(&file).unwrap();
        assert_eq!(cfg.claude, "claude");
        assert_eq!(cfg.accounts.len(), 2);
        assert!(cfg.accounts[0].config_dir.as_ref().unwrap().ends_with(".claude-trabalho"));
        assert!(cfg.accounts[1].config_dir.is_none());
    }
}
