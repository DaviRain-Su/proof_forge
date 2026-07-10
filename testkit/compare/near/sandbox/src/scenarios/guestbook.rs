//! Scenario: guestbook dual-deploy.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_guestbook_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.call_raw("add_message", &11u64.to_le_bytes(), "PF add 11").await?;
        ctx.call_raw("add_message", &22u64.to_le_bytes(), "PF add 22").await?;
        ctx.view_raw_u64("total_messages", "PF total", Some(2)).await?;
        ctx.view_raw_u64_args("get_message", &0u64.to_le_bytes(), "PF get0", Some(11)).await?;
        ctx.view_raw_u64_args("get_message", &1u64.to_le_bytes(), "PF get1", Some(22)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.call_json("add_message", json!({ "code": 11 }), "sdk add 11").await?;
        ctx.call_json("add_message", json!({ "code": 22 }), "sdk add 22").await?;
        ctx.view_json_u64("total_messages", json!({}), "sdk total", Some(2)).await?;
        ctx.view_json_u64("get_message", json!({ "index": 0 }), "sdk get0", Some(11)).await?;
        ctx.view_json_u64("get_message", json!({ "index": 1 }), "sdk get1", Some(22)).await?;
    }
    ctx.finish().await
}
