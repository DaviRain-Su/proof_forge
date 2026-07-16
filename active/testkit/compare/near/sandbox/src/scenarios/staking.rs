//! Scenario: staking-vault dual-deploy.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_staking_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.call_raw_deposit("deposit", &[], 50, "PF deposit").await?;
        ctx.view_raw_u64("totalDeposits", "PF total#1", Some(50)).await?;
        ctx.call_raw("withdraw", &20u64.to_le_bytes(), "PF withdraw").await?;
        ctx.view_raw_u64("totalDeposits", "PF total#2", Some(30)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.call_json_deposit("deposit", json!({}), 50, "sdk deposit").await?;
        ctx.view_json_u64("total_deposits", json!({}), "sdk total#1", Some(50)).await?;
        ctx.call_json("withdraw", json!({ "share_amount": 20 }), "sdk withdraw").await?;
        ctx.view_json_u64("total_deposits", json!({}), "sdk total#2", Some(30)).await?;
    }
    ctx.finish().await
}
