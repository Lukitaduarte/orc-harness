//! The workspace browser with the real Chrome (skipped when none is
//! installed): frames stream, the pane's mouse and keys reach the page,
//! cookies survive closing it, and a session asking for it gets the
//! browser MCP attached to it.

use std::io::{Read, Write};
use std::time::Duration;

use orc_daemon::browser::{Browsers, find_chrome};
use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{BrowserAction, ClientMessage, DaemonMessage, Profile};
use serde_json::json;
use tokio::sync::broadcast::Receiver;

const PAGE: &str = "<title>orc</title><input id=q style='position:absolute;left:10px;top:10px;width:200px;height:30px'>";

/// Serves PAGE on 127.0.0.1 (cookies need a real origin).
fn serve_page() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for mut s in listener.incoming().flatten() {
            let mut buf = [0u8; 2048];
            let _ = s.read(&mut buf);
            let _ = write!(s, "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\n\r\n{PAGE}", PAGE.len());
        }
    });
    port
}

async fn until<T>(events: &mut Receiver<DaemonMessage>, mut pick: impl FnMut(DaemonMessage) -> Option<T>) -> T {
    loop {
        let m = tokio::time::timeout(Duration::from_secs(20), events.recv()).await.expect("timeout").unwrap();
        if let DaemonMessage::Error { message } = &m {
            panic!("daemon error: {message}");
        }
        if let Some(t) = pick(m) {
            return t;
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn workspace_browser_streams_takes_input_and_keeps_cookies() {
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
            vec![Account { id: "work".into(), config_dir: None, gh_config_dir: None }],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    )
    .with_browsers(Browsers::new(dir.join("browsers"), Some(chrome.clone())));
    let mut events = daemon.events.subscribe();
    let port = serve_page();
    let url = format!("http://127.0.0.1:{port}/");
    let browser = |action| daemon.handle(ClientMessage::Browser { profile: "work".into(), action });

    assert!(browser(BrowserAction::Open { url: Some(url.clone()) }).is_empty());
    until(&mut events, |m| matches!(m, DaemonMessage::BrowserState { url: ref u, .. } if *u == url).then_some(())).await;
    let (w, h) = until(&mut events, |m| match m {
        DaemonMessage::BrowserFrame { jpeg, width, height, .. } if !jpeg.is_empty() => Some((width, height)),
        _ => None,
    })
    .await;
    assert_eq!((w, h), (1280, 800));
    assert!(daemon.hello().iter().any(|m| matches!(m, DaemonMessage::BrowserState { open: true, .. })));

    // Click the field, type, press a named key (once the page loaded).
    let b = daemon.browsers.running("work").await.unwrap();
    for _ in 0..100 {
        if b.evaluate("document.readyState").await.unwrap() == "complete" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    for kind in ["mousePressed", "mouseReleased"] {
        browser(BrowserAction::Input { event: json!({ "kind": "mouse", "type": kind, "x": 50, "y": 25, "button": "left", "clickCount": 1 }) });
    }
    browser(BrowserAction::Input { event: json!({ "kind": "text", "text": "olá" }) });
    browser(BrowserAction::Input { event: json!({ "kind": "key", "key": "Backspace" }) });
    let mut value = json!(null);
    for _ in 0..50 {
        value = b.evaluate("document.querySelector('#q').value").await.unwrap();
        if value == "ol" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!(value, "ol");

    // The wheel scrolls the page (the pane sends trackpad and mouse wheel
    // this way).
    b.evaluate("document.body.style.height = '5000px'; window.scrollTo(0, 0)").await.unwrap();
    browser(BrowserAction::Input { event: json!({ "kind": "mouse", "type": "mouseWheel", "x": 100, "y": 100, "deltaX": 0, "deltaY": 400 }) });
    let mut scrolled = json!(0);
    for _ in 0..50 {
        scrolled = b.evaluate("window.scrollY").await.unwrap();
        if scrolled.as_f64().unwrap_or(0.0) > 0.0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(scrolled.as_f64().unwrap_or(0.0) > 0.0, "page did not scroll: {scrolled}");
    b.evaluate("document.cookie = 'orc=1; max-age=3600'").await.unwrap();
    drop(b);

    // Closed and reopened: the profile still has the cookie.
    browser(BrowserAction::Close);
    until(&mut events, |m| matches!(m, DaemonMessage::BrowserState { open: false, .. }).then_some(())).await;
    browser(BrowserAction::Open { url: Some(url.clone()) });
    until(&mut events, |m| matches!(m, DaemonMessage::BrowserState { url: ref u, .. } if *u == url).then_some(())).await;
    let b = daemon.browsers.running("work").await.unwrap();
    assert_eq!(b.evaluate("document.cookie").await.unwrap(), "orc=1");

    // A session asking for the browser gets Playwright MCP on its CDP port.
    daemon.handle(ClientMessage::CreateSession {
        account_id: "work".into(),
        cwd: Some(dir.display().to_string()),
        profile: Profile { browser: Some("work".into()), ..Profile::default() },
        cols: 80,
        rows: 24,
    });
    until(&mut events, |m| matches!(m, DaemonMessage::Sessions { ref sessions } if !sessions.is_empty()).then_some(())).await;
    let id = daemon.sessions.lock().unwrap().list()[0].id.clone();
    let mcp: serde_json::Value =
        serde_json::from_slice(&std::fs::read(dir.join("sessions").join(&id).join("mcp.json")).unwrap()).unwrap();
    let args = &mcp["mcpServers"]["browser"]["args"];
    assert_eq!(args[1], orc_daemon::server::PLAYWRIGHT_MCP);
    assert_eq!(args[3], b.cdp_http.as_str());

    // Bad input never reaches Chrome.
    browser(BrowserAction::Input { event: json!({ "kind": "mouse", "type": "dragIntercepted" }) });
    loop {
        let m = tokio::time::timeout(Duration::from_secs(10), events.recv()).await.unwrap().unwrap();
        if let DaemonMessage::Error { message } = m {
            assert!(message.contains("inválido"), "{message}");
            break;
        }
    }
    // A Chrome outliving this test would linger: close it.
    drop(b);
    daemon.browsers.close("work").await;

    // An orcd that died leaves its Chrome on the profile: the next launch
    // closes it and starts its own.
    let lock_pid = || {
        std::fs::read_link(dir.join("browsers/orphan/SingletonLock"))
            .ok()
            .and_then(|t| t.to_string_lossy().rsplit('-').next()?.parse::<u32>().ok())
    };
    let dead = Browsers::new(dir.join("browsers"), Some(chrome.clone()));
    std::mem::forget(dead.get("orphan", |_| {}).await.unwrap());
    std::mem::forget(dead);
    let old = lock_pid().expect("Chrome holds the profile");
    let fresh = Browsers::new(dir.join("browsers"), Some(chrome));
    let (n, _) = fresh.get("orphan", |_| {}).await.unwrap();
    assert_eq!(n.evaluate("1 + 1").await.unwrap(), 2);
    assert_ne!(lock_pid(), Some(old));
    // Gone, or a zombie of this test process (a real orphan's parent is
    // dead, so it gets reaped).
    let out = std::process::Command::new("ps").args(["-p", &old.to_string(), "-o", "stat="]).output().unwrap();
    let stat = String::from_utf8_lossy(&out.stdout);
    assert!(stat.trim().is_empty() || stat.starts_with('Z'), "the orphan Chrome was closed: {stat}");
    drop(n);
    fresh.close("orphan").await;
}
