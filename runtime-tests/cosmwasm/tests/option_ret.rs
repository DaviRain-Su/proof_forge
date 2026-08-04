//! OptionRet fixture: anonymous Option UInt64 tag+payload returns
//! (N-ANON-RESULT / BL-22).
//!
//! Wire (same idiom as PairRet / B-RET-ABI):
//! - none = (0, 0) → query `{"ok":"[0,0]"}`
//! - some v = (1, v) → execute result `"[1,v]"` / query `{"ok":"[1,v]"}`
//!
//! Engineering only: cosmwasm-vm 3.0.9 mock. Not wasmd / formal.

mod common;

use {
    common::*,
    serde_json::Value,
};

fn option_instance() -> common::CwInstance {
    assert_abi_schema_if_present("OptionRet");
    make_instance("OptionRet")
}

fn instantiate_seed(instance: &mut common::CwInstance, x: u64) {
    let msg = serde_json::to_vec(&serde_json::json!({ "x": x })).expect("instantiate seed json");
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
fn option_ret_none_and_some_of_seed() {
    let mut instance = option_instance();
    instantiate_seed(&mut instance, 42);
    assert_eq!(read_state0_u64(&mut instance), Some(42));

    // asNone → (0, 0)
    let raw_none = query_raw(&mut instance, &method_msg_empty("asNone"));
    assert_eq!(
        parse_query_ok_array(&raw_none),
        vec![0, 0],
        "asNone raw={}",
        String::from_utf8_lossy(&raw_none)
    );
    assert_eq!(
        raw_none.as_slice(),
        br#"{"ok":"[0,0]"}"#,
        "asNone exact payload; got {}",
        String::from_utf8_lossy(&raw_none)
    );

    // asSomeOfSeed → (1, 42)
    let raw_some = query_raw(&mut instance, &method_msg_empty("asSomeOfSeed"));
    assert_eq!(
        parse_query_ok_array(&raw_some),
        vec![1, 42],
        "asSomeOfSeed raw={}",
        String::from_utf8_lossy(&raw_some)
    );
    assert_eq!(
        raw_some.as_slice(),
        br#"{"ok":"[1,42]"}"#,
        "asSomeOfSeed exact payload; got {}",
        String::from_utf8_lossy(&raw_some)
    );
}

#[test]
fn option_ret_as_some_execute_result() {
    let mut instance = option_instance();
    instantiate_seed(&mut instance, 7);

    let cr = execute_ok(
        &mut instance,
        &method_msg("asSome", &[("v", 99)]),
    );
    let resp = expect_response_ok(cr);
    let result = attr_value(&resp, "result").expect("asSome result attribute");
    assert_eq!(
        parse_result_array(&result),
        vec![1, 99],
        "asSome(99) result attr={result:?}"
    );
    // asSome does not mutate seed
    assert_eq!(read_state0_u64(&mut instance), Some(7));
}
