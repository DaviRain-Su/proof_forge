//! CosmWasm mock-runtime differential for product Accumulator WASM.
//!
//! Same add/overflow shape as Counter (init seed / entry add / view current).
//! Engineering only — not wasmd / formal.

mod common;

use common::*;

fn accumulator_instance() -> common::CwInstance {
    assert_abi_schema_if_present("Accumulator");
    make_instance("Accumulator")
}

#[test]
fn accumulator_add_and_query() {
    let mut instance = accumulator_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("seed", 10),
    ));
    assert_eq!(query_u64(&mut instance, "current"), 10);

    let resp = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("add", &[("amount", 5)]),
    ));
    assert_attr(&resp, "result", "15");
    assert_eq!(read_state0_u64(&mut instance), Some(15));
    assert_eq!(query_u64(&mut instance, "current"), 15);
}

/// Overflow trap holds total (store-after-add never commits).
#[test]
fn accumulator_add_overflow_traps_state_unchanged() {
    let mut instance = accumulator_instance();
    let start = u64::MAX - 3;
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("seed", start),
    ));

    let _err = execute_trap(&mut instance, &method_msg("add", &[("amount", 4)]));

    assert_eq!(read_state0_u64(&mut instance), Some(start));
    assert_eq!(query_u64(&mut instance, "current"), start);
}
