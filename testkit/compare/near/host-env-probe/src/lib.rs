//! near-sdk HostEnvProbe — snapshot block_timestamp / block_height / self / predecessor.
//! Mirrors Product HostEnvProbe portable triad fields (u64 projections where needed).

use near_sdk::{env, near};

#[near(contract_state)]
#[derive(Default)]
pub struct HostEnvProbe {
    last_time: u64,
    last_height: u64,
    last_self: u64,
    last_caller: u64,
}

fn account_u64(account: &str) -> u64 {
    let h = env::sha256(account.as_bytes());
    u64::from_le_bytes(h[..8].try_into().unwrap())
}

#[near]
impl HostEnvProbe {
    pub fn initialize(&mut self) {
        self.last_time = 0;
        self.last_height = 0;
        self.last_self = 0;
        self.last_caller = 0;
    }

    pub fn snapshot(&mut self) {
        self.last_time = env::block_timestamp();
        self.last_height = env::block_height();
        // contractId projection: first 8 LE of sha256(current account)
        self.last_self = account_u64(env::current_account_id().as_str());
        self.last_caller = account_u64(env::predecessor_account_id().as_str());
    }

    pub fn get_time(&self) -> u64 {
        self.last_time
    }

    pub fn get_height(&self) -> u64 {
        self.last_height
    }

    pub fn get_self(&self) -> u64 {
        self.last_self
    }

    pub fn get_caller(&self) -> u64 {
        self.last_caller
    }
}
