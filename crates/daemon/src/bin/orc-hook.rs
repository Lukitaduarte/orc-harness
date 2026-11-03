//! Hook command the daemon configures for every session it starts:
//! `orc-hook <Event>`. Tells the daemon which session moved (`ORC_SESSION`)
//! so the app shows running, waiting for you, or idle; that part never
//! blocks or fails Claude Code.
//!
//! On PreToolUse it also guards outward actions (deploys, releases, pushes
//! to main, merges; see orc_daemon::gates): those wait for your OK in the
//! app. Refused, unanswered, or with the daemon unreachable, the call is
//! blocked (exit 2, the reason goes back to Claude). It fails closed.

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use orc_protocol::{ClientMessage, DaemonMessage};

fn send(path: &str, msg: &ClientMessage) -> Option<UnixStream> {
    let mut stream = UnixStream::connect(path).ok()?;
    stream.set_write_timeout(Some(Duration::from_millis(500))).ok()?;
    let line = serde_json::to_string(msg).ok()?;
    stream.write_all(format!("{line}\n").as_bytes()).ok()?;
    Some(stream)
}

/// Asks the daemon whether the call may run; waits for your decision.
fn gate(socket: Option<&str>, session_id: &str, tool: &str, input: &serde_json::Value) -> Result<(), String> {
    let socket = socket.ok_or("o harness não está acessível; deploys precisam do OK do usuário")?;
    let msg = ClientMessage::Gate { session_id: session_id.into(), tool: tool.into(), input: input.clone() };
    let stream = send(socket, &msg).ok_or("o harness não respondeu; deploys precisam do OK do usuário")?;
    stream.set_read_timeout(Some(Duration::from_secs(650))).map_err(|e| e.to_string())?;
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).map_err(|e| format!("sem resposta do harness: {e}"))?;
    match serde_json::from_str::<DaemonMessage>(&line) {
        Ok(DaemonMessage::GateDecision { allow: true, .. }) => Ok(()),
        Ok(DaemonMessage::GateDecision { reason, .. }) => Err(reason),
        Ok(DaemonMessage::Error { message }) => Err(message),
        _ => Err("resposta inesperada do harness".into()),
    }
}

fn main() {
    // Always read stdin so Claude Code never blocks writing the hook input.
    let mut raw = String::new();
    let _ = std::io::stdin().read_to_string(&mut raw);
    let event = std::env::args().nth(1).unwrap_or_default();
    let session_id = std::env::var("ORC_SESSION").unwrap_or_default();
    if event.is_empty() || session_id.is_empty() {
        return;
    }
    let socket = std::env::var("ORC_SOCKET").ok();
    if let Some(path) = &socket {
        let _ = send(path, &ClientMessage::Hook { session_id: session_id.clone(), event: event.clone() });
    }
    if event != "PreToolUse" {
        return;
    }
    let input: serde_json::Value = serde_json::from_str(&raw).unwrap_or_default();
    let tool = input["tool_name"].as_str().unwrap_or_default();
    let tool_input = &input["tool_input"];
    // Ordinary work never waits on the daemon.
    if orc_daemon::gates::needs_ok(tool, tool_input).is_none() {
        return;
    }
    if let Err(reason) = gate(socket.as_deref(), &session_id, tool, tool_input) {
        eprintln!("{reason}");
        std::process::exit(2);
    }
}
