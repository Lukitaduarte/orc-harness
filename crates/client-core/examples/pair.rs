//! `cargo run -p orc-client-core --example pair -- <ticket> [name]`
//! Pairs from the command line and prints the identity JSON (for scripts
//! and checks; the app pairs through its own dialog).

#[tokio::main]
async fn main() {
    let mut args = std::env::args().skip(1);
    let ticket = args.next().expect("uso: pair <ticket> [nome]");
    let name = args.next().unwrap_or_else(|| "linha de comando".into());
    match orc_client_core::pair(&ticket, &name).await {
        Ok(identity) => println!("{identity}"),
        Err(e) => {
            eprintln!("falhou: {e}");
            std::process::exit(1);
        }
    }
}
