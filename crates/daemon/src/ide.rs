//! The IDE's daemon side: files of a session's folder (never outside it)
//! and language servers (LSP over stdio) proxied to the app as JSON.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::path::{Component, Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};

use orc_protocol::DirEntry;
use serde_json::Value;

/// Files bigger than this are not opened in the editor.
pub const MAX_FILE: u64 = 2 * 1024 * 1024;

/// `rel` inside `root`, refusing anything that leaves it (`..`, absolute
/// paths, symlinks pointing out).
pub fn resolve(root: &Path, rel: &str) -> std::io::Result<PathBuf> {
    let rel = Path::new(rel);
    if rel.components().any(|c| !matches!(c, Component::Normal(_) | Component::CurDir)) {
        return Err(std::io::Error::other("caminho fora da pasta da sessão"));
    }
    let root = root.canonicalize()?;
    let path = root.join(rel);
    // An existing path must stay inside once links are followed; a new
    // file's folder must.
    let real = match path.canonicalize() {
        Ok(p) => p,
        Err(_) => {
            let parent = path.parent().ok_or_else(|| std::io::Error::other("caminho inválido"))?.canonicalize()?;
            parent.join(path.file_name().ok_or_else(|| std::io::Error::other("caminho inválido"))?)
        }
    };
    if !real.starts_with(&root) {
        return Err(std::io::Error::other("caminho fora da pasta da sessão"));
    }
    Ok(real)
}

