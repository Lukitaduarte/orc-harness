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
    /// Workspace browser the session's agent drives (Playwright MCP over
    /// CDP); the daemon opens it if needed.
    #[serde(default)]
    pub browser: Option<String>,
    /// claude.ai connectors let in, by URL (see `Connector`).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub connectors: Vec<String>,
}

/// An MCP server the account added on claude.ai, as Claude Code lists it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Connector {
    /// As on claude.ai (Claude Code shows it as `claude.ai <name>`).
    pub name: String,
    pub url: String,
    /// `connected`, `needs_auth` (connect it on claude.ai) or `failed`.
    pub status: String,
}

/// One entry of a folder in the IDE's file tree.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DirEntry {
    pub name: String,
    pub dir: bool,
}

/// What the app asks of a workspace browser.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum BrowserAction {
    /// Opens the browser if needed, then goes to `url` if given.
    Open { url: Option<String> },
    Back,
    Forward,
    Reload,
    /// The pane's size in logical pixels.
    Resize { width: u32, height: u32 },
    /// `{kind: mouse|text|key, …}`, see browser::Browser::input.
    Input { event: serde_json::Value },
    Close,
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

/// An MCP server found in your Claude Code config, offered for the
/// catalog. Secret values were already replaced by `${NAME}` references.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct McpImport {
    pub key: String,
    /// Where it was found (account and project, or repository).
    pub label: String,
    pub name: String,
    pub mcp: serde_json::Value,
    /// Envs whose values move to the Keychain on import.
    #[serde(default)]
    pub secrets: Vec<String>,
    /// The catalog already has an MCP with this name.
    #[serde(default)]
    pub in_catalog: bool,
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
    /// Set for sessions in a project worktree (a branch is a plan's card).
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub branch: Option<String>,
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
    /// The workspace it belongs to (none: the first one).
    #[serde(default)]
    pub workspace_id: Option<String>,
}

/// A skill change proposed by Learn: replace `old` (empty: append) with
/// `new` in `file` of skill `skill`. Applied only when you accept it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearningItem {
    pub id: String,
    pub skill: String,
    pub file: String,
    pub summary: String,
    pub old: String,
    pub new: String,
    /// Which comment it came from.
    pub source: String,
    /// pending, applied, declined or failed.
    pub status: String,
    #[serde(default)]
    pub error: Option<String>,
}

/// A workspace: a name and the accounts in it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceInfo {
    pub id: String,
    pub name: String,
    pub accounts: Vec<String>,
    /// Memory provider of its sessions: none or `orc` (the harness's
    /// own), `off`, or the id of a catalog MCP (mem0, basic-memory…).
    #[serde(default)]
    pub memory: Option<String>,
    /// Monthly budget in US$; the app warns at 80% and 100%.
    #[serde(default)]
    pub budget_usd: Option<f64>,
}

/// A subfolder in the folder picker.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FolderEntry {
    pub name: String,
    pub repo: bool,
}

/// A paired app (desktop or phone).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeviceInfo {
    /// Its iroh key.
    pub id: String,
    pub name: String,
    /// Unix seconds.
    pub paired_at: i64,
    pub connected: bool,
    /// The device asking.
    #[serde(default)]
    pub this: bool,
}

/// One entry of the harness's memory provider.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MemoryEntry {
    pub id: String,
    /// Unix seconds.
    pub at: i64,
    /// The session that remembered it.
    pub session: String,
    pub text: String,
    #[serde(default)]
    pub tags: Vec<String>,
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

/// A plan kept by the daemon: the markdown plus the review state the app
/// keeps (approvals, comments, amendments) as JSON. The planning session
/// writes the markdown (and replies to comments) through `save_plan`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct PlanDoc {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub markdown: String,
    #[serde(default)]
    pub state: serde_json::Value,
    /// The Claude session writing this plan, while it lives.
    #[serde(default)]
    pub planner: Option<String>,
    /// Times the planning session saved the plan.
    #[serde(default)]
    pub revision: u32,
    /// The planning session is working on a request.
    #[serde(default)]
    pub busy: bool,
}

