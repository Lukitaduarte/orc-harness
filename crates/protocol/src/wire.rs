//! The framed wire format (ALPN `orc/2`), daemon to client: each message
//! is `[kind: u8][len: u32 BE][payload]`. JSON messages keep their shape
//! (kind 0); grid diffs and snapshots, which are most of the traffic, go
//! binary (kind 1), about twenty times smaller than their JSON.
//!
//! Grid payload (integers little endian):
//!
//! ```text
//! u8  version (1)
//! u16 session id length, bytes
//! u16 cols, u16 rows, u16 cursor row, u16 cursor col, u8 cursor visible
//! u16 changed lines
//!   u16 row, u16 runs
//!     u8 flags, color fg, color bg, u16 cells, u8 mode
//!       mode 0: one ASCII byte per cell
//!       mode 1: per cell, u8 length + UTF-8 (combining marks, wide chars)
//! color: u8 0 (default) | 1, u8 index | 2, u8 r, u8 g, u8 b
//! ```

use crate::{Cell, Cursor, DaemonMessage, GridDiff, TermColor};

pub const FRAME_JSON: u8 = 0;
pub const FRAME_GRID: u8 = 1;
const VERSION: u8 = 1;

/// `[kind][len][payload]`.
pub fn frame(kind: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(payload.len() + 5);
    out.push(kind);
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(payload);
    out
}

/// One daemon message as a frame: grids binary, the rest JSON.
pub fn encode_message(msg: &DaemonMessage) -> Vec<u8> {
    match msg {
        DaemonMessage::GridDiff { session_id, diff } => frame(FRAME_GRID, &encode_grid(session_id, diff)),
        DaemonMessage::Grid { session_id, snapshot } => {
            let diff = GridDiff {
                cols: snapshot.cols,
                rows: snapshot.rows,
                lines: snapshot.lines.iter().cloned().enumerate().map(|(i, l)| (i as u16, l)).collect(),
                cursor: snapshot.cursor,
            };
            frame(FRAME_GRID, &encode_grid(session_id, &diff))
        }
        other => frame(FRAME_JSON, &serde_json::to_vec(other).unwrap_or_default()),
    }
}

fn put_u16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn put_color(out: &mut Vec<u8>, c: TermColor) {
    match c {
        TermColor::Default => out.push(0),
        TermColor::Indexed { index } => out.extend_from_slice(&[1, index]),
        TermColor::Rgb { r, g, b } => out.extend_from_slice(&[2, r, g, b]),
    }
}

fn same_style(a: &Cell, b: &Cell) -> bool {
    a.fg == b.fg && a.bg == b.bg && a.flags == b.flags
}

pub fn encode_grid(session_id: &str, diff: &GridDiff) -> Vec<u8> {
    let mut out = Vec::with_capacity(64 + diff.lines.len() * (diff.cols as usize + 16));
    out.push(VERSION);
    put_u16(&mut out, session_id.len() as u16);
    out.extend_from_slice(session_id.as_bytes());
    for v in [diff.cols, diff.rows, diff.cursor.row, diff.cursor.col] {
        put_u16(&mut out, v);
    }
    out.push(diff.cursor.visible as u8);
    put_u16(&mut out, diff.lines.len() as u16);
    for (row, cells) in &diff.lines {
        put_u16(&mut out, *row);
        let runs_at = out.len();
        put_u16(&mut out, 0);
        let mut runs = 0u16;
        let mut i = 0;
        while i < cells.len() {
            let mut end = i + 1;
            while end < cells.len() && same_style(&cells[end], &cells[i]) && end - i < u16::MAX as usize {
                end += 1;
            }
            let run = &cells[i..end];
            out.push(run[0].flags);
            put_color(&mut out, run[0].fg);
            put_color(&mut out, run[0].bg);
            put_u16(&mut out, run.len() as u16);
            let ascii = run.iter().all(|c| c.text.len() == 1 && c.text.as_bytes()[0].is_ascii());
            if ascii {
                out.push(0);
                out.extend(run.iter().map(|c| c.text.as_bytes()[0]));
            } else {
                out.push(1);
                for c in run {
                    let t = &c.text.as_bytes()[..c.text.len().min(255)];
                    out.push(t.len() as u8);
                    out.extend_from_slice(t);
                }
            }
            runs += 1;
            i = end;
        }
        out[runs_at..runs_at + 2].copy_from_slice(&runs.to_le_bytes());
    }
    out
}

struct Reader<'a> {
    b: &'a [u8],
    at: usize,
}

