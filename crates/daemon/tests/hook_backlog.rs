//! A session's first hook can come before the daemon serves its socket (a
//! restart resumes sessions while the Keychain and iroh start): bound
//! first, the socket keeps it until the daemon reads it.

use std::io::Write;
use std::time::{Duration, Instant};

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths, bind_socket};
use orc_protocol::{ClientMessage, Profile, SessionState};

#[tokio::test(flavor = "multi_thread")]
async fn a_hook_sent_before_the_daemon_serves_is_not_lost() {
    let tmp = tempfile::tempdir().unwrap();
    let dir = tmp.path();
    let socket = dir.join("orcd.sock");
    let d = Daemon::new(
        SessionManager::new(
            ManagerConfig {
                claude: "/bin/cat".into(),
                statusline: "/usr/bin/true".into(),
                hook: "/usr/bin/true".into(),
                runtime_root: dir.join("sessions"),
                socket: socket.clone(),
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
    let listener = bind_socket(&socket).unwrap();
    let id = d.sessions.lock().unwrap().create("work", Some(dir.into()), Profile::default(), 80, 10).unwrap().id;

    // The hook arrives while nobody accepts yet.
    let msg = serde_json::to_string(&ClientMessage::Hook { session_id: id.clone(), event: "SessionStart".into() }).unwrap();
    let mut s = std::os::unix::net::UnixStream::connect(&socket).unwrap();
    s.write_all(format!("{msg}\n").as_bytes()).unwrap();
    drop(s);
    let state = |d: &Daemon| d.sessions.lock().unwrap().summary(&id).unwrap().state;
    assert_eq!(state(&d), SessionState::Starting);

    tokio::spawn(d.clone().serve_on(listener));
    let until = Instant::now() + Duration::from_secs(5);
    while state(&d) != SessionState::Idle {
        assert!(Instant::now() < until, "the early SessionStart was lost");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}
