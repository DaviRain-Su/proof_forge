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
            "target '{target}' developer lane not implemented in pf v0 (Aleo-first)"
        )));
    }
    Ok(())
}
