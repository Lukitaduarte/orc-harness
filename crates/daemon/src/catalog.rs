//! The global catalog (`~/.orc/catalog.json`) and plan mode templates
//! (`~/.orc/templates/*.md`): configured once, enabled per session.
//! Env entries hold names only; values live in the Keychain.

use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

use orc_protocol::{CatalogEntry, PlanTemplateFile};
use serde_json::{Value, json};

use crate::secrets::{SecretStore, env_key, env_key_in, valid_env_name};

/// Templates installed on first run; afterwards the files are the user's.
const DEFAULT_TEMPLATES: [(&str, &str); 4] = [
    ("back", include_str!("../templates/back.md")),
    ("app", include_str!("../templates/app.md")),
    ("spike", include_str!("../templates/spike.md")),
    ("blank", include_str!("../templates/blank.md")),
];

pub struct Catalog {
    file: PathBuf,
    templates_dir: PathBuf,
    entries: Vec<CatalogEntry>,
}

impl Catalog {
    pub fn load(home: &Path) -> std::io::Result<Self> {
        let file = home.join("catalog.json");
        let entries = match std::fs::read(&file) {
            Ok(raw) => serde_json::from_slice(&raw)?,
            Err(_) => Vec::new(),
        };
        let templates_dir = home.join("templates");
        if !templates_dir.exists() {
            std::fs::create_dir_all(&templates_dir)?;
            for (id, md) in DEFAULT_TEMPLATES {
                std::fs::write(templates_dir.join(format!("{id}.md")), md)?;
            }
        }
        Ok(Self { file, templates_dir, entries })
    }

    /// Entries with `has_value` filled in for envs.
    pub fn entries(&self, secrets: &SecretStore) -> Vec<CatalogEntry> {
        self.entries
            .iter()
            .cloned()
            .map(|mut e| {
                if e.kind == "env" {
                    e.has_value = secrets.get(&env_key_in(e.workspace.as_deref(), &e.name)).is_some();
                }
                e
            })
            .collect()
    }

    /// The entries as stored.
    pub fn list(&self) -> Vec<CatalogEntry> {
        self.entries.clone()
    }

    pub fn get(&self, id: &str) -> Option<&CatalogEntry> {
        self.entries.iter().find(|e| e.id == id)
    }

    pub fn upsert(&mut self, mut entry: CatalogEntry) -> std::io::Result<()> {
        match entry.kind.as_str() {
            "skill" => {
                let path = entry.path.as_deref().map(expand).unwrap_or_default();
                if !path.join("SKILL.md").exists() {
                    return Err(std::io::Error::other(format!(
                        "skill sem SKILL.md em {}",
                        path.display()
                    )));
                }
                entry.path = Some(path.display().to_string());
            }
            "mcp" => {
                let ok = entry.mcp.as_ref().is_some_and(|m| m.get("command").is_some() || m.get("url").is_some());
                if !ok {
                    return Err(std::io::Error::other("MCP precisa de command ou url"));
                }
            }
            "env" => {
                if !valid_env_name(&entry.name) {
                    return Err(std::io::Error::other(format!("nome de env inválido: {}", entry.name)));
                }
                if entry.workspace.as_deref().is_some_and(|w| w.is_empty() || w.contains('/')) {
                    return Err(std::io::Error::other("workspace inválido"));
                }
                // Never persisted here, whatever a client sends.
                entry.path = None;
                entry.mcp = None;
            }
            other => return Err(std::io::Error::other(format!("tipo desconhecido: {other}"))),
        }
        entry.has_value = false;
        match self.entries.iter_mut().find(|e| e.id == entry.id) {
            Some(e) => *e = entry,
            None => self.entries.push(entry),
        }
        self.save()
    }

    /// Who has an env: `Some(workspace)` for its own value, None for every
    /// workspace. Empty when the catalog does not list it.
    pub fn env_owners(&self, name: &str) -> Vec<Option<String>> {
        self.entries.iter().filter(|e| e.kind == "env" && e.name == name).map(|e| e.workspace.clone()).collect()
    }

    /// Lists an env for a workspace (or for every one) if it is not there
    /// yet.
    pub fn ensure_env(&mut self, name: &str, workspace: Option<&str>, description: &str) -> std::io::Result<()> {
        if self.env_owners(name).iter().any(|w| w.as_deref() == workspace) {
            return Ok(());
        }
        self.upsert(CatalogEntry {
            id: match workspace {
                Some(w) => format!("env-{w}-{name}"),
                None => format!("env-{name}"),
            },
            kind: "env".into(),
            name: name.into(),
            description: description.into(),
            path: None,
            mcp: None,
            has_value: false,
            workspace: workspace.map(String::from),
        })
    }

