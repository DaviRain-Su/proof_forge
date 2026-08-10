//! Spawn `proof-forge-solana-client verify-artifacts` (offline OutputSet verify).

use crate::error::{PfError, PfResult};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug)]
pub struct VerifyOutcome {
    pub stdout: String,
    pub stderr: String,
    pub client_path: PathBuf,
    pub parsed: Option<serde_json::Value>,
}

/// Resolve offline Solana verifier binary.
pub fn resolve_solana_client() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_SOLANA_CLIENT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_SOLANA_CLIENT set but not a file: {p}"
        )));
    }

    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            for name in ["proof-forge-solana-client", "pf-solana-client"] {
                let cand = dir.join(name);
                if cand.is_file() {
                    return Ok(cand);
                }
            }
        }
    }

    // Monorepo layout: clients/solana-client/target/release|debug
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        for profile in ["release", "debug"] {
            let cand = PathBuf::from(&root)
                .join("clients/solana-client/target")
                .join(profile)
                .join("proof-forge-solana-client");
            if cand.is_file() {
                return Ok(cand);
            }
        }
    }

    let cwd = std::env::current_dir()?;
    for profile in ["release", "debug"] {
        let cand = cwd
            .join("clients/solana-client/target")
            .join(profile)
            .join("proof-forge-solana-client");
        if cand.is_file() {
            return Ok(cand);
        }
    }

    if let Ok(w) = which::which("proof-forge-solana-client") {
        return Ok(w);
    }

    Err(PfError::Tool(
        "proof-forge-solana-client not found.\n\
         `pf verify -t solana` spawns a separate offline verifier binary \
         (not shipped inside the crates.io `proof-forge-pf` package).\n\
         Fix one of:\n\
           • set PROOF_FORGE_SOLANA_CLIENT=/path/to/proof-forge-solana-client\n\
           • put proof-forge-solana-client next to the `pf` binary (Release bundle)\n\
           • monorepo: cargo build -p proof-forge-solana-client --release\n\
         See clients/pf-cli/ARCHITECTURE.md"
            .into(),
    ))
}

pub fn verify_artifacts(
    artifact_dir: &Path,
    program_adapter: Option<&str>,
) -> PfResult<VerifyOutcome> {
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

    let client = resolve_solana_client()?;
    let mut cmd = Command::new(&client);
    cmd.arg("verify-artifacts")
        .arg("--artifact-dir")
        .arg(artifact_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(adapter) = program_adapter {
        if !adapter.is_empty() {
            cmd.arg("--program-adapter").arg(adapter);
        }
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn {}: {e}", client.display())))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "solana verify-artifacts failed (exit {:?})\n{stderr}{stdout}",
            out.status.code()
        )));
    }

    let parsed: Option<serde_json::Value> = serde_json::from_str(&stdout).ok();
    if let Some(v) = &parsed {
        if v.get("ok").and_then(|x| x.as_bool()) == Some(false) {
            return Err(PfError::Tool(format!(
                "solana verify reported ok=false\n{stdout}"
            )));
        }
    }

    Ok(VerifyOutcome {
        stdout,
        stderr,
        client_path: client,
        parsed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::{Mutex, OnceLock};

    fn env_lock() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
            .lock()
            .unwrap_or_else(|e| e.into_inner())
    }

    #[test]
    fn missing_artifact_dir_is_artifact_error() {
        let err = verify_artifacts(Path::new("/tmp/pf-verify-missing-dir-xyz"), None).unwrap_err();
        match err {
            PfError::Artifact(msg) => assert!(msg.contains("artifact dir missing")),
            other => panic!("expected Artifact, got {other}"),
        }
    }

    #[test]
    fn missing_manifest_is_artifact_error() {
        let dir = tempfile::tempdir().unwrap();
        let err = verify_artifacts(dir.path(), None).unwrap_err();
        match err {
            PfError::Artifact(msg) => assert!(msg.contains("manifest.json")),
            other => panic!("expected Artifact, got {other}"),
        }
    }

    #[test]
    fn env_override_missing_file_is_tool_error() {
        let _guard = env_lock();
        let key = "PROOF_FORGE_SOLANA_CLIENT";
        let prev = std::env::var_os(key);
        std::env::set_var(key, "/nonexistent/proof-forge-solana-client");
        let err = resolve_solana_client().unwrap_err();
        match prev {
            Some(v) => std::env::set_var(key, v),
            None => std::env::remove_var(key),
        }
        match err {
            PfError::Tool(msg) => assert!(msg.contains("PROOF_FORGE_SOLANA_CLIENT")),
            other => panic!("expected Tool, got {other}"),
        }
    }

    #[test]
    fn env_override_file_is_resolved() {
        let _guard = env_lock();
        let dir = tempfile::tempdir().unwrap();
        let bin = dir.path().join("proof-forge-solana-client");
        fs::write(&bin, b"#!/bin/sh\nexit 0\n").unwrap();
        let mut perms = fs::metadata(&bin).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&bin, perms).unwrap();

        let key = "PROOF_FORGE_SOLANA_CLIENT";
        let prev = std::env::var_os(key);
        std::env::set_var(key, &bin);
        let resolved = resolve_solana_client().unwrap();
        match prev {
            Some(v) => std::env::set_var(key, v),
            None => std::env::remove_var(key),
        }
        assert_eq!(resolved, bin);
    }
}
