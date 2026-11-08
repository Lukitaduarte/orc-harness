//! What you already set up on this Mac, offered for the catalog: MCP
//! servers from Claude Code (every `~/.claude*` setup, user and project
//! level), from other tools (Claude Desktop, Cursor, Windsurf, VS Code,
//! Cline, Roo, Gemini CLI, Amazon Q, LM Studio, opencode, Zed, Codex) and
//! from projects' own files, plus skills (Claude Code setups, plugins,
//! projects, `~/.agents`, `~/.codex`). Every MCP config becomes Claude
//! Code's `mcpServers` shape. Secret values written in them move to the
//! Keychain on import, and the config keeps `${NAME}` references; values
//! never reach a client.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

use crate::secrets::valid_env_name;

/// An MCP server found in a config file.
#[derive(Debug, Clone, PartialEq)]
pub struct Found {
    /// Unique across a scan: where it came from plus its name.
    pub key: String,
    /// Where it was found, for people.
    pub label: String,
    pub name: String,
    /// In Claude Code's `mcpServers` shape.
    pub config: Value,
}

/// A skill folder (with a SKILL.md).
#[derive(Debug, Clone, PartialEq)]
pub struct FoundSkill {
    pub key: String,
    pub label: String,
    pub name: String,
    pub description: String,
    pub path: PathBuf,
}

#[derive(Debug, Default)]
pub struct Scan {
    pub mcps: Vec<Found>,
    pub skills: Vec<FoundSkill>,
}

/// JSON, or JSON with comments and trailing commas (VS Code, Zed).
pub fn jsonc(raw: &str) -> Option<Value> {
    if let Ok(v) = serde_json::from_str(raw) {
        return Some(v);
    }
    let (mut out, mut chars) = (String::with_capacity(raw.len()), raw.chars().peekable());
    let mut in_str = false;
    while let Some(c) = chars.next() {
        if in_str {
            out.push(c);
            if c == '\\' {
                if let Some(n) = chars.next() {
                    out.push(n);
                }
            } else if c == '"' {
                in_str = false;
            }
            continue;
        }
        match (c, chars.peek()) {
            ('"', _) => {
                in_str = true;
                out.push(c);
            }
            ('/', Some('/')) => {
                for n in chars.by_ref() {
                    if n == '\n' {
                        out.push('\n');
                        break;
                    }
                }
            }
            ('/', Some('*')) => {
                chars.next();
                let mut prev = ' ';
                for n in chars.by_ref() {
                    if prev == '*' && n == '/' {
                        break;
                    }
                    prev = n;
                }
            }
            _ => out.push(c),
        }
    }
    // Trailing commas before } or ].
    let mut clean = String::with_capacity(out.len());
    let bytes: Vec<char> = out.chars().collect();
    let mut in_str = false;
    for (i, &c) in bytes.iter().enumerate() {
        if c == '"' && (i == 0 || bytes[i - 1] != '\\') {
            in_str = !in_str;
        }
        if !in_str && c == ',' && bytes[i + 1..].iter().find(|x| !x.is_whitespace()).is_some_and(|x| *x == '}' || *x == ']') {
            continue;
        }
        clean.push(c);
    }
    serde_json::from_str(&clean).ok()
}

/// Any tool's server entry in Claude Code's `mcpServers` shape, or None
/// when it has neither a command nor a URL.
pub fn normalize(entry: &Value) -> Option<Value> {
    let o = entry.as_object()?;
    let mut out = Map::new();
    // opencode: {"type": "local", "command": [...], "environment": {}}.
    if let Some(cmd) = o.get("command").and_then(Value::as_array) {
        let mut parts = cmd.iter().filter_map(Value::as_str);
        out.insert("command".into(), json!(parts.next()?));
        out.insert("args".into(), json!(parts.collect::<Vec<_>>()));
    // Zed: {"command": {"path", "args", "env"}}.
    } else if let Some(cmd) = o.get("command").and_then(Value::as_object) {
        out.insert("command".into(), cmd.get("path")?.clone());
        if let Some(a) = cmd.get("args") {
            out.insert("args".into(), a.clone());
        }
        if let Some(e) = cmd.get("env") {
            out.insert("env".into(), e.clone());
        }
    } else if let Some(cmd) = o.get("command").and_then(Value::as_str) {
        out.insert("command".into(), json!(cmd));
    }
    let url = ["url", "httpUrl", "serverUrl", "serverURL"].iter().find_map(|k| o.get(*k).and_then(Value::as_str));
    if let Some(url) = url {
        let kind = match o.get("type").and_then(Value::as_str) {
            Some("sse") => "sse",
            _ if url.trim_end_matches('/').ends_with("/sse") => "sse",
            _ => "http",
        };
        out.insert("type".into(), json!(kind));
        out.insert("url".into(), json!(url));
    }
    if !out.contains_key("command") && !out.contains_key("url") {
        return None;
    }
    if out.contains_key("command")
        && !out.contains_key("args")
        && let Some(a) = o.get("args").filter(|a| a.is_array())
    {
        out.insert("args".into(), a.clone());
    }
    for (from, to) in [("env", "env"), ("environment", "env"), ("headers", "headers")] {
        if !out.contains_key(to)
            && let Some(v) = o.get(from).filter(|v| v.as_object().is_some_and(|m| !m.is_empty()))
        {
            out.insert(to.into(), v.clone());
        }
    }
    Some(Value::Object(out))
}

