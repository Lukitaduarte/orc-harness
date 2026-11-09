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
            vec![Account { id: "work".into(), config_dir: Some(dir.join("claude-work")), gh_config_dir: None }],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths {
            worktrees: dir.join("worktrees"),
            hooks: dir.join("hooks"),
            commit_check: env!("CARGO_BIN_EXE_orc-commit-check").into(),
        },
    );

    let bad = daemon.handle(ClientMessage::AddProject {
        name: "Não repo".into(),
        repo: dir.display().to_string(),
        base_branch: "main".into(), workspace_id: None });
    assert!(matches!(&bad[..], [DaemonMessage::Error { .. }]));
    // A base branch the clone does not have is refused.
    let wrong = daemon.handle(ClientMessage::AddProject {
        name: "Plataforma Web".into(),
        repo: r.display().to_string(),
        base_branch: "develop".into(), workspace_id: None });
    assert!(matches!(&wrong[..], [DaemonMessage::Error { message }] if message.contains("develop")), "{wrong:?}");
    assert!(daemon.handle(ClientMessage::AddProject {
        name: "Plataforma".into(),
        repo: r.display().to_string(),
        base_branch: "main".into(), workspace_id: None })
    .is_empty());
    // Renamed later; the base must still exist.
    let id = daemon.projects.lock().unwrap().list()[0].id.clone();
    let bad = daemon.handle(ClientMessage::UpdateProject { id: id.clone(), name: "Plataforma Web".into(), base_branch: "develop".into() });
    assert!(matches!(&bad[..], [DaemonMessage::Error { .. }]));
    assert!(daemon.handle(ClientMessage::UpdateProject { id: id.clone(), name: "Plataforma Web".into(), base_branch: "main".into() }).is_empty());
    let project = daemon.projects.lock().unwrap().list()[0].clone();
    assert_eq!((project.id.as_str(), project.name.as_str()), ("plataforma", "Plataforma Web"));

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
    // The worktree is trusted in the account's Claude Code state: no trust
    // question stops the session.
    let state: serde_json::Value =
        serde_json::from_slice(&std::fs::read(dir.join("claude-work/.claude.json")).unwrap()).unwrap();
    assert_eq!(state["projects"][s.cwd.as_str()]["hasTrustDialogAccepted"], true);

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
        session_id: Some(s.id.clone()),
        query: "login".into(),
        regex: false,
    });
    let [DaemonMessage::SearchResults { hits, .. }] = &found[..] else { panic!("{found:?}") };
    assert_eq!(hits[0].path, "login.rs");

    // Commit and push from the app, through the same rules.
    std::fs::write(wt.join("logout.rs"), "fn logout() {}\n").unwrap();
    let commit = |m: &str| match &daemon.handle(ClientMessage::GitCommit { session_id: s.id.clone(), message: m.into() })[..] {
        [DaemonMessage::GitResult { ok, output, .. }] => (*ok, output.clone()),
        other => panic!("{other:?}"),
    };
    assert!(!commit("arrumei").0, "conventional commits still apply");
    let (ok, out) = commit("feat(auth): logout");
    assert!(ok, "{out}");
    let remote = tempfile::tempdir().unwrap();
    assert!(git(remote.path(), &["init", "-q", "--bare"]));
    assert!(git(r, &["remote", "add", "origin", &remote.path().display().to_string()]));
    let mut events = daemon.events.subscribe();
    assert!(daemon.handle(ClientMessage::GitPush { session_id: s.id.clone() }).is_empty());
    let (ok, out) = loop {
        if let DaemonMessage::GitResult { action, ok, output, .. } = events.blocking_recv().unwrap()
            && action == "push"
        {
            break (ok, output);
        }
    };
    assert!(ok, "{out}");
    assert!(git(remote.path(), &["rev-parse", "--verify", "refs/heads/feat/1-login"]));

    // And it can go (worktrees and branches stay in git).
    assert!(daemon.handle(ClientMessage::RemoveProject { id: project.id.clone() }).is_empty());
    assert!(daemon.projects.lock().unwrap().list().is_empty());
}
