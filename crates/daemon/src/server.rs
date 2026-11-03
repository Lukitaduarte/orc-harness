//! The daemon's state and the local socket the helper binaries talk to
//! (one JSON message per line). Remote clients (the app) reach the same
//! `Daemon::handle` through iroh.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use orc_protocol::{ClientMessage, DaemonMessage};
use orc_protocol::GridSnapshot;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;
use tokio::sync::broadcast;

use crate::catalog::{Catalog, mcp_env, test_mcp};
use crate::git;
use crate::manager::SessionManager;
use crate::projects::Projects;
use crate::quota::QuotaStore;
use crate::usage::{UsageStore, day_of, parse_otlp};
use crate::remote::Remote;

/// Where worktrees and the commit hook live, and the hook's checker.
#[derive(Clone, Debug)]
pub struct GitPaths {
    pub worktrees: PathBuf,
    pub hooks: PathBuf,
    pub commit_check: PathBuf,
}

#[derive(Clone)]
pub struct Daemon {
    pub quotas: Arc<Mutex<QuotaStore>>,
    pub sessions: Arc<Mutex<SessionManager>>,
    pub catalog: Arc<Mutex<Catalog>>,
    pub usage: Arc<Mutex<UsageStore>>,
    pub projects: Arc<Mutex<Projects>>,
    pub git: GitPaths,
    /// Everything clients should see; each connection subscribes.
    pub events: broadcast::Sender<DaemonMessage>,
    /// Set once iroh is up; mints pairing tickets for `orcd pair`.
    pub remote: Arc<OnceLock<Remote>>,
}

impl Daemon {
    pub fn new(
        sessions: SessionManager,
        catalog: Catalog,
        usage: UsageStore,
        projects: Projects,
        git: GitPaths,
    ) -> Self {
        Self {
            quotas: Arc::default(),
            sessions: Arc::new(Mutex::new(sessions)),
            catalog: Arc::new(Mutex::new(catalog)),
            usage: Arc::new(Mutex::new(usage)),
            projects: Arc::new(Mutex::new(projects)),
            git,
            events: broadcast::channel(1024).0,
            remote: Arc::default(),
        }
    }

    /// Sends each session's changed lines as they render, and the session
    /// list when one exits. Clients never get raw terminal bytes.
    pub async fn stream_grids(self) {
        let mut last: HashMap<String, (u64, GridSnapshot)> = HashMap::new();
        let mut exited: Vec<String> = Vec::new();
        let mut tick = tokio::time::interval(Duration::from_millis(33));
        loop {
            tick.tick().await;
            let mut out = Vec::new();
            {
                let sessions = self.sessions.lock().unwrap();
                let list = sessions.list();
                last.retain(|id, _| list.iter().any(|s| &s.id == id));
                for summary in &list {
                    let Some(s) = sessions.session(&summary.id) else { continue };
                    let generation = s.generation();
                    let entry = last.get(&summary.id);
                    if entry.is_some_and(|(g, _)| *g == generation) {
                        continue;
                    }
                    let snap = s.snapshot();
                    let diff = snap.diff_from(entry.map(|(_, p)| p).unwrap_or(&GridSnapshot::default()));
                    if !diff.lines.is_empty() || entry.is_none_or(|(_, p)| p.cursor != snap.cursor) {
                        out.push(DaemonMessage::GridDiff { session_id: summary.id.clone(), diff });
                    }
                    last.insert(summary.id.clone(), (generation, snap));
                }
                let now_exited: Vec<String> = list
                    .iter()
                    .filter(|s| s.state == orc_protocol::SessionState::Exited)
                    .map(|s| s.id.clone())
                    .collect();
                if now_exited != exited {
                    exited = now_exited;
                    out.push(DaemonMessage::Sessions { sessions: list });
                }
            }
            for m in out {
                let _ = self.events.send(m);
            }
        }
    }

