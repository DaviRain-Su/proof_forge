//! Scenario: ownable-hash (32-byte sha256 owner).

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{sha256_32, SideCtx};
use crate::report::{SideKind, SideReport};

pub(crate) async fn run_ownable_hash_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let self_id = ctx.contract.id().as_str().to_string();
    // Deploy account is predecessor for contract.call; owner = sha256(self).
    let owner_hash = sha256_32(self_id.as_bytes());
    let zeros = [0u8; 32];

    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.view_raw_bytes("owner", "PF owner after init", Some(&owner_hash))
            .await?;
        ctx.call_raw("renounceOwnership", &[], "PF renounce").await?;
        ctx.view_raw_bytes("owner", "PF owner renounced", Some(&zeros))
            .await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.view_json_bytes("owner", json!({}), "sdk owner after init", Some(&owner_hash))
            .await?;
        ctx.call_json("renounce_ownership", json!({}), "sdk renounce")
            .await?;
        ctx.view_json_bytes("owner", json!({}), "sdk owner renounced", Some(&zeros))
            .await?;
    }
    ctx.finish().await
}
