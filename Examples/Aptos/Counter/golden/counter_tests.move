#[test_only]
module proof_forge::counter_tests {
    use proof_forge::counter;
    use std::signer;

    #[test(account = @0xCAFE)]
    fun test_lifecycle(account: &signer) {
        let addr = signer::address_of(account);
        counter::initialize(account);
        assert!(counter::value(addr) == 0, 0);
        counter::increment(account);
        assert!(counter::value(addr) == 1, 1);
        counter::increment(account);
        assert!(counter::value(addr) == 2, 2);
    }
}