    /// What a client gets on connect: accounts, sessions, known quotas.
    pub fn hello(&self) -> Vec<DaemonMessage> {
        // Takes the sessions lock itself: build it before holding that lock.
        let catalog = self.catalog_message();
        let sessions = self.sessions.lock().unwrap();
        let mut out = vec![
            DaemonMessage::Hello { accounts: sessions.account_ids() },
            DaemonMessage::Sessions { sessions: sessions.list() },
            catalog,
            DaemonMessage::Projects { projects: self.projects.lock().unwrap().list() },
        ];
        let usage = self.usage.lock().unwrap();
        for s in sessions.list() {
            out.push(DaemonMessage::SessionUsage { usage: usage.session(&s.id), session_id: s.id });
        }
        let quotas = self.quotas.lock().unwrap();
        for id in sessions.account_ids() {
            if let Some(q) = quotas.get(&id) {
                out.push(DaemonMessage::Quota {
                    account_id: id,
                    limits: q.limits.clone(),
                    read_at: q.read_at,
                });
            }
        }
        out
    }

    /// A project session's folder and its project's base branch.
    fn session_base(&self, session_id: &str) -> Option<(PathBuf, String)> {
        let s = self.sessions.lock().unwrap().summary(session_id)?;
        let base = self.projects.lock().unwrap().get(s.project_id.as_deref()?)?.base_branch.clone();
        Some((PathBuf::from(s.cwd), base))
    }

    fn catalog_message(&self) -> DaemonMessage {
        let secrets = self.sessions.lock().unwrap().secrets.clone();
        let catalog = self.catalog.lock().unwrap();
        DaemonMessage::Catalog { entries: catalog.entries(&secrets), templates: catalog.templates() }
    }

