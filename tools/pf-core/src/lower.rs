//! Future `buildFromCore` pilot surface (not implemented).
//!
//! Dual-run observe can use Lean-produced artifacts today. A Rust lowerer must
//! remain optional, experimental, and off the product CLI default path (D-057).

use crate::ExportPackage;
use anyhow::{bail, Result};

/// Placeholder for target-specific lowered outputs (paths / bytes).
#[derive(Debug, Clone)]
pub struct LoweredArtifacts {
    pub target_id: String,
    pub notes: Vec<String>,
}

/// Experimental lowerer trait. No production implementation yet.
pub trait BuildFromCore {
    fn target_id(&self) -> &str;
    fn build_from_core(&self, package: &ExportPackage) -> Result<LoweredArtifacts>;
}

/// EVM pilot slot — explicitly not implemented.
#[derive(Debug, Default, Clone, Copy)]
pub struct EvmLowererPilot;

impl BuildFromCore for EvmLowererPilot {
    fn target_id(&self) -> &str {
        "evm"
    }

    fn build_from_core(&self, package: &ExportPackage) -> Result<LoweredArtifacts> {
        let ready = package.dual_run_readiness();
        if !ready.ready_for_dual_run_observe() {
            bail!(
                "package not dual-run observe ready:\n{}",
                ready.lines().join("\n")
            );
        }
        bail!(
            "EvmLowererPilot::build_from_core is not implemented \
             (module={}, target={}). Observe-only dual-run remains available; \
             product CLI default stays Lean.",
            package.module_name(),
            package.target_id()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    #[test]
    fn evm_pilot_refuses_with_clear_error() {
        let pkg = crate::ExportPackage::load(fixture("counter-evm")).unwrap();
        let err = EvmLowererPilot
            .build_from_core(&pkg)
            .unwrap_err()
            .to_string();
        assert!(err.contains("not implemented"), "{err}");
        assert!(err.contains("Counter"), "{err}");
    }
}
