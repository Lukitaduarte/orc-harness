//! The daemon's state and the local socket the helper binaries talk to
//! (one JSON message per line). Remote clients (the app) reach the same
//! `Daemon::handle` through iroh.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use orc_protocol::{BrowserAction, ClientMessage, DaemonMessage, ProjectInfo, Profile};
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
    /// Everything clients should see; each connection subscribes.
    pub events: broadcast::Sender<DaemonMessage>,
    /// Set once iroh is up; mints pairing tickets for `orcd pair`.
    pub remote: Arc<OnceLock<Remote>>,
    /// Workspace browsers, and the address each open one is at.
    pub browsers: Arc<Browsers>,
    browser_urls: Arc<Mutex<HashMap<String, String>>>,
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
            events: broadcast::channel(1024).0,
            remote: Arc::default(),
            browsers: Arc::new(Browsers::new(PathBuf::new(), None)),
            browser_urls: Arc::default(),
        }
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
                    profile.mcp_servers.insert(
                        "browser".into(),
                        serde_json::json!({
                            "command": "npx",
                            "args": ["-y", PLAYWRIGHT_MCP, "--cdp-endpoint", b.cdp_http],
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
        let (plan_docs, runs) = {
            let plans = self.plans.lock().unwrap();
            let runs: Vec<_> = plans.runs.iter().map(run_message).collect();
            (plans.docs.clone(), runs)
        };
        let sessions = self.sessions.lock().unwrap();
        let mut out = vec![
            DaemonMessage::Hello { accounts: sessions.account_ids() },
            DaemonMessage::Sessions { sessions: sessions.list() },
            catalog,
            DaemonMessage::Projects { projects: self.projects.lock().unwrap().list() },
            DaemonMessage::Plans { plans: plan_docs },
        ];
        for (profile, url) in self.browser_urls.lock().unwrap().iter() {
            out.push(DaemonMessage::BrowserState { profile: profile.clone(), open: true, url: url.clone() });
        }
        out.extend(runs);
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
        for spec in ready {
            let started = project
                .as_ref()
                .ok_or_else(|| std::io::Error::other("o projeto do plano foi removido"))
                .and_then(|project| {
                    let path = self.worktree(project, &spec.branch)?;
                    let profile = Profile { model: spec.model.clone(), ..Profile::default() };
                    self.sessions.lock().unwrap().create_with_prompt(
                        &run.account_id,
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
                }
                Err(e) => {
                    card.state = "failed".into();
                    card.note = Some(e.to_string());
                }
            }
        }
        let _ = self.events.send(DaemonMessage::Sessions { sessions: self.sessions.lock().unwrap().list() });
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
                changed.push(plan);
            }
        }
        for plan in changed {
            let Some(run) = plans.run_mut(&plan) else { continue };
            self.start_ready(run);
            let run = run.clone();
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

    /// Polls plans every `every`, off the async runtime.
    pub async fn watch_plans(self, every: Duration) {
        let mut tick = tokio::time::interval(every);
        loop {
            tick.tick().await;
            let d = self.clone();
            let _ = tokio::task::spawn_blocking(move || d.poll_plans()).await;
        }
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
            ClientMessage::Browser { profile, action } => {
                let Ok(rt) = tokio::runtime::Handle::try_current() else {
                    return vec![DaemonMessage::Error { message: "navegador indisponível aqui".into() }];
                };
                let d = self.clone();
                rt.spawn(async move {
                    if let Err(message) = d.browser_action(&profile, action).await {
                        let _ = d.events.send(DaemonMessage::Error { message });
                    }
                });
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
            ClientMessage::SavePlan { plan } => {
                let mut plans = self.plans.lock().unwrap();
                if let Err(e) = plans.save_from_app(plan) {
                    return error(e);
                }
                emit(DaemonMessage::Plans { plans: plans.docs.clone() });
            }
            ClientMessage::RemovePlan { id } => {
                let mut plans = self.plans.lock().unwrap();
                if plans.runs.iter().any(|r| r.plan_id == id && r.active()) {
                    return vec![DaemonMessage::Error { message: "o plano tem cards em execução".into() }];
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
                        ClientMessage::ResolveEnvRequest { .. } => vec![DaemonMessage::Error {
                            message: "aprovação só pelo app".into(),
                        }],
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

/// Claude Code asks whether to trust a new folder before anything else.
/// Trusting a folder covers the ones inside it.
fn asks_trust(snap: &GridSnapshot) -> bool {
    (0..snap.rows as usize).any(|r| snap.line_text(r).contains("trust this folder"))
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
