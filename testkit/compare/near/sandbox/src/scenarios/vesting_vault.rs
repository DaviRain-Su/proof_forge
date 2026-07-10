//! Scenario: linear vesting vault (HostEnv timestamp).

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

/// Pack 4 LE u64s for ProofForge Borsh-style multi-arg entry.
fn pack4(a: u64, b: u64, c: u64, d: u64) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[0..8].copy_from_slice(&a.to_le_bytes());
    out[8..16].copy_from_slice(&b.to_le_bytes());
    out[16..24].copy_from_slice(&c.to_le_bytes());
    out[24..32].copy_from_slice(&d.to_le_bytes());
    out
}

pub(crate) async fn run_vesting_vault_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;

    // start=0, duration=1 → any real sandbox block_timestamp fully vests total=1000.
    if ctx.is_pf() {
        ctx.call_raw("init", &pack4(7, 1000, 0, 1), "PF init").await?;
        ctx.view_raw_u64("total_allocation", "PF total0", Some(1000))
            .await?;
        ctx.view_raw_u64("claim_balance", "PF claim0", Some(0)).await?;
        ctx.view_raw_u64("released_amount", "PF rel0", Some(0)).await?;
        ctx.call_raw("release", &[], "PF release").await?;
        ctx.view_raw_u64("claim_balance", "PF claim", Some(1000))
            .await?;
        ctx.view_raw_u64("released_amount", "PF released", Some(1000))
            .await?;
        ctx.view_raw_u64("total_allocation", "PF total", Some(1000))
            .await?;
    } else {
        ctx.call_json(
            "init",
            json!({ "who": 7, "total": 1000, "start": 0, "dur": 1 }),
            "sdk init",
        )
        .await?;
        ctx.view_json_u64("total_allocation", json!({}), "sdk total0", Some(1000))
            .await?;
        ctx.view_json_u64("claim_balance", json!({}), "sdk claim0", Some(0))
            .await?;
        ctx.view_json_u64("released_amount", json!({}), "sdk rel0", Some(0))
            .await?;
        ctx.call_json("release", json!({}), "sdk release").await?;
        ctx.view_json_u64("claim_balance", json!({}), "sdk claim", Some(1000))
            .await?;
        ctx.view_json_u64("released_amount", json!({}), "sdk released", Some(1000))
            .await?;
        ctx.view_json_u64("total_allocation", json!({}), "sdk total", Some(1000))
            .await?;
    }
    ctx.finish().await
}
