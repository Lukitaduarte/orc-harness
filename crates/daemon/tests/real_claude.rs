//! Runs the real `claude` with the files the manager generates and returns
//! its first screen. Ignored by default (needs Claude Code installed);
//! sends no prompt, so it uses no quota:
//! `cargo test -p orc-daemon --test real_claude -- --ignored --nocapture`

use std::time::Duration;

use orc_daemon::manager::{Account, ManagerConfig, SessionManager};
use orc_protocol::Profile;

#[test]
#[ignore]
fn real_claude_accepts_the_generated_session() {
    let dir = tempfile::tempdir().unwrap();
    let skill = dir.path().join("skills/hello");
    std::fs::create_dir_all(&skill).unwrap();
    std::fs::write(
        skill.join("SKILL.md"),
        "---\nname: hello\ndescription: Says hello.\n---\nSay hello.\n",
    )
    .unwrap();
    let mut m = SessionManager::new(
        ManagerConfig {
            claude: "claude".into(),
            statusline: env!("CARGO_BIN_EXE_orc-statusline").into(),
            hook: env!("CARGO_BIN_EXE_orc-hook").into(),
            runtime_root: dir.path().join("sessions"),
            socket: dir.path().join("orcd.sock"),
            otlp_metrics: None,
        },
        vec![Account { id: "default".into(), config_dir: None, gh_config_dir: None }],
        std::sync::Arc::new(orc_daemon::secrets::SecretStore::memory()),
    );
    let profile = Profile {
        skills: vec![skill.display().to_string()],
        ..Profile::default()
    };
    let s = m.create("default", Some(dir.path().into()), profile, 110, 32).unwrap();
    let snap = m.session(&s.id).unwrap().wait_for(Duration::from_secs(20), |g| {
        (0..g.rows as usize).any(|r| {
            let l = g.line_text(r);
            l.contains("trust") || l.contains('>') || l.contains("❯")
        })
    });
    let text: Vec<String> = (0..snap.rows as usize)
        .map(|r| snap.line_text(r))
        .filter(|l| !l.is_empty())
        .collect();
    println!("{}", text.join("\n"));
    let joined = text.join("\n").to_lowercase();
    for bad in ["invalid", "error", "failed to load"] {
        assert!(!joined.contains(bad), "claude reported {bad}:\n{joined}");
    }
    assert!(m.session(&s.id).unwrap().exited().is_none(), "claude exited early");
}
