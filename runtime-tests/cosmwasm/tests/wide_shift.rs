//! WideShiftProbe: CosmWasm body-only UInt128 multiword << / >>.
//!
//! Pins Emit multiword shift path is reachable and count≥128 traps.
//! Engineering only.

mod common;

use common::*;

fn instance() -> common::CwInstance {
    assert_abi_schema_if_present("WideShiftProbe");
    make_instance("WideShiftProbe")
}

fn inited() -> common::CwInstance {
    let mut i = instance();
    expect_response_ok(instantiate_ok(
        &mut i,
        &instantiate_msg_u64("initial", 0),
    ));
    i
}

#[test]
fn wide_shift_left_ok() {
    let mut i = inited();
    let r = expect_response_ok(execute_ok(
        &mut i,
        &method_msg("shiftOneLeft", &[("count", 3)]),
    ));
    assert_attr(&r, "result", "1");
    assert_eq!(query_u64(&mut i, "get"), 1);
}

#[test]
fn wide_shift_right_ok() {
    let mut i = inited();
    let r = expect_response_ok(execute_ok(
        &mut i,
        &method_msg("shiftOneRight", &[("count", 5)]),
    ));
    assert_attr(&r, "result", "1");
}

#[test]
fn wide_shift_max_bit_ok() {
    let mut i = inited();
    let r = expect_response_ok(execute_ok(
        &mut i,
        &method_msg_empty("shiftMaxBit"),
    ));
    assert_attr(&r, "result", "1");
}

/// count = 128 ≥ bitWidth → trap; pad holds.
#[test]
fn wide_shift_count_ge_bitwidth_traps() {
    let mut i = inited();
    let _ = execute_trap(
        &mut i,
        &method_msg("shiftOneLeft", &[("count", 128)]),
    );
    assert_eq!(query_u64(&mut i, "get"), 0, "pad must hold after shift trap");
}

/// 1 << 64 moves into high limb (whole-limb path); must not trap.
#[test]
fn wide_shift_left_whole_limb_ok() {
    let mut i = inited();
    let r = expect_response_ok(execute_ok(
        &mut i,
        &method_msg("shiftOneLeft", &[("count", 64)]),
    ));
    assert_attr(&r, "result", "1");
}
