//! Spawn `scripts/pf_near_test.sh` (near-sandbox engineering corpus).
//!
//! Script resolution is **bundle-first** (same order as EVM/Solana).
//! Full sandbox still needs monorepo `runtime-tests/near` + locked
//! `near-sandbox`/`wat2wasm`; without them the script **skip-cleans**.
//! Save-only packaging: `pf deploy -t near`. No public broadcast.

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

/// Resolve `scripts/pf_near_test.sh` without requiring a monorepo checkout.
pub fn resolve_near_test_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_NEAR_TEST_SCRIPT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_NEAR_TEST_SCRIPT set but not a file: {p}"
        )));
    }

    if let Some(root) = compiler::resolve_package_root() {
        if let Some(p) = script_if_file(root.join("scripts/pf_near_test.sh")) {
            return Ok(p);
        }
    }

    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        if let Some(p) = script_if_file(PathBuf::from(&root).join("scripts/pf_near_test.sh")) {
            return Ok(p);
        }
    }

    if let Ok(cli) = compiler::resolve_compiler() {
        if let Some(bin_dir) = cli.parent() {
            if let Some(pkg) = bin_dir.parent() {
                if let Some(p) = script_if_file(pkg.join("scripts/pf_near_test.sh")) {
                    return Ok(p);
                }
            }
            if let Some(p) = script_if_file(bin_dir.join("scripts/pf_near_test.sh")) {
                return Ok(p);
            }
        }
    }

    let cwd = std::env::current_dir()?;
    if let Some(p) = script_if_file(cwd.join("scripts/pf_near_test.sh")) {
        return Ok(p);
    }

    let mut dir = cwd;
    loop {
        if let Some(p) = script_if_file(dir.join("scripts/pf_near_test.sh")) {
            return Ok(p);
        }
        if !dir.pop() {
            break;
        }
    }

    Err(PfError::Tool(
        "scripts/pf_near_test.sh not found.\n\
         External authors: install the engineering **bundle** (includes scripts/).\n\
         Full near-sandbox needs monorepo runtime-tests/near + locked tools; without it\n\
         the script skip-cleans (not a pass). Save-only: pf deploy -t near.\n\
         Override: PROOF_FORGE_NEAR_TEST_SCRIPT=/path/to/pf_near_test.sh\n\
         See docs/product/near-agent-cheatsheet.md"
            .into(),
    ))
}

pub fn run_sandbox_test(artifact_dir: &Path) -> PfResult<TestOutcome> {
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t near` first)",
            artifact_dir.display()
        )));
    }
    if !artifact_dir.join("manifest.json").is_file() {
        return Err(PfError::Artifact(format!(
            "missing manifest.json under {}",
            artifact_dir.display()
        )));
    }

    let script = resolve_near_test_script()?;
    let tool_root = default_tool_root();

    let mut cmd = Command::new("bash");
    cmd.arg(&script)
        .env("PF_NEAR_ARTIFACT_DIR", artifact_dir)
        .env("PROOF_FORGE_TOOL_ROOT", &tool_root)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Some(root) = compiler::resolve_package_root() {
        cmd.env("PROOF_FORGE_ROOT", root);
    }

    let output = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn pf_near_test.sh: {e}")))?;

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let combined = format!("{stdout}\n{stderr}");

    let skipped = output.status.success()
        && (combined.contains("skipped:") || combined.contains("pf-near-test: skipped:"));
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
            "pf_near_test.sh failed (exit {:?})\n{stderr}\n{stdout}",
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
