//! Wrap official `psy_user_cli simulate --circuit-defs-path <*.dpn.json>`.

use crate::error::{PfError, PfResult};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone)]
pub struct SimulateOutcome {
    pub method: String,
    pub inputs: Vec<String>,
    pub raw_stdout: String,
    pub result: Value,
    pub psy_user_cli: PathBuf,
    pub dpn_path: PathBuf,
}

pub fn find_dpn(dir: &Path) -> PfResult<PathBuf> {
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t psy` first)",
            dir.display()
        )));
    }
    let mut matches = Vec::new();
    for ent in std::fs::read_dir(dir).map_err(|e| PfError::Artifact(e.to_string()))? {
        let ent = ent.map_err(|e| PfError::Artifact(e.to_string()))?;
        let p = ent.path();
        if p.extension().and_then(|s| s.to_str()) == Some("json") {
            let name = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if name.ends_with(".dpn.json") {
                matches.push(p);
            }
        }
    }
    matches.sort();
    match matches.as_slice() {
        [] => Err(PfError::Artifact(format!(
            "no *.dpn.json under {} (pf build --target psy)",
            dir.display()
        ))),
        [one] => Ok(one.clone()),
        many => Err(PfError::Artifact(format!(
            "multiple *.dpn.json under {}: {:?}",
            dir.display(),
            many
        ))),
    }
}

pub fn resolve_psy_user_cli() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_PSY_USER_CLI") {
        let pb = PathBuf::from(p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_PSY_USER_CLI not a file: {}",
            pb.display()
        )));
    }
    let home = dirs_next_home();
    if let Some(h) = home {
        let candidate = h.join(".psy/bin/psy_user_cli");
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    which("psy_user_cli").ok_or_else(|| {
        PfError::Tool(
            "psy_user_cli not found — install via psyup (https://github.com/QEDProtocol/psyup) \
             or set PROOF_FORGE_PSY_USER_CLI"
                .into(),
        )
    })
}

fn dirs_next_home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

fn which(bin: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        let p = dir.join(bin);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

/// Extract first top-level JSON object from mixed log+JSON stdout.
pub fn extract_json_object(raw: &str) -> PfResult<Value> {
    let i = raw
        .find('{')
        .ok_or_else(|| PfError::Tool("psy_user_cli simulate: no JSON object in output".into()))?;
    let j = raw
        .rfind('}')
        .ok_or_else(|| PfError::Tool("psy_user_cli simulate: truncated JSON".into()))?;
    if j <= i {
        return Err(PfError::Tool("psy_user_cli simulate: bad JSON span".into()));
    }
    serde_json::from_str(&raw[i..=j])
        .map_err(|e| PfError::Tool(format!("psy_user_cli simulate JSON parse: {e}")))
}

pub fn simulate(dir: &Path, method: &str, inputs: &[String]) -> PfResult<SimulateOutcome> {
    let dpn = find_dpn(dir)?;
    let cli = resolve_psy_user_cli()?;
    let mut cmd = Command::new(&cli);
    cmd.arg("simulate")
        .arg("--circuit-defs-path")
        .arg(&dpn)
        .arg("--method")
        .arg(method)
        .arg("--format")
        .arg("json");
    if !inputs.is_empty() {
        cmd.arg("--inputs");
        for i in inputs {
            // Accept bare decimals; strip optional trailing u64/felt noise.
            let cleaned = i
                .trim()
                .trim_end_matches("u64")
                .trim_end_matches("felt")
                .trim()
                .to_string();
            cmd.arg(cleaned);
        }
    }
    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn psy_user_cli: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    let combined = if stderr.is_empty() {
        stdout.clone()
    } else {
        format!("{stdout}\n{stderr}")
    };
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "psy_user_cli simulate failed (exit {:?}):\n{combined}",
            out.status.code()
        )));
    }
    let result = extract_json_object(&combined)?;
    if result.get("success").and_then(|v| v.as_bool()) != Some(true) {
        return Err(PfError::Tool(format!(
            "simulate success=false: {}",
            result
                .get("failure")
                .map(|v| v.to_string())
                .unwrap_or_else(|| result.to_string())
        )));
    }
    Ok(SimulateOutcome {
        method: method.into(),
        inputs: inputs.to_vec(),
        raw_stdout: combined,
        result,
        psy_user_cli: cli,
        dpn_path: dpn,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_json_skips_tracing_prefix() {
        let raw = r#"2026-08-10T INFO foo
{"success": true, "outputs": [5]}
"#;
        let v = extract_json_object(raw).unwrap();
        assert_eq!(v["success"], true);
        assert_eq!(v["outputs"][0], 5);
    }
}
