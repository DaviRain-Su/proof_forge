//! MapDump fixture: dense Map return as flat occ/key/val × 8 JSON decimals.
//!
//! Wire: query `{"ok":"[occ0,key0,val0,...,occ7,key7,val7]"}` (24 u64 leaves).
//! Engineering only.

mod common;

use {
    common::*,
    serde_json::Value,
};

fn map_dump_instance() -> common::CwInstance {
    assert_abi_schema_if_present("MapDump");
    make_instance("MapDump")
}

fn parse_ok_array(raw: &[u8]) -> Vec<u64> {
    let v: Value = serde_json::from_slice(raw).expect("query json");
    let s = match v {
        Value::Object(map) => match map.get("ok") {
            Some(Value::String(s)) => s.clone(),
            Some(other) => panic!("ok not string: {other:?}"),
            None => panic!("missing ok: {}", String::from_utf8_lossy(raw)),
        },
        other => panic!("query not object: {other:?}"),
    };
    let arr: Value = serde_json::from_str(&s).unwrap_or_else(|e| {
        panic!("ok value not JSON array string {s:?}: {e}")
    });
    match arr {
        Value::Array(items) => items
            .into_iter()
            .map(|item| match item {
                Value::Number(n) => n
                    .as_u64()
                    .unwrap_or_else(|| panic!("leaf not u64: {n}")),
                Value::String(s) => s
                    .parse::<u64>()
                    .unwrap_or_else(|_| panic!("leaf string not u64: {s:?}")),
                other => panic!("unexpected leaf: {other:?}"),
            })
            .collect(),
        other => panic!("ok must be array string, got {other:?} from {s:?}"),
    }
}

fn query_dump(instance: &mut common::CwInstance) -> Vec<u64> {
    let raw = query_raw(instance, &method_msg_empty("dump"));
    parse_ok_array(&raw)
}

#[test]
fn map_dump_empty_is_24_zero_leaves() {
    let mut i = map_dump_instance();
    expect_response_ok(instantiate_ok(&mut i, br"{}"));
    let leaves = query_dump(&mut i);
    assert_eq!(leaves.len(), 24, "cap-8 Map = 24 occ/key/val leaves");
    assert!(leaves.iter().all(|&x| x == 0), "empty map all zeros: {leaves:?}");
}

#[test]
fn map_dump_after_puts_shows_occupied_slots() {
    let mut i = map_dump_instance();
    expect_response_ok(instantiate_ok(&mut i, br"{}"));
    expect_response_ok(execute_ok(
        &mut i,
        &method_msg("put", &[("k", 7), ("v", 99)]),
    ));
    expect_response_ok(execute_ok(
        &mut i,
        &method_msg("put", &[("k", 3), ("v", 11)]),
    ));
    let leaves = query_dump(&mut i);
    assert_eq!(leaves.len(), 24);
    // Collect occupied (occ,key,val) triples.
    let mut entries = Vec::new();
    for slot in 0..8 {
        let base = slot * 3;
        let occ = leaves[base];
        let key = leaves[base + 1];
        let val = leaves[base + 2];
        if occ != 0 {
            entries.push((key, val));
        }
    }
    entries.sort_by_key(|(k, _)| *k);
    assert_eq!(entries, vec![(3, 11), (7, 99)], "dump entries={entries:?}");
}
