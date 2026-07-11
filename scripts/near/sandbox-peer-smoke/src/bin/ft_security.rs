//! Execute the NEAR FT authority and callback-privacy attacks against a real
//! near-sandbox VM with distinct signer accounts.

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

fn mint_args(amount: u64) -> Vec<u8> {
    let mut args = vec![7u8; 32];
    args.extend_from_slice(&amount.to_le_bytes());
    args
}

fn callback_args() -> Vec<u8> {
    let mut args = 0u64.to_le_bytes().to_vec();
    args.extend_from_slice(&[7u8; 32]);
    args.extend_from_slice(&[8u8; 32]);
    args
}

#[tokio::main]
async fn main() -> Result<()> {
    ensure_sandbox_bin_env();
    let wasm_path = repo_root().join("build/near-ft-security/nearfungibletoken.wasm");
    let wasm =
        std::fs::read(&wasm_path).with_context(|| format!("read {}", wasm_path.display()))?;
    let worker: Worker<near_workspaces::network::Sandbox> = near_workspaces::sandbox()
        .await
        .context("near_workspaces::sandbox()")?;
    let contract = worker.dev_deploy(&wasm).await.context("deploy FT")?;
    let owner = worker.dev_create_account().await.context("create owner")?;
    let attacker = worker
        .dev_create_account()
        .await
        .context("create attacker")?;

    let init = owner
        .call(contract.id(), "init")
        .args(vec![])
        .transact()
        .await
        .context("owner init")?;
    if !init.is_success() {
        bail!("owner init failed: {init:?}");
    }

    let repeat = owner
        .call(contract.id(), "init")
        .args(vec![])
        .transact()
        .await
        .context("repeat init transaction")?;
    if repeat.is_success() {
        bail!("repeat init unexpectedly succeeded");
    }

    let owner_mint = owner
        .call(contract.id(), "ft_mint")
        .args(mint_args(10))
        .transact()
        .await
        .context("owner mint")?;
    if !owner_mint.is_success() {
        bail!("owner mint failed: {owner_mint:?}");
    }

    let attacker_mint = attacker
        .call(contract.id(), "ft_mint")
        .args(mint_args(10))
        .transact()
        .await
        .context("attacker mint transaction")?;
    if attacker_mint.is_success() {
        bail!("attacker mint unexpectedly succeeded");
    }

    let direct_callback = attacker
        .call(contract.id(), "ft_resolve_transfer")
        .args(callback_args())
        .transact()
        .await
        .context("direct callback transaction")?;
    if direct_callback.is_success() {
        bail!("attacker direct callback unexpectedly succeeded");
    }

    println!(
        "near-ft-security-sandbox: ok (repeat init, attacker mint, and direct callback rejected)"
    );
    Ok(())
}
