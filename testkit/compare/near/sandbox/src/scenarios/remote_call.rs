//! Scenario module `remote_call`.

use std::path::Path;
use std::fs;
use anyhow::{bail, Context, Result};
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{
    call_json,
    call_raw,
    deploy_with_metrics,
    ensure_file,
    ensure_ok,
    refresh_storage,
};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_remote_call_matrix(
    worker: &Worker<Sandbox>,
    repo_root: &Path,
    _pf_stub_wasm: &Path,
    sdk_wasm: &Path,
    callee_wasm: &Path,
) -> Result<(SideReport, SideReport)> {
    ensure_file(callee_wasm, "callee wasm")?;
    ensure_file(sdk_wasm, "sdk caller wasm")?;

    // ── callee ──────────────────────────────────────────────────────────────
    let callee_bytes = fs::read(callee_wasm)?;
    let (callee, _c_deploy, _) = deploy_with_metrics(worker, &callee_bytes).await?;
    let s = call_json(&callee, "new", json!({})).await?;
    ensure_ok(&s, "callee new")?;
    let callee_id = callee.id().to_string();
    println!("remote-call: callee account = {callee_id}");

    // ── rebuild PF with peer binding ────────────────────────────────────────
    let pf_out = repo_root.join("build/testkit/compare/near/remote-call/proof-forge-live");
    if pf_out.exists() {
        let _ = fs::remove_dir_all(&pf_out);
    }
    fs::create_dir_all(&pf_out)?;
    let peer_spec = format!("peer.callee={callee_id}");
    let status = std::process::Command::new("lake")
        .current_dir(repo_root)
        .args([
            "env",
            "proof-forge",
            "build",
            "--target",
            "wasm-near",
            "--root",
            ".",
            "--peer",
            &peer_spec,
            "-o",
        ])
        .arg(&pf_out)
        .arg("Examples/Product/RemoteCall.lean")
        .status()
        .context("spawn lake env proof-forge for peer rebuild")?;
    if !status.success() {
        bail!("skip: failed to rebuild PF RemoteCall with --peer (lake/proof-forge unavailable or build failed)");
    }
    let pf_wasm_path = ["remotecall.wasm", "RemoteCall.wasm"]
        .iter()
        .map(|n| pf_out.join(n))
        .find(|p| p.is_file())
        .context("peer-rebuilt PF wasm missing")?;
    // wat2wasm if only wat present
    if !pf_wasm_path.is_file() {
        bail!("peer-rebuilt PF wasm missing at {}", pf_out.display());
    }

    // ── PF caller ───────────────────────────────────────────────────────────
    let pf_bytes = fs::read(&pf_wasm_path)?;
    let pf_wasm_bytes = pf_bytes.len() as u64;
    let (pf_contract, pf_deploy, _) = deploy_with_metrics(worker, &pf_bytes).await?;
    let mut pf_steps = Vec::new();
    let mut pf_call_gas = 0u64;

    let s = call_raw(&pf_contract, "initialize", &[]).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF initialize")?;
    pf_steps.push(s);

    let s = call_raw(&pf_contract, "call_remote", &[]).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF call_remote")?;
    pf_steps.push(s);

    let pf_storage = refresh_storage(&pf_contract).await?;
    let pf = SideReport {
        label: SideKind::ProofForge.label().into(),
        account_id: pf_contract.id().to_string(),
        wasm_bytes: pf_wasm_bytes,
        deploy_gas_burnt: pf_deploy,
        storage_usage_bytes: pf_storage,
        call_gas_burnt: pf_call_gas,
        total_gas_burnt: pf_deploy.saturating_add(pf_call_gas),
        steps: pf_steps,
    };

    // ── sdk caller ──────────────────────────────────────────────────────────
    let sdk_bytes = fs::read(sdk_wasm)?;
    let sdk_wasm_bytes = sdk_bytes.len() as u64;
    let (sdk_contract, sdk_deploy, _) = deploy_with_metrics(worker, &sdk_bytes).await?;
    let mut sdk_steps = Vec::new();
    let mut sdk_call_gas = 0u64;

    let s = call_json(
        &sdk_contract,
        "initialize",
        json!({ "callee": callee_id }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk initialize")?;
    sdk_steps.push(s);

    let s = call_json(&sdk_contract, "call_remote", json!({})).await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk call_remote")?;
    sdk_steps.push(s);

    let sdk_storage = refresh_storage(&sdk_contract).await?;
    let sdk = SideReport {
        label: SideKind::NearSdk.label().into(),
        account_id: sdk_contract.id().to_string(),
        wasm_bytes: sdk_wasm_bytes,
        deploy_gas_burnt: sdk_deploy,
        storage_usage_bytes: sdk_storage,
        call_gas_burnt: sdk_call_gas,
        total_gas_burnt: sdk_deploy.saturating_add(sdk_call_gas),
        steps: sdk_steps,
    };

    Ok((pf, sdk))
}

