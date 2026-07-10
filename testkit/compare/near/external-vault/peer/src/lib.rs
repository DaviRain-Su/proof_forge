//! Mock vault: deposit([assets,receiver]) records assets; 1:1 shares.

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
    env::input()
        .as_deref()
        .and_then(parse_one_u64_bytes)
        .unwrap_or_else(|| env::panic_str("expected JSON args [value]"))
}

fn parse_two_u64() -> (u64, u64) {
    env::input()
        .as_deref()
        .and_then(parse_two_u64_bytes)
        .unwrap_or_else(|| env::panic_str("expected JSON args [assets,receiver]"))
}

fn parse_one_u64_bytes(bytes: &[u8]) -> Option<u64> {
    let args: Vec<u64> = near_sdk::serde_json::from_slice(bytes).ok()?;
    match args.as_slice() {
        [value] => Some(*value),
        _ => None,
    }
}

fn parse_two_u64_bytes(bytes: &[u8]) -> Option<(u64, u64)> {
    let args: Vec<u64> = near_sdk::serde_json::from_slice(bytes).ok()?;
    match args.as_slice() {
        [first, second] => Some((*first, *second)),
        _ => None,
    }
}
