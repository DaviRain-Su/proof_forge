//! near-sdk mirror of Backend WasmNear FtPeerClient (NEP-141 peer client).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, Gas, NearToken, PanicOnDefault, Promise};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct FtPeerClient {
    last_amount: u64,
    token: AccountId,
    receiver: AccountId,
}

#[near]
impl FtPeerClient {
    #[init]
    pub fn new(token: AccountId, receiver: AccountId) -> Self {
        Self {
            last_amount: 0,
            token,
            receiver,
        }
    }

    pub fn last_amount(&self) -> u64 {
        self.last_amount
    }

    pub fn pay(&mut self, amount: u64) -> Promise {
        self.last_amount = amount;
        let args = format!(
            r#"{{"receiver_id":"{}","amount":"{}","memo":null}}"#,
            self.receiver, amount
        );
        Promise::new(self.token.clone()).function_call(
            "ft_transfer".to_string(),
            args.into_bytes(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }

    pub fn pay_with_callback(&mut self, amount: u64, msg_tag: u64) -> Promise {
        self.last_amount = amount;
        let args = format!(
            r#"{{"receiver_id":"{}","amount":"{}","memo":null,"msg":"{}"}}"#,
            self.receiver, amount, msg_tag
        );
        // Mock peer may expose ft_transfer_call; fall back surface name.
        Promise::new(self.token.clone()).function_call(
            "ft_transfer_call".to_string(),
            args.into_bytes(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(40),
        )
    }

    pub fn query_balance(&self) -> Promise {
        let args = format!(r#"{{"account_id":"{}"}}"#, self.receiver);
        Promise::new(self.token.clone()).function_call(
            "ft_balance_of".to_string(),
            args.into_bytes(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }

    pub fn query_supply(&self) -> Promise {
        Promise::new(self.token.clone()).function_call(
            "ft_total_supply".to_string(),
            b"{}".to_vec(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }
}
