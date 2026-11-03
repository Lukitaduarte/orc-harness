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
use orc_daemon::plans::Plans;
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
            let relay_cfg = cfg.relay.clone();
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
                Plans::load(home.join("plans")),
                GitPaths {
                    worktrees: home.join("worktrees"),
                    hooks: home.join("hooks"),
                    commit_check: bin_dir.join("orc-commit-check"),
                },
            );
            let chrome = orc_daemon::browser::find_chrome(std::env::var("ORC_BROWSER").ok().as_deref());
            match &chrome {
                Some(c) => eprintln!("orcd: navegador dos workspaces: {}", c.display()),
                None => eprintln!("orcd: nenhum Chrome/Chromium/Brave/Edge; navegador dos workspaces desligado"),
            }
            let restored = daemon.sessions.lock().unwrap().restore();
            if restored > 0 {
                eprintln!("orcd: {restored} sessão(ões) retomada(s)");
            }
            let daemon = daemon.with_home(home.clone()).with_browsers(orc_daemon::browser::Browsers::new(home.join("browsers"), chrome));
            runtime.block_on(async move {
                tokio::spawn(daemon.clone().serve_otlp(otlp));
                let key = secrets::daemon_key(&secrets, &home.join("daemon.key"))?;
                // Same port across restarts: paired apps dial the ticket's addresses.
                let port_file = home.join("link-port");
                let saved: u16 = std::fs::read_to_string(&port_file).ok().and_then(|p| p.trim().parse().ok()).unwrap_or(0);
                let alpns = [orc_link::ALPN_PAIR, orc_link::ALPN_MAIN];
                let relay = orc_link::Relay::parse(relay_cfg.as_deref()).map_err(std::io::Error::other)?;
                match &relay {
                    orc_link::Relay::Off => eprintln!("orcd: sem relay: apps alcançam o daemon só na mesma rede"),
                    orc_link::Relay::N0 => eprintln!("orcd: relay público da n0 (tráfego cifrado de ponta a ponta)"),
                    orc_link::Relay::Url(u) => eprintln!("orcd: relay próprio {u}"),
                }
                let endpoint = match orc_link::endpoint_on(key.clone(), &alpns, saved, &relay).await {
                    Ok(e) => e,
                    Err(e) => {
                        eprintln!("orcd: porta {saved} indisponível ({e}); apps pareados precisam parear de novo");
                        orc_link::endpoint_on(key, &alpns, 0, &relay).await?
                    }
                };
                if let Some(port) = orc_link::bound_port(&endpoint).filter(|p| *p != saved) {
                    std::fs::write(&port_file, port.to_string())?;
                }
                let remote = Remote::new(endpoint, Devices::load(home.join("devices.json")))
                    .with_relay(relay != orc_link::Relay::Off);
                let _ = daemon.remote.set(remote.clone());
                eprintln!("orcd: socket em {}", socket.display());
                eprintln!("orcd: id {}", remote.endpoint.id());
                eprintln!("orcd: para parear um app, rode `orcd pair`");
                tokio::spawn(remote.serve(daemon.clone()));
                tokio::spawn(daemon.clone().stream_grids());
                // Cards move with their PRs on GitHub.
                tokio::spawn(daemon.clone().watch_plans(Duration::from_secs(60)));
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
                    // The phone scans it; the text above is for pasting.
                    if let Ok(code) = qrcode::QrCode::with_error_correction_level(&ticket, qrcode::EcLevel::L) {
                        let qr = code
                            .render::<qrcode::render::unicode::Dense1x2>()
                            .dark_color(qrcode::render::unicode::Dense1x2::Light)
                            .light_color(qrcode::render::unicode::Dense1x2::Dark)
                            .build();
                        eprintln!("{qr}");
                    }
                    eprintln!("Cole no app em Conectar daemon, ou escaneie o QR no celular. Vale 10 minutos, uma vez.");
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
        Some("devices") | Some("revoke") => {
            // Over the owner-only local socket, like pair.
            use std::io::{BufRead, BufReader, Write};
            let socket = config::orc_home().join("orcd.sock");
            let mut stream = std::os::unix::net::UnixStream::connect(&socket)
                .map_err(|e| std::io::Error::other(format!("orcd não está rodando ({e})")))?;
            let msg = match (args[0].as_str(), args.get(1)) {
                ("revoke", Some(id)) => serde_json::json!({ "type": "revoke_device", "id": id }),
                ("revoke", None) => {
                    eprintln!("uso: orcd revoke ID (veja orcd devices)");
                    std::process::exit(2);
                }
                _ => serde_json::json!({ "type": "list_devices" }),
            };
            stream.write_all(format!("{msg}\n").as_bytes())?;
            if args[0] == "revoke" {
                eprintln!("revogado (se existia); a conexão dele caiu");
                return Ok(());
            }
            let mut line = String::new();
            BufReader::new(stream).read_line(&mut line)?;
            if let Ok(DaemonMessage::Devices { devices }) = serde_json::from_str(&line) {
                for d in devices {
                    println!("{}  {}  {}", d.id, d.name, if d.connected { "conectado" } else { "" });
                }
            }
            Ok(())
        }
        Some("install") => {
            // `--sign "Apple Development: …"` signs the copies (see
            // `security find-identity -v -p codesigning`).
            let sign = args.iter().position(|a| a == "--sign").and_then(|i| args.get(i + 1)).cloned();
            let home = config::orc_home();
            std::fs::create_dir_all(&home)?;
            let plist = orc_daemon::service::install(&home, sign.as_deref())?;
            eprintln!("orcd instalado: {} (sobe no login, volta se cair)", plist.display());
            eprintln!("log em {}", home.join("orcd.log").display());
            if sign.is_none() {
                eprintln!("sem assinatura: o Keychain e o firewall vão perguntar de novo a cada atualização (use --sign)");
            }
            Ok(())
        }
        Some("uninstall") => {
            orc_daemon::service::uninstall()?;
            eprintln!("serviço removido (binários e dados em ~/.orc ficam)");
            Ok(())
        }
        Some("status") => {
            match orc_daemon::service::status()? {
                Some(s) => println!("orcd: {s}"),
                None => println!("orcd: não instalado como serviço"),
            }
            Ok(())
        }
        _ => {
            eprintln!(
                "uso: orcd serve [--socket PATH] | orcd pair | orcd install [--sign IDENTIDADE] | orcd uninstall | orcd status | orcd run -- PROGRAMA [ARGS]"
            );
            std::process::exit(2);
        }
    }
}
