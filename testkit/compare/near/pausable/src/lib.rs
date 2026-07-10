//! near-sdk Pausable reference (unauthenticated pause/unpause).
//! Mirrors `ProofForge.Contract.Stdlib.Pausable` / Product Pausable.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near};

/// Default state (unpaused) so deploy needs no init — matches PF surface (no init export).
#[near(contract_state)]
#[derive(Default)]
pub struct Pausable {
    paused: u64,
}

#[near]
impl Pausable {
    pub fn paused(&self) -> u64 {
        self.paused
    }

    pub fn pause(&mut self) {
        if self.paused != 0 {
            env::panic_str("already paused");
        }
        self.paused = 1;
    }

    pub fn unpause(&mut self) {
        if self.paused == 0 {
            env::panic_str("not paused");
        }
        self.paused = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    #[test]
    fn toggle() {
        testing_env!(VMContextBuilder::new().build());
        let mut c = Pausable::default();
        assert_eq!(c.paused(), 0);
        c.pause();
        assert_eq!(c.paused(), 1);
        c.unpause();
        assert_eq!(c.paused(), 0);
    }
}
