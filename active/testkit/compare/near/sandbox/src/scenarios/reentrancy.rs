//! Scenario: reentrancy-guard lock-bit mixin.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_reentrancy_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    if ctx.is_pf() {
        ctx.view_raw_u64("locked", "PF locked0", Some(0)).await?;
        ctx.call_raw("acquire", &[], "PF acquire").await?;
        ctx.view_raw_u64("locked", "PF locked1", Some(1)).await?;
        ctx.call_raw("release", &[], "PF release").await?;
        ctx.view_raw_u64("locked", "PF locked2", Some(0)).await?;
    } else {
        ctx.view_json_u64("locked", json!({}), "sdk locked0", Some(0)).await?;
        ctx.call_json("acquire", json!({}), "sdk acquire").await?;
        ctx.view_json_u64("locked", json!({}), "sdk locked1", Some(1)).await?;
        ctx.call_json("release", json!({}), "sdk release").await?;
        ctx.view_json_u64("locked", json!({}), "sdk locked2", Some(0)).await?;
    }
    ctx.finish().await
}
