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
// Daemon <-> client messages
// ---------------------------------------------------------------------------

/// Messages from a client to the daemon.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    /// Sent by `orc-statusline` on every statusLine refresh.
    Status(StatusReport),
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
    Grid { session_id: String, snapshot: GridSnapshot },
    GridDiff { session_id: String, diff: GridDiff },
    Quota { account_id: String, limits: RateLimits, read_at: i64 },
    SessionExited { session_id: String, code: Option<i32> },
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

    #[test]
    fn messages_have_a_type_tag() {
        let m = ClientMessage::Input { session_id: "s1".into(), data: "ls\r".into() };
        let json = serde_json::to_string(&m).unwrap();
        assert!(json.contains(r#""type":"input""#));
        assert_eq!(serde_json::from_str::<ClientMessage>(&json).unwrap(), m);
    }
}
