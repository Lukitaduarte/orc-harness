//! The harness MCP end to end: the real orc-mcp binary speaking MCP over
//! stdio, its calls answered by a running daemon over the local socket.

use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage, Profile};
use serde_json::{Value, json};

/// Runs orc-mcp as `session`, sends JSON-RPC requests, returns responses.
fn mcp(socket: &Path, session: &str, requests: &[Value]) -> Vec<Value> {
    let mut child = Command::new(env!("CARGO_BIN_EXE_orc-mcp"))
        .env("ORC_SOCKET", socket)
        .env("ORC_SESSION", session)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut out = BufReader::new(child.stdout.take().unwrap());
    let mut responses = Vec::new();
    for r in requests {
        writeln!(stdin, "{r}").unwrap();
        if r.get("id").is_some() {
            let mut line = String::new();
            out.read_line(&mut line).unwrap();
            responses.push(serde_json::from_str(&line).unwrap());
        }
    }
    drop(stdin);
    let _ = child.wait();
    responses
}

fn call(id: u64, tool: &str, args: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "method": "tools/call", "params": { "name": tool, "arguments": args } })
}

fn text(r: &Value) -> &str {
    r["result"]["content"][0]["text"].as_str().unwrap_or_default()
}

#[tokio::test(flavor = "multi_thread")]
async fn sessions_talk_delegate_and_ask_for_envs() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let socket = dir.join("orcd.sock");
    // Stand-in for claude: prints its last argument (the initial prompt).
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\nfor a in \"$@\"; do last=\"$a\"; done\necho \"prompt:$last\"\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let daemon = Daemon::new(
        SessionManager::new(
            ManagerConfig {
                claude: fake.display().to_string(),
                statusline: "/usr/bin/true".into(),
                hook: "/usr/bin/true".into(),
                runtime_root: dir.join("sessions"),
                socket: socket.clone(),
                otlp_metrics: None,
                orc_mcp: Some(env!("CARGO_BIN_EXE_orc-mcp").into()),
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
    for _ in 0..2 {
        daemon.handle(ClientMessage::CreateSession {
            account_id: "work".into(),
            cwd: Some(dir.display().to_string()),
            profile: Profile::default(),
            cols: 80,
            rows: 24,
        });
    }
    let (s1, s2) = {
        let list = daemon.sessions.lock().unwrap().list();
        (list[0].id.clone(), list[1].id.clone())
    };

    let sock = socket.clone();
    let (s1c, s2c) = (s1.clone(), s2.clone());
    let r = tokio::task::spawn_blocking(move || {
        mcp(&sock, &s1c, &[
            json!({ "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "protocolVersion": "2025-06-18" } }),
            json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }),
            json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }),
            call(3, "list_sessions", json!({})),
            call(4, "send_message", json!({ "to": s2c, "body": "rode os testes" })),
            call(5, "send_message", json!({ "to": "nope", "body": "x" })),
            call(6, "request_env_change", json!({ "name": "API_TOKEN", "value": "s3cret" })),
            call(7, "delegate_task", json!({ "prompt": "revise o README", "model": "haiku" })),
        ])
    })
    .await
    .unwrap();
    assert_eq!(r[0]["result"]["serverInfo"]["name"], "orc-harness");
    let tools: Vec<&str> = r[1]["result"]["tools"].as_array().unwrap().iter().map(|t| t["name"].as_str().unwrap()).collect();
    assert_eq!(tools, ["list_sessions", "send_message", "read_inbox", "delegate_task", "search_code", "save_plan", "propose_learning", "list_envs", "request_env_change"]);
    assert!(text(&r[2]).contains("(você)"));
    assert!(text(&r[3]).contains("entregue"));
    assert_eq!(r[4]["result"]["isError"], true);
    assert!(text(&r[5]).contains("só é gravada se ele aprovar"));
    assert!(text(&r[6]).contains("criada"));

    // The delegated session started with the prompt and the reply-to note.
    let delegated = daemon.sessions.lock().unwrap().list()[2].clone();
    assert_eq!(delegated.model.as_deref(), Some("haiku"));
    let screen = daemon.sessions.lock().unwrap().session(&delegated.id).unwrap().wait_for(Duration::from_secs(5), |g| {
        (0..g.rows as usize).any(|row| g.line_text(row).contains("revise o README"))
    });
    assert!((0..screen.rows as usize).any(|row| screen.line_text(row).contains("prompt:revise o README")));

    // s2 reads its inbox (once).
    let sock = socket.clone();
    let s2c = s2.clone();
    let r = tokio::task::spawn_blocking(move || {
        mcp(&sock, &s2c, &[call(1, "read_inbox", json!({})), call(2, "read_inbox", json!({}))])
    })
    .await
    .unwrap();
    assert_eq!(text(&r[0]), format!("de {s1}: rode os testes"));
    assert_eq!(text(&r[1]), "nenhuma mensagem");

    // The env request waits for you; the local socket cannot approve it.
    let id = loop {
        match tokio::time::timeout(Duration::from_secs(5), events.recv()).await.unwrap().unwrap() {
            DaemonMessage::EnvRequest { id, name, .. } => {
                assert_eq!(name, "API_TOKEN");
                break id;
            }
            _ => continue,
        }
    };
    let secrets = daemon.sessions.lock().unwrap().secrets.clone();
    assert_eq!(secrets.get("env/API_TOKEN"), None);
    {
        use tokio::io::{AsyncBufReadExt, AsyncWriteExt};
        let stream = tokio::net::UnixStream::connect(&socket).await.unwrap();
        let (read, mut write) = stream.into_split();
        let msg = serde_json::to_string(&ClientMessage::ResolveEnvRequest { id: id.clone(), approve: true }).unwrap();
        write.write_all(format!("{msg}\n").as_bytes()).await.unwrap();
        let line = tokio::io::BufReader::new(read).lines().next_line().await.unwrap().unwrap();
        assert!(line.contains("aprovação só pelo app"));
    }
    assert_eq!(secrets.get("env/API_TOKEN"), None);
    // From the app (paired client path): approved and stored.
    daemon.handle(ClientMessage::ResolveEnvRequest { id, approve: true });
    assert_eq!(secrets.get("env/API_TOKEN").as_deref(), Some("s3cret"));
    let sock = socket.clone();
    let r = tokio::task::spawn_blocking(move || mcp(&sock, &s1, &[call(1, "read_inbox", json!({}))]))
        .await
        .unwrap();
    assert!(text(&r[0]).contains("aprovou gravar API_TOKEN"));

    // The agent sees the env names and state, never the value.
    daemon.handle(ClientMessage::UpsertCatalog {
        entry: orc_protocol::CatalogEntry {
            id: "env-API_TOKEN".into(),
            kind: "env".into(),
            name: "API_TOKEN".into(),
            description: "token da API".into(),
            path: None,
            mcp: None,
            has_value: false,
        },
    });
    let sock = socket.clone();
    let s1c = daemon.sessions.lock().unwrap().list()[0].id.clone();
    let r = tokio::task::spawn_blocking(move || mcp(&sock, &s1c, &[call(1, "list_envs", json!({}))])).await.unwrap();
    assert_eq!(text(&r[0]), "API_TOKEN · com valor · não ativa nesta sessão · token da API");
    assert!(!text(&r[0]).contains("s3cret"));
}
