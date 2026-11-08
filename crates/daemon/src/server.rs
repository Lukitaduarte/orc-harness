//! The daemon's state and the local socket the helper binaries talk to
//! (one JSON message per line). Remote clients (the app) reach the same
//! `Daemon::handle` through iroh.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use orc_protocol::{BrowserAction, CatalogEntry, ClientMessage, DaemonMessage, EmulatorAction, ProjectInfo, Profile};
use orc_protocol::GridSnapshot;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;
use tokio::sync::broadcast;

use crate::browser::{Browser, BrowserEvent, Browsers};
use crate::catalog::{Catalog, mcp_env, test_mcp};
use crate::git;
use crate::manager::SessionManager;
use crate::plans::{self, Plans, Run};
use crate::projects::Projects;
use crate::quota::QuotaStore;
use crate::usage::{UsageStore, day_of, parse_otlp};
use crate::remote::Remote;

/// Messages between sessions, by recipient: (from, body).
pub type Inbox = HashMap<String, Vec<(String, String)>>;

/// Env values agents asked to store, waiting for you: id → (session, name, value).
pub type EnvRequests = HashMap<String, (String, String, String)>;

/// Pending MCP additions: id → (session, name, config, reason).
pub type McpRequests = HashMap<String, (String, String, serde_json::Value, String)>;

/// `${NAME}` references in an MCP config: the envs it needs.
pub fn env_refs(config: &serde_json::Value) -> Vec<String> {
    let mut out = Vec::new();
    let mut strings = Vec::new();
    fn walk<'a>(v: &'a serde_json::Value, out: &mut Vec<&'a str>) {
        match v {
            serde_json::Value::String(s) => out.push(s),
            serde_json::Value::Array(a) => a.iter().for_each(|x| walk(x, out)),
            serde_json::Value::Object(o) => o.values().for_each(|x| walk(x, out)),
            _ => {}
        }
    }
    walk(config, &mut strings);
    for s in strings {
        let mut rest = s;
        while let Some(i) = rest.find("${") {
            rest = &rest[i + 2..];
            let Some(end) = rest.find('}') else { break };
            // `${NAME:-default}` names NAME.
            let name = rest[..end].split(":-").next().unwrap_or_default();
            if crate::secrets::valid_env_name(name) && !out.iter().any(|n| n == name) {
                out.push(name.to_string());
            }
            rest = &rest[end + 1..];
        }
    }
    out
}

/// Checks an MCP server an agent asks for: Claude Code's `mcpServers`
/// entry shape, and no secret written into it (env and header values must
/// be `${ENV}` references; the values go to the Keychain).
pub fn check_mcp_request(name: &str, config: &serde_json::Value) -> Result<(), String> {
    if name.is_empty() || name.len() > 64 || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err(format!("nome de MCP inválido: {name} (letras, números, - e _)"));
    }
    let o = config.as_object().ok_or("`config` precisa ser um objeto no formato do mcpServers")?;
    let has = |k: &str| o.get(k).and_then(|v| v.as_str()).is_some_and(|s| !s.is_empty());
    if !has("command") && !has("url") {
        return Err("`config` precisa de `command` (stdio) ou `url` (http/sse)".into());
    }
    for key in ["env", "headers"] {
        let Some(map) = o.get(key) else { continue };
        let map = map.as_object().ok_or(format!("`{key}` precisa ser um objeto"))?;
        for (k, v) in map {
            let v = v.as_str().ok_or(format!("{key}.{k} precisa ser texto"))?;
            if !v.contains("${") {
                return Err(format!(
                    "{key}.{k} tem um valor escrito; use uma referência como \"${{{k}}}\" e peça o valor com request_env_change (segredos ficam só no Keychain)"
                ));
            }
        }
    }
    Ok(())
}

/// Actions waiting for your OK: id → (session, action, the hook waiting).
pub type Approvals = HashMap<String, (String, String, tokio::sync::oneshot::Sender<bool>)>;

/// How long a gated action waits for you before it is refused.
pub const APPROVAL_TIMEOUT: Duration = Duration::from_secs(600);

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
    /// Lock order: plans, then sessions or projects.
    pub plans: Arc<Mutex<Plans>>,
    pub git: GitPaths,
    pub inbox: Arc<Mutex<Inbox>>,
    pub env_requests: Arc<Mutex<EnvRequests>>,
    pub mcp_requests: Arc<Mutex<McpRequests>>,
    /// Everything clients should see; each connection subscribes.
    pub events: broadcast::Sender<DaemonMessage>,
    /// Set once iroh is up; mints pairing tickets for `orcd pair`.
    pub remote: Arc<OnceLock<Remote>>,
    /// Workspace browsers, and the address each open one is at.
    pub browsers: Arc<Browsers>,
    browser_urls: Arc<Mutex<HashMap<String, String>>>,
    /// Agents' last traffic per browser (through the CDP proxy).
    pub browser_use: crate::cdp_proxy::BrowserUse,
    pub devices: crate::devices::Devices,
    /// The CDP proxy's port, once it listens.
    pub cdp_proxy_port: Arc<OnceLock<u16>>,
    /// Browser actions run one at a time, in arrival order (a click must
    /// reach the page before the typing that follows it).
    browser_queue: Arc<OnceLock<tokio::sync::mpsc::UnboundedSender<(String, BrowserAction)>>>,
    pub language_servers: crate::ide::LanguageServers,
    pub workspaces: Arc<Mutex<crate::workspaces::Workspaces>>,
    pub approvals: Arc<Mutex<Approvals>>,
    /// The harness's memory provider (set with a home).
    pub memory: Option<Arc<crate::memory::Memory>>,
    /// `~/.orc` and its config.json, for new accounts (unset: refused).
    home: Option<PathBuf>,
}

/// Playwright MCP, pinned, attached to a workspace browser.
pub const PLAYWRIGHT_MCP: &str = "@playwright/mcp@0.0.83";

impl Daemon {
    pub fn new(
        sessions: SessionManager,
        catalog: Catalog,
        usage: UsageStore,
        projects: Projects,
        plans: Plans,
        git: GitPaths,
    ) -> Self {
        Self {
            quotas: Arc::default(),
            sessions: Arc::new(Mutex::new(sessions)),
            catalog: Arc::new(Mutex::new(catalog)),
            usage: Arc::new(Mutex::new(usage)),
            projects: Arc::new(Mutex::new(projects)),
            plans: Arc::new(Mutex::new(plans)),
            git,
            inbox: Arc::default(),
            env_requests: Arc::default(),
            mcp_requests: Arc::default(),
            events: broadcast::channel(1024).0,
            remote: Arc::default(),
            browsers: Arc::new(Browsers::new(PathBuf::new(), None)),
            browser_urls: Arc::default(),
            browser_use: Arc::default(),
            devices: crate::devices::Devices::new(),
            cdp_proxy_port: Arc::default(),
            browser_queue: Arc::default(),
            language_servers: Default::default(),
            workspaces: Arc::new(Mutex::new(crate::workspaces::Workspaces::load(None))),
            approvals: Arc::default(),
            memory: None,
            home: None,
        }
    }

    /// Keeps workspaces in `home/workspaces.json` and lets the app add
    /// accounts to `home/config.json`.
    pub fn with_home(mut self, home: PathBuf) -> Self {
        self.workspaces = Arc::new(Mutex::new(crate::workspaces::Workspaces::load(Some(home.join("workspaces.json")))));
        let db = self.usage.lock().unwrap().db();
        self.memory = Some(Arc::new(crate::memory::Memory::open(db, Some(home.join("memory")))));
        self.home = Some(home);
        self.sync_memory_providers();
        self
    }

    /// The workspace an account is in.
    fn workspace_of(&self, account_id: &str) -> Option<orc_protocol::WorkspaceInfo> {
        let all = self.sessions.lock().unwrap().account_ids();
        self.workspaces.lock().unwrap().view(&all).into_iter().find(|w| w.accounts.iter().any(|a| a == account_id))
    }

    /// Gives each account's sessions its workspace's external memory MCP
    /// (the harness's own needs nothing: its tools are in `orc`).
    fn sync_memory_providers(&self) {
        let all = self.sessions.lock().unwrap().account_ids();
        let view = self.workspaces.lock().unwrap().view(&all);
        let catalog = self.catalog.lock().unwrap().list();
        let mut extra = HashMap::new();
        for w in view {
            let Some(id) = w.memory.as_deref().filter(|m| *m != "orc" && *m != "off") else { continue };
            let Some(config) = catalog.iter().find(|e| e.id == id && e.kind == "mcp").and_then(|e| e.mcp.clone()) else { continue };
            for a in w.accounts {
                extra.insert(a, std::collections::BTreeMap::from([("memory".to_string(), config.clone())]));
            }
        }
        self.sessions.lock().unwrap().set_extra_mcp(extra);
    }