    /// Applies a message. Replies meant only for the sender come back;
    /// changes everyone should see go out on `events`.
    pub fn handle(&self, msg: ClientMessage) -> Vec<DaemonMessage> {
        let emit = |m: DaemonMessage| {
            let _ = self.events.send(m);
        };
        let error = |e: std::io::Error| vec![DaemonMessage::Error { message: e.to_string() }];
        match msg {
            ClientMessage::Status(report) => {
                let changed = self.quotas.lock().unwrap().ingest(&report).cloned();
                if let Some(q) = changed {
                    emit(DaemonMessage::Quota {
                        account_id: report.account_id,
                        limits: q.limits,
                        read_at: q.read_at,
                    });
                }
            }
            ClientMessage::Hook { session_id, event } => {
                let changed = self.sessions.lock().unwrap().on_hook(&session_id, &event);
                if let Some(state) = changed {
                    emit(DaemonMessage::SessionState { session_id, state });
                }
            }
            ClientMessage::CreateSession { account_id, cwd, profile, cols, rows } => {
                let mut sessions = self.sessions.lock().unwrap();
                if let Err(e) = sessions.create(&account_id, cwd.map(PathBuf::from), profile, cols, rows) {
                    return error(e);
                }
                emit(DaemonMessage::Sessions { sessions: sessions.list() });
            }
            ClientMessage::ApplyProfile { session_id, profile } => {
                let mut sessions = self.sessions.lock().unwrap();
                if let Err(e) = sessions.apply_profile(&session_id, profile) {
                    return error(e);
                }
                emit(DaemonMessage::Sessions { sessions: sessions.list() });
            }
            ClientMessage::StopSession { session_id } => {
                let mut sessions = self.sessions.lock().unwrap();
                sessions.stop(&session_id);
                emit(DaemonMessage::Sessions { sessions: sessions.list() });
            }
            // Only the local socket may mint tickets; see `serve`.
            ClientMessage::NewPairingTicket => {
                return vec![DaemonMessage::Error { message: "use orcd pair".into() }];
            }
            ClientMessage::SetSecret { name, value } => {
                if !crate::secrets::valid_env_name(&name) {
                    return vec![DaemonMessage::Error { message: format!("nome de env inválido: {name}") }];
                }
                let secrets = self.sessions.lock().unwrap().secrets.clone();
                if let Err(e) = secrets.set(&crate::secrets::env_key(&name), &value) {
                    return error(e);
                }
                emit(DaemonMessage::Secret { name, stored: true });
                emit(self.catalog_message());
            }
            ClientMessage::DeleteSecret { name } => {
                let secrets = self.sessions.lock().unwrap().secrets.clone();
                if let Err(e) = secrets.delete(&crate::secrets::env_key(&name)) {
                    return error(e);
                }
                emit(DaemonMessage::Secret { name, stored: false });
                emit(self.catalog_message());
            }
            ClientMessage::UpsertCatalog { entry } => {
                if let Err(e) = self.catalog.lock().unwrap().upsert(entry) {
                    return error(e);
                }
                emit(self.catalog_message());
            }
            ClientMessage::RemoveCatalog { id } => {
                if let Err(e) = self.catalog.lock().unwrap().remove(&id) {
                    return error(e);
                }
                emit(self.catalog_message());
            }
            ClientMessage::UpsertTemplate { template } => {
                if let Err(e) = self.catalog.lock().unwrap().upsert_template(&template) {
                    return error(e);
                }
                emit(self.catalog_message());
            }
            ClientMessage::RemoveTemplate { id } => {
                if let Err(e) = self.catalog.lock().unwrap().remove_template(&id) {
                    return error(e);
                }
                emit(self.catalog_message());
            }
            ClientMessage::TestMcp { id } => {
                let Some(config) = self.catalog.lock().unwrap().get(&id).and_then(|e| e.mcp.clone()) else {
                    return vec![DaemonMessage::Error { message: format!("MCP desconhecido: {id}") }];
                };
                let secrets = self.sessions.lock().unwrap().secrets.clone();
                let events = self.events.clone();
                // Starting a server can take seconds: off the async runtime.
                std::thread::spawn(move || {
                    let env = mcp_env(&config, &secrets);
                    let result = test_mcp(&config, &env, Duration::from_secs(20));
                    let _ = events.send(DaemonMessage::McpTest {
                        id,
                        ok: result.is_ok(),
                        tools: *result.as_ref().unwrap_or(&0),
                        error: result.err(),
                    });
                });
            }
            ClientMessage::UsageReport { days } => {
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_nanos())
                    .unwrap_or(0);
                let since = day_of(now.saturating_sub(u128::from(days) * 86_400 * 1_000_000_000));
                return vec![DaemonMessage::UsageReport { rows: self.usage.lock().unwrap().report(&since) }];
            }
            ClientMessage::AddProject { name, repo, base_branch } => {
                let mut projects = self.projects.lock().unwrap();
                if let Err(e) = projects.add(&name, &repo, &base_branch) {
                    return error(e);
                }
                emit(DaemonMessage::Projects { projects: projects.list() });
            }
            ClientMessage::RemoveProject { id } => {
                let mut projects = self.projects.lock().unwrap();
                if let Err(e) = projects.remove(&id) {
                    return error(e);
                }
                emit(DaemonMessage::Projects { projects: projects.list() });
            }
            ClientMessage::CreateWorktreeSession { project_id, branch, account_id, profile, cols, rows } => {
                let Some(project) = self.projects.lock().unwrap().get(&project_id).cloned() else {
                    return vec![DaemonMessage::Error { message: format!("projeto desconhecido: {project_id}") }];
                };
                let repo = PathBuf::from(&project.repo);
                let path = git::worktree_path(&self.git.worktrees, &project.id, &branch);
                if let Err(e) = git::worktree_add(&repo, &path, &branch, &project.base_branch)
                    .and_then(|_| git::enable_commit_check(&repo, &path, &self.git.hooks, &self.git.commit_check))
                {
                    return error(e);
                }
                let mut sessions = self.sessions.lock().unwrap();
                if let Err(e) = sessions.create_in(&account_id, Some(path), Some((project.id, branch)), profile, cols, rows) {
                    return error(e);
                }
                emit(DaemonMessage::Sessions { sessions: sessions.list() });
            }
            ClientMessage::Diff { session_id } => {
                let Some((cwd, base)) = self.session_base(&session_id) else {
                    return vec![DaemonMessage::Error { message: "a sessão não está num projeto".into() }];
                };
                return match git::diff(&cwd, &base) {
                    Ok(files) => vec![DaemonMessage::Diff { session_id, base, files }],
                    Err(e) => error(e),
                };
            }
            ClientMessage::Search { project_id, session_id, query, regex } => {
                let root = match (&session_id, &project_id) {
                    (Some(s), _) => self.sessions.lock().unwrap().summary(s).map(|s| PathBuf::from(s.cwd)),
                    (None, Some(p)) => self.projects.lock().unwrap().get(p).map(|p| PathBuf::from(&p.repo)),
                    _ => None,
                };
                let Some(root) = root else {
                    return vec![DaemonMessage::Error { message: "nada para buscar".into() }];
                };
                return match git::search(&root, &query, regex, 500) {
                    Ok((hits, truncated)) => vec![DaemonMessage::SearchResults { query, hits, truncated }],
                    Err(e) => vec![DaemonMessage::Error { message: e }],
                };
            }
            ClientMessage::PrStatus { session_id } => {
                let sessions = self.sessions.lock().unwrap();
                let Some(s) = sessions.summary(&session_id) else { return Vec::new() };
                let (Some(branch), gh_dir) = (s.branch.clone(), sessions.account(&s.account_id).and_then(|a| a.gh_config_dir.clone())) else {
                    return vec![DaemonMessage::Error { message: "a sessão não tem branch".into() }];
                };
                let events = self.events.clone();
                // gh goes to the network: off the async runtime.
                std::thread::spawn(move || {
                    let mut cmd = std::process::Command::new("gh");
                    cmd.current_dir(&s.cwd).args([
                        "pr", "view", &branch, "--json",
                        "number,title,state,url,isDraft,reviewDecision,statusCheckRollup",
                    ]);
                    match &gh_dir {
                        Some(dir) => { cmd.env("GH_CONFIG_DIR", dir); }
                        None => { cmd.env_remove("GH_CONFIG_DIR"); }
                    }
                    let pr = cmd
                        .output()
                        .ok()
                        .filter(|o| o.status.success())
                        .and_then(|o| serde_json::from_slice(&o.stdout).ok());
                    let _ = events.send(DaemonMessage::Pr { session_id, pr });
                });
            }
            ClientMessage::ListSessions => {
                return vec![DaemonMessage::Sessions {
                    sessions: self.sessions.lock().unwrap().list(),
                }];
            }
            ClientMessage::Input { session_id, data } => {
                let sessions = self.sessions.lock().unwrap();
                if let Some(s) = sessions.session(&session_id)
                    && let Err(e) = s.write(data.as_bytes())
                {
                    return error(e);
                }
            }
            ClientMessage::Resize { session_id, cols, rows } => {
                let sessions = self.sessions.lock().unwrap();
                if let Some(s) = sessions.session(&session_id)
                    && let Err(e) = s.resize(cols, rows)
                {
                    return error(e);
                }
            }
            ClientMessage::Snapshot { session_id } => {
                let sessions = self.sessions.lock().unwrap();
                if let Some(s) = sessions.session(&session_id) {
                    return vec![DaemonMessage::Grid { session_id, snapshot: s.snapshot() }];
                }
            }
        }
        Vec::new()
    }

    /// Serves the local socket until the task is dropped. The socket file is
    /// owner-only: only this user's processes can talk to the daemon.
    pub async fn serve(self, path: PathBuf) -> std::io::Result<()> {
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path)?;
        set_owner_only(&path)?;
        loop {
            let (stream, _) = listener.accept().await?;
            let daemon = self.clone();
            tokio::spawn(async move {
                let (read, mut write) = stream.into_split();
                let mut lines = BufReader::new(read).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    // Malformed lines are dropped; a helper bug must not take
                    // the daemon down.
                    let Ok(msg) = serde_json::from_str::<ClientMessage>(&line) else { continue };
                    let replies = match msg {
                        ClientMessage::NewPairingTicket => match daemon.remote.get() {
                            Some(r) => vec![DaemonMessage::PairingTicket { ticket: r.new_ticket().await.encode() }],
                            None => vec![DaemonMessage::Error { message: "iroh ainda não subiu".into() }],
                        },
                        other => daemon.handle(other),
                    };
                    for reply in replies {
                        let Ok(mut line) = serde_json::to_vec(&reply) else { continue };
                        line.push(b'\n');
                        if write.write_all(&line).await.is_err() {
                            return;
                        }
                    }
                }
            });
        }
    }
}

impl Daemon {
    /// Local OTLP/HTTP-JSON metrics endpoint for the sessions' Claude Code.
    /// Bound to 127.0.0.1 only.
    pub async fn serve_otlp(self, listener: tokio::net::TcpListener) -> std::io::Result<()> {
        use axum::{Json, Router, extract::State, routing::post};
        async fn metrics(State(d): State<Daemon>, Json(body): Json<serde_json::Value>) -> Json<serde_json::Value> {
            let changed = d.usage.lock().unwrap().record(&parse_otlp(&body));
            for (session_id, usage) in changed {
                let _ = d.events.send(DaemonMessage::SessionUsage { session_id, usage });
            }
            Json(serde_json::json!({}))
        }
        let app = Router::new().route("/v1/metrics", post(metrics)).with_state(self);
        axum::serve(listener, app).await
    }
}

fn set_owner_only(path: &std::path::Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}
