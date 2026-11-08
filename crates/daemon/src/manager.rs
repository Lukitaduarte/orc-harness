//! Starts Claude Code sessions the way the harness needs them.
//!
//! Each session gets a runtime folder with generated files, and a command
//! line built only from documented Claude Code flags:
//!
//! - `--settings` → statusLine (`orc-statusline`) and hooks (`orc-hook`);
//! - `--mcp-config` + `--strict-mcp-config` → only the profile's MCPs;
//! - `--plugin-dir` → a plugin whose skills are the profile's skills;
//! - `--session-id` the first time, `--resume` the same id after a profile
//!   change, so the conversation survives the restart;
//! - `CLAUDE_CONFIG_DIR` → the account.

use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};

use orc_protocol::{Profile, SessionState, SessionSummary};
use serde_json::json;

use crate::secrets::{SecretStore, valid_env_name};
use crate::session::{Session, SessionSpec};

/// Env name → its owners (`Some(workspace)`, or None for every workspace).
pub type EnvOwners = HashMap<String, Vec<Option<String>>>;

#[derive(Debug, Clone)]
pub struct Account {
    pub id: String,
    /// `None` uses Claude Code's default config folder.
    pub config_dir: Option<PathBuf>,
    /// The GitHub CLI login for this account (`GH_CONFIG_DIR`); `None`
    /// uses gh's default.
    pub gh_config_dir: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub struct ManagerConfig {
    /// The `claude` executable (a fake one in tests).
    pub claude: String,
    pub statusline: PathBuf,
    pub hook: PathBuf,
    /// Where runtime folders go: `<root>/<session id>/`.
    pub runtime_root: PathBuf,
    /// The daemon's local socket, passed to the helpers.
    pub socket: PathBuf,
    /// Where sessions send OpenTelemetry metrics (the daemon's local OTLP
    /// endpoint); `None` turns telemetry off.
    pub otlp_metrics: Option<String>,
    /// The harness MCP server (`orc-mcp`), added to every session.
    pub orc_mcp: Option<PathBuf>,
}

struct Managed {
    summary: SessionSummary,
    profile: Profile,
    cols: u16,
    rows: u16,
    session: Session,
}

/// What `sessions.json` keeps of a session to bring it back after the
/// daemon restarts.
#[derive(serde::Serialize, serde::Deserialize)]
struct SavedState {
    /// Ids are never reused, even across restarts.
    next: u32,
    sessions: Vec<Saved>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Saved {
    summary: SessionSummary,
    profile: Profile,
    cols: u16,
    rows: u16,
}

/// Claude Code keeps a conversation as `<config>/projects/<folder>/<id>.jsonl`;
/// one that never got a message has no file and cannot be resumed.
fn has_transcript(account: &Account, claude_session_id: &str) -> bool {
    let config = account.config_dir.clone().unwrap_or_else(|| {
        PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".claude")
    });
    let file = format!("{claude_session_id}.jsonl");
    fs::read_dir(config.join("projects"))
        .into_iter()
        .flatten()
        .flatten()
        .any(|d| d.path().join(&file).exists())
}

pub struct SessionManager {
    cfg: ManagerConfig,
    pub secrets: std::sync::Arc<SecretStore>,
    accounts: HashMap<String, Account>,
    /// MCP servers every session of an account gets (its workspace's
    /// memory provider), set by the daemon.
    extra_mcp: HashMap<String, BTreeMap<String, serde_json::Value>>,
    /// (account → workspace, env name → owners), see `set_env_scope`.
    env_scope: (HashMap<String, String>, EnvOwners),
    sessions: BTreeMap<String, Managed>,
    next: u32,
}

/// Hook events Claude Code sends that move the session state.
const HOOK_EVENTS: [&str; 5] = [
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "Notification",
    "Stop",
];

impl SessionManager {
    pub fn new(cfg: ManagerConfig, accounts: Vec<Account>, secrets: std::sync::Arc<SecretStore>) -> Self {
        Self {
            cfg,
            secrets,
            accounts: accounts.into_iter().map(|a| (a.id.clone(), a)).collect(),
            extra_mcp: HashMap::new(),
            env_scope: Default::default(),
            sessions: BTreeMap::new(),
            next: 0,
        }
    }

