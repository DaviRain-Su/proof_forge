//! near-sdk-rs RoleGatedToken mirror of `Examples/Product/RoleGatedToken.lean`.
//!
//! Role membership is a flat map keyed by `"{role}:{account_id}"` for simplicity
//! (PF uses nested mapKey path storage). Scenario is the same.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, AccountId, PanicOnDefault};

pub const ADMIN_ROLE: u64 = 0;
pub const MINTER_ROLE: u64 = 1;

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct RoleGatedToken {
    total_supply: u64,
    balances: LookupMap<AccountId, u64>,
    role_members: LookupMap<String, u64>,
}

fn role_key(role: u64, who: &AccountId) -> String {
    format!("{role}:{who}")
}

#[near]
impl RoleGatedToken {
    #[init]
    pub fn init() -> Self {
        let admin = env::predecessor_account_id();
        let mut role_members = LookupMap::new(b"r");
        role_members.insert(role_key(ADMIN_ROLE, &admin), 1);
        Self {
            total_supply: 0,
            balances: LookupMap::new(b"b"),
            role_members,
        }
    }

    fn assert_role(&self, role: u64) {
        let who = env::predecessor_account_id();
        if self.role_members.get(&role_key(role, &who)).copied().unwrap_or(0) == 0 {
            env::panic_str("missing role");
        }
    }

    pub fn grant_role(&mut self, role: u64, who: AccountId) {
        self.assert_role(ADMIN_ROLE);
        self.role_members.insert(role_key(role, &who), 1);
        env::log_str(&format!(
            "{{\"event\":\"RoleGranted\",\"role\":{role},\"who\":\"{who}\"}}"
        ));
    }

    pub fn mint(&mut self, recipient: AccountId, amount: u64) {
        self.assert_role(MINTER_ROLE);
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
            "{{\"event\":\"Transfer\",\"from\":0,\"to\":\"{recipient}\",\"amount\":{amount}}}"
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
        let dst = self.balances.get(&recipient).copied().unwrap_or(0);
        self.balances.insert(sender.clone(), src - amount);
        self.balances.insert(
            recipient.clone(),
            dst.checked_add(amount)
                .unwrap_or_else(|| env::panic_str("overflow")),
        );
        env::log_str(&format!(
            "{{\"event\":\"Transfer\",\"from\":\"{sender}\",\"to\":\"{recipient}\",\"amount\":{amount}}}"
        ));
    }

    pub fn balance_of(&self, who: AccountId) -> u64 {
        self.balances.get(&who).copied().unwrap_or(0)
    }

    pub fn total_supply(&self) -> u64 {
        self.total_supply
    }

    pub fn has_role(&self, role: u64, who: AccountId) -> bool {
        self.role_members
            .get(&role_key(role, &who))
            .copied()
            .unwrap_or(0)
            != 0
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
    fn admin_grant_mint_transfer() {
        ctx("alice.testnet");
        let mut c = RoleGatedToken::init();
        let alice: AccountId = "alice.testnet".parse().unwrap();
        let bob: AccountId = "bob.testnet".parse().unwrap();
        c.grant_role(MINTER_ROLE, alice.clone());
        c.mint(alice.clone(), 100);
        assert_eq!(c.balance_of(alice.clone()), 100);
        c.transfer(bob.clone(), 30);
        assert_eq!(c.balance_of(alice), 70);
        assert_eq!(c.balance_of(bob), 30);
        assert_eq!(c.total_supply(), 100);
    }
}
