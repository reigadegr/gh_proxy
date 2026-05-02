use std::sync::OnceLock;

use anyhow::anyhow;
use serde::Deserialize;
use toml::from_str;

static PROFILE: OnceLock<Config> = OnceLock::new();

pub fn init_config(app_config: &str) -> anyhow::Result<()> {
    let profile: Config = from_str(app_config)?;
    PROFILE
        .set(profile)
        .map_err(|_| anyhow!("Failed to set configuration."))?;
    Ok(())
}

pub fn get_cfg() -> anyhow::Result<&'static Config> {
    PROFILE
        .get()
        .ok_or_else(|| anyhow!("Configuration not initialized."))
}

#[derive(Deserialize)]
pub struct Config {
    pub client_cfg: ClientCfg,
}

#[derive(Deserialize, Eq, Hash, PartialEq)]
pub struct ClientCfg {
    pub service_ip: String,
    pub service_port: i32,
}
