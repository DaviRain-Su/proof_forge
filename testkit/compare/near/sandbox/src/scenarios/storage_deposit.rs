//! Scenario: NEP-145-lite storage_deposit.

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{sha256_32, SideCtx};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_storage_deposit_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let alice = ctx.contract.id().as_str().to_string();
    let alice_hash = sha256_32(alice.as_bytes());
    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.view_raw_u64("storage_balance_bounds", "PF bounds", Some(1)).await?;
        ctx.view_raw_u64_args("storage_balance_of", &alice_hash, "PF bal0", Some(0)).await?;
        ctx.call_raw_deposit("storage_deposit", &alice_hash, 7, "PF deposit").await?;
        ctx.view_raw_u64_args("storage_balance_of", &alice_hash, "PF bal1", Some(7)).await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.view_json_u64("storage_balance_bounds", json!({}), "sdk bounds", Some(1)).await?;
        ctx.view_json_u64(
            "storage_balance_of",
            json!({ "account_id": alice.clone() }),
            "sdk bal0",
            Some(0),
        )
        .await?;
        ctx.call_json_deposit(
            "storage_deposit",
            json!({ "account_id": alice.clone() }),
            7,
            "sdk deposit",
        )
        .await?;
        ctx.view_json_u64(
            "storage_balance_of",
            json!({ "account_id": alice }),
            "sdk bal1",
            Some(7),
        )
        .await?;
    }
    ctx.finish().await
}
