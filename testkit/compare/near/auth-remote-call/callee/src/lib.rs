//! Peer for AuthRemoteCall: `receive` reads LE u64 amount from input body.

use near_sdk::{env, near};

#[near(contract_state)]
#[derive(Default)]
pub struct Callee {
    total: u64,
    hits: u64,
}

#[near]
impl Callee {
    #[init]
    pub fn new() -> Self {
        Self::default()
    }

    /// Accepts raw LE u64 amount (ProofForge promise args) or empty body (amount=0).
    pub fn receive(&mut self) -> u64 {
        let amount = env::input()
            .and_then(|b| {
                if b.len() >= 8 {
                    Some(u64::from_le_bytes(b[..8].try_into().ok()?))
                } else {
                    None
                }
            })
            .unwrap_or(0);
        self.total = self.total.saturating_add(amount);
        self.hits = self.hits.saturating_add(1);
        amount
    }

    pub fn total(&self) -> u64 {
        self.total
    }

    pub fn hits(&self) -> u64 {
        self.hits
    }
}
