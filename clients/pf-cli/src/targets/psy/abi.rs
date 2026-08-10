//! Derive PF Psy ABI JSON from *.dpn.json (no dargo source required).

use super::simulate::find_dpn;
use crate::error::{PfError, PfResult};
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn derive_abi_path(artifact_dir: &Path) -> PfResult<PathBuf> {
    let dpn = find_dpn(artifact_dir)?;
    let stem = dpn
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("Program.dpn.json")
        .replace(".dpn.json", "")
        .replace(".json", "");
    let out = artifact_dir.join(format!("{stem}.abi.json"));
    // Prefer monorepo script
    if let Some(script) = resolve_abi_script() {
        let status = Command::new("python3")
            .args(["-I", "-S"])
            .arg(&script)
            .arg("--dpn")
            .arg(&dpn)
            .arg("-o")
            .arg(&out)
            .status()
            .map_err(|e| PfError::Tool(format!("spawn psy_dpn_to_abi.py: {e}")))?;
        if status.success() && out.is_file() {
            return Ok(out);
        }
    }
    // Inline fallback (same shape as script)
    let data: Value = serde_json::from_str(
        &fs::read_to_string(&dpn).map_err(|e| PfError::Artifact(e.to_string()))?,
    )
    .map_err(|e| PfError::Artifact(format!("dpn json: {e}")))?;
    let arr = data
        .as_array()
        .ok_or_else(|| PfError::Artifact("dpn not array".into()))?;
    let mut methods = Vec::new();
    for fnv in arr {
        let name = fnv.get("name").and_then(|x| x.as_str()).unwrap_or("unknown");
        let mid = fnv.get("method_id").and_then(|x| x.as_u64()).unwrap_or(0);
        let n_in = fnv
            .get("circuit_inputs")
            .and_then(|x| x.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        let n_out = fnv
            .get("circuit_outputs")
            .and_then(|x| x.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        let cmds = fnv
            .get("state_commands")
            .and_then(|x| x.as_array())
            .cloned()
            .unwrap_or_default();
        let is_view = !cmds.iter().any(|c| {
            c.get("type")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .starts_with("Set")
        });
        let mode = if name == "initialize" || name == "init" {
            "initialize"
        } else if is_view {
            "view"
        } else {
            "entry"
        };
        let params: Vec<Value> = (0..n_in)
            .map(|i| json!({"name": format!("arg{i}"), "type": "u64", "feltSize": 1}))
            .collect();
        let returns: Vec<Value> = (0..n_out)
            .map(|i| json!({"name": format!("ret{i}"), "type": "u64", "feltSize": 1}))
            .collect();
        methods.push(json!({
            "name": name,
            "methodId": mid,
            "mode": mode,
            "isView": is_view,
            "params": params,
            "returns": returns,
            "arity": {"inputs": n_in, "outputs": n_out},
        }));
    }
    let abi = json!({
        "schema": "proof-forge.psy.abi.v1",
        "program": stem,
        "target": "psy",
        "source": "derived-from-dpn",
        "methods": methods,
    });
    fs::write(&out, serde_json::to_string_pretty(&abi).expect("json") + "\n")?;
    Ok(out)
}

fn resolve_abi_script() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_PSY_ABI") {
        let pb = PathBuf::from(p);
        if pb.is_file() {
            return Some(pb);
        }
    }
    if let Some(root) = crate::compiler::resolve_package_root() {
        let c = root.join("scripts/psy_dpn_to_abi.py");
        if c.is_file() {
            return Some(c);
        }
    }
    let mut cur = std::env::current_dir().ok()?;
    for _ in 0..8 {
        let c = cur.join("scripts/psy_dpn_to_abi.py");
        if c.is_file() {
            return Some(c);
        }
        if !cur.pop() {
            break;
        }
    }
    None
}
