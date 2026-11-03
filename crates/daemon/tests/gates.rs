//! Deploys wait for your OK: the real orc-hook, as Claude Code runs it on
//! PreToolUse, against a running daemon.

use std::io::Write;
use std::path::Path;
use std::process::{Command, Output, Stdio};
use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage};
use serde_json::json;

fn hook(socket: &Path, session: &str, command: &str) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_orc-hook"))
        .arg("PreToolUse")
        .env("ORC_SOCKET", socket)
        .env("ORC_SESSION", session)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let input = json!({ "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": { "command": command } });
    child.stdin.take().unwrap().write_all(input.to_string().as_bytes()).unwrap();
    child.wait_with_output().unwrap()
}

#[tokio::test(flavor = "multi_thread")]
async fn deploys_wait_for_your_ok() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let socket = dir.join("orcd.sock");
    let daemon = Daemon::new(
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
    let mut events = daemon.events.subscribe();
    tokio::spawn(daemon.clone().serve(socket.clone()));
    while !socket.exists() {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    daemon.handle(ClientMessage::CreateSession { account_id: "work".into(), cwd: Some(dir.display().to_string()), profile: Default::default(), cols: 80, rows: 24 });
    let sid = daemon.sessions.lock().unwrap().list()[0].id.clone();

    // Everyday work runs right away.
    let (s, sock) = (sid.clone(), socket.clone());
    let out = tokio::task::spawn_blocking(move || hook(&sock, &s, "flutter test")).await.unwrap();
    assert!(out.status.success());

    // A deploy waits; you approve it in the app.
    let next_approval = async |events: &mut tokio::sync::broadcast::Receiver<DaemonMessage>| loop {
        if let DaemonMessage::Approval { id, action, .. } = tokio::time::timeout(Duration::from_secs(10), events.recv()).await.unwrap().unwrap() {
            return (id, action);
        }
    };
    let (s, sock) = (sid.clone(), socket.clone());
    let waiting = tokio::task::spawn_blocking(move || hook(&sock, &s, "railway up --service api"));
    let (id, action) = next_approval(&mut events).await;
    assert!(action.starts_with("deploy no Railway"), "{action}");
    assert!(daemon.hello().iter().any(|m| matches!(m, DaemonMessage::Approval { .. })), "a new app sees it");
    // The sessions' socket cannot approve.
    {
        use tokio::io::{AsyncBufReadExt, AsyncWriteExt};
        let stream = tokio::net::UnixStream::connect(&socket).await.unwrap();
        let (read, mut write) = stream.into_split();
        let msg = serde_json::to_string(&ClientMessage::ResolveApproval { id: id.clone(), approve: true }).unwrap();
        write.write_all(format!("{msg}\n").as_bytes()).await.unwrap();
        let line = tokio::io::BufReader::new(read).lines().next_line().await.unwrap().unwrap();
        assert!(line.contains("aprovação só pelo app"));
    }
    assert!(!waiting.is_finished());
    daemon.handle(ClientMessage::ResolveApproval { id, approve: true });
    assert!(waiting.await.unwrap().status.success());

    // Refused: blocked, and Claude is told why.
    let (s, sock) = (sid.clone(), socket.clone());
    let waiting = tokio::task::spawn_blocking(move || hook(&sock, &s, "gh pr merge 3 --squash"));
    let (id, _) = next_approval(&mut events).await;
    daemon.handle(ClientMessage::ResolveApproval { id, approve: false });
    let out = waiting.await.unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("recusou"));

    // No daemon: a deploy is blocked, never let through.
    let s = sid.clone();
    let out = tokio::task::spawn_blocking(move || hook(Path::new("/nonexistent/orcd.sock"), &s, "firebase deploy")).await.unwrap();
    assert_eq!(out.status.code(), Some(2));
}
