program counter.aleo {
    mapping count: u64 => u64;
    
    @noupgrade
    constructor() {}
    
    fn initialize() -> Final {
        return final {
            Mapping::set(count, 0u64, 0u64);
        };
    }
    fn increment() -> Final {
        return final {
            let n: u64 = Mapping::get_or_use(count, 0u64, 0u64);
            Mapping::set(count, 0u64, (n + 1u64));
        };
    }
    fn get() -> Final {
        return final {
            Mapping::get_or_use(count, 0u64, 0u64);
        };
    }
}