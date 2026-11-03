//! Types shared by the daemon and its clients (the Flutter app through
//! `client-core`, and the helper binaries Claude Code runs).
//!
//! Everything here is plain data with a stable JSON shape; transport is
//! somebody else's job.

use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Claude Code statusLine input
// ---------------------------------------------------------------------------

/// The part of Claude Code's statusLine JSON the harness reads. Unknown
/// fields are ignored, so newer Claude Code versions keep working.
#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct StatusLineInput {
    pub session_id: Option<String>,
    pub model: Option<ModelInfo>,
    pub cost: Option<CostInfo>,
    pub context_window: Option<ContextWindow>,
    /// Present only for Pro/Max subscribers, after the first API response.
    pub rate_limits: Option<RateLimits>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct ModelInfo {
    pub id: Option<String>,
    pub display_name: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct CostInfo {
    pub total_cost_usd: Option<f64>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct ContextWindow {
    pub total_input_tokens: Option<u64>,
    pub total_output_tokens: Option<u64>,
    pub used_percentage: Option<f64>,
}

/// Subscription rate-limit windows, as Claude Code reports them.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct RateLimits {
    pub five_hour: Option<QuotaWindow>,
    pub seven_day: Option<QuotaWindow>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct QuotaWindow {
    /// 0 to 100.
    pub used_percentage: f64,
    /// Unix epoch seconds when the window resets.
    pub resets_at: i64,
}

/// What the `orc-statusline` helper sends the daemon for each statusLine
/// refresh: who it came from and what Claude Code reported.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StatusReport {
    pub account_id: String,
    pub session_id: String,
    pub rate_limits: Option<RateLimits>,
    pub cost_usd: Option<f64>,
    pub tokens: Option<u64>,
    /// Unix epoch seconds when the helper received it.
    pub read_at: i64,
}

impl StatusReport {
    pub fn from_input(
        account_id: impl Into<String>,
        session_id: impl Into<String>,
        input: &StatusLineInput,
        read_at: i64,
    ) -> Self {
        let tokens = input.context_window.as_ref().and_then(|c| {
            match (c.total_input_tokens, c.total_output_tokens) {
                (None, None) => None,
                (i, o) => Some(i.unwrap_or(0) + o.unwrap_or(0)),
            }
        });
        Self {
            account_id: account_id.into(),
            session_id: input
                .session_id
                .clone()
                .unwrap_or_else(|| session_id.into()),
            rate_limits: input.rate_limits.clone(),
            cost_usd: input.cost.as_ref().and_then(|c| c.total_cost_usd),
            tokens,
            read_at,
        }
    }
}

// ---------------------------------------------------------------------------
// Terminal grid
// ---------------------------------------------------------------------------

/// A terminal color: the default, one of the 256 indexed colors, or RGB.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum TermColor {
    #[default]
    Default,
    Indexed { index: u8 },
    Rgb { r: u8, g: u8, b: u8 },
}

pub mod cell_flags {
    pub const BOLD: u8 = 1;
    pub const ITALIC: u8 = 1 << 1;
    pub const UNDERLINE: u8 = 1 << 2;
    pub const INVERSE: u8 = 1 << 3;
    pub const DIM: u8 = 1 << 4;
    pub const STRIKEOUT: u8 = 1 << 5;
    /// The right half of a double-width character: draw nothing.
    pub const WIDE_SPACER: u8 = 1 << 6;
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Cell {
    /// The character, plus any zero-width combining marks.
    pub text: String,
    pub fg: TermColor,
    pub bg: TermColor,
    pub flags: u8,
}

/// The visible screen of a session. The daemon emulates the terminal; the
/// app only draws this.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct GridSnapshot {
    pub cols: u16,
    pub rows: u16,
    /// Row-major, `rows` lines of `cols` cells.
    pub lines: Vec<Vec<Cell>>,
    pub cursor: Cursor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Cursor {
    pub row: u16,
    pub col: u16,
    pub visible: bool,
}

/// Only the lines that changed since the previous snapshot.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GridDiff {
    pub cols: u16,
    pub rows: u16,
    pub lines: Vec<(u16, Vec<Cell>)>,
    pub cursor: Cursor,
}

impl GridSnapshot {
    /// Lines that differ from `previous`; every line when the size changed.
    pub fn diff_from(&self, previous: &GridSnapshot) -> GridDiff {
        let same_size = self.cols == previous.cols && self.rows == previous.rows;
        let lines = self
            .lines
            .iter()
            .enumerate()
            .filter(|(i, line)| !same_size || previous.lines.get(*i) != Some(*line))
            .map(|(i, line)| (i as u16, line.clone()))
            .collect();
        GridDiff {
            cols: self.cols,
            rows: self.rows,
            lines,
            cursor: self.cursor,
        }
    }

    pub fn apply(&mut self, diff: &GridDiff) {
        if diff.cols != self.cols || diff.rows != self.rows {
            self.cols = diff.cols;
            self.rows = diff.rows;
            self.lines = vec![Vec::new(); diff.rows as usize];
        }
        for (i, line) in &diff.lines {
            if let Some(slot) = self.lines.get_mut(*i as usize) {
                *slot = line.clone();
            }
        }
        self.cursor = diff.cursor;
    }

    /// Plain text of a line, trailing spaces trimmed. For tests and search.
    pub fn line_text(&self, row: usize) -> String {
        self.lines
            .get(row)
            .map(|l| l.iter().map(|c| c.text.as_str()).collect::<String>())
            .unwrap_or_default()
            .trim_end()
            .to_string()
    }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// Session state, driven by Claude Code's hooks.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Starting,
    /// Working on a prompt.
    Running,
    /// Asked for permission or input.
    WaitingInput,
    /// Finished its turn.
    Idle,
    Exited,
}

/// Skills, MCP servers and env a session runs with, picked from the
/// catalog. Changing it restarts the session with `--resume`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Profile {
    /// Skill folders (each with a SKILL.md).
    #[serde(default)]
    pub skills: Vec<String>,
    /// MCP servers in Claude Code's `mcpServers` format.
    #[serde(default)]
    pub mcp_servers: std::collections::BTreeMap<String, serde_json::Value>,
    /// Env names; the daemon reads the values from the Keychain when it
    /// starts the session. Values never travel in a profile.
    #[serde(default)]
    pub env_names: Vec<String>,
    pub model: Option<String>,
}

/// One item of the global catalog, configured once, enabled per session.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CatalogEntry {
    pub id: String,
    /// `skill`, `mcp` or `env`.
    pub kind: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    /// Skill folder (with a SKILL.md).
    #[serde(default)]
    pub path: Option<String>,
    /// MCP server config in Claude Code's `mcpServers` entry format.
    #[serde(default)]
    pub mcp: Option<serde_json::Value>,
    /// Env: whether the Keychain has a value. Filled by the daemon.
    #[serde(default)]
    pub has_value: bool,
}

/// A plan mode template: markdown in `~/.orc/templates/<id>.md`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlanTemplateFile {
    pub id: String,
    pub markdown: String,
}

/// Token and cost totals, from Claude Code's OpenTelemetry metrics.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
pub struct Usage {
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_creation: u64,
    pub cost_usd: f64,
}

impl Usage {
    pub fn tokens(&self) -> u64 {
        self.input + self.output + self.cache_read + self.cache_creation
    }
}

/// One row of the usage report: a day, an account, a model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UsageRow {
    /// YYYY-MM-DD, UTC.
    pub day: String,
    pub account_id: String,
    pub model: String,
    pub usage: Usage,
}

