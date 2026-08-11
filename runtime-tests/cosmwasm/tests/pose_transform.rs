//! PoseTransform fixture: named Struct Pose {x,y : Int64} translate/rotate90/scale.
//!
//! Wire honesty:
//!   * CosmWasm multi-leaf result uses **unsigned** decimal formatting of the
//!     i64 bit pattern (`pf_fmt_u64`). Negative Int64 appears as large u64
//!     decimals (two's complement), not with a leading `-`.
//!   * Tests decode leaves via `as i64` so rotate90 negative coords are honest.
//!
//! Engineering only: cosmwasm-vm 3.0.9 mock. Not wasmd / formal.

mod common;

use {
    common::*,
    serde_json::Value,
};

fn pose_instance() -> common::CwInstance {
    assert_abi_schema_if_present("PoseTransform");
    make_instance("PoseTransform")
}

fn instantiate_pose(instance: &mut common::CwInstance, x: i64, y: i64) {
    // JSON numbers: positive path uses ordinary decimals; negatives use signed JSON.
    let msg = serde_json::to_vec(&serde_json::json!({ "x0": x, "y0": y }))
        .expect("instantiate pose json");
    expect_response_ok(instantiate_ok(instance, &msg));
}

/// Parse multi-leaf result / query as Int64 pair (u64 bit-pattern → i64).
fn parse_i64_array(s: &str) -> Vec<i64> {
    let v: Value = serde_json::from_str(s).unwrap_or_else(|e| {
        panic!("result attr not JSON array string {s:?}: {e}")
    });
    match v {
        Value::Array(items) => items
            .into_iter()
            .map(|item| match item {
                // Product wire uses unsigned decimal of the i64 bit pattern.
                Value::Number(n) => {
                    if let Some(u) = n.as_u64() {
                        u as i64
                    } else if let Some(i) = n.as_i64() {
                        i
                    } else {
                        panic!("leaf not integer: {n}")
                    }
                }
                Value::String(s) => {
                    if let Ok(u) = s.parse::<u64>() {
                        u as i64
                    } else if let Ok(i) = s.parse::<i64>() {
                        i
                    } else {
                        panic!("leaf string not int: {s:?}")
                    }
                }
                other => panic!("unexpected leaf JSON: {other:?}"),
            })
            .collect(),
        other => panic!("result attr must be JSON array, got {other:?} from {s:?}"),
    }
}

fn parse_query_ok_i64_array(raw: &[u8]) -> Vec<i64> {
    let v: Value = serde_json::from_slice(raw).expect("query json");
    match v {
        Value::Object(map) => {
            if let Some(Value::String(s)) = map.get("ok") {
                return parse_i64_array(s);
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

fn query_pose(instance: &mut common::CwInstance) -> (i64, i64) {
    let raw = query_raw(instance, &method_msg_empty("getPose"));
    let leaves = parse_query_ok_i64_array(&raw);
    assert_eq!(leaves.len(), 2, "getPose must return 2 leaves; raw={}", String::from_utf8_lossy(&raw));
    (leaves[0], leaves[1])
}

fn exec_result_pose(instance: &mut common::CwInstance, msg: &[u8]) -> (i64, i64) {
    let resp = expect_response_ok(execute_ok(instance, msg));
    let result = attr_value(&resp, "result").expect("pose result attribute");
    let leaves = parse_i64_array(&result);
    assert_eq!(leaves.len(), 2, "pose result must be 2 leaves; got {result:?}");
    (leaves[0], leaves[1])
}

#[test]
fn pose_init_get_and_translate() {
    let mut instance = pose_instance();
    instantiate_pose(&mut instance, 3, 5);
    assert_eq!(query_pose(&mut instance), (3, 5));
    assert_eq!(read_state0_i64(&mut instance), Some(3));
    assert_eq!(
        read_state_u64_named(&mut instance, "pf:cw:v1:state:1").map(|v| v as i64),
        Some(5)
    );

    let (x, y) = exec_result_pose(
        &mut instance,
        &method_msg("translate", &[("dx", 1), ("dy", 2)]),
    );
    assert_eq!((x, y), (4, 7));
    assert_eq!(query_pose(&mut instance), (4, 7));
}

#[test]
fn pose_rotate90_and_scale() {
    let mut instance = pose_instance();
    // (3, 4) → rotate90 CW → (4, -3)
    instantiate_pose(&mut instance, 3, 4);
    let (x, y) = exec_result_pose(&mut instance, &method_msg_empty("rotate90"));
    assert_eq!((x, y), (4, -3), "rotate90 (x,y)→(y,-x)");
    assert_eq!(query_pose(&mut instance), (4, -3));

    // scale(2) → (8, -6)
    let (x2, y2) = exec_result_pose(
        &mut instance,
        &method_msg("scale", &[("k", 2)]),
    );
    assert_eq!((x2, y2), (8, -6));
    assert_eq!(query_pose(&mut instance), (8, -6));
}

#[test]
fn pose_set_and_scale_overflow_holds() {
    let mut instance = pose_instance();
    instantiate_pose(&mut instance, 1, 1);
    let (x, y) = exec_result_pose(
        &mut instance,
        &method_msg("setPose", &[("x", 100), ("y", 200)]),
    );
    assert_eq!((x, y), (100, 200));

    // Int64 max-ish * large k must trap; state holds prior pose.
    // 2^62 = 4611686018427387904; * 4 overflows signed mul.
    let big: u64 = 1u64 << 62;
    let msg = serde_json::to_vec(&serde_json::json!({
        "setPose": { "x": big, "y": 1 }
    }))
    .expect("setPose big");
    let (bx, by) = exec_result_pose(&mut instance, &msg);
    assert_eq!((bx, by), (big as i64, 1));

    let scale_msg = serde_json::to_vec(&serde_json::json!({
        "scale": { "k": 4 }
    }))
    .expect("scale overflow");
    let _ = execute_trap(&mut instance, &scale_msg);
    assert_eq!(
        query_pose(&mut instance),
        (big as i64, 1),
        "scale overflow must hold prior pose"
    );
}
