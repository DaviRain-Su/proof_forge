//! OptionState fixture: Option UInt64 state as Enum-shaped tag+payload leaves
//! (B-OPT-STATE / BL-33).
//!
//! Layout (same physical shape as a 1-payload named Enum):
//! - `slot_tag`  @ `pf:cw:v1:state:0` (u64 LE) — 0 = none, 1 = some
//! - `slot_p0`   @ `pf:cw:v1:state:1` (u64 LE) — payload; zeroed on none
//!
//! Pins:
//! - init none → both leaves 0
//! - set(v) → tag=1, payload=v; peek=v; getOpt=[1,v]
//! - clear after some → both leaves 0 (stale payload must not survive)
//!
//! Engineering only: cosmwasm-vm 3.0.9 mock. Not wasmd / formal.

mod common;

use {
    common::*,
    serde_json::Value,
};

fn option_state_instance() -> common::CwInstance {
    assert_abi_schema_if_present("OptionState");
    make_instance("OptionState")
}

/// Zero-arg init: empty JSON object (init has no params).
fn instantiate_empty(instance: &mut common::CwInstance) {
    let msg = serde_json::to_vec(&serde_json::json!({})).expect("empty instantiate json");
    expect_response_ok(instantiate_ok(instance, &msg));
}

fn parse_result_array(s: &str) -> Vec<u64> {
    let v: Value = serde_json::from_str(s).unwrap_or_else(|e| {
        panic!("result attr not JSON array string {s:?}: {e}")
    });
    match v {
        Value::Array(items) => items
            .into_iter()
            .map(|item| match item {
                Value::Number(n) => n
                    .as_u64()
                    .unwrap_or_else(|| panic!("leaf not u64: {n}")),
                Value::String(s) => s
                    .parse::<u64>()
                    .unwrap_or_else(|_| panic!("leaf string not u64: {s:?}")),
                other => panic!("unexpected leaf JSON: {other:?}"),
            })
            .collect(),
        other => panic!("result attr must be JSON array, got {other:?} from {s:?}"),
    }
}

fn parse_query_ok_array(raw: &[u8]) -> Vec<u64> {
    let v: Value = serde_json::from_slice(raw).expect("query json");
    match v {
        Value::Object(map) => {
            if let Some(Value::String(s)) = map.get("ok") {
                return parse_result_array(s);
            }
            if let Some(Value::String(err)) = map.get("error") {
                panic!(
                    "query ContractResult::Err({err}) raw={}",
                    String::from_utf8_lossy(raw)
                );
            }
            panic!("query missing ok/error: {}", String::from_utf8_lossy(raw));
        }
        other => panic!("query not object: {other:?}"),
    }
}

/// Exact 8-byte LE state leaf under `pf:cw:v1:state:{i}`.
fn read_state_leaf(instance: &mut common::CwInstance, idx: usize) -> Option<u64> {
    let key = format!("pf:cw:v1:state:{idx}");
    read_state_u64_named(instance, &key)
}

#[test]
fn option_state_init_none_zero_leaves() {
    let mut instance = option_state_instance();
    instantiate_empty(&mut instance);

    assert!(
        has_layout_marker(&mut instance),
        "layout marker must be written on instantiate"
    );
    // none = (tag=0, payload=0) exact storage bytes.
    assert_eq!(read_state_leaf(&mut instance, 0), Some(0), "init none tag");
    assert_eq!(
        read_state_leaf(&mut instance, 1),
        Some(0),
        "init none payload"
    );

    assert_eq!(query_u64(&mut instance, "peek"), 0, "peek on none");

    let raw = query_raw(&mut instance, &method_msg_empty("getOpt"));
    assert_eq!(
        parse_query_ok_array(&raw),
        vec![0, 0],
        "getOpt after init none raw={}",
        String::from_utf8_lossy(&raw)
    );
    assert_eq!(
        raw.as_slice(),
        br#"{"ok":"[0,0]"}"#,
        "getOpt none exact payload; got {}",
        String::from_utf8_lossy(&raw)
    );
}

#[test]
fn option_state_set_peek_and_get_opt() {
    let mut instance = option_state_instance();
    instantiate_empty(&mut instance);

    let cr = execute_ok(&mut instance, &method_msg("set", &[("v", 99)]));
    let resp = expect_response_ok(cr);
    let result = attr_value(&resp, "result").expect("set result attribute");
    assert_eq!(result, "99", "set(99) result attr={result:?}");

    assert_eq!(
        read_state_leaf(&mut instance, 0),
        Some(1),
        "some tag must be 1"
    );
    assert_eq!(
        read_state_leaf(&mut instance, 1),
        Some(99),
        "some payload must be 99"
    );
    assert_eq!(query_u64(&mut instance, "peek"), 99, "peek after some(99)");

    let raw = query_raw(&mut instance, &method_msg_empty("getOpt"));
    assert_eq!(
        parse_query_ok_array(&raw),
        vec![1, 99],
        "getOpt after some raw={}",
        String::from_utf8_lossy(&raw)
    );
    assert_eq!(
        raw.as_slice(),
        br#"{"ok":"[1,99]"}"#,
        "getOpt some exact payload; got {}",
        String::from_utf8_lossy(&raw)
    );
}

#[test]
fn option_state_clear_zeroes_payload() {
    let mut instance = option_state_instance();
    instantiate_empty(&mut instance);

    let cr = execute_ok(&mut instance, &method_msg("set", &[("v", 42)]));
    let _ = expect_response_ok(cr);
    assert_eq!(read_state_leaf(&mut instance, 0), Some(1));
    assert_eq!(read_state_leaf(&mut instance, 1), Some(42));

    // none-reset must zero the payload leaf (not leave stale 42).
    let cr2 = execute_ok(&mut instance, &method_msg_empty("clear"));
    let resp = expect_response_ok(cr2);
    let result = attr_value(&resp, "result").expect("clear result attribute");
    assert_eq!(result, "0", "clear result attr={result:?}");

    assert_eq!(
        read_state_leaf(&mut instance, 0),
        Some(0),
        "clear tag must be 0"
    );
    assert_eq!(
        read_state_leaf(&mut instance, 1),
        Some(0),
        "clear must zero payload (pin), not leave stale 42"
    );
    assert_eq!(query_u64(&mut instance, "peek"), 0, "peek after clear");

    let raw = query_raw(&mut instance, &method_msg_empty("getOpt"));
    assert_eq!(
        parse_query_ok_array(&raw),
        vec![0, 0],
        "getOpt after clear raw={}",
        String::from_utf8_lossy(&raw)
    );
    assert_eq!(
        raw.as_slice(),
        br#"{"ok":"[0,0]"}"#,
        "getOpt clear exact payload; got {}",
        String::from_utf8_lossy(&raw)
    );
}