/// A local repository the daemon creates worktrees from.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectInfo {
    pub id: String,
    pub name: String,
    /// Path of the main clone.
    pub repo: String,
    pub base_branch: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiffFile {
    pub path: String,
    /// A, M, D, R… as git reports it; `?` for untracked.
    pub status: String,
    /// Unified diff of the file; empty for untracked files.
    pub patch: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchHit {
    pub path: String,
    pub line: u32,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionSummary {
    pub id: String,
    pub account_id: String,
    pub cwd: String,
    pub state: SessionState,
    pub model: Option<String>,
    /// Claude Code's own session id, used for `--resume`.
    pub claude_session_id: String,
    /// Set when the session runs in a project worktree.
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub branch: Option<String>,
}

// ---------------------------------------------------------------------------
// Daemon <-> client messages
// ---------------------------------------------------------------------------

/// Messages from a client to the daemon.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    /// Sent by `orc-statusline` on every statusLine refresh.
    Status(StatusReport),
    /// Sent by `orc-hook` for Claude Code hook events (Stop, Notification…).
    Hook { session_id: String, event: String },
    CreateSession {
        account_id: String,
        cwd: Option<String>,
        profile: Profile,
        cols: u16,
        rows: u16,
    },
    /// Restarts the session with the new profile, keeping the conversation.
    ApplyProfile { session_id: String, profile: Profile },
    StopSession { session_id: String },
    /// Ask for the session list (sent on connect).
    ListSessions,
    /// Mint a pairing ticket. Honored only on the owner-only local socket.
    NewPairingTicket,
    /// Stores an env value in the daemon's Keychain. The value is never
    /// sent back to any client.
    SetSecret { name: String, value: String },
    DeleteSecret { name: String },
    UpsertCatalog { entry: CatalogEntry },
    RemoveCatalog { id: String },
    /// Starts the MCP and lists its tools, to check it works.
    TestMcp { id: String },
    UpsertTemplate { template: PlanTemplateFile },
    RemoveTemplate { id: String },
    /// Usage per day, account and model for the last `days` days.
    UsageReport { days: u32 },
    AddProject { name: String, repo: String, base_branch: String },
    RemoveProject { id: String },
    /// A worktree on `branch` (created from the base if new) and a session
    /// in it, with conventional commits enforced.
    CreateWorktreeSession {
        project_id: String,
        branch: String,
        account_id: String,
        profile: Profile,
        cols: u16,
        rows: u16,
    },
    /// Changes of the session's worktree against its base branch.
    Diff { session_id: String },
    /// Text search (regex when `regex`) in a project or session folder.
    Search { project_id: Option<String>, session_id: Option<String>, query: String, regex: bool },
    /// The GitHub PR of the session's branch, through `gh`.
    PrStatus { session_id: String },
    /// Keystrokes or pasted text for a session's terminal.
    Input { session_id: String, data: String },
    Resize { session_id: String, cols: u16, rows: u16 },
    /// Ask for the full grid (on attach or after losing diffs).
    Snapshot { session_id: String },
}

/// Messages from the daemon to clients.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum DaemonMessage {
    /// Accounts the daemon knows, sent on connect.
    Hello { accounts: Vec<String> },
    Sessions { sessions: Vec<SessionSummary> },
    SessionState { session_id: String, state: SessionState },
    Error { message: String },
    Grid { session_id: String, snapshot: GridSnapshot },
    GridDiff { session_id: String, diff: GridDiff },
    Quota { account_id: String, limits: RateLimits, read_at: i64 },
    SessionExited { session_id: String, code: Option<i32> },
    PairingTicket { ticket: String },
    /// A secret was stored (or deleted, with `stored: false`); no value.
    Secret { name: String, stored: bool },
    Catalog { entries: Vec<CatalogEntry>, templates: Vec<PlanTemplateFile> },
    McpTest { id: String, ok: bool, tools: usize, error: Option<String> },
    /// A session's running totals, sent as metrics arrive.
    SessionUsage { session_id: String, usage: Usage },
    UsageReport { rows: Vec<UsageRow> },
    Projects { projects: Vec<ProjectInfo> },
    Diff { session_id: String, base: String, files: Vec<DiffFile> },
    SearchResults { query: String, hits: Vec<SearchHit>, truncated: bool },
    /// `gh pr view` JSON (number, state, url, checks, review), or `none`.
    Pr { session_id: String, pr: Option<serde_json::Value> },
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Trimmed copy of the example in Claude Code's statusLine docs.
    const DOCS_EXAMPLE: &str = r#"{
      "cwd": "/current/working/directory",
      "session_id": "abc123",
      "model": { "id": "claude-opus-5-5", "display_name": "Opus" },
      "cost": { "total_cost_usd": 0.01234, "total_duration_ms": 45000 },
      "context_window": { "total_input_tokens": 15500, "total_output_tokens": 1200, "used_percentage": 8 },
      "prompt_cache": { "warm": true },
      "rate_limits": {
        "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
        "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
      }
    }"#;

    #[test]
    fn reads_rate_limits_and_ignores_unknown_fields() {
        let input: StatusLineInput = serde_json::from_str(DOCS_EXAMPLE).unwrap();
        let limits = input.rate_limits.clone().unwrap();
        assert_eq!(limits.five_hour.unwrap().used_percentage, 23.5);
        assert_eq!(limits.seven_day.unwrap().resets_at, 1738857600);

        let report = StatusReport::from_input("work-main", "fallback", &input, 42);
        assert_eq!(report.session_id, "abc123");
        assert_eq!(report.tokens, Some(16700));
        assert_eq!(report.cost_usd, Some(0.01234));
    }

    #[test]
    fn rate_limits_are_optional() {
        let input: StatusLineInput =
            serde_json::from_str(r#"{"model":{"display_name":"Opus"}}"#).unwrap();
        assert!(input.rate_limits.is_none());
    }

    #[test]
    fn diff_carries_only_changed_lines_and_applies_back() {
        let line = |s: &str| {
            s.chars()
                .map(|c| Cell { text: c.to_string(), ..Cell::default() })
                .collect::<Vec<_>>()
        };
        let a = GridSnapshot {
            cols: 3,
            rows: 2,
            lines: vec![line("abc"), line("def")],
            cursor: Cursor::default(),
        };
        let mut b = a.clone();
        b.lines[1] = line("xyz");
        let diff = b.diff_from(&a);
        assert_eq!(diff.lines.len(), 1);
        assert_eq!(diff.lines[0].0, 1);

        let mut c = a.clone();
        c.apply(&diff);
        assert_eq!(c, b);
    }

    /// The exact JSON the app parses (app/test/live_test.dart uses this
    /// same string): if serialization changes, both tests must change.
    pub const GRID_DIFF_JSON: &str = r#"{"type":"grid_diff","session_id":"s1","diff":{"cols":4,"rows":2,"lines":[[1,[{"text":"h","fg":{"kind":"indexed","index":1},"bg":{"kind":"default"},"flags":1},{"text":"i","fg":{"kind":"rgb","r":1,"g":2,"b":3},"bg":{"kind":"default"},"flags":0}]]],"cursor":{"row":1,"col":2,"visible":true}}}"#;

    #[test]
    fn grid_diff_json_is_what_the_app_expects() {
        let cell = |text: &str, fg, flags| Cell { text: text.into(), fg, bg: TermColor::Default, flags };
        let msg = DaemonMessage::GridDiff {
            session_id: "s1".into(),
            diff: GridDiff {
                cols: 4,
                rows: 2,
                lines: vec![(
                    1,
                    vec![
                        cell("h", TermColor::Indexed { index: 1 }, cell_flags::BOLD),
                        cell("i", TermColor::Rgb { r: 1, g: 2, b: 3 }, 0),
                    ],
                )],
                cursor: Cursor { row: 1, col: 2, visible: true },
            },
        };
        assert_eq!(serde_json::to_string(&msg).unwrap(), GRID_DIFF_JSON);
    }

    #[test]
    fn messages_have_a_type_tag() {
        let m = ClientMessage::Input { session_id: "s1".into(), data: "ls\r".into() };
        let json = serde_json::to_string(&m).unwrap();
        assert!(json.contains(r#""type":"input""#));
        assert_eq!(serde_json::from_str::<ClientMessage>(&json).unwrap(), m);
    }
}
