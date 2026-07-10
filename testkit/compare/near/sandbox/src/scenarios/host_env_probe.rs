//! Scenario: host-env-probe triad snapshot.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{account_u64, SideCtx};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_host_env_probe_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let self_id = ctx.contract.id().as_str().to_string();
    // contract.call predecessor = contract account on near-workspaces.
    let expect_caller = account_u64(&self_id);
    let expect_self = account_u64(&self_id);

    if ctx.is_pf() {
        ctx.call_raw("initialize", &[], "PF init").await?;
        ctx.view_raw_u64("getCaller", "PF caller0", Some(0)).await?;
        ctx.call_raw("snapshot", &[], "PF snapshot").await?;
        ctx.view_raw_u64("getCaller", "PF caller", Some(expect_caller))
            .await?;
        ctx.view_raw_u64("getSelf", "PF self", Some(expect_self))
            .await?;
        // Time/height are host-defined; only require success (may be 0 or >0).
        ctx.view_raw_u64("getTime", "PF time", None).await?;
        ctx.view_raw_u64("getHeight", "PF height", None).await?;
    } else {
        ctx.call_json("initialize", json!({}), "sdk init").await?;
        ctx.view_json_u64("get_caller", json!({}), "sdk caller0", Some(0))
            .await?;
        ctx.call_json("snapshot", json!({}), "sdk snapshot").await?;
        ctx.view_json_u64("get_caller", json!({}), "sdk caller", Some(expect_caller))
            .await?;
        ctx.view_json_u64("get_self", json!({}), "sdk self", Some(expect_self))
            .await?;
        ctx.view_json_u64("get_time", json!({}), "sdk time", None)
            .await?;
        ctx.view_json_u64("get_height", json!({}), "sdk height", None)
            .await?;
    }
    ctx.finish().await
}
