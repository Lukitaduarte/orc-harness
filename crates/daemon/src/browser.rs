//! A browser per workspace: the system's Chrome (or Chromium, Brave, Edge)
//! with its own profile folder (`~/.orc/browsers/<profile>`), so cookies
//! and logins stay with that workspace. Headless; you see it as a stream of
//! frames in a pane and drive it with mouse and keys, and agents drive the
//! same browser through Playwright MCP attached over CDP (127.0.0.1 only).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::tungstenite::Message;

/// What a browser tells the daemon: a new screen frame or a new address.
#[derive(Debug, Clone)]
pub enum BrowserEvent {
    /// JPEG, base64, as CDP sends it; size of the page in CSS pixels.
    Frame { jpeg: String, width: u32, height: u32 },
    Navigated { url: String },
}

type Pending = Arc<Mutex<HashMap<u64, oneshot::Sender<Result<Value, String>>>>>;

/// A CDP connection to one page.
#[derive(Clone)]
struct Cdp {
    out: mpsc::UnboundedSender<String>,
    pending: Pending,
    next: Arc<AtomicU64>,
}

impl Cdp {
    async fn connect(ws_url: &str, on_event: impl Fn(&str, &Value) + Send + 'static) -> std::io::Result<Self> {
        let (ws, _) = tokio_tungstenite::connect_async(ws_url).await.map_err(std::io::Error::other)?;
        let (mut sink, mut stream) = ws.split();
        let (out, mut rx) = mpsc::unbounded_channel::<String>();
        let pending: Pending = Arc::default();
        tokio::spawn(async move {
            while let Some(m) = rx.recv().await {
                if sink.send(Message::text(m)).await.is_err() {
                    break;
                }
            }
        });
        let p = pending.clone();
        let cdp = Self { out, pending, next: Arc::new(AtomicU64::new(1)) };
        let me = cdp.clone();
        tokio::spawn(async move {
            while let Some(Ok(msg)) = stream.next().await {
                let Message::Text(text) = msg else { continue };
                let Ok(v) = serde_json::from_str::<Value>(&text) else { continue };
                if let Some(id) = v["id"].as_u64() {
                    if let Some(tx) = p.lock().unwrap().remove(&id) {
                        let r = match v.get("error") {
                            Some(e) => Err(e["message"].as_str().unwrap_or("erro do CDP").to_string()),
                            None => Ok(v["result"].clone()),
                        };
                        let _ = tx.send(r);
                    }
                } else if let Some(method) = v["method"].as_str() {
                    // Frames must be acked or Chrome stops sending them.
                    if method == "Page.screencastFrame" {
                        me.fire("Page.screencastFrameAck", json!({ "sessionId": v["params"]["sessionId"] }));
                    }
                    on_event(method, &v["params"]);
                }
            }
            // Connection gone: nobody waits forever.
            p.lock().unwrap().clear();
        });
        Ok(cdp)
    }

    fn send(&self, method: &str, params: Value) -> oneshot::Receiver<Result<Value, String>> {
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(id, tx);
        let _ = self.out.send(json!({ "id": id, "method": method, "params": params }).to_string());
        rx
    }

    fn fire(&self, method: &str, params: Value) {
        drop(self.send(method, params));
    }

    async fn call(&self, method: &str, params: Value) -> Result<Value, String> {
        match tokio::time::timeout(Duration::from_secs(15), self.send(method, params)).await {
            Ok(Ok(r)) => r,
            Ok(Err(_)) => Err("o navegador fechou".into()),
            Err(_) => Err(format!("{method}: sem resposta do navegador")),
        }
    }
}

pub struct Browser {
    child: Mutex<Child>,
    /// `http://127.0.0.1:PORT`, for Playwright MCP's `--cdp-endpoint`.
    pub cdp_http: String,
    /// The browser-level CDP endpoint (closing it gracefully).
    browser_ws: String,
    page: Cdp,
    size: Mutex<(u32, u32)>,
}

