//! Hook command the daemon configures for every session it starts:
//! `orc-hook <Event>`. Tells the daemon which session moved (`ORC_SESSION`)
//! so the app shows running, waiting for you, or idle. Like
//! `orc-statusline`, it never blocks or fails Claude Code.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use orc_protocol::ClientMessage;

fn main() {
    // Drain stdin so Claude Code never blocks writing the hook input.
    let mut raw = String::new();
    let _ = std::io::stdin().read_to_string(&mut raw);
    let event = std::env::args().nth(1).unwrap_or_default();
    let session_id = std::env::var("ORC_SESSION").unwrap_or_default();
    if event.is_empty() || session_id.is_empty() {
        return;
    }
    if let Ok(path) = std::env::var("ORC_SOCKET")
        && let Ok(mut stream) = UnixStream::connect(path)
    {
        let _ = stream.set_write_timeout(Some(Duration::from_millis(200)));
        if let Ok(line) = serde_json::to_string(&ClientMessage::Hook { session_id, event }) {
            let _ = stream.write_all(format!("{line}\n").as_bytes());
        }
    }
}
