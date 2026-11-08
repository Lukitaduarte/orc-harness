//! Workspaces keep to themselves: an agent sees and messages only its own
//! workspace's sessions, and an env that belongs to a workspace (with its
//! own value) reaches only that workspace's sessions.

use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{CatalogEntry, ClientMessage, DaemonMessage, Profile, WorkspaceInfo};
use serde_json::json;

fn daemon(dir: &std::path::Path) -> Daemon {
    // Prints the env it got, then stays up.
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\necho \"token=$GH_TOKEN\"\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let account = |id: &str| Account { id: id.into(), config_dir: Some(dir.join(id)), gh_config_dir: None };
    Daemon::new(
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
            vec![account("work"), account("home")],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    )
    .with_home(dir.to_path_buf())
}

fn call(d: &Daemon, session: &str, tool: &str, args: serde_json::Value) -> (String, bool) {
    match d.handle(ClientMessage::McpCall { session_id: session.into(), tool: tool.into(), args }).pop() {
        Some(DaemonMessage::McpResult { text, is_error }) => (text, is_error),
        other => panic!("{other:?}"),
    }
}

fn screen(d: &Daemon, session: &str, want: &str) -> String {
    let sessions = d.sessions.lock().unwrap();
    let snap = sessions.session(session).unwrap().wait_for(Duration::from_secs(5), |g| {
        (0..g.rows as usize).any(|r| g.line_text(r).contains(want))
    });
    (0..snap.rows as usize).map(|r| snap.line_text(r)).collect::<Vec<_>>().join("\n")
}

#[tokio::test(flavor = "multi_thread")]
async fn workspaces_keep_their_sessions_and_envs_to_themselves() {
    let tmp = tempfile::tempdir().unwrap();
    let d = daemon(tmp.path());
    for (id, account) in [("trabalho", "work"), ("casa", "home")] {
        let w = WorkspaceInfo { id: id.into(), name: id.into(), accounts: vec![account.into()], memory: None, budget_usd: None };
        assert!(d.handle(ClientMessage::UpsertWorkspace { workspace: w }).is_empty());
    }
    let (work, home) = {
        let mut s = d.sessions.lock().unwrap();
        let a = s.create("work", Some(tmp.path().into()), Profile::default(), 80, 10).unwrap().id;
        let b = s.create("home", Some(tmp.path().into()), Profile::default(), 80, 10).unwrap().id;
        (a, b)
    };

    // The harness tools stay inside the workspace.
    let (list, _) = call(&d, &work, "list_sessions", json!({}));
    assert!(list.contains(&work) && !list.contains(&home), "{list}");
    let (msg, err) = call(&d, &work, "send_message", json!({ "to": home, "body": "oi" }));
    assert!(err && msg.contains("não existe"), "{msg}");

    // GH_TOKEN: one for every workspace, and casa's own.
    let env = |workspace: Option<&str>| CatalogEntry {
        id: format!("env-{}-GH_TOKEN", workspace.unwrap_or("all")),
        kind: "env".into(),
        name: "GH_TOKEN".into(),
        description: String::new(),
        path: None,
        mcp: None,
        has_value: false,
        workspace: workspace.map(String::from),
    };
    for (w, value) in [(None, "shared"), (Some("casa"), "casa-token")] {
        d.handle(ClientMessage::UpsertCatalog { entry: env(w) });
        d.handle(ClientMessage::SetSecret { name: "GH_TOKEN".into(), value: value.into(), workspace: w.map(String::from) });
    }
    let with_token = Profile { env_names: vec!["GH_TOKEN".into()], ..Profile::default() };
    {
        let mut s = d.sessions.lock().unwrap();
        s.apply_profile(&home, with_token.clone()).unwrap();
        s.apply_profile(&work, with_token.clone()).unwrap();
    }
    assert!(screen(&d, &home, "token=").contains("token=casa-token"), "casa gets its own value");
    assert!(screen(&d, &work, "token=").contains("token=shared"), "trabalho gets the shared one");
    // The agent lists what it may use: both see GH_TOKEN, never the value.
    let (envs, _) = call(&d, &home, "list_envs", json!({}));
    assert!(envs.contains("GH_TOKEN") && !envs.contains("casa-token"), "{envs}");

    // An env only casa has: trabalho cannot turn it on.
    let mut only_casa = env(Some("casa"));
    only_casa.id = "env-casa-NPM_TOKEN".into();
    only_casa.name = "NPM_TOKEN".into();
    d.handle(ClientMessage::UpsertCatalog { entry: only_casa });
    d.handle(ClientMessage::SetSecret { name: "NPM_TOKEN".into(), value: "npm".into(), workspace: Some("casa".into()) });
    let npm = Profile { env_names: vec!["NPM_TOKEN".into()], ..Profile::default() };
    let refused = d.sessions.lock().unwrap().apply_profile(&work, npm.clone()).unwrap_err();
    assert!(refused.to_string().contains("outro workspace"), "{refused}");
    d.sessions.lock().unwrap().apply_profile(&home, npm).unwrap();
    let (envs, _) = call(&d, &work, "list_envs", json!({}));
    assert!(!envs.contains("NPM_TOKEN"), "{envs}");

    // An agent's own value goes to its workspace.
    let (_, err) = call(&d, &work, "request_env_change", json!({ "name": "API_KEY", "value": "k" }));
    assert!(!err);
    let id = d.env_requests.lock().unwrap().keys().next().cloned().unwrap();
    d.handle(ClientMessage::ResolveEnvRequest { id, approve: true });
    let api = d.catalog.lock().unwrap().list().into_iter().find(|e| e.name == "API_KEY").unwrap();
    assert_eq!(api.workspace.as_deref(), Some("trabalho"));
    let secrets = d.sessions.lock().unwrap().secrets.clone();
    assert_eq!(secrets.get("env/@trabalho/API_KEY").as_deref(), Some("k"));
    assert_eq!(secrets.get("env/API_KEY"), None);
}
