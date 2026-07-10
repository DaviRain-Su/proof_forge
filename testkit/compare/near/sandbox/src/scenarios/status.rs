//! Scenario: status-message dual-deploy.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{account_u64, SideCtx};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_status_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let alice = ctx.contract.id().as_str().to_string();
    let alice_u64 = account_u64(&alice);
    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.call_raw("set_status", &7u64.to_le_bytes(), "PF set_status").await?;
        ctx.view_raw_u64_args("get_status", &alice_u64.to_le_bytes(), "PF get", Some(7)).await?;
        ctx.call_raw("set_status", &99u64.to_le_bytes(), "PF set 99").await?;
        ctx.view_raw_u64_args("get_status", &alice_u64.to_le_bytes(), "PF get 99", Some(99)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.call_json("set_status", json!({ "status": 7 }), "sdk set").await?;
        ctx.view_json_u64("get_status", json!({ "account": alice.clone() }), "sdk get", Some(7)).await?;
        ctx.call_json("set_status", json!({ "status": 99 }), "sdk set 99").await?;
        ctx.view_json_u64("get_status", json!({ "account": alice }), "sdk get 99", Some(99)).await?;
    }
    ctx.finish().await
}
