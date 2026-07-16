//! PF-P2-03: deploy RemoteCall + PeerOracle to near-sandbox and assert
//! `call_with_args` returns u64 49 (42+7 via promise to peer `remote_call`).

use anyhow::{bail, Context, Result};
use near_workspaces::types::{Gas, NearToken};
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
    for c in [
        home.join(".near/near-sandbox-2.13.0/near-sandbox"),
        home.join(".local/bin/near-sandbox"),
    ] {
        if c.is_file() {
            env::set_var("NEAR_SANDBOX_BIN_PATH", &c);
            eprintln!("sandbox-peer-smoke: NEAR_SANDBOX_BIN_PATH={}", c.display());
            return;
        }
    }
}

fn parse_u64_le(bytes: &[u8]) -> Result<u64> {
    if bytes.len() < 8 {
        bail!("expected ≥8 return bytes, got {} ({bytes:?})", bytes.len());
    }
    Ok(u64::from_le_bytes(bytes[..8].try_into().unwrap()))
}

fn rebuild_host_with_peer(root: &std::path::Path, peer_id: &str) -> Result<Vec<u8>> {
    let out_dir = root.join("build/near-sandbox-peer/host");
    std::fs::create_dir_all(&out_dir)?;
    let status = Command::new("lake")
        .current_dir(root)
        .args([
            "env",
            "proof-forge",
            "build",
            "--target",
            "wasm-near",
            "--root",
            ".",
            "--peer",
            &format!("peer.callee={peer_id}"),
            "-o",
            out_dir.to_str().unwrap(),
            "Examples/Product/RemoteCall.lean",
        ])
        .status()
        .context("proof-forge build")?;
    if !status.success() {
        bail!("proof-forge build RemoteCall failed: {status}");
    }
    let path = out_dir.join("remotecall.wasm");
    std::fs::read(&path).with_context(|| format!("read {}", path.display()))
}

#[tokio::main]
async fn main() -> Result<()> {
    ensure_sandbox_bin_env();
    let root = repo_root();
    let peer_wasm_path = root.join("Examples/Backend/WasmNear/fixtures/PeerOracle.wasm");
    if !peer_wasm_path.exists() {
        bail!("missing peer wasm {}", peer_wasm_path.display());
    }
    let peer_wasm = std::fs::read(&peer_wasm_path)?;

    eprintln!("sandbox-peer-smoke: starting near-sandbox…");
    let worker: Worker<near_workspaces::network::Sandbox> = near_workspaces::sandbox()
        .await
        .context("near_workspaces::sandbox()")?;

    let peer_contract: Contract = worker
        .dev_deploy(&peer_wasm)
        .await
        .context("deploy peer")?;
    let peer_id = peer_contract.id().to_string();
    eprintln!("sandbox-peer-smoke: peer at {peer_id}");

    let host_wasm = rebuild_host_with_peer(&root, &peer_id)?;
    let host_contract: Contract = worker
        .dev_deploy(&host_wasm)
        .await
        .context("deploy host")?;
    eprintln!("sandbox-peer-smoke: host at {}", host_contract.id());

    // PF-P2-02: storage accounting — storage_usage must be positive after deploy
    // and non-decreasing after initialize (writes marker state).
    let storage_before = host_contract
        .view_account()
        .await
        .context("view_account before init")?
        .storage_usage;
    eprintln!("sandbox-peer-smoke: storage_usage before init={storage_before}");

    let init = host_contract
        .call("initialize")
        .args_borsh(())
        .deposit(NearToken::from_yoctonear(0))
        .transact()
        .await
        .context("initialize")?;
    if !init.is_success() {
        bail!("initialize failed: {init:?}");
    }

    let storage_after = host_contract
        .view_account()
        .await
        .context("view_account after init")?
        .storage_usage;
    eprintln!("sandbox-peer-smoke: storage_usage after init={storage_after}");
    if storage_after == 0 {
        bail!("storage_usage after initialize is 0 (expected non-zero contract storage)");
    }
    if storage_after < storage_before {
        bail!("storage_usage decreased after initialize ({storage_before} → {storage_after})");
    }

    let outcome = host_contract
        .call("call_with_args")
        .args_borsh(())
        .gas(Gas::from_tgas(100))
        .transact()
        .await
        .context("call_with_args")?;

    eprintln!("sandbox-peer-smoke: outcome logs={:?}", outcome.logs());
    if !outcome.is_success() {
        bail!("call_with_args failed: {outcome:?}");
    }

    // N1.6: real NEAR VM gas from sandbox (not Wasmtime fuel).
    let near_gas = outcome.total_gas_burnt.as_gas();
    if near_gas == 0 {
        bail!("expected non-zero nearGas from sandbox call_with_args");
    }
    eprintln!("sandbox-peer-smoke: nearGas={near_gas} (NEAR VM gas burnt)");

    // Prefer Borsh u64 in the value return.
    let raw = outcome
        .raw_bytes()
        .map_err(|e| anyhow::anyhow!("raw_bytes: {e}"))?;
    let n = parse_u64_le(&raw).with_context(|| format!("raw={raw:?}"))?;
    if n != 49 {
        bail!("expected call_with_args → 49, got {n}");
    }
    println!(
        "sandbox-peer-smoke: ok (call_with_args → 49 via near-sandbox peer; storage_usage={storage_after}; nearGas={near_gas})"
    );
    Ok(())
}
