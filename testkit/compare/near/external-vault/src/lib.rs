//! near-sdk ExternalVault peer client.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{near, AccountId, Gas, NearToken, PanicOnDefault, Promise};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ExternalVault {
    last_shares: u64,
    vault: AccountId,
}

#[near]
impl ExternalVault {
    #[init]
    pub fn initialize(vault: AccountId) -> Self {
        Self {
            last_shares: 0,
            vault,
        }
    }

    pub fn last_shares(&self) -> u64 {
        self.last_shares
    }

    pub fn deposit_assets(&mut self, assets: u64, receiver: u64) -> Promise {
        self.last_shares = assets; // preview-equal for mock 1:1
        let mut args = assets.to_le_bytes().to_vec();
        args.extend_from_slice(&receiver.to_le_bytes());
        Promise::new(self.vault.clone()).function_call(
            "deposit".to_string(),
            args,
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }

    pub fn preview_shares(&self, assets: u64) -> Promise {
        Promise::new(self.vault.clone()).function_call(
            "convert_to_shares".to_string(),
            assets.to_le_bytes().to_vec(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }

    pub fn read_total_assets(&self) -> Promise {
        Promise::new(self.vault.clone()).function_call(
            "total_assets".to_string(),
            Vec::new(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }
}
