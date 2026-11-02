//! Local socket the helper binaries talk to. One JSON message per line.
//!
//! This is the daemon's local side only (statusLine and hooks run on the
//! same machine). Clients like the app reach the daemon through iroh, in the
//! next slice.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use orc_protocol::{ClientMessage, DaemonMessage};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::net::UnixListener;
use tokio::sync::broadcast;

use crate::quota::QuotaStore;

#[derive(Clone)]
pub struct Daemon {
    pub quotas: Arc<Mutex<QuotaStore>>,
    pub events: broadcast::Sender<DaemonMessage>,
}

impl Default for Daemon {
    fn default() -> Self {
        Self {
            quotas: Arc::default(),
            events: broadcast::channel(256).0,
        }
    }
}

impl Daemon {
    pub fn handle(&self, msg: ClientMessage) {
        match msg {
            ClientMessage::Status(report) => {
                let changed = self.quotas.lock().unwrap().ingest(&report).cloned();
                if let Some(q) = changed {
                    let _ = self.events.send(DaemonMessage::Quota {
                        account_id: report.account_id,
                        limits: q.limits,
                        read_at: q.read_at,
                    });
                }
            }
            // Session input, resize and snapshots arrive with the session
            // manager in the next slice.
            ClientMessage::Input { .. }
            | ClientMessage::Resize { .. }
            | ClientMessage::Snapshot { .. } => {}
        }
    }

    /// Serves the local socket until the task is dropped. The socket file is
    /// created owner-only: only this user's processes can report.
    pub async fn serve(self, path: PathBuf) -> std::io::Result<()> {
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path)?;
        set_owner_only(&path)?;
        loop {
            let (stream, _) = listener.accept().await?;
            let daemon = self.clone();
            tokio::spawn(async move {
                let mut lines = BufReader::new(stream).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    // Malformed lines are dropped; a helper bug must not take
                    // the daemon down.
                    if let Ok(msg) = serde_json::from_str::<ClientMessage>(&line) {
                        daemon.handle(msg);
                    }
                }
            });
        }
    }
}

#[cfg(unix)]
fn set_owner_only(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}