impl Reader<'_> {
    fn u8(&mut self) -> Option<u8> {
        let v = *self.b.get(self.at)?;
        self.at += 1;
        Some(v)
    }
    fn u16(&mut self) -> Option<u16> {
        let s = self.b.get(self.at..self.at + 2)?;
        self.at += 2;
        Some(u16::from_le_bytes([s[0], s[1]]))
    }
    fn bytes(&mut self, n: usize) -> Option<&[u8]> {
        let s = self.b.get(self.at..self.at + n)?;
        self.at += n;
        Some(s)
    }
    fn color(&mut self) -> Option<TermColor> {
        Some(match self.u8()? {
            0 => TermColor::Default,
            1 => TermColor::Indexed { index: self.u8()? },
            2 => TermColor::Rgb { r: self.u8()?, g: self.u8()?, b: self.u8()? },
            _ => return None,
        })
    }
}

/// The inverse of [`encode_grid`]; None on anything malformed.
pub fn decode_grid(b: &[u8]) -> Option<(String, GridDiff)> {
    let mut r = Reader { b, at: 0 };
    if r.u8()? != VERSION {
        return None;
    }
    let n = r.u16()? as usize;
    let session = String::from_utf8(r.bytes(n)?.to_vec()).ok()?;
    let (cols, rows, crow, ccol) = (r.u16()?, r.u16()?, r.u16()?, r.u16()?);
    let visible = r.u8()? != 0;
    let mut lines = Vec::new();
    for _ in 0..r.u16()? {
        let row = r.u16()?;
        let mut cells = Vec::new();
        for _ in 0..r.u16()? {
            let (flags, fg, bg) = (r.u8()?, r.color()?, r.color()?);
            let count = r.u16()? as usize;
            match r.u8()? {
                0 => {
                    for &c in r.bytes(count)? {
                        cells.push(Cell { text: (c as char).to_string(), fg, bg, flags });
                    }
                }
                1 => {
                    for _ in 0..count {
                        let len = r.u8()? as usize;
                        let text = String::from_utf8(r.bytes(len)?.to_vec()).ok()?;
                        cells.push(Cell { text, fg, bg, flags });
                    }
                }
                _ => return None,
            }
        }
        lines.push((row, cells));
    }
    Some((session, GridDiff { cols, rows, lines, cursor: Cursor { row: crow, col: ccol, visible } }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cell_flags;

    fn cell(text: &str, fg: TermColor, bg: TermColor, flags: u8) -> Cell {
        Cell { text: text.into(), fg, bg, flags }
    }

    /// The same sample the app's decoder test reads (app/test/wire_test.dart).
    pub fn sample() -> GridDiff {
        let d = TermColor::Default;
        let red = TermColor::Indexed { index: 1 };
        let teal = TermColor::Rgb { r: 0, g: 128, b: 128 };
        GridDiff {
            cols: 6,
            rows: 3,
            lines: vec![
                (0, vec![cell("o", d, d, 0), cell("k", d, d, 0), cell("!", red, d, cell_flags::BOLD)]),
                (2, vec![cell("é", teal, red, 0), cell("界", d, d, 0), cell("", d, d, cell_flags::WIDE_SPACER)]),
            ],
            cursor: Cursor { row: 2, col: 3, visible: true },
        }
    }

    pub const SAMPLE_HEX: &str = "01020073310600030002000300010200000002000000000200006f6b0101010001000021020003000002008080010101000102c3a900000001000103e7958c40000001000100";

    #[test]
    fn grid_round_trips_and_matches_the_app_fixture() {
        let bytes = encode_grid("s1", &sample());
        let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(hex, SAMPLE_HEX, "the Dart test decodes this exact hex");
        assert_eq!(decode_grid(&bytes), Some(("s1".to_string(), sample())));
        assert_eq!(decode_grid(&bytes[..bytes.len() - 1]), None);
    }

    #[test]
    fn binary_is_much_smaller_than_json() {
        let line: Vec<Cell> = "  fn main() { println!(\"hello, world\"); }                                       "
            .chars()
            .map(|c| cell(&c.to_string(), TermColor::Default, TermColor::Default, 0))
            .collect();
        let diff = GridDiff { cols: 80, rows: 40, lines: (0..40).map(|r| (r, line.clone())).collect(), cursor: Cursor::default() };
        let msg = DaemonMessage::GridDiff { session_id: "s1".into(), diff };
        let json = serde_json::to_vec(&msg).unwrap().len();
        let bin = encode_message(&msg).len();
        assert!(bin * 15 < json, "binary {bin} vs json {json}");
    }

    #[test]
    fn other_messages_stay_json() {
        let m = DaemonMessage::Error { message: "x".into() };
        let f = encode_message(&m);
        assert_eq!(f[0], FRAME_JSON);
        assert_eq!(u32::from_be_bytes([f[1], f[2], f[3], f[4]]) as usize, f.len() - 5);
        assert_eq!(serde_json::from_slice::<DaemonMessage>(&f[5..]).unwrap(), m);
    }
}
