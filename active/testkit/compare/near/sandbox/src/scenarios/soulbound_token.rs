//! Scenario: soulbound token body (mint/burn, no transfer).

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{account_u64, SideCtx};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_soulbound_token_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let who = account_u64(ctx.contract.id().as_str());

    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        let mut mint = who.to_le_bytes().to_vec();
        mint.extend_from_slice(&10u64.to_le_bytes());
        ctx.call_raw("mint", &mint, "PF mint").await?;
        ctx.view_raw_u64_args("balance_of", &who.to_le_bytes(), "PF bal 10", Some(10))
            .await?;
        ctx.view_raw_u64("total_supply", "PF supply 10", Some(10)).await?;
        ctx.call_raw("burn", &10u64.to_le_bytes(), "PF burn").await?;
        ctx.view_raw_u64_args("balance_of", &who.to_le_bytes(), "PF bal 0", Some(0))
            .await?;
        ctx.view_raw_u64("total_supply", "PF supply 0", Some(0)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.call_json(
            "mint",
            json!({ "recipient": who, "amount": 10 }),
            "sdk mint",
        )
        .await?;
        ctx.view_json_u64("balance_of", json!({ "who": who }), "sdk bal 10", Some(10))
            .await?;
        ctx.view_json_u64("total_supply", json!({}), "sdk supply 10", Some(10))
            .await?;
        ctx.call_json("burn", json!({ "amount": 10 }), "sdk burn").await?;
        ctx.view_json_u64("balance_of", json!({ "who": who }), "sdk bal 0", Some(0))
            .await?;
        ctx.view_json_u64("total_supply", json!({}), "sdk supply 0", Some(0))
            .await?;
    }
    ctx.finish().await
}
