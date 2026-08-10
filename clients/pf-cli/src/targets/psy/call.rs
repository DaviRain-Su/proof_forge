//! Wrap official `psy_user_cli call` for on-chain method invocation.

use super::deploy::{
    load_deployment_meta, resolve_rpc_config, services_base_url, DeployMeta,
};
use super::simulate::resolve_psy_user_cli;
use crate::error::{PfError, PfResult};
use crate::safety::{self, NetworkKind};
use serde_json::json;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug)]
pub struct CallOutcome {
    pub network: String,
    pub contract_id: u64,
    pub method: String,
    pub inputs: Vec<String>,
    pub stdout_tail: String,
    pub saved: Vec<PathBuf>,
}

pub struct CallRequest<'a> {
    pub artifact_dir: &'a Path,
    pub network: NetworkKind,
    pub rpc_config: Option<&'a Path>,
    pub private_key_env: Option<&'a str>,
    pub contract_id: Option<u64>,
    pub method: &'a str,
    pub inputs: &'a [String],
    pub wait: bool,
    pub save_dir: &'a Path,
}

fn resolve_contract_id(artifact_dir: &Path, explicit: Option<u64>) -> PfResult<u64> {
    if let Some(id) = explicit {
        return Ok(id);
    }
    if let Ok(v) = std::env::var("PF_PSY_CONTRACT_ID") {
        if let Ok(id) = v.trim().parse::<u64>() {
            return Ok(id);
        }
    }
    if let Some(meta) = load_deployment_meta(artifact_dir)? {
        if let Some(id) = meta.contract_id {
            return Ok(id);
        }
        return Err(PfError::Usage(format!(
            "deployment meta has uuid {:?} but no contract_id yet — re-run deploy --broadcast or pass --contract-id",
            meta.contract_uuid
        )));
    }
    Err(PfError::Usage(
        "psy call needs --contract-id N, or PF_PSY_CONTRACT_ID, or tx/deployment.json from pf deploy --broadcast"
            .into(),
    ))
}

pub fn call(req: CallRequest<'_>) -> PfResult<CallOutcome> {
    safety::refuse_mainnet(req.network)?;
    let cli = resolve_psy_user_cli()?;
    let rpc = resolve_rpc_config(req.network, req.rpc_config)?;
    let contract_id = resolve_contract_id(req.artifact_dir, req.contract_id)?;
    let key = safety::resolve_private_key_for_mode(true, req.private_key_env)?;

    std::fs::create_dir_all(req.save_dir)?;

    let mut cmd = Command::new(&cli);
    cmd.arg("call")
        .arg("--rpc-config")
        .arg(&rpc)
        .arg("--private-key")
        .arg(&key)
        .arg("--contract-id")
        .arg(contract_id.to_string())
        .arg("--method-name")
        .arg(req.method);
    if !req.inputs.is_empty() {
        cmd.arg("--inputs");
        for i in req.inputs {
            let cleaned = i
                .trim()
                .trim_end_matches("u64")
                .trim_end_matches("felt")
                .trim();
            cmd.arg(cleaned);
        }
    }
    if req.wait {
        cmd.arg("--wait-until-confirmation");
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn psy_user_cli call: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    let combined = format!("{stdout}{stderr}");
    if !out.status.success() {
        return Err(PfError::Network(format!(
            "psy_user_cli call failed (exit {:?}):\n{combined}",
            out.status.code()
        )));
    }

    let log_path = req.save_dir.join(format!(
        "call-{}-{}.log",
        req.method,
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    ));
    std::fs::write(&log_path, &combined)?;

    let receipt = json!({
        "schema": "proof-forge.pf.psy-call.receipt.v1",
        "target": "psy",
        "network": req.network.as_str(),
        "contractId": contract_id,
        "method": req.method,
        "inputs": req.inputs,
        "rpcConfig": rpc.display().to_string(),
        "servicesBase": services_base_url(&rpc).ok().flatten(),
    });
    let receipt_path = req.save_dir.join("call.receipt.json");
    std::fs::write(
        &receipt_path,
        serde_json::to_string_pretty(&receipt).expect("json"),
    )?;

    let tail: String = combined
        .chars()
        .rev()
        .take(1200)
        .collect::<String>()
        .chars()
        .rev()
        .collect();

    Ok(CallOutcome {
        network: req.network.as_str().into(),
        contract_id,
        method: req.method.into(),
        inputs: req.inputs.to_vec(),
        stdout_tail: tail,
        saved: vec![log_path, receipt_path],
    })
}

/// Re-export meta type for callers.
pub type Meta = DeployMeta;
