//! Peer callee for dual-deploy RemoteCall compare.
//! Zero-arg `remote_call` matches PF empty promise args (empty input body).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::near;

#[near(contract_state)]
#[derive(Default)]
pub struct Callee {
    hits: u64,
}

#[near]
impl Callee {
    #[init]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn remote_call(&mut self) -> u64 {
        self.hits = self.hits.saturating_add(1);
        42
    }
}
