//! near-sdk StatusMessage reference for dual-deploy compare.
//!
//! Official tutorial uses `String` messages; this reference stores **u64**
//! status codes to match ProofForge EmitWat portable surface
//! (`Examples/Product/StatusMessage.lean`).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct StatusMessage {
    records: LookupMap<u64, u64>,
}

fn account_handle(account: &str) -> u64 {
    u64::from_le_bytes(env::sha256_array(account.as_bytes())[..8].try_into().unwrap())
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
        let who = account_handle(env::predecessor_account_id().as_str());
        self.records.insert(who, status);
        env::log_str(&format!(
            r#"EVENT_JSON:{{"standard":"proof_forge","version":"1.0.0","event":"StatusSet","data":[{{"account":{who},"status":{status}}}]}}"#
        ));
    }

    pub fn get_status(&self, who: u64) -> u64 {
        self.records.get(&who).copied().unwrap_or(0)
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
        let alice = account_handle("alice.testnet");
        assert_eq!(c.get_status(alice), 7);
    }
}
