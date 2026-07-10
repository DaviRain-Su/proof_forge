//! Minimal FT peer: records transfers; does not enforce NEP-141 deposit rules strictly.

use near_sdk::near;

#[near(contract_state)]
#[derive(Default)]
pub struct FtPeer {
    supply: u64,
    transferred: u64,
    hits: u64,
}

#[near]
impl FtPeer {
    #[init]
    pub fn new() -> Self {
        Self {
            supply: 1_000_000,
            transferred: 0,
            hits: 0,
        }
    }

    pub fn ft_transfer(&mut self, receiver_id: String, amount: String, memo: Option<String>) {
        let _ = (receiver_id, memo);
        let a: u64 = amount.parse().unwrap_or(0);
        self.transferred = self.transferred.saturating_add(a);
        self.hits = self.hits.saturating_add(1);
    }

    pub fn ft_approve_stub(&mut self, account_id: String, amount: String) {
        let _ = (account_id, amount);
        self.hits = self.hits.saturating_add(1);
    }

    pub fn ft_balance_of(&self, account_id: String) -> String {
        let _ = account_id;
        "0".to_string()
    }

    pub fn ft_total_supply(&self) -> String {
        self.supply.to_string()
    }

    pub fn transferred(&self) -> u64 {
        self.transferred
    }

    pub fn hits(&self) -> u64 {
        self.hits
    }
}
