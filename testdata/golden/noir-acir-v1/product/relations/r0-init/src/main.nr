fn main(pre_initialized: pub bool, arg_p0: pub u64, post_s0: pub u64, post_initialized: pub bool) {
    assert(pre_initialized == false);
    assert(post_s0 == arg_p0);
    assert(post_initialized == true);
}