    fn workspaces_message(&self) -> DaemonMessage {
        let accounts = self.sessions.lock().unwrap().account_ids();
        DaemonMessage::Workspaces { workspaces: self.workspaces.lock().unwrap().view(&accounts) }
    }

    /// Enables workspace browsers (off until set: no browser found).
    pub fn with_browsers(mut self, browsers: Browsers) -> Self {
        self.browsers = Arc::new(browsers);
        self
    }

    /// The profile's browser, opened if needed; its frames and addresses
    /// go to clients.
    pub async fn open_browser(&self, name: &str) -> Result<Arc<Browser>, String> {
        let events = self.events.clone();
        let urls = self.browser_urls.clone();
        let profile = name.to_string();
        let (b, new) = self
            .browsers
            .get(name, move |e| match e {
                BrowserEvent::Frame { jpeg, width, height } => {
                    let _ = events.send(DaemonMessage::BrowserFrame { profile: profile.clone(), jpeg, width, height });
                }
                BrowserEvent::Navigated { url } => {
                    urls.lock().unwrap().insert(profile.clone(), url.clone());
                    let _ = events.send(DaemonMessage::BrowserState { profile: profile.clone(), open: true, url });
                }
            })
            .await?;
        if new {
            self.browser_urls.lock().unwrap().insert(name.into(), "about:blank".into());
            let _ = self.events.send(DaemonMessage::BrowserState { profile: name.into(), open: true, url: "about:blank".into() });
        }
        Ok(b)
    }

    async fn browser_action(&self, profile: &str, action: BrowserAction) -> Result<(), String> {
        if let BrowserAction::Close = action {
            self.browsers.close(profile).await;
            self.browser_urls.lock().unwrap().remove(profile);
            let _ = self.events.send(DaemonMessage::BrowserState { profile: profile.into(), open: false, url: String::new() });
            return Ok(());
        }
        let b = match &action {
            BrowserAction::Open { .. } => self.open_browser(profile).await?,
            _ => self.browsers.running(profile).await.ok_or("o navegador não está aberto")?,
        };
        match action {
            BrowserAction::Open { url: Some(url) } => b.navigate(&url).await,
            BrowserAction::Open { url: None } => Ok(()),
            BrowserAction::Back => b.history(-1).await,
            BrowserAction::Forward => b.history(1).await,
            BrowserAction::Reload => b.reload().await,
            BrowserAction::Resize { width, height } => b.resize(width, height).await,
            BrowserAction::Input { event } => b.input(&event).await,
            BrowserAction::Close => unreachable!(),
        }
    }

