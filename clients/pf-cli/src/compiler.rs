//! Resolve and spawn `proof-forge-next`.

use crate::error::{PfError, PfResult};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

pub fn resolve_compiler() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_CLI") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Compiler(format!(
            "PROOF_FORGE_CLI is set but not a file: {p}"
        )));
    }

    // Sibling of current exe.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let cand = dir.join("proof-forge-next");
            if cand.is_file() {
                return Ok(cand);
            }
        }
    }

    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        let cand = PathBuf::from(&root)
            .join(".lake")
            .join("build")
            .join("bin")
            .join("proof-forge-next");
        if cand.is_file() {
            return Ok(cand);
        }
    }

    // CWD monorepo layout.
    let cwd = std::env::current_dir()?;
    let cand = cwd
        .join(".lake")
        .join("build")
        .join("bin")
        .join("proof-forge-next");
    if cand.is_file() {
        return Ok(cand);
    }

    Err(PfError::Compiler(
        "cannot resolve proof-forge-next (set PROOF_FORGE_CLI or build via lake)".into(),
    ))
}

pub fn resolve_package_root() -> Option<PathBuf> {
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        let p = PathBuf::from(root);
        if p.join("scripts").join("proof_forge_doctor.py").is_file() {
            return Some(p);
        }
    }
    let cwd = std::env::current_dir().ok()?;
    if cwd.join("scripts").join("proof_forge_doctor.py").is_file() {
        return Some(cwd);
    }
    None
}

pub fn run_compiler(args: &[&str], cwd: Option<&Path>) -> PfResult<Output> {
    let cli = resolve_compiler()?;
    let mut cmd = Command::new(&cli);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(c) = cwd {
        cmd.current_dir(c);
    }
    // Inherit tool root if set.
    if let Ok(tr) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        cmd.env("PROOF_FORGE_TOOL_ROOT", tr);
    }
    let out = cmd
        .output()
        .map_err(|e| PfError::Compiler(format!("failed to spawn {}: {e}", cli.display())))?;
    Ok(out)
}

pub fn run_compiler_checked(args: &[&str], cwd: Option<&Path>) -> PfResult<Output> {
    let out = run_compiler(args, cwd)?;
    if out.status.success() {
        return Ok(out);
    }
    let stderr = String::from_utf8_lossy(&out.stderr);
    let stdout = String::from_utf8_lossy(&out.stdout);
    Err(PfError::Compiler(format!(
        "proof-forge-next failed (exit {:?})\n{stderr}{stdout}",
        out.status.code()
    )))
}
