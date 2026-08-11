//! ConstAnswer fixture: scalar `const ANSWER : UInt64 := 42` via Op.Constant.
//!
//! Wire (scalar MVP):
//! - instantiate unit → stored=0
//! - query get → {"ok":"0"}
//! - execute answer → result attr "42", stored=42
//! - execute answer again → result "84"
//!
//! Engineering only: cosmwasm-vm 3.0.9 mock. Not wasmd / formal.

mod common;

use common::*;

fn const_instance() -> common::CwInstance {
    assert_abi_schema_if_present("ConstAnswer");
    make_instance("ConstAnswer")
}

#[test]
fn const_answer_init_get_zero() {
    let mut instance = const_instance();
    let cr = instantiate_ok(&mut instance, br"{}");
    let _ = expect_response_ok(cr);
    assert!(has_layout_marker(&mut instance), "layout marker on instantiate");
    assert_eq!(read_state0_u64(&mut instance), Some(0));
    assert_eq!(query_u64(&mut instance, "get"), 0);
}

#[test]
fn const_answer_adds_forty_two() {
    let mut instance = const_instance();
    expect_response_ok(instantiate_ok(&mut instance, br"{}"));

    let r1 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg_empty("answer"),
    ));
    assert_attr(&r1, "result", "42");
    assert_eq!(read_state0_u64(&mut instance), Some(42));
    assert_eq!(query_u64(&mut instance, "get"), 42);

    let r2 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg_empty("answer"),
    ));
    assert_attr(&r2, "result", "84");
    assert_eq!(query_u64(&mut instance, "get"), 84);
}
