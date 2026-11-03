//! Memory providers: the harness's own, shared by a workspace's sessions,
//! or an external MCP from the catalog given to them.

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{CatalogEntry, ClientMessage, DaemonMessage, WorkspaceInfo};
use serde_json::json;

fn text(r: &[DaemonMessage]) -> (String, bool) {
    match r {
        [DaemonMessage::McpResult { text, is_error }] => (text.clone(), *is_error),
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_workspace_remembers_across_sessions() {
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
            vec![
                Account { id: "w".into(), config_dir: None, gh_config_dir: None },
                Account { id: "p".into(), config_dir: None, gh_config_dir: None },
            ],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    )
    .with_home(dir.to_path_buf());
    let ws = |id: &str, accounts: &[&str], memory: Option<&str>| WorkspaceInfo {
        id: id.into(),
        name: id.into(),
        accounts: accounts.iter().map(|a| a.to_string()).collect(),
        memory: memory.map(String::from),
        budget_usd: None,
    };
    daemon.handle(ClientMessage::UpsertWorkspace { workspace: ws("trabalho", &["w"], None) });
    daemon.handle(ClientMessage::UpsertWorkspace { workspace: ws("pessoal", &["p"], None) });
    let session = |account: &str| {
        daemon.handle(ClientMessage::CreateSession { account_id: account.into(), cwd: Some(dir.display().to_string()), profile: Default::default(), cols: 80, rows: 24 });
        daemon.sessions.lock().unwrap().list().last().unwrap().id.clone()
    };
    let (s1, s2, s3) = (session("w"), session("w"), session("p"));
    let tool = |s: &str, name: &str, args: serde_json::Value| text(&daemon.handle(ClientMessage::McpCall { session_id: s.into(), tool: name.into(), args }));

    let (out, err) = tool(&s1, "remember", json!({ "text": "Deploy da API é no Railway (api-prod).", "tags": ["deploy"] }));
    assert!(!err && out.contains("trabalho"), "{out}");
    let (out, _) = tool(&s2, "recall", json!({ "query": "onde é o deploy?" }));
    assert!(out.contains("Railway"), "another session of the workspace recalls it: {out}");
    let (out, _) = tool(&s3, "recall", json!({ "query": "deploy" }));
    assert_eq!(out, "nada na memória sobre isso", "other workspaces do not see it");

    // You see and clean it from the app.
    let entries = match &daemon.handle(ClientMessage::ListMemory { workspace_id: "trabalho".into() })[..] {
        [DaemonMessage::Memory { entries, .. }] => entries.clone(),
        other => panic!("{other:?}"),
    };
    assert_eq!(entries.len(), 1);
    assert!(matches!(&daemon.handle(ClientMessage::ForgetMemory { workspace_id: "trabalho".into(), id: entries[0].id.clone() })[..], [DaemonMessage::Memory { entries, .. }] if entries.is_empty()));

    // An external provider: the catalog MCP goes to the workspace's new
    // sessions, and the harness's tools point there.
    daemon.handle(ClientMessage::UpsertCatalog {
        entry: CatalogEntry {
            id: "mcp-mem0".into(),
            kind: "mcp".into(),
            name: "mem0".into(),
            description: String::new(),
            path: None,
            mcp: Some(json!({ "command": "npx", "args": ["-y", "mem0-mcp"] })),
            has_value: false,
        },
    });
    daemon.handle(ClientMessage::UpsertWorkspace { workspace: ws("trabalho", &["w"], Some("mcp-mem0")) });
    let s4 = session("w");
    let mcp: serde_json::Value = serde_json::from_slice(&std::fs::read(dir.join("sessions").join(&s4).join("mcp.json")).unwrap()).unwrap();
    assert_eq!(mcp["mcpServers"]["memory"]["args"][1], "mem0-mcp");
    let s5 = session("p");
    let mcp: serde_json::Value = serde_json::from_slice(&std::fs::read(dir.join("sessions").join(&s5).join("mcp.json")).unwrap()).unwrap();
    assert!(mcp["mcpServers"]["memory"].is_null(), "only that workspace");
    let (out, err) = tool(&s4, "recall", json!({ "query": "x" }));
    assert!(err && out.contains("mcp-mem0"), "{out}");
}
