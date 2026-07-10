//! near-sdk-rs FeeToken mirror of `Examples/Backend/WasmNear/FeeToken.lean`.
//! Transfer burns `fee_bps/10000` of amount from total supply.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct FeeToken {
    total_supply: u64,
    fee_bps: u64,
    balances: LookupMap<AccountId, u64>,
}

#[near]
impl FeeToken {
    #[init]
    pub fn init(fee_bps: u64) -> Self {
        Self {
            total_supply: 0,
            fee_bps,
            balances: LookupMap::new(b"b"),
        }
    }

    pub fn mint(&mut self, recipient: AccountId, amount: u64) {
        if amount == 0 {
            env::panic_str("zero amount");
        }
        let bal = self.balances.get(&recipient).copied().unwrap_or(0);
        self.balances.insert(
            recipient.clone(),
            bal.checked_add(amount)
                .unwrap_or_else(|| env::panic_str("overflow")),
        );
        self.total_supply = self
            .total_supply
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("overflow"));
        env::log_str(&format!(
            "{{\"event\":\"Mint\",\"to\":\"{recipient}\",\"amount\":{amount}}}"
        ));
    }

    pub fn transfer(&mut self, recipient: AccountId, amount: u64) {
        if amount == 0 {
            env::panic_str("zero amount");
        }
        let sender = env::predecessor_account_id();
        let src = self.balances.get(&sender).copied().unwrap_or(0);
        if src < amount {
            env::panic_str("insufficient balance");
        }
        let fee = amount
            .checked_mul(self.fee_bps)
            .and_then(|v| v.checked_div(10_000))
            .unwrap_or_else(|| env::panic_str("fee math"));
        let net = amount
            .checked_sub(fee)
            .unwrap_or_else(|| env::panic_str("net underflow"));
        let dst = self.balances.get(&recipient).copied().unwrap_or(0);
        self.balances.insert(sender.clone(), src - amount);
        self.balances.insert(
            recipient.clone(),
            dst.checked_add(net)
                .unwrap_or_else(|| env::panic_str("overflow")),
        );
        self.total_supply = self
            .total_supply
            .checked_sub(fee)
            .unwrap_or_else(|| env::panic_str("supply underflow"));
        env::log_str(&format!(
            "{{\"event\":\"Transfer\",\"from\":\"{sender}\",\"to\":\"{recipient}\",\"amount\":{net},\"fee\":{fee}}}"
        ));
    }

    pub fn balance_of(&self, who: AccountId) -> u64 {
        self.balances.get(&who).copied().unwrap_or(0)
    }

    pub fn total_supply(&self) -> u64 {
        self.total_supply
    }

    pub fn get_fee_bps(&self) -> u64 {
        self.fee_bps
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
    fn fee_transfer() {
        ctx("alice.testnet");
        let mut c = FeeToken::init(1000); // 10%
        let alice: AccountId = "alice.testnet".parse().unwrap();
        let bob: AccountId = "bob.testnet".parse().unwrap();
        c.mint(alice.clone(), 100);
        c.transfer(bob.clone(), 50); // fee=5 (10%), net=45
        assert_eq!(c.balance_of(alice), 50);
        assert_eq!(c.balance_of(bob), 45);
        assert_eq!(c.total_supply(), 95);
    }
}
