//! A session stuck on Claude Code's folder trust question shows as waiting
//! for you; "trust worktrees" opens a session in the worktrees folder.

use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage, SessionState};

#[tokio::test(flavor = "multi_thread")]
async fn the_trust_question_waits_for_you() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\necho ' ❯ No, exit'\necho '   Yes, I trust this folder'\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let daemon = Daemon::new(
        SessionManager::new(
            ManagerConfig {
                claude: fake.display().to_string(),
                statusline: "/usr/bin/true".into(),
                hook: "/usr/bin/true".into(),
                runtime_root: dir.join("sessions"),
                socket: dir.join("orcd.sock"),
                otlp_metrics: None,
                orc_mcp: None,
            },
            vec![Account { id: "work".into(), config_dir: None, gh_config_dir: None }],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    );
    let mut events = daemon.events.subscribe();
    tokio::spawn(daemon.clone().stream_grids());
    assert!(daemon.handle(ClientMessage::TrustWorktrees { account_id: "work".into() }).is_empty());
    let s = daemon.sessions.lock().unwrap().list()[0].clone();
    assert_eq!(std::path::Path::new(&s.cwd), dir.join("worktrees"));
    loop {
        match tokio::time::timeout(Duration::from_secs(10), events.recv()).await.unwrap().unwrap() {
            DaemonMessage::SessionState { session_id, state } => {
                assert_eq!((session_id, state), (s.id.clone(), SessionState::WaitingInput));
                break;
            }
            _ => continue,
        }
    }
}
