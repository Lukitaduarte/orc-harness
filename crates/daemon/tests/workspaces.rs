//! Workspaces and new accounts through the daemon.

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage, WorkspaceInfo};

#[test]
fn workspaces_and_new_accounts() {
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
            vec![Account { id: "default".into(), config_dir: None, gh_config_dir: None }],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    )
    .with_home(dir.to_path_buf());
    let workspaces = |d: &Daemon| {
        d.hello()
            .into_iter()
            .find_map(|m| match m {
                DaemonMessage::Workspaces { workspaces } => Some(workspaces),
                _ => None,
            })
            .unwrap()
    };
    assert_eq!(workspaces(&daemon)[0].accounts, ["default"]);

    let ws = |id: &str, accounts: &[&str]| WorkspaceInfo {
        id: id.into(),
        name: format!("WS {id}"),
        accounts: accounts.iter().map(|a| a.to_string()).collect(),
        memory: None,
    };
    assert!(daemon.handle(ClientMessage::UpsertWorkspace { workspace: ws("trabalho", &[]) }).is_empty());
    assert!(daemon.handle(ClientMessage::AddAccount { id: "work-2".into(), workspace_id: "trabalho".into() }).is_empty());

    // config.json keeps the implicit default and gets the new account.
    let cfg = orc_daemon::config::load(&dir.join("config.json")).unwrap();
    assert_eq!(cfg.accounts.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(), ["default", "work-2"]);
    assert_eq!(cfg.accounts[1].config_dir.as_deref(), Some(dir.join("accounts/work-2").as_path()));
    let mode = std::os::unix::fs::PermissionsExt::mode(&std::fs::metadata(dir.join("accounts/work-2")).unwrap().permissions());
    assert_eq!(mode & 0o777, 0o700);
    let list = workspaces(&daemon);
    assert_eq!(list.iter().map(|w| (w.id.as_str(), w.accounts.clone())).collect::<Vec<_>>(), [
        ("default", vec!["default".to_string()]),
        ("trabalho", vec!["work-2".to_string()]),
    ]);
    // The new account runs sessions with its own Claude Code folder.
    daemon.handle(ClientMessage::CreateSession {
        account_id: "work-2".into(),
        cwd: Some(dir.display().to_string()),
        profile: Default::default(),
        cols: 80,
        rows: 24,
    });
    assert_eq!(daemon.sessions.lock().unwrap().list()[0].account_id, "work-2");

    let dup = daemon.handle(ClientMessage::AddAccount { id: "work-2".into(), workspace_id: "trabalho".into() });
    assert!(matches!(&dup[..], [DaemonMessage::Error { .. }]));
    assert!(daemon.handle(ClientMessage::RemoveWorkspace { id: "default".into() }).is_empty());
    assert_eq!(workspaces(&daemon)[0].accounts, ["work-2", "default"], "loose accounts land in the first");
    assert!(matches!(&daemon.handle(ClientMessage::RemoveWorkspace { id: "trabalho".into() })[..], [DaemonMessage::Error { .. }]));
}
