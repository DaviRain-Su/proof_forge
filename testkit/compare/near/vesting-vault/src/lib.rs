//! near-sdk VestingVault mirror of Examples/Product/VestingVault.lean.
//! Linear vesting via env::block_timestamp (HostEnv block time).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct VestingVault {
    beneficiary: u64,
    total_allocation: u64,
    released: u64,
    start_time: u64,
    duration: u64,
    claim_balance: u64,
}

#[near]
impl VestingVault {
    #[init]
    pub fn init(who: u64, total: u64, start: u64, dur: u64) -> Self {
        assert!(total > 0, "zero total");
        assert!(dur > 0, "zero duration");
        Self {
            beneficiary: who,
            total_allocation: total,
            released: 0,
            start_time: start,
            duration: dur,
            claim_balance: 0,
        }
    }

    fn compute_vested(&self) -> u64 {
        let now = env::block_timestamp();
        let elapsed = now.saturating_sub(self.start_time);
        if elapsed >= self.duration {
            self.total_allocation
        } else {
            self.total_allocation
                .saturating_mul(elapsed)
                / self.duration
        }
    }

    /// Change method (matches PF entry that writes scratch).
    pub fn vested(&mut self) -> u64 {
        self.compute_vested()
    }

    pub fn releasable(&mut self) -> u64 {
        self.compute_vested().saturating_sub(self.released)
    }

    pub fn claim_balance(&self) -> u64 {
        self.claim_balance
    }

    pub fn total_allocation(&self) -> u64 {
        self.total_allocation
    }

    pub fn released_amount(&self) -> u64 {
        self.released
    }

    pub fn release(&mut self) {
        let vested = self.compute_vested();
        let amount = vested.saturating_sub(self.released);
        assert!(amount > 0, "nothing releasable");
        self.released = self.released.saturating_add(amount);
        self.claim_balance = self.claim_balance.saturating_add(amount);
    }
}
