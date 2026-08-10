//! Per-chain developer adapters.

pub mod aleo;
pub mod evm;
pub mod solana;

use crate::error::{PfError, PfResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetId {
    Aleo,
    Evm,
    Solana,
    Other,
}

impl TargetId {
    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "aleo" => Self::Aleo,
            "evm" => Self::Evm,
            "solana" => Self::Solana,
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
        assert!(capability_note("near").contains("fail closed"));
    }
}
