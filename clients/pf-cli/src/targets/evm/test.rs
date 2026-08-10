//! Local EVM Anvil smoke for `pf test -t evm` (standalone-capable).
//!
//! Prefers the package-owned script shipped in the engineering **bundle**
//! (`scripts/pf_evm_test.sh` next to `proof-forge-next`). Monorepo checkout is
//! optional fallback only — not required for external authors (ADR-0039 / P1-1).

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
    if let Ok(p) = std::env::var("FOUNDRY_BIN") {
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

/// Resolve `scripts/pf_evm_test.sh` without requiring a monorepo checkout.
///
/// Order:
/// 1. `PROOF_FORGE_EVM_TEST_SCRIPT`
/// 2. package root next to compiler / `PROOF_FORGE_ROOT` (bundle layout)
/// 3. sibling of `proof-forge-next` → `../scripts/pf_evm_test.sh`
/// 4. cwd / parent walk (contributor monorepo)
pub fn resolve_evm_test_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_EVM_TEST_SCRIPT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_EVM_TEST_SCRIPT set but not a file: {p}"
        )));
    }

    // Bundle / install tree: package root has scripts/pf_evm_test.sh
    if let Some(root) = compiler::resolve_package_root() {
        if let Some(p) = script_if_file(root.join("scripts/pf_evm_test.sh")) {
            return Ok(p);
        }
    }

    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        if let Some(p) = script_if_file(PathBuf::from(&root).join("scripts/pf_evm_test.sh")) {
            return Ok(p);
        }
    }

    // Sibling of compiler binary: …/bin/proof-forge-next → …/scripts/
    if let Ok(cli) = compiler::resolve_compiler() {
        if let Some(bin_dir) = cli.parent() {
            if let Some(pkg) = bin_dir.parent() {
                if let Some(p) = script_if_file(pkg.join("scripts/pf_evm_test.sh")) {
                    return Ok(p);
                }
            }
            // Also accept scripts/ next to bin/ (flat layouts)
            if let Some(p) = script_if_file(bin_dir.join("scripts/pf_evm_test.sh")) {
                return Ok(p);
            }
        }
    }

    let cwd = std::env::current_dir()?;
    if let Some(p) = script_if_file(cwd.join("scripts/pf_evm_test.sh")) {
        return Ok(p);
    }

    let mut dir = cwd;
    loop {
        if let Some(p) = script_if_file(dir.join("scripts/pf_evm_test.sh")) {
            return Ok(p);
        }
        if !dir.pop() {
            break;
        }
    }

    Err(PfError::Tool(
        "scripts/pf_evm_test.sh not found.\n\
         External authors: install the engineering **bundle** (pf + proof-forge-next + scripts/):\n\
           pf bootstrap --from proof-forge-bundle-*.tar.gz\n\
           export PROOF_FORGE_ROOT=$HOME/.local/proof-forge/current\n\
           pf -y setup --target evm   # materializes anvil+cast into Tool Root\n\
         Override: PROOF_FORGE_EVM_TEST_SCRIPT=/path/to/pf_evm_test.sh\n\
         Save-only without Anvil: pf deploy -t evm\n\
         See docs/product/14-external-author-mvp.md · ADR-0039"
            .into(),
    ))
}

pub fn run_anvil_test(artifact_dir: &Path) -> PfResult<TestOutcome> {
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t evm` first)",
            artifact_dir.display()
        )));
    }
    if !artifact_dir.join("manifest.json").is_file() {
        return Err(PfError::Artifact(format!(
            "missing manifest.json under {}",
            artifact_dir.display()
        )));
    }

    let has_bin = std::fs::read_dir(artifact_dir)
        .map_err(|e| PfError::Io(e.to_string()))?
        .filter_map(|e| e.ok())
        .any(|e| {
            e.path()
                .extension()
                .and_then(|x| x.to_str())
                .is_some_and(|x| x.eq_ignore_ascii_case("bin"))
        });
    if !has_bin {
        return Err(PfError::Artifact(format!(
            "no *.bin under {} (run `pf build -t evm` first)",
            artifact_dir.display()
        )));
    }

    let script = resolve_evm_test_script()?;
    let tool_root = default_tool_root();

    let mut cmd = Command::new("bash");
    cmd.arg(&script)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env("PF_EVM_ARTIFACT_DIR", artifact_dir)
        .env("PROOF_FORGE_TOOL_ROOT", &tool_root)
        .env("PROOF_FORGE_HOST_MODE", std::env::var("PROOF_FORGE_HOST_MODE").unwrap_or_else(|_| "dev".into()));
    if let Ok(fb) = std::env::var("FOUNDRY_BIN") {
        cmd.env("FOUNDRY_BIN", fb);
    }
    // Optional: only needed if the script grows monorepo-only legs.
    if let Some(root) = compiler::resolve_package_root() {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cmd.env("PROOF_FORGE_ROOT", root);
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn {}: {e}", script.display())))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    let combined = format!("{stderr}{stdout}");

    // Script skip-clean: exit 0 + "skipped:" marker.
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
            "evm anvil test failed (exit {:?})\n{stderr}{stdout}\n\
fix: pf -y setup --target evm   # ensure Tool Root has anvil+cast\n\
# or set PROOF_FORGE_TOOL_ROOT to a lock-materialized root",
            out.status.code()
        )));
    }

    if !combined.contains("pf-evm-test: ok") {
        return Err(PfError::Tool(format!(
            "evm anvil test produced no ok marker\n{stderr}{stdout}"
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
        let err = run_anvil_test(Path::new("/tmp/pf-evm-missing-xyz")).unwrap_err();
        match err {
            PfError::Artifact(msg) => assert!(msg.contains("artifact dir missing")),
            other => panic!("expected Artifact, got {other}"),
        }
    }

    #[test]
    fn missing_manifest_is_artifact_error() {
        let dir = tempfile::tempdir().unwrap();
        let err = run_anvil_test(dir.path()).unwrap_err();
        match err {
            PfError::Artifact(msg) => assert!(msg.contains("manifest.json")),
            other => panic!("expected Artifact, got {other}"),
        }
    }
}
