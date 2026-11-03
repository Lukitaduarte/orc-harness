//! commit-msg hook for harness worktrees: refuses commits that are not
//! conventional commits, with a message the agent can act on.

fn main() {
    let Some(path) = std::env::args().nth(1) else {
        eprintln!("uso: orc-commit-check <arquivo-da-mensagem>");
        std::process::exit(2);
    };
    let msg = std::fs::read_to_string(&path).unwrap_or_default();
    if let Err(e) = orc_daemon::git::check_commit_message(&msg) {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
