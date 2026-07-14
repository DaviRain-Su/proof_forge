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
        let owner = env::predecessor_account_id();
        log_ownership_transferred(None, Some(&owner));
        Self {
            owner,
        }
    }

    pub fn owner(&self) -> AccountId {
        self.owner.clone()
    }

    /// Snake_case export; compare harness also accepts this name for sdk side.
    pub fn transfer_ownership(&mut self, new_owner: AccountId) {
        self.assert_owner();
        assert_ne!(new_owner.as_str(), "", "zero address");
        log_ownership_transferred(Some(&self.owner), Some(&new_owner));
        self.owner = new_owner;
    }

    pub fn renounce_ownership(&mut self) {
        self.assert_owner();
        // AccountId cannot be empty; sentinel matches PF setting owner to 0 (renounced).
        let renounced = "renounced.near".parse().unwrap();
        log_ownership_transferred(Some(&self.owner), None);
        self.owner = renounced;
    }

    fn assert_owner(&self) {
        if env::predecessor_account_id() != self.owner {
            env::panic_str("Ownable: caller is not the owner");
        }
    }
}

fn log_ownership_transferred(previous_owner: Option<&AccountId>, new_owner: Option<&AccountId>) {
    let previous = previous_owner.map_or("0", |owner| owner.as_str());
    let next = new_owner.map_or("0", |owner| owner.as_str());
    env::log_str(&format!(
        "EVENT_JSON:{{\"standard\":\"proof_forge\",\"version\":\"1.0.0\",\"event\":\"OwnershipTransferred\",\"data\":[{{\"previousOwner\":\"{previous}\",\"newOwner\":\"{next}\"}}]}}"
    ));
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::{get_logs, VMContextBuilder};
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
        assert!(get_logs().last().unwrap().contains("OwnershipTransferred"));
        c.transfer_ownership("bob.testnet".parse().unwrap());
        ctx("bob.testnet");
        assert_eq!(c.owner().as_str(), "bob.testnet");
        c.renounce_ownership();
        assert_eq!(c.owner().as_str(), "renounced.near");
        assert!(get_logs().last().unwrap().contains("\"newOwner\":\"0\""));
    }
}
