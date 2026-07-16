//! Verify stable Hash-valued map reads and per-entrypoint hash allocator reset
//! in a real near-sandbox VM.

use anyhow::{bail, Context, Result};
use near_workspaces::Worker;
use std::env;
use std::path::PathBuf;

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
            return;
        }
    }
}

fn hash_args() -> Vec<u8> {
    let mut args = Vec::with_capacity(64);
    for limb in 1u64..=8 {
        args.extend_from_slice(&limb.to_le_bytes());
    }
    args
}

#[tokio::main]
async fn main() -> Result<()> {
    ensure_sandbox_bin_env();
    let wasm_path = repo_root().join("build/near-map-hash-alias/alias.wasm");
    let wasm =
        std::fs::read(&wasm_path).with_context(|| format!("read {}", wasm_path.display()))?;
    let worker: Worker<near_workspaces::network::Sandbox> = near_workspaces::sandbox()
        .await
        .context("near_workspaces::sandbox()")?;
    let contract = worker
        .dev_deploy(&wasm)
        .await
        .context("deploy alias fixture")?;

    for call_index in 1..=2 {
        let outcome = contract
            .call("alias_probe")
            .args(hash_args())
            .transact()
            .await
            .with_context(|| format!("alias_probe call {call_index}"))?;
        if !outcome.is_success() {
            bail!("alias_probe call {call_index} failed: {outcome:?}");
        }
        let bytes = outcome
            .raw_bytes()
            .map_err(|error| anyhow::anyhow!("alias_probe return: {error}"))?;
        if bytes != [1] {
            bail!("alias_probe call {call_index} returned {bytes:?}, expected Borsh true");
        }
    }

    println!("near-map-hash-alias-sandbox: ok (stable reads and entry reset)");
    Ok(())
}
