//! near-sdk AuthRemoteCall: debit local balance then promise_create(callee, receive, [amount]).
//! Mirrors `Examples/Product/AuthRemoteCall.lean`.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, Gas, NearToken, PanicOnDefault, Promise};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct AuthRemoteCall {
    balance: u64,
    callee: AccountId,
}

#[near]
impl AuthRemoteCall {
    #[init]
    pub fn initialize(callee: AccountId) -> Self {
        Self {
            balance: 100,
            callee,
        }
    }

    pub fn balance(&self) -> u64 {
        self.balance
    }

    /// Debit `amount` then forward using the same JSON-array ABI as EmitWat.
    pub fn debit_and_forward(&mut self, amount: u64) -> Promise {
        if self.balance < amount {
            env::panic_str("insufficient balance");
        }
        self.balance = self.balance.saturating_sub(amount);
        // Keep caller projection used (same as PF reading `caller`).
        let _ = env::predecessor_account_id();
        let args = near_sdk::serde_json::to_vec(&[amount])
            .unwrap_or_else(|_| env::panic_str("encode receive args"));
        Promise::new(self.callee.clone()).function_call(
            "receive".to_string(),
            args,
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }
}
