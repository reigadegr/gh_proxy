use std::sync::{Arc, OnceLock};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::{Request as HyperRequest, Response as HyperResponse};
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::{
    client::legacy::{Client, connect::HttpConnector},
    rt::TokioExecutor,
};
use log::info;
use salvo::{
    Router,
    conn::rustls::{Keycert, RustlsConfig},
    prelude::*,
};

pub type HttpClient = Client<hyper_rustls::HttpsConnector<HttpConnector>, Full<Bytes>>;

static HTTP_CLIENT: OnceLock<Arc<HttpClient>> = OnceLock::new();

pub fn create_http_client() -> Arc<HttpClient> {
    let https = HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http1()
        .build();
    let client = Arc::new(Client::builder(TokioExecutor::new()).build(https));
    let _ = HTTP_CLIENT.set(client.clone());
    client
}

fn get_client() -> &'static Arc<HttpClient> {
    HTTP_CLIENT
        .get()
        .expect("HTTP_CLIENT not initialized, call create_http_client() first")
}

#[handler]
async fn log_request(
    req: &mut Request,
    depot: &mut Depot,
    res: &mut Response,
    ctrl: &mut FlowCtrl,
) {
    let method = req.method().clone();
    let uri = req.uri().clone();
    let host = req
        .headers()
        .get("host")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("?")
        .to_string();
    info!(">>> {method} {uri} Host:{host}");
    ctrl.call_next(req, depot, res).await;
    info!("<<< {method} {uri} -> {:?}", res.status_code);
}

#[handler]
async fn redirect_to_gh_proxy(req: &mut Request, res: &mut Response) {
    info!("redirect: {}", req.uri());
    res.render(Redirect::found(format!(
        "https://gh-proxy.com/{}",
        req.uri()
    )));
}

#[handler]
async fn direct_to_github(req: &mut Request, res: &mut Response) {
    let client = get_client();
    let upstream = "https://github.com";

    let path = req.params().tail().unwrap_or("");
    let query = req
        .uri()
        .query()
        .map(|q| format!("?{q}"))
        .unwrap_or_default();
    let forward_url = format!("{upstream}/{path}{query}");

    info!("forwarding to: {forward_url}");

    // 读取请求体
    let body_bytes = req
        .payload()
        .await
        .map_or_else(|_| Bytes::new(), Clone::clone);

    // 构建 hyper 请求
    let mut builder = HyperRequest::builder()
        .method(req.method())
        .uri(&forward_url);

    // 复制原始请求头（跳过 host、content-length）
    for (name, value) in req.headers() {
        if name != "host" && name != "content-length" {
            builder = builder.header(name, value);
        }
    }

    // 设置正确的 Host
    builder = builder.header("host", "github.com");

    let proxy_req = match builder.body(Full::new(body_bytes)) {
        Ok(req) => req,
        Err(e) => {
            info!("build request error: {e}");
            res.status_code(StatusCode::INTERNAL_SERVER_ERROR);
            return;
        }
    };

    // 发送请求
    match client.request(proxy_req).await {
        Ok(upstream_res) => {
            forward_response(upstream_res, res).await;
        }
        Err(e) => {
            info!("upstream error: {e}");
            res.status_code(StatusCode::BAD_GATEWAY);
        }
    }
}

async fn forward_response(upstream_res: HyperResponse<hyper::body::Incoming>, res: &mut Response) {
    let status = upstream_res.status();
    info!("upstream response: {status}");

    let headers = upstream_res.headers().clone();
    for (key, value) in &headers {
        if key != "content-length" && key != "transfer-encoding" {
            res.headers.append(key.clone(), value.clone());
        }
    }

    match upstream_res.collect().await {
        Ok(body) => {
            res.status_code(status);
            res.body(body.to_bytes());
        }
        Err(e) => {
            info!("body read error: {e}");
            res.status_code(StatusCode::INTERNAL_SERVER_ERROR);
        }
    }
}

pub fn init_router(_client: Arc<HttpClient>) -> Router {
    Router::new()
        .host("github.com")
        .hoop(log_request)
        .push(
            Router::with_path("/{user}/{repo}/releases/download/{**rest}")
                .goal(redirect_to_gh_proxy),
        )
        .push(Router::with_path("{**rest}").goal(direct_to_github))
}

pub fn init_tls_config(public_key: &[u8], private_key: &[u8]) -> RustlsConfig {
    RustlsConfig::new(Keycert::new().cert(public_key).key(private_key))
}
