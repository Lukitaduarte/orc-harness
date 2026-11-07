//! `orcd install`: orcd as a macOS LaunchAgent that starts at login and
//! comes back if it dies. The binaries are copied to `<home>/bin` (a path
//! that survives rebuilds) and optionally signed, so the Keychain and the
//! firewall remember them across updates.

use std::path::{Path, PathBuf};
use std::process::Command;

pub const LABEL: &str = "me.lukita.orcd";

/// orcd and the helpers it starts sessions with.
pub const BINARIES: [&str; 5] = ["orcd", "orc-statusline", "orc-hook", "orc-commit-check", "orc-mcp"];

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// The LaunchAgent. `PATH` is the installing shell's, so sessions find
/// `claude`, `gh`, `dart` and `npx` (launchd's own PATH is minimal).
pub fn plist(orcd: &Path, home: &Path, path_env: &str, orc_home: Option<&Path>) -> String {
    let log = xml_escape(&home.join("orcd.log").display().to_string());
    let mut env = format!("    <key>PATH</key><string>{}</string>\n", xml_escape(path_env));
    if let Some(h) = orc_home {
        env.push_str(&format!("    <key>ORC_HOME</key><string>{}</string>\n", xml_escape(&h.display().to_string())));
    }
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>{}</string><string>serve</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>{log}</string>
  <key>StandardErrorPath</key><string>{log}</string>
  <key>EnvironmentVariables</key>
  <dict>
{env}  </dict>
</dict>
</plist>
"#,
        xml_escape(&orcd.display().to_string()),
    )
}

pub fn plist_path() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default()).join("Library/LaunchAgents").join(format!("{LABEL}.plist"))
}

