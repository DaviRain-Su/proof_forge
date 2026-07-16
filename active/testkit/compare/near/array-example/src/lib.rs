//! near-sdk ArrayExample — fixed [u64;3] locals matching Product ArrayExample.

use near_sdk::near;

#[near(contract_state)]
#[derive(Default)]
pub struct ArrayExample {}

#[near]
impl ArrayExample {
    pub fn size_of3(&self) -> u64 {
        3
    }

    pub fn get_elem(&self) -> u64 {
        let xs: [u64; 3] = [10, 20, 30];
        xs[1]
    }

    pub fn sum_of3(&self) -> u64 {
        let xs: [u64; 3] = [10, 20, 30];
        xs[0] + xs[1] + xs[2]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    #[test]
    fn values() {
        testing_env!(VMContextBuilder::new().build());
        let c = ArrayExample::default();
        assert_eq!(c.size_of3(), 3);
        assert_eq!(c.get_elem(), 20);
        assert_eq!(c.sum_of3(), 60);
    }
}
