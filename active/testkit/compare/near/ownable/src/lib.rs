//! near-sdk-rs Ownable reference aligned to portable Ownable surface:
//! - `init` → owner = predecessor
//! - `owner` view → AccountId (sdk) / u64 projection (PF)
//! - `transfer_ownership(new_owner)`
//! - `renounce_ownership`
//!
//! Method names use snake_case for near-sdk ABI; PF emits camelCase
//! `transferOwnership` / `renounceOwnership` / query `owner`.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Ownable {
    owner: AccountId,
}

#[near]
impl Ownable {
    #[init]
    pub fn init() -> Self {
        Self {
            owner: env::predecessor_account_id(),
        }
    }

    pub fn owner(&self) -> AccountId {
        self.owner.clone()
    }

    /// Snake_case export; compare harness also accepts this name for sdk side.
    pub fn transfer_ownership(&mut self, new_owner: AccountId) {
        self.assert_owner();
        assert_ne!(new_owner.as_str(), "", "zero address");
        self.owner = new_owner;
    }

    pub fn renounce_ownership(&mut self) {
        self.assert_owner();
        // AccountId cannot be empty; sentinel matches PF setting owner to 0 (renounced).
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
    fn transfer_and_renounce() {
        ctx("alice.testnet");
        let mut c = Ownable::init();
        assert_eq!(c.owner().as_str(), "alice.testnet");
        c.transfer_ownership("bob.testnet".parse().unwrap());
        ctx("bob.testnet");
        assert_eq!(c.owner().as_str(), "bob.testnet");
        c.renounce_ownership();
        assert_eq!(c.owner().as_str(), "renounced.near");
    }
}
