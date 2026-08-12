//! MapMini fixture: dense Map UInt64→UInt64 cap-8 (occ/key/val × 8 = 24 leaves).
//!
//! CosmWasm host gate: cosmwasm-vm MAX_LOCALS=100. Loop IR Map lookup/upsert
//! keeps put/get under the limit (pure-expr upsert at cap-8 does not).
//!
//! Pins:
//!   * init empty → get(k)=0
//!   * put/get/overwrite
//!   * capacity-8: 8 distinct keys ok; 9th traps and prior holds
//!
//! Engineering only. Map **return** stays fail-closed.

mod common;

use common::*;

fn map_instance() -> common::CwInstance {
    assert_abi_schema_if_present("MapMini");
    make_instance("MapMini")
}

fn instantiate_empty(instance: &mut common::CwInstance) {
    expect_response_ok(instantiate_ok(instance, br"{}"));
}

fn query_get(instance: &mut common::CwInstance, k: u64) -> u64 {
    let raw = query_raw(instance, &method_msg("get", &[("k", k)]));
    parse_query_ok_u64(&raw)
}

#[test]
fn map_mini_empty_get_zero() {
    let mut instance = map_instance();
    instantiate_empty(&mut instance);
    assert!(has_layout_marker(&mut instance));
    assert_eq!(query_get(&mut instance, 0), 0);
    assert_eq!(query_get(&mut instance, 42), 0);
}

#[test]
fn map_mini_put_get_overwrite() {
    let mut instance = map_instance();
    instantiate_empty(&mut instance);

    let r = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("put", &[("k", 7), ("v", 99)]),
    ));
    assert_attr(&r, "result", "99");
    assert_eq!(query_get(&mut instance, 7), 99);
    assert_eq!(query_get(&mut instance, 8), 0);

    let r2 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("put", &[("k", 7), ("v", 3)]),
    ));
    assert_attr(&r2, "result", "3");
    assert_eq!(query_get(&mut instance, 7), 3);
}

#[test]
fn map_mini_multiple_keys() {
    let mut instance = map_instance();
    instantiate_empty(&mut instance);
    for i in 0u64..8 {
        expect_response_ok(execute_ok(
            &mut instance,
            &method_msg("put", &[("k", i + 1), ("v", (i + 1) * 10)]),
        ));
    }
    for i in 0u64..8 {
        assert_eq!(query_get(&mut instance, i + 1), (i + 1) * 10);
    }
    assert_eq!(query_get(&mut instance, 99), 0);
}

/// Dense Map CosmWasm pilot capacity is 8 slots; the 9th distinct key must trap.
#[test]
fn map_mini_ninth_key_traps_state_holds() {
    let mut instance = map_instance();
    instantiate_empty(&mut instance);
    for i in 0u64..8 {
        expect_response_ok(execute_ok(
            &mut instance,
            &method_msg("put", &[("k", 100 + i), ("v", 1000 + i)]),
        ));
    }
    for i in 0u64..8 {
        assert_eq!(query_get(&mut instance, 100 + i), 1000 + i);
    }

    let _ = execute_trap(
        &mut instance,
        &method_msg("put", &[("k", 999), ("v", 1)]),
    );

    for i in 0u64..8 {
        assert_eq!(
            query_get(&mut instance, 100 + i),
            1000 + i,
            "slot {i} must hold after capacity trap"
        );
    }
    assert_eq!(query_get(&mut instance, 999), 0);
}
