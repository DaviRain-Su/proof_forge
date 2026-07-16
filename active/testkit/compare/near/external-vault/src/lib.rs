//! near-sdk ExternalVault peer client.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, Gas, NearToken, PanicOnDefault, Promise};

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

    pub fn deposit_assets(&self, assets: u64, receiver: u64) -> Promise {
        // A scheduled promise has no synchronous shares result. Keep
        // `last_shares` unchanged until a real callback contract exists.
        let args = near_sdk::serde_json::to_vec(&[assets, receiver])
            .unwrap_or_else(|_| env::panic_str("encode deposit args"));
        Promise::new(self.vault.clone()).function_call(
            "deposit".to_string(),
            args,
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }

    pub fn preview_shares(&self, assets: u64) -> Promise {
        let args = near_sdk::serde_json::to_vec(&[assets])
            .unwrap_or_else(|_| env::panic_str("encode convert args"));
        Promise::new(self.vault.clone()).function_call(
            "convert_to_shares".to_string(),
            args,
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
