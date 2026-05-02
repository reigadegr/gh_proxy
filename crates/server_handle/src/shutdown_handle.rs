use std::sync::OnceLock;

use anyhow::anyhow;
use salvo::server::ServerHandle;
use tokio::signal;
use tracing::{error, info};

static SERVER_HANDLE: OnceLock<ServerHandle> = OnceLock::new();

pub fn init_handle(handle: ServerHandle) -> anyhow::Result<()> {
    SERVER_HANDLE
        .set(handle)
        .map_err(|_| anyhow!("Failed to set server handle."))?;
    Ok(())
}

pub fn get_handle() -> anyhow::Result<&'static ServerHandle> {
    SERVER_HANDLE
        .get()
        .ok_or_else(|| anyhow!("Server handle not initialized."))
}

pub async fn shutdown_signal() {
    let ctrl_c = async {
        match signal::ctrl_c().await {
            Ok(()) => Some(()),
            Err(e) => {
                error!("Failed to install Ctrl+C handler: {e}");
                std::process::exit(1);
            }
        }
    };

    #[cfg(unix)]
    let terminate = async {
        match signal::unix::signal(signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                if signal.recv().await == Some(()) {
                    Some(())
                } else {
                    None
                }
            }
            Err(e) => {
                error!("Failed to install signal handler: {e}");
                std::process::exit(1);
            }
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<Option<()>>();

    tokio::select! {
        Some(()) = ctrl_c => info!("ctrl_c signal received"),
        Some(()) = terminate => info!("terminate signal received"),
    }

    #[cfg(debug_assertions)]
    let timeout = std::time::Duration::from_secs(1);

    #[cfg(not(debug_assertions))]
    let timeout = std::time::Duration::from_secs(60);

    match get_handle() {
        Ok(handle) => handle.stop_graceful(timeout),
        Err(e) => {
            error!("Failed to get server handle: {e}");
            std::process::exit(1);
        }
    }
}
