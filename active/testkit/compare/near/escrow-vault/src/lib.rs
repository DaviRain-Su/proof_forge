//! near-sdk EscrowVault mirror of Examples/Product/EscrowVault.lean.
//! Two-party internal-ledger escrow (fund → release | refund).

#![allow(clippy::needless_pass_by_value)]

use near_sdk::{near, PanicOnDefault};

const STATUS_EMPTY: u64 = 0;
const STATUS_FUNDED: u64 = 1;
const STATUS_RELEASED: u64 = 2;
const STATUS_REFUNDED: u64 = 3;

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct EscrowVault {
    buyer: u64,
    seller: u64,
    amount: u64,
    status: u64,
    seller_claim: u64,
    buyer_claim: u64,
}

#[near]
impl EscrowVault {
    #[init]
    pub fn init(buyer_id: u64, seller_id: u64) -> Self {
        assert!(buyer_id > 0, "zero buyer");
        assert!(seller_id > 0, "zero seller");
        assert!(buyer_id != seller_id, "same party");
        Self {
            buyer: buyer_id,
            seller: seller_id,
            amount: 0,
            status: STATUS_EMPTY,
            seller_claim: 0,
            buyer_claim: 0,
        }
    }

    pub fn fund(&mut self, amt: u64) {
        assert_eq!(self.status, STATUS_EMPTY, "not empty");
        assert!(amt > 0, "zero amount");
        self.amount = amt;
        self.status = STATUS_FUNDED;
    }

    pub fn release(&mut self) {
        assert_eq!(self.status, STATUS_FUNDED, "not funded");
        self.status = STATUS_RELEASED;
        self.seller_claim = self.amount;
    }

    pub fn refund(&mut self) {
        assert_eq!(self.status, STATUS_FUNDED, "not funded");
        self.status = STATUS_REFUNDED;
        self.buyer_claim = self.amount;
    }

    pub fn get_status(&self) -> u64 {
        self.status
    }

    pub fn get_amount(&self) -> u64 {
        self.amount
    }

    pub fn seller_claim(&self) -> u64 {
        self.seller_claim
    }

    pub fn buyer_claim(&self) -> u64 {
        self.buyer_claim
    }

    pub fn get_buyer(&self) -> u64 {
        self.buyer
    }

    pub fn get_seller(&self) -> u64 {
        self.seller
    }
}
