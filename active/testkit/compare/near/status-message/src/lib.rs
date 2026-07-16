//! near-sdk StatusMessage reference for dual-deploy compare.
//!
//! Official tutorial uses `String` messages; this reference stores **u64**
//! status codes to match ProofForge EmitWat portable surface
//! (`Examples/Product/StatusMessage.lean`).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct StatusMessage {
    records: LookupMap<AccountId, u64>,
}

#[near]
impl StatusMessage {
    #[init]
    pub fn init() -> Self {
        Self {
            records: LookupMap::new(b"r"),
        }
    }

    pub fn set_status(&mut self, status: u64) {
        let who = env::predecessor_account_id();
        self.records.insert(who.clone(), status);
        env::log_str(&format!(
            "{{\"event\":\"StatusSet\",\"account\":\"{who}\",\"status\":{status}}}"
        ));
    }

    pub fn get_status(&self, account: AccountId) -> u64 {
        self.records.get(&account).copied().unwrap_or(0)
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
    fn set_get() {
        ctx("alice.testnet");
        let mut c = StatusMessage::init();
        c.set_status(7);
        let alice: AccountId = "alice.testnet".parse().unwrap();
        assert_eq!(c.get_status(alice), 7);
    }
}
