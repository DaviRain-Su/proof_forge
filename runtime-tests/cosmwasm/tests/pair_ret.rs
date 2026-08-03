//! PairRet fixture: named Struct entry/view returns multi-leaf JSON decimal array.
//!
//! Wire (B-RET-ABI, CosmWasm):
//! - execute setPair → Response attribute `result` = `"[x,y]"` (JSON array of
//!   decimal strings, generalizing the scalar `result="<decimal>"` path)
//! - query getPair → raw `{"ok":"[x,y]"}` (ok is a string containing a JSON array)
//!
//! Engineering only: cosmwasm-vm 3.0.9 mock. Not wasmd / formal.

mod common;

use {
    common::*,
    serde_json::Value,
};

fn pair_instance() -> common::CwInstance {
    assert_abi_schema_if_present("PairRet");
    make_instance("PairRet")
}

/// Flat instantiate with two u64 params (x, y).
fn instantiate_pair(instance: &mut common::CwInstance, x: u64, y: u64) {
    let msg = serde_json::to_vec(&serde_json::json!({ "x": x, "y": y }))
        .expect("instantiate pair json");
    expect_response_ok(instantiate_ok(instance, &msg));
}

/// Parse multi-leaf result attribute value `"[n0,n1,...]"` → Vec<u64>.
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

/// Parse query ok multi-leaf: `{"ok":"[n0,n1,...]"}` (ok is a string).
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
fn pair_ret_init_query_and_set() {
    let mut instance = pair_instance();
    instantiate_pair(&mut instance, 3, 5);

    // State leaves: p_a @ state:0, p_b @ state:1
    assert_eq!(read_state0_u64(&mut instance), Some(3));
    assert_eq!(
        read_state_u64_named(&mut instance, "pf:cw:v1:state:1"),
        Some(5)
    );

    // Query getPair → {"ok":"[3,5]"}
    let raw = query_raw(&mut instance, &method_msg_empty("getPair"));
    let leaves = parse_query_ok_array(&raw);
    assert_eq!(leaves, vec![3, 5], "getPair after init raw={}", String::from_utf8_lossy(&raw));

    // Execute setPair(11, 22) → result attr "[11,22]"
    let cr = execute_ok(
        &mut instance,
        &method_msg("setPair", &[("x", 11), ("y", 22)]),
    );
    let resp = expect_response_ok(cr);
    let result = attr_value(&resp, "result").expect("setPair result attribute");
    assert_eq!(
        parse_result_array(&result),
        vec![11, 22],
        "setPair result attr={result:?}"
    );
    assert_eq!(read_state0_u64(&mut instance), Some(11));
    assert_eq!(
        read_state_u64_named(&mut instance, "pf:cw:v1:state:1"),
        Some(22)
    );

    // Query again
    let raw2 = query_raw(&mut instance, &method_msg_empty("getPair"));
    assert_eq!(
        parse_query_ok_array(&raw2),
        vec![11, 22],
        "getPair after set raw={}",
        String::from_utf8_lossy(&raw2)
    );
}

#[test]
fn pair_ret_byte_for_byte_query_payload() {
    let mut instance = pair_instance();
    instantiate_pair(&mut instance, 7, 9);
    let raw = query_raw(&mut instance, &method_msg_empty("getPair"));
    // Exact MVP wire: ok is a quoted JSON-array-of-decimals string.
    assert_eq!(
        raw.as_slice(),
        br#"{"ok":"[7,9]"}"#,
        "query payload must be exact byte-for-byte; got {}",
        String::from_utf8_lossy(&raw)
    );
}
