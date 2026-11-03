//! `orcd serve [--socket PATH]`: runs the daemon's local socket.
//! `orcd run -- PROGRAM [ARGS]`: runs a program in a session and prints the
//! final screen, as the app would draw it (a quick check of the emulation).

use std::path::PathBuf;
use std::time::Duration;

use orc_daemon::catalog::Catalog;
use orc_daemon::config;
use orc_daemon::manager::{ManagerConfig, SessionManager};
use orc_daemon::remote::{Devices, Remote};
use orc_daemon::secrets::{self, SecretStore};
use orc_daemon::projects::Projects;
use orc_daemon::server::{Daemon, GitPaths};
use orc_daemon::usage::UsageStore;
use orc_protocol::DaemonMessage;
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
            // Holds keys, device list and session folders: owner only.
            std::fs::set_permissions(&home, std::os::unix::fs::PermissionsExt::from_mode(0o700))?;
            let cfg = config::load(&home.join("config.json"))?;
            // The helpers ship next to orcd.
            let bin_dir = std::env::current_exe()?.parent().map(PathBuf::from).unwrap_or_default();
            let secrets = std::sync::Arc::new(if std::env::var("ORC_SECRETS").as_deref() == Ok("file") {
                eprintln!("orcd: segredos em arquivo (ORC_SECRETS=file), só para desenvolvimento");
                SecretStore::file(home.join("secrets.json"))
            } else {
                SecretStore::keychain()
            });
            let runtime = tokio::runtime::Runtime::new()?;
            // Sessions report tokens and cost here (127.0.0.1 only).
            let otlp = runtime.block_on(tokio::net::TcpListener::bind("127.0.0.1:0"))?;
            let otlp_url = format!("http://{}/v1/metrics", otlp.local_addr()?);
            eprintln!("orcd: métricas OTLP em {otlp_url}");
            let manager = SessionManager::new(
                ManagerConfig {
                    claude: cfg.claude,
                    statusline: bin_dir.join("orc-statusline"),
                    hook: bin_dir.join("orc-hook"),
                    runtime_root: home.join("sessions"),
                    socket: socket.clone(),
                    otlp_metrics: Some(otlp_url),
                    orc_mcp: Some(bin_dir.join("orc-mcp")),
                },
                cfg.accounts,
                secrets.clone(),
            );
            let daemon = Daemon::new(
                manager,
                Catalog::load(&home)?,
                UsageStore::load(home.join("usage.jsonl")),
                Projects::load(home.join("projects.json")),
                GitPaths {
                    worktrees: home.join("worktrees"),
                    hooks: home.join("hooks"),
                    commit_check: bin_dir.join("orc-commit-check"),
                },
            );
            runtime.block_on(async move {
                tokio::spawn(daemon.clone().serve_otlp(otlp));
                let key = secrets::daemon_key(&secrets, &home.join("daemon.key"))?;
                let endpoint = orc_link::endpoint(key, &[orc_link::ALPN_PAIR, orc_link::ALPN_MAIN]).await?;
                let remote = Remote::new(endpoint, Devices::load(home.join("devices.json")));
                let _ = daemon.remote.set(remote.clone());
                eprintln!("orcd: socket em {}", socket.display());
                eprintln!("orcd: id {}", remote.endpoint.id());
                eprintln!("orcd: para parear um app, rode `orcd pair`");
                tokio::spawn(remote.serve(daemon.clone()));
                tokio::spawn(daemon.clone().stream_grids());
                daemon.serve(socket).await
            })
        }
        Some("pair") => {
            // Asks the running daemon for a one-time ticket over the
            // owner-only local socket.
            use std::io::{BufRead, BufReader, Write};
            let socket = config::orc_home().join("orcd.sock");
            let mut stream = std::os::unix::net::UnixStream::connect(&socket)
                .map_err(|e| std::io::Error::other(format!("orcd não está rodando ({e})")))?;
            stream.write_all(b"{\"type\":\"new_pairing_ticket\"}\n")?;
            let mut line = String::new();
            BufReader::new(stream).read_line(&mut line)?;
            match serde_json::from_str::<DaemonMessage>(&line) {
                Ok(DaemonMessage::PairingTicket { ticket }) => {
                    println!("{ticket}");
                    eprintln!("Cole no app em Configurações → Conectar daemon. Vale 10 minutos, uma vez.");
                    Ok(())
                }
                Ok(DaemonMessage::Error { message }) => Err(std::io::Error::other(message)),
                _ => Err(std::io::Error::other("resposta inesperada do daemon")),
            }
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
            eprintln!("uso: orcd serve [--socket PATH] | orcd pair | orcd run -- PROGRAMA [ARGS]");
            std::process::exit(2);
        }
    }
}
