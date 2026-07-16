//! Scenario: value-vault dual-deploy.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_value_vault_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    // initialize(100) → get_balance=100 → deposit(50) → get_balance=150
    if ctx.is_pf() {
        ctx.call_raw("initialize", &100u64.to_le_bytes(), "PF initialize").await?;
        ctx.view_raw_u64("get_balance", "PF get_balance#1", Some(100)).await?;
        ctx.call_raw("deposit", &50u64.to_le_bytes(), "PF deposit").await?;
        ctx.view_raw_u64("get_balance", "PF get_balance#2", Some(150)).await?;
    } else {
        ctx.call_json("initialize", json!({ "initial": 100 }), "sdk initialize").await?;
        ctx.view_json_u64("get_balance", json!({}), "sdk get_balance#1", Some(100)).await?;
        ctx.call_json("deposit", json!({ "amount": 50 }), "sdk deposit").await?;
        ctx.view_json_u64("get_balance", json!({}), "sdk get_balance#2", Some(150)).await?;
    }
    ctx.finish().await
}
