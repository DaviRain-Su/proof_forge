//! Scenario: access-control role map (admin grant/revoke).

use std::path::Path;

use anyhow::Result;
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;
use serde_json::json;

use crate::host::{account_u64, SideCtx};
use crate::report::{SideKind, SideReport};

fn role_who_args(role: u64, who: u64) -> Vec<u8> {
    let mut v = role.to_le_bytes().to_vec();
    v.extend_from_slice(&who.to_le_bytes());
    v
}

pub(crate) async fn run_access_control_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let mut ctx = SideCtx::open(worker, wasm_path, kind).await?;
    let self_id = ctx.contract.id().as_str().to_string();
    let admin = account_u64(&self_id);
    let bob = account_u64("bob.testnet");

    if ctx.is_pf() {
        ctx.call_raw("init", &[], "PF init").await?;
        ctx.view_raw_bool(
            "hasRole",
            &role_who_args(0, admin),
            "PF has admin",
            Some(true),
        )
        .await?;
        ctx.call_raw("grantRole", &role_who_args(1, bob), "PF grant minter bob")
            .await?;
        ctx.view_raw_bool(
            "hasRole",
            &role_who_args(1, bob),
            "PF has minter bob",
            Some(true),
        )
        .await?;
        ctx.call_raw("revokeRole", &role_who_args(1, bob), "PF revoke minter")
            .await?;
        ctx.view_raw_bool(
            "hasRole",
            &role_who_args(1, bob),
            "PF no minter bob",
            Some(false),
        )
        .await?;
    } else {
        ctx.call_json("init", json!({}), "sdk init").await?;
        ctx.view_json_bool(
            "has_role",
            json!({ "role": 0, "who": admin }),
            "sdk has admin",
            Some(true),
        )
        .await?;
        ctx.call_json(
            "grant_role",
            json!({ "role": 1, "who": bob }),
            "sdk grant minter bob",
        )
        .await?;
        ctx.view_json_bool(
            "has_role",
            json!({ "role": 1, "who": bob }),
            "sdk has minter bob",
            Some(true),
        )
        .await?;
        ctx.call_json(
            "revoke_role",
            json!({ "role": 1, "who": bob }),
            "sdk revoke minter",
        )
        .await?;
        ctx.view_json_bool(
            "has_role",
            json!({ "role": 1, "who": bob }),
            "sdk no minter bob",
            Some(false),
        )
        .await?;
    }
    ctx.finish().await
}
