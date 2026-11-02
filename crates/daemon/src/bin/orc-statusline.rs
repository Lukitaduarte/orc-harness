//! statusLine command the daemon configures for every session it starts.
//!
//! Claude Code runs it with the session JSON on stdin. It forwards the rate
//! limits to the daemon (`ORC_SOCKET`, tagged with `ORC_ACCOUNT` and
//! `ORC_SESSION`) and prints a short line for the terminal. It never blocks
//! or fails Claude Code: if the daemon is down, it just prints.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use orc_daemon::quota::status_text;
use orc_protocol::{ClientMessage, StatusLineInput, StatusReport};

fn main() {
    let mut raw = String::new();
    let _ = std::io::stdin().read_to_string(&mut raw);
    let input: StatusLineInput = serde_json::from_str(&raw).unwrap_or_default();

    let env = |k: &str| std::env::var(k).unwrap_or_default();
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let report = StatusReport::from_input(env("ORC_ACCOUNT"), env("ORC_SESSION"), &input, now);

    if let Ok(path) = std::env::var("ORC_SOCKET")
        && let Ok(mut stream) = UnixStream::connect(path)
    {
        let _ = stream.set_write_timeout(Some(Duration::from_millis(200)));
        if let Ok(line) = serde_json::to_string(&ClientMessage::Status(report.clone())) {
            let _ = stream.write_all(format!("{line}\n").as_bytes());
        }
    }

    let model = input
        .model
        .and_then(|m| m.display_name)
        .unwrap_or_default();
    let limits = report.rate_limits.as_ref().map(status_text).unwrap_or_default();
    let line = [model, limits]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" · ");
    println!("{line}");
}
