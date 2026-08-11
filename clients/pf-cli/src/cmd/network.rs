//! `pf network list|show|use` — catalog metadata (P1-4).

use crate::cmd::emit;
use crate::error::PfResult;
use crate::networks;
use crate::result_json::PfOk;
use serde_json::json;

pub fn list(family: Option<&str>, json: bool) -> PfResult<()> {
    let rows = networks::list_networks(family)?;
    let mut ok = PfOk::new("network-list");
    ok.extra = Some(json!({
        "schema": "proof-forge.pf.network-list.v1",
        "family": family,
        "count": rows.len(),
        "networks": rows,
        "notes": [
            "metadata only — does not enable public broadcast",
            "pf deploy --broadcast remains local-only for EVM/Solana in v0",
        ],
    }));
    emit(ok, json, || {
        println!("pf network list (schema proof-forge.network-catalog.v1)");
        if let Some(f) = family {
            println!("filter targetFamily={f}");
        }
        println!();
        println!(
            "{:<28} {:<8} {:<10} {:<16} {}",
            "ID", "FAMILY", "ENV", "POLICY", "CHAIN"
        );
        for n in &rows {
            let id = n.get("id").and_then(|x| x.as_str()).unwrap_or("?");
            let fam = n
                .get("targetFamily")
                .and_then(|x| x.as_str())
                .unwrap_or("?");
            let env = n.get("env").and_then(|x| x.as_str()).unwrap_or("?");
            let policy = n.get("policy").and_then(|x| x.as_str()).unwrap_or("?");
            let chain = n
                .get("chainId")
                .map(|c| c.to_string())
                .unwrap_or_else(|| "-".into());
            println!("{id:<28} {fam:<8} {env:<10} {policy:<16} {chain}");
        }
        println!();
        println!("show one:  pf network show <id>");
        println!("print env: pf network use <id>   # exports; does not broadcast");
    })
}

pub fn show(id: &str, json: bool) -> PfResult<()> {
    let n = networks::find_network(id)?;
    let mut ok = PfOk::new("network-show");
    ok.extra = Some(json!({
        "schema": "proof-forge.pf.network-show.v1",
        "network": n,
    }));
    emit(ok, json, || {
        println!("{}", serde_json::to_string_pretty(&n).unwrap_or_default());
        let policy = n.get("policy").and_then(|x| x.as_str()).unwrap_or("?");
        let bc = n
            .get("pfProductBroadcast")
            .and_then(|x| x.as_str())
            .unwrap_or("?");
        println!();
        println!("policy={policy}  pfProductBroadcast={bc}");
        println!("note: catalog never grants keys or default public broadcast");
    })
}

/// Print shell exports for RPC / chain id (operator still decides deploy).
pub fn use_network(id: &str, json: bool) -> PfResult<()> {
    let n = networks::find_network(id)?;
    let rpc = networks::primary_rpc(&n);
    let chain = n.get("chainId").cloned();
    let coarse = networks::coarse_network_kind(&n);
    let policy = n
        .get("policy")
        .and_then(|x| x.as_str())
        .unwrap_or("unknown")
        .to_string();
    let broadcast = n
        .get("pfProductBroadcast")
        .and_then(|x| x.as_str())
        .unwrap_or("unknown")
        .to_string();

    let mut ok = PfOk::new("network-use");
    ok.extra = Some(json!({
        "schema": "proof-forge.pf.network-use.v1",
        "id": id,
        "rpcUrl": rpc,
        "chainId": chain,
        "coarseNetwork": coarse,
        "policy": policy,
        "pfProductBroadcast": broadcast,
        "notes": [
            "prints env suggestions only",
            "EVM/Solana --broadcast still local-only in pf v0",
            "never puts private keys in the environment from this command",
        ],
    }));
    emit(ok, json, || {
        println!("# pf network use {id}");
        println!("export PF_NETWORK_ID={id}");
        if let Some(rpc) = &rpc {
            println!("export PF_RPC_URL={rpc}");
            println!("export VITE_RPC_URL={rpc}");
        }
        if let Some(c) = &chain {
            println!("export PF_CHAIN_ID={c}");
            println!("export VITE_CHAIN_ID={c}");
        }
        println!("export VITE_NETWORK_ID={id}");
        if let Some(cn) = coarse {
            println!("# coarse pf --network kind (not always enough for catalog id): {cn}");
        }
        println!("# policy={policy} broadcast={broadcast}");
        println!("# deploy: pf deploy -t evm   # save-only");
        println!("# local broadcast only: pf deploy -t evm --broadcast --network local");
        if policy == "testnet-opt-in" {
            println!(
                "# public testnet: attach wallet UI or engineering scripts; pf v0 refuses public --broadcast"
            );
        }
    })
}
