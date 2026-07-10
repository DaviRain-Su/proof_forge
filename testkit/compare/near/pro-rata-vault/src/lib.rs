//! near-sdk ProRataVault mirror of Examples/Product/ProRataVault.lean.

#![allow(clippy::needless_pass_by_value)]

use near_sdk::store::LookupMap;
use near_sdk::{env, near, PanicOnDefault};

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ProRataVault {
    total_assets: u64,
    total_supply: u64,
    share_balances: LookupMap<u64, u64>,
}

fn account_u64(account: &str) -> u64 {
    let h = env::sha256(account.as_bytes());
    u64::from_le_bytes(h[..8].try_into().unwrap())
}

#[near]
impl ProRataVault {
    #[init]
    pub fn init() -> Self {
        Self {
            total_assets: 0,
            total_supply: 0,
            share_balances: LookupMap::new(b"s"),
        }
    }

    pub fn total_assets(&self) -> u64 { self.total_assets }
    pub fn total_supply(&self) -> u64 { self.total_supply }

    pub fn balance_of(&self, who: u64) -> u64 {
        self.share_balances.get(&who).copied().unwrap_or(0)
    }

    pub fn convert_to_shares(&self, assets: u64) -> u64 {
        if self.total_supply == 0 || self.total_assets == 0 {
            assets
        } else {
            assets.saturating_mul(self.total_supply) / self.total_assets
        }
    }

    pub fn convert_to_assets(&self, shares: u64) -> u64 {
        if self.total_supply == 0 || self.total_assets == 0 {
            shares
        } else {
            shares.saturating_mul(self.total_assets) / self.total_supply
        }
    }

    pub fn donate(&mut self, assets: u64) {
        assert!(assets > 0, "zero assets");
        self.total_assets = self.total_assets.saturating_add(assets);
    }

    pub fn deposit(&mut self, assets: u64) {
        assert!(assets > 0, "zero assets");
        let shares = self.convert_to_shares(assets);
        assert!(shares > 0, "zero shares");
        let who = account_u64(env::predecessor_account_id().as_str());
        let bal = self.share_balances.get(&who).copied().unwrap_or(0);
        self.share_balances.insert(who, bal.saturating_add(shares));
        self.total_assets = self.total_assets.saturating_add(assets);
        self.total_supply = self.total_supply.saturating_add(shares);
    }

    pub fn withdraw(&mut self, shares: u64) {
        assert!(shares > 0, "zero shares");
        let who = account_u64(env::predecessor_account_id().as_str());
        let bal = self.share_balances.get(&who).copied().unwrap_or(0);
        assert!(bal >= shares, "insufficient shares");
        let assets = self.convert_to_assets(shares);
        self.share_balances.insert(who, bal - shares);
        self.total_supply = self.total_supply.saturating_sub(shares);
        self.total_assets = self.total_assets.saturating_sub(assets);
    }
}
