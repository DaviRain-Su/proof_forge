//! Spawn `scripts/pf_solana_test.sh` (focused TransferSol Mollusk lane).

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

fn default_tool_root() -> PathBuf {
    if let Ok(p) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    match std::env::consts::OS {
        "macos" => PathBuf::from(home).join(".cache/proof-forge-v2/tool-root/darwin-arm64"),
        "linux" => {
            let arch = std::env::consts::ARCH;
            PathBuf::from(home).join(format!(".cache/proof-forge-v2/tool-root/linux-{arch}"))
        }
        _ => PathBuf::from(home).join(".cache/proof-forge-v2/tool-root"),
    }
}

/// Resolve monorepo `scripts/pf_solana_test.sh`.
pub fn resolve_solana_test_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_SOLANA_TEST_SCRIPT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_SOLANA_TEST_SCRIPT set but not a file: {p}"
        )));
    }

    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        let cand = PathBuf::from(&root).join("scripts/pf_solana_test.sh");
        if cand.is_file() {
            return Ok(cand);
        }
    }

    let cwd = std::env::current_dir()?;
    let cand = cwd.join("scripts/pf_solana_test.sh");
    if cand.is_file() {
        return Ok(cand);
    }

    let mut dir = cwd;
    loop {
        let cand = dir.join("scripts/pf_solana_test.sh");
        if cand.is_file() {
            return Ok(cand);
        }
        if !dir.pop() {
            break;
        }
    }

    Err(PfError::Tool(
        "scripts/pf_solana_test.sh not found (set PROOF_FORGE_ROOT or run from monorepo)".into(),
    ))
}

pub fn run_mollusk_test(artifact_dir: &Path) -> PfResult<TestOutcome> {
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t solana` first)",
            artifact_dir.display()
        )));
    }
    if !artifact_dir.join("manifest.json").is_file() {
        return Err(PfError::Artifact(format!(
            "missing manifest.json under {}",
            artifact_dir.display()
        )));
    }

    let script = resolve_solana_test_script()?;
    let tool_root = default_tool_root();

    let mut cmd = Command::new("bash");
    cmd.arg(&script)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("PF_SOLANA_ARTIFACT_DIR", artifact_dir)
        .env("PROOF_FORGE_TOOL_ROOT", &tool_root);
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Some(root) = script
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.to_path_buf())
    {
        // scripts/ → monorepo root
        cmd.env("PROOF_FORGE_ROOT", root);
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn {}: {e}", script.display())))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    let combined = format!("{stderr}{stdout}");

    if out.status.success() && combined.to_ascii_lowercase().contains("skipped:") {
        let reason = combined
            .lines()
            .find(|l| l.to_ascii_lowercase().contains("skipped:"))
            .unwrap_or("skipped")
            .to_string();
        return Ok(TestOutcome {
            stdout,
            stderr,
            script_path: script,
            skipped: true,
            skip_reason: Some(reason),
        });
    }

    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "solana mollusk test failed (exit {:?})\n{stderr}{stdout}",
            out.status.code()
        )));
    }

    if !combined.contains("pf-solana-test: ok") {
        return Err(PfError::Tool(format!(
            "solana mollusk test produced no ok marker\n{stderr}{stdout}"
        )));
    }

    Ok(TestOutcome {
        stdout,
        stderr,
        script_path: script,
        skipped: false,
        skip_reason: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_artifact_dir_is_artifact_error() {
        let err = run_mollusk_test(Path::new("/tmp/pf-solana-missing-xyz")).unwrap_err();
        match err {
            PfError::Artifact(msg) => assert!(msg.contains("artifact dir missing")),
            other => panic!("expected Artifact, got {other}"),
        }
    }

    #[test]
    fn missing_manifest_is_artifact_error() {
        let dir = tempfile::tempdir().unwrap();
        let err = run_mollusk_test(dir.path()).unwrap_err();
        match err {
            PfError::Artifact(msg) => assert!(msg.contains("manifest.json")),
            other => panic!("expected Artifact, got {other}"),
        }
    }
}
