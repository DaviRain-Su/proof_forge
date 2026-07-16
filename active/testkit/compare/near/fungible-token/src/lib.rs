//! near-sdk-rs NEP-141-minimal FT reference for `testkit/compare`.
//!
//! Comparable surface vs ProofForge `Stdlib.NearFungibleToken` / Backend
//! `Examples/Backend/WasmNear/FungibleToken.lean`:
//! - `init`
//! - `ft_mint(account_id, amount)`
//! - `ft_transfer(receiver_id, amount)` (predecessor is sender)
//! - `ft_balance_of(account_id)` → u64
//! - `ft_total_supply()` → u64
//!
//! Intentionally omits approve / transfer_call / NEP-145 for a fair minimal face.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct FungibleToken {
    total_supply: u64,
    balances: LookupMap<AccountId, u64>,
}

#[near]
impl FungibleToken {
    #[init]
    pub fn init() -> Self {
        Self {
            total_supply: 0,
            balances: LookupMap::new(b"b"),
        }
    }

    pub fn ft_mint(&mut self, account_id: AccountId, amount: u64) {
        let bal = self.balances.get(&account_id).copied().unwrap_or(0);
        let next = bal
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("balance overflow"));
        self.balances.insert(account_id.clone(), next);
        self.total_supply = self
            .total_supply
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("supply overflow"));
        // Match PF event name shape (account id string rather than hash hex).
        env::log_str(&format!(
            "{{\"event\":\"FMint\",\"to\":\"{account_id}\",\"amount\":{amount}}}"
        ));
    }

    pub fn ft_transfer(&mut self, receiver_id: AccountId, amount: u64) {
        if amount == 0 {
            env::panic_str("zero amount");
        }
        let sender = env::predecessor_account_id();
        let src = self.balances.get(&sender).copied().unwrap_or(0);
        if src < amount {
            env::panic_str("insufficient balance");
        }
        let dst = self.balances.get(&receiver_id).copied().unwrap_or(0);
        self.balances.insert(sender.clone(), src - amount);
        self.balances.insert(
            receiver_id.clone(),
            dst.checked_add(amount)
                .unwrap_or_else(|| env::panic_str("balance overflow")),
        );
        env::log_str(&format!(
            "{{\"event\":\"FTransfer\",\"from\":\"{sender}\",\"to\":\"{receiver_id}\",\"amount\":{amount}}}"
        ));
    }

    pub fn ft_balance_of(&self, account_id: AccountId) -> u64 {
        self.balances.get(&account_id).copied().unwrap_or(0)
    }

    pub fn ft_total_supply(&self) -> u64 {
        self.total_supply
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
    fn mint_transfer_balances() {
        ctx("alice.testnet");
        let mut c = FungibleToken::init();
        let alice: AccountId = "alice.testnet".parse().unwrap();
        let bob: AccountId = "bob.testnet".parse().unwrap();
        c.ft_mint(alice.clone(), 100);
        assert_eq!(c.ft_total_supply(), 100);
        assert_eq!(c.ft_balance_of(alice.clone()), 100);
        c.ft_transfer(bob.clone(), 30);
        assert_eq!(c.ft_balance_of(alice), 70);
        assert_eq!(c.ft_balance_of(bob), 30);
    }
}
