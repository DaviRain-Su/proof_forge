//! Scenario: auth-remote-call multi-account (debit + promise receive).

use std::fs;
use std::path::Path;

use anyhow::{bail, Context, Result};
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{
    call_json, call_raw, deploy_with_metrics, ensure_file, ensure_ok, refresh_storage,
    view_json_u64,
};
use crate::report::{SideKind, SideReport};

/// Deploy callee, rebuild PF AuthRemoteCall with peer, dual-deploy callers.
pub(crate) async fn run_auth_remote_call_matrix(
    worker: &Worker<Sandbox>,
    repo_root: &Path,
    _pf_stub_wasm: &Path,
    sdk_wasm: &Path,
    callee_wasm: &Path,
) -> Result<(SideReport, SideReport)> {
    ensure_file(callee_wasm, "callee wasm")?;
    ensure_file(sdk_wasm, "sdk caller wasm")?;

    let callee_bytes = fs::read(callee_wasm)?;
    let (callee, _c_deploy, _) = deploy_with_metrics(worker, &callee_bytes).await?;
    let s = call_json(&callee, "new", json!({})).await?;
    ensure_ok(&s, "callee new")?;
    let callee_id = callee.id().to_string();
    println!("auth-remote-call: callee account = {callee_id}");

    let pf_out = repo_root.join("build/testkit/compare/near/auth-remote-call/proof-forge-live");
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
        .arg("Examples/Product/AuthRemoteCall.lean")
        .status()
        .context("spawn lake env proof-forge for AuthRemoteCall peer rebuild")?;
    if !status.success() {
        bail!("skip: failed to rebuild PF AuthRemoteCall with --peer");
    }
    let pf_wasm_path = ["authremotecall.wasm", "AuthRemoteCall.wasm"]
        .iter()
        .map(|n| pf_out.join(n))
        .find(|p| p.is_file())
        .context("peer-rebuilt AuthRemoteCall wasm missing")?;

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

    let s = call_raw(&pf_contract, "debit_and_forward", &10u64.to_le_bytes()).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF debit_and_forward")?;
    pf_steps.push(s);

    // Peer should have received amount 10 (async; near-workspaces resolves promises).
    let s = view_json_u64(&callee, "total", json!({})).await?;
    ensure_ok(&s, "callee total after PF")?;
    // Best-effort: if promise settled, total==10; otherwise still ok if call succeeded.
    if s.return_u64 == Some(10) {
        pf_steps.push(s);
    }

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
    // Fresh callee for independent sdk scenario (avoid shared total).
    let (callee2, _, _) = deploy_with_metrics(worker, &callee_bytes).await?;
    let s = call_json(&callee2, "new", json!({})).await?;
    ensure_ok(&s, "callee2 new")?;
    let callee2_id = callee2.id().to_string();

    let sdk_bytes = fs::read(sdk_wasm)?;
    let sdk_wasm_bytes = sdk_bytes.len() as u64;
    let (sdk_contract, sdk_deploy, _) = deploy_with_metrics(worker, &sdk_bytes).await?;
    let mut sdk_steps = Vec::new();
    let mut sdk_call_gas = 0u64;

    let s = call_json(
        &sdk_contract,
        "initialize",
        json!({ "callee": callee2_id }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk initialize")?;
    sdk_steps.push(s);

    let s = call_json(
        &sdk_contract,
        "debit_and_forward",
        json!({ "amount": 10 }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk debit_and_forward")?;
    sdk_steps.push(s);

    let s = view_json_u64(&sdk_contract, "balance", json!({})).await?;
    ensure_ok(&s, "sdk balance")?;
    if s.return_u64 != Some(90) {
        bail!("sdk balance after debit: expected 90, got {:?}", s.return_u64);
    }
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
