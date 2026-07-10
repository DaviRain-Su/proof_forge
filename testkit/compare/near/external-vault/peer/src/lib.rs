//! Mock vault: deposit(assets,receiver LE) records assets; 1:1 shares.

use near_sdk::{env, near};

#[near(contract_state)]
#[derive(Default)]
pub struct VaultPeer {
    total_assets: u64,
    hits: u64,
}

#[near]
impl VaultPeer {
    #[init]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn deposit(&mut self) -> u64 {
        let (assets, _recv) = parse_two_u64();
        self.total_assets = self.total_assets.saturating_add(assets);
        self.hits = self.hits.saturating_add(1);
        assets // 1:1 shares
    }

    pub fn convert_to_shares(&self) -> u64 {
        parse_one_u64()
    }

    pub fn total_assets(&self) -> u64 {
        self.total_assets
    }

    pub fn hits(&self) -> u64 {
        self.hits
    }
}

fn parse_one_u64() -> u64 {
    let b = env::input().unwrap_or_default();
    if b.len() >= 8 {
        u64::from_le_bytes(b[0..8].try_into().unwrap_or([0; 8]))
    } else {
        0
    }
}

fn parse_two_u64() -> (u64, u64) {
    let b = env::input().unwrap_or_default();
    if b.len() >= 16 {
        let a = u64::from_le_bytes(b[0..8].try_into().unwrap_or([0; 8]));
        let r = u64::from_le_bytes(b[8..16].try_into().unwrap_or([0; 8]));
        (a, r)
    } else {
        (0, 0)
    }
}