fn uid() -> std::io::Result<String> {
    let out = Command::new("id").arg("-u").output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn run(cmd: &mut Command) -> std::io::Result<()> {
    let out = cmd.output()?;
    if out.status.success() {
        Ok(())
    } else {
        Err(std::io::Error::other(format!("{:?}: {}", cmd, String::from_utf8_lossy(&out.stderr).trim())))
    }
}

/// Copies the binaries next to the running orcd into `<home>/bin`, signs
/// them with `sign` (a codesigning identity) if given, writes the
/// LaunchAgent and (re)loads it.
pub fn install(home: &Path, sign: Option<&str>) -> std::io::Result<PathBuf> {
    // Through a symlink (Homebrew's `orcd` in PATH) the helpers sit next to
    // the real file.
    let exe = std::env::current_exe()?;
    let from = exe.canonicalize().unwrap_or(exe).parent().map(PathBuf::from).unwrap_or_default();
    let bin = home.join("bin");
    std::fs::create_dir_all(&bin)?;
    // Unload first: the running orcd holds the old binary.
    let _ = uninstall_agent();
    for name in BINARIES {
        let src = from.join(name);
        if !src.exists() {
            return Err(std::io::Error::other(format!("{} não encontrado ao lado do orcd", src.display())));
        }
        let dst = bin.join(name);
        // A new file (not overwritten in place) keeps the old signature's
        // cached pages away from the new code.
        let _ = std::fs::remove_file(&dst);
        std::fs::copy(&src, &dst)?;
        std::fs::set_permissions(&dst, std::os::unix::fs::PermissionsExt::from_mode(0o755))?;
        if let Some(identity) = sign {
            run(Command::new("codesign").args(["--force", "--sign", identity, "--identifier", &format!("{LABEL}.{name}")]).arg(&dst))?;
        }
    }
    let orc_home = std::env::var_os("ORC_HOME").map(PathBuf::from);
    let path_env = merge_paths(&[login_path().as_deref(), std::env::var("PATH").ok().as_deref(), Some(FALLBACK_PATH)]);
    let plist_file = plist_path();
    std::fs::create_dir_all(plist_file.parent().expect("LaunchAgents"))?;
    std::fs::write(&plist_file, plist(&bin.join("orcd"), home, &path_env, orc_home.as_deref()))?;
    run(Command::new("launchctl").args(["bootstrap", &format!("gui/{}", uid()?)]).arg(&plist_file))?;
    Ok(plist_file)
}

const FALLBACK_PATH: &str = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

/// The PATH a terminal would have: an app opened from Finder (which runs
/// `install` on first launch) only gets launchd's minimal one, without
/// `claude`, `gh` or `npx`. Gives up after a few seconds on a shell config
/// that waits for input.
fn login_path() -> Option<String> {
    use std::process::Stdio;
    let shell = std::env::var("SHELL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| "/bin/zsh".into());
    let mut child = Command::new(shell)
        .args(["-ilc", "printf '\\n__ORC_PATH__%s\\n' \"$PATH\""])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let started = std::time::Instant::now();
    while child.try_wait().ok()?.is_none() {
        if started.elapsed() > std::time::Duration::from_secs(5) {
            let _ = child.kill();
            let _ = child.wait();
            return None;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    let out = child.wait_with_output().ok()?;
    String::from_utf8_lossy(&out.stdout).lines().find_map(|l| l.strip_prefix("__ORC_PATH__")).map(str::to_string).filter(|p| !p.is_empty())
}

/// Joins PATH lists in order, without repeats.
fn merge_paths(parts: &[Option<&str>]) -> String {
    let mut seen = Vec::<&str>::new();
    for dir in parts.iter().flatten().flat_map(|p| p.split(':')) {
        if !dir.is_empty() && !seen.contains(&dir) {
            seen.push(dir);
        }
    }
    seen.join(":")
}

fn uninstall_agent() -> std::io::Result<()> {
    run(Command::new("launchctl").args(["bootout", &format!("gui/{}/{LABEL}", uid()?)]))
}

/// Stops the service and removes the LaunchAgent (binaries and data stay).
pub fn uninstall() -> std::io::Result<()> {
    let _ = uninstall_agent();
    match std::fs::remove_file(plist_path()) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
        _ => Ok(()),
    }
}

/// Whether the service is loaded, and its pid when running.
pub fn status() -> std::io::Result<Option<String>> {
    let out = Command::new("launchctl").args(["print", &format!("gui/{}/{LABEL}", uid()?)]).output()?;
    if !out.status.success() {
        return Ok(None);
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let state = text.lines().find_map(|l| l.trim().strip_prefix("state = ")).unwrap_or("?");
    let pid = text.lines().find_map(|l| l.trim().strip_prefix("pid = ")).map(|p| format!(", pid {p}")).unwrap_or_default();
    Ok(Some(format!("{state}{pid}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_merge_in_order_without_repeats() {
        assert_eq!(merge_paths(&[Some("/a:/b"), None, Some("/b:/c::/a")]), "/a:/b:/c");
    }

    #[test]
    fn the_login_shell_gives_a_path() {
        // Whatever the shell's config, the system dirs are there.
        let p = login_path().expect("PATH do shell");
        assert!(p.split(':').any(|d| d == "/usr/bin"), "{p}");
    }

    #[test]
    fn the_agent_runs_orcd_serve_with_the_shells_path() {
        let p = plist(Path::new("/Users/x/.orc/bin/orcd"), Path::new("/Users/x/.orc"), "/opt/homebrew/bin:/usr/bin", None);
        assert!(p.contains("<string>/Users/x/.orc/bin/orcd</string><string>serve</string>"));
        assert!(p.contains("<key>PATH</key><string>/opt/homebrew/bin:/usr/bin</string>"));
        assert!(p.contains("<key>KeepAlive</key><true/>"));
        assert!(!p.contains("ORC_HOME"));
        let p = plist(Path::new("/a & b/orcd"), Path::new("/h"), "/x", Some(Path::new("/tmp/orc")));
        assert!(p.contains("/a &amp; b/orcd"));
        assert!(p.contains("<key>ORC_HOME</key><string>/tmp/orc</string>"));
        // A valid property list for launchd.
        let file = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(file.path(), &p).unwrap();
        let lint = Command::new("plutil").arg("-lint").arg(file.path()).output().unwrap();
        assert!(lint.status.success(), "{}", String::from_utf8_lossy(&lint.stdout));
    }
}
