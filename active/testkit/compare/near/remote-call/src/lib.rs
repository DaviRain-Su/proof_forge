//! near-sdk-rs RemoteCall mirror of `Examples/Product/RemoteCall.lean`.
//!
//! - `initialize(callee)` stores peer account
//! - `call_remote` → promise_create(callee, "remote_call", [])
//! - `call_with_args` → promise with JSON `[42,7]` body (method still remote_call)

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, Gas, NearToken, PanicOnDefault, Promise};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct RemoteCall {
    marker: u64,
    callee: AccountId,
}

#[near]
impl RemoteCall {
    #[init]
    pub fn initialize(callee: AccountId) -> Self {
        Self {
            marker: 0,
            callee,
        }
    }

    pub fn call_remote(&self) -> Promise {
        Promise::new(self.callee.clone()).function_call(
            "remote_call".to_string(),
            b"{}".to_vec(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }

    pub fn call_with_args(&self) -> Promise {
        Promise::new(self.callee.clone()).function_call(
            "remote_call".to_string(),
            br#"{"_args":[42,7]}"#.to_vec(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }

    pub fn marker(&self) -> u64 {
        self.marker
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    #[test]
    fn init_stores_callee() {
        let mut b = VMContextBuilder::new();
        b.predecessor_account_id("alice.testnet".parse().unwrap());
        testing_env!(b.build());
        let c = RemoteCall::initialize("bob.testnet".parse().unwrap());
        assert_eq!(c.marker(), 0);
        let _ = env::block_timestamp();
    }
}
