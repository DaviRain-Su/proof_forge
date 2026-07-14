//! near-sdk-rs ValueVault reference for `testkit/compare`.
//!
//! Implements the complete seven-method portable surface for the CMP-3
//! primary-triad differential and the existing Sandbox comparison harness.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ValueVault {
    balance: u64,
    released: u64,
    fees: u64,
    last_value: u64,
    last_checkpoint: u64,
    operations: u64,
}

#[near]
impl ValueVault {
    #[init]
    pub fn initialize(initial: u64) -> Self {
        let checkpoint = env::block_height();
        env::log_str(&format!(
            "EVENT_JSON:{{\"standard\":\"proof_forge\",\"version\":\"1.0.0\",\"event\":\"VaultInitialized\",\"data\":[{{\"initial\":{initial},\"checkpoint\":{checkpoint}}}]}}"
        ));
        Self {
            balance: initial,
            released: 0,
            fees: 0,
            last_value: initial,
            last_checkpoint: checkpoint,
            operations: 1,
        }
    }

    pub fn deposit(&mut self, amount: u64) {
        self.balance = self
            .balance
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("balance overflow"));
        self.last_value = amount;
        self.operations = self
            .operations
            .checked_add(1)
            .unwrap_or_else(|| env::panic_str("operations overflow"));
        env::log_str(&format!(
            "EVENT_JSON:{{\"standard\":\"proof_forge\",\"version\":\"1.0.0\",\"event\":\"ValueDeposited\",\"data\":[{{\"amount\":{amount},\"balance\":{},\"operations\":{}}}]}}",
            self.balance, self.operations
        ));
    }

    pub fn charge_fee(&mut self, gross: u64, fee_bps: u64) {
        let fee = gross
            .checked_mul(fee_bps)
            .and_then(|v| v.checked_div(10_000))
            .unwrap_or_else(|| env::panic_str("fee math"));
        let net = gross
            .checked_sub(fee)
            .unwrap_or_else(|| env::panic_str("net underflow"));
        self.balance = self
            .balance
            .checked_add(net)
            .unwrap_or_else(|| env::panic_str("balance overflow"));
        self.fees = self
            .fees
            .checked_add(fee)
            .unwrap_or_else(|| env::panic_str("fees overflow"));
        self.last_value = net;
        self.operations = self
            .operations
            .checked_add(1)
            .unwrap_or_else(|| env::panic_str("operations overflow"));
        env::log_str(&format!(
            "EVENT_JSON:{{\"standard\":\"proof_forge\",\"version\":\"1.0.0\",\"event\":\"ValueCharged\",\"data\":[{{\"gross\":{gross},\"fee\":{fee},\"net\":{net},\"balance\":{}}}]}}",
            self.balance
        ));
    }

    pub fn release(&mut self, amount: u64) {
        self.balance = self
            .balance
            .checked_sub(amount)
            .unwrap_or_else(|| env::panic_str("balance underflow"));
        self.released = self
            .released
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("released overflow"));
        self.last_value = amount;
        self.operations = self
            .operations
            .checked_add(1)
            .unwrap_or_else(|| env::panic_str("operations overflow"));
        env::log_str(&format!(
            "EVENT_JSON:{{\"standard\":\"proof_forge\",\"version\":\"1.0.0\",\"event\":\"ValueReleased\",\"data\":[{{\"amount\":{amount},\"balance\":{},\"released\":{}}}]}}",
            self.balance, self.released
        ));
    }

    pub fn snapshot(&mut self) -> u64 {
        let checkpoint = env::block_height();
        self.last_checkpoint = checkpoint;
        env::log_str(&format!(
            "EVENT_JSON:{{\"standard\":\"proof_forge\",\"version\":\"1.0.0\",\"event\":\"ValueSnapshot\",\"data\":[{{\"balance\":{},\"released\":{},\"fees\":{},\"checkpoint\":{checkpoint}}}]}}",
            self.balance, self.released, self.fees
        ));
        self.balance
    }

    pub fn get_balance(&self) -> u64 {
        self.balance
    }

    pub fn get_net_value(&self) -> u64 {
        self.balance
            .checked_sub(self.fees)
            .unwrap_or_else(|| env::panic_str("net underflow"))
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
    fn full_lifecycle_and_rejected_release() {
        context();
        let mut v = ValueVault::initialize(100);
        assert_eq!(v.get_balance(), 100);
        v.deposit(25);
        assert_eq!(v.get_balance(), 125);
        v.charge_fee(100, 250);
        assert_eq!(v.get_balance(), 223);
        assert_eq!(v.get_net_value(), 221);
        v.release(23);
        assert_eq!(v.get_balance(), 200);
        assert_eq!(v.snapshot(), 200);
        assert_eq!(v.get_net_value(), 198);

        let rejected = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| v.release(201)));
        assert!(rejected.is_err());
        assert_eq!(v.get_balance(), 200);
    }
}
