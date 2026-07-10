//! near-sdk ExternalTokenTransfer: call peer NEP-141 methods via promise.
//! Mirrors Product ExternalTokenTransfer control flow (not identical JSON packing).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{env, near, AccountId, Gas, NearToken, PanicOnDefault, Promise};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ExternalTokenTransfer {
    last_amount: u64,
    token: AccountId,
}

#[near]
impl ExternalTokenTransfer {
    #[init]
    pub fn initialize(token: AccountId) -> Self {
        Self {
            last_amount: 0,
            token,
        }
    }

    pub fn last_amount(&self) -> u64 {
        self.last_amount
    }

    /// Promise ft_transfer; records amount. receiver_id is a placeholder account string
    /// derived from u64 tag for fairness with PF u64 recipient projection.
    #[payable]
    pub fn pay(&mut self, recipient: u64, amount: u64) -> Promise {
        self.last_amount = amount;
        // Valid AccountId shape (lowercase letters + digits + separators).
        let receiver = format!("recv-{recipient}.test.near");
        let args = format!(
            r#"{{"receiver_id":"{receiver}","amount":"{amount}","memo":null}}"#
        );
        Promise::new(self.token.clone()).function_call(
            "ft_transfer".to_string(),
            args.into_bytes(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(30),
        )
    }

    pub fn set_allowance(&mut self, spender: u64, amount: u64) -> Promise {
        self.last_amount = amount;
        let spender_id = format!("s{spender}.test.near");
        let args = format!(
            r#"{{"account_id":"{spender_id}","amount":"{amount}"}}"#
        );
        // Use storage_deposit-shaped or custom approve stub on mock FT.
        Promise::new(self.token.clone()).function_call(
            "ft_approve_stub".to_string(),
            args.into_bytes(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }

    pub fn read_balance(&self, holder: u64) -> Promise {
        let account = format!("h{holder}.test.near");
        let args = format!(r#"{{"account_id":"{account}"}}"#);
        Promise::new(self.token.clone()).function_call(
            "ft_balance_of".to_string(),
            args.into_bytes(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }

    pub fn read_supply(&self) -> Promise {
        Promise::new(self.token.clone()).function_call(
            "ft_total_supply".to_string(),
            b"{}".to_vec(),
            NearToken::from_yoctonear(0),
            Gas::from_tgas(20),
        )
    }
}
