module proof_forge::counter {
    use std::signer;

    struct Counter has key {
        count: u64
    }

    public entry fun initialize(account: &signer) {
        move_to(account, Counter { count: 0 })
    }

    public entry fun increment(account: &signer) acquires Counter {
        let counter = borrow_global_mut<Counter>(signer::address_of(account));
        counter.count = counter.count + 1;
    }

    #[view]
    public fun value(addr: address): u64 acquires Counter {
        borrow_global<Counter>(addr).count
    }
}
