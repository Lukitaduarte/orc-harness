//! claude.ai connectors (the MCP servers an account adds on claude.ai):
//! listed per account with `claude mcp list`, and let into a session by URL.
//!
//! Sessions normally run with `--strict-mcp-config`, which also keeps the
//! connectors out. A session with connectors runs without it and with an
//! allowlist (`allowedMcpServers`) of its own servers plus the chosen
//! connectors' URLs, so the account's other MCP servers, plugins' and
//! repositories' still stay out.

use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use orc_protocol::Connector;
use serde_json::{Value, json};

/// The connectors in `claude mcp list` output (`claude.ai Name: URL - status`).
pub fn parse_list(out: &str) -> Vec<Connector> {
    out.lines()
        .filter_map(|l| {
            let rest = l.trim().strip_prefix("claude.ai ")?;
            let (name, rest) = rest.split_once(": ")?;
            let (url, status) = rest.rsplit_once(" - ").unwrap_or((rest, ""));
            let status = status.to_lowercase();
            let status = if status.contains("connected") {
                "connected"
            } else if status.contains("auth") {
                "needs_auth"
            } else {
                "failed"
            };
            Some(Connector { name: name.trim().into(), url: url.trim().into(), status: status.into() })
        })
        .collect()
}

/// Asks Claude Code for an account's connectors (it checks each one, which
/// can take a while). `config_dir` is the account's; none is the default.
pub fn list(claude: &str, config_dir: Option<&Path>) -> std::io::Result<Vec<Connector>> {
    let mut cmd = Command::new(claude);
    cmd.args(["mcp", "list"]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    if let Some(home) = std::env::var_os("HOME") {
        // Not a repository: its .mcp.json does not matter here.
        cmd.current_dir(home);
    }
    if let Some(dir) = config_dir {
        cmd.env("CLAUDE_CONFIG_DIR", dir);
    }
    let mut child = cmd.spawn()?;
    let started = Instant::now();
    while child.try_wait()?.is_none() {
        if started.elapsed() > Duration::from_secs(120) {
            let _ = child.kill();
            return Err(std::io::Error::other("claude mcp list demorou demais"));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let out = child.wait_with_output()?;
    Ok(parse_list(&String::from_utf8_lossy(&out.stdout)))
}

/// Allowlist entries for a session's own servers and its connectors.
/// Names Claude Code's allowlist cannot match (only letters, digits, - and
/// _) are matched by command or URL instead.
pub fn allowlist<'a>(servers: impl IntoIterator<Item = (&'a String, &'a Value)>, connectors: &[String]) -> Value {
    let valid = |n: &str| !n.is_empty() && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    let mut out: Vec<Value> = servers
        .into_iter()
        .map(|(name, config)| {
            if valid(name) {
                json!({ "serverName": name })
            } else if let Some(url) = config.get("url").and_then(Value::as_str) {
                json!({ "serverUrl": url })
            } else {
                let mut command = vec![config.get("command").cloned().unwrap_or_default()];
                command.extend(config.get("args").and_then(Value::as_array).cloned().unwrap_or_default());
                json!({ "serverCommand": command })
            }
        })
        .collect();
    out.extend(connectors.iter().map(|url| json!({ "serverUrl": url })));
    Value::Array(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_connectors_from_mcp_list() {
        let out = "Checking MCP server health…\n\n\
            claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected\n\
            claude.ai Slack: https://mcp.slack.com/mcp - ! Needs authentication\n\
            claude.ai Box: https://mcp.box.com - ✗ Failed to connect\n\
            caveman: /x/caveman-mcp  - ✔ Connected\n";
        let c = parse_list(out);
        let got: Vec<(&str, &str, &str)> = c.iter().map(|c| (c.name.as_str(), c.url.as_str(), c.status.as_str())).collect();
        assert_eq!(
            got,
            [
                ("Gmail", "https://gmailmcp.googleapis.com/mcp/v1", "connected"),
                ("Slack", "https://mcp.slack.com/mcp", "needs_auth"),
                ("Box", "https://mcp.box.com", "failed"),
            ]
        );
    }

    #[test]
    fn allowlist_by_name_or_else_by_command_or_url() {
        let servers: std::collections::BTreeMap<String, Value> = [
            ("orc".to_string(), json!({ "command": "orc-mcp" })),
            ("my server".to_string(), json!({ "command": "npx", "args": ["x"] })),
            ("web api".to_string(), json!({ "type": "http", "url": "https://w/mcp" })),
        ]
        .into();
        let list = allowlist(&servers, &["https://mcp.slack.com/mcp".to_string()]);
        assert_eq!(
            list,
            json!([
                { "serverCommand": ["npx", "x"] },
                { "serverName": "orc" },
                { "serverUrl": "https://w/mcp" },
                { "serverUrl": "https://mcp.slack.com/mcp" },
            ])
        );
    }
}
