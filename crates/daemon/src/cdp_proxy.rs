//! The agents' way into a workspace browser. Each session's Playwright MCP
//! gets `http://127.0.0.1:<port>/orc/<profile>/<session>` as its CDP
//! endpoint; this proxy forwards to that profile's Chrome (opening it if
//! needed) and sees who drives it, so the app can show the browser "in use
//! by" a session. Local only, like Chrome's own port.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use orc_protocol::DaemonMessage;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt, ReadBuf};
use tokio::net::{TcpListener, TcpStream};

use crate::server::Daemon;

/// A browser counts as in use this long after the agent's last command.
pub const ACTIVE_FOR: Duration = Duration::from_secs(5);

/// Last agent traffic per browser profile: (session, when).
pub type BrowserUse = Arc<Mutex<HashMap<String, (String, Instant)>>>;

fn valid(s: &str) -> bool {
    !s.is_empty() && s.len() <= 64 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

/// `/orc/<profile>/<session>/rest` → (profile, session, `/rest`).
pub fn route(path: &str) -> Option<(String, String, String)> {
    let rest = path.strip_prefix("/orc/")?;
    let mut parts = rest.splitn(3, '/');
    let (profile, session) = (parts.next()?, parts.next()?);
    if !valid(profile) || !valid(session) {
        return None;
    }
    Some((profile.into(), session.into(), format!("/{}", parts.next().unwrap_or(""))))
}

/// Counts what the agent sends: any byte marks the browser in use.
struct Watched<R> {
    inner: R,
    usage: BrowserUse,
    profile: String,
    session: String,
}

impl<R: AsyncRead + Unpin> AsyncRead for Watched<R> {
    fn poll_read(mut self: std::pin::Pin<&mut Self>, cx: &mut std::task::Context<'_>, buf: &mut ReadBuf<'_>) -> std::task::Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        let r = std::pin::Pin::new(&mut self.inner).poll_read(cx, buf);
        if buf.filled().len() > before {
            let (p, s) = (self.profile.clone(), self.session.clone());
            self.usage.lock().unwrap().insert(p, (s, Instant::now()));
        }
        r
    }
}

/// Reads an HTTP request or response head (up to the blank line).
async fn read_head(s: &mut TcpStream) -> std::io::Result<(String, Vec<u8>)> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        let n = s.read(&mut chunk).await?;
        if n == 0 {
            return Err(std::io::Error::other("conexão fechada"));
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&buf[..i + 4]).into_owned();
            return Ok((head, buf[i + 4..].to_vec()));
        }
        if buf.len() > 64 * 1024 {
            return Err(std::io::Error::other("cabeçalho grande demais"));
        }
    }
}

