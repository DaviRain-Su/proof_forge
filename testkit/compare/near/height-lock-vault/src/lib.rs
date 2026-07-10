//! near-sdk HeightLockVault mirror of Examples/Product/HeightLockVault.lean.
//! Binary unlock via env::block_height (HostEnv checkpointId).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct HeightLockVault {
    locked: u64,
    unlock_height: u64,
    claim_balance: u64,
    claimed: u64,
}

#[near]
impl HeightLockVault {
    #[init]
    pub fn init() -> Self {
        Self {
            locked: 0,
            unlock_height: 0,
            claim_balance: 0,
            claimed: 0,
        }
    }

    pub fn lock(&mut self, amount: u64, unlock_height: u64) {
        assert_eq!(self.locked, 0, "already locked");
        assert_eq!(self.claimed, 0, "already claimed");
        assert!(amount > 0, "zero amount");
        self.locked = amount;
        self.unlock_height = unlock_height;
    }

    pub fn claim(&mut self) {
        assert_eq!(self.claimed, 0, "already claimed");
        assert!(self.locked > 0, "nothing locked");
        let height = env::block_height();
        assert!(height >= self.unlock_height, "height too low");
        let amount = self.locked;
        self.claimed = 1;
        self.locked = 0;
        self.claim_balance = self.claim_balance.saturating_add(amount);
    }

    pub fn get_locked(&self) -> u64 {
        self.locked
    }

    pub fn get_unlock_height(&self) -> u64 {
        self.unlock_height
    }

    pub fn claim_balance(&self) -> u64 {
        self.claim_balance
    }

    pub fn is_claimed(&self) -> u64 {
        self.claimed
    }
}
