//! Scenario: pro-rata vault (ERC-4626-inspired internal shares).

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{account_u64, SideCtx};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_pro_rata_vault_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let who = account_u64(ctx.contract.id().as_str());

    // Scenario proves pro-rata via state: deposit 100 → donate 100 → deposit 100
    // yields balance 150 / supply 150 / assets 300 (second deposit mints 50 shares).
    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.call_raw("deposit", &100u64.to_le_bytes(), "PF deposit 100")
            .await?;
        ctx.call_raw("donate", &100u64.to_le_bytes(), "PF donate 100")
            .await?;
        ctx.call_raw("deposit", &100u64.to_le_bytes(), "PF deposit 100 @ 50%")
            .await?;
        ctx.view_raw_u64_args("balance_of", &who.to_le_bytes(), "PF bal", Some(150))
            .await?;
        ctx.view_raw_u64("total_supply", "PF supply", Some(150)).await?;
        ctx.view_raw_u64("total_assets", "PF assets", Some(300)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.call_json("deposit", json!({ "assets": 100 }), "sdk deposit 100")
            .await?;
        ctx.call_json("donate", json!({ "assets": 100 }), "sdk donate")
            .await?;
        ctx.call_json("deposit", json!({ "assets": 100 }), "sdk deposit 2")
            .await?;
        ctx.view_json_u64("balance_of", json!({ "who": who }), "sdk bal", Some(150))
            .await?;
        ctx.view_json_u64("total_supply", json!({}), "sdk supply", Some(150))
            .await?;
        ctx.view_json_u64("total_assets", json!({}), "sdk assets", Some(300))
            .await?;
    }
    ctx.finish().await
}
