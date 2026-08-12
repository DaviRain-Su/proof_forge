//! Token fixture: Map UInt64→UInt64 balances + supply (cap-8 loop IR).
//!
//! Pins:
//!   * init empty supply / balanceOf → 0
//!   * mint new account + mint existing (overwrite path)
//!   * transfer existing→existing and existing→new
//!   * insufficient balance traps; state holds
//!   * capacity-8: 8 distinct balance keys ok; 9th mint traps and prior holds
//!
//! Engineering only. Not wasmd / formal.

mod common;

use common::*;

fn token_instance() -> common::CwInstance {
    assert_abi_schema_if_present("Token");
    make_instance("Token")
}

fn instantiate_token(instance: &mut common::CwInstance) {
    expect_response_ok(instantiate_ok(instance, br"{}"));
}

fn query_balance(instance: &mut common::CwInstance, who: u64) -> u64 {
    let raw = query_raw(instance, &method_msg("balanceOf", &[("who", who)]));
    parse_query_ok_u64(&raw)
}

fn query_total(instance: &mut common::CwInstance) -> u64 {
    query_u64(instance, "total")
}

#[test]
fn token_init_empty() {
    let mut instance = token_instance();
    instantiate_token(&mut instance);
    assert!(has_layout_marker(&mut instance));
    assert_eq!(query_total(&mut instance), 0);
    assert_eq!(query_balance(&mut instance, 1), 0);
}

#[test]
fn token_mint_and_balance() {
    let mut instance = token_instance();
    instantiate_token(&mut instance);

    let r = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("mint", &[("to", 7), ("amount", 100)]),
    ));
    assert_attr(&r, "result", "100");
    assert_eq!(query_total(&mut instance), 100);
    assert_eq!(query_balance(&mut instance, 7), 100);
    assert_eq!(query_balance(&mut instance, 8), 0);

    // Second mint to same account (update path).
    let r2 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("mint", &[("to", 7), ("amount", 50)]),
    ));
    assert_attr(&r2, "result", "150");
    assert_eq!(query_total(&mut instance), 150);
    assert_eq!(query_balance(&mut instance, 7), 150);
}

#[test]
fn token_transfer_existing_to_existing_and_new() {
    let mut instance = token_instance();
    instantiate_token(&mut instance);
    expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("mint", &[("to", 1), ("amount", 100)]),
    ));
    expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("mint", &[("to", 2), ("amount", 10)]),
    ));

    // existing → existing
    let r = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("transfer", &[("src", 1), ("dst", 2), ("amount", 40)]),
    ));
    assert_attr(&r, "result", "1");
    assert_eq!(query_balance(&mut instance, 1), 60);
    assert_eq!(query_balance(&mut instance, 2), 50);
    assert_eq!(query_total(&mut instance), 110);

    // existing → new
    let r2 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("transfer", &[("src", 1), ("dst", 3), ("amount", 20)]),
    ));
    assert_attr(&r2, "result", "1");
    assert_eq!(query_balance(&mut instance, 1), 40);
    assert_eq!(query_balance(&mut instance, 3), 20);
    assert_eq!(query_total(&mut instance), 110);
}

#[test]
fn token_transfer_insufficient_traps_state_holds() {
    let mut instance = token_instance();
    instantiate_token(&mut instance);
    expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("mint", &[("to", 1), ("amount", 30)]),
    ));
    let _ = execute_trap(
        &mut instance,
        &method_msg("transfer", &[("src", 1), ("dst", 2), ("amount", 31)]),
    );
    assert_eq!(query_balance(&mut instance, 1), 30);
    assert_eq!(query_balance(&mut instance, 2), 0);
    assert_eq!(query_total(&mut instance), 30);
}

#[test]
fn token_transfer_missing_src_traps() {
    let mut instance = token_instance();
    instantiate_token(&mut instance);
    let _ = execute_trap(
        &mut instance,
        &method_msg("transfer", &[("src", 99), ("dst", 1), ("amount", 1)]),
    );
    assert_eq!(query_total(&mut instance), 0);
}

/// Cap-8 balances: 8 distinct mint keys ok; 9th traps and prior holds.
#[test]
fn token_ninth_account_mint_traps_state_holds() {
    let mut instance = token_instance();
    instantiate_token(&mut instance);
    for i in 0u64..8 {
        expect_response_ok(execute_ok(
            &mut instance,
            &method_msg("mint", &[("to", 10 + i), ("amount", 1 + i)]),
        ));
    }
    for i in 0u64..8 {
        assert_eq!(query_balance(&mut instance, 10 + i), 1 + i);
    }
    let supply = query_total(&mut instance);
    assert_eq!(supply, (1 + 8) * 8 / 2);

    let _ = execute_trap(
        &mut instance,
        &method_msg("mint", &[("to", 999), ("amount", 1)]),
    );
    for i in 0u64..8 {
        assert_eq!(
            query_balance(&mut instance, 10 + i),
            1 + i,
            "account slot {i} must hold after capacity trap"
        );
    }
    assert_eq!(query_balance(&mut instance, 999), 0);
    assert_eq!(query_total(&mut instance), supply);
}
