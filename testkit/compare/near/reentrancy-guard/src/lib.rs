//! near-sdk ReentrancyGuard lock-bit reference.
//! Implements the portable acquire / release / locked policy independently.
//! This is lock-state behavior, not EVM call-stack reentrancy theory.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near};

/// Default unlocked state — matches PF surface (no init export).
#[near(contract_state)]
#[derive(Default)]
pub struct ReentrancyGuard {
    lock: u64,
}

#[near]
impl ReentrancyGuard {
    pub fn locked(&self) -> u64 {
        self.lock
    }

    pub fn acquire(&mut self) {
        if self.lock != 0 {
            env::panic_str("reentrant call");
        }
        self.lock = 1;
    }

    pub fn release(&mut self) {
        if self.lock == 0 {
            env::panic_str("lock not held");
        }
        self.lock = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    #[test]
    fn lock_cycle() {
        testing_env!(VMContextBuilder::new().build());
        let mut c = ReentrancyGuard::default();
        assert_eq!(c.locked(), 0);
        c.acquire();
        assert_eq!(c.locked(), 1);
        c.release();
        assert_eq!(c.locked(), 0);
    }

    #[test]
    #[should_panic(expected = "reentrant call")]
    fn repeated_acquire_is_rejected() {
        testing_env!(VMContextBuilder::new().build());
        let mut c = ReentrancyGuard::default();
        c.acquire();
        c.acquire();
    }

    #[test]
    #[should_panic(expected = "lock not held")]
    fn release_while_unlocked_is_rejected() {
        testing_env!(VMContextBuilder::new().build());
        let mut c = ReentrancyGuard::default();
        c.release();
    }
}
