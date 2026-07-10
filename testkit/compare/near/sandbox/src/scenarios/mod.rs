//! Scenario registry — one dispatch table for dual-deploy sides.

use std::path::Path;

use anyhow::{bail, Result};
use near_workspaces::network::Sandbox;
use near_workspaces::Worker;

use crate::kind::ContractKind;
use crate::report::{SideKind, SideReport};

mod status;
mod guestbook;
mod pausable;
mod reentrancy;
mod ownable_pausable;
mod storage_deposit;
mod remote_call;
mod counter;
mod value_vault;
mod fungible_token;
mod ownable;
mod staking;
mod role_gated;
mod fee_token;
mod array_example;
mod ownable_hash;
mod host_env_probe;
mod auth_remote_call;
mod access_control;
mod external_token_transfer;
mod external_vault;
mod pro_rata_vault;
mod soulbound_token;
mod ft_peer_client;
mod vesting_vault;
mod escrow_vault;
mod timelock_vault;
mod height_lock_vault;


/// Run one side (ProofForge or near-sdk) for a registered contract.
pub(crate) async fn run_side(
    kind: ContractKind,
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    side: SideKind,
) -> Result<SideReport> {
    match kind {
        ContractKind::Counter => counter::run_counter_side(worker, wasm_path, side).await,
        ContractKind::ValueVault => value_vault::run_value_vault_side(worker, wasm_path, side).await,
        ContractKind::FungibleToken => fungible_token::run_ft_side(worker, wasm_path, side).await,
        ContractKind::Ownable => ownable::run_ownable_side(worker, wasm_path, side).await,
        ContractKind::StakingVault => staking::run_staking_side(worker, wasm_path, side).await,
        ContractKind::RoleGatedToken => role_gated::run_rgt_side(worker, wasm_path, side).await,
        ContractKind::FeeToken => fee_token::run_fee_side(worker, wasm_path, side).await,
        ContractKind::StatusMessage => status::run_status_side(worker, wasm_path, side).await,
        ContractKind::GuestBook => guestbook::run_guestbook_side(worker, wasm_path, side).await,
        ContractKind::StorageDeposit => {
            storage_deposit::run_storage_deposit_side(worker, wasm_path, side).await
        }
        ContractKind::Pausable => pausable::run_pausable_side(worker, wasm_path, side).await,
        ContractKind::ReentrancyGuard => {
            reentrancy::run_reentrancy_side(worker, wasm_path, side).await
        }
        ContractKind::OwnablePausable => {
            ownable_pausable::run_ownable_pausable_side(worker, wasm_path, side).await
        }
        ContractKind::ArrayExample => {
            array_example::run_array_example_side(worker, wasm_path, side).await
        }
        ContractKind::OwnableHash => {
            ownable_hash::run_ownable_hash_side(worker, wasm_path, side).await
        }
        ContractKind::HostEnvProbe => {
            host_env_probe::run_host_env_probe_side(worker, wasm_path, side).await
        }
        ContractKind::AccessControl => {
            access_control::run_access_control_side(worker, wasm_path, side).await
        }
        ContractKind::ProRataVault => {
            pro_rata_vault::run_pro_rata_vault_side(worker, wasm_path, side).await
        }
        ContractKind::SoulboundToken => {
            soulbound_token::run_soulbound_token_side(worker, wasm_path, side).await
        }
        ContractKind::VestingVault => {
            vesting_vault::run_vesting_vault_side(worker, wasm_path, side).await
        }
        ContractKind::EscrowVault => {
            escrow_vault::run_escrow_vault_side(worker, wasm_path, side).await
        }
        ContractKind::TimelockVault => {
            timelock_vault::run_timelock_vault_side(worker, wasm_path, side).await
        }
        ContractKind::HeightLockVault => {
            height_lock_vault::run_height_lock_vault_side(worker, wasm_path, side).await
        }
        ContractKind::RemoteCall
        | ContractKind::AuthRemoteCall
        | ContractKind::ExternalTokenTransfer
        | ContractKind::ExternalVault
        | ContractKind::FtPeerClient => {
            bail!("{} uses multi-account matrix, not run_side", kind.as_str())
        }
    }
}

pub(crate) use auth_remote_call::run_auth_remote_call_matrix;
pub(crate) use external_token_transfer::run_external_token_transfer_matrix;
pub(crate) use external_vault::run_external_vault_matrix;
pub(crate) use ft_peer_client::run_ft_peer_client_matrix;
pub(crate) use remote_call::run_remote_call_matrix;
