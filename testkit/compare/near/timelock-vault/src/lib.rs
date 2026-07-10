//! near-sdk TimelockVault mirror of Examples/Product/TimelockVault.lean.
//! Binary unlock via env::block_timestamp (not linear vesting).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct TimelockVault {
    locked: u64,
    unlock_at: u64,
    claim_balance: u64,
    claimed: u64,
}

#[near]
impl TimelockVault {
    #[init]
    pub fn init() -> Self {
        Self {
            locked: 0,
            unlock_at: 0,
            claim_balance: 0,
            claimed: 0,
        }
    }

    pub fn lock(&mut self, amount: u64, unlock_at: u64) {
        assert_eq!(self.locked, 0, "already locked");
        assert_eq!(self.claimed, 0, "already claimed");
        assert!(amount > 0, "zero amount");
        self.locked = amount;
        self.unlock_at = unlock_at;
    }

    pub fn claim(&mut self) {
        assert_eq!(self.claimed, 0, "already claimed");
        assert!(self.locked > 0, "nothing locked");
        let now = env::block_timestamp();
        assert!(now >= self.unlock_at, "still locked");
        let amount = self.locked;
        self.claimed = 1;
        self.locked = 0;
        self.claim_balance = self.claim_balance.saturating_add(amount);
    }

    pub fn get_locked(&self) -> u64 {
        self.locked
    }

    pub fn get_unlock_at(&self) -> u64 {
        self.unlock_at
    }

    pub fn claim_balance(&self) -> u64 {
        self.claim_balance
    }

    pub fn is_claimed(&self) -> u64 {
        self.claimed
    }
}
