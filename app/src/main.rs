mod router;

use mimalloc::MiMalloc;
use my_server_handle::shutdown_handle::shutdown_signal;
use obfstr::obfbytes;
use salvo::prelude::*;

use crate::router::{init_router, init_tls_config};

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt().init();

    let private_key = obfbytes!(include_bytes!("../../keys/private_key.pem"));
    let public_key = obfbytes!(include_bytes!("../../keys/cert.pem"));

    let tls_config = init_tls_config(public_key, private_key);
    let router = init_router();

    let acceptor = TcpListener::new("0.0.0.0:443")
        .rustls(tls_config)
        .bind()
        .await;
    tokio::spawn(shutdown_signal());
    Server::new(acceptor).serve(router).await;
}