    /// Servers added to new and restarted sessions of each account.
    pub fn set_extra_mcp(&mut self, extra: HashMap<String, BTreeMap<String, serde_json::Value>>) {
        self.extra_mcp = extra;
    }

    /// Which workspace each account is in, and who has each env (see
    /// catalog::env_secret_key): a session gets its workspace's values and
    /// cannot start with another workspace's env.
    pub fn set_env_scope(&mut self, accounts: HashMap<String, String>, owners: EnvOwners) {
        self.env_scope = (accounts, owners);
    }

    /// Ends the account's sessions and forgets it.
    pub fn remove_account(&mut self, id: &str) {
        let ids: Vec<String> = self.sessions.values().filter(|m| m.summary.account_id == id).map(|m| m.summary.id.clone()).collect();
        for s in ids {
            self.stop(&s);
        }
        self.accounts.remove(id);
        self.extra_mcp.remove(id);
    }

    pub fn add_account(&mut self, account: Account) {
        self.accounts.insert(account.id.clone(), account);
    }

    /// The `claude` program sessions run.
    pub fn claude(&self) -> &str {
        &self.cfg.claude
    }

    pub fn account(&self, id: &str) -> Option<&Account> {
        self.accounts.get(id)
    }

    pub fn summary(&self, id: &str) -> Option<SessionSummary> {
        self.sessions.get(id).map(|m| m.summary.clone())
    }

    pub fn account_ids(&self) -> Vec<String> {
        let mut ids: Vec<_> = self.accounts.keys().cloned().collect();
        ids.sort();
        ids
    }

    pub fn create(
        &mut self,
        account_id: &str,
        cwd: Option<PathBuf>,
        profile: Profile,
        cols: u16,
        rows: u16,
    ) -> std::io::Result<SessionSummary> {
        self.create_in(account_id, cwd, None, profile, cols, rows)
    }

    /// Like `create`, for a session in a project worktree on `branch`.
    pub fn create_in(
        &mut self,
        account_id: &str,
        cwd: Option<PathBuf>,
        project: Option<(String, String)>,
        profile: Profile,
        cols: u16,
        rows: u16,
    ) -> std::io::Result<SessionSummary> {
        self.create_with_prompt(account_id, cwd, project, profile, None, cols, rows)
    }

    /// A session that starts working on `prompt` right away (delegation,
    /// cards).
    #[allow(clippy::too_many_arguments)]
    pub fn create_with_prompt(
        &mut self,
        account_id: &str,
        cwd: Option<PathBuf>,
        project: Option<(String, String)>,
        profile: Profile,
        prompt: Option<String>,
        cols: u16,
        rows: u16,
    ) -> std::io::Result<SessionSummary> {
        let account = self
            .accounts
            .get(account_id)
            .cloned()
            .ok_or_else(|| std::io::Error::other(format!("conta desconhecida: {account_id}")))?;
        self.next += 1;
        let id = format!("s{}", self.next);
        let cwd = match cwd {
            Some(dir) => dir,
            // Not the daemon's own folder: under launchd that is `/`.
            None => std::env::var_os("HOME").map(PathBuf::from).map_or_else(std::env::current_dir, Ok)?,
        };
        let summary = SessionSummary {
            id: id.clone(),
            account_id: account.id.clone(),
            cwd: cwd.to_string_lossy().into_owned(),
            state: SessionState::Starting,
            model: profile.model.clone(),
            claude_session_id: uuid::Uuid::new_v4().to_string(),
            project_id: project.as_ref().map(|p| p.0.clone()),
            branch: project.map(|p| p.1),
            profile: None,
        };
        let mut spec = self.prepare(&summary, &account, &profile, cols, rows, false)?;
        if let Some(p) = prompt {
            // Claude Code's interactive mode takes an initial prompt.
            spec.args.push(p);
        }
        let session = Session::spawn(&spec)?;
        self.sessions.insert(
            id.clone(),
            Managed { summary: summary.clone(), profile, cols, rows, session },
        );
        self.save();
        Ok(summary)
    }