fn read_json(path: &Path) -> Option<Value> {
    jsonc(&std::fs::read_to_string(path).ok()?)
}

fn short(home: &Path, p: &Path) -> String {
    match p.strip_prefix(home) {
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => p.display().to_string(),
    }
}

/// Where Claude Code setups live: `~/.claude` (its `.claude.json` sits in
/// the home folder) and every `~/.claude*` folder (CLAUDE_CONFIG_DIR, like
/// aliases), plus the given account folders. (folder, its .claude.json).
pub fn claude_setups(home: &Path, accounts: &[PathBuf]) -> Vec<(PathBuf, PathBuf)> {
    let mut out = vec![(home.join(".claude"), home.join(".claude.json"))];
    let mut dirs: Vec<PathBuf> = std::fs::read_dir(home)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with(".claude") && e.file_name() != ".claude" && e.path().is_dir())
        .map(|e| e.path())
        .collect();
    dirs.sort();
    dirs.extend(accounts.iter().cloned());
    let mut seen: BTreeSet<PathBuf> = out.iter().map(|(d, _)| d.clone()).collect();
    for d in dirs {
        let canon = d.canonicalize().unwrap_or(d.clone());
        if seen.insert(canon) {
            out.push((d.clone(), d.join(".claude.json")));
        }
    }
    out
}

/// Servers under `key` in a JSON file, normalized.
fn servers_in(doc: &Value, key: &str) -> Vec<(String, Value)> {
    doc.get(key)
        .and_then(Value::as_object)
        .map(|m| m.iter().filter_map(|(n, v)| Some((n.clone(), normalize(v)?))).collect())
        .unwrap_or_default()
}

/// Codex keeps its servers in TOML: `[mcp_servers.<name>]`.
fn codex_servers(path: &Path) -> Vec<(String, Value)> {
    let Ok(raw) = std::fs::read_to_string(path) else { return Vec::new() };
    let Ok(doc) = raw.parse::<toml::Table>() else { return Vec::new() };
    let Ok(v) = serde_json::to_value(doc) else { return Vec::new() };
    servers_in(&v, "mcp_servers")
}

/// The skill folders under `dir` (`<dir>/<skill>/SKILL.md`, or one level
/// deeper for grouped folders), following links.
fn skills_under(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let p = e.path();
        if p.join("SKILL.md").is_file() {
            out.push(p);
        } else if p.is_dir() {
            out.extend(
                std::fs::read_dir(&p).into_iter().flatten().flatten().map(|e| e.path()).filter(|p| p.join("SKILL.md").is_file()),
            );
        }
    }
    out.sort();
    out
}

/// Every `skills` folder inside a Claude Code plugins tree.
fn plugin_skill_dirs(root: &Path, depth: usize, out: &mut Vec<PathBuf>) {
    if depth == 0 {
        return;
    }
    for e in std::fs::read_dir(root).into_iter().flatten().flatten() {
        let p = e.path();
        if !p.is_dir() || e.file_type().is_ok_and(|t| t.is_symlink()) {
            continue;
        }
        if e.file_name() == "skills" {
            out.push(p);
        } else if e.file_name() != "node_modules" && !e.file_name().to_string_lossy().starts_with('.') {
            plugin_skill_dirs(&p, depth - 1, out);
        }
    }
}

