use proof_forge_counter_stylus::Counter;
use stylus_sdk::{
    alloy_primitives::{B256, U256},
    testing::TestVM,
};

fn word(value: u64) -> B256 {
    B256::from(U256::from(value).to_be_bytes::<32>())
}

#[test]
fn generated_counter_runs_against_test_vm() {
    let vm = TestVM::default();
    let mut counter = Counter::from(&vm);
    counter.initialize();
    assert_eq!(counter.get(), 0);
    counter.increment().unwrap();
    assert_eq!(counter.get(), 1);

    let high = (1_u64 << 40) + 7;
    vm.set_storage(U256::ZERO, word(high));
    assert_eq!(counter.get(), high);

    vm.set_storage(U256::ZERO, word(u64::MAX));
    assert_eq!(
        counter.increment(),
        Err(b"checked arithmetic overflow".to_vec())
    );
    assert_eq!(vm.snapshot().storage.get(&U256::ZERO), Some(&word(u64::MAX)));
}
