//! BytesRet fixture: anonymous Bytes 4 state + entry/view return.
//!
//! Wire (N-ANON-RESULT / CosmWasm JSON decimals):
//! - execute setBuf → Response attribute `result` = `"[a,b,c,d]"`
//! - query getBuf → raw `{"ok":"[a,b,c,d]"}` (ok is a string containing a JSON array)
//!
//! Each Bytes leaf is a zero-extended UInt64 JSON decimal (not tight u8 packing).
//! Engineering only: cosmwasm-vm 3.0.9 mock. Not wasmd / formal.

mod common;

use {
    common::*,
    serde_json::Value,
};

fn bytes_instance() -> common::CwInstance {
    assert_abi_schema_if_present("BytesRet");
    make_instance("BytesRet")
}

/// Flat instantiate with four u8 params (a, b, c, d) as JSON decimals.
fn instantiate_bytes(instance: &mut common::CwInstance, a: u64, b: u64, c: u64, d: u64) {
    let msg = serde_json::to_vec(&serde_json::json!({ "a": a, "b": b, "c": c, "d": d }))
        .expect("instantiate bytes json");
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

#[test]
fn bytes_ret_init_query_and_set() {
    let mut instance = bytes_instance();
    instantiate_bytes(&mut instance, 10, 20, 30, 40);

    // Bytes leaves are 1-byte semantic width stored as 8-byte LE KV words.
    assert_eq!(read_state0_u64(&mut instance), Some(10));
    assert_eq!(
        read_state_u64_named(&mut instance, "pf:cw:v1:state:1"),
        Some(20)
    );
    assert_eq!(
        read_state_u64_named(&mut instance, "pf:cw:v1:state:2"),
        Some(30)
    );
    assert_eq!(
        read_state_u64_named(&mut instance, "pf:cw:v1:state:3"),
        Some(40)
    );

    let raw = query_raw(&mut instance, &method_msg_empty("getBuf"));
    let leaves = parse_query_ok_array(&raw);
    assert_eq!(
        leaves,
        vec![10, 20, 30, 40],
        "getBuf after init raw={}",
        String::from_utf8_lossy(&raw)
    );

    let cr = execute_ok(
        &mut instance,
        &method_msg(
            "setBuf",
            &[("a", 1), ("b", 2), ("c", 3), ("d", 4)],
        ),
    );
    let resp = expect_response_ok(cr);
    let result = attr_value(&resp, "result").expect("setBuf result attribute");
    assert_eq!(
        parse_result_array(&result),
        vec![1, 2, 3, 4],
        "setBuf result attr={result:?}"
    );

    let raw2 = query_raw(&mut instance, &method_msg_empty("getBuf"));
    assert_eq!(
        parse_query_ok_array(&raw2),
        vec![1, 2, 3, 4],
        "getBuf after set raw={}",
        String::from_utf8_lossy(&raw2)
    );
}

#[test]
fn bytes_ret_byte_for_byte_query_payload() {
    let mut instance = bytes_instance();
    instantiate_bytes(&mut instance, 7, 8, 9, 10);
    let raw = query_raw(&mut instance, &method_msg_empty("getBuf"));
    assert_eq!(
        raw.as_slice(),
        br#"{"ok":"[7,8,9,10]"}"#,
        "query payload must be exact byte-for-byte; got {}",
        String::from_utf8_lossy(&raw)
    );
}
