//! near-sdk Ownable + Pausable: only owner may pause/unpause.
//! Mirrors `ProofForge.Contract.Stdlib.OwnablePausable`.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct OwnablePausable {
    owner: AccountId,
    paused: u64,
}

#[near]
impl OwnablePausable {
    #[init]
    pub fn init() -> Self {
        Self {
            owner: env::predecessor_account_id(),
            paused: 0,
        }
    }

    pub fn owner(&self) -> AccountId {
        self.owner.clone()
    }

    pub fn paused(&self) -> u64 {
        self.paused
    }

    pub fn pause(&mut self) {
        self.assert_owner();
        if self.paused != 0 {
            env::panic_str("already paused");
        }
        self.paused = 1;
    }

    pub fn unpause(&mut self) {
        self.assert_owner();
        if self.paused == 0 {
            env::panic_str("not paused");
        }
        self.paused = 0;
    }

    pub fn renounce_ownership(&mut self) {
        self.assert_owner();
        self.owner = "renounced.near".parse().unwrap();
    }

    fn assert_owner(&self) {
        if env::predecessor_account_id() != self.owner {
            env::panic_str("Ownable: caller is not the owner");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    fn ctx(pred: &str) {
        let mut b = VMContextBuilder::new();
        b.predecessor_account_id(pred.parse().unwrap());
        testing_env!(b.build());
    }

    #[test]
    fn owner_pause() {
        ctx("alice.testnet");
        let mut c = OwnablePausable::init();
        assert_eq!(c.paused(), 0);
        c.pause();
        assert_eq!(c.paused(), 1);
        c.unpause();
        assert_eq!(c.paused(), 0);
    }
}
