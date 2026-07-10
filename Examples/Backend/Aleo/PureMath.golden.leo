program puremath.aleo {
    @noupgrade
    constructor() {}
    
    fn plus(a: u64, b: u64) -> u64 {
        return (a + b);
    }
    fn max(a: u64, b: u64) -> u64 {
        if (a > b) {
            return a;
        } else {
            return b;
        }
    }
    fn sumFirst10() -> u64 {
        let total: u64 = 0u64;
        for i: u64 in 0u64..10u64 {
            total = (total + i);
        }
        return total;
    }
    fn isEven(n: u64) -> bool {
        return ((n % 2u64) == 0u64);
    }
}
