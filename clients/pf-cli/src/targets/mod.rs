//! Per-chain developer adapters.

pub mod aleo;

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
            "build supported via proof-forge-next; local run not in pf v0 (use just evm-* / anvil scripts)"
        }
        TargetId::Solana => {
            "build supported; local verify via proof-forge-solana-client; deploy not in pf v0"
        }
        TargetId::Other => "unsupported developer operation in pf v0 (fail closed)",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capability_notes_are_target_specific() {
        assert!(capability_note("evm").contains("anvil scripts"));
        assert!(capability_note("solana").contains("proof-forge-solana-client"));
        assert!(capability_note("near").contains("fail closed"));
    }
}
