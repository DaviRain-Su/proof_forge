//! EventFlow fixture: emit → Response attributes; revert → `{"error":"Cap"}`.
//!
//! Product CosmWasm emit maps to Response attributes (key = event name, value =
//! first UInt64 arg decimal). Explicit `revert` returns ContractResult::Err
//! with the ErrorDecl name. Engineering mock-runtime only — not wasmd/formal.

mod common;

use common::*;

fn eventflow_instance() -> common::CwInstance {
    assert_abi_schema_if_present("EventFlow");
    make_instance("EventFlow")
}

/// emit Moved then successful store: attribute key=Moved value=<src bal>.
#[test]
fn eventflow_emit_attribute_on_success() {
    let mut instance = eventflow_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 3),
    ));

    let resp = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("move", &[("d", 4)]),
    ));
    // MVP emitter: first emit arg only (src=bal before update = 3).
    assert_attr(&resp, "Moved", "3");
    // Valued entry also appends synthetic result attribute (new bal=7).
    assert_attr(&resp, "result", "7");
    assert_eq!(query_u64(&mut instance, "get"), 7);
}

/// revert Cap(d) → ContractResult::Err("Cap"); state unchanged.
#[test]
fn eventflow_revert_is_contract_err_state_unchanged() {
    let mut instance = eventflow_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 1),
    ));

    // emit runs before the if; revert returns error JSON without applying bal:=.
    // Note: emit attribute is only visible on Ok paths; Err path is error string.
    let cr = execute_ok(&mut instance, &method_msg("move", &[("d", 11)]));
    expect_contract_err(cr, "Cap");

    assert_eq!(read_state0_u64(&mut instance), Some(1));
    assert_eq!(query_u64(&mut instance, "get"), 1);
}