    fn state_file(&self) -> PathBuf {
        self.cfg.runtime_root.join("sessions.json")
    }

    /// Writes the sessions still running to `sessions.json` (owner only).
    pub fn save(&self) {
        let saved: Vec<Saved> = self
            .sessions
            .values()
            .filter(|m| m.session.exited().is_none())
            .map(|m| Saved { summary: m.summary.clone(), profile: m.profile.clone(), cols: m.cols, rows: m.rows })
            .collect();
        let write = || -> std::io::Result<()> {
            fs::create_dir_all(&self.cfg.runtime_root)?;
            let file = self.state_file();
            let state = SavedState { next: self.next, sessions: saved };
            fs::write(&file, serde_json::to_vec_pretty(&state)?)?;
            fs::set_permissions(&file, std::os::unix::fs::PermissionsExt::from_mode(0o600))
        };
        if let Err(e) = write() {
            eprintln!("orcd: não salvei as sessões: {e}");
        }
    }

    /// Brings back the sessions of the last run, same ids: conversations
    /// that exist are resumed, the others start fresh with the same id.
    /// Returns how many came back.
    pub fn restore(&mut self) -> usize {
        let Ok(raw) = fs::read(self.state_file()) else { return 0 };
        let Ok(state) = serde_json::from_slice::<SavedState>(&raw) else { return 0 };
        self.next = self.next.max(state.next);
        let mut n = 0;
        for s in state.sessions {
            let Some(account) = self.accounts.get(&s.summary.account_id).cloned() else { continue };
            if self.sessions.contains_key(&s.summary.id) || !std::path::Path::new(&s.summary.cwd).is_dir() {
                continue;
            }
            let mut summary = s.summary;
            summary.state = SessionState::Starting;
            let resume = has_transcript(&account, &summary.claude_session_id);
            let spawned = self
                .prepare(&summary, &account, &s.profile, s.cols, s.rows, resume)
                .and_then(|spec| Session::spawn(&spec));
            match spawned {
                Ok(session) => {
                    self.sessions.insert(
                        summary.id.clone(),
                        Managed { summary, profile: s.profile, cols: s.cols, rows: s.rows, session },
                    );
                    n += 1;
                }
                Err(e) => eprintln!("orcd: não retomei {}: {e}", summary.id),
            }
        }
        self.save();
        n
    }

    /// Restarts the session with a new profile, resuming the conversation.
    pub fn apply_profile(&mut self, id: &str, profile: Profile) -> std::io::Result<SessionSummary> {
        let m = self
            .sessions
            .get(id)
            .ok_or_else(|| std::io::Error::other(format!("sessão desconhecida: {id}")))?;
        let account = self.accounts[&m.summary.account_id].clone();
        let mut summary = m.summary.clone();
        summary.state = SessionState::Starting;
        summary.model = profile.model.clone();
        let spec = self.prepare(&summary, &account, &profile, m.cols, m.rows, true)?;
        let m = self.sessions.get_mut(id).unwrap();
        m.session.kill();
        m.session = Session::spawn(&spec)?;
        m.summary = summary.clone();
        m.profile = profile;
        self.save();
        Ok(summary)
    }

    /// Ends a session and deletes its generated folder (settings, MCP
    /// config, skills links). The conversation stays in Claude Code and the
    /// worktree in git.
    pub fn stop(&mut self, id: &str) -> bool {
        let removed = self.sessions.remove(id).is_some();
        if removed {
            let _ = fs::remove_dir_all(self.runtime_dir(id));
        }
        self.save();
        removed
    }

    pub fn session(&self, id: &str) -> Option<&Session> {
        self.sessions.get(id).map(|m| &m.session)
    }