    /// Runs `then` with `profile`; when the profile asks for a workspace
    /// browser, first opens it and adds the browser MCP attached to it.
    fn with_browser(
        &self,
        profile: Profile,
        then: impl FnOnce(&Daemon, Profile) -> std::io::Result<()> + Send + 'static,
    ) -> Vec<DaemonMessage> {
        let Some(name) = profile.browser.clone() else {
            return match then(self, profile) {
                Ok(()) => Vec::new(),
                Err(e) => vec![DaemonMessage::Error { message: e.to_string() }],
            };
        };
        let Ok(rt) = tokio::runtime::Handle::try_current() else {
            return vec![DaemonMessage::Error { message: "navegador indisponível aqui".into() }];
        };
        let d = self.clone();
        rt.spawn(async move {
            let result = match d.open_browser(&name).await {
                Ok(b) => {
                    let mut profile = profile;
                    // Through the proxy when it runs, so the app sees who drives
                    // the browser; {ORC_SESSION} becomes the session's id.
                    let endpoint = match d.cdp_proxy_port.get() {
                        Some(port) => format!("http://127.0.0.1:{port}/orc/{name}/{{ORC_SESSION}}"),
                        None => b.cdp_http.clone(),
                    };
                    profile.mcp_servers.insert(
                        "browser".into(),
                        serde_json::json!({
                            "command": "npx",
                            "args": ["-y", PLAYWRIGHT_MCP, "--cdp-endpoint", endpoint],
                        }),
                    );
                    let d2 = d.clone();
                    tokio::task::spawn_blocking(move || then(&d2, profile).map_err(|e| e.to_string()))
                        .await
                        .unwrap_or_else(|e| Err(e.to_string()))
                }
                Err(e) => Err(e),
            };
            if let Err(message) = result {
                let _ = d.events.send(DaemonMessage::Error { message });
            }
        });
        Vec::new()
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
                let mut sessions = self.sessions.lock().unwrap();
                let list = sessions.list();
                let mut trust = Vec::new();
                last.retain(|id, _| list.iter().any(|s| &s.id == id));
                for summary in &list {
                    let Some(s) = sessions.session(&summary.id) else { continue };
                    let generation = s.generation();
                    let entry = last.get(&summary.id);
                    if entry.is_some_and(|(g, _)| *g == generation) {
                        continue;
                    }
                    let snap = s.snapshot();
                    if summary.state == orc_protocol::SessionState::Starting && asks_trust(&snap) {
                        trust.push(summary.id.clone());
                    }
                    let diff = snap.diff_from(entry.map(|(_, p)| p).unwrap_or(&GridSnapshot::default()));
                    if !diff.lines.is_empty() || entry.is_none_or(|(_, p)| p.cursor != snap.cursor) {
                        out.push(DaemonMessage::GridDiff { session_id: summary.id.clone(), diff });
                    }
                    last.insert(summary.id.clone(), (generation, snap));
                }
                for id in trust {
                    if let Some(state) = sessions.on_trust_question(&id) {
                        out.push(DaemonMessage::SessionState { session_id: id, state });
                    }
                }
                let now_exited: Vec<String> = list
                    .iter()
                    .filter(|s| s.state == orc_protocol::SessionState::Exited)
                    .map(|s| s.id.clone())
                    .collect();
                if now_exited != exited {
                    exited = now_exited;
                    // An ended session does not come back after a restart.
                    sessions.save();
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
        let workspaces = self.workspaces_message();
        let (plan_docs, runs) = {
            let plans = self.plans.lock().unwrap();
            let runs: Vec<_> = plans.runs.iter().map(run_message).collect();
            (plans.docs.clone(), runs)
        };
        let sessions = self.sessions.lock().unwrap();
        let mut out = vec![
            DaemonMessage::Hello { accounts: sessions.account_ids() },
            workspaces,
            DaemonMessage::Sessions { sessions: sessions.list() },
            catalog,
            DaemonMessage::Projects { projects: self.projects.lock().unwrap().list() },
            DaemonMessage::Plans { plans: plan_docs },
        ];
        for (id, (session_id, action, _)) in self.approvals.lock().unwrap().iter() {
            out.push(DaemonMessage::Approval { id: id.clone(), session_id: session_id.clone(), action: action.clone() });
        }
        for (profile, url) in self.browser_urls.lock().unwrap().iter() {
            out.push(DaemonMessage::BrowserState { profile: profile.clone(), open: true, url: url.clone() });
        }
        for (profile, (session, at)) in self.browser_use.lock().unwrap().iter() {
            if at.elapsed() < crate::cdp_proxy::ACTIVE_FOR {
                out.push(DaemonMessage::BrowserUse { profile: profile.clone(), session_id: Some(session.clone()) });
            }
        }
        out.extend(runs);
        {
            let plans = self.plans.lock().unwrap();
            for doc in &plans.docs {
                if let Ok(dir) = plans.folder(&doc.id) {
                    let items = crate::learn::load(&dir);
                    if !items.is_empty() {
                        out.push(DaemonMessage::Learnings { plan_id: doc.id.clone(), items });
                    }
                }
            }
        }
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

    fn deliver(&self, from: &str, to: &str, body: &str) {
        self.inbox.lock().unwrap().entry(to.into()).or_default().push((from.into(), body.into()));
        let _ = self.events.send(DaemonMessage::SessionMessage {
            from: from.into(),
            to: to.into(),
            body: body.into(),
        });
    }

    /// The harness MCP tools. `session_id` is the caller (set by orc-mcp
    /// from the session's own environment).
    fn mcp_call(&self, session_id: &str, tool: &str, args: &serde_json::Value) -> Result<String, String> {
        let arg = |k: &str| args.get(k).and_then(|v| v.as_str()).map(str::to_string);
        let me = self.sessions.lock().unwrap().summary(session_id).ok_or("sessão desconhecida")?;
        match tool {
            "list_sessions" => {
                let list = self.sessions.lock().unwrap().list();
                Ok(list
                    .iter()
                    .map(|s| {
                        format!(
                            "{}{} · {:?} · {} · {}",
                            s.id,
                            if s.id == me.id { " (você)" } else { "" },
                            s.state,
                            s.branch.as_deref().unwrap_or(&s.cwd),
                            s.model.as_deref().unwrap_or("modelo padrão"),
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n"))
            }
            "send_message" => {
                let to = arg("to").ok_or("falta `to`")?;
                let body = arg("body").ok_or("falta `body`")?;
                if self.sessions.lock().unwrap().summary(&to).is_none() {
                    return Err(format!("sessão {to} não existe; veja list_sessions"));
                }
                self.deliver(&me.id, &to, &body);
                Ok(format!("mensagem entregue a {to}"))
            }
            "read_inbox" => {
                let msgs = self.inbox.lock().unwrap().remove(&me.id).unwrap_or_default();
                if msgs.is_empty() {
                    return Ok("nenhuma mensagem".into());
                }
                Ok(msgs.iter().map(|(f, b)| format!("de {f}: {b}")).collect::<Vec<_>>().join("\n\n"))
            }
            "delegate_task" => {
                let prompt = arg("prompt").ok_or("falta `prompt`")?;
                let mut sessions = self.sessions.lock().unwrap();
                let mut profile = sessions.profile(&me.id).cloned().unwrap_or_default();
                if let Some(model) = arg("model") {
                    profile.model = Some(model);
                }
                let (cwd, project) = match (arg("branch"), &me.project_id) {
                    (Some(branch), Some(pid)) => {
                        let project = self.projects.lock().unwrap().get(pid).cloned().ok_or("projeto sumiu")?;
                        let path = self.worktree(&project, &branch).map_err(|e| e.to_string())?;
                        (path, Some((project.id, branch)))
                    }
                    (Some(_), None) => return Err("branch só vale para sessões de projeto".into()),
                    (None, _) => (PathBuf::from(&me.cwd), me.project_id.clone().zip(me.branch.clone())),
                };
                let full = format!(
                    "{prompt}\n\n(Você foi criado pela sessão {} via delegate_task do harness. Ao terminar, \
                     use a tool send_message para {} com o resultado.)",
                    me.id, me.id
                );
                let new = sessions
                    .create_with_prompt(&me.account_id, Some(cwd), project, profile, Some(full), 100, 30)
                    .map_err(|e| e.to_string())?;
                let _ = self.events.send(DaemonMessage::Sessions { sessions: sessions.list() });
                Ok(format!("sessão {} criada; ela vai responder com send_message", new.id))
            }
            "search_code" => {
                let query = arg("query").ok_or("falta `query`")?;
                let regex = args.get("regex").and_then(|v| v.as_bool()).unwrap_or(false);
                let (hits, more) = git::search(std::path::Path::new(&me.cwd), &query, regex, 100)?;
                let mut out: Vec<String> = hits.iter().map(|h| format!("{}:{}: {}", h.path, h.line, h.text.trim())).collect();
                if more {
                    out.push("(mais resultados omitidos; refine a busca)".into());
                }
                Ok(if out.is_empty() { "nada encontrado".into() } else { out.join("\n") })
            }
            "request_env_change" => {
                let name = arg("name").ok_or("falta `name`")?;
                let value = arg("value").ok_or("falta `value`")?;
                if !crate::secrets::valid_env_name(&name) {
                    return Err(format!("nome de env inválido: {name}"));
                }
                let id = uuid::Uuid::new_v4().simple().to_string();
                self.env_requests.lock().unwrap().insert(id.clone(), (me.id.clone(), name.clone(), value));
                let _ = self.events.send(DaemonMessage::EnvRequest { id, session_id: me.id, name: name.clone() });
                Ok(format!("pedido enviado ao usuário; {name} só é gravada se ele aprovar no app (a resposta chega no read_inbox)"))
            }
            "request_mcp_add" => {
                let name = arg("name").ok_or("falta `name`")?;
                let config = args.get("config").cloned().ok_or("falta `config`")?;
                check_mcp_request(&name, &config)?;
                // The session cannot start with an env that has no value:
                // values first, then the server.
                let secrets = self.sessions.lock().unwrap().secrets.clone();
                let missing: Vec<String> =
                    env_refs(&config).into_iter().filter(|n| secrets.get(&crate::secrets::env_key(n)).is_none()).collect();
                if !missing.is_empty() {
                    return Err(format!(
                        "antes, peça o valor de {} com request_env_change; depois que o usuário aprovar, peça o MCP de novo",
                        missing.join(", ")
                    ));
                }
                let reason = arg("reason").unwrap_or_default();
                let id = uuid::Uuid::new_v4().simple().to_string();
                self.mcp_requests.lock().unwrap().insert(id.clone(), (me.id.clone(), name.clone(), config.clone(), reason.clone()));
                let _ = self.events.send(DaemonMessage::McpRequest { id, session_id: me.id, name: name.clone(), mcp: config, reason });
                Ok(format!(
                    "pedido enviado ao usuário; o MCP {name} só entra se ele aprovar no app. Se aprovar, esta sessão reinicia com ele (a conversa continua) e o aviso chega no read_inbox."
                ))
            }
            "remember" | "recall" | "forget" => {
                let memory = self.memory.as_ref().ok_or("este harness não tem memória")?;
                let ws = self.workspace_of(&me.account_id).ok_or("a sessão não está em nenhum workspace")?;
                match ws.memory.as_deref() {
                    None | Some("orc") => {}
                    Some("off") => return Err("a memória está desligada neste workspace".into()),
                    Some(other) => return Err(format!("a memória deste workspace é o MCP {other}; use as tools dele")),
                }
                match tool {
                    "remember" => {
                        let tags: Vec<String> = args
                            .get("tags")
                            .and_then(|v| v.as_array())
                            .map(|a| a.iter().filter_map(|t| t.as_str().map(String::from)).collect())
                            .unwrap_or_default();
                        let e = memory.remember(&ws.id, &me.id, &arg("text").ok_or("falta `text`")?, tags).map_err(|e| e.to_string())?;
                        Ok(format!("guardado ({}) na memória do workspace {}", e.id, ws.name))
                    }
                    "recall" => {
                        let hits = memory.recall(&ws.id, &arg("query").unwrap_or_default(), 10);
                        Ok(if hits.is_empty() {
                            "nada na memória sobre isso".into()
                        } else {
                            hits.iter()
                                .map(|e| {
                                    let tags = if e.tags.is_empty() { String::new() } else { format!(" [{}]", e.tags.join(", ")) };
                                    format!("{}{}: {}", e.id, tags, e.text)
                                })
                                .collect::<Vec<_>>()
                                .join("\n")
                        })
                    }
                    _ => {
                        let id = arg("id").ok_or("falta `id`")?;
                        match memory.forget(&ws.id, &id).map_err(|e| e.to_string())? {
                            true => Ok(format!("esquecido: {id}")),
                            false => Err(format!("não há memória {id}")),
                        }
                    }
                }
            }
            "list_envs" => {
                // Names and whether they have a value; values never.
                let mine = self.sessions.lock().unwrap().profile(&me.id).map(|p| p.env_names.clone()).unwrap_or_default();
                let secrets = self.sessions.lock().unwrap().secrets.clone();
                let envs: Vec<String> = self
                    .catalog
                    .lock()
                    .unwrap()
                    .entries(&secrets)
                    .into_iter()
                    .filter(|e| e.kind == "env")
                    .map(|e| {
                        format!(
                            "{} · {} · {}{}",
                            e.name,
                            if e.has_value { "com valor" } else { "sem valor" },
                            if mine.contains(&e.name) { "ativa nesta sessão" } else { "não ativa nesta sessão" },
                            if e.description.is_empty() { String::new() } else { format!(" · {}", e.description) },
                        )
                    })
                    .collect();
                Ok(if envs.is_empty() {
                    "nenhuma env no catálogo; peça com request_env_change".into()
                } else {
                    envs.join("\n")
                })
            }
            "propose_learning" => {
                let field = |k: &str| arg(k).unwrap_or_default();
                let plans = self.plans.lock().unwrap();
                let (plan_id, skills) = plans.learners.get(&me.id).cloned().ok_or("esta sessão não está fazendo Learn")?;
                let skill = field("skill");
                if !skills.iter().any(|(n, _)| *n == skill) {
                    return Err(format!("skill {skill} não está entre as deste Learn"));
                }
                if field("file").is_empty() || field("new").is_empty() {
                    return Err("falta `file` ou `new`".into());
                }
                let dir = plans.folder(&plan_id).map_err(|e| e.to_string())?;
                let mut items = crate::learn::load(&dir);
                items.push(orc_protocol::LearningItem {
                    id: uuid::Uuid::new_v4().simple().to_string()[..12].to_string(),
                    skill,
                    file: field("file"),
                    summary: field("summary"),
                    old: field("old"),
                    new: field("new"),
                    source: field("source"),
                    status: "pending".into(),
                    error: None,
                });
                crate::learn::save(&dir, &items).map_err(|e| e.to_string())?;
                let _ = self.events.send(DaemonMessage::Learnings { plan_id, items });
                drop(plans);
                Ok("proposta registrada; o usuário decide no app".into())
            }
            "save_plan" => {
                let markdown = arg("markdown").ok_or("falta `markdown`")?;
                let replies = args.get("replies").and_then(|v| v.as_array()).cloned().unwrap_or_default();
                let amendments: Vec<String> = args
                    .get("amendments")
                    .and_then(|v| v.as_array())
                    .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
                    .unwrap_or_default();
                let mut plans = self.plans.lock().unwrap();
                let Some(doc) = plans.docs.iter_mut().find(|d| d.planner.as_deref() == Some(me.id.as_str())) else {
                    return Err("esta sessão não está planejando nenhum plano".into());
                };
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_millis() as u64)
                    .unwrap_or(0);
                let skipped = plans::apply_save(doc, &markdown, &replies, &amendments, now);
                let doc = doc.clone();
                plans.save(doc.clone()).map_err(|e| e.to_string())?;
                let _ = self.events.send(DaemonMessage::Plans { plans: plans.docs.clone() });
                let mut out = format!("plano salvo (revisão {}); o usuário revisa no app", doc.revision);
                for s in skipped {
                    out.push_str(&format!("\nignorado: {s}"));
                }
                Ok(out)
            }
            other => Err(format!("tool desconhecida: {other}")),
        }
    }

    /// A project session's folder and its project's base branch.
    fn session_base(&self, session_id: &str) -> Option<(PathBuf, String)> {
        let s = self.sessions.lock().unwrap().summary(session_id)?;
        let base = self.projects.lock().unwrap().get(s.project_id.as_deref()?)?.base_branch.clone();
        Some((PathBuf::from(s.cwd), base))
    }

    /// The worktree of `branch` (created if needed), commit check on.
    fn worktree(&self, project: &ProjectInfo, branch: &str) -> std::io::Result<PathBuf> {
        let repo = PathBuf::from(&project.repo);
        let path = git::worktree_path(&self.git.worktrees, &project.id, branch);
        git::worktree_add(&repo, &path, branch, &project.base_branch)?;
        git::enable_commit_check(&repo, &path, &self.git.hooks, &self.git.commit_check)?;
        Ok(path)
    }

    /// Starts the run's cards whose dependencies are done, each in its own
    /// worktree session told what to do. A card that cannot start fails
    /// with the reason; the others go on.
    fn start_ready(&self, run: &mut Run) {
        let ready = run.ready_to_start();
        if ready.is_empty() {
            return;
        }
        let project = self.projects.lock().unwrap().get(&run.project_id).cloned();
        let candidates = self.run_accounts(run, project.as_ref());
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        for spec in ready {
            // The account with most room; none with room: the card waits.
            let account = match self.quotas.lock().unwrap().pick(&candidates, now) {
                Ok(a) => a,
                Err(why) => {
                    if let Some(card) = run.card_mut(spec.number) {
                        card.note = Some(why);
                    }
                    continue;
                }
            };
            let started = project
                .as_ref()
                .ok_or_else(|| std::io::Error::other("o projeto do plano foi removido"))
                .and_then(|project| {
                    let path = self.worktree(project, &spec.branch)?;
                    let profile = Profile { model: spec.model.clone(), ..Profile::default() };
                    self.sessions.lock().unwrap().create_with_prompt(
                        &account,
                        Some(path),
                        Some((project.id.clone(), spec.branch.clone())),
                        profile,
                        Some(plans::card_prompt(&spec.prompt, &spec.branch)),
                        100,
                        30,
                    )
                });
            let Some(card) = run.card_mut(spec.number) else { continue };
            match started {
                Ok(s) => {
                    card.state = "running".into();
                    card.session_id = Some(s.id);
                    card.account_id = Some(account);
                    card.note = None;
                }
                Err(e) => {
                    card.state = "failed".into();
                    card.note = Some(e.to_string());
                }
            }
        }
        let _ = self.events.send(DaemonMessage::Sessions { sessions: self.sessions.lock().unwrap().list() });
    }

    /// Accounts a run's cards may use: those of its repository's workspace
    /// (the run's own account if that is unknown).
    fn run_accounts(&self, run: &Run, project: Option<&ProjectInfo>) -> Vec<String> {
        let all = self.sessions.lock().unwrap().account_ids();
        let view = self.workspaces.lock().unwrap().view(&all);
        let ws = project
            .and_then(|p| p.workspace_id.as_deref())
            .and_then(|id| view.iter().find(|w| w.id == id))
            .or_else(|| view.iter().find(|w| w.accounts.contains(&run.account_id)));
        match ws {
            Some(w) if !w.accounts.is_empty() => w.accounts.clone(),
            _ => vec![run.account_id.clone()],
        }
    }

    /// Asks GitHub about every card with work out: an open PR moves it to
    /// review, a merged one to done (freeing its dependents, started
    /// here). A running card whose session ended without a PR stops.
    pub fn poll_plans(&self) {
        // Read what to ask, then ask without holding any lock (network).
        let mut asks = Vec::new();
        {
            let plans = self.plans.lock().unwrap();
            let sessions = self.sessions.lock().unwrap();
            let projects = self.projects.lock().unwrap();
            for run in plans.runs.iter().filter(|r| r.active()) {
                let Some(project) = projects.get(&run.project_id) else { continue };
                let gh = sessions.account(&run.account_id).and_then(|a| a.gh_config_dir.clone());
                for c in run.cards.iter().filter(|c| c.state == "running" || c.state == "review") {
                    let alive = c
                        .session_id
                        .as_deref()
                        .and_then(|id| sessions.summary(id))
                        .is_some_and(|s| s.state != orc_protocol::SessionState::Exited);
                    asks.push((run.plan_id.clone(), c.number, c.branch.clone(), PathBuf::from(&project.repo), gh.clone(), alive));
                }
            }
        }
        let answers: Vec<_> = asks
            .into_iter()
            .map(|(plan, n, branch, repo, gh, alive)| {
                let pr = gh_pr(&repo, &branch, gh.as_deref());
                (plan, n, branch, pr, alive)
            })
            .collect();
        let mut plans = self.plans.lock().unwrap();
        let mut changed = Vec::new();
        let mut moved_plans = Vec::new();
        for (plan, n, branch, pr, alive) in answers {
            let Some(run) = plans.run_mut(&plan) else { continue };
            let moved = match &pr {
                Some(pr) => run.apply_pr(&branch, pr),
                None if !alive => {
                    let card = run.card_mut(n).filter(|c| c.state == "running");
                    card.map(|c| {
                        c.state = "stopped".into();
                        c.note = Some("a sessão terminou sem abrir PR".into());
                    })
                    .is_some()
                }
                None => false,
            };
            if moved && !changed.contains(&plan) {
                moved_plans.push(plan.clone());
                changed.push(plan);
            }
        }
        // Cards waiting for quota or a free slot get another try each poll.
        for run in plans.runs.iter().filter(|r| !r.finished()) {
            if !run.ready_to_start().is_empty() && !changed.contains(&run.plan_id) {
                changed.push(run.plan_id.clone());
            }
        }
        for plan in changed {
            let Some(run) = plans.run_mut(&plan) else { continue };
            let before = run.cards.clone();
            self.start_ready(run);
            let run = run.clone();
            if run.cards == before && !moved_plans.contains(&plan) {
                continue;
            }
            if let Err(e) = plans.save_run(&run) {
                eprintln!("orcd: não salvei a execução de {plan}: {e}");
            }
            let _ = self.events.send(run_message(&run));
        }
    }

    /// Sends `request` to the plan's planning session, or starts one in the
    /// project's repository (it reads code, never commits) with the plan so
    /// far and the request.
    fn ask_planner(&self, plan_id: &str, account_id: &str, request: &str) -> Result<(), String> {
        let mut plans = self.plans.lock().unwrap();
        let doc = plans.docs.iter().find(|d| d.id == plan_id).cloned().ok_or("plano desconhecido")?;
        let mut sessions = self.sessions.lock().unwrap();
        let alive = doc
            .planner
            .as_deref()
            .and_then(|id| sessions.summary(id))
            .filter(|s| s.state != orc_protocol::SessionState::Exited);
        let planner = match alive {
            Some(s) => {
                let session = sessions.session(&s.id).ok_or("sessão de planejamento sumiu")?;
                // Bracketed paste keeps the request's lines together; Enter sends it.
                session
                    .write(format!("\x1b[200~{request}\x1b[201~").as_bytes())
                    .map_err(|e| e.to_string())?;
                std::thread::sleep(Duration::from_millis(150));
                session.write(b"\r").map_err(|e| e.to_string())?;
                s.id
            }
            None => {
                let project = self.projects.lock().unwrap().get(&doc.project_id).cloned().ok_or("o projeto do plano foi removido")?;
                let prompt = plans::planner_prompt(&doc, &project.repo, request);
                let s = sessions
                    .create_with_prompt(account_id, Some(PathBuf::from(&project.repo)), None, Profile::default(), Some(prompt), 100, 30)
                    .map_err(|e| e.to_string())?;
                let _ = self.events.send(DaemonMessage::Sessions { sessions: sessions.list() });
                s.id
            }
        };
        drop(sessions);
        let doc = plans.doc_mut(plan_id).ok_or("plano desconhecido")?;
        doc.planner = Some(planner);
        doc.busy = true;
        let doc = doc.clone();
        plans.save(doc).map_err(|e| e.to_string())?;
        let _ = self.events.send(DaemonMessage::Plans { plans: plans.docs.clone() });
        Ok(())
    }

    /// Starts the Learn session for a plan: in its repository, told the
    /// comments and the skills' text; it only proposes.
    fn start_learner(&self, plan_id: &str, account_id: &str, notes: &[String], skills: &[String]) -> Result<(), String> {
        if notes.is_empty() {
            return Err("nenhum comentário novo para aprender".into());
        }
        let (name, project_id) = {
            let plans = self.plans.lock().unwrap();
            let doc = plans.docs.iter().find(|d| d.id == plan_id).ok_or("plano desconhecido")?;
            (doc.name.clone(), doc.project_id.clone())
        };
        let catalog = self.catalog.lock().unwrap();
        let found: Vec<(String, PathBuf)> = skills
            .iter()
            .filter_map(|s| {
                let e = catalog.list().into_iter().find(|e| e.kind == "skill" && &e.name == s)?;
                Some((e.name.clone(), crate::catalog::expand(e.path.as_deref()?)))
            })
            .collect();
        drop(catalog);
        if found.is_empty() {
            return Err("nenhuma das skills dos cards está no catálogo".into());
        }
        let repo = self.projects.lock().unwrap().get(&project_id).map(|p| PathBuf::from(&p.repo)).ok_or("o projeto do plano foi removido")?;
        let prompt = crate::learn::learner_prompt(&name, notes, &found);
        let mut sessions = self.sessions.lock().unwrap();
        let s = sessions
            .create_with_prompt(account_id, Some(repo), None, Profile::default(), Some(prompt), 100, 30)
            .map_err(|e| e.to_string())?;
        let _ = self.events.send(DaemonMessage::Sessions { sessions: sessions.list() });
        drop(sessions);
        self.plans.lock().unwrap().learners.insert(s.id, (plan_id.into(), found));
        Ok(())
    }

    /// Applies (in the skill's folder) or declines a proposed learning.
    fn decide_learning(&self, plan_id: &str, id: &str, accept: bool) -> Result<(), String> {
        let plans = self.plans.lock().unwrap();
        let dir = plans.folder(plan_id).map_err(|e| e.to_string())?;
        let mut items = crate::learn::load(&dir);
        let item = items.iter_mut().find(|i| i.id == id).ok_or("aprendizado desconhecido")?;
        if item.status != "pending" && item.status != "failed" {
            return Err("já decidido".into());
        }
        if accept {
            let skill_dir = self
                .catalog
                .lock()
                .unwrap()
                .list()
                .into_iter()
                .find(|e| e.kind == "skill" && e.name == item.skill)
                .and_then(|e| e.path.map(|p| crate::catalog::expand(&p)))
                .ok_or("a skill saiu do catálogo")?;
            match crate::learn::apply(&skill_dir, item) {
                Ok(()) => {
                    item.status = "applied".into();
                    item.error = None;
                }
                Err(e) => {
                    item.status = "failed".into();
                    item.error = Some(e.to_string());
                }
            }
        } else {
            item.status = "declined".into();
        }
        crate::learn::save(&dir, &items).map_err(|e| e.to_string())?;
        let _ = self.events.send(DaemonMessage::Learnings { plan_id: plan_id.into(), items });
        Ok(())
    }

    /// Polls plans every `every`, off the async runtime.
    pub async fn watch_plans(self, every: Duration) {
        let mut tick = tokio::time::interval(every);
        loop {
            tick.tick().await;
            let d = self.clone();
            let _ = tokio::task::spawn_blocking(move || d.poll_plans()).await;
        }
    }

    /// The folder a session works in (the IDE's root).
    fn session_root(&self, session_id: &str) -> Option<PathBuf> {
        self.sessions.lock().unwrap().summary(session_id).map(|s| PathBuf::from(s.cwd))
    }

    /// Push of a project session's branch, or squash-merge of its PR, as
    /// the session's account; the result comes as an event.
    fn git_remote(&self, session_id: String, merge: bool) -> Vec<DaemonMessage> {
        let sessions = self.sessions.lock().unwrap();
        let Some(s) = sessions.summary(&session_id) else { return no_session() };
        let (Some(branch), gh_dir) = (s.branch.clone(), sessions.account(&s.account_id).and_then(|a| a.gh_config_dir.clone())) else {
            return vec![DaemonMessage::Error { message: "a sessão não tem branch".into() }];
        };
        let events = self.events.clone();
        // Network: off the async runtime; the result comes as an event.
        std::thread::spawn(move || {
            let mut cmd = if merge {
                let mut c = std::process::Command::new("gh");
                c.args(["pr", "merge", &branch, "--squash"]);
                c
            } else {
                let mut c = std::process::Command::new("git");
                c.args(["push", "-u", "origin", &branch]);
                c
            };
            cmd.current_dir(&s.cwd);
            // gh (and git's gh credential helper) as the session's account.
            match &gh_dir {
                Some(dir) => cmd.env("GH_CONFIG_DIR", dir),
                None => cmd.env_remove("GH_CONFIG_DIR"),
            };
            let (ok, output) = match cmd.output() {
                Ok(o) => (o.status.success(), format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr)).trim().to_string()),
                Err(e) => (false, e.to_string()),
            };
            let action = if merge { "merge" } else { "push" }.to_string();
            let _ = events.send(DaemonMessage::GitResult { session_id, action, ok, output });
        });
        Vec::new()
    }

    /// MCP servers and skills set up on this Mac (see mcp_import).
    fn scan_imports(&self) -> crate::mcp_import::Scan {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
        let accounts: Vec<PathBuf> = {
            let sessions = self.sessions.lock().unwrap();
            sessions.account_ids().iter().filter_map(|id| sessions.account(id)?.config_dir.clone()).collect()
        };
        let projects: Vec<(String, PathBuf)> =
            self.projects.lock().unwrap().list().into_iter().map(|p| (p.name, crate::catalog::expand(&p.repo))).collect();
        crate::mcp_import::scan_all(&home, &accounts, &projects)
    }

    fn mcp_imports(&self) -> DaemonMessage {
        let catalog = self.catalog.lock().unwrap().list();
        let has_mcp = |n: &str| catalog.iter().any(|e| e.kind == "mcp" && e.name == n);
        let has_skill = |p: &std::path::Path| {
            catalog.iter().any(|e| e.kind == "skill" && e.path.as_deref().map(std::path::Path::new) == Some(p))
        };
        let scan = self.scan_imports();
        let mut items: Vec<orc_protocol::McpImport> = scan
            .mcps
            .into_iter()
            .map(|f| {
                let (mcp, secrets) = crate::mcp_import::sanitize(&f.name, &f.config);
                orc_protocol::McpImport {
                    in_catalog: has_mcp(&f.name),
                    kind: "mcp".into(),
                    description: String::new(),
                    key: f.key,
                    label: f.label,
                    name: f.name,
                    mcp,
                    secrets: secrets.into_iter().map(|(n, _)| n).collect(),
                }
            })
            .collect();
        items.extend(scan.skills.into_iter().map(|s| orc_protocol::McpImport {
            in_catalog: has_skill(&s.path),
            kind: "skill".into(),
            description: s.description,
            key: s.key,
            label: s.label,
            name: s.name,
            mcp: serde_json::Value::Null,
            secrets: Vec::new(),
        }));
        DaemonMessage::McpImports { items }
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
                return self.with_browser(profile, move |d, profile| {
                    let mut sessions = d.sessions.lock().unwrap();
                    sessions.create(&account_id, cwd.map(PathBuf::from), profile, cols, rows)?;
                    let _ = d.events.send(DaemonMessage::Sessions { sessions: sessions.list() });
                    Ok(())
                });
            }
            ClientMessage::ApplyProfile { session_id, profile } => {
                return self.with_browser(profile, move |d, profile| {
                    let mut sessions = d.sessions.lock().unwrap();
                    sessions.apply_profile(&session_id, profile)?;
                    let _ = d.events.send(DaemonMessage::Sessions { sessions: sessions.list() });
                    Ok(())
                });
            }
            ClientMessage::ListDir { session_id, path } => {
                let Some(root) = self.session_root(&session_id) else { return no_session() };
                return match crate::ide::list_dir(&root, &path) {
                    Ok(entries) => vec![DaemonMessage::DirEntries { session_id, path, entries }],
                    Err(e) => error(e),
                };
            }
            ClientMessage::ReadFile { session_id, path } => {
                let Some(root) = self.session_root(&session_id) else { return no_session() };
                return match crate::ide::read_file(&root, &path) {
                    Ok(text) => vec![DaemonMessage::FileContent { session_id, path, text }],
                    Err(e) => error(e),
                };
            }
            ClientMessage::WriteFile { session_id, path, text } => {
                let Some(root) = self.session_root(&session_id) else { return no_session() };
                return match crate::ide::write_file(&root, &path, &text) {
                    Ok(()) => vec![DaemonMessage::FileSaved { session_id, path }],
                    Err(e) => error(e),
                };
            }
            ClientMessage::Lsp { session_id, language, message } => {
                let Some(root) = self.session_root(&session_id) else { return no_session() };
                let events = self.events.clone();
                let (sid, lang) = (session_id.clone(), language.clone());
                let sent = self.language_servers.send(&session_id, &language, &root, &message, move |message| {
                    let _ = events.send(DaemonMessage::Lsp { session_id: sid.clone(), language: lang.clone(), message });
                });
                if let Err(e) = sent {
                    return error(e);
                }
            }
            ClientMessage::OpenExternal { session_id, path, app } => {
                let Some(root) = self.session_root(&session_id) else { return no_session() };
                let Some(app) = crate::ide::external_app(&app) else {
                    return vec![DaemonMessage::Error { message: format!("app desconhecido: {app}") }];
                };
                let target = match crate::ide::resolve(&root, &path) {
                    Ok(p) => p,
                    Err(e) => return error(e),
                };
                if let Err(e) = std::process::Command::new("open").arg("-a").arg(app).arg(target).status() {
                    return error(e);
                }
            }
            ClientMessage::Browser { profile, action } => {
                let Ok(rt) = tokio::runtime::Handle::try_current() else {
                    return vec![DaemonMessage::Error { message: "navegador indisponível aqui".into() }];
                };
                let queue = self.browser_queue.get_or_init(|| {
                    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<(String, BrowserAction)>();
                    let d = self.clone();
                    rt.spawn(async move {
                        while let Some((profile, action)) = rx.recv().await {
                            if let Err(message) = d.browser_action(&profile, action).await {
                                let _ = d.events.send(DaemonMessage::Error { message });
                            }
                        }
                    });
                    tx
                });
                let _ = queue.send((profile, action));
            }
            ClientMessage::ListEmulators | ClientMessage::Emulator { .. } => {
                // simctl, adb and AXe take a while: off the message loop.
                let (d, events) = (self.devices.clone(), self.events.clone());
                std::thread::spawn(move || {
                    let refresh = match msg {
                        ClientMessage::Emulator { id, action } => {
                            let changes = matches!(action, EmulatorAction::Boot | EmulatorAction::Shutdown);
                            let result = match action {
                                EmulatorAction::Boot => d.boot(&id),
                                EmulatorAction::Shutdown => d.shutdown(&id),
                                EmulatorAction::Watch => d.watch(&id, events.clone()),
                                EmulatorAction::Unwatch => {
                                    d.unwatch(&id);
                                    Ok(())
                                }
                                other => d.act(&id, other),
                            };
                            if let Err(message) = result {
                                let _ = events.send(DaemonMessage::Error { message });
                            }
                            changes
                        }
                        _ => true,
                    };
                    if refresh {
                        let _ = events.send(DaemonMessage::Emulators { emulators: d.list() });
                    }
                });
            }
            ClientMessage::StopSession { session_id } => {
                self.language_servers.stop(&session_id);
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
                self.sync_memory_providers();
                emit(self.catalog_message());
            }
            ClientMessage::RemoveCatalog { id } => {
                if let Err(e) = self.catalog.lock().unwrap().remove(&id) {
                    return error(e);
                }
                self.sync_memory_providers();
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
            ClientMessage::UpsertWorkspace { workspace } => {
                let known = self.sessions.lock().unwrap().account_ids();
                if let Err(e) = self.workspaces.lock().unwrap().upsert(workspace, &known) {
                    return error(e);
                }
                emit(self.workspaces_message());
                self.sync_memory_providers();
            }
            ClientMessage::RemoveWorkspace { id } => {
                let known = self.sessions.lock().unwrap().account_ids();
                if let Err(e) = self.workspaces.lock().unwrap().remove(&id, &known) {
                    return error(e);
                }
                emit(self.workspaces_message());
                self.sync_memory_providers();
            }
            ClientMessage::AddAccount { id, workspace_id } => {
                let Some(home) = &self.home else {
                    return vec![DaemonMessage::Error { message: "este daemon não aceita contas novas".into() }];
                };
                let account = match crate::config::add_account(&home.join("config.json"), home, &id) {
                    Ok(a) => a,
                    Err(e) => return error(e),
                };
                let known = {
                    let mut sessions = self.sessions.lock().unwrap();
                    sessions.add_account(account);
                    sessions.account_ids()
                };
                if let Err(e) = self.workspaces.lock().unwrap().assign(&id, &workspace_id, &known) {
                    return error(e);
                }
                emit(DaemonMessage::Hello { accounts: known });
                emit(self.workspaces_message());
                self.sync_memory_providers();
            }
            ClientMessage::AddProject { name, repo, base_branch, workspace_id } => {
                let mut projects = self.projects.lock().unwrap();
                if let Err(e) = projects.add(&name, &repo, &base_branch, workspace_id) {
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
                let path = match self.worktree(&project, &branch) {
                    Ok(p) => p,
                    Err(e) => return error(e),
                };
                return self.with_browser(profile, move |d, profile| {
                    let mut sessions = d.sessions.lock().unwrap();
                    sessions.create_in(&account_id, Some(path), Some((project.id, branch)), profile, cols, rows)?;
                    let _ = d.events.send(DaemonMessage::Sessions { sessions: sessions.list() });
                    Ok(())
                });
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
            ClientMessage::GitCommit { session_id, message } => {
                let Some((cwd, _)) = self.session_base(&session_id) else {
                    return vec![DaemonMessage::Error { message: "a sessão não está num projeto".into() }];
                };
                let (ok, output) = match git::commit_all(&cwd, &message) {
                    Ok(out) => (true, out),
                    Err(e) => (false, e.to_string()),
                };
                return vec![DaemonMessage::GitResult { session_id, action: "commit".into(), ok, output }];
            }
            ClientMessage::GitPush { session_id } => return self.git_remote(session_id, false),
            ClientMessage::MergePr { session_id } => return self.git_remote(session_id, true),
            ClientMessage::PrStatus { session_id } => {
                let sessions = self.sessions.lock().unwrap();
                let Some(s) = sessions.summary(&session_id) else { return Vec::new() };
                let (Some(branch), gh_dir) = (s.branch.clone(), sessions.account(&s.account_id).and_then(|a| a.gh_config_dir.clone())) else {
                    return vec![DaemonMessage::Error { message: "a sessão não tem branch".into() }];
                };
                let events = self.events.clone();
                // gh goes to the network: off the async runtime.
                std::thread::spawn(move || {
                    let pr = gh_pr(std::path::Path::new(&s.cwd), &branch, gh_dir.as_deref());
                    let _ = events.send(DaemonMessage::Pr { session_id, pr });
                });
            }
            ClientMessage::McpCall { session_id, tool, args } => {
                let (text, is_error) = match self.mcp_call(&session_id, &tool, &args) {
                    Ok(t) => (t, false),
                    Err(e) => (e, true),
                };
                return vec![DaemonMessage::McpResult { text, is_error }];
            }
            ClientMessage::ResolveEnvRequest { id, approve } => {
                let Some((session, name, value)) = self.env_requests.lock().unwrap().remove(&id) else {
                    return vec![DaemonMessage::Error { message: "pedido de env não encontrado".into() }];
                };
                if approve {
                    let secrets = self.sessions.lock().unwrap().secrets.clone();
                    if let Err(e) = secrets.set(&crate::secrets::env_key(&name), &value) {
                        return error(e);
                    }
                    emit(self.catalog_message());
                }
                let verdict = if approve { "aprovou" } else { "recusou" };
                self.deliver("harness", &session, &format!("O usuário {verdict} gravar {name}."));
                emit(DaemonMessage::EnvRequestResolved { id, approved: approve });
            }
            ClientMessage::ResolveMcpRequest { id, approve } => {
                let Some((session, name, config, reason)) = self.mcp_requests.lock().unwrap().remove(&id) else {
                    return vec![DaemonMessage::Error { message: "pedido de MCP não encontrado".into() }];
                };
                if !approve {
                    self.deliver("harness", &session, &format!("O usuário recusou o MCP {name}."));
                    emit(DaemonMessage::McpRequestResolved { id, approved: false });
                    return Vec::new();
                }
                let needs = env_refs(&config);
                {
                    let mut catalog = self.catalog.lock().unwrap();
                    // Same name: the agent's version replaces it.
                    let entry_id = catalog
                        .list()
                        .into_iter()
                        .find(|e| e.kind == "mcp" && e.name == name)
                        .map_or_else(|| format!("mcp-{name}"), |e| e.id);
                    let entry = CatalogEntry {
                        id: entry_id,
                        kind: "mcp".into(),
                        name: name.clone(),
                        description: reason,
                        path: None,
                        mcp: Some(config.clone()),
                        has_value: false,
                    };
                    if let Err(e) = catalog.upsert(entry) {
                        return error(e);
                    }
                    for env in &needs {
                        if !catalog.list().iter().any(|e| e.kind == "env" && &e.name == env) {
                            let entry = CatalogEntry {
                                id: format!("env-{env}"),
                                kind: "env".into(),
                                name: env.clone(),
                                description: format!("usada pelo MCP {name}"),
                                path: None,
                                mcp: None,
                                has_value: false,
                            };
                            if let Err(e) = catalog.upsert(entry) {
                                return error(e);
                            }
                        }
                    }
                }
                emit(self.catalog_message());
                // On in that session, with the envs it references.
                {
                    let mut sessions = self.sessions.lock().unwrap();
                    let Some(mut profile) = sessions.profile(&session).cloned() else {
                        return vec![DaemonMessage::Error { message: format!("sessão desconhecida: {session}") }];
                    };
                    profile.mcp_servers.insert(name.clone(), config);
                    for env in &needs {
                        if !profile.env_names.contains(env) {
                            profile.env_names.push(env.clone());
                        }
                    }
                    if let Err(e) = sessions.apply_profile(&session, profile) {
                        return error(e);
                    }
                    emit(DaemonMessage::Sessions { sessions: sessions.list() });
                }
                let note = format!("O usuário aprovou o MCP {name}; a sessão reiniciou com ele.");
                self.deliver("harness", &session, &note);
                emit(DaemonMessage::McpRequestResolved { id, approved: true });
            }
            ClientMessage::ScanMcpImports => return vec![self.mcp_imports()],
            ClientMessage::ListConnectors { account_id } => {
                let (claude, dir) = {
                    let sessions = self.sessions.lock().unwrap();
                    let Some(a) = sessions.account(&account_id) else {
                        return vec![DaemonMessage::Error { message: format!("conta desconhecida: {account_id}") }];
                    };
                    (sessions.claude().to_string(), a.config_dir.clone())
                };
                let events = self.events.clone();
                // It checks each connector: off the message loop.
                std::thread::spawn(move || {
                    let reply = match crate::connectors::list(&claude, dir.as_deref()) {
                        Ok(items) => DaemonMessage::Connectors { account_id, items },
                        Err(e) => DaemonMessage::Error { message: e.to_string() },
                    };
                    let _ = events.send(reply);
                });
            }
            ClientMessage::ImportMcps { keys } => {
                let scan = self.scan_imports();
                let secrets = self.sessions.lock().unwrap().secrets.clone();
                {
                    let mut catalog = self.catalog.lock().unwrap();
                    for s in scan.skills.iter().filter(|s| keys.contains(&s.key)) {
                        let path = s.path.display().to_string();
                        let list = catalog.list();
                        if list.iter().any(|e| e.kind == "skill" && e.path.as_deref() == Some(&path)) {
                            continue;
                        }
                        // Two skills may share a name: the id gets a number.
                        let base = format!("skill-{}", s.name);
                        let id = (1..)
                            .map(|n| if n == 1 { base.clone() } else { format!("{base}-{n}") })
                            .find(|id| !list.iter().any(|e| &e.id == id))
                            .unwrap_or(base);
                        let entry = CatalogEntry {
                            id,
                            kind: "skill".into(),
                            name: s.name.clone(),
                            description: if s.description.is_empty() { format!("importada de {}", s.label) } else { s.description.clone() },
                            path: Some(path),
                            mcp: None,
                            has_value: false,
                        };
                        if let Err(e) = catalog.upsert(entry) {
                            return error(e);
                        }
                    }
                    for f in scan.mcps.iter().filter(|f| keys.contains(&f.key)) {
                        let (config, values) = crate::mcp_import::sanitize(&f.name, &f.config);
                        for (env, value) in &values {
                            if let Err(e) = secrets.set(&crate::secrets::env_key(env), value) {
                                return error(e);
                            }
                            if !catalog.list().iter().any(|e| e.kind == "env" && &e.name == env) {
                                let entry = CatalogEntry {
                                    id: format!("env-{env}"),
                                    kind: "env".into(),
                                    name: env.clone(),
                                    description: format!("usada pelo MCP {}", f.name),
                                    path: None,
                                    mcp: None,
                                    has_value: false,
                                };
                                if let Err(e) = catalog.upsert(entry) {
                                    return error(e);
                                }
                            }
                        }
                        let id = catalog
                            .list()
                            .into_iter()
                            .find(|e| e.kind == "mcp" && e.name == f.name)
                            .map_or_else(|| format!("mcp-{}", f.name), |e| e.id);
                        let entry = CatalogEntry {
                            id,
                            kind: "mcp".into(),
                            name: f.name.clone(),
                            description: format!("importado de {}", f.label),
                            path: None,
                            mcp: Some(config),
                            has_value: false,
                        };
                        if let Err(e) = catalog.upsert(entry) {
                            return error(e);
                        }
                    }
                }
                emit(self.catalog_message());
                return vec![self.mcp_imports()];
            }
            ClientMessage::SavePlan { plan } => {
                let mut plans = self.plans.lock().unwrap();
                if let Err(e) = plans.save_from_app(plan) {
                    return error(e);
                }
                emit(DaemonMessage::Plans { plans: plans.docs.clone() });
            }
            ClientMessage::RemovePlan { id, force } => {
                let mut plans = self.plans.lock().unwrap();
                let active = plans.runs.iter().any(|r| r.plan_id == id && r.active());
                if active && !force {
                    return vec![DaemonMessage::Error { message: "o plano tem cards em execução".into() }];
                }
                // Its sessions go with it: cards, planner, learners.
                let mut ending: Vec<String> = plans
                    .runs
                    .iter()
                    .filter(|r| r.plan_id == id)
                    .flat_map(|r| r.cards.iter().filter_map(|c| c.session_id.clone()))
                    .collect();
                ending.extend(plans.docs.iter().filter(|d| d.id == id).filter_map(|d| d.planner.clone()));
                ending.extend(plans.learners.iter().filter(|(_, (p, _))| *p == id).map(|(s, _)| s.clone()));
                plans.learners.retain(|_, (p, _)| *p != id);
                if !ending.is_empty() {
                    let mut sessions = self.sessions.lock().unwrap();
                    for s in &ending {
                        self.language_servers.stop(s);
                        sessions.stop(s);
                    }
                    emit(DaemonMessage::Sessions { sessions: sessions.list() });
                }
                if let Err(e) = plans.remove(&id) {
                    return error(e);
                }
                emit(DaemonMessage::Plans { plans: plans.docs.clone() });
            }
            ClientMessage::StartPlan { plan_id, account_id, cards } => {
                let mut plans = self.plans.lock().unwrap();
                let Some(doc) = plans.docs.iter().find(|d| d.id == plan_id).cloned() else {
                    return vec![DaemonMessage::Error { message: format!("plano desconhecido: {plan_id}") }];
                };
                if plans.runs.iter().any(|r| r.plan_id == plan_id && r.active()) {
                    return vec![DaemonMessage::Error { message: "o plano já está em execução".into() }];
                }
                if self.sessions.lock().unwrap().account(&account_id).is_none() {
                    return vec![DaemonMessage::Error { message: format!("conta desconhecida: {account_id}") }];
                }
                if let Err(message) = Run::validate(&cards) {
                    return vec![DaemonMessage::Error { message }];
                }
                let mut run = Run::new(&plan_id, &doc.project_id, &account_id, cards);
                self.start_ready(&mut run);
                if let Err(e) = plans.save_run(&run) {
                    return error(e);
                }
                emit(run_message(&run));
                plans.runs.retain(|r| r.plan_id != plan_id);
                plans.runs.push(run);
            }
            ClientMessage::AskPlanner { plan_id, account_id, request } => {
                return match self.ask_planner(&plan_id, &account_id, &request) {
                    Ok(()) => Vec::new(),
                    Err(message) => vec![DaemonMessage::Error { message }],
                };
            }
            ClientMessage::TrustWorktrees { account_id } => {
                // Answering Claude Code's trust question here once covers
                // every worktree the harness creates inside.
                if let Err(e) = std::fs::create_dir_all(&self.git.worktrees) {
                    return error(e);
                }
                let mut sessions = self.sessions.lock().unwrap();
                if let Err(e) = sessions.create(&account_id, Some(self.git.worktrees.clone()), Profile::default(), 100, 30) {
                    return error(e);
                }
                emit(DaemonMessage::Sessions { sessions: sessions.list() });
            }
            ClientMessage::Learn { plan_id, account_id, notes, skills } => {
                return match self.start_learner(&plan_id, &account_id, &notes, &skills) {
                    Ok(()) => Vec::new(),
                    Err(message) => vec![DaemonMessage::Error { message }],
                };
            }
            ClientMessage::DecideLearning { plan_id, id, accept } => {
                return match self.decide_learning(&plan_id, &id, accept) {
                    Ok(()) => Vec::new(),
                    Err(message) => vec![DaemonMessage::Error { message }],
                };
            }
            // Only the sessions' hook asks, over the local socket (see serve).
            ClientMessage::Gate { .. } => {
                return vec![DaemonMessage::Error { message: "só pelo hook das sessões".into() }];
            }
            ClientMessage::ResolveApproval { id, approve } => {
                let Some((_, _, waiting)) = self.approvals.lock().unwrap().remove(&id) else {
                    return vec![DaemonMessage::Error { message: "aprovação não encontrada (o tempo pode ter acabado)".into() }];
                };
                let _ = waiting.send(approve);
                emit(DaemonMessage::ApprovalResolved { id, approved: approve });
            }
            ClientMessage::RemoveAccount { id } => {
                let Some(home) = &self.home else {
                    return vec![DaemonMessage::Error { message: "este daemon não edita contas".into() }];
                };
                if let Err(e) = crate::config::remove_account(&home.join("config.json"), &id) {
                    return error(e);
                }
                let known = {
                    let mut sessions = self.sessions.lock().unwrap();
                    sessions.remove_account(&id);
                    emit(DaemonMessage::Sessions { sessions: sessions.list() });
                    sessions.account_ids()
                };
                emit(DaemonMessage::Hello { accounts: known });
                emit(self.workspaces_message());
            }
            ClientMessage::LogoutAccount { id } => {
                let home = std::env::var("HOME").map(PathBuf::from).unwrap_or_default();
                let mut sessions = self.sessions.lock().unwrap();
                let s = match sessions.create(&id, Some(home), Profile::default(), 100, 30) {
                    Ok(s) => s,
                    Err(e) => return error(e),
                };
                emit(DaemonMessage::Sessions { sessions: sessions.list() });
                drop(sessions);
                // Typed once Claude Code is up: the command, then Enter.
                let all = self.sessions.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_secs(4));
                    if let Some(session) = all.lock().unwrap().session(&s.id) {
                        let _ = session.write(b"/logout");
                        std::thread::sleep(Duration::from_millis(300));
                        let _ = session.write(b"\r");
                    }
                });
            }
            ClientMessage::BrowseFolders { path, hidden } => {
                return match git::browse(path.as_deref(), hidden) {
                    Ok((path, parent, folders)) => vec![DaemonMessage::Folders { path, parent, folders }],
                    Err(e) => error(e),
                };
            }
            ClientMessage::ListDevices => {
                let devices = self.remote.get().map(|r| r.device_list(None)).unwrap_or_default();
                return vec![DaemonMessage::Devices { devices }];
            }
            ClientMessage::RevokeDevice { id } => {
                let Some(remote) = self.remote.get() else { return Vec::new() };
                match remote.revoke(&id) {
                    Ok(true) => emit(DaemonMessage::Devices { devices: remote.device_list(None) }),
                    Ok(false) => return vec![DaemonMessage::Error { message: "aparelho não encontrado".into() }],
                    Err(e) => return error(e),
                }
            }
            ClientMessage::ListMemory { workspace_id } => {
                let entries = self.memory.as_ref().map(|m| m.list(&workspace_id)).unwrap_or_default();
                return vec![DaemonMessage::Memory { workspace_id, entries }];
            }
            ClientMessage::ForgetMemory { workspace_id, id } => {
                let Some(memory) = &self.memory else { return Vec::new() };
                if let Err(e) = memory.forget(&workspace_id, &id) {
                    return error(e);
                }
                return vec![DaemonMessage::Memory { entries: memory.list(&workspace_id), workspace_id }];
            }
            ClientMessage::RetryCard { plan_id, number } => {
                let mut plans = self.plans.lock().unwrap();
                let Some(run) = plans.run_mut(&plan_id) else {
                    return vec![DaemonMessage::Error { message: "o plano não está em execução".into() }];
                };
                match run.card_mut(number) {
                    Some(c) if c.state == "failed" || c.state == "stopped" => {
                        c.state = "todo".into();
                        c.session_id = None;
                        c.note = None;
                    }
                    _ => return vec![DaemonMessage::Error { message: "só cards com falha ou parados voltam".into() }],
                }
                self.start_ready(run);
                let run = run.clone();
                if let Err(e) = plans.save_run(&run) {
                    return error(e);
                }
                emit(run_message(&run));
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
                        // Approvals come from you in the app, never from the
                        // socket the sessions' tools use.
                        ClientMessage::ResolveEnvRequest { .. }
                        | ClientMessage::ResolveMcpRequest { .. }
                        | ClientMessage::ResolveApproval { .. } => {
                            vec![DaemonMessage::Error { message: "aprovação só pelo app".into() }]
                        }
                        ClientMessage::Gate { session_id, tool, input } => vec![daemon.gate(&session_id, &tool, &input).await],
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
    /// Decides a session's tool call: ordinary work runs; a deploy or the
    /// like waits for your decision in the app (refused after
    /// APPROVAL_TIMEOUT).
    pub async fn gate(&self, session_id: &str, tool: &str, input: &serde_json::Value) -> DaemonMessage {
        // Every tool call passes here: the ones driving a device light it up.
        if crate::devices::platform_of_call(tool, input).is_some() {
            let (d, s, t, i) = (self.devices.clone(), session_id.to_string(), tool.to_string(), input.clone());
            std::thread::spawn(move || d.note_call(&s, &t, &i));
        }
        let Some(action) = crate::gates::needs_ok(tool, input) else {
            return DaemonMessage::GateDecision { allow: true, reason: String::new() };
        };
        if self.sessions.lock().unwrap().summary(session_id).is_none() {
            return DaemonMessage::GateDecision { allow: false, reason: "sessão desconhecida".into() };
        }
        let id = uuid::Uuid::new_v4().simple().to_string()[..12].to_string();
        let (tx, rx) = tokio::sync::oneshot::channel();
        self.approvals.lock().unwrap().insert(id.clone(), (session_id.into(), action.clone(), tx));
        let _ = self.events.send(DaemonMessage::Approval { id: id.clone(), session_id: session_id.into(), action: action.clone() });
        let decided = tokio::time::timeout(APPROVAL_TIMEOUT, rx).await;
        let approved = matches!(decided, Ok(Ok(true)));
        if decided.is_err() {
            self.approvals.lock().unwrap().remove(&id);
            let _ = self.events.send(DaemonMessage::ApprovalResolved { id, approved: false });
        }
        DaemonMessage::GateDecision {
            allow: approved,
            reason: match decided {
                Ok(Ok(true)) => String::new(),
                Ok(_) => format!("O usuário recusou: {action}. Não tente de novo por outro caminho; pergunte o que fazer."),
                Err(_) => format!("Sem resposta do usuário em 10 minutos: {action}. Peça o OK antes de tentar de novo."),
            },
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

/// Claude Code asks whether to trust a new folder before anything else.
/// Trusting a folder covers the ones inside it.
fn asks_trust(snap: &GridSnapshot) -> bool {
    (0..snap.rows as usize).any(|r| snap.line_text(r).contains("trust this folder"))
}

fn no_session() -> Vec<DaemonMessage> {
    vec![DaemonMessage::Error { message: "sessão desconhecida".into() }]
}

fn run_message(run: &Run) -> DaemonMessage {
    DaemonMessage::PlanRun { plan_id: run.plan_id.clone(), cards: run.cards.clone() }
}

/// `gh pr view` of `branch` (as the account in `gh_dir`), if there is a PR.
fn gh_pr(cwd: &std::path::Path, branch: &str, gh_dir: Option<&std::path::Path>) -> Option<serde_json::Value> {
    let mut cmd = std::process::Command::new("gh");
    cmd.current_dir(cwd).args([
        "pr", "view", branch, "--json",
        "number,title,state,url,isDraft,reviewDecision,statusCheckRollup",
    ]);
    match gh_dir {
        Some(dir) => cmd.env("GH_CONFIG_DIR", dir),
        None => cmd.env_remove("GH_CONFIG_DIR"),
    };
    cmd.output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| serde_json::from_slice(&o.stdout).ok())
}

fn set_owner_only(path: &std::path::Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}

#[cfg(test)]
mod mcp_request_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn mcp_configs_carry_references_not_secrets() {
        let ok = json!({ "type": "http", "url": "https://x/mcp", "headers": { "Authorization": "Bearer ${X_TOKEN}" } });
        assert_eq!(check_mcp_request("x", &ok), Ok(()));
        assert_eq!(env_refs(&ok), ["X_TOKEN"]);
        let refs = json!({ "command": "a", "args": ["${A}", "--b=${B:-1}"], "env": { "A": "${A}" } });
        assert_eq!(env_refs(&refs), ["A", "B"]);
        assert!(check_mcp_request("x", &json!({ "command": "a", "env": { "K": "secret" } })).is_err());
        assert!(check_mcp_request("x", &json!({ "args": [] })).is_err());
        assert!(check_mcp_request("../x", &json!({ "command": "a" })).is_err());
    }
}
