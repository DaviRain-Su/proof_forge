//! near-sdk AccessControl mirror of Stdlib.AccessControl (NEAR lowers .address → u64).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, PanicOnDefault};

const DEFAULT_ADMIN_ROLE: u64 = 0;

fn account_u64(account: &str) -> u64 {
    let h = env::sha256(account.as_bytes());
    u64::from_le_bytes(h[..8].try_into().unwrap())
}

fn role_key(role: u64, who: u64) -> [u8; 16] {
    let mut k = [0u8; 16];
    k[..8].copy_from_slice(&role.to_le_bytes());
    k[8..].copy_from_slice(&who.to_le_bytes());
    k
}

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct AccessControl {
    /// Nested (role, who) → membership (1/0), keyed by 16-byte compound.
    members: LookupMap<[u8; 16], u64>,
}

#[near]
impl AccessControl {
    #[init]
    pub fn init() -> Self {
        let mut members = LookupMap::new(b"r");
        let admin = account_u64(env::predecessor_account_id().as_str());
        members.insert(role_key(DEFAULT_ADMIN_ROLE, admin), 1);
        Self { members }
    }

    pub fn has_role(&self, role: u64, who: u64) -> bool {
        self.members.get(&role_key(role, who)).copied().unwrap_or(0) != 0
    }

    pub fn grant_role(&mut self, role: u64, who: u64) {
        self.assert_admin();
        self.members.insert(role_key(role, who), 1);
    }

    pub fn revoke_role(&mut self, role: u64, who: u64) {
        self.assert_admin();
        self.members.insert(role_key(role, who), 0);
    }

    fn assert_admin(&self) {
        let caller = account_u64(env::predecessor_account_id().as_str());
        if self.members.get(&role_key(DEFAULT_ADMIN_ROLE, caller)).copied().unwrap_or(0) == 0 {
            env::panic_str("AccessControl: missing admin role");
        }
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
    fn admin_grant() {
        ctx("alice.testnet");
        let mut c = AccessControl::init();
        let alice = account_u64("alice.testnet");
        let bob = account_u64("bob.testnet");
        assert!(c.has_role(0, alice));
        c.grant_role(1, bob);
        assert!(c.has_role(1, bob));
        c.revoke_role(1, bob);
        assert!(!c.has_role(1, bob));
    }
}
