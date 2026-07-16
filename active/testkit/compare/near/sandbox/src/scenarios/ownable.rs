//! Scenario module `ownable`.

use std::path::Path;
use std::fs;
use anyhow::{Context, ensure, Result};
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{
    account_u64,
    call_json,
    call_raw,
    deploy_with_metrics,
    ensure_ok,
    ensure_ret,
    refresh_storage,
    view_raw_u64,
};
use crate::report::{SideKind, SideReport, StepReport};

pub(crate) async fn run_ownable_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    let alice = contract.id().as_str().to_string();
    let alice_u64 = account_u64(&alice);

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "owner").await?;
            ensure_ok(&s, "PF owner#1")?;
            ensure_ret(&s, alice_u64, "PF owner after init")?;
            steps.push(s);

            let bob = worker.dev_create_account().await.context("bob")?;
            let bob_u64 = account_u64(bob.id().as_str());
            let s = call_raw(&contract, "transferOwnership", &bob_u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF transferOwnership")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "owner").await?;
            ensure_ok(&s, "PF owner#2")?;
            ensure_ret(&s, bob_u64, "PF owner after transfer")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            // owner view returns AccountId string — check via view bytes/json.
            let details = contract.view("owner").args_json(json!({})).await?;
            let owner: String = details.json().context("owner AccountId")?;
            ensure!(
                owner == alice,
                "sdk owner after init: expected {alice}, got {owner}"
            );
            steps.push(StepReport {
                call: "owner".into(),
                kind: "view".into(),
                ok: true,
                gas_burnt: None,
                return_u64: None,
                logs: details.logs,
                error: None,
            });

            let bob = worker.dev_create_account().await.context("bob")?;
            let s = call_json(
                &contract,
                "transfer_ownership",
                json!({ "new_owner": bob.id().as_str() }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk transfer_ownership")?;
            steps.push(s);

            let details = contract.view("owner").args_json(json!({})).await?;
            let owner: String = details.json().context("owner2")?;
            ensure!(
                owner == bob.id().as_str(),
                "sdk owner after transfer: expected {}, got {owner}",
                bob.id()
            );
            steps.push(StepReport {
                call: "owner".into(),
                kind: "view".into(),
                ok: true,
                gas_burnt: None,
                return_u64: None,
                logs: details.logs,
                error: None,
            });
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