/// Name and description from a SKILL.md's frontmatter.
pub fn skill_meta(dir: &Path) -> (String, String) {
    let folder = dir.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
    let raw = std::fs::read_to_string(dir.join("SKILL.md")).unwrap_or_default();
    let front = raw.strip_prefix("---").and_then(|r| r.split_once("\n---")).map(|(f, _)| f).unwrap_or_default();
    let field = |k: &str| {
        front.lines().find_map(|l| l.strip_prefix(k).and_then(|r| r.strip_prefix(':'))).map(|v| v.trim().trim_matches('"').to_string())
    };
    let name = field("name").filter(|n| !n.is_empty()).unwrap_or(folder);
    let mut description = field("description").unwrap_or_default();
    if description.chars().count() > 160 {
        description = description.chars().take(157).collect::<String>() + "…";
    }
    (name, description)
}

/// Everything on this Mac. `accounts` are the harness's account folders;
/// `projects` the repositories it knows (name, folder).
pub fn scan_all(home: &Path, accounts: &[PathBuf], projects: &[(String, PathBuf)]) -> Scan {
    let mut scan = Scan::default();
    let mut project_dirs: Vec<(String, PathBuf)> = projects.to_vec();
    let add = |scan: &mut Scan, file: &Path, label: String, servers: Vec<(String, Value)>| {
        for (name, config) in servers {
            scan.mcps.push(Found { key: format!("{}#{label}#{name}", file.display()), label: label.clone(), name, config });
        }
    };

    // Claude Code setups: user servers, per-project servers, and the
    // projects they know.
    let setups = claude_setups(home, accounts);
    for (dir, json) in &setups {
        let setup = short(home, dir);
        let Some(doc) = read_json(json) else { continue };
        add(&mut scan, json, format!("Claude Code {setup}"), servers_in(&doc, "mcpServers"));
        for (path, p) in doc.get("projects").and_then(Value::as_object).into_iter().flatten() {
            let folder = Path::new(path).file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or(path.clone());
            add(&mut scan, json, format!("{folder} · Claude Code {setup}"), servers_in(p, "mcpServers"));
            if Path::new(path).is_dir() {
                project_dirs.push((folder, PathBuf::from(path)));
            }
        }
    }

    // Other tools, user level.
    let support = home.join("Library/Application Support");
    let code = |app: &str| support.join(app).join("User");
    let tools: Vec<(&str, PathBuf, &str)> = vec![
        ("Claude Desktop", support.join("Claude/claude_desktop_config.json"), "mcpServers"),
        ("Cursor", home.join(".cursor/mcp.json"), "mcpServers"),
        ("Windsurf", home.join(".codeium/windsurf/mcp_config.json"), "mcpServers"),
        ("VS Code", code("Code").join("mcp.json"), "servers"),
        ("VS Code Insiders", code("Code - Insiders").join("mcp.json"), "servers"),
        ("Cline", code("Code").join("globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"), "mcpServers"),
        ("Roo Code", code("Code").join("globalStorage/rooveterinaryinc.roo-cline/settings/mcp_settings.json"), "mcpServers"),
        ("Gemini CLI", home.join(".gemini/settings.json"), "mcpServers"),
        ("Amazon Q", home.join(".aws/amazonq/mcp.json"), "mcpServers"),
        ("LM Studio", home.join(".lmstudio/mcp.json"), "mcpServers"),
        ("opencode", home.join(".config/opencode/opencode.json"), "mcp"),
        ("Zed", home.join(".config/zed/settings.json"), "context_servers"),
    ];
    for (tool, file, key) in tools {
        if let Some(doc) = read_json(&file) {
            add(&mut scan, &file, tool.to_string(), servers_in(&doc, key));
        }
    }
    let codex = home.join(".codex/config.toml");
    add(&mut scan, &codex, "Codex".into(), codex_servers(&codex));

    // Project level, each folder once.
    let mut seen = BTreeSet::new();
    project_dirs.retain(|(_, d)| seen.insert(d.canonicalize().unwrap_or(d.clone())));
    for (name, dir) in &project_dirs {
        for (file, key, what) in [
            (dir.join(".mcp.json"), "mcpServers", ".mcp.json"),
            (dir.join(".cursor/mcp.json"), "mcpServers", "Cursor"),
            (dir.join(".vscode/mcp.json"), "servers", "VS Code"),
            (dir.join(".gemini/settings.json"), "mcpServers", "Gemini CLI"),
        ] {
            if let Some(doc) = read_json(&file) {
                add(&mut scan, &file, format!("{name} · {what}"), servers_in(&doc, key));
            }
        }
    }

    // The same server found in several places is offered once.
    let mut seen = BTreeSet::new();
    scan.mcps.retain(|f| seen.insert((f.name.clone(), f.config.to_string())));

    // Skills.
    let mut skill_dirs: Vec<(String, PathBuf)> = Vec::new();
    for (dir, _) in &setups {
        let setup = short(home, dir);
        skill_dirs.push((format!("Claude Code {setup}"), dir.join("skills")));
        let mut plugins = Vec::new();
        plugin_skill_dirs(&dir.join("plugins"), 7, &mut plugins);
        for p in plugins {
            // …/<plugin>/<version>/skills or …/<plugin>/skills.
            let plugin = p
                .ancestors()
                .skip(1)
                .filter_map(|a| a.file_name())
                .map(|f| f.to_string_lossy().into_owned())
                .find(|n| !n.chars().next().is_some_and(|c| c.is_ascii_digit()))
                .unwrap_or_default();
            skill_dirs.push((format!("plugin {plugin} · {setup}"), p));
        }
    }
    skill_dirs.push(("~/.agents".into(), home.join(".agents/skills")));
    skill_dirs.push(("Codex".into(), home.join(".codex/skills")));
    for (name, dir) in &project_dirs {
        skill_dirs.push((name.clone(), dir.join(".claude/skills")));
    }
    // A folder once, and the same skill (a plugin installed in several
    // setups) once.
    let (mut seen, mut same) = (BTreeSet::new(), BTreeSet::new());
    for (label, dir) in skill_dirs {
        for path in skills_under(&dir) {
            let real = path.canonicalize().unwrap_or(path.clone());
            if !seen.insert(real.clone()) {
                continue;
            }
            let body = std::fs::read(real.join("SKILL.md")).unwrap_or_default();
            if !same.insert((real.file_name().map(|f| f.to_os_string()), body)) {
                continue;
            }
            let (name, description) = skill_meta(&real);
            scan.skills.push(FoundSkill { key: format!("skill#{}", real.display()), label: label.clone(), name, description, path: real });
        }
    }
    scan
}

