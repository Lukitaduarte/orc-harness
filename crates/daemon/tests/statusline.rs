//! End to end: Claude Code runs `orc-statusline` with its JSON on stdin; the
//! daemon gets the account's quota over the local socket.

use std::io::Write;
use std::process::{Command, Stdio};
use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::Daemon;
use orc_protocol::DaemonMessage;

const INPUT: &str = r#"{
  "session_id": "abc123",
  "model": { "display_name": "Opus" },
  "rate_limits": {
    "five_hour": { "used_percentage": 62.4, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 38.0, "resets_at": 1738857600 }
  }
}"#;

fn run_helper(socket: &std::path::Path, input: &str) -> String {
    let mut child = Command::new(env!("CARGO_BIN_EXE_orc-statusline"))
        .env("ORC_SOCKET", socket)
        .env("ORC_ACCOUNT", "work-main")
        .env("ORC_SESSION", "api")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input.as_bytes()).unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success());
    String::from_utf8(out.stdout).unwrap()
}

fn daemon(dir: &std::path::Path, socket: &std::path::Path) -> Daemon {
    // `cat` stands in for claude: it ignores nothing and waits.
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    Daemon::new(SessionManager::new(
        ManagerConfig {
            claude: fake.display().to_string(),
            statusline: env!("CARGO_BIN_EXE_orc-statusline").into(),
            hook: env!("CARGO_BIN_EXE_orc-hook").into(),
            runtime_root: dir.join("sessions"),
            socket: socket.to_path_buf(),
            otlp_metrics: None,
        },
        vec![Account { id: "work-main".into(), config_dir: None, gh_config_dir: None }],
        std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
    ), orc_daemon::catalog::Catalog::load(dir).unwrap(), orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::server::GitPaths {
            worktrees: dir.join("worktrees"),
            hooks: dir.join("hooks"),
            commit_check: env!("CARGO_BIN_EXE_orc-commit-check").into(),
        })
}

#[tokio::test]
async fn statusline_reports_reach_the_daemon() {
    let dir = tempfile::tempdir().unwrap();
    let socket = dir.path().join("orcd.sock");
    let daemon = daemon(dir.path(), &socket);
    let mut events = daemon.events.subscribe();
    tokio::spawn(daemon.clone().serve(socket.clone()));
    while !socket.exists() {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    let printed = tokio::task::spawn_blocking({
        let socket = socket.clone();
        move || run_helper(&socket, INPUT)
    })
    .await
    .unwrap();
    assert_eq!(printed.trim(), "Opus · 5h 62% · 7d 38%");

    let event = tokio::time::timeout(Duration::from_secs(5), events.recv())
        .await
        .expect("no quota event")
        .unwrap();
    let DaemonMessage::Quota { account_id, limits, .. } = event else {
        panic!("unexpected event");
    };
    assert_eq!(account_id, "work-main");
    assert_eq!(limits.five_hour.unwrap().used_percentage, 62.4);
    assert_eq!(daemon.quotas.lock().unwrap().get("work-main").unwrap().limits, limits);
}

#[test]
fn helper_never_fails_without_a_daemon() {
    let printed = run_helper(std::path::Path::new("/nonexistent/orcd.sock"), "not json");
    assert_eq!(printed.trim(), "");
}

#[tokio::test]
async fn hooks_move_the_session_state() {
    use orc_protocol::{ClientMessage, Profile, SessionState};

    let dir = tempfile::tempdir().unwrap();
    let socket = dir.path().join("orcd.sock");
    let daemon = daemon(dir.path(), &socket);
    let mut events = daemon.events.subscribe();
    tokio::spawn(daemon.clone().serve(socket.clone()));
    while !socket.exists() {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    daemon.handle(ClientMessage::CreateSession {
        account_id: "work-main".into(),
        cwd: Some(dir.path().display().to_string()),
        profile: Profile::default(),
        cols: 80,
        rows: 24,
    });
    let session_id = daemon.sessions.lock().unwrap().list()[0].id.clone();

    for (event, expected) in [
        ("UserPromptSubmit", SessionState::Running),
        ("Notification", SessionState::WaitingInput),
        ("Stop", SessionState::Idle),
    ] {
        let status = Command::new(env!("CARGO_BIN_EXE_orc-hook"))
            .arg(event)
            .env("ORC_SOCKET", &socket)
            .env("ORC_SESSION", &session_id)
            .stdin(Stdio::null())
            .status()
            .unwrap();
        assert!(status.success());
        let state = loop {
            match tokio::time::timeout(Duration::from_secs(5), events.recv()).await {
                Ok(Ok(DaemonMessage::SessionState { state, .. })) => break state,
                Ok(Ok(_)) => continue,
                other => panic!("no state event: {other:?}"),
            }
        };
        assert_eq!(state, expected);
    }
}
