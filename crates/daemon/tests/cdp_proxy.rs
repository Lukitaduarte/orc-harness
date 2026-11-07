//! Agents reach the workspace browser through the daemon's CDP proxy, with
//! the real Chrome (skipped when none is installed): the app learns which
//! session drives it, and when it stops.

use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use orc_daemon::browser::{Browsers, find_chrome};
use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn get(port: u16, path: &str) -> String {
    let mut s = tokio::net::TcpStream::connect(("127.0.0.1", port)).await.unwrap();
    s.write_all(format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n").as_bytes()).await.unwrap();
    let mut out = String::new();
    s.read_to_string(&mut out).await.unwrap();
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn agents_drive_the_browser_through_the_daemon() {
    let Some(chrome) = find_chrome(std::env::var("ORC_BROWSER").ok().as_deref()) else {
        eprintln!("sem Chrome: teste pulado");
        return;
    };
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let daemon = Daemon::new(
        SessionManager::new(
            ManagerConfig {
                claude: "/bin/cat".into(),
                statusline: "/usr/bin/true".into(),
                hook: "/usr/bin/true".into(),
                runtime_root: dir.join("sessions"),
                socket: dir.join("orcd.sock"),
                otlp_metrics: None,
                orc_mcp: None,
            },
            vec![Account { id: "w".into(), config_dir: None, gh_config_dir: None }],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    )
    .with_browsers(Browsers::new(dir.join("browsers"), Some(chrome)));
    let mut events = daemon.events.subscribe();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let _ = daemon.cdp_proxy_port.set(port);
    tokio::spawn(orc_daemon::cdp_proxy::serve(listener, daemon.clone()));
    daemon.handle(ClientMessage::CreateSession { account_id: "w".into(), cwd: Some(dir.display().to_string()), profile: Default::default(), cols: 80, rows: 24 });
    let sid = daemon.sessions.lock().unwrap().list()[0].id.clone();

    // Unknown sessions stay out.
    assert!(get(port, "/orc/live/s999/json/version").await.starts_with("HTTP/1.1 403"));

    // What Playwright's connectOverCDP does: /json/version, then the WebSocket
    // it names, which points back at the proxy.
    let version = get(port, &format!("/orc/live/{sid}/json/version")).await;
    let body = version.split("\r\n\r\n").nth(1).unwrap();
    let ws: serde_json::Value = serde_json::from_str(body).unwrap();
    let url = ws["webSocketDebuggerUrl"].as_str().unwrap().to_string();
    assert!(url.starts_with(&format!("ws://127.0.0.1:{port}/orc/live/{sid}/devtools/browser/")), "{url}");
    let (mut socket, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    socket.send(tokio_tungstenite::tungstenite::Message::text(r#"{"id":1,"method":"Browser.getVersion"}"#)).await.unwrap();
    let reply = loop {
        if let Some(Ok(tokio_tungstenite::tungstenite::Message::Text(t))) = socket.next().await
            && t.contains("\"id\":1")
        {
            break t;
        }
    };
    assert!(reply.contains("product"), "{reply}");

    // The app hears who drives it, and when it stops.
    let next_use = async |events: &mut tokio::sync::broadcast::Receiver<DaemonMessage>| loop {
        if let DaemonMessage::BrowserUse { profile, session_id } = tokio::time::timeout(Duration::from_secs(15), events.recv()).await.unwrap().unwrap() {
            return (profile, session_id);
        }
    };
    assert_eq!(next_use(&mut events).await, ("live".to_string(), Some(sid.clone())));
    assert!(daemon.hello().iter().any(|m| matches!(m, DaemonMessage::BrowserUse { session_id: Some(_), .. })));
    assert_eq!(next_use(&mut events).await, ("live".to_string(), None), "idle after a few seconds");
    drop(socket);
    daemon.browsers.close("live").await;
}
