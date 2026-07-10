//! Scenario: Backend FtPeerClient multi-account (protocol NEP-141 client).

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

pub(crate) async fn run_ft_peer_client_matrix(
    worker: &Worker<Sandbox>,
    repo_root: &Path,
    _pf_stub_wasm: &Path,
    sdk_wasm: &Path,
    peer_wasm: &Path,
) -> Result<(SideReport, SideReport)> {
    ensure_file(peer_wasm, "FT peer wasm")?;
    ensure_file(sdk_wasm, "sdk client wasm")?;

    let peer_bytes = fs::read(peer_wasm)?;
    let (peer, _, _) = deploy_with_metrics(worker, &peer_bytes).await?;
    let s = call_json(&peer, "new", json!({})).await?;
    ensure_ok(&s, "FT peer new")?;
    let peer_id = peer.id().to_string();
    println!("ft-peer-client: FT peer = {peer_id}");

    // Receiver account for sdk side (and for PF rebuild pool alice.near is fixed).
    let receiver = worker
        .dev_create_account()
        .await
        .context("create receiver account")?;
    let receiver_id = receiver.id().to_string();

    let pf_out = repo_root.join("build/testkit/compare/near/ft-peer-client/proof-forge-live");
    if pf_out.exists() {
        let _ = fs::remove_dir_all(&pf_out);
    }
    fs::create_dir_all(&pf_out)?;
    // Bind my_ft peer; alice.near is baked into IR host pool for receiver.
    let peer_spec = format!("my_ft={peer_id}");
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
        .arg("Examples/Backend/WasmNear/FtPeerClient.lean")
        .status()
        .context("rebuild FtPeerClient with peer")?;
    if !status.success() {
        bail!("skip: failed to rebuild PF FtPeerClient with --peer");
    }
    let pf_wasm_path = ["nearftpeerclient.wasm", "NearFtPeerClient.wasm", "ftpeerclient.wasm"]
        .iter()
        .map(|n| pf_out.join(n))
        .find(|p| p.is_file())
        .context("peer-rebuilt FtPeerClient wasm missing")?;

    // ── PF ──────────────────────────────────────────────────────────────────
    let pf_bytes = fs::read(&pf_wasm_path)?;
    let pf_wasm_bytes = pf_bytes.len() as u64;
    let (pf_contract, pf_deploy, _) = deploy_with_metrics(worker, &pf_bytes).await?;
    let mut pf_steps = Vec::new();
    let mut pf_call_gas = 0u64;

    let s = call_raw(&pf_contract, "pay", &50u64.to_le_bytes()).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF pay")?;
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
    ensure_ok(&s, "FT peer2 new")?;
    let peer2_id = peer2.id().to_string();

    let sdk_bytes = fs::read(sdk_wasm)?;
    let sdk_wasm_bytes = sdk_bytes.len() as u64;
    let (sdk_contract, sdk_deploy, _) = deploy_with_metrics(worker, &sdk_bytes).await?;
    let mut sdk_steps = Vec::new();
    let mut sdk_call_gas = 0u64;

    let s = call_json(
        &sdk_contract,
        "new",
        json!({ "token": peer2_id, "receiver": receiver_id }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk new")?;
    sdk_steps.push(s);

    let s = call_json(&sdk_contract, "pay", json!({ "amount": 50 })).await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk pay")?;
    sdk_steps.push(s);

    let s = view_json_u64(&sdk_contract, "last_amount", json!({})).await?;
    ensure_ok(&s, "sdk last_amount")?;
    if s.return_u64 != Some(50) {
        bail!("sdk last_amount expected 50, got {:?}", s.return_u64);
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
