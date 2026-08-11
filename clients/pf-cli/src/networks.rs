//! Network catalog (`proof-forge.network-catalog.v1`) for `pf network`.
//!
//! Metadata only — never enables public broadcast by itself (ADR-0039 D3).

use crate::error::{PfError, PfResult};
use serde_json::Value;
use std::path::PathBuf;

const EMBEDDED: &str = include_str!("../data/networks.v1.json");

/// Load catalog JSON: package root → monorepo docs → embedded copy.
pub fn load_catalog() -> PfResult<Value> {
    for cand in catalog_search_paths() {
        if cand.is_file() {
            let text = std::fs::read_to_string(&cand)
                .map_err(|e| PfError::Io(format!("read {}: {e}", cand.display())))?;
            let v: Value = serde_json::from_str(&text).map_err(|e| {
                PfError::Tool(format!("invalid network catalog {}: {e}", cand.display()))
            })?;
            validate_schema(&v)?;
            return Ok(v);
        }
    }
    let v: Value = serde_json::from_str(EMBEDDED)
        .map_err(|e| PfError::Tool(format!("embedded network catalog corrupt: {e}")))?;
    validate_schema(&v)?;
    Ok(v)
}

fn validate_schema(v: &Value) -> PfResult<()> {
    let schema = v.get("schema").and_then(|s| s.as_str()).unwrap_or("");
    if schema != "proof-forge.network-catalog.v1" {
        return Err(PfError::Tool(format!(
            "unsupported network catalog schema '{schema}' (want proof-forge.network-catalog.v1)"
        )));
    }
    if !v.get("networks").and_then(|n| n.as_array()).is_some() {
        return Err(PfError::Tool(
            "network catalog missing networks[] array".into(),
        ));
    }
    Ok(())
}

fn catalog_search_paths() -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Some(root) = crate::compiler::resolve_package_root() {
        out.push(root.join("docs/product/networks.v1.json"));
        out.push(root.join("networks.v1.json"));
        out.push(root.join("data/networks.v1.json"));
    }
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        let r = PathBuf::from(root);
        out.push(r.join("docs/product/networks.v1.json"));
        out.push(r.join("networks.v1.json"));
    }
    if let Ok(cwd) = std::env::current_dir() {
        out.push(cwd.join("docs/product/networks.v1.json"));
        let mut dir = cwd;
        for _ in 0..6 {
            out.push(dir.join("docs/product/networks.v1.json"));
            if !dir.pop() {
                break;
            }
        }
    }
    out
}

pub fn list_networks(family: Option<&str>) -> PfResult<Vec<Value>> {
    let cat = load_catalog()?;
    let arr = cat
        .get("networks")
        .and_then(|n| n.as_array())
        .cloned()
        .unwrap_or_default();
    let filtered: Vec<Value> = arr
        .into_iter()
        .filter(|n| {
            if let Some(f) = family {
                n.get("targetFamily")
                    .and_then(|x| x.as_str())
                    .is_some_and(|tf| tf.eq_ignore_ascii_case(f))
            } else {
                true
            }
        })
        .collect();
    Ok(filtered)
}

pub fn find_network(id: &str) -> PfResult<Value> {
    let list = list_networks(None)?;
    list.into_iter()
        .find(|n| n.get("id").and_then(|x| x.as_str()) == Some(id))
        .ok_or_else(|| {
            PfError::Usage(format!(
                "unknown network id '{id}'\n\
fix: pf network list\n\
# catalog: docs/product/networks.v1.json (schema proof-forge.network-catalog.v1)"
            ))
        })
}

/// Map catalog id → pf `--network` coarse kind when applicable.
pub fn coarse_network_kind(entry: &Value) -> Option<&'static str> {
    match entry.get("env").and_then(|e| e.as_str()) {
        Some("local") => Some("local"),
        Some("testnet") => Some("testnet"),
        Some("devnet") => Some("devnet"),
        Some("mainnet") => Some("mainnet"),
        _ => None,
    }
}

pub fn primary_rpc(entry: &Value) -> Option<String> {
    entry
        .get("rpcUrls")
        .and_then(|u| u.as_array())
        .and_then(|a| a.first())
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}