    pub fn profile(&self, id: &str) -> Option<&Profile> {
        self.sessions.get(id).map(|m| &m.profile)
    }

    pub fn list(&self) -> Vec<SessionSummary> {
        self.sessions
            .values()
            .map(|m| {
                let mut s = m.summary.clone();
                s.profile = Some(m.profile.clone());
                if m.session.exited().is_some() {
                    s.state = SessionState::Exited;
                }
                s
            })
            .collect()
    }

    /// Moves the state from a hook event. Returns the new state if it changed.
    pub fn on_hook(&mut self, id: &str, event: &str) -> Option<SessionState> {
        let m = self.sessions.get_mut(id)?;
        let next = match event {
            "SessionStart" => SessionState::Idle,
            "UserPromptSubmit" | "PreToolUse" => SessionState::Running,
            "Notification" => SessionState::WaitingInput,
            "Stop" => SessionState::Idle,
            _ => return None,
        };
        (m.summary.state != next).then(|| {
            m.summary.state = next;
            next
        })
    }

    /// A starting session showing Claude Code's folder trust question waits
    /// for you (hooks only run after it is answered).
    pub fn on_trust_question(&mut self, id: &str) -> Option<SessionState> {
        let m = self.sessions.get_mut(id)?;
        (m.summary.state == SessionState::Starting).then(|| {
            m.summary.state = SessionState::WaitingInput;
            SessionState::WaitingInput
        })
    }

    pub fn runtime_dir(&self, id: &str) -> PathBuf {
        self.cfg.runtime_root.join(id)
    }

    /// Writes the runtime folder and returns the command to run.
    fn prepare(
        &self,
        s: &SessionSummary,
        account: &Account,
        profile: &Profile,
        cols: u16,
        rows: u16,
        resume: bool,
    ) -> std::io::Result<SessionSpec> {
        let dir = self.runtime_dir(&s.id);
        // A profile change rebuilds the folder from scratch: a removed skill
        // or MCP must not linger.
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir)?;
        restrict(&dir)?;

        let hook = |event: &str| {
            json!([{
                "matcher": if event == "PreToolUse" { json!("*") } else { json!("") },
                // PreToolUse may wait for your OK on a deploy (gates).
                "hooks": [if event == "PreToolUse" {
                    json!({ "type": "command", "command": format!("{} {event}", self.cfg.hook.display()), "timeout": 660 })
                } else {
                    json!({ "type": "command", "command": format!("{} {event}", self.cfg.hook.display()) })
                }]
            }])
        };
        let mut settings = json!({
            "statusLine": { "type": "command", "command": self.cfg.statusline.display().to_string() },
            "hooks": HOOK_EVENTS.iter().map(|e| (e.to_string(), hook(e))).collect::<serde_json::Map<_, _>>(),
        });
        let mut servers = profile.mcp_servers.clone();
        for (name, config) in self.extra_mcp.get(&account.id).into_iter().flatten() {
            servers.entry(name.clone()).or_insert_with(|| config.clone());
        }
        // Per-session endpoints (the browser's CDP proxy) name the session.
        let mut servers: BTreeMap<String, serde_json::Value> =
            serde_json::from_str(&serde_json::to_string(&servers)?.replace("{ORC_SESSION}", &s.id))?;
        if let Some(orc) = &self.cfg.orc_mcp {
            // The harness tools; the session id ties every call to it.
            servers.insert(
                "orc".into(),
                json!({
                    "command": orc.display().to_string(),
                    "args": [],
                    "env": { "ORC_SOCKET": self.cfg.socket.display().to_string(), "ORC_SESSION": s.id },
                }),
            );
        }
        write_json(&dir.join("mcp.json"), &json!({ "mcpServers": servers }))?;
        // Strict mode keeps the account's other MCP servers out, and its
        // claude.ai connectors too; with connectors, an allowlist does it.
        let strict = profile.connectors.is_empty();
        if !strict {
            settings["allowedMcpServers"] = crate::connectors::allowlist(&servers, &profile.connectors);
        }
        write_json(&dir.join("settings.json"), &settings)?;

