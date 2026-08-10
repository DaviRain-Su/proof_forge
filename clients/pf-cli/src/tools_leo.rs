//! Resolve host-optional Leo binary (never PATH-install into Tool Root).

use crate::error::{PfError, PfResult};
use std::path::PathBuf;
use std::process::Command;

pub fn resolve_leo() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_ALEO_LEO") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            return Ok(pb);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_ALEO_LEO set but not a file: {p}"
        )));
    }
    if let Ok(root) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        let cand = PathBuf::from(root).join("leo");
        if cand.is_file() {
            return Ok(cand);
        }
    }
    // Cache layout used by toolchain materialize.
    if let Some(home) = dirs_home() {
        let plat = platform_id();
        let cand = home
            .join(".cache")
            .join("proof-forge-v2")
            .join("tool-root")
            .join(plat)
            .join("leo");
        if cand.is_file() {
            return Ok(cand);
        }
        let cargo_leo = home.join(".cargo").join("bin").join("leo");
        if cargo_leo.is_file() {
            return Ok(cargo_leo);
        }
    }
    if let Ok(w) = which::which("leo") {
        return Ok(w);
    }
    Err(PfError::Tool(
        "leo not found (set PROOF_FORGE_ALEO_LEO or install Leo 4.0.x)".into(),
    ))
}

fn dirs_home() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

fn platform_id() -> String {
    let sys = std::env::consts::OS;
    let arch = std::env::consts::ARCH;
    // uname-style: darwin-arm64 / linux-x86_64
    let sys = match sys {
        "macos" => "darwin",
        other => other,
    };
    let arch = match arch {
        "aarch64" => "arm64",
        "x86_64" => "x86_64",
        other => other,
    };
    format!("{sys}-{arch}")
}

pub fn leo_version_line(leo: &std::path::Path) -> String {
    Command::new(leo)
        .arg("--version")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.lines().next().unwrap_or("").to_string())
        .unwrap_or_default()
}
