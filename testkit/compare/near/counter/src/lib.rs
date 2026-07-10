//! near-sdk-rs Counter reference for `testkit/compare`.
//!
//! Semantic surface matches `Examples/Product/Counter.lean`:
//! - `initialize` → count = 0
//! - `increment`  → count += 1 (checked)
//! - `get`        → current count as `u64`
//!
//! Adapted from the official NEAR counter tutorial shape
//! (`near-examples/counters`) but aligned to ProofForge's portable
//! initialize/increment/get API and `u64` state (the tutorial uses `i8`
//! with optional delta args).
//!
//! Colocated with the compare driver under `testkit/compare/near/counter/`.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{near, PanicOnDefault};

/// Counter contract state. Field name `count` mirrors the portable IR state.
#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Counter {
    count: u64,
}

#[near]
impl Counter {
    /// Create the contract with `count = 0`.
    #[init]
    pub fn initialize() -> Self {
        Self { count: 0 }
    }

    /// Increment `count` by one. Panics on overflow.
    pub fn increment(&mut self) {
        self.count = self
            .count
            .checked_add(1)
            .unwrap_or_else(|| near_sdk::env::panic_str("counter overflow"));
    }

    /// Return the current count.
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
