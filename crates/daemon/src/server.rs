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

use crate::manager::SessionManager;
use crate::quota::QuotaStore;
use crate::remote::Remote;

#[derive(Clone)]
pub struct Daemon {
    pub quotas: Arc<Mutex<QuotaStore>>,
    pub sessions: Arc<Mutex<SessionManager>>,
    /// Everything clients should see; each connection subscribes.
    pub events: broadcast::Sender<DaemonMessage>,
    /// Set once iroh is up; mints pairing tickets for `orcd pair`.
    pub remote: Arc<OnceLock<Remote>>,
}

impl Daemon {
    pub fn new(sessions: SessionManager) -> Self {
        Self {
            quotas: Arc::default(),
            sessions: Arc::new(Mutex::new(sessions)),
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
        let sessions = self.sessions.lock().unwrap();
        let mut out = vec![
            DaemonMessage::Hello { accounts: sessions.account_ids() },
            DaemonMessage::Sessions { sessions: sessions.list() },
        ];
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
                            Some(r) => vec![DaemonMessage::PairingTicket { ticket: r.new_ticket().encode() }],
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

fn set_owner_only(path: &std::path::Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}
