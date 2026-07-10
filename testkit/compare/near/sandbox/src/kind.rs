//! Contract kind identity for dual-deploy dispatch.

use anyhow::{bail, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ContractKind {
    Counter,
    ValueVault,
    FungibleToken,
    Ownable,
    StakingVault,
    RoleGatedToken,
    FeeToken,
    RemoteCall,
    StatusMessage,
    GuestBook,
    StorageDeposit,
    Pausable,
    ReentrancyGuard,
    OwnablePausable,
    ArrayExample,
    OwnableHash,
    HostEnvProbe,
}

impl ContractKind {
    pub(crate) fn parse(s: &str) -> Result<Self> {
        match s {
            "counter" => Ok(Self::Counter),
            "value-vault" | "valuevault" | "value_vault" => Ok(Self::ValueVault),
            "fungible-token" | "ft" | "fungible_token" => Ok(Self::FungibleToken),
            "ownable" => Ok(Self::Ownable),
            "staking-vault" | "stakingvault" | "staking_vault" => Ok(Self::StakingVault),
            "role-gated-token" | "rolegatedtoken" | "rgt" => Ok(Self::RoleGatedToken),
            "fee-token" | "feetoken" => Ok(Self::FeeToken),
            "remote-call" | "remotecall" | "crosscall" => Ok(Self::RemoteCall),
            "status-message" | "statusmessage" | "status" => Ok(Self::StatusMessage),
            "guestbook" | "guest-book" => Ok(Self::GuestBook),
            "storage-deposit" | "storagedeposit" | "nep145" => Ok(Self::StorageDeposit),
            "pausable" | "pause" => Ok(Self::Pausable),
            "reentrancy-guard" | "reentrancyguard" | "reentrancy" | "rg" => Ok(Self::ReentrancyGuard),
            "ownable-pausable" | "ownablepausable" | "ownable_pausable" => Ok(Self::OwnablePausable),
            "array-example" | "arrayexample" | "array" => Ok(Self::ArrayExample),
            "ownable-hash" | "ownablehash" | "ownable_hash" => Ok(Self::OwnableHash),
            "host-env-probe" | "hostenvprobe" | "hostenv" => Ok(Self::HostEnvProbe),
            other => bail!("unknown --contract `{other}`"),
        }
    }

    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Counter => "counter",
            Self::ValueVault => "value-vault",
            Self::FungibleToken => "fungible-token",
            Self::Ownable => "ownable",
            Self::StakingVault => "staking-vault",
            Self::RoleGatedToken => "role-gated-token",
            Self::FeeToken => "fee-token",
            Self::RemoteCall => "remote-call",
            Self::StatusMessage => "status-message",
            Self::GuestBook => "guestbook",
            Self::StorageDeposit => "storage-deposit",
            Self::Pausable => "pausable",
            Self::ReentrancyGuard => "reentrancy-guard",
            Self::OwnablePausable => "ownable-pausable",
            Self::ArrayExample => "array-example",
            Self::OwnableHash => "ownable-hash",
            Self::HostEnvProbe => "host-env-probe",
        }
    }
}
