//! Daemon and client over a real iroh connection on this machine.

use std::sync::mpsc;
use std::time::Duration;

use orc_client_core::{Identity, connect, pair};
use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::remote::{Devices, Remote};
use orc_daemon::server::Daemon;
use orc_protocol::{DaemonMessage, GridSnapshot};

async fn start_daemon(dir: &std::path::Path) -> (Daemon, Remote) {
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\necho hello from fake\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let daemon = Daemon::new(SessionManager::new(
        ManagerConfig {
            claude: fake.display().to_string(),
            statusline: "/bin/true".into(),
            hook: "/bin/true".into(),
            runtime_root: dir.join("sessions"),
            socket: dir.join("orcd.sock"),
            otlp_metrics: None,
            orc_mcp: None,
        },
        vec![Account { id: "work-main".into(), config_dir: None, gh_config_dir: None }],
        std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
    ), orc_daemon::catalog::Catalog::load(dir).unwrap(), orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::server::GitPaths {
            worktrees: dir.join("worktrees"),
            hooks: dir.join("hooks"),
            commit_check: "/usr/bin/true".into(),
        });
    let key = orc_link::load_or_create_key(&dir.join("daemon.key")).unwrap();
    let endpoint = orc_link::endpoint(key, &[orc_link::ALPN_PAIR, orc_link::ALPN_MAIN])
        .await
        .unwrap();
    let remote = Remote::new(endpoint, Devices::load(dir.join("devices.json")));
    let _ = daemon.remote.set(remote.clone());
    tokio::spawn(remote.clone().serve(daemon.clone()));
    tokio::spawn(daemon.clone().stream_grids());
    (daemon, remote)
}

/// Waits for a daemon message matching `pick`.
fn wait<T>(rx: &mpsc::Receiver<String>, mut pick: impl FnMut(DaemonMessage) -> Option<T>) -> T {
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    loop {
        let left = deadline.saturating_duration_since(std::time::Instant::now());
        let line = rx.recv_timeout(left).expect("timed out waiting for the daemon");
        if let Some(t) = serde_json::from_str(&line).ok().and_then(&mut pick) {
            return t;
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn pair_connect_create_and_see_the_terminal() {
    let dir = tempfile::tempdir().unwrap();
    let (_daemon, remote) = start_daemon(dir.path()).await;

    let t = remote.new_ticket().await;
    assert!(
        t.addr.addrs.iter().any(|a| matches!(a, iroh::TransportAddr::Ip(ip) if ip.ip().is_loopback())),
        "the ticket must carry loopback for same-machine clients"
    );
    let ticket = t.encode();
    let identity = pair(&ticket, "teste").await.expect("pairing failed");
    // The ticket works once.
    assert!(pair(&ticket, "intruso").await.is_err());

    let (tx, rx) = mpsc::channel();
    let conn = connect(&identity, move |m| { let _ = tx.send(m); }, |_| {})
        .await
        .unwrap();
    let accounts = wait(&rx, |m| match m {
        DaemonMessage::Hello { accounts } => Some(accounts),
        _ => None,
    });
    assert_eq!(accounts, ["work-main"]);

    conn.send(
        serde_json::json!({
            "type": "create_session", "account_id": "work-main",
            "cwd": dir.path(), "profile": {}, "cols": 60, "rows": 12
        })
        .to_string(),
    )
    .await
    .unwrap();
    let session_id = wait(&rx, |m| match m {
        DaemonMessage::Sessions { sessions } => sessions.first().map(|s| s.id.clone()),
        _ => None,
    });

    // The screen arrives as grid diffs, rebuilt here like the app does.
    let mut screen = GridSnapshot::default();
    let has = |screen: &GridSnapshot, text: &str| {
        (0..screen.rows as usize).any(|r| screen.line_text(r).contains(text))
    };
    wait(&rx, |m| match m {
        DaemonMessage::GridDiff { session_id: s, diff } if s == session_id => {
            screen.apply(&diff);
            has(&screen, "hello from fake").then_some(())
        }
        _ => None,
    });

    conn.send(
        serde_json::json!({ "type": "input", "session_id": session_id, "data": "ping\r" }).to_string(),
    )
    .await
    .unwrap();
    wait(&rx, |m| match m {
        DaemonMessage::GridDiff { session_id: s, diff } if s == session_id => {
            screen.apply(&diff);
            has(&screen, "ping").then_some(())
        }
        _ => None,
    });
    assert_eq!((screen.cols, screen.rows), (60, 12));
}

#[tokio::test(flavor = "multi_thread")]
async fn unpaired_devices_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let (_daemon, remote) = start_daemon(dir.path()).await;
    // A well-formed identity whose key was never paired.
    let stranger = Identity {
        device_key: orc_link::key_to_hex(&iroh::SecretKey::generate()),
        // The address a real client has: the ticket's (with loopback).
        daemon: remote.new_ticket().await.addr,
    };
    let (tx, rx) = mpsc::channel();
    let (closed_tx, closed_rx) = mpsc::channel();
    let result = connect(
        &serde_json::to_string(&stranger).unwrap(),
        move |m| { let _ = tx.send(m); },
        move |reason| { let _ = closed_tx.send(reason); },
    )
    .await;
    if let Ok(_conn) = result {
        closed_rx.recv_timeout(Duration::from_secs(10)).expect("stranger was not disconnected");
    }
    assert!(rx.try_recv().is_err(), "stranger received daemon data");
}
