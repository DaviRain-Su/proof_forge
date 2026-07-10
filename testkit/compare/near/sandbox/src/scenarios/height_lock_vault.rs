//! Scenario: binary height lock (lock → claim after block height).

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::SideCtx;
use crate::report::{SideKind, SideReport};

fn pack2(a: u64, b: u64) -> [u8; 16] {
    let mut out = [0u8; 16];
    out[0..8].copy_from_slice(&a.to_le_bytes());
    out[8..16].copy_from_slice(&b.to_le_bytes());
    out
}

pub(crate) async fn run_height_lock_vault_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;

    // unlockHeight=1 → any real sandbox block_height fully unlocks amount=1000.
    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.view_raw_u64("get_locked", "PF locked0", Some(0)).await?;
        ctx.call_raw("lock", &pack2(1000, 1), "PF lock").await?;
        ctx.view_raw_u64("get_locked", "PF locked", Some(1000)).await?;
        ctx.view_raw_u64("get_unlock_height", "PF unlock h", Some(1))
            .await?;
        ctx.call_raw("claim", &[], "PF claim").await?;
        ctx.view_raw_u64("claim_balance", "PF claim bal", Some(1000))
            .await?;
        ctx.view_raw_u64("is_claimed", "PF claimed", Some(1)).await?;
        ctx.view_raw_u64("get_locked", "PF locked after", Some(0)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.view_json_u64("get_locked", json!({}), "sdk locked0", Some(0))
            .await?;
        ctx.call_json(
            "lock",
            json!({ "amount": 1000, "unlock_height": 1 }),
            "sdk lock",
        )
        .await?;
        ctx.view_json_u64("get_locked", json!({}), "sdk locked", Some(1000))
            .await?;
        ctx.view_json_u64("get_unlock_height", json!({}), "sdk unlock h", Some(1))
            .await?;
        ctx.call_json("claim", json!({}), "sdk claim").await?;
        ctx.view_json_u64("claim_balance", json!({}), "sdk claim bal", Some(1000))
            .await?;
        ctx.view_json_u64("is_claimed", json!({}), "sdk claimed", Some(1))
            .await?;
        ctx.view_json_u64("get_locked", json!({}), "sdk locked after", Some(0))
            .await?;
    }
    ctx.finish().await
}