        // Skills go in through a local plugin made of links to the catalog.
        let plugin = dir.join("plugin");
        fs::create_dir_all(plugin.join(".claude-plugin"))?;
        fs::create_dir_all(plugin.join("skills"))?;
        write_json(
            &plugin.join(".claude-plugin").join("plugin.json"),
            &json!({ "name": format!("orc-{}", s.id), "version": "0.1.0", "description": "Skills do perfil da sessão" }),
        )?;
        for skill in &profile.skills {
            let expanded = crate::catalog::expand(skill);
            let src = expanded.as_path();
            if let Some(name) = src.file_name() {
                std::os::unix::fs::symlink(src, plugin.join("skills").join(name))?;
            }
        }

        let mut args = vec![
            "--settings".to_string(),
            dir.join("settings.json").display().to_string(),
            "--mcp-config".into(),
            dir.join("mcp.json").display().to_string(),
            "--plugin-dir".into(),
            plugin.display().to_string(),
        ];
        if strict {
            args.push("--strict-mcp-config".into());
        }
        if resume {
            args.extend(["--resume".into(), s.claude_session_id.clone()]);
        } else {
            args.extend(["--session-id".into(), s.claude_session_id.clone()]);
        }
        if let Some(model) = &profile.model {
            args.extend(["--model".into(), model.clone()]);
        }

        let mut env: HashMap<String, String> = HashMap::new();
        for name in &profile.env_names {
            if !valid_env_name(name) {
                return Err(std::io::Error::other(format!("nome de env inválido: {name}")));
            }
            let owners = self.env_scope.1.get(name).cloned().unwrap_or_default();
            let workspace = self.env_scope.0.get(&account.id).map(String::as_str);
            let key = crate::catalog::env_secret_key(&owners, workspace, name).map_err(std::io::Error::other)?;
            let value = self.secrets.get(&key).ok_or_else(|| {
                std::io::Error::other(format!("{name} não tem valor no Keychain do daemon"))
            })?;
            env.insert(name.clone(), value);
        }
        env.insert("ORC_SOCKET".into(), self.cfg.socket.display().to_string());
        env.insert("ORC_ACCOUNT".into(), account.id.clone());
        env.insert("ORC_SESSION".into(), s.id.clone());
        if let Some(endpoint) = &self.cfg.otlp_metrics {
            // Tokens and cost per session, from Claude Code's own metrics.
            for (k, v) in [
                ("CLAUDE_CODE_ENABLE_TELEMETRY", "1"),
                ("OTEL_METRICS_EXPORTER", "otlp"),
                ("OTEL_EXPORTER_OTLP_METRICS_PROTOCOL", "http/json"),
                ("OTEL_EXPORTER_OTLP_PROTOCOL", "http/json"),
                ("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", endpoint.as_str()),
                ("OTEL_METRIC_EXPORT_INTERVAL", "10000"),
                ("OTEL_LOGS_EXPORTER", "none"),
            ] {
                env.insert(k.into(), v.into());
            }
            // Project and branch (a plan's card) label the usage too.
            let mut attrs = format!("orc.session={},orc.account={}", s.id, account.id);
            if let (Some(project), Some(branch)) = (&s.project_id, &s.branch) {
                attrs.push_str(&format!(",orc.project={project},orc.branch={branch}"));
            }
            env.insert("OTEL_RESOURCE_ATTRIBUTES".into(), attrs);
        }
        let mut env_remove = Vec::new();
        match &account.config_dir {
            Some(cfg_dir) => {
                env.insert("CLAUDE_CONFIG_DIR".into(), cfg_dir.display().to_string());
            }
            // Claude Code's default folder: never the daemon's inherited one.
            None => env_remove.push("CLAUDE_CONFIG_DIR".into()),
        }
        match &account.gh_config_dir {
            Some(dir) => {
                env.insert("GH_CONFIG_DIR".into(), dir.display().to_string());
            }
            None => env_remove.push("GH_CONFIG_DIR".into()),
        }

