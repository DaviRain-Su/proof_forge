//! Scenario: counter dual-deploy.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_counter_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    if ctx.is_pf() {
        ctx.call_raw("initialize", &[], "PF initialize").await?;
        ctx.view_raw_u64("get", "PF get#1", Some(0)).await?;
        ctx.call_raw("increment", &[], "PF increment").await?;
        ctx.view_raw_u64("get", "PF get#2", Some(1)).await?;
    } else {
        ctx.call_json("initialize", json!({}), "sdk initialize").await?;
        ctx.view_json_u64("get", json!({}), "sdk get#1", Some(0)).await?;
        ctx.call_json("increment", json!({}), "sdk increment").await?;
        ctx.view_json_u64("get", json!({}), "sdk get#2", Some(1)).await?;
    }
    ctx.finish().await
}