async fn reply(s: &mut TcpStream, status: &str, body: &str) {
    let _ = s
        .write_all(format!("HTTP/1.1 {status}\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).as_bytes())
        .await;
}

/// The request head for Chrome: its own path and Host (Chrome only answers
/// local hosts and builds its URLs from Host).
fn rewrite_head(head: &str, path: &str, chrome: u16) -> String {
    let mut lines = head.split("\r\n");
    let first = lines.next().unwrap_or_default();
    let mut parts = first.splitn(3, ' ');
    let (method, version) = (parts.next().unwrap_or("GET"), parts.nth(1).unwrap_or("HTTP/1.1"));
    let mut out = format!("{method} {path} {version}\r\n");
    for l in lines {
        if l.to_ascii_lowercase().starts_with("host:") {
            out.push_str(&format!("Host: 127.0.0.1:{chrome}\r\n"));
        } else if !l.is_empty() {
            out.push_str(l);
            out.push_str("\r\n");
        }
    }
    out.push_str("\r\n");
    out
}

async fn handle(mut client: TcpStream, daemon: Daemon, me: u16, usage: BrowserUse) -> std::io::Result<()> {
    let (head, early) = read_head(&mut client).await?;
    let path = head.split_whitespace().nth(1).unwrap_or_default().to_string();
    let Some((profile, session, rest)) = route(&path) else {
        reply(&mut client, "404 Not Found", "use /orc/<perfil>/<sessão>/").await;
        return Ok(());
    };
    if daemon.sessions.lock().unwrap().summary(&session).is_none() {
        reply(&mut client, "403 Forbidden", "sessão desconhecida").await;
        return Ok(());
    }
    // The agent may come before anyone opened the browser.
    let browser = match daemon.open_browser(&profile).await {
        Ok(b) => b,
        Err(e) => {
            reply(&mut client, "503 Service Unavailable", &e).await;
            return Ok(());
        }
    };
    let chrome: u16 = browser.cdp_http.rsplit(':').next().and_then(|p| p.parse().ok()).unwrap_or(0);
    let mut upstream = TcpStream::connect(("127.0.0.1", chrome)).await?;
    let websocket = head.to_ascii_lowercase().contains("upgrade: websocket");
    upstream.write_all(rewrite_head(&head, &rest, chrome).as_bytes()).await?;
    upstream.write_all(&early).await?;
    if websocket {
        usage.lock().unwrap().insert(profile.clone(), (session.clone(), Instant::now()));
        let (cr, mut cw) = client.into_split();
        let (mut ur, mut uw) = upstream.into_split();
        let mut watched = Watched { inner: cr, usage, profile, session };
        let up = tokio::io::copy(&mut watched, &mut uw);
        let down = tokio::io::copy(&mut ur, &mut cw);
        let _ = tokio::join!(up, down);
        return Ok(());
    }
    // Plain HTTP (/json/version…): Chrome's URLs point back here.
    let (resp_head, mut body) = read_head(&mut upstream).await?;
    let len = resp_head
        .lines()
        .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse::<usize>()))
        .and_then(Result::ok);
    let mut chunk = [0u8; 8192];
    while len.is_none_or(|l| body.len() < l) {
        let n = upstream.read(&mut chunk).await?;
        if n == 0 {
            break;
        }
        body.extend_from_slice(&chunk[..n]);
    }
    let body = String::from_utf8_lossy(&body).replace(
        &format!("127.0.0.1:{chrome}"),
        &format!("127.0.0.1:{me}/orc/{profile}/{session}"),
    );
    let status = resp_head.lines().next().unwrap_or("HTTP/1.1 200 OK");
    client
        .write_all(format!("{status}\r\nContent-Type: application/json; charset=UTF-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).as_bytes())
        .await?;
    Ok(())
}

/// Serves the proxy, and tells clients when a browser's agent starts and
/// stops driving it.
pub async fn serve(listener: TcpListener, daemon: Daemon) {
    let me = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    let usage = daemon.browser_use.clone();
    let (d, u) = (daemon.clone(), usage.clone());
    tokio::spawn(async move {
        let mut shown: HashMap<String, String> = HashMap::new();
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        loop {
            tick.tick().await;
            let now: HashMap<String, String> = u
                .lock()
                .unwrap()
                .iter()
                .filter(|(_, (_, at))| at.elapsed() < ACTIVE_FOR)
                .map(|(p, (s, _))| (p.clone(), s.clone()))
                .collect();
            for (profile, session) in &now {
                if shown.get(profile) != Some(session) {
                    let _ = d.events.send(DaemonMessage::BrowserUse { profile: profile.clone(), session_id: Some(session.clone()) });
                }
            }
            for profile in shown.keys().filter(|p| !now.contains_key(*p)) {
                let _ = d.events.send(DaemonMessage::BrowserUse { profile: profile.clone(), session_id: None });
            }
            shown = now;
        }
    });
    while let Ok((client, _)) = listener.accept().await {
        let (d, u) = (daemon.clone(), usage.clone());
        tokio::spawn(async move {
            let _ = handle(client, d, me, u).await;
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_and_heads() {
        assert_eq!(route("/orc/live/s3/json/version"), Some(("live".into(), "s3".into(), "/json/version".into())));
        assert_eq!(route("/orc/live/s3/devtools/browser/ab"), Some(("live".into(), "s3".into(), "/devtools/browser/ab".into())));
        assert_eq!(route("/orc/live/s3"), Some(("live".into(), "s3".into(), "/".into())));
        assert_eq!(route("/orc/../s3/x"), None);
        assert_eq!(route("/json/version"), None);
        let head = "GET /orc/live/s3/json/version HTTP/1.1\r\nHost: 127.0.0.1:5000\r\nAccept: */*\r\n\r\n";
        assert_eq!(
            rewrite_head(head, "/json/version", 9222),
            "GET /json/version HTTP/1.1\r\nHost: 127.0.0.1:9222\r\nAccept: */*\r\n\r\n"
        );
    }
}