/// An env name from free text: `my-server` + `Authorization` →
/// `MY_SERVER_AUTHORIZATION`.
fn env_name(parts: &[&str]) -> String {
    let raw: String = parts
        .join("_")
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { '_' })
        .collect();
    if raw.starts_with(|c: char| c.is_ascii_digit()) { format!("_{raw}") } else { raw }
}

/// The config with literal env and header values replaced by `${NAME}`
/// references, and the (NAME, value) pairs that go to the Keychain.
pub fn sanitize(name: &str, config: &Value) -> (Value, Vec<(String, String)>) {
    let mut config = config.clone();
    let mut secrets = Vec::new();
    for key in ["env", "headers"] {
        let Some(map) = config.get_mut(key).and_then(Value::as_object_mut) else { continue };
        for (k, v) in map.iter_mut() {
            let Some(text) = v.as_str() else { continue };
            if text.contains("${") {
                continue;
            }
            let env = if key == "env" && valid_env_name(k) { k.clone() } else { env_name(&[name, k]) };
            secrets.push((env.clone(), text.to_string()));
            *v = Value::String(format!("${{{env}}}"));
        }
    }
    (config, secrets)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(p: &Path, s: &str) {
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, s).unwrap();
    }

    fn skill(dir: &Path, front: &str) {
        write(&dir.join("SKILL.md"), &format!("---\n{front}\n---\n# body\n"));
    }

    #[test]
    fn finds_every_setup_tool_project_and_skill() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        let repo = home.join("code/app");
        // Default Claude Code: user server and a project with its own.
        write(
            &home.join(".claude.json"),
            &json!({
                "mcpServers": { "railway": { "command": "npx", "args": ["railway-mcp"] } },
                "projects": { repo.display().to_string(): { "mcpServers": { "db": { "type": "http", "url": "https://db/mcp" } } } }
            })
            .to_string(),
        );
        // An alias setup (CLAUDE_CONFIG_DIR=~/.claude-personal).
        write(&home.join(".claude-personal/.claude.json"), &json!({ "mcpServers": { "notes": { "command": "notes-mcp" } } }).to_string());
        skill(&home.join(".claude-personal/skills/voz"), "name: voz-lukita\ndescription: Escreve na minha voz");
        skill(&home.join(".claude/skills/synced/railway"), "name: use-railway");
        skill(&home.join(".claude/plugins/cache/mk/dart-flutter/1.0.0/skills/add-test"), "name: dart-add-test");
        // Other tools.
        write(&home.join(".cursor/mcp.json"), &json!({ "mcpServers": { "linear": { "url": "https://mcp.linear.app/sse" } } }).to_string());
        write(
            &home.join("Library/Application Support/Code/User/mcp.json"),
            "{\n  // comments are fine\n  \"servers\": { \"gh\": { \"type\": \"stdio\", \"command\": \"gh-mcp\", }, },\n}",
        );
        write(&home.join(".config/opencode/opencode.json"), &json!({ "mcp": { "oc": { "type": "local", "command": ["bunx", "oc-mcp"], "environment": { "K": "v" } } } }).to_string());
        write(&home.join(".codex/config.toml"), "[mcp_servers.cx]\ncommand = \"cx-mcp\"\nargs = [\"--stdio\"]\n");
        // The project's own files and skills.
        write(&repo.join(".mcp.json"), &json!({ "mcpServers": { "lint": { "command": "lint-mcp" } } }).to_string());
        skill(&repo.join(".claude/skills/deploy"), "name: deploy\ndescription: \"Ships it\"");

        let scan = scan_all(home, &[], &[]);
        let mcps: Vec<(&str, &str)> = scan.mcps.iter().map(|f| (f.name.as_str(), f.label.as_str())).collect();
        for want in [
            ("railway", "Claude Code ~/.claude"),
            ("db", "app · Claude Code ~/.claude"),
            ("notes", "Claude Code ~/.claude-personal"),
            ("linear", "Cursor"),
            ("gh", "VS Code"),
            ("oc", "opencode"),
            ("cx", "Codex"),
            ("lint", "app · .mcp.json"),
        ] {
            assert!(mcps.contains(&want), "{want:?} not in {mcps:?}");
        }
        let get = |n: &str| &scan.mcps.iter().find(|f| f.name == n).unwrap().config;
        assert_eq!(get("linear"), &json!({ "type": "sse", "url": "https://mcp.linear.app/sse" }));
        assert_eq!(get("oc"), &json!({ "command": "bunx", "args": ["oc-mcp"], "env": { "K": "v" } }));
        assert_eq!(get("cx"), &json!({ "command": "cx-mcp", "args": ["--stdio"] }));

        let skills: Vec<(&str, &str)> = scan.skills.iter().map(|s| (s.name.as_str(), s.label.as_str())).collect();
        for want in [
            ("voz-lukita", "Claude Code ~/.claude-personal"),
            ("use-railway", "Claude Code ~/.claude"),
            ("dart-add-test", "plugin dart-flutter · ~/.claude"),
            ("deploy", "app"),
        ] {
            assert!(skills.contains(&want), "{want:?} not in {skills:?}");
        }
        assert_eq!(scan.skills.iter().find(|s| s.name == "deploy").unwrap().description, "Ships it");
    }

    #[test]
    fn a_plugin_in_two_setups_offers_its_skills_once() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        for setup in [".claude", ".claude-remote"] {
            skill(&home.join(setup).join("plugins/cache/mk/dart/1.0.0/skills/add-test"), "name: dart-add-test");
        }
        std::fs::create_dir_all(home.join(".claude-remote")).unwrap();
        assert_eq!(scan_all(home, &[], &[]).skills.len(), 1);
    }

    #[test]
    fn the_same_server_in_two_places_is_offered_once() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        let s = json!({ "mcpServers": { "x": { "command": "x-mcp" } } }).to_string();
        write(&home.join(".claude.json"), &s);
        write(&home.join(".cursor/mcp.json"), &s);
        assert_eq!(scan_all(home, &[], &[]).mcps.len(), 1);
    }

    #[test]
    fn secrets_move_out_of_the_config() {
        let config = json!({ "command": "npx", "env": { "API_KEY": "sk-1", "MODE": "${MODE}" } });
        let (clean, secrets) = sanitize("x", &config);
        assert_eq!(clean["env"]["API_KEY"], "${API_KEY}");
        assert_eq!(clean["env"]["MODE"], "${MODE}");
        assert_eq!(secrets, [("API_KEY".to_string(), "sk-1".to_string())]);
        let http = json!({ "type": "http", "url": "https://u", "headers": { "Authorization": "Bearer t" } });
        let (clean, secrets) = sanitize("my-db", &http);
        assert_eq!(clean["headers"]["Authorization"], "${MY_DB_AUTHORIZATION}");
        assert_eq!(secrets, [("MY_DB_AUTHORIZATION".to_string(), "Bearer t".to_string())]);
    }

    #[test]
    fn jsonc_with_comments_and_trailing_commas() {
        assert_eq!(jsonc("{ // c\n \"a\": [1, 2,], /* x */ \"b\": \"//no\", }"), Some(json!({ "a": [1, 2], "b": "//no" })));
    }
}