        Ok(SessionSpec {
            program: self.cfg.claude.clone(),
            args,
            env,
            env_remove,
            cwd: Some(PathBuf::from(&s.cwd)),
            cols,
            rows,
        })
    }
}

fn write_json(path: &Path, value: &serde_json::Value) -> std::io::Result<()> {
    fs::write(path, serde_json::to_vec_pretty(value)?)
}

/// Runtime folders may hold env values: owner only.
fn restrict(dir: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(dir, fs::Permissions::from_mode(0o700))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    /// A stand-in for `claude` that prints its arguments and the variables
    /// the harness sets, then waits.
    fn fake_claude(dir: &Path) -> String {
        let path = dir.join("fake-claude");
        fs::write(
            &path,
            "#!/bin/sh\nfor a in \"$@\"; do echo \"arg:$a\"; done\necho \"env:$ORC_ACCOUNT:$ORC_SESSION:$CLAUDE_CONFIG_DIR:$GREETING\"\necho \"otel:$CLAUDE_CODE_ENABLE_TELEMETRY:$OTEL_RESOURCE_ATTRIBUTES\"\necho READY\nexec cat\n",
        )
        .unwrap();
        fs::set_permissions(&path, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        path.display().to_string()
    }

    fn manager(dir: &Path) -> SessionManager {
        let secrets = SecretStore::memory();
        secrets.set("env/GREETING", "oi").unwrap();
        SessionManager::new(
            ManagerConfig {
                claude: fake_claude(dir),
                statusline: "/opt/orc/orc-statusline".into(),
                hook: "/opt/orc/orc-hook".into(),
                runtime_root: dir.join("sessions"),
                socket: dir.join("orcd.sock"),
                otlp_metrics: Some("http://127.0.0.1:4318/v1/metrics".into()),
                orc_mcp: Some("/opt/orc/orc-mcp".into()),
            },
            vec![
                Account { id: "work-main".into(), config_dir: Some("/cfg/work".into()), gh_config_dir: None },
                Account { id: "personal".into(), config_dir: None, gh_config_dir: None },
            ],
            std::sync::Arc::new(secrets),
        )
    }

    fn screen(m: &SessionManager, id: &str) -> Vec<String> {
        let snap = m
            .session(id)
            .unwrap()
            .wait_for(Duration::from_secs(5), |g| (0..g.rows as usize).any(|r| g.line_text(r) == "READY"));
        (0..snap.rows as usize).map(|r| snap.line_text(r)).filter(|l| !l.is_empty()).collect()
    }

    fn profile() -> Profile {
        let mut p = Profile { model: Some("opus".into()), ..Profile::default() };
        p.skills.push("/catalog/skills/code-review".into());
        p.mcp_servers.insert("postgres".into(), json!({ "command": "npx", "args": ["pg-mcp"] }));
        p.env_names.push("GREETING".into());
        p
    }

    #[test]
    fn sessions_come_back_after_a_restart() {
        let tmp = tempfile::tempdir().unwrap();
        let cfg = tmp.path().join("cfg");
        let account = |id: &str| Account { id: id.into(), config_dir: Some(cfg.clone()), gh_config_dir: None };
        let make = || {
            SessionManager::new(
                ManagerConfig {
                    claude: fake_claude(tmp.path()),
                    statusline: "/opt/orc/orc-statusline".into(),
                    hook: "/opt/orc/orc-hook".into(),
                    runtime_root: tmp.path().join("sessions"),
                    socket: tmp.path().join("orcd.sock"),
                    otlp_metrics: None,
                    orc_mcp: None,
                },
                vec![account("work")],
                std::sync::Arc::new(SecretStore::memory()),
            )
        };
        let mut m = make();
        let talked = m.create("work", Some(tmp.path().into()), Profile { model: Some("opus".into()), ..Profile::default() }, 90, 30).unwrap();
        let silent = m.create("work", Some(tmp.path().into()), Profile::default(), 90, 30).unwrap();
        let ended = m.create("work", Some(tmp.path().into()), Profile::default(), 90, 30).unwrap();
        m.stop(&ended.id);
        // Claude Code wrote a transcript only for the first one.
        fs::create_dir_all(cfg.join("projects/-tmp-x")).unwrap();
        fs::write(cfg.join(format!("projects/-tmp-x/{}.jsonl", talked.claude_session_id)), "{}").unwrap();
        drop(m); // the daemon goes away

        let mut m = make();
        assert_eq!(m.restore(), 2);
        let ids: Vec<_> = m.list().into_iter().map(|s| s.id).collect();
        assert_eq!(ids, [talked.id.clone(), silent.id.clone()]);
        let resumed = screen(&m, &talked.id);
        assert!(resumed.contains(&"arg:--resume".to_string()), "{resumed:?}");
        assert!(resumed.contains(&format!("arg:{}", talked.claude_session_id)));
        assert!(resumed.contains(&"arg:opus".to_string()), "profile kept");
        let fresh = screen(&m, &silent.id);
        assert!(fresh.contains(&"arg:--session-id".to_string()), "{fresh:?}");
        // New sessions do not reuse ids.
        let next = m.create("work", Some(tmp.path().into()), Profile::default(), 90, 30).unwrap();
        assert_eq!(next.id, "s4");
        let mode = std::os::unix::fs::PermissionsExt::mode(&fs::metadata(tmp.path().join("sessions/sessions.json")).unwrap().permissions());
        assert_eq!(mode & 0o777, 0o600);
    }

    #[test]
    fn starts_claude_with_generated_files_and_the_account() {
        let tmp = tempfile::tempdir().unwrap();
        let mut m = manager(tmp.path());
        let s = m.create("work-main", Some(tmp.path().into()), profile(), 120, 40).unwrap();
        let lines = screen(&m, &s.id);
        let dir = m.runtime_dir(&s.id);

        for expected in [
            format!("arg:{}", dir.join("settings.json").display()),
            "arg:--strict-mcp-config".into(),
            format!("arg:{}", s.claude_session_id),
            "arg:opus".into(),
            format!("env:work-main:{}:/cfg/work:oi", s.id),
            format!("otel:1:orc.session={},orc.account=work-main", s.id),
        ] {
            assert!(lines.contains(&expected), "missing {expected} in {lines:?}");
        }
        assert!(lines.contains(&"arg:--session-id".to_string()));
        assert!(!lines.contains(&"arg:--resume".to_string()));

        let settings: serde_json::Value =
            serde_json::from_slice(&fs::read(dir.join("settings.json")).unwrap()).unwrap();
        assert_eq!(settings["statusLine"]["command"], "/opt/orc/orc-statusline");
        assert_eq!(settings["hooks"]["Stop"][0]["hooks"][0]["command"], "/opt/orc/orc-hook Stop");
        let mcp: serde_json::Value =
            serde_json::from_slice(&fs::read(dir.join("mcp.json")).unwrap()).unwrap();
        assert_eq!(mcp["mcpServers"]["postgres"]["command"], "npx");
        assert_eq!(mcp["mcpServers"]["orc"]["command"], "/opt/orc/orc-mcp");
        assert_eq!(mcp["mcpServers"]["orc"]["env"]["ORC_SESSION"], s.id.as_str());
        let link = dir.join("plugin/skills/code-review");
        assert_eq!(fs::read_link(link).unwrap(), Path::new("/catalog/skills/code-review"));
    }

    #[test]
    fn connectors_swap_strict_mode_for_an_allowlist() {
        let tmp = tempfile::tempdir().unwrap();
        let mut m = manager(tmp.path());
        let mut p = profile();
        p.connectors = vec!["https://mcp.slack.com/mcp".into()];
        let s = m.create("work-main", Some(tmp.path().into()), p, 120, 40).unwrap();
        let lines = screen(&m, &s.id);
        assert!(!lines.contains(&"arg:--strict-mcp-config".to_string()), "{lines:?}");
        let settings: serde_json::Value =
            serde_json::from_slice(&fs::read(m.runtime_dir(&s.id).join("settings.json")).unwrap()).unwrap();
        let allowed = settings["allowedMcpServers"].as_array().unwrap();
        for entry in [
            serde_json::json!({ "serverName": "orc" }),
            serde_json::json!({ "serverName": "postgres" }),
            serde_json::json!({ "serverUrl": "https://mcp.slack.com/mcp" }),
        ] {
            assert!(allowed.contains(&entry), "{entry} not in {allowed:?}");
        }
        // Without connectors, strict as before and no allowlist.
        let plain = m.create("work-main", Some(tmp.path().into()), profile(), 120, 40).unwrap();
        let settings: serde_json::Value =
            serde_json::from_slice(&fs::read(m.runtime_dir(&plain.id).join("settings.json")).unwrap()).unwrap();
        assert!(settings.get("allowedMcpServers").is_none());
    }

    #[test]
    fn applying_a_profile_resumes_the_same_conversation() {
        let tmp = tempfile::tempdir().unwrap();
        let mut m = manager(tmp.path());
        let s = m.create("personal", Some(tmp.path().into()), profile(), 120, 40).unwrap();
        screen(&m, &s.id);

        let lean = Profile { model: Some("sonnet".into()), ..Profile::default() };
        m.apply_profile(&s.id, lean).unwrap();
        let lines = screen(&m, &s.id);
        assert!(lines.contains(&"arg:--resume".to_string()));
        assert!(lines.contains(&format!("arg:{}", s.claude_session_id)));
        assert!(lines.contains(&"arg:sonnet".to_string()));
        // No account config dir: Claude Code's default is used.
        assert!(lines.contains(&format!("env:personal:{}::", s.id)));
        // The removed skill and MCP are gone from the runtime folder.
        let dir = m.runtime_dir(&s.id);
        assert!(!dir.join("plugin/skills/code-review").exists());
        let mcp: serde_json::Value =
            serde_json::from_slice(&fs::read(dir.join("mcp.json")).unwrap()).unwrap();
        // Only the harness MCP remains.
        assert_eq!(mcp["mcpServers"].as_object().unwrap().keys().collect::<Vec<_>>(), ["orc"]);
    }

    #[test]
    fn hooks_drive_the_state_and_unknown_accounts_fail() {
        let tmp = tempfile::tempdir().unwrap();
        let mut m = manager(tmp.path());
        let s = m.create("work-main", Some(tmp.path().into()), Profile::default(), 80, 24).unwrap();
        assert_eq!(m.on_hook(&s.id, "UserPromptSubmit"), Some(SessionState::Running));
        assert_eq!(m.on_hook(&s.id, "PreToolUse"), None); // already running
        assert_eq!(m.on_hook(&s.id, "Notification"), Some(SessionState::WaitingInput));
        assert_eq!(m.on_hook(&s.id, "Stop"), Some(SessionState::Idle));
        assert_eq!(m.on_hook(&s.id, "Unknown"), None);
        assert!(m.create("nope", None, Profile::default(), 80, 24).is_err());
    }

    #[test]
    fn env_values_come_from_the_store_and_missing_ones_fail() {
        let tmp = tempfile::tempdir().unwrap();
        let mut m = manager(tmp.path());
        let missing = Profile { env_names: vec!["NOT_SET".into()], ..Profile::default() };
        let err = m.create("work-main", Some(tmp.path().into()), missing, 80, 24).unwrap_err();
        assert!(err.to_string().contains("NOT_SET"));
        let bad = Profile { env_names: vec!["A=B".into()], ..Profile::default() };
        assert!(m.create("work-main", Some(tmp.path().into()), bad, 80, 24).is_err());
    }
}
