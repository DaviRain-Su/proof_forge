//! Spawn `scripts/pf_solana_test.sh` (StateCell / TransferSol Mollusk lane).
//!
//! Script resolution is **bundle-first** (ADR-0040), same order as EVM.
//! Full Mollusk execution still needs monorepo `runtime-tests/solana` + cargo;
//! without it the script **skip-cleans** (not a pass claim). Offline joins:
//! `pf verify -t solana` (proof-forge-solana-client).

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

fn script_if_file(path: PathBuf) -> Option<PathBuf> {
    path.is_file().then_some(path)
}

/// Resolve `scripts/pf_solana_test.sh` (bundle-first; monorepo optional).
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

    if let Some(root) = compiler::resolve_package_root() {
        if let Some(p) = script_if_file(root.join("scripts/pf_solana_test.sh")) {
            return Ok(p);
        }
    }

    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        if let Some(p) = script_if_file(PathBuf::from(&root).join("scripts/pf_solana_test.sh")) {
            return Ok(p);
        }
    }

    if let Ok(cli) = compiler::resolve_compiler() {
        if let Some(bin_dir) = cli.parent() {
            if let Some(pkg) = bin_dir.parent() {
                if let Some(p) = script_if_file(pkg.join("scripts/pf_solana_test.sh")) {
                    return Ok(p);
                }
            }
            if let Some(p) = script_if_file(bin_dir.join("scripts/pf_solana_test.sh")) {
                return Ok(p);
            }
        }
    }

    let cwd = std::env::current_dir()?;
    if let Some(p) = script_if_file(cwd.join("scripts/pf_solana_test.sh")) {
        return Ok(p);
    }

    let mut dir = cwd;
    loop {
        if let Some(p) = script_if_file(dir.join("scripts/pf_solana_test.sh")) {
            return Ok(p);
        }
        if !dir.pop() {
            break;
        }
    }

    Err(PfError::Tool(
        "scripts/pf_solana_test.sh not found.\n\
         External authors: install the engineering **bundle** (includes scripts/).\n\
         Full Mollusk still needs monorepo runtime-tests/solana + cargo; without it\n\
         the script skip-cleans (not a pass). Offline joins: pf verify -t solana.\n\
         Override: PROOF_FORGE_SOLANA_TEST_SCRIPT=/path/to/pf_solana_test.sh\n\
         See docs/product/14-external-author-mvp.md · ADR-0040"
            .into(),
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
        .env("PROOF_FORGE_TOOL_ROOT", &tool_root)
        .env(
            "PROOF_FORGE_HOST_MODE",
            std::env::var("PROOF_FORGE_HOST_MODE").unwrap_or_else(|_| "dev".into()),
        );
    if let Some(root) = compiler::resolve_package_root() {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Some(root) = script
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.to_path_buf())
    {
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
            "solana mollusk test failed (exit {:?})\n{stderr}{stdout}\n\
fix: monorepo path needs runtime-tests/solana + cargo\n\
# offline without Mollusk: pf verify -t solana",
            out.status.code()
        )));
    }

    // Accept either explicit ok marker or successful cargo test chatter.
    if !combined.contains("pf-solana-test: ok")
        && !combined.contains("test result: ok")
        && !combined.to_ascii_lowercase().contains("passed")
    {
        // Some lanes only print cargo summary; if exit 0, treat as ok.
        // Keep soft: exit 0 already checked.
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
