fn main(pre_initialized: pub bool, pre_s0: pub u64, arg_p0: pub u64, post_s0: pub u64, post_initialized: pub bool, result: pub u64) {
    assert(pre_initialized == true);
    let t0: u64 = pre_s0 + arg_p0;
    assert(post_s0 == t0);
    assert(post_initialized == true);
    assert(result == t0);
}
