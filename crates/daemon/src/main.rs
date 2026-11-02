//! `orcd serve [--socket PATH]`: runs the daemon's local socket.
//! `orcd run -- PROGRAM [ARGS]`: runs a program in a session and prints the
//! final screen, as the app would draw it (a quick check of the emulation).

use std::path::PathBuf;
use std::time::Duration;

use orc_daemon::config;
use orc_daemon::manager::{ManagerConfig, SessionManager};
use orc_daemon::server::Daemon;
use orc_daemon::session::{Session, SessionSpec};

fn main() -> std::io::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("serve") => {
            let home = config::orc_home();
            let socket = args
                .iter()
                .position(|a| a == "--socket")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join("orcd.sock"));
            std::fs::create_dir_all(&home)?;
            let cfg = config::load(&home.join("config.json"))?;
            // The helpers ship next to orcd.
            let bin_dir = std::env::current_exe()?.parent().map(PathBuf::from).unwrap_or_default();
            let manager = SessionManager::new(
                ManagerConfig {
                    claude: cfg.claude,
                    statusline: bin_dir.join("orc-statusline"),
                    hook: bin_dir.join("orc-hook"),
                    runtime_root: home.join("sessions"),
                    socket: socket.clone(),
                },
                cfg.accounts,
            );
            eprintln!("orcd: socket em {}", socket.display());
            tokio::runtime::Runtime::new()?.block_on(Daemon::new(manager).serve(socket))
        }
        Some("run") => {
            let cmd: Vec<&str> = args
                .iter()
                .skip_while(|a| *a != "--")
                .skip(1)
                .map(String::as_str)
                .collect();
            let Some((program, rest)) = cmd.split_first() else {
                eprintln!("uso: orcd run -- PROGRAMA [ARGS]");
                std::process::exit(2);
            };
            let session = Session::spawn(&SessionSpec::new(*program, rest))?;
            let snap = session.wait_for(Duration::from_secs(30), |_| false);
            for row in 0..snap.rows as usize {
                println!("{}", snap.line_text(row));
            }
            Ok(())
        }
        _ => {
            eprintln!("uso: orcd serve [--socket PATH] | orcd run -- PROGRAMA [ARGS]");
            std::process::exit(2);
        }
    }
}
