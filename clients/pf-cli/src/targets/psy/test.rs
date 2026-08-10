//! `pf test -t psy` — multi-step DPN session (shared state) + optional official CLI.

use super::abi;
use super::simulate;
use crate::error::{PfError, PfResult};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug)]
pub struct TestOutcome {
    pub skipped: bool,
    pub skip_reason: Option<String>,
    pub message: String,
    pub dpn_path: Option<PathBuf>,
    pub session: Option<Value>,
}

/// Resolve monorepo `scripts/psy_dpn_session.py`.
fn resolve_session_script() -> PfResult<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_PSY_SESSION") {
        let pb = PathBuf::from(p);
        if pb.is_file() {
            return Ok(pb);
        }
    }
    if let Some(root) = crate::compiler::resolve_package_root() {
        let cand = root.join("scripts/psy_dpn_session.py");
        if cand.is_file() {
            return Ok(cand);
        }
    }
    // Walk up from CWD for monorepo marker
    let mut cur = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    for _ in 0..8 {
        let cand = cur.join("scripts/psy_dpn_session.py");
        if cand.is_file() {
            return Ok(cand);
        }
        if !cur.pop() {
            break;
        }
    }
    Err(PfError::Tool(
        "scripts/psy_dpn_session.py not found (set PROOF_FORGE_ROOT or PROOF_FORGE_PSY_SESSION)"
            .into(),
    ))
}

pub fn run_official_simulate_smoke(dir: &Path) -> PfResult<TestOutcome> {
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t psy` first)",
            dir.display()
        )));
    }
    let dpn = simulate::find_dpn(dir)?;
    let _ = abi::derive_abi_path(dir);
    let script = match resolve_session_script() {
        Ok(s) => s,
        Err(e) => {
            return Ok(TestOutcome {
                skipped: true,
                skip_reason: Some(e.to_string()),
                message: "skipped multi-step session".into(),
                dpn_path: Some(dpn),
                session: None,
            });
        }
    };

    let out = Command::new("python3")
        .arg("-I")
        .arg("-S")
        .arg(&script)
        .arg("--dpn")
        .arg(&dpn)
        .arg("--json")
        .arg("--call")
        .arg("initialize:7")
        .arg("--call")
        .arg("increment:5")
        .arg("--call")
        .arg("get")
        .output()
        .map_err(|e| PfError::Tool(format!("spawn psy_dpn_session.py: {e}")))?;

    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "psy_dpn_session failed (exit {:?}):\n{stderr}\n{stdout}",
            out.status.code()
        )));
    }
    let session: Value = serde_json::from_str(stdout.trim()).map_err(|e| {
        PfError::Tool(format!("session JSON: {e}\nstdout={stdout}"))
    })?;

    // Expect 7+5=12 continuity
    let slots = session.get("slots").cloned().unwrap_or(Value::Null);
    let calls = session
        .get("calls")
        .and_then(|c| c.as_array())
        .cloned()
        .unwrap_or_default();
    let get_out = calls
        .last()
        .and_then(|c| c.get("outputs"))
        .and_then(|o| o.as_array())
        .and_then(|a| a.first())
        .and_then(|v| v.as_u64());
    if get_out != Some(12) {
        return Err(PfError::Tool(format!(
            "session continuity failed: want get=12, got {get_out:?}, slots={slots}"
        )));
    }

    let mut msg = format!(
        "pf-psy-test: ok session init(7)+inc(5)+get=12 dpn={}",
        dpn.display()
    );
    if simulate::resolve_psy_user_cli().is_ok() {
        msg.push_str(" (+ psy_user_cli present for single-call simulate)");
    }

    Ok(TestOutcome {
        skipped: false,
        skip_reason: None,
        message: msg,
        dpn_path: Some(dpn),
        session: Some(session),
    })
}