    pub fn remove(&mut self, id: &str) -> std::io::Result<()> {
        self.entries.retain(|e| e.id != id);
        self.save()
    }

    fn save(&self) -> std::io::Result<()> {
        std::fs::write(&self.file, serde_json::to_vec_pretty(&self.entries)?)
    }

    pub fn templates(&self) -> Vec<PlanTemplateFile> {
        let mut out: Vec<_> = std::fs::read_dir(&self.templates_dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|f| {
                let path = f.path();
                (path.extension()? == "md").then_some(())?;
                Some(PlanTemplateFile {
                    id: path.file_stem()?.to_string_lossy().into_owned(),
                    markdown: std::fs::read_to_string(&path).ok()?,
                })
            })
            .collect();
        out.sort_by(|a, b| a.id.cmp(&b.id));
        out
    }

    pub fn upsert_template(&self, t: &PlanTemplateFile) -> std::io::Result<()> {
        std::fs::write(self.template_path(&t.id)?, &t.markdown)
    }

    pub fn remove_template(&self, id: &str) -> std::io::Result<()> {
        std::fs::remove_file(self.template_path(id)?)
    }

    /// Template ids are file names: no paths, no dots.
    fn template_path(&self, id: &str) -> std::io::Result<PathBuf> {
        let ok = !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
        if !ok {
            return Err(std::io::Error::other(format!("id de template inválido: {id}")));
        }
        Ok(self.templates_dir.join(format!("{id}.md")))
    }
}

pub fn expand(p: &str) -> PathBuf {
    match p.strip_prefix("~/") {
        Some(rest) => PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(rest),
        None => PathBuf::from(p),
    }
}

/// Starts a stdio MCP server, initializes it and counts its tools. HTTP
/// servers are not tested yet.
pub fn test_mcp(config: &Value, env: &[(String, String)], timeout: Duration) -> Result<usize, String> {
    let Some(command) = config.get("command").and_then(Value::as_str) else {
        return Err("teste de MCP por HTTP ainda não é suportado".into());
    };
    let args: Vec<String> = config
        .get("args")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let mut cmd = Command::new(command);
    cmd.args(&args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null());
    if let Some(vars) = config.get("env").and_then(Value::as_object) {
        for (k, v) in vars {
            cmd.env(k, v.as_str().unwrap_or_default());
        }
    }
    for (k, v) in env {
        cmd.env(k, v);
    }
    let mut child = cmd.spawn().map_err(|e| format!("não iniciou {command}: {e}"))?;
    let mut stdin = child.stdin.take().ok_or("sem stdin")?;
    let stdout = child.stdout.take().ok_or("sem stdout")?;

    // Responses are read on a thread so a silent server can time out.
    let (tx, rx) = mpsc::channel::<Value>();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if let Ok(v) = serde_json::from_str::<Value>(&line)
                && tx.send(v).is_err()
            {
                break;
            }
        }
    });
    let mut send = |v: Value| -> Result<(), String> {
        writeln!(stdin, "{v}").map_err(|e| e.to_string())?;
        stdin.flush().map_err(|e| e.to_string())
    };
    let wait = |id: u64| -> Result<Value, String> {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            let left = deadline.saturating_duration_since(std::time::Instant::now());
            let v = rx.recv_timeout(left).map_err(|_| "o MCP não respondeu a tempo".to_string())?;
            if v.get("id").and_then(Value::as_u64) == Some(id) {
                if let Some(err) = v.get("error") {
                    return Err(format!("erro do MCP: {err}"));
                }
                return Ok(v);
            }
        }
    };

    let result = (|| {
        send(json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": { "name": "orc-harness", "version": "0.1.0" } } }))?;
        wait(1)?;
        send(json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }))?;
        send(json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }))?;
        let list = wait(2)?;
        Ok(list["result"]["tools"].as_array().map(Vec::len).unwrap_or(0))
    })();
    let _ = child.kill();
    let _ = child.wait();
    result
}

/// The Keychain entry a session of `workspace` reads for an env: its
/// workspace's own value, else the one for every workspace. An env only
/// other workspaces have is refused. `owners` empty (not in the catalog):
/// the shared one.
pub fn env_secret_key(owners: &[Option<String>], workspace: Option<&str>, name: &str) -> Result<String, String> {
    if owners.is_empty() {
        return Ok(env_key(name));
    }
    if let Some(w) = workspace
        && owners.iter().any(|o| o.as_deref() == Some(w))
    {
        return Ok(env_key_in(Some(w), name));
    }
    if owners.iter().any(Option::is_none) {
        return Ok(env_key(name));
    }
    Err(format!("{name} é de outro workspace; esta sessão não pode usá-la"))
}

