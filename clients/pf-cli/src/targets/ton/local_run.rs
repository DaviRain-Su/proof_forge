//! `pf run -t ton -- <method> [u64…]` → one-shot @ton/sandbox.
//!
//! Engineering only. Spawns `scripts/pf_ton_run.sh` → oneshot.mjs.
//! Not mainnet / formal. Sync call FC at compiler.

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

pub fn resolve_ton_run_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_TON_RUN_SCRIPT") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_TON_RUN_SCRIPT set but not a file: {p}"
        )));
    }
    if let Some(root) = compiler::resolve_package_root() {
        if let Some(p) = script_if_file(root.join("scripts/pf_ton_run.sh")) {
            return Ok(p);
        }
    }
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        if let Some(p) = script_if_file(PathBuf::from(&root).join("scripts/pf_ton_run.sh")) {
            return Ok(p);
        }
    }
    let cwd = std::env::current_dir()?;
    if let Some(p) = script_if_file(cwd.join("scripts/pf_ton_run.sh")) {
        return Ok(p);
    }
    let mut dir = cwd;
    loop {
        if let Some(p) = script_if_file(dir.join("scripts/pf_ton_run.sh")) {
            return Ok(p);
        }
        if !dir.pop() {
            break;
        }
    }
    Err(PfError::Tool(
        "scripts/pf_ton_run.sh not found (install engineering bundle or monorepo)".into(),
    ))
}

pub fn run_local(artifact_dir: &Path, call_args: &[String]) -> PfResult<LocalRunOutcome> {
    if call_args.is_empty() {
        return Err(PfError::Usage(
            "ton: missing method after `--` (example: pf run -t ton -- get)".into(),
        ));
    }
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t ton` first)",
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
            .map_err(|_| PfError::Usage(format!("ton run args must be u64 decimals, got {a}")))?;
        u64_args.push(cleaned);
    }

    let script = resolve_ton_run_script()?;
    let mut cmd = Command::new("bash");
    cmd.arg(&script)
        .env("PF_TON_ARTIFACT_DIR", artifact_dir)
        .env("PF_TON_METHOD", method)
        .env("PF_TON_ARGS", u64_args.join(" "))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cmd.env("PROOF_FORGE_ROOT", root);
    } else if let Some(root) = compiler::resolve_package_root() {
        cmd.env("PROOF_FORGE_ROOT", root);
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn pf_ton_run.sh failed: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    let skipped = stderr.contains("skipped:") || stdout.contains("skipped:");
    if !out.status.success() && !skipped {
        return Err(PfError::Tool(format!(
            "ton run failed (exit {:?})\n{stderr}{stdout}",
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
