//! near-sdk-rs Counter for ProofForge benchmarks (B1.2).
//!
//! Semantic surface matches `Examples/Product/Counter.lean` and the durable
//! compare package under `testkit/compare/near/counter`.
//!
//! Kept under `benchmarks/native/` so B1 corpus is self-contained; the testkit
//! package remains the live dual-deploy compare driver.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Counter {
    count: u64,
}

#[near]
impl Counter {
    #[init]
    pub fn initialize() -> Self {
        Self { count: 0 }
    }

    pub fn increment(&mut self) {
        self.count = self
            .count
            .checked_add(1)
            .unwrap_or_else(|| near_sdk::env::panic_str("counter overflow"));
    }

    pub fn get(&self) -> u64 {
        self.count
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    fn context() {
        let mut builder = VMContextBuilder::new();
        builder.predecessor_account_id("alice.testnet".parse().unwrap());
        testing_env!(builder.build());
    }

    #[test]
    fn initialize_get_zero() {
        context();
        let contract = Counter::initialize();
        assert_eq!(contract.get(), 0);
    }

    #[test]
    fn increment_sequence() {
        context();
        let mut contract = Counter::initialize();
        contract.increment();
        assert_eq!(contract.get(), 1);
        contract.increment();
        assert_eq!(contract.get(), 2);
    }
}
