//! near-sdk NEP-145-lite storage reference for dual-deploy compare.
//!
//! Mirrors `Examples/Product/StorageDeposit.lean`: min bounds + cumulative
//! deposit balance keyed by account. Full NEP-145 JSON objects / withdraw /
//! refund are intentionally out of scope for a fair EmitWat surface.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct StorageDeposit {
    storage_required: u64,
    storage_deposits: LookupMap<AccountId, u64>,
}

#[near]
impl StorageDeposit {
    #[init]
    pub fn init() -> Self {
        Self {
            storage_required: 1,
            storage_deposits: LookupMap::new(b"s"),
        }
    }

    pub fn storage_balance_bounds(&self) -> u64 {
        self.storage_required
    }

    pub fn storage_balance_of(&self, account_id: AccountId) -> u64 {
        self.storage_deposits
            .get(&account_id)
            .copied()
            .unwrap_or(0)
    }

    #[payable]
    pub fn storage_deposit(&mut self, account_id: AccountId) {
        let amount = env::attached_deposit().as_yoctonear();
        let amount_u64 = u64::try_from(amount).unwrap_or_else(|_| env::panic_str("deposit overflow"));
        if amount_u64 < self.storage_required {
            env::panic_str("storage deposit too small");
        }
        let previous = self
            .storage_deposits
            .get(&account_id)
            .copied()
            .unwrap_or(0);
        let next = previous
            .checked_add(amount_u64)
            .unwrap_or_else(|| env::panic_str("balance overflow"));
        self.storage_deposits.insert(account_id, next);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::{testing_env, NearToken};

    fn ctx(pred: &str, deposit: u128) {
        let mut b = VMContextBuilder::new();
        b.predecessor_account_id(pred.parse().unwrap());
        b.attached_deposit(NearToken::from_yoctonear(deposit));
        testing_env!(b.build());
    }

    #[test]
    fn deposit_and_read() {
        ctx("alice.testnet", 7);
        let mut c = StorageDeposit::init();
        let alice: AccountId = "alice.testnet".parse().unwrap();
        assert_eq!(c.storage_balance_bounds(), 1);
        assert_eq!(c.storage_balance_of(alice.clone()), 0);
        c.storage_deposit(alice.clone());
        assert_eq!(c.storage_balance_of(alice), 7);
    }
}
