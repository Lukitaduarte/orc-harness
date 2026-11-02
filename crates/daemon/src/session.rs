//! A session is one process (Claude Code, or anything else) running in a
//! PTY. The daemon owns the terminal emulation: bytes from the PTY go into
//! an `alacritty_terminal` `Term`, and clients get the cell grid, never the
//! raw escape codes.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::Dimensions;
use alacritty_terminal::index::{Column, Line};
use alacritty_terminal::term::cell::Flags;
use alacritty_terminal::term::{Config, Term, TermMode};
use alacritty_terminal::vte::ansi::{Color, NamedColor, Processor};
use orc_protocol::{Cell, Cursor, GridSnapshot, TermColor, cell_flags};
use portable_pty::{Child, CommandBuilder, MasterPty, PtySize, native_pty_system};

/// What to run and where.
#[derive(Debug, Clone)]
pub struct SessionSpec {
    pub program: String,
    pub args: Vec<String>,
    /// Extra environment, e.g. `CLAUDE_CONFIG_DIR` for the account.
    pub env: HashMap<String, String>,
    /// Working directory (a card's worktree). `None` means the daemon's
    /// current directory, never the home folder portable-pty would pick.
    pub cwd: Option<PathBuf>,
    pub cols: u16,
    pub rows: u16,
}

impl SessionSpec {
    pub fn new(program: impl Into<String>, args: &[&str]) -> Self {
        Self {
            program: program.into(),
            args: args.iter().map(|a| a.to_string()).collect(),
            env: HashMap::new(),
            cwd: None,
            cols: 100,
            rows: 30,
        }
    }
}

#[derive(Clone, Copy)]
struct Size {
    cols: usize,
    rows: usize,
}

impl Dimensions for Size {
    fn total_lines(&self) -> usize {
        self.rows
    }
    fn screen_lines(&self) -> usize {
        self.rows
    }
    fn columns(&self) -> usize {
        self.cols
    }
}

type Writer = Arc<Mutex<Box<dyn Write + Send>>>;

/// Answers terminal queries (cursor position, device attributes) back into
/// the PTY; programs that ask and get no answer can hang.
struct Replies(Writer);

impl EventListener for Replies {
    fn send_event(&self, event: Event) {
        if let Event::PtyWrite(text) = event
            && let Ok(mut w) = self.0.lock()
        {
            let _ = w.write_all(text.as_bytes());
            let _ = w.flush();
        }
    }
}

struct Screen {
    term: Term<Replies>,
    parser: Processor,
    /// Bumped on every chunk of output, so waiters can tell something changed.
    generation: u64,
    exited: Option<Option<i32>>,
}

pub struct Session {
    screen: Arc<(Mutex<Screen>, Condvar)>,
    writer: Writer,
    master: Box<dyn MasterPty + Send>,
    child: Arc<Mutex<Box<dyn Child + Send + Sync>>>,
}

impl Session {
    pub fn spawn(spec: &SessionSpec) -> std::io::Result<Self> {
        let pty = native_pty_system()
            .openpty(PtySize {
                rows: spec.rows,
                cols: spec.cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(other)?;
        let mut cmd = CommandBuilder::new(&spec.program);
        cmd.args(&spec.args);
        cmd.env("TERM", "xterm-256color");
        cmd.env("COLORTERM", "truecolor");
        for (k, v) in &spec.env {
            cmd.env(k, v);
        }
        let cwd = match &spec.cwd {
            Some(dir) => dir.clone(),
            None => std::env::current_dir()?,
        };
        cmd.cwd(cwd);
        let child = pty.slave.spawn_command(cmd).map_err(other)?;
        drop(pty.slave);

        let writer: Writer = Arc::new(Mutex::new(pty.master.take_writer().map_err(other)?));
        let mut reader = pty.master.try_clone_reader().map_err(other)?;
        let size = Size { cols: spec.cols as usize, rows: spec.rows as usize };
        let screen = Arc::new((
            Mutex::new(Screen {
                term: Term::new(Config::default(), &size, Replies(writer.clone())),
                parser: Processor::new(),
                generation: 0,
                exited: None,
            }),
            Condvar::new(),
        ));
        let child = Arc::new(Mutex::new(child));

        let (screen2, child2) = (screen.clone(), child.clone());
        thread::spawn(move || {
            let mut buf = [0u8; 8192];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        let (lock, changed) = &*screen2;
                        let mut s = lock.lock().unwrap();
                        let Screen { term, parser, .. } = &mut *s;
                        parser.advance(term, &buf[..n]);
                        s.generation += 1;
                        changed.notify_all();
                    }
                }
            }
            // Output closed: record the exit code for clients.
            let code = child2
                .lock()
                .ok()
                .and_then(|mut c| c.wait().ok())
                .map(|status| status.exit_code() as i32);
            let (lock, changed) = &*screen2;
            let mut s = lock.lock().unwrap();
            s.exited = Some(code);
            s.generation += 1;
            changed.notify_all();
        });

