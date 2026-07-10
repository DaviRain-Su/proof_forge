//! Scenario module `fungible_token`.

use std::path::Path;
use std::fs;
use anyhow::{Context, Result};
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{
    account_hash_borsh,
    call_json,
    call_raw,
    deploy_with_metrics,
    ensure_ok,
    ensure_ret,
    refresh_storage,
    view_json_u64,
    view_raw_u64_args,
};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_ft_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    // alice is the deploy account (predecessor for PF raw calls from contract account).
    // For FT mint/transfer we call from the contract's account — predecessor is
    // the signer. near-workspaces contract.call uses the contract account as
    // predecessor. Mint to that account's hash, transfer to bob (hash of
    // "bob.testnet" — balance map only, no bob account needed for PF).
    let alice = contract.id().as_str();
    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let mint_args = account_hash_borsh(alice, Some(100));
            let s = call_raw(&contract, "ft_mint", &mint_args).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF ft_mint")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "ft_total_supply", &[]).await?;
            ensure_ok(&s, "PF supply")?;
            ensure_ret(&s, 100, "PF supply after mint")?;
            steps.push(s);

            let bal_args = account_hash_borsh(alice, None);
            let s = view_raw_u64_args(&contract, "ft_balance_of", &bal_args).await?;
            ensure_ok(&s, "PF bal alice")?;
            ensure_ret(&s, 100, "PF alice bal")?;
            steps.push(s);

            let xfer = account_hash_borsh("bob.testnet", Some(30));
            let s = call_raw(&contract, "ft_transfer", &xfer).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF ft_transfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "ft_balance_of", &bal_args).await?;
            ensure_ok(&s, "PF bal alice after")?;
            ensure_ret(&s, 70, "PF alice after xfer")?;
            steps.push(s);

            let bob_args = account_hash_borsh("bob.testnet", None);
            let s = view_raw_u64_args(&contract, "ft_balance_of", &bob_args).await?;
            ensure_ok(&s, "PF bal bob")?;
            ensure_ret(&s, 30, "PF bob bal")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(
                &contract,
                "ft_mint",
                json!({ "account_id": alice, "amount": 100 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk ft_mint")?;
            steps.push(s);

            let s = view_json_u64(&contract, "ft_total_supply", json!({})).await?;
            ensure_ok(&s, "sdk supply")?;
            ensure_ret(&s, 100, "sdk supply")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "ft_balance_of",
                json!({ "account_id": alice }),
            )
            .await?;
            ensure_ok(&s, "sdk bal alice")?;
            ensure_ret(&s, 100, "sdk alice bal")?;
            steps.push(s);

            // Create bob account so LookupMap AccountId is valid; transfer as contract
            // (predecessor = contract id which we minted to).
            let bob = worker.dev_create_account().await.context("create bob")?;
            let s = call_json(
                &contract,
                "ft_transfer",
                json!({ "receiver_id": bob.id().as_str(), "amount": 30 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk ft_transfer")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "ft_balance_of",
                json!({ "account_id": alice }),
            )
            .await?;
            ensure_ok(&s, "sdk bal alice after")?;
            ensure_ret(&s, 70, "sdk alice after")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "ft_balance_of",
                json!({ "account_id": bob.id().as_str() }),
            )
            .await?;
            ensure_ok(&s, "sdk bal bob")?;
            ensure_ret(&s, 30, "sdk bob bal")?;
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

