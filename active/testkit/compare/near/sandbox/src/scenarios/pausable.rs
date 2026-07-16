//! Scenario: pausable emergency-stop mixin.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_pausable_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    if ctx.is_pf() {
        ctx.view_raw_u64("paused", "PF paused0", Some(0)).await?;
        ctx.call_raw("pause", &[], "PF pause").await?;
        ctx.view_raw_u64("paused", "PF paused1", Some(1)).await?;
        ctx.call_raw("unpause", &[], "PF unpause").await?;
        ctx.view_raw_u64("paused", "PF paused2", Some(0)).await?;
    } else {
        ctx.view_json_u64("paused", json!({}), "sdk paused0", Some(0)).await?;
        ctx.call_json("pause", json!({}), "sdk pause").await?;
        ctx.view_json_u64("paused", json!({}), "sdk paused1", Some(1)).await?;
        ctx.call_json("unpause", json!({}), "sdk unpause").await?;
        ctx.view_json_u64("paused", json!({}), "sdk paused2", Some(0)).await?;
    }
    ctx.finish().await
}
