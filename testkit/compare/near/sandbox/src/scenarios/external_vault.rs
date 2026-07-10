//! Scenario: external-vault multi-account peer client.

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

pub(crate) async fn run_external_vault_matrix(
    worker: &Worker<Sandbox>,
    repo_root: &Path,
    _pf_stub_wasm: &Path,
    sdk_wasm: &Path,
    peer_wasm: &Path,
) -> Result<(SideReport, SideReport)> {
    ensure_file(peer_wasm, "vault peer wasm")?;
    ensure_file(sdk_wasm, "sdk client wasm")?;

    let peer_bytes = fs::read(peer_wasm)?;
    let (peer, _, _) = deploy_with_metrics(worker, &peer_bytes).await?;
    let s = call_json(&peer, "new", json!({})).await?;
    ensure_ok(&s, "vault peer new")?;
    let peer_id = peer.id().to_string();
    println!("external-vault: vault peer = {peer_id}");

    let pf_out = repo_root.join("build/testkit/compare/near/external-vault/proof-forge-live");
    if pf_out.exists() {
        let _ = fs::remove_dir_all(&pf_out);
    }
    fs::create_dir_all(&pf_out)?;
    let peer_spec = format!("vault.peer={peer_id}");
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
        .arg("Examples/Product/ExternalVault.lean")
        .status()
        .context("rebuild ExternalVault with peer")?;
    if !status.success() {
        bail!("skip: failed to rebuild PF ExternalVault with --peer");
    }
    let pf_wasm_path = ["externalvault.wasm", "ExternalVault.wasm"]
        .iter()
        .map(|n| pf_out.join(n))
        .find(|p| p.is_file())
        .context("peer-rebuilt ExternalVault wasm missing")?;

    // ── PF ──────────────────────────────────────────────────────────────────
    let pf_bytes = fs::read(&pf_wasm_path)?;
    let pf_wasm_bytes = pf_bytes.len() as u64;
    let (pf_contract, pf_deploy, _) = deploy_with_metrics(worker, &pf_bytes).await?;
    let mut pf_steps = Vec::new();
    let mut pf_call_gas = 0u64;

    let s = call_raw(&pf_contract, "initialize", &[]).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF initialize")?;
    pf_steps.push(s);

    let mut dep = 100u64.to_le_bytes().to_vec();
    dep.extend_from_slice(&7u64.to_le_bytes());
    let s = call_raw(&pf_contract, "deposit_assets", &dep).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF deposit_assets")?;
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

    // ── sdk ─────────────────────────────────────────────────────────────────
    let (peer2, _, _) = deploy_with_metrics(worker, &peer_bytes).await?;
    let s = call_json(&peer2, "new", json!({})).await?;
    ensure_ok(&s, "vault peer2 new")?;
    let peer2_id = peer2.id().to_string();

    let sdk_bytes = fs::read(sdk_wasm)?;
    let sdk_wasm_bytes = sdk_bytes.len() as u64;
    let (sdk_contract, sdk_deploy, _) = deploy_with_metrics(worker, &sdk_bytes).await?;
    let mut sdk_steps = Vec::new();
    let mut sdk_call_gas = 0u64;

    let s = call_json(
        &sdk_contract,
        "initialize",
        json!({ "vault": peer2_id }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk initialize")?;
    sdk_steps.push(s);

    let s = call_json(
        &sdk_contract,
        "deposit_assets",
        json!({ "assets": 100, "receiver": 7 }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk deposit_assets")?;
    sdk_steps.push(s);

    let s = view_json_u64(&sdk_contract, "last_shares", json!({})).await?;
    ensure_ok(&s, "sdk last_shares")?;
    if s.return_u64 != Some(100) {
        bail!("sdk last_shares expected 100, got {:?}", s.return_u64);
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
