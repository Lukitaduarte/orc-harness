//! A plan run through the daemon: cards start as worktree sessions in
//! dependency order, and GitHub (a stand-in `gh` on PATH) moves them.

use std::path::Path;
use std::process::Command;
use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_daemon::server::{Daemon, GitPaths};
use orc_protocol::{CardSpec, ClientMessage, DaemonMessage, PlanDoc};

fn git(dir: &Path, args: &[&str]) -> bool {
    Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success()
}

fn exe(path: &Path, body: &str) {
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
}

fn card(n: u32, deps: &[u32]) -> CardSpec {
    CardSpec {
        number: n,
        title: format!("card {n}"),
        branch: format!("feat/{n}-x"),
        model: Some("sonnet".into()),
        depends_on: deps.to_vec(),
        prompt: format!("Faça o card {n}"),
    }
}

fn states(d: &Daemon) -> Vec<(u32, String)> {
    let plans = d.plans.lock().unwrap();
    plans.runs[0].cards.iter().map(|c| (c.number, c.state.clone())).collect()
}

#[test]
fn cards_run_in_order_and_follow_their_prs() {
    let home = tempfile::tempdir().unwrap();
    let dir = home.path();
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

    // `gh pr view BRANCH`: answers from $FAKE_GH/<branch with / as _>.
    let bin = dir.join("bin");
    let prs = dir.join("prs");
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::create_dir_all(&prs).unwrap();
    exe(&bin.join("gh"), "#!/bin/sh\nf=\"$FAKE_GH/$(echo \"$3\" | tr / _)\"\n[ -f \"$f\" ] && exec cat \"$f\"\nexit 1\n");
    // Only test in this binary: changing the environment is safe here.
    unsafe {
        std::env::set_var("PATH", format!("{}:{}", bin.display(), std::env::var("PATH").unwrap()));
        std::env::set_var("FAKE_GH", &prs);
    }
    let pr = |branch: &str, state: &str| {
        std::fs::write(
            prs.join(branch.replace('/', "_")),
            format!(r#"{{"number":7,"state":"{state}","url":"https://github.com/x/y/pull/7"}}"#),
        )
        .unwrap()
    };

    let fake = dir.join("fake-claude");
    exe(&fake, "#!/bin/sh\nfor a in \"$@\"; do last=\"$a\"; done\necho \"prompt:$last\"\nexec cat\n");
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
    assert!(daemon
        .handle(ClientMessage::AddProject { name: "Web".into(), repo: r.display().to_string(), base_branch: "main".into() , workspace_id: None })
        .is_empty());
    assert!(daemon
        .handle(ClientMessage::SavePlan {
            plan: PlanDoc {
                id: "push".into(),
                project_id: "web".into(),
                name: "Push".into(),
                markdown: "# Push\n".into(),
                state: serde_json::json!({}),
                ..PlanDoc::default()
            },
        })
        .is_empty());

    // Bad cards never start anything.
    let cycle = daemon.handle(ClientMessage::StartPlan {
        plan_id: "push".into(),
        account_id: "work".into(),
        cards: vec![card(1, &[2]), card(2, &[1])],
    });
    assert!(matches!(&cycle[..], [DaemonMessage::Error { message }] if message.contains("ciclo")));

    assert!(daemon
        .handle(ClientMessage::StartPlan {
            plan_id: "push".into(),
            account_id: "work".into(),
            cards: vec![card(1, &[]), card(2, &[1]), card(3, &[])],
        })
        .is_empty());
    assert_eq!(states(&daemon), [(1, "running".into()), (2, "todo".into()), (3, "running".into())]);
    let again = daemon.handle(ClientMessage::StartPlan { plan_id: "push".into(), account_id: "work".into(), cards: vec![card(1, &[])] });
    assert!(matches!(&again[..], [DaemonMessage::Error { .. }]), "one run at a time");

    // Card 1's session: in its worktree, on the card's model, told what to do.
    let s1 = daemon.plans.lock().unwrap().runs[0].cards[0].session_id.clone().unwrap();
    let summary = daemon.sessions.lock().unwrap().summary(&s1).unwrap();
    assert_eq!(summary.branch.as_deref(), Some("feat/1-x"));
    assert_eq!(summary.model.as_deref(), Some("sonnet"));
    assert!(summary.cwd.ends_with("worktrees/web/feat__1-x"));
    let screen = daemon.sessions.lock().unwrap().session(&s1).unwrap().wait_for(Duration::from_secs(5), |g| {
        (0..g.rows as usize).any(|row| g.line_text(row).contains("prompt:Faça o card 1"))
    });
    assert!((0..screen.rows as usize).any(|row| screen.line_text(row).contains("prompt:Faça o card 1")));

    // PR opened, then merged: card 1 goes review → done and frees card 2.
    pr("feat/1-x", "OPEN");
    daemon.poll_plans();
    assert_eq!(states(&daemon)[0], (1, "review".into()));
    pr("feat/1-x", "MERGED");
    daemon.poll_plans();
    assert_eq!(states(&daemon), [(1, "done".into()), (2, "running".into()), (3, "running".into())]);

    // Card 3's session ends with no PR: stopped; a retry starts it again.
    let s3 = daemon.plans.lock().unwrap().runs[0].cards[2].session_id.clone().unwrap();
    daemon.handle(ClientMessage::StopSession { session_id: s3.clone() });
    daemon.poll_plans();
    assert_eq!(states(&daemon)[2], (3, "stopped".into()));
    assert!(daemon.handle(ClientMessage::RetryCard { plan_id: "push".into(), number: 3 }).is_empty());
    let run = daemon.plans.lock().unwrap().runs[0].clone();
    assert_eq!(run.cards[2].state, "running");
    assert_ne!(run.cards[2].session_id.as_deref(), Some(s3.as_str()));

    // The run is on disk and clients were told.
    let saved = orc_daemon::plans::Plans::load(dir.join("plans"));
    assert_eq!(saved.runs[0].cards, run.cards);
    let mut saw_run = false;
    while let Ok(m) = events.try_recv() {
        saw_run |= matches!(m, DaemonMessage::PlanRun { ref plan_id, .. } if plan_id == "push");
    }
    assert!(saw_run);
    assert!(daemon.hello().iter().any(|m| matches!(m, DaemonMessage::PlanRun { .. })));
    let removing = daemon.handle(ClientMessage::RemovePlan { id: "push".into(), force: false });
    assert!(matches!(&removing[..], [DaemonMessage::Error { .. }]), "active plans stay");

    // Planning: a session in the repo gets the plan and the request…
    assert!(daemon
        .handle(ClientMessage::AskPlanner { plan_id: "push".into(), account_id: "work".into(), request: "Escreva o plano".into() })
        .is_empty());
    let doc = daemon.plans.lock().unwrap().docs[0].clone();
    assert!(doc.busy);
    let planner = doc.planner.clone().unwrap();
    let summary = daemon.sessions.lock().unwrap().summary(&planner).unwrap();
    assert_eq!(std::path::Path::new(&summary.cwd).canonicalize().unwrap(), r.canonicalize().unwrap());
    assert_eq!(summary.branch, None, "the planner never works on a branch");
    // …saves through the harness MCP (only the planner may)…
    let save = |session: &str| {
        daemon.handle(ClientMessage::McpCall {
            session_id: session.into(),
            tool: "save_plan".into(),
            args: serde_json::json!({ "markdown": "# Push\n\n## Fontes\nv2\n" }),
        })
    };
    assert!(matches!(&save(&s3)[..], [DaemonMessage::McpResult { is_error: true, .. }]));
    assert!(matches!(&save(&planner)[..], [DaemonMessage::McpResult { is_error: false, .. }]));
    let doc = daemon.plans.lock().unwrap().docs[0].clone();
    assert_eq!((doc.revision, doc.busy, doc.markdown.contains("v2")), (1, false, true));
    // …and the next request goes to the same session.
    assert!(daemon
        .handle(ClientMessage::AskPlanner { plan_id: "push".into(), account_id: "work".into(), request: "Revise os comentários".into() })
        .is_empty());
    assert_eq!(daemon.plans.lock().unwrap().docs[0].planner.as_deref(), Some(planner.as_str()));
    let screen = daemon.sessions.lock().unwrap().session(&planner).unwrap().wait_for(Duration::from_secs(5), |g| {
        (0..g.rows as usize).any(|row| g.line_text(row).contains("Revise os comentários"))
    });
    assert!((0..screen.rows as usize).any(|row| screen.line_text(row).contains("Revise os comentários")));

    // Deleting a running plan, on purpose: its sessions end, it is gone.
    let card_sessions: Vec<String> = daemon.plans.lock().unwrap().runs[0].cards.iter().filter_map(|c| c.session_id.clone()).collect();
    assert!(!card_sessions.is_empty());
    assert!(daemon.handle(ClientMessage::RemovePlan { id: "push".into(), force: true }).is_empty());
    let alive: Vec<String> = daemon.sessions.lock().unwrap().list().into_iter().map(|s| s.id).collect();
    assert!(card_sessions.iter().all(|s| !alive.contains(s)), "card sessions ended");
    assert!(!alive.contains(&planner), "the planner too");
    assert!(daemon.plans.lock().unwrap().docs.is_empty());
    assert!(!dir.join("plans/push").exists());
    assert!(!dir.join("sessions").join(&planner).exists(), "its generated folder is gone");
}
