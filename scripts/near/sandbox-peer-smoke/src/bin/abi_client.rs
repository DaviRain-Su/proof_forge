//! Deploy the generated Borsh echo fixture and keep the sandbox alive while the
//! generated TypeScript client calls it through raw NEAR RPC.

use anyhow::{bail, Context, Result};
use near_workspaces::{Contract, Worker};
use std::env;
use std::path::PathBuf;
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn ensure_sandbox_bin_env() {
    if env::var_os("NEAR_SANDBOX_BIN_PATH").is_some() {
        return;
    }
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    for candidate in [
        home.join(".near/near-sandbox-2.13.0/near-sandbox"),
        home.join(".local/bin/near-sandbox"),
    ] {
        if candidate.is_file() {
            env::set_var("NEAR_SANDBOX_BIN_PATH", &candidate);
            eprintln!(
                "near-abi-client-sandbox: NEAR_SANDBOX_BIN_PATH={}",
                candidate.display()
            );
            return;
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    ensure_sandbox_bin_env();
    let root = repo_root();
    let wasm_path = root.join("build/near-abi-client/echo.wasm");
    let client_path = root.join("build/near-abi-client/dist/sandbox-smoke.js");
    let wasm =
        std::fs::read(&wasm_path).with_context(|| format!("read {}", wasm_path.display()))?;

    eprintln!("near-abi-client-sandbox: starting near-sandbox");
    let worker: Worker<near_workspaces::network::Sandbox> = near_workspaces::sandbox()
        .await
        .context("near_workspaces::sandbox()")?;
    let contract: Contract = worker
        .dev_deploy(&wasm)
        .await
        .context("deploy echo fixture")?;
    let rpc_url = worker.rpc_addr();
    eprintln!(
        "near-abi-client-sandbox: echo at {} via {}",
        contract.id(),
        rpc_url
    );

    let status = Command::new("node")
        .current_dir(&root)
        .arg(&client_path)
        .env("NEAR_RPC_URL", rpc_url.as_str())
        .env("NEAR_CONTRACT_ID", contract.id().as_str())
        .status()
        .context("run generated TypeScript client")?;
    if !status.success() {
        bail!("generated TypeScript client failed: {status}");
    }
    Ok(())
}