impl Drop for Browser {
    /// Asks Chrome to quit (it writes cookies and session to the profile),
    /// and kills it only if it does not.
    fn drop(&mut self) {
        let mut c = self.child.lock().unwrap();
        let _ = Command::new("kill").args(["-TERM", &c.id().to_string()]).status();
        for _ in 0..50 {
            if matches!(c.try_wait(), Ok(Some(_))) {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let _ = c.kill();
        let _ = c.wait();
    }
}

impl Browser {
    async fn launch(
        chrome: &Path,
        profile_dir: &Path,
        on_event: impl Fn(BrowserEvent) + Send + Sync + 'static,
    ) -> std::io::Result<Self> {
        std::fs::create_dir_all(profile_dir)?;
        close_orphan(profile_dir).await;
        let port_file = profile_dir.join("DevToolsActivePort");
        let _ = std::fs::remove_file(&port_file);
        let child = Command::new(chrome)
            .arg("--headless=new")
            .arg(format!("--user-data-dir={}", profile_dir.display()))
            .args([
                "--remote-debugging-address=127.0.0.1",
                "--remote-debugging-port=0",
                "--no-first-run",
                "--no-default-browser-check",
                "--window-size=1280,800",
                "about:blank",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        let child = Mutex::new(child);
        // Chrome writes its debugging port here once it listens.
        // Line 1: the port; line 2: the browser target's path.
        let mut port = None;
        for _ in 0..200 {
            let read = std::fs::read_to_string(&port_file).ok().and_then(|s| {
                let mut lines = s.lines();
                let p = lines.next()?.trim().parse::<u16>().ok()?;
                Some((p, lines.next()?.trim().to_string()))
            });
            if let Some(found) = read {
                port = Some(found);
                break;
            }
            if let Ok(Some(status)) = child.lock().unwrap().try_wait() {
                return Err(std::io::Error::other(format!("o navegador saiu ao abrir ({status}); outro processo usa este perfil?")));
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        let (port, browser_path) = port.ok_or_else(|| std::io::Error::other("o navegador não abriu a porta de depuração"))?;
        let targets = http_get_json(port, "/json/list").await?;
        let ws = targets
            .as_array()
            .and_then(|ts| {
                let pages = || ts.iter().filter(|t| t["type"] == "page");
                pages().find(|t| t["url"] == "about:blank").or_else(|| pages().next())
            })
            .and_then(|t| t["webSocketDebuggerUrl"].as_str())
            .ok_or_else(|| std::io::Error::other("nenhuma página no navegador"))?
            .to_string();
        let on_event = Arc::new(on_event);
        let page = Cdp::connect(&ws, move |method, params| match method {
            "Page.screencastFrame" => on_event(BrowserEvent::Frame {
                jpeg: params["data"].as_str().unwrap_or_default().to_string(),
                width: params["metadata"]["deviceWidth"].as_f64().unwrap_or(0.0) as u32,
                height: params["metadata"]["deviceHeight"].as_f64().unwrap_or(0.0) as u32,
            }),
            "Page.frameNavigated" if params["frame"]["parentId"].is_null() => on_event(BrowserEvent::Navigated {
                url: params["frame"]["url"].as_str().unwrap_or_default().to_string(),
            }),
            _ => {}
        })
        .await?;
        let b = Self {
            child,
            cdp_http: format!("http://127.0.0.1:{port}"),
            browser_ws: format!("ws://127.0.0.1:{port}{browser_path}"),
            page,
            size: Mutex::new((1280, 800)),
        };
        b.page.call("Page.enable", json!({})).await.map_err(std::io::Error::other)?;
        b.resize(1280, 800).await.map_err(std::io::Error::other)?;
        Ok(b)
    }

    /// Closes Chrome the way its own quit does, so cookies and the session
    /// reach the profile (a TERM signal does not flush them), and waits
    /// for it to exit. Drop kills it if it is still there.
    pub async fn shutdown(&self) {
        if let Ok(cdp) = Cdp::connect(&self.browser_ws, |_, _| {}).await {
            let _ = cdp.call("Browser.close", json!({})).await;
        }
        for _ in 0..50 {
            if !self.alive() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }

    pub fn alive(&self) -> bool {
        matches!(self.child.lock().unwrap().try_wait(), Ok(None))
    }

    pub async fn navigate(&self, url: &str) -> Result<(), String> {
        let url = if url.contains("://") || url.starts_with("about:") || url.starts_with("data:") {
            url.to_string()
        } else {
            format!("https://{url}")
        };
        let r = self.page.call("Page.navigate", json!({ "url": url })).await?;
        match r["errorText"].as_str() {
            Some(e) if !e.is_empty() => Err(format!("não abriu {url}: {e}")),
            _ => Ok(()),
        }
    }

    pub async fn history(&self, delta: i64) -> Result<(), String> {
        let h = self.page.call("Page.getNavigationHistory", json!({})).await?;
        let i = h["currentIndex"].as_i64().unwrap_or(0) + delta;
        let Some(entry) = h["entries"].as_array().and_then(|e| e.get(i.max(0) as usize)) else { return Ok(()) };
        self.page.call("Page.navigateToHistoryEntry", json!({ "entryId": entry["id"] })).await.map(|_| ())
    }

    pub async fn reload(&self) -> Result<(), String> {
        self.page.call("Page.reload", json!({})).await.map(|_| ())
    }

    /// The page's size in CSS pixels, as the pane shows it; restarts the
    /// frame stream at that size.
    pub async fn resize(&self, width: u32, height: u32) -> Result<(), String> {
        let (w, h) = (width.clamp(200, 3840), height.clamp(200, 2400));
        *self.size.lock().unwrap() = (w, h);
        self.page
            .call("Emulation.setDeviceMetricsOverride", json!({ "width": w, "height": h, "deviceScaleFactor": 1, "mobile": false }))
            .await?;
        let _ = self.page.call("Page.stopScreencast", json!({})).await;
        self.page
            .call("Page.startScreencast", json!({ "format": "jpeg", "quality": 70, "maxWidth": w, "maxHeight": h }))
            .await
            .map(|_| ())
    }

    /// Mouse and keyboard from the pane. Only these CDP input calls, with
    /// these fields, get through.
    pub async fn input(&self, event: &Value) -> Result<(), String> {
        let num = |k: &str| event[k].as_f64().unwrap_or(0.0);
        match event["kind"].as_str() {
            Some("mouse") => {
                let kind = event["type"].as_str().unwrap_or_default();
                if !["mousePressed", "mouseReleased", "mouseMoved", "mouseWheel"].contains(&kind) {
                    return Err(format!("evento de mouse inválido: {kind}"));
                }
                let button = event["button"].as_str().filter(|b| ["none", "left", "middle", "right"].contains(b)).unwrap_or("none");
                self.page
                    .call(
                        "Input.dispatchMouseEvent",
                        json!({ "type": kind, "x": num("x"), "y": num("y"), "button": button,
                                "clickCount": event["clickCount"].as_u64().unwrap_or(0),
                                "deltaX": num("deltaX"), "deltaY": num("deltaY") }),
                    )
                    .await
                    .map(|_| ())
            }
            Some("text") => {
                let text = event["text"].as_str().unwrap_or_default();
                self.page.call("Input.insertText", json!({ "text": text })).await.map(|_| ())
            }
            Some("key") => {
                // Named keys (Enter, Backspace, arrows, Tab, Escape…).
                let key = event["key"].as_str().unwrap_or_default();
                let Some((code, vk, text)) = named_key(key) else { return Err(format!("tecla desconhecida: {key}")) };
                let modifiers = event["modifiers"].as_u64().unwrap_or(0);
                for kind in ["keyDown", "keyUp"] {
                    let mut e = json!({ "type": kind, "key": key, "code": code, "windowsVirtualKeyCode": vk, "modifiers": modifiers });
                    if kind == "keyDown" && !text.is_empty() {
                        e["text"] = json!(text);
                    }
                    self.page.call("Input.dispatchKeyEvent", e).await?;
                }
                Ok(())
            }
            other => Err(format!("entrada desconhecida: {other:?}")),
        }
    }

    pub async fn evaluate(&self, expression: &str) -> Result<Value, String> {
        let r = self.page.call("Runtime.evaluate", json!({ "expression": expression, "returnByValue": true })).await?;
        Ok(r["result"]["value"].clone())
    }
}

/// A Chrome left on this profile by an orcd that died would make a new
/// launch hand off to it and exit. Chrome's `SingletonLock` link names it
/// (`host-pid`); it is asked to quit when its command line has this profile.
async fn close_orphan(profile_dir: &Path) {
    let Ok(target) = std::fs::read_link(profile_dir.join("SingletonLock")) else { return };
    let Some(pid) = target.to_string_lossy().rsplit('-').next().and_then(|p| p.parse::<u32>().ok()) else { return };
    let Ok(out) = Command::new("ps").args(["-p", &pid.to_string(), "-o", "command="]).output() else { return };
    let cmd = String::from_utf8_lossy(&out.stdout);
    if !cmd.contains(&format!("--user-data-dir={}", profile_dir.display())) {
        return;
    }
    let _ = Command::new("kill").args(["-TERM", &pid.to_string()]).status();
    for _ in 0..50 {
        let alive = Command::new("kill").args(["-0", &pid.to_string()]).status().is_ok_and(|s| s.success());
        if !alive {
            return;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let _ = Command::new("kill").args(["-KILL", &pid.to_string()]).status();
}

fn named_key(key: &str) -> Option<(&'static str, u32, &'static str)> {
    Some(match key {
        "Enter" => ("Enter", 13, "\r"),
        "Backspace" => ("Backspace", 8, ""),
        "Tab" => ("Tab", 9, ""),
        "Escape" => ("Escape", 27, ""),
        "Delete" => ("Delete", 46, ""),
        "ArrowLeft" => ("ArrowLeft", 37, ""),
        "ArrowUp" => ("ArrowUp", 38, ""),
        "ArrowRight" => ("ArrowRight", 39, ""),
        "ArrowDown" => ("ArrowDown", 40, ""),
        "Home" => ("Home", 36, ""),
        "End" => ("End", 35, ""),
        "PageUp" => ("PageUp", 33, ""),
        "PageDown" => ("PageDown", 34, ""),
        _ => return None,
    })
}

/// A tiny HTTP GET to Chrome's local debugging endpoint.
async fn http_get_json(port: u16, path: &str) -> std::io::Result<Value> {
    let mut s = tokio::net::TcpStream::connect(("127.0.0.1", port)).await?;
    s.write_all(format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n").as_bytes()).await?;
    // Chrome keeps the connection open: read up to Content-Length.
    let read = async {
        let mut raw = Vec::new();
        let mut buf = [0u8; 8192];
        loop {
            let n = s.read(&mut buf).await?;
            if n == 0 {
                break;
            }
            raw.extend_from_slice(&buf[..n]);
            let text = String::from_utf8_lossy(&raw);
            if let Some((head, body)) = text.split_once("\r\n\r\n") {
                let len = head
                    .lines()
                    .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse::<usize>()))
                    .and_then(Result::ok);
                if len.is_some_and(|len| body.len() >= len) {
                    break;
                }
            }
        }
        Ok::<_, std::io::Error>(raw)
    };
    let raw = tokio::time::timeout(Duration::from_secs(5), read)
        .await
        .map_err(|_| std::io::Error::other("o navegador não respondeu"))??;
    let text = String::from_utf8_lossy(&raw);
    let body = text.split_once("\r\n\r\n").map(|(_, b)| b).unwrap_or_default();
    serde_json::from_str(body).map_err(std::io::Error::other)
}

/// Profile names become folder names.
pub fn valid_profile(name: &str) -> bool {
    !name.is_empty() && name.len() <= 64 && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// The installed Chromium-family browser to use.
pub fn find_chrome(configured: Option<&str>) -> Option<PathBuf> {
    if let Some(c) = configured {
        return Some(PathBuf::from(c));
    }
    [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
    ]
    .iter()
    .map(PathBuf::from)
    .find(|p| p.exists())
}

/// The workspace browsers that are open.
pub struct Browsers {
    root: PathBuf,
    chrome: Option<PathBuf>,
    open: tokio::sync::Mutex<HashMap<String, Arc<Browser>>>,
}

impl Browsers {
    pub fn new(root: PathBuf, chrome: Option<PathBuf>) -> Self {
        Self { root, chrome, open: Default::default() }
    }

    /// The profile's browser, opened if needed.
    pub async fn get(
        &self,
        profile: &str,
        on_event: impl Fn(BrowserEvent) + Send + Sync + 'static,
    ) -> Result<(Arc<Browser>, bool), String> {
        if !valid_profile(profile) {
            return Err(format!("perfil de navegador inválido: {profile}"));
        }
        let mut open = self.open.lock().await;
        if let Some(b) = open.get(profile).filter(|b| b.alive()) {
            return Ok((b.clone(), false));
        }
        let chrome = self.chrome.as_ref().ok_or("nenhum Chrome, Chromium, Brave ou Edge instalado")?;
        let b = Arc::new(Browser::launch(chrome, &self.root.join(profile), on_event).await.map_err(|e| e.to_string())?);
        open.insert(profile.into(), b.clone());
        Ok((b, true))
    }

    pub async fn running(&self, profile: &str) -> Option<Arc<Browser>> {
        self.open.lock().await.get(profile).filter(|b| b.alive()).cloned()
    }

    pub async fn close(&self, profile: &str) {
        let closed = self.open.lock().await.remove(profile);
        if let Some(b) = closed {
            b.shutdown().await;
        }
    }
}
