//! Cards go to the account with most room and wait when none has any.

use std::path::Path;
use std::process::Command;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{CardSpec, ClientMessage, PlanDoc, QuotaWindow, RateLimits, StatusReport};

fn git(dir: &Path, args: &[&str]) -> bool {
    Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success()
}

fn quota(d: &Daemon, account: &str, h5: f64, at: i64) {
    let resets = 4_102_444_800; // 2100: the window is current
    d.handle(ClientMessage::Status(StatusReport {
        account_id: account.into(),
        session_id: "x".into(),
        rate_limits: Some(RateLimits {
            five_hour: Some(QuotaWindow { used_percentage: h5, resets_at: resets }),
            seven_day: Some(QuotaWindow { used_percentage: 10.0, resets_at: resets }),
        }),
        cost_usd: None,
        tokens: None,
        read_at: at,
    }));
}

#[test]
fn cards_follow_the_quota() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
    let repo = tempfile::tempdir().unwrap();
    let r = repo.path();
    for a in [&["init", "-q", "-b", "main"][..], &["config", "user.email", "t@t"], &["config", "user.name", "t"], &["config", "commit.gpgsign", "false"]] {
        assert!(git(r, a));
    }
    std::fs::write(r.join("README.md"), "x\n").unwrap();
    assert!(git(r, &["add", "."]) && git(r, &["commit", "-qm", "chore: init"]));
    let fake = dir.join("fake-claude");
    std::fs::write(&fake, "#!/bin/sh\nexec cat\n").unwrap();
    std::fs::set_permissions(&fake, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
    let account = |id: &str| Account { id: id.into(), config_dir: Some(dir.join(format!("claude-{id}"))), gh_config_dir: None };
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
            vec![account("a"), account("b")],
            std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
        ),
        orc_daemon::catalog::Catalog::load(dir).unwrap(),
        orc_daemon::usage::UsageStore::load(dir.join("usage.jsonl")),
        orc_daemon::projects::Projects::load(dir.join("projects.json")),
        orc_daemon::plans::Plans::load(dir.join("plans")),
        GitPaths { worktrees: dir.join("worktrees"), hooks: dir.join("hooks"), commit_check: "/usr/bin/true".into() },
    );
    daemon.handle(ClientMessage::AddProject { name: "Web".into(), repo: r.display().to_string(), base_branch: "main".into(), workspace_id: None });
    daemon.handle(ClientMessage::SavePlan { plan: PlanDoc { id: "p".into(), project_id: "web".into(), name: "P".into(), ..PlanDoc::default() } });
    let card = |n: u32| CardSpec { number: n, title: format!("c{n}"), branch: format!("feat/{n}"), model: None, depends_on: vec![], prompt: "x".into() };

    // a is busier than b: the card goes to b.
    quota(&daemon, "a", 70.0, 1);
    quota(&daemon, "b", 20.0, 1);
    daemon.handle(ClientMessage::StartPlan { plan_id: "p".into(), account_id: "a".into(), cards: vec![card(1)] });
    let c = daemon.plans.lock().unwrap().runs[0].cards[0].clone();
    assert_eq!((c.state.as_str(), c.account_id.as_deref()), ("running", Some("b")));

    // Both at the limit: the next card waits, saying why.
    daemon.handle(ClientMessage::StopSession { session_id: c.session_id.clone().unwrap() });
    quota(&daemon, "a", 95.0, 2);
    quota(&daemon, "b", 92.0, 2);
    daemon.poll_plans(); // card 1 stops (no PR)
    daemon.handle(ClientMessage::RetryCard { plan_id: "p".into(), number: 1 });
    let c = daemon.plans.lock().unwrap().runs[0].cards[0].clone();
    assert_eq!(c.state, "todo");
    assert!(c.note.as_deref().is_some_and(|n| n.starts_with("aguardando cota")), "{:?}", c.note);

    // Room again (the window reset or another reading): the next poll starts it.
    quota(&daemon, "a", 10.0, 3);
    daemon.poll_plans();
    let c = daemon.plans.lock().unwrap().runs[0].cards[0].clone();
    assert_eq!((c.state.as_str(), c.account_id.as_deref(), c.note), ("running", Some("a"), None));
}
