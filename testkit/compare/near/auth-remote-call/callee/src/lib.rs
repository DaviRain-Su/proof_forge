//! Peer for AuthRemoteCall: `receive` reads the canonical JSON-array body.

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

    /// Accepts the portable wasm-near crosscall ABI: a one-element JSON array.
    pub fn receive(&mut self) -> u64 {
        let amount = env::input()
            .as_deref()
            .and_then(parse_amount)
            .unwrap_or_else(|| env::panic_str("expected JSON args [amount]"));
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

fn parse_amount(bytes: &[u8]) -> Option<u64> {
    let args: Vec<u64> = near_sdk::serde_json::from_slice(bytes).ok()?;
    match args.as_slice() {
        [amount] => Some(*amount),
        _ => None,
    }
}
