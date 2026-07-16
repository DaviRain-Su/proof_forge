//! Scenario: two-party escrow (fund → release).

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

pub(crate) async fn run_escrow_vault_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;

    // init(7, 8) → fund(1000) → release → seller_claim=1000, status=2 (Released)
    if ctx.is_pf() {
        ctx.call_raw("init", &pack2(7, 8), "PF init").await?;
        ctx.view_raw_u64("get_status", "PF status0", Some(0)).await?;
        ctx.view_raw_u64("get_buyer", "PF buyer", Some(7)).await?;
        ctx.view_raw_u64("get_seller", "PF seller", Some(8)).await?;
        ctx.call_raw("fund", &1000u64.to_le_bytes(), "PF fund").await?;
        ctx.view_raw_u64("get_status", "PF funded", Some(1)).await?;
        ctx.view_raw_u64("get_amount", "PF amount", Some(1000)).await?;
        ctx.call_raw("release", &[], "PF release").await?;
        ctx.view_raw_u64("get_status", "PF released", Some(2)).await?;
        ctx.view_raw_u64("seller_claim", "PF seller claim", Some(1000))
            .await?;
        ctx.view_raw_u64("buyer_claim", "PF buyer claim", Some(0))
            .await?;
    } else {
        ctx.call_json(
            "init",
            json!({ "buyer_id": 7, "seller_id": 8 }),
            "sdk init",
        )
        .await?;
        ctx.view_json_u64("get_status", json!({}), "sdk status0", Some(0))
            .await?;
        ctx.view_json_u64("get_buyer", json!({}), "sdk buyer", Some(7))
            .await?;
        ctx.view_json_u64("get_seller", json!({}), "sdk seller", Some(8))
            .await?;
        ctx.call_json("fund", json!({ "amt": 1000 }), "sdk fund")
            .await?;
        ctx.view_json_u64("get_status", json!({}), "sdk funded", Some(1))
            .await?;
        ctx.view_json_u64("get_amount", json!({}), "sdk amount", Some(1000))
            .await?;
        ctx.call_json("release", json!({}), "sdk release").await?;
        ctx.view_json_u64("get_status", json!({}), "sdk released", Some(2))
            .await?;
        ctx.view_json_u64("seller_claim", json!({}), "sdk seller claim", Some(1000))
            .await?;
        ctx.view_json_u64("buyer_claim", json!({}), "sdk buyer claim", Some(0))
            .await?;
    }
    ctx.finish().await
}
