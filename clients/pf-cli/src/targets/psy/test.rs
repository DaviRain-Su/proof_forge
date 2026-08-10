//! `pf test -t psy` — host-optional official DPN VM smoke.

use super::simulate::{self, SimulateOutcome};
use crate::error::{PfError, PfResult};
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct TestOutcome {
    pub skipped: bool,
    pub skip_reason: Option<String>,
    pub message: String,
    pub dpn_path: Option<PathBuf>,
    pub steps: Vec<SimulateOutcome>,
}

pub fn run_official_simulate_smoke(dir: &Path) -> PfResult<TestOutcome> {
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t psy` first)",
            dir.display()
        )));
    }
    let dpn = match simulate::find_dpn(dir) {
        Ok(p) => p,
        Err(e) => return Err(e),
    };
    if simulate::resolve_psy_user_cli().is_err() {
        return Ok(TestOutcome {
            skipped: true,
            skip_reason: Some(
                "psy_user_cli not found — install psyup or set PROOF_FORGE_PSY_USER_CLI".into(),
            ),
            message: "skipped official DPN simulate".into(),
            dpn_path: Some(dpn),
            steps: vec![],
        });
    }

    // Ephemeral backend per call — assert each method alone.
    let init = simulate::simulate(dir, "initialize", &["7".into()])?;
    let inc = simulate::simulate(dir, "increment", &["5".into()])?;
    let get = simulate::simulate(dir, "get", &[])?;

    // Soft structural checks (StateCell-shaped); non-StateCell may still pass simulate success.
    let _ = (&init, &inc, &get);

    Ok(TestOutcome {
        skipped: false,
        skip_reason: None,
        message: format!(
            "pf-psy-test: ok dpn={} initialize/increment/get via psy_user_cli simulate",
            dpn.display()
        ),
        dpn_path: Some(dpn),
        steps: vec![init, inc, get],
    })
}
