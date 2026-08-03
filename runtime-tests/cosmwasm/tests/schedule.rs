//! ScheduleFlow fixture: schedule → Response.messages[0] SubMsg with Binary msg.
//!
//! Product CosmWasm emitter packs WasmMsg::Execute.msg as cosmwasm-std Binary
//! (base64 of UTF-8 JSON `{"daily":{"a0":N}}`). cosmwasm-vm deserializes the
//! ContractResult; we assert id/reply_on/contract_addr/funds and that
//! Binary decodes to the expected JSON. Engineering only — not wasmd/formal.

mod common;

use {
    common::*,
    cosmwasm_std::{CosmosMsg, ReplyOn, WasmMsg},
};

fn schedule_instance() -> common::CwInstance {
    assert_abi_schema_if_present("ScheduleFlow");
    make_instance("ScheduleFlow")
}

/// init(5) → later() enqueues one SubMsg; state becomes 6; peek == 6.
/// messages[0]: id=0, reply_on=Never, WasmMsg::Execute {
///   contract_addr = "ledger.daily",
///   msg = Binary(b`{"daily":{"a0":5}}`),
///   funds = [],
/// }.
#[test]
fn schedule_submsg_binary_msg_decodes_to_method_json() {
    let mut instance = schedule_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("x", 5),
    ));
    assert_eq!(query_u64(&mut instance, "peek"), 5);

    let resp = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg_empty("later"),
    ));

    // Parent body continues after schedule: count := count + 1; return count.
    assert_attr(&resp, "result", "6");
    assert_eq!(read_state0_u64(&mut instance), Some(6));
    assert_eq!(query_u64(&mut instance, "peek"), 6);

    assert_eq!(
        resp.messages.len(),
        1,
        "later must enqueue exactly one SubMsg: {:?}",
        resp.messages
    );
    let sub = &resp.messages[0];
    assert_eq!(sub.id, 0, "UNUSED_MSG_ID");
    assert_eq!(sub.reply_on, ReplyOn::Never);
    assert_eq!(sub.gas_limit, None, "gas_limit omitted → None");

    match &sub.msg {
        CosmosMsg::Wasm(WasmMsg::Execute {
            contract_addr,
            msg,
            funds,
        }) => {
            assert_eq!(
                contract_addr, "ledger.daily",
                "contract_addr is static QN stub (not bech32)"
            );
            assert!(funds.is_empty(), "funds must be empty: {funds:?}");
            // Binary: cosmwasm-vm already base64-decoded into raw bytes.
            let decoded = String::from_utf8(msg.to_vec()).unwrap_or_else(|e| {
                panic!(
                    "Binary msg not UTF-8: {e}; raw={:?}",
                    msg.as_slice()
                )
            });
            assert_eq!(
                decoded, r#"{"daily":{"a0":5}}"#,
                "Binary msg must decode to method-keyed JSON with count at schedule time"
            );
        }
        other => panic!("expected WasmMsg::Execute, got {other:?}"),
    }
}

/// init(0) → later() Binary encodes a0=0; empty-ish but valid decimal.
#[test]
fn schedule_submsg_binary_zero_arg_decimal() {
    let mut instance = schedule_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("x", 0),
    ));

    let resp = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg_empty("later"),
    ));
    assert_eq!(resp.messages.len(), 1);
    match &resp.messages[0].msg {
        CosmosMsg::Wasm(WasmMsg::Execute { msg, .. }) => {
            let decoded = String::from_utf8(msg.to_vec()).expect("utf-8");
            assert_eq!(decoded, r#"{"daily":{"a0":0}}"#);
        }
        other => panic!("expected WasmMsg::Execute, got {other:?}"),
    }
}
