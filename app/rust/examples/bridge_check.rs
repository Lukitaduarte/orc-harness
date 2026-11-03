//! Pairs and connects through the exact functions the app calls, built
//! with the bridge's dependencies, against a running orcd:
//! `cargo run --example bridge_check -- <ticket>`

use orc_bridge::api::link::{connect_daemon, pair_device};

#[tokio::main]
async fn main() {
    let ticket = std::env::args().nth(1).expect("uso: bridge_check <ticket>");
    let identity = pair_device(ticket, "bridge-check".into()).await.expect("pareamento falhou");
    println!("pareado");
    let link = connect_daemon(identity).await.expect("conexão falhou");
    link.send(r#"{"type":"list_sessions"}"#.into()).await.expect("envio falhou");
    println!("conectado e enviado");
}