/// A loop of an approved plan, as the daemon runs it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CardSpec {
    pub number: u32,
    pub title: String,
    pub branch: String,
    pub model: Option<String>,
    #[serde(default)]
    pub depends_on: Vec<u32>,
    /// The full instruction the card's session starts with.
    pub prompt: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CardRun {
    pub number: u32,
    /// todo, running, review, done; failed (did not start) or stopped
    /// (session ended without a PR), both retried with `RetryCard`.
    pub state: String,
    pub session_id: Option<String>,
    pub branch: String,
    pub pr: Option<u64>,
    pub pr_url: Option<String>,
    /// Why the card is failed, stopped or waiting (quota).
    #[serde(default)]
    pub note: Option<String>,
    /// The account its session runs on (the one with most room).
    #[serde(default)]
    pub account_id: Option<String>,
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
    /// What the session runs with, filled in for clients (kept apart on
    /// disk), so the app shows what is really on after a restart.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<Profile>,
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
    AddProject {
        name: String,
        repo: String,
        base_branch: String,
        #[serde(default)]
        workspace_id: Option<String>,
    },
    UpsertWorkspace { workspace: WorkspaceInfo },
    RemoveWorkspace { id: String },
    /// A new Claude Code account with its own config folder (log in from a
    /// session on it), placed in `workspace_id`.
    AddAccount { id: String, workspace_id: String },
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
    /// A harness MCP tool call from a session (sent by `orc-mcp` over the
    /// local socket; the session id comes from its environment).
    McpCall { session_id: String, tool: String, args: serde_json::Value },
    /// Your answer to an agent asking to store an env value.
    ResolveEnvRequest { id: String, approve: bool },
    /// Your answer to an agent asking to add an MCP server; approving adds
    /// it to the catalog and restarts that session with it (`--resume`).
    ResolveMcpRequest { id: String, approve: bool },
    /// Lists the MCP servers already set up in Claude Code (accounts'
    /// `.claude.json`, repositories' `.mcp.json`).
    ScanMcpImports,
    /// The account's claude.ai connectors (slow: Claude Code checks each).
    ListConnectors { account_id: String },
    /// Brings those (by key) into the catalog; secrets go to the Keychain.
    ImportMcps { keys: Vec<String> },
    /// Saves a plan (new or updated) with its review state.
    SavePlan { plan: PlanDoc },
    /// Deletes a plan. A plan running cards is refused unless `force`,
    /// which first stops its card, planning and learning sessions
    /// (branches, worktrees and PRs stay).
    RemovePlan {
        id: String,
        #[serde(default)]
        force: bool,
    },
    /// Runs an approved plan's loops as worktree sessions on `account_id`.
    StartPlan { plan_id: String, account_id: String, cards: Vec<CardSpec> },
    /// Asks the plan's planning session (started if needed, in the project's
    /// repository) to draft the plan or address comments.
    AskPlanner { plan_id: String, account_id: String, request: String },
    /// Opens a session in the worktrees folder so you can answer Claude
    /// Code's folder trust question once for all worktrees.
    TrustWorktrees { account_id: String },
    Browser { profile: String, action: BrowserAction },
    /// IDE: files under the session's folder; paths are relative to it.
    ListDir { session_id: String, path: String },
    ReadFile { session_id: String, path: String },
    WriteFile { session_id: String, path: String, text: String },
    /// A JSON-RPC message for the session's language server (started on
    /// first use in the session's folder).
    Lsp { session_id: String, language: String, message: serde_json::Value },
    /// Opens a path of the session's folder in Xcode, Android Studio, Zed,
    /// VS Code or Finder.
    OpenExternal { session_id: String, path: String, app: String },
    /// Learn: a session reads these card comments and the named catalog
    /// skills and proposes edits (see LearningItem).
    Learn { plan_id: String, account_id: String, notes: Vec<String>, skills: Vec<String> },
    DecideLearning { plan_id: String, id: String, accept: bool },
    /// From a session's PreToolUse hook: may this tool call run? Deploys
    /// and the like wait for your decision (see gates).
    Gate { session_id: String, tool: String, input: serde_json::Value },
    /// Your decision on an action waiting for OK (app only).
    ResolveApproval { id: String, approve: bool },
    /// From the app, as you: in a project session's worktree.
    GitCommit { session_id: String, message: String },
    GitPush { session_id: String },
    /// Squash-merges the branch's PR (gh, as the session's account).
    MergePr { session_id: String },
    /// Folders of the Mac, for picking a repository (default: home).
    BrowseFolders { path: Option<String>, #[serde(default)] hidden: bool },
    /// Takes an account out of the harness: its sessions end; its folder
    /// (and conversations) stay. The last account cannot go.
    RemoveAccount { id: String },
    /// Opens a session on the account and runs Claude Code's /logout.
    LogoutAccount { id: String },
    ListDevices,
    /// Unpairs a device and drops its connection.
    RevokeDevice { id: String },
    ListMemory { workspace_id: String },
    ForgetMemory { workspace_id: String, id: String },
    /// Puts a failed or stopped card back in line.
    RetryCard { plan_id: String, number: u32 },
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
    Plans { plans: Vec<PlanDoc> },
    Workspaces { workspaces: Vec<WorkspaceInfo> },
    Memory { workspace_id: String, entries: Vec<MemoryEntry> },
    Devices { devices: Vec<DeviceInfo> },
    /// A folder's subfolders; `repo` marks git repositories.
    Folders { path: String, parent: Option<String>, folders: Vec<FolderEntry> },
    /// Result of a commit, push or merge.
    GitResult { session_id: String, action: String, ok: bool, output: String },
    /// Reply to `Gate`.
    GateDecision { allow: bool, reason: String },
    /// A session wants to do something that needs your OK.
    Approval { id: String, session_id: String, action: String },
    ApprovalResolved { id: String, approved: bool },
    Learnings { plan_id: String, items: Vec<LearningItem> },
    BrowserState { profile: String, open: bool, url: String },
    /// Which session's agent is driving a workspace browser (None: no one).
    BrowserUse { profile: String, session_id: Option<String> },
    DirEntries { session_id: String, path: String, entries: Vec<DirEntry> },
    FileContent { session_id: String, path: String, text: String },
    FileSaved { session_id: String, path: String },
    /// What a language server sent (responses, diagnostics, requests).
    Lsp { session_id: String, language: String, message: serde_json::Value },
    /// A screen of a workspace browser: JPEG in base64, page size in CSS
    /// pixels.
    BrowserFrame { profile: String, jpeg: String, width: u32, height: u32 },
    /// Where each loop of a running plan is.
    PlanRun { plan_id: String, cards: Vec<CardRun> },
    /// Reply to an `McpCall`: text for the agent.
    McpResult { text: String, is_error: bool },
    /// A message between sessions (`send_message`), for the app to show.
    SessionMessage { from: String, to: String, body: String },
    /// An agent asks to store an env value; nothing happens until you
    /// approve it. The value is never sent to clients.
    EnvRequest { id: String, session_id: String, name: String },
    EnvRequestResolved { id: String, approved: bool },
    /// An agent asks to add an MCP server (config in Claude Code's
    /// `mcpServers` format, secrets only as `${ENV}` references).
    McpRequest {
        id: String,
        session_id: String,
        name: String,
        mcp: serde_json::Value,
        #[serde(default)]
        reason: String,
    },
    McpRequestResolved { id: String, approved: bool },
    McpImports { items: Vec<McpImport> },
    Connectors { account_id: String, items: Vec<Connector> },
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
