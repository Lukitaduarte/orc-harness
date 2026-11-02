//! `orcd serve [--socket PATH]`: runs the daemon's local socket.
//! `orcd run -- PROGRAM [ARGS]`: runs a program in a session and prints the
//! final screen, as the app would draw it (a quick check of the emulation).

use std::path::PathBuf;
use std::time::Duration;

use orc_daemon::server::Daemon;
use orc_daemon::session::{Session, SessionSpec};

fn default_socket() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".orc").join("orcd.sock")
}

fn main() -> std::io::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("serve") => {
            let socket = args
                .iter()
                .position(|a| a == "--socket")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from)
                .unwrap_or_else(default_socket);
            if let Some(dir) = socket.parent() {
                std::fs::create_dir_all(dir)?;
            }
            eprintln!("orcd: socket em {}", socket.display());
            tokio::runtime::Runtime::new()?.block_on(Daemon::default().serve(socket))
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
