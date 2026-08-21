//! Per-chain developer adapters.

pub mod aleo;
pub mod cosmwasm;
pub mod evm;
pub mod near;
pub mod noir;
pub mod psy;
pub mod quint;
pub mod solana;
pub mod ton;

use crate::error::{PfError, PfResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetId {
    Aleo,
    Evm,
    Solana,
    Psy,
    Near,
    Cosmwasm,
    Ton,
    Noir,
    Quint,
    Soroban,
    Icp,
    OpenVm,
    Xrpl,
    Unknown,
}

impl TargetId {
    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "aleo" => Self::Aleo,
            "evm" => Self::Evm,
            "solana" => Self::Solana,
            "psy" => Self::Psy,
            "near" => Self::Near,
            "cosmwasm" | "cw" => Self::Cosmwasm,
            "ton" => Self::Ton,
            "noir" => Self::Noir,
            "quint" => Self::Quint,
            "soroban" => Self::Soroban,
            "icp" => Self::Icp,
            "openvm" => Self::OpenVm,
            "xrpl" => Self::Xrpl,
            _ => Self::Unknown,
        }
    }
}

pub fn require_aleo(target: &str) -> PfResult<()> {
    if TargetId::parse(target) != TargetId::Aleo {
        return Err(PfError::NotImplemented(format!(
            "target '{target}': {}",
            capability_note(target)
        )));
    }
    Ok(())
}

pub fn capability_note(target: &str) -> &'static str {
    match TargetId::parse(target) {
        TargetId::Aleo => "build, local run, deploy, and execute supported",
        TargetId::Evm => {
            "build + `pf test` (Anvil) + `pf run` (one-shot Anvil) + `pf deploy` (save-only; --broadcast local only)"
        }
        TargetId::Solana => {
            "build + `pf test` (Mollusk) + `pf run` (one-shot Mollusk, body-only) + `pf verify` + `pf deploy` (save-only; --broadcast local only)"
        }
        TargetId::Psy => {
            "build DPN + `pf test` (session) + `pf run` (simulate) + `pf deploy` wraps psy_user_cli deploy-contract"
        }
        TargetId::Near => {
            "build Wasm + `pf test` (near-sandbox; artifact fast-path or corpus) + `pf run` (one-shot sandbox) + `pf deploy` (save-only; --broadcast refused) + `pf scaffold-ui --template near-dapp`"
        }
        TargetId::Cosmwasm => {
            "build Wasm + `pf test` (cosmwasm-vm mock; artifact fast-path or corpus) + `pf run` (one-shot cosmwasm-vm mock) + `pf deploy` (save-only; --broadcast refused) + `pf scaffold-ui --template cosmwasm-dapp`"
        }
        TargetId::Ton => {
            "build Tolk/BoC + `pf test` (@ton/sandbox corpus) + `pf run` (one-shot sandbox) + `pf deploy` (save-only; --broadcast refused)"
        }
        TargetId::Noir => {
            "build Noir relations/ACIR + `pf test` (artifact smoke; no nargo re-run) + `pf deploy` (save-only circuit package; --broadcast refused)"
        }
        TargetId::Quint => {
            "build source-only `.qnt` + `pf test` (artifact smoke; no Quint CLI) + `pf deploy` (save-only model package; --broadcast refused; ADR-0026)"
        }
        TargetId::Icp => {
            "compiler build + `proof-forge-next local --target icp` runtime entry point; `pf test` adapter not implemented"
        }
        TargetId::Soroban => {
            "compiler build supported; no compiler local runtime entry point and no `pf test` adapter"
        }
        TargetId::OpenVm => {
            "compiler build supported; no compiler local runtime entry point and no `pf test` adapter"
        }
        TargetId::Xrpl => {
            "compiler build supported; no compiler local runtime entry point and no `pf test` adapter"
        }
        TargetId::Unknown => "unknown target; unsupported developer operation in pf v0 (fail closed)",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capability_notes_are_target_specific() {
        assert!(capability_note("evm").contains("pf test"));
        assert!(capability_note("evm").contains("pf run"));
        assert!(capability_note("solana").contains("pf verify"));
        assert!(capability_note("solana").contains("pf run"));
        assert!(capability_note("psy").contains("psy_user_cli"));
        assert!(capability_note("near").contains("save-only"));
        assert!(capability_note("near").contains("broadcast refused"));
        assert!(capability_note("near").contains("pf test"));
        assert!(capability_note("near").contains("pf run"));
        assert!(capability_note("near").contains("near-dapp"));
        assert!(capability_note("cosmwasm").contains("pf test"));
        assert!(capability_note("cosmwasm").contains("cosmwasm-dapp"));
        assert!(capability_note("ton").contains("pf test"));
        assert!(capability_note("ton").contains("pf run"));
        assert!(capability_note("ton").contains("save-only"));
        assert!(capability_note("noir").contains("pf test"));
        assert!(capability_note("noir").contains("broadcast refused"));
        assert!(capability_note("quint").contains("pf test"));
        assert!(capability_note("quint").contains("ADR-0026"));
        assert!(capability_note("icp").contains("compiler build"));
        assert!(capability_note("icp").contains("pf test` adapter not implemented"));
        assert!(capability_note("soroban").contains("no compiler local runtime"));
        assert!(capability_note("openvm").contains("no `pf test` adapter"));
        assert!(capability_note("xrpl").contains("no `pf test` adapter"));
    }

    #[test]
    fn all_engineering_registry_targets_are_classified() {
        for target in [
            "aleo", "cosmwasm", "evm", "icp", "near", "noir", "openvm", "psy", "quint",
            "solana", "soroban", "ton", "xrpl",
        ] {
            assert_ne!(TargetId::parse(target), TargetId::Unknown, "{target}");
        }
        assert_eq!(TargetId::parse("not-a-target"), TargetId::Unknown);
    }
}
