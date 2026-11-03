//! What Dart calls to reach the daemon. Messages cross as JSON strings
//! (orc_protocol shapes); Dart parses them into its own models.

use std::sync::OnceLock;

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;

/// iroh needs tokio; flutter_rust_bridge runs async calls on its own
/// executor, so the network work runs here and is awaited from there.
fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

/// Pairs with the daemon that issued `ticket` (from `orcd pair`). Returns
/// the identity JSON the app must keep to connect later.
pub async fn pair_device(ticket: String, device_name: String) -> Result<String, String> {
    runtime()
        .spawn(async move { orc_client_core::pair(&ticket, &device_name).await })
        .await
        .map_err(|e| e.to_string())?
}

/// An open link to the daemon.
#[frb(opaque)]
pub struct DaemonLink {
    conn: orc_client_core::Connection,
    inbox: std::sync::Mutex<Option<tokio::sync::mpsc::UnboundedReceiver<String>>>,
}

impl DaemonLink {
    /// Sends one client message (JSON).
    pub async fn send(&self, json: String) -> Result<(), String> {
        self.conn.send(json).await
    }

    /// Daemon messages as JSON, from the moment of connecting (nothing is
    /// lost before Dart listens). Ends after a final
    /// `{"type":"link_closed","reason":…}`. Can be listened to once.
    pub fn listen(&self, sink: StreamSink<String>) {
        let Some(mut rx) = self.inbox.lock().unwrap().take() else { return };
        runtime().spawn(async move {
            while let Some(m) = rx.recv().await {
                if sink.add(m).is_err() {
                    break;
                }
            }
        });
    }
}

/// Connects with a stored identity (from `pair_device`).
pub async fn connect_daemon(identity: String) -> Result<DaemonLink, String> {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    let closed = tx.clone();
    let conn = runtime()
        .spawn(async move {
            orc_client_core::connect(
                &identity,
                move |m| {
                    let _ = tx.send(m);
                },
                move |reason| {
                    let _ = closed.send(format!(
                        "{{\"type\":\"link_closed\",\"reason\":{}}}",
                        string_json(&reason)
                    ));
                },
            )
            .await
        })
        .await
        .map_err(|e| e.to_string())??;
    Ok(DaemonLink { conn, inbox: std::sync::Mutex::new(Some(rx)) })
}

fn string_json(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
