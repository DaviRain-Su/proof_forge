//! Scenario module `fee_token`.

use std::path::Path;
use std::fs;
use anyhow::{Context, Result};
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
    view_json_u64,
    view_raw_u64,
    view_raw_u64_args,
};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_fee_side(
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
            let s = call_raw(&contract, "init", &1000u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let mut mint = alice_u64.to_le_bytes().to_vec();
            mint.extend_from_slice(&100u64.to_le_bytes());
            let s = call_raw(&contract, "mint", &mint).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF mint")?;
            steps.push(s);

            let bob_u64 = account_u64("bob.testnet");
            let mut xfer = bob_u64.to_le_bytes().to_vec();
            xfer.extend_from_slice(&50u64.to_le_bytes());
            let s = call_raw(&contract, "transfer", &xfer).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF transfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &alice_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal alice")?;
            ensure_ret(&s, 50, "PF alice after fee xfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &bob_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal bob")?;
            ensure_ret(&s, 45, "PF bob net")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "totalSupply").await?;
            ensure_ok(&s, "PF supply")?;
            ensure_ret(&s, 95, "PF supply after fee")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({ "fee_bps": 1000 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(
                &contract,
                "mint",
                json!({ "recipient": alice, "amount": 100 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk mint")?;
            steps.push(s);

            let bob = worker.dev_create_account().await.context("bob")?;
            let s = call_json(
                &contract,
                "transfer",
                json!({ "recipient": bob.id().as_str(), "amount": 50 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk transfer")?;
            steps.push(s);

            let s = view_json_u64(&contract, "balance_of", json!({ "who": alice })).await?;
            ensure_ok(&s, "sdk bal alice")?;
            ensure_ret(&s, 50, "sdk alice")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "balance_of",
                json!({ "who": bob.id().as_str() }),
            )
            .await?;
            ensure_ok(&s, "sdk bal bob")?;
            ensure_ret(&s, 45, "sdk bob")?;
            steps.push(s);

            let s = view_json_u64(&contract, "total_supply", json!({})).await?;
            ensure_ok(&s, "sdk supply")?;
            ensure_ret(&s, 95, "sdk supply")?;
            steps.push(s);
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

