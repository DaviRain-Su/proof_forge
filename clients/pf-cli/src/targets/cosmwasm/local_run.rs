//! `pf run -t cosmwasm -- <method> [u64…]` → one-shot cosmwasm-vm mock.
//!
//! Engineering only. Spawns `scripts/pf_cosmwasm_run.sh` → `cw_oneshot`.
//! Not wasmd / mainnet / formal. Sync call FC at compiler; schedule=SubMsg never.

use crate::compiler;
use crate::error::{PfError, PfResult};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug)]
pub struct LocalRunOutcome {
    pub stdout: String,
    pub stderr: String,
    pub script_path: PathBuf,
    pub skipped: bool,
}

fn script_if_file(path: PathBuf) -> Option<PathBuf> {
    path.is_file().then_some(path)
}

pub fn resolve_cosmwasm_run_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_COSMWASM_RUN_SCRIPT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_COSMWASM_RUN_SCRIPT set but not a file: {p}"
        )));
    }
    if let Some(root) = compiler::resolve_package_root() {
        if let Some(p) = script_if_file(root.join("scripts/pf_cosmwasm_run.sh")) {
            return Ok(p);
        }
    }
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        if let Some(p) = script_if_file(PathBuf::from(&root).join("scripts/pf_cosmwasm_run.sh")) {
            return Ok(p);
        }
    }
    let cwd = std::env::current_dir()?;
    if let Some(p) = script_if_file(cwd.join("scripts/pf_cosmwasm_run.sh")) {
        return Ok(p);
    }
    let mut dir = cwd;
    loop {
        if let Some(p) = script_if_file(dir.join("scripts/pf_cosmwasm_run.sh")) {
            return Ok(p);
        }
        if !dir.pop() {
            break;
        }
    }
    Err(PfError::Tool(
        "scripts/pf_cosmwasm_run.sh not found (install engineering bundle or monorepo)".into(),
    ))
}

/// Read export mode for `method` from `*.cosmwasm-abi.json` when present.
fn abi_export_mode(dir: &Path, method: &str) -> Option<&'static str> {
    use std::fs;
    let entries = fs::read_dir(dir).ok()?;
    let mut abi_path: Option<PathBuf> = None;
    for ent in entries.flatten() {
        let p = ent.path();
        let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if name.ends_with(".cosmwasm-abi.json") {
            abi_path = Some(p);
            break;
        }
    }
    let path = abi_path?;
    let text = fs::read_to_string(path).ok()?;
    let v: serde_json::Value = serde_json::from_str(&text).ok()?;
    let methods = v.get("methods")?.as_array()?;
    for m in methods {
        let name = m.get("name")?.as_str()?;
        if name != method {
            continue;
        }
        let mode = m.get("mode")?.as_str()?;
        return Some(match mode {
            "instantiate" | "init" => "instantiate",
            "query" | "view" => "query",
            _ => "execute",
        });
    }
    None
}

/// Parse `call_args` as `<method> [u64…]`.
pub fn run_local(artifact_dir: &Path, call_args: &[String]) -> PfResult<LocalRunOutcome> {
    if call_args.is_empty() {
        return Err(PfError::Usage(
            "cosmwasm: missing method after `--` (example: pf run -t cosmwasm -- get)".into(),
        ));
    }
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t cosmwasm` first)",
            artifact_dir.display()
        )));
    }
    if !artifact_dir.join("manifest.json").is_file() {
        return Err(PfError::Artifact(format!(
            "missing manifest.json under {}",
            artifact_dir.display()
        )));
    }

    let method = &call_args[0];
    let mut u64_args: Vec<String> = Vec::new();
    for a in &call_args[1..] {
        let cleaned = a
            .trim_end_matches("u64")
            .trim_end_matches('u')
            .trim()
            .to_string();
        cleaned
            .parse::<u64>()
            .map_err(|_| PfError::Usage(format!("cosmwasm run args must be u64 decimals, got {a}")))?;
        u64_args.push(cleaned);
    }

    let mode = abi_export_mode(artifact_dir, method).unwrap_or_else(|| {
        if method == "init" || method.starts_with("init") {
            "instantiate"
        } else if method.starts_with("get")
            || method.starts_with("view")
            || method.starts_with("query")
            || method.starts_with("native")
            || method.ends_with("Balance")
            || matches!(
                method.as_str(),
                "seconds"
                    | "height"
                    | "answer"
                    | "dump"
                    | "selfIsContract"
                    | "callerIsContract"
            )
        {
            "query"
        } else {
            "execute"
        }
    });

    let script = resolve_cosmwasm_run_script()?;
    let mut cmd = Command::new("bash");
    cmd.arg(&script)
        .env("PF_CW_ARTIFACT_DIR", artifact_dir)
        .env("PF_CW_METHOD", method)
        .env("PF_CW_MODE", mode)
        .env("PF_CW_ARGS", u64_args.join(" "))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Some(root) = compiler::resolve_package_root() {
        cmd.env("PROOF_FORGE_ROOT", root);
    }
    if let Ok(tr) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        cmd.env("PROOF_FORGE_TOOL_ROOT", tr);
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn pf_cosmwasm_run.sh failed: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    let skipped = stderr.contains("skipped:") || stdout.contains("skipped:");
    if !out.status.success() && !skipped {
        return Err(PfError::Tool(format!(
            "cosmwasm run failed (exit {:?})\n{stderr}{stdout}",
            out.status.code()
        )));
    }
    Ok(LocalRunOutcome {
        stdout,
        stderr,
        script_path: script,
        skipped,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn abi_export_mode_reads_query_and_execute() {
        let dir = std::env::temp_dir().join(format!(
            "pf-cw-abi-mode-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("Hello.cosmwasm-abi.json"),
            r#"{
              "methods": [
                {"name":"init","mode":"instantiate","args":[]},
                {"name":"get","mode":"query","args":[]},
                {"name":"increment","mode":"execute","args":[{"name":"delta"}]}
              ]
            }"#,
        )
        .unwrap();
        assert_eq!(abi_export_mode(&dir, "get"), Some("query"));
        assert_eq!(abi_export_mode(&dir, "increment"), Some("execute"));
        assert_eq!(abi_export_mode(&dir, "init"), Some("instantiate"));
        assert_eq!(abi_export_mode(&dir, "missing"), None);
        let _ = fs::remove_dir_all(&dir);
    }
}