        Ok(Self { screen, writer, master: pty.master, child })
    }

    /// Sends keystrokes or pasted text to the process.
    pub fn write(&self, data: &[u8]) -> std::io::Result<()> {
        let mut w = self.writer.lock().unwrap();
        w.write_all(data)?;
        w.flush()
    }

    pub fn resize(&self, cols: u16, rows: u16) -> std::io::Result<()> {
        self.master
            .resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .map_err(other)?;
        let (lock, _) = &*self.screen;
        lock.lock()
            .unwrap()
            .term
            .resize(Size { cols: cols as usize, rows: rows as usize });
        Ok(())
    }

    /// `Some(code)` once the process exited (code may be unknown).
    pub fn exited(&self) -> Option<Option<i32>> {
        self.screen.0.lock().unwrap().exited
    }

    pub fn kill(&self) {
        if let Ok(mut c) = self.child.lock() {
            let _ = c.kill();
        }
    }

    pub fn snapshot(&self) -> GridSnapshot {
        snapshot(&self.screen.0.lock().unwrap().term)
    }

    /// Waits until `done` holds for the screen or the process exited, up to
    /// `timeout`. Returns the last snapshot either way.
    pub fn wait_for(
        &self,
        timeout: Duration,
        mut done: impl FnMut(&GridSnapshot) -> bool,
    ) -> GridSnapshot {
        let deadline = Instant::now() + timeout;
        let (lock, changed) = &*self.screen;
        let mut s = lock.lock().unwrap();
        loop {
            let snap = snapshot(&s.term);
            if done(&snap) || s.exited.is_some() {
                return snap;
            }
            let now = Instant::now();
            if now >= deadline {
                return snap;
            }
            s = changed.wait_timeout(s, deadline - now).unwrap().0;
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.kill();
    }
}

fn snapshot<T: EventListener>(term: &Term<T>) -> GridSnapshot {
    let grid = term.grid();
    let (cols, rows) = (grid.columns(), grid.screen_lines());
    let lines = (0..rows)
        .map(|r| {
            let row = &grid[Line(r as i32)];
            (0..cols)
                .map(|c| {
                    let cell = &row[Column(c)];
                    let mut text = cell.c.to_string();
                    if let Some(marks) = cell.zerowidth() {
                        text.extend(marks);
                    }
                    Cell {
                        text,
                        fg: color(cell.fg),
                        bg: color(cell.bg),
                        flags: flags(cell.flags),
                    }
                })
                .collect()
        })
        .collect();
    let point = grid.cursor.point;
    GridSnapshot {
        cols: cols as u16,
        rows: rows as u16,
        lines,
        cursor: Cursor {
            row: point.line.0.max(0) as u16,
            col: point.column.0 as u16,
            visible: term.mode().contains(TermMode::SHOW_CURSOR),
        },
    }
}

