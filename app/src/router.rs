use log::info;
use salvo::{
    Router,
    conn::rustls::{Keycert, RustlsConfig},
    prelude::*,
};

#[handler]
async fn redirect_to_gh_proxy(req: &mut Request, res: &mut Response) {
    info!("redirect: {}", req.uri());
    res.render(Redirect::found(format!(
        "https://gh-proxy.com/{}",
        req.uri()
    )));
}

pub fn init_router() -> Router {
    Router::new()
        .host("github.com")
        .push(
            Router::with_path("/{user}/{repo}/releases/download/{**rest}")
                .goal(redirect_to_gh_proxy),
        )
        .push(Router::with_path("{**rest}").goal(Proxy::use_hyper_client("https://lgithub.xyz")))
}

pub fn init_tls_config(public_key: &[u8], private_key: &[u8]) -> RustlsConfig {
    RustlsConfig::new(Keycert::new().cert(public_key).key(private_key))
}
