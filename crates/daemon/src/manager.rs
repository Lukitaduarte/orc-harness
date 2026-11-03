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

use crate::secrets::{SecretStore, env_key, valid_env_name};
use crate::session::{Session, SessionSpec};

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

pub struct SessionManager {
    cfg: ManagerConfig,
    pub secrets: std::sync::Arc<SecretStore>,
    accounts: HashMap<String, Account>,
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
            sessions: BTreeMap::new(),
            next: 0,
        }
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
            None => std::env::current_dir()?,
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
        Ok(summary)
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
        Ok(summary)
    }

    pub fn stop(&mut self, id: &str) -> bool {
        self.sessions.remove(id).is_some()
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
                "hooks": [{ "type": "command", "command": format!("{} {event}", self.cfg.hook.display()) }]
            }])
        };
        let settings = json!({
            "statusLine": { "type": "command", "command": self.cfg.statusline.display().to_string() },
            "hooks": HOOK_EVENTS.iter().map(|e| (e.to_string(), hook(e))).collect::<serde_json::Map<_, _>>(),
        });
        write_json(&dir.join("settings.json"), &settings)?;
        let mut servers = profile.mcp_servers.clone();
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
            "--strict-mcp-config".into(),
            "--plugin-dir".into(),
            plugin.display().to_string(),
        ];
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
            let value = self.secrets.get(&env_key(name)).ok_or_else(|| {
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