fn color(c: Color) -> TermColor {
    match c {
        Color::Spec(rgb) => TermColor::Rgb { r: rgb.r, g: rgb.g, b: rgb.b },
        Color::Indexed(index) => TermColor::Indexed { index },
        // The 16 ANSI colors are the first 16 indexed ones; foreground,
        // background and the dim variants fall back to the theme default.
        Color::Named(n) if (n as usize) < 16 => TermColor::Indexed { index: n as u8 },
        Color::Named(NamedColor::Foreground | NamedColor::Background) | Color::Named(_) => {
            TermColor::Default
        }
    }
}

fn flags(f: Flags) -> u8 {
    let mut out = 0;
    for (from, to) in [
        (Flags::BOLD, cell_flags::BOLD),
        (Flags::ITALIC, cell_flags::ITALIC),
        (Flags::ALL_UNDERLINES, cell_flags::UNDERLINE),
        (Flags::INVERSE, cell_flags::INVERSE),
        (Flags::DIM, cell_flags::DIM),
        (Flags::STRIKEOUT, cell_flags::STRIKEOUT),
        (Flags::WIDE_CHAR_SPACER, cell_flags::WIDE_SPACER),
    ] {
        if f.intersects(from) {
            out |= to;
        }
    }
    out
}

fn other(e: impl std::fmt::Display) -> std::io::Error {
    std::io::Error::other(e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const WAIT: Duration = Duration::from_secs(5);

    #[test]
    fn renders_text_colors_and_cursor_moves() {
        // Red "red", then jump to row 5 col 10 and write X.
        let s = Session::spawn(&SessionSpec::new(
            "printf",
            &["hello \\033[31mred\\033[0m\\033[5;10HX"],
        ))
        .unwrap();
        let snap = s.wait_for(WAIT, |g| g.line_text(4).ends_with('X'));
        assert_eq!(snap.line_text(0), "hello red");
        assert_eq!(snap.lines[0][6].fg, TermColor::Indexed { index: 1 });
        assert_eq!(snap.lines[0][0].fg, TermColor::Default);
        assert_eq!(snap.lines[4][9].text, "X");
    }

    #[test]
    fn input_reaches_the_process_and_size_is_respected() {
        let mut spec = SessionSpec::new("cat", &[]);
        spec.cols = 40;
        spec.rows = 10;
        let s = Session::spawn(&spec).unwrap();
        s.write(b"orc harness\r").unwrap();
        let snap = s.wait_for(WAIT, |g| (0..10).any(|r| g.line_text(r) == "orc harness"));
        assert_eq!((snap.cols, snap.rows), (40, 10));
        assert!((0..10).any(|r| snap.line_text(r) == "orc harness"));
    }

    #[test]
    fn reports_exit() {
        let s = Session::spawn(&SessionSpec::new("sh", &["-c", "exit 3"])).unwrap();
        s.wait_for(WAIT, |_| false);
        assert_eq!(s.exited(), Some(Some(3)));
    }

    #[test]
    fn starts_in_the_given_directory_and_defaults_to_the_current_one() {
        let dir = tempfile::tempdir().unwrap();
        let mut spec = SessionSpec::new("pwd", &[]);
        spec.cwd = Some(dir.path().to_path_buf());
        let s = Session::spawn(&spec).unwrap();
        let snap = s.wait_for(WAIT, |_| false);
        let expected = dir.path().canonicalize().unwrap();
        assert_eq!(snap.line_text(0), expected.to_string_lossy());

        let s = Session::spawn(&SessionSpec::new("pwd", &[])).unwrap();
        let snap = s.wait_for(WAIT, |_| false);
        let here = std::env::current_dir().unwrap().canonicalize().unwrap();
        assert_eq!(snap.line_text(0), here.to_string_lossy());
    }

    #[test]
    fn env_is_passed_for_the_account() {
        let mut spec = SessionSpec::new("sh", &["-c", "printf \"$CLAUDE_CONFIG_DIR\""]);
        spec.env.insert("CLAUDE_CONFIG_DIR".into(), "/tmp/orc/work-main".into());
        let s = Session::spawn(&spec).unwrap();
        let snap = s.wait_for(WAIT, |g| g.line_text(0).contains("work-main"));
        assert_eq!(snap.line_text(0), "/tmp/orc/work-main");
    }
}
