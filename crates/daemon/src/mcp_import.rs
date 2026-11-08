//! MCP servers you already set up in Claude Code, brought into the catalog:
//! from each account's `.claude.json` (user and per-project servers) and
//! the `.mcp.json` of the repositories the harness knows. Secret values
//! written in them move to the Keychain and the config keeps `${NAME}`
//! references; values never reach a client.

use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::secrets::valid_env_name;

/// A server found in a Claude Code config file.
#[derive(Debug, Clone, PartialEq)]
pub struct Found {
    /// Unique across a scan: where it came from plus its name.
    pub key: String,
    /// Where it was found, for people.
    pub label: String,
    pub name: String,
    pub config: Value,
}

fn servers(map: Option<&Value>) -> Vec<(String, Value)> {
    map.and_then(Value::as_object)
        .map(|m| m.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
        .unwrap_or_default()
}

/// Reads the servers in `.claude.json` files (labelled by account) and
/// `.mcp.json` files (labelled by repository). Missing or broken files are
/// skipped.
pub fn scan(claude_jsons: &[(String, PathBuf)], mcp_jsons: &[(String, PathBuf)]) -> Vec<Found> {
    let read = |p: &Path| std::fs::read(p).ok().and_then(|raw| serde_json::from_slice::<Value>(&raw).ok());
    let mut out = Vec::new();
    for (account, file) in claude_jsons {
        let Some(doc) = read(file) else { continue };
        for (name, config) in servers(doc.get("mcpServers")) {
            out.push(Found {
                key: format!("{}#user#{name}", file.display()),
                label: format!("{account} · Claude Code"),
                name,
                config,
            });
        }
        let projects = doc.get("projects").and_then(Value::as_object).cloned().unwrap_or_default();
        for (dir, project) in projects {
            for (name, config) in servers(project.get("mcpServers")) {
                let folder = Path::new(&dir).file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or(dir.clone());
                out.push(Found {
                    key: format!("{}#{dir}#{name}", file.display()),
                    label: format!("{account} · {folder}"),
                    name,
                    config,
                });
            }
        }
    }
    for (repo, file) in mcp_jsons {
        let Some(doc) = read(file) else { continue };
        for (name, config) in servers(doc.get("mcpServers")) {
            out.push(Found {
                key: format!("{}#mcp.json#{name}", file.display()),
                label: format!("{repo} · .mcp.json"),
                name,
                config,
            });
        }
    }
    out.retain(|f| f.config.get("command").is_some() || f.config.get("url").is_some());
    out
}

/// An env name from free text: `my-server` + `Authorization` →
/// `MY_SERVER_AUTHORIZATION`.
fn env_name(parts: &[&str]) -> String {
    let raw: String = parts
        .join("_")
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { '_' })
        .collect();
    if raw.starts_with(|c: char| c.is_ascii_digit()) { format!("_{raw}") } else { raw }
}

/// The config with literal env and header values replaced by `${NAME}`
/// references, and the (NAME, value) pairs that go to the Keychain.
pub fn sanitize(name: &str, config: &Value) -> (Value, Vec<(String, String)>) {
    let mut config = config.clone();
    let mut secrets = Vec::new();
    for key in ["env", "headers"] {
        let Some(map) = config.get_mut(key).and_then(Value::as_object_mut) else { continue };
        for (k, v) in map.iter_mut() {
            let Some(text) = v.as_str() else { continue };
            if text.contains("${") {
                continue;
            }
            let env = if key == "env" && valid_env_name(k) { k.clone() } else { env_name(&[name, k]) };
            secrets.push((env.clone(), text.to_string()));
            *v = Value::String(format!("${{{env}}}"));
        }
    }
    (config, secrets)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn finds_user_project_and_repo_servers() {
        let dir = tempfile::tempdir().unwrap();
        let claude = dir.path().join(".claude.json");
        std::fs::write(
            &claude,
            json!({
                "mcpServers": { "railway": { "command": "npx", "args": ["railway-mcp"] } },
                "projects": { "/r/app": { "mcpServers": { "db": { "type": "http", "url": "https://db/mcp" } } },
                              "/r/x": {} },
                "other": 1
            })
            .to_string(),
        )
        .unwrap();
        let mcp = dir.path().join(".mcp.json");
        std::fs::write(&mcp, json!({ "mcpServers": { "lint": { "command": "lint-mcp" }, "broken": {} } }).to_string()).unwrap();
        let found = scan(&[("default".into(), claude), ("gone".into(), dir.path().join("nope.json"))], &[("app".into(), mcp)]);
        let names: Vec<(&str, &str)> = found.iter().map(|f| (f.name.as_str(), f.label.as_str())).collect();
        assert_eq!(names, [("railway", "default · Claude Code"), ("db", "default · app"), ("lint", "app · .mcp.json")]);
        let keys: std::collections::HashSet<_> = found.iter().map(|f| &f.key).collect();
        assert_eq!(keys.len(), 3);
    }

    #[test]
    fn secrets_move_out_of_the_config() {
        let config = json!({
            "command": "npx",
            "env": { "API_KEY": "sk-1", "MODE": "${MODE}" },
        });
        let (clean, secrets) = sanitize("x", &config);
        assert_eq!(clean["env"]["API_KEY"], "${API_KEY}");
        assert_eq!(clean["env"]["MODE"], "${MODE}");
        assert_eq!(secrets, [("API_KEY".to_string(), "sk-1".to_string())]);

        let http = json!({ "type": "http", "url": "https://u", "headers": { "Authorization": "Bearer t" } });
        let (clean, secrets) = sanitize("my-db", &http);
        assert_eq!(clean["headers"]["Authorization"], "${MY_DB_AUTHORIZATION}");
        assert_eq!(secrets, [("MY_DB_AUTHORIZATION".to_string(), "Bearer t".to_string())]);
    }
}
