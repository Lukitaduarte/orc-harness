//! Learn through the daemon: a session proposes skill edits over the
//! harness MCP; only accepted ones touch the skill.

use std::path::Path;
use std::process::Command;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{CatalogEntry, ClientMessage, DaemonMessage, PlanDoc};
use serde_json::json;

fn git(dir: &Path, args: &[&str]) -> bool {
    Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success()
}

#[test]
fn comments_become_accepted_skill_edits() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let repo = dir.join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    for a in [&["init", "-q", "-b", "main"][..], &["config", "user.email", "t@t"], &["config", "user.name", "t"], &["config", "commit.gpgsign", "false"]] {
        assert!(git(&repo, a));
    }
    std::fs::write(repo.join("README.md"), "x\n").unwrap();
    assert!(git(&repo, &["add", "."]) && git(&repo, &["commit", "-qm", "chore: init"]));
    let skill = dir.join("skills/flutter-tests");
    std::fs::create_dir_all(&skill).unwrap();
    std::fs::write(skill.join("SKILL.md"), "# Testes\n\nRode os testes unitários.\n").unwrap();
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let daemon = Daemon::new(
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
    daemon.handle(ClientMessage::UpsertCatalog {
        entry: CatalogEntry {
            id: "skill-flutter-tests".into(),
            kind: "skill".into(),
            name: "flutter-tests".into(),
            description: String::new(),
            path: Some(skill.display().to_string()),
            mcp: None,
            has_value: false,
        },
    });
    daemon.handle(ClientMessage::AddProject { name: "Web".into(), repo: repo.display().to_string(), base_branch: "main".into(), workspace_id: None });
    daemon.handle(ClientMessage::SavePlan { plan: PlanDoc { id: "p".into(), project_id: "web".into(), name: "Push".into(), ..PlanDoc::default() } });

    let none = daemon.handle(ClientMessage::Learn { plan_id: "p".into(), account_id: "work".into(), notes: vec![], skills: vec!["flutter-tests".into()] });
    assert!(matches!(&none[..], [DaemonMessage::Error { .. }]));
    assert!(daemon
        .handle(ClientMessage::Learn {
            plan_id: "p".into(),
            account_id: "work".into(),
            notes: vec!["Card #2 · faltou golden test".into()],
            skills: vec!["flutter-tests".into(), "fora-do-catalogo".into()],
        })
        .is_empty());
    let learner = daemon.sessions.lock().unwrap().list()[0].id.clone();

    let propose = |session: &str, old: &str, new: &str| {
        daemon.handle(ClientMessage::McpCall {
            session_id: session.into(),
            tool: "propose_learning".into(),
            args: json!({ "skill": "flutter-tests", "file": "SKILL.md", "summary": "goldens", "old": old, "new": new, "source": "Card #2" }),
        })
    };
    assert!(matches!(&propose(&learner, "Rode os testes unitários.", "Rode os testes unitários e os golden tests.")[..], [DaemonMessage::McpResult { is_error: false, .. }]));
    assert!(matches!(&propose(&learner, "", "## Nunca\nPule testes.")[..], [DaemonMessage::McpResult { is_error: false, .. }]));
    // Another session cannot propose.
    daemon.handle(ClientMessage::CreateSession { account_id: "work".into(), cwd: Some(dir.display().to_string()), profile: Default::default(), cols: 80, rows: 24 });
    let other = daemon.sessions.lock().unwrap().list()[1].id.clone();
    assert!(matches!(&propose(&other, "", "x")[..], [DaemonMessage::McpResult { is_error: true, .. }]));

    let items = loop {
        if let Ok(DaemonMessage::Learnings { items, .. }) = events.try_recv()
            && items.len() == 2
        {
            break items;
        }
    };
    assert!(items.iter().all(|i| i.status == "pending"));
    // Nothing touched yet.
    assert_eq!(std::fs::read_to_string(skill.join("SKILL.md")).unwrap(), "# Testes\n\nRode os testes unitários.\n");

    assert!(daemon.handle(ClientMessage::DecideLearning { plan_id: "p".into(), id: items[0].id.clone(), accept: true }).is_empty());
    assert!(daemon.handle(ClientMessage::DecideLearning { plan_id: "p".into(), id: items[1].id.clone(), accept: false }).is_empty());
    assert_eq!(std::fs::read_to_string(skill.join("SKILL.md")).unwrap(), "# Testes\n\nRode os testes unitários e os golden tests.\n");
    let after = daemon
        .hello()
        .into_iter()
        .find_map(|m| match m {
            DaemonMessage::Learnings { items, .. } => Some(items),
            _ => None,
        })
        .unwrap();
    assert_eq!(after.iter().map(|i| i.status.as_str()).collect::<Vec<_>>(), ["applied", "declined"]);
}
