//! near-sdk OwnableHash — owner = sha256(predecessor account id) as 32 bytes.
//! Mirrors `ProofForge.Contract.Stdlib.OwnableHash` / Product OwnableHash.

use near_sdk::env;
use near_sdk::near;

#[near(contract_state)]
#[derive(Default)]
pub struct OwnableHash {
    owner: [u8; 32],
    initialized: bool,
}

#[near]
impl OwnableHash {
    pub fn init(&mut self) {
        if self.initialized {
            env::panic_str("already initialized");
        }
        self.owner = env::sha256_array(env::predecessor_account_id().as_bytes());
        self.initialized = true;
    }

    pub fn owner(&self) -> Vec<u8> {
        self.owner.to_vec()
    }

    pub fn renounce_ownership(&mut self) {
        self.assert_owner();
        self.owner = [0u8; 32];
    }

    fn assert_owner(&self) {
        let who = env::sha256_array(env::predecessor_account_id().as_bytes());
        if who != self.owner {
            env::panic_str("Ownable: caller is not the owner");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    fn ctx(pred: &str) {
        let mut b = VMContextBuilder::new();
        b.predecessor_account_id(pred.parse().unwrap());
        testing_env!(b.build());
    }

    #[test]
    fn init_renounce() {
        ctx("alice.testnet");
        let mut c = OwnableHash::default();
        c.init();
        let o = c.owner();
        assert_eq!(o.len(), 32);
        assert_ne!(o, vec![0u8; 32]);
        c.renounce_ownership();
        assert_eq!(c.owner(), vec![0u8; 32]);
    }
}
