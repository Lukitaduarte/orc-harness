//! Through the daemon: project, worktree session with the real commit
//! checker, diff and search.

use std::path::Path;
use std::process::Command;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{ClientMessage, DaemonMessage, Profile};

fn git(dir: &Path, args: &[&str]) -> bool {
    Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success()
}

#[test]
fn worktree_session_enforces_conventional_commits() {
    let home = tempfile::tempdir().unwrap();
    let repo = tempfile::tempdir().unwrap();
    let r = repo.path();
    for a in [
        &["init", "-q", "-b", "main"][..],
        &["config", "user.email", "t@t"],
        &["config", "user.name", "t"],
        &["config", "commit.gpgsign", "false"],
    ] {
        assert!(git(r, a));
    }
    std::fs::write(r.join("README.md"), "orc\n").unwrap();
    assert!(git(r, &["add", "."]) && git(r, &["commit", "-qm", "chore: init"]));

    let fake = home.path().join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let dir = home.path();
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
        GitPaths {
            worktrees: dir.join("worktrees"),
            hooks: dir.join("hooks"),
            commit_check: env!("CARGO_BIN_EXE_orc-commit-check").into(),
        },
    );

    let bad = daemon.handle(ClientMessage::AddProject {
        name: "Não repo".into(),
        repo: dir.display().to_string(),
        base_branch: "main".into(),
    });
    assert!(matches!(&bad[..], [DaemonMessage::Error { .. }]));
    assert!(daemon.handle(ClientMessage::AddProject {
        name: "Plataforma Web".into(),
        repo: r.display().to_string(),
        base_branch: "main".into(),
    })
    .is_empty());
    let project = daemon.projects.lock().unwrap().list()[0].clone();
    assert_eq!(project.id, "plataforma-web");

    assert!(daemon.handle(ClientMessage::CreateWorktreeSession {
        project_id: project.id.clone(),
        branch: "feat/1-login".into(),
        account_id: "work".into(),
        profile: Profile::default(),
        cols: 80,
        rows: 24,
    })
    .is_empty());
    let s = daemon.sessions.lock().unwrap().list()[0].clone();
    assert_eq!(s.branch.as_deref(), Some("feat/1-login"));
    let wt = Path::new(&s.cwd);
    assert!(wt.starts_with(dir.join("worktrees")));

    std::fs::write(wt.join("login.rs"), "fn login() {}\n").unwrap();
    assert!(git(wt, &["add", "."]));
    assert!(!git(wt, &["commit", "-qm", "wip"]), "the real checker must refuse");
    assert!(git(wt, &["commit", "-qm", "feat(auth): login"]));

    let diff = daemon.handle(ClientMessage::Diff { session_id: s.id.clone() });
    let [DaemonMessage::Diff { base, files, .. }] = &diff[..] else { panic!("{diff:?}") };
    assert_eq!(base, "main");
    assert_eq!(files.iter().map(|f| f.path.as_str()).collect::<Vec<_>>(), ["login.rs"]);

    let found = daemon.handle(ClientMessage::Search {
        project_id: None,
        session_id: Some(s.id),
        query: "login".into(),
        regex: false,
    });
    let [DaemonMessage::SearchResults { hits, .. }] = &found[..] else { panic!("{found:?}") };
    assert_eq!(hits[0].path, "login.rs");
}