/// Env values for an MCP from the Keychain, by the names it declares in
/// `env_names` (values are never stored in the catalog).
pub fn mcp_env(config: &Value, secrets: &SecretStore) -> Vec<(String, String)> {
    config
        .get("env_names")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|n| n.as_str())
        .filter_map(|n| secrets.get(&env_key(n)).map(|v| (n.to_string(), v)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_workspace_env_beats_the_shared_one_and_stays_home() {
        let shared_and_casa = [None, Some("casa".to_string())];
        assert_eq!(env_secret_key(&shared_and_casa, Some("casa"), "T").unwrap(), "env/@casa/T");
        assert_eq!(env_secret_key(&shared_and_casa, Some("trabalho"), "T").unwrap(), "env/T");
        assert!(env_secret_key(&[Some("casa".to_string())], Some("trabalho"), "T").is_err());
        assert!(env_secret_key(&[Some("casa".to_string())], None, "T").is_err());
        assert_eq!(env_secret_key(&[], Some("x"), "T").unwrap(), "env/T", "not in the catalog: the shared one");
    }

    fn entry(kind: &str, name: &str) -> CatalogEntry {
        CatalogEntry {
            id: name.into(),
            kind: kind.into(),
            name: name.into(),
            description: String::new(),
            path: None,
            mcp: None,
            has_value: false,
            workspace: None,
        }
    }

    #[test]
    fn persists_entries_and_installs_default_templates() {
        let home = tempfile::tempdir().unwrap();
        let skill = home.path().join("skills/review");
        std::fs::create_dir_all(&skill).unwrap();
        std::fs::write(skill.join("SKILL.md"), "x").unwrap();

        let mut c = Catalog::load(home.path()).unwrap();
        assert_eq!(c.templates().iter().map(|t| t.id.as_str()).collect::<Vec<_>>(), ["app", "back", "blank", "spike"]);
        c.upsert(CatalogEntry { path: Some(skill.display().to_string()), ..entry("skill", "review") }).unwrap();
        c.upsert(CatalogEntry { mcp: Some(json!({ "command": "npx", "args": ["x"] })), ..entry("mcp", "pg") }).unwrap();
        // An env never keeps anything but its name, whatever is sent.
        c.upsert(CatalogEntry { path: Some("/leak".into()), ..entry("env", "TOKEN") }).unwrap();

        let again = Catalog::load(home.path()).unwrap();
        let secrets = SecretStore::memory();
        let entries = again.entries(&secrets);
        assert_eq!(entries.len(), 3);
        assert_eq!(entries[2].path, None);
        assert!(!entries[2].has_value);
        secrets.set("env/TOKEN", "v").unwrap();
        assert!(again.entries(&secrets)[2].has_value);
    }

    #[test]
    fn refuses_bad_entries_and_template_ids() {
        let home = tempfile::tempdir().unwrap();
        let mut c = Catalog::load(home.path()).unwrap();
        assert!(c.upsert(CatalogEntry { path: Some("/nope".into()), ..entry("skill", "s") }).is_err());
        assert!(c.upsert(entry("mcp", "m")).is_err());
        assert!(c.upsert(entry("env", "A B")).is_err());
        let evil = PlanTemplateFile { id: "../evil".into(), markdown: String::new() };
        assert!(c.upsert_template(&evil).is_err());
    }

    #[test]
    fn tests_a_stdio_mcp() {
        // A tiny MCP server in sh: answers initialize, then lists 2 tools.
        let home = tempfile::tempdir().unwrap();
        let server = home.path().join("mcp.sh");
        std::fs::write(
            &server,
            r#"#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'"initialize"'*) echo '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"t","version":"1"}}}' ;;
    *'"tools/list"'*) echo '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"a"},{"name":"b"}]}}' ;;
  esac
done
"#,
        )
        .unwrap();
        std::fs::set_permissions(&server, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        let tools = test_mcp(&json!({ "command": server }), &[], Duration::from_secs(5)).unwrap();
        assert_eq!(tools, 2);

        // Reads nothing and says nothing.
        let silent = test_mcp(&json!({ "command": "sleep", "args": ["5"] }), &[], Duration::from_millis(300));
        assert!(silent.unwrap_err().contains("não respondeu"));
        assert!(test_mcp(&json!({ "url": "https://x" }), &[], Duration::from_secs(1)).is_err());
    }
}
