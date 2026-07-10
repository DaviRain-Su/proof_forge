//! near-sdk GuestBook reference (u64 message codes) for dual-deploy compare.
//! Mirrors `Examples/Product/GuestBook.lean` control flow.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct GuestBook {
    message_count: u64,
    messages: LookupMap<u64, u64>,
    authors: LookupMap<u64, AccountId>,
}

#[near]
impl GuestBook {
    #[init]
    pub fn init() -> Self {
        Self {
            message_count: 0,
            messages: LookupMap::new(b"m"),
            authors: LookupMap::new(b"a"),
        }
    }

    pub fn add_message(&mut self, code: u64) {
        let idx = self.message_count;
        let who = env::predecessor_account_id();
        self.messages.insert(idx, code);
        self.authors.insert(idx, who.clone());
        self.message_count = idx.saturating_add(1);
        env::log_str(&format!(
            "{{\"event\":\"MessagePosted\",\"index\":{idx},\"author\":\"{who}\",\"code\":{code}}}"
        ));
    }

    pub fn get_message(&self, index: u64) -> u64 {
        self.messages.get(&index).copied().unwrap_or(0)
    }

    pub fn get_author(&self, index: u64) -> AccountId {
        self.authors
            .get(&index)
            .cloned()
            .unwrap_or_else(|| "0".parse().unwrap_or_else(|_| env::current_account_id()))
    }

    pub fn total_messages(&self) -> u64 {
        self.message_count
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
    fn append_read() {
        ctx("alice.testnet");
        let mut g = GuestBook::init();
        g.add_message(11);
        g.add_message(22);
        assert_eq!(g.total_messages(), 2);
        assert_eq!(g.get_message(0), 11);
        assert_eq!(g.get_message(1), 22);
    }
}
