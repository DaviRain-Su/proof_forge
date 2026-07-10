//! near-sdk non-transferable token mirror of SoulboundTokenBody.lean.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct SoulboundToken {
    total_supply: u64,
    balances: LookupMap<u64, u64>,
}

fn account_u64(account: &str) -> u64 {
    let h = env::sha256(account.as_bytes());
    u64::from_le_bytes(h[..8].try_into().unwrap())
}

#[near]
impl SoulboundToken {
    #[init]
    pub fn init() -> Self {
        Self {
            total_supply: 0,
            balances: LookupMap::new(b"b"),
        }
    }

    pub fn mint(&mut self, recipient: u64, amount: u64) {
        assert!(amount > 0, "zero amount");
        let bal = self.balances.get(&recipient).copied().unwrap_or(0);
        self.balances.insert(recipient, bal.saturating_add(amount));
        self.total_supply = self.total_supply.saturating_add(amount);
    }

    pub fn burn(&mut self, amount: u64) {
        assert!(amount > 0, "zero amount");
        let who = account_u64(env::predecessor_account_id().as_str());
        let bal = self.balances.get(&who).copied().unwrap_or(0);
        assert!(bal >= amount, "insufficient balance");
        self.balances.insert(who, bal - amount);
        self.total_supply = self.total_supply.saturating_sub(amount);
    }

    pub fn balance_of(&self, who: u64) -> u64 {
        self.balances.get(&who).copied().unwrap_or(0)
    }

    pub fn total_supply(&self) -> u64 {
        self.total_supply
    }
}
