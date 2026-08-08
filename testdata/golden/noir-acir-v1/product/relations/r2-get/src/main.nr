fn main(pre_initialized: pub bool, pre_s0: pub u64, post_s0: pub u64, post_initialized: pub bool, result: pub u64) {
    assert(pre_initialized == true);
    assert(post_s0 == pre_s0);
    assert(post_initialized == true);
    assert(result == pre_s0);
}
