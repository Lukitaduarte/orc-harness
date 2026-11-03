//! The IDE through the daemon: files of the session folder and the real
//! Dart language server (skipped when `dart` is not installed).

use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage, Profile};
use serde_json::{Value, json};

/// The next language-server message `pick` accepts.
async fn wait(events: &mut tokio::sync::broadcast::Receiver<DaemonMessage>, pick: impl Fn(&Value) -> bool) -> Value {
    loop {
        let m = tokio::time::timeout(Duration::from_secs(60), events.recv()).await.expect("lsp timeout").unwrap();
        if let DaemonMessage::Lsp { message, .. } = m
            && pick(&message)
        {
            return message;
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn files_and_the_dart_language_server() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let repo = dir.join("app");
    std::fs::create_dir_all(repo.join("lib")).unwrap();
    std::fs::write(repo.join("pubspec.yaml"), "name: app\nenvironment:\n  sdk: ^3.0.0\n").unwrap();
    std::fs::write(repo.join("lib/main.dart"), "void main() {\n  int x = 'oi';\n  pri\n}\n").unwrap();
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
    );
    let mut events = daemon.events.subscribe();
    daemon.handle(ClientMessage::CreateSession {
        account_id: "work".into(),
        cwd: Some(repo.display().to_string()),
        profile: Profile::default(),
        cols: 80,
        rows: 24,
    });
    let sid = daemon.sessions.lock().unwrap().list()[0].id.clone();

    let r = daemon.handle(ClientMessage::ListDir { session_id: sid.clone(), path: String::new() });
    assert!(matches!(&r[..], [DaemonMessage::DirEntries { entries, .. }] if entries[0].name == "lib"));
    let r = daemon.handle(ClientMessage::WriteFile { session_id: sid.clone(), path: "../fora.txt".into(), text: "x".into() });
    assert!(matches!(&r[..], [DaemonMessage::Error { .. }]));
    assert!(!dir.join("fora.txt").exists());

    if std::process::Command::new("dart").arg("--version").output().is_err() {
        eprintln!("sem dart: parte de LSP pulada");
        return;
    }
    let lsp = |message: Value| {
        let r = daemon.handle(ClientMessage::Lsp { session_id: sid.clone(), language: "dart".into(), message });
        assert!(r.is_empty(), "{r:?}");
    };
    let uri = format!("file://{}", repo.canonicalize().unwrap().join("lib/main.dart").display());
    let root = format!("file://{}", repo.canonicalize().unwrap().display());
    lsp(json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": { "processId": null, "rootUri": root, "capabilities": {} } }));
    let init = wait(&mut events, |m| m["id"] == 1).await;
    assert!(init["result"]["capabilities"]["completionProvider"].is_object());
    lsp(json!({ "jsonrpc": "2.0", "method": "initialized", "params": {} }));
    let text = std::fs::read_to_string(repo.join("lib/main.dart")).unwrap();
    lsp(json!({ "jsonrpc": "2.0", "method": "textDocument/didOpen",
                "params": { "textDocument": { "uri": uri, "languageId": "dart", "version": 1, "text": text } } }));
    let diags = wait(&mut events, |m| m["method"] == "textDocument/publishDiagnostics" && m["params"]["diagnostics"].as_array().is_some_and(|d| !d.is_empty())).await;
    assert!(diags["params"]["diagnostics"].as_array().unwrap().iter().any(|d| d["range"]["start"]["line"] == 1));
    lsp(json!({ "jsonrpc": "2.0", "id": 2, "method": "textDocument/completion",
                "params": { "textDocument": { "uri": uri }, "position": { "line": 2, "character": 5 } } }));
    let done = wait(&mut events, |m| m["id"] == 2).await;
    let items = done["result"]["items"].as_array().or(done["result"].as_array()).unwrap().clone();
    assert!(items.iter().any(|i| i["label"].as_str().is_some_and(|l| l.starts_with("print"))), "{}", items.len());

    // Symbol search across the folder.
    lsp(json!({ "jsonrpc": "2.0", "id": 3, "method": "workspace/symbol", "params": { "query": "main" } }));
    let symbols = wait(&mut events, |m| m["id"] == 3).await;
    assert!(symbols["result"].as_array().unwrap().iter().any(|s| s["name"].as_str().is_some_and(|n| n.starts_with("main"))), "{symbols}");

    // Hover on `int`, and formatting of the badly spaced file.
    lsp(json!({ "jsonrpc": "2.0", "id": 4, "method": "textDocument/hover",
                "params": { "textDocument": { "uri": uri }, "position": { "line": 1, "character": 3 } } }));
    let hover = wait(&mut events, |m| m["id"] == 4).await;
    assert!(hover["result"]["contents"].to_string().contains("int"), "{hover}");
    lsp(json!({ "jsonrpc": "2.0", "id": 5, "method": "textDocument/formatting",
                "params": { "textDocument": { "uri": uri }, "options": { "tabSize": 2, "insertSpaces": true } } }));
    let fmt = wait(&mut events, |m| m["id"] == 5).await;
    assert!(fmt.get("result").is_some(), "{fmt}");

    // Stopping the session stops its language server.
    daemon.handle(ClientMessage::StopSession { session_id: sid });
}
