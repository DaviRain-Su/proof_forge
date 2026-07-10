//! near-sdk-rs StakingVault mirror of `Examples/Product/StakingVault.lean`.
//!
//! - `init`
//! - `deposit` — credit predecessor with attached deposit (1:1 shares)
//! - `withdraw(share_amount)`
//! - `get_shares(account)` / `get_total_deposits` views for scenario checks
//!
//! PF uses u64 caller projection + map; sdk uses AccountId map + attached deposit.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, NearToken, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct StakingVault {
    total_deposits: u64,
    total_shares: u64,
    shares: LookupMap<AccountId, u64>,
}

#[near]
impl StakingVault {
    #[init]
    pub fn init() -> Self {
        Self {
            total_deposits: 0,
            total_shares: 0,
            shares: LookupMap::new(b"s"),
        }
    }

    #[payable]
    pub fn deposit(&mut self) {
        let amount = env::attached_deposit().as_yoctonear();
        // Scenario uses small whole-NEAR amounts cast to u64 (same as PF U64 nativeValue).
        let amount = u64::try_from(amount).unwrap_or_else(|_| env::panic_str("amount > u64"));
        if amount == 0 {
            env::panic_str("zero deposit");
        }
        let who = env::predecessor_account_id();
        let cur = self.shares.get(&who).copied().unwrap_or(0);
        self.shares.insert(
            who.clone(),
            cur.checked_add(amount)
                .unwrap_or_else(|| env::panic_str("shares overflow")),
        );
        self.total_deposits = self
            .total_deposits
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("deposits overflow"));
        self.total_shares = self
            .total_shares
            .checked_add(amount)
            .unwrap_or_else(|| env::panic_str("shares overflow"));
        env::log_str(&format!(
            "{{\"event\":\"Deposit\",\"depositor\":\"{who}\",\"amount\":{amount}}}"
        ));
        let _ = NearToken::from_yoctonear(0); // keep NearToken linked for clarity
    }

    pub fn withdraw(&mut self, share_amount: u64) {
        if share_amount == 0 {
            env::panic_str("zero shares");
        }
        let who = env::predecessor_account_id();
        let cur = self.shares.get(&who).copied().unwrap_or(0);
        if cur < share_amount {
            env::panic_str("insufficient shares");
        }
        self.shares.insert(who.clone(), cur - share_amount);
        self.total_deposits = self
            .total_deposits
            .checked_sub(share_amount)
            .unwrap_or_else(|| env::panic_str("deposits underflow"));
        self.total_shares = self
            .total_shares
            .checked_sub(share_amount)
            .unwrap_or_else(|| env::panic_str("shares underflow"));
        env::log_str(&format!(
            "{{\"event\":\"Withdraw\",\"depositor\":\"{who}\",\"amount\":{share_amount}}}"
        ));
        // Compare scenario does not require real NEAR refund transfer.
    }

    pub fn get_shares(&self, account_id: AccountId) -> u64 {
        self.shares.get(&account_id).copied().unwrap_or(0)
    }

    pub fn get_total_deposits(&self) -> u64 {
        self.total_deposits
    }

    /// PF-compatible view name used by dual-deploy scenario checks.
    pub fn total_deposits(&self) -> u64 {
        self.total_deposits
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    fn ctx(pred: &str, deposit: u128) {
        let mut b = VMContextBuilder::new();
        b.predecessor_account_id(pred.parse().unwrap());
        b.attached_deposit(NearToken::from_yoctonear(deposit));
        testing_env!(b.build());
    }

    #[test]
    fn deposit_withdraw() {
        ctx("alice.testnet", 50);
        let mut c = StakingVault::init();
        c.deposit();
        let alice: AccountId = "alice.testnet".parse().unwrap();
        assert_eq!(c.get_shares(alice.clone()), 50);
        assert_eq!(c.get_total_deposits(), 50);
        ctx("alice.testnet", 0);
        c.withdraw(20);
        assert_eq!(c.get_shares(alice), 30);
        assert_eq!(c.get_total_deposits(), 30);
    }
}
