//! near-sdk-rs ValueVault reference for `testkit/compare`.
//!
//! Mirrors the portable surface of `Examples/Product/ValueVault.lean` for the
//! dual-deploy scenario used by the sandbox harness:
//! - `initialize(initial)`
//! - `deposit(amount)`
//! - `get_balance()` → u64
//!
//! Additional fields/methods exist for size parity with the portable state
//! shape; the live scenario only exercises initialize/deposit/get_balance.

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
        // Match ProofForge EmitWat JSON log shape for fair dual-deploy gas compare.
        env::log_str(&format!(
            "{{\"event\":\"VaultInitialized\",\"initial\":{initial},\"checkpoint\":{checkpoint}}}"
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
            "{{\"event\":\"ValueDeposited\",\"amount\":{amount},\"balance\":{},\"operations\":{}}}",
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
    fn init_deposit_balance() {
        context();
        let mut v = ValueVault::initialize(100);
        assert_eq!(v.get_balance(), 100);
        v.deposit(50);
        assert_eq!(v.get_balance(), 150);
    }
}
