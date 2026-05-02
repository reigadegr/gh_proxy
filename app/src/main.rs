mod router;

use std::{fmt, io::IsTerminal};

use chrono::Local;
use mimalloc::MiMalloc;
use my_server_handle::shutdown_handle::{init_handle, shutdown_signal};
use salvo::prelude::*;
use tracing_subscriber::{
    EnvFilter,
    fmt::{format::Writer, time::FormatTime},
};

use crate::router::{create_http_client, init_router, init_tls_config};

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

struct LoggerFormatter;

impl FormatTime for LoggerFormatter {
    fn format_time(&self, w: &mut Writer<'_>) -> fmt::Result {
        write!(w, "{}", Local::now().format("%Y-%m-%d %H:%M:%S"))
    }
}

#[tokio::main]
async fn main() {
    // 初始化日志
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("debug"));

    let is_terminal = std::io::stdout().is_terminal();

    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_timer(LoggerFormatter)
        .with_ansi(is_terminal)
        .init();

    let private_key = include_bytes!("../../keys/private_key.pem");
    let public_key = include_bytes!("../../keys/cert.pem");

    let tls_config = init_tls_config(public_key, private_key);
    let client = create_http_client();
    let router = init_router(client);

    let acceptor = TcpListener::new("0.0.0.0:443")
        .rustls(tls_config)
        .bind()
        .await;
    tokio::spawn(shutdown_signal());
    let server = Server::new(acceptor);

    if let Err(e) = init_handle(server.handle()) {
        eprintln!("Failed to initialize server handle: {e}");
        std::process::exit(1);
    }

    server.serve(router).await;
}
