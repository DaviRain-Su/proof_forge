//! Per-chain developer adapters.

pub mod aleo;
pub mod cosmwasm;
pub mod evm;
pub mod near;
pub mod psy;
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
    Other,
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
            _ => Self::Other,
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
            "build + `pf test` (Anvil) + `pf deploy` (save-only; --broadcast local only)"
        }
        TargetId::Solana => {
            "build + `pf test` (Mollusk) + `pf verify` + `pf deploy` (save-only; --broadcast local only)"
        }
        TargetId::Psy => {
            "build DPN + `pf test` (session) + `pf run` (simulate) + `pf deploy` wraps psy_user_cli deploy-contract"
        }
        TargetId::Near => {
            "build Wasm + `pf test` (near-sandbox; artifact fast-path or corpus) + `pf run` (one-shot sandbox) + `pf deploy` (save-only; --broadcast refused) + `pf scaffold-ui --template near-dapp`"
        }
        TargetId::Cosmwasm => {
            "build Wasm + `pf test` (cosmwasm-vm mock; artifact fast-path or corpus) + `pf deploy` (save-only; --broadcast refused) + `pf scaffold-ui --template cosmwasm-dapp` (no interactive pf run in v0)"
        }
        TargetId::Ton => {
            "build Tolk/BoC + `pf test` (@ton/sandbox corpus; skip-clean if tools missing); deploy/broadcast not product"
        }
        TargetId::Other => "unsupported developer operation in pf v0 (fail closed)",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capability_notes_are_target_specific() {
        assert!(capability_note("evm").contains("pf test"));
        assert!(capability_note("solana").contains("pf verify"));
        assert!(capability_note("psy").contains("psy_user_cli"));
        assert!(capability_note("near").contains("save-only"));
        assert!(capability_note("near").contains("broadcast refused"));
        assert!(capability_note("near").contains("pf test"));
        assert!(capability_note("near").contains("pf run"));
        assert!(capability_note("near").contains("near-dapp"));
        assert!(capability_note("cosmwasm").contains("pf test"));
        assert!(capability_note("cosmwasm").contains("cosmwasm-dapp"));
        assert!(capability_note("ton").contains("pf test"));
    }
}
