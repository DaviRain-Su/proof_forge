//! Scenario: array-example fixed u64x3 locals.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_array_example_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    if ctx.is_pf() {
        ctx.view_raw_u64("sizeOf3", "PF size", Some(3)).await?;
        ctx.view_raw_u64("getElem", "PF elem", Some(20)).await?;
        ctx.view_raw_u64("sumOf3", "PF sum", Some(60)).await?;
    } else {
        ctx.view_json_u64("size_of3", json!({}), "sdk size", Some(3))
            .await?;
        ctx.view_json_u64("get_elem", json!({}), "sdk elem", Some(20))
            .await?;
        ctx.view_json_u64("sum_of3", json!({}), "sdk sum", Some(60))
            .await?;
    }
    ctx.finish().await
}
