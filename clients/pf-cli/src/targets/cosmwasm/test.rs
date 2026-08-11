//! Spawn `scripts/pf_cosmwasm_test.sh` (cosmwasm-vm engineering corpus).

use crate::compiler;
use crate::error::{PfError, PfResult};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug)]
pub struct TestOutcome {
    pub stdout: String,
    pub stderr: String,
    pub script_path: PathBuf,
    pub skipped: bool,
    pub skip_reason: Option<String>,
}

fn script_if_file(path: PathBuf) -> Option<PathBuf> {
    path.is_file().then_some(path)
}

pub fn resolve_cosmwasm_test_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_COSMWASM_TEST_SCRIPT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_COSMWASM_TEST_SCRIPT set but not a file: {p}"
        )));
    }
    if let Some(root) = compiler::resolve_package_root() {
        if let Some(p) = script_if_file(root.join("scripts/pf_cosmwasm_test.sh")) {
            return Ok(p);
        }
    }
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        if let Some(p) = script_if_file(PathBuf::from(&root).join("scripts/pf_cosmwasm_test.sh")) {
            return Ok(p);
        }
    }
    let cwd = std::env::current_dir()?;
    if let Some(p) = script_if_file(cwd.join("scripts/pf_cosmwasm_test.sh")) {
        return Ok(p);
    }
    let mut dir = cwd;
    loop {
        if let Some(p) = script_if_file(dir.join("scripts/pf_cosmwasm_test.sh")) {
            return Ok(p);
        }
        if !dir.pop() {
            break;
        }
    }
    Err(PfError::Tool(
        "scripts/pf_cosmwasm_test.sh not found (install engineering bundle or monorepo)".into(),
    ))
}

pub fn run_mock_runtime_test(artifact_dir: &Path) -> PfResult<TestOutcome> {
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

    let script = resolve_cosmwasm_test_script()?;
    let mut cmd = Command::new("bash");
    cmd.arg(&script)
        .env("PF_COSMWASM_ARTIFACT_DIR", artifact_dir)
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

    let output = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn pf_cosmwasm_test.sh: {e}")))?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let combined = format!("{stdout}\n{stderr}");
    let skipped = output.status.success() && combined.contains("skipped:");
    let skip_reason = if skipped {
        combined
            .lines()
            .find(|l| l.contains("skipped:"))
            .map(|s| s.trim().to_string())
    } else {
        None
    };
    if !output.status.success() && !skipped {
        return Err(PfError::Tool(format!(
            "pf_cosmwasm_test.sh failed (exit {:?})\n{stderr}\n{stdout}",
            output.status.code()
        )));
    }
    Ok(TestOutcome {
        stdout,
        stderr,
        script_path: script,
        skipped,
        skip_reason,
    })
}