/// One folder level, folders first, without `.git` and what `.gitignore`
/// hides (build outputs).
pub fn list_dir(root: &Path, rel: &str) -> std::io::Result<Vec<DirEntry>> {
    let dir = resolve(root, rel)?;
    let mut entries: Vec<DirEntry> = ignore::WalkBuilder::new(&dir)
        .max_depth(Some(1))
        .hidden(false)
        .filter_entry(|e| e.file_name() != ".git")
        .build()
        .flatten()
        .filter(|e| e.depth() == 1)
        .map(|e| DirEntry {
            name: e.file_name().to_string_lossy().into_owned(),
            dir: e.file_type().is_some_and(|t| t.is_dir()),
        })
        .collect();
    entries.sort_by(|a, b| b.dir.cmp(&a.dir).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    Ok(entries)
}

pub fn read_file(root: &Path, rel: &str) -> std::io::Result<String> {
    let path = resolve(root, rel)?;
    if std::fs::metadata(&path)?.len() > MAX_FILE {
        return Err(std::io::Error::other("arquivo grande demais para o editor (2 MB)"));
    }
    String::from_utf8(std::fs::read(&path)?).map_err(|_| std::io::Error::other("arquivo binário"))
}

pub fn write_file(root: &Path, rel: &str, text: &str) -> std::io::Result<()> {
    let path = resolve(root, rel)?;
    if path.is_dir() {
        return Err(std::io::Error::other("é uma pasta"));
    }
    std::fs::write(path, text)
}

/// The language server for `language`, as installed on this machine.
pub fn server_command(language: &str) -> Option<(&'static str, &'static [&'static str])> {
    Some(match language {
        "dart" => ("dart", &["language-server", "--protocol=lsp"]),
        "typescript" => ("typescript-language-server", &["--stdio"]),
        "kotlin" => ("kotlin-lsp", &["--stdio"]),
        "swift" => ("xcrun", &["sourcekit-lsp"]),
        _ => return None,
    })
}

/// Apps a file or folder can be opened in (macOS `open -a`).
pub fn external_app(app: &str) -> Option<&'static str> {
    Some(match app {
        "xcode" => "Xcode",
        "android-studio" => "Android Studio",
        "zed" => "Zed",
        "vscode" => "Visual Studio Code",
        "finder" => "Finder",
        _ => return None,
    })
}

struct Server {
    child: Child,
    stdin: ChildStdin,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Running language servers by (session, language).
#[derive(Default, Clone)]
pub struct LanguageServers {
    servers: Arc<Mutex<HashMap<(String, String), Server>>>,
}

impl LanguageServers {
    /// Sends `message` to the session's server for `language`, starting it
    /// in `root` if needed. Whatever the server says goes to `on_message`.
    pub fn send(
        &self,
        session_id: &str,
        language: &str,
        root: &Path,
        message: &Value,
        on_message: impl Fn(Value) + Send + 'static,
    ) -> std::io::Result<()> {
        let key = (session_id.to_string(), language.to_string());
        let mut servers = self.servers.lock().unwrap();
        if servers.get_mut(&key).is_some_and(|s| !matches!(s.child.try_wait(), Ok(None))) {
            servers.remove(&key);
        }
        if !servers.contains_key(&key) {
            let (program, args) =
                server_command(language).ok_or_else(|| std::io::Error::other(format!("sem servidor de linguagem para {language}")))?;
            let mut child = Command::new(program)
                .args(args)
                .current_dir(root)
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|e| std::io::Error::other(format!("{program} não abriu: {e}")))?;
            let stdin = child.stdin.take().expect("piped");
            let stdout = child.stdout.take().expect("piped");
            std::thread::spawn(move || {
                let mut r = BufReader::new(stdout);
                while let Some(msg) = read_frame(&mut r) {
                    on_message(msg);
                }
            });
            servers.insert(key.clone(), Server { child, stdin });
        }
        let server = servers.get_mut(&key).expect("inserted");
        let body = serde_json::to_vec(message)?;
        write!(server.stdin, "Content-Length: {}\r\n\r\n", body.len())?;
        server.stdin.write_all(&body)?;
        server.stdin.flush()
    }

    /// Stops a session's servers (session ended).
    pub fn stop(&self, session_id: &str) {
        self.servers.lock().unwrap().retain(|(s, _), _| s != session_id);
    }
}

/// One LSP message (`Content-Length` framed JSON).
fn read_frame(r: &mut impl BufRead) -> Option<Value> {
    let mut len = None;
    loop {
        let mut line = String::new();
        if r.read_line(&mut line).ok()? == 0 {
            return None;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some(v) = line.strip_prefix("Content-Length:") {
            len = v.trim().parse::<usize>().ok();
        }
    }
    let mut body = vec![0; len?];
    r.read_exact(&mut body).ok()?;
    serde_json::from_slice(&body).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn files_stay_inside_the_session_folder() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("repo");
        std::fs::create_dir_all(root.join("lib")).unwrap();
        std::fs::create_dir_all(root.join(".git")).unwrap();
        std::fs::create_dir_all(root.join("build")).unwrap();
        std::fs::write(root.join(".gitignore"), "build/\n").unwrap();
        std::fs::write(root.join("lib/main.dart"), "void main() {}\n").unwrap();
        std::fs::write(dir.path().join("secret.txt"), "x").unwrap();
        std::os::unix::fs::symlink(dir.path().join("secret.txt"), root.join("link")).unwrap();

        let names: Vec<_> = list_dir(&root, "").unwrap().into_iter().map(|e| (e.name, e.dir)).collect();
        assert_eq!(names[0], ("lib".into(), true));
        assert!(!names.iter().any(|(n, _)| n == ".git" || n == "build"), "{names:?}");
        assert_eq!(read_file(&root, "lib/main.dart").unwrap(), "void main() {}\n");
        write_file(&root, "lib/new.dart", "// novo\n").unwrap();
        assert_eq!(read_file(&root, "./lib/new.dart").unwrap(), "// novo\n");

        for bad in ["../secret.txt", "/etc/passwd", "link", "lib/../../secret.txt"] {
            assert!(read_file(&root, bad).is_err(), "{bad}");
            assert!(write_file(&root, bad, "x").is_err(), "{bad}");
        }
        std::fs::write(root.join("bin"), [0xff, 0xfe, 0]).unwrap();
        assert!(read_file(&root, "bin").is_err());
    }

    #[test]
    fn frames_are_read_by_length() {
        let raw = b"Content-Length: 16\r\nContent-Type: x\r\n\r\n{\"id\":1,\"a\":\"b\"}Content-Length: 2\r\n\r\n{}";
        let mut r = BufReader::new(&raw[..]);
        assert_eq!(read_frame(&mut r).unwrap()["a"], "b");
        assert_eq!(read_frame(&mut r).unwrap(), serde_json::json!({}));
        assert!(read_frame(&mut r).is_none());
    }
}
