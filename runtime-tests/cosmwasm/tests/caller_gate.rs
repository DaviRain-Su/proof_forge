//! ADR-0031 S1: CallerGate mock-runtime gate — context.caller binds
//! CosmWasm MessageInfo.sender as Principal wire identity
//! (`u32le(len) || utf8`, len + 8×u64 LE body leaves, zero-padded).
//!
//! Covers:
//!   * instantiate records creator as owner
//!   * onlyOwner succeeds for matching sender
//!   * onlyOwner traps (assert → unreachable) for mismatched sender;
//!     owner state holds (full snapshot rollback of the failed execute)
//!   * setOwner rebinds owner; subsequent onlyOwner requires new sender
//!   * multi-word bech32-shaped senders exercise leaf packing + zero pad
//!   * invalid/escaped/non-bech32 senders trap at `$pf_dst_check` before
//!     Principal globals are published (ADR-0031 bech32 UTF-8 bind)
//!   * mixed execute dispatcher: non-caller `ping` does not load sender
//!     and succeeds even with invalid sender bytes
//!
//! Honest scope: cosmwasm-vm MockStorage/Api; assert failure uses Wasm
//! `unreachable` → `VmError` trap (not ContractResult::Err).
//! Not wasmd / formal Reference↔host closure.

mod common;

use {
    common::*,
    cosmwasm_std::{ContractResult, Empty, Response},
    cosmwasm_vm::{
        call_execute, call_instantiate,
        testing::{mock_env, mock_info},
    },
};

const OWNER: &str = "creator";
const STRANGER: &str = "stranger";
/// Longer bech32-shaped sender to exercise multi-word Principal packing
/// and high-word zero padding (len=20 < 64).
const OWNER_LONG: &str = "cosmos1owner0000000001";
const STRANGER_LONG: &str = "cosmos1stranger00000002";
/// Uppercase bech32-shaped bytes — fails `$pf_dst_check` charset gate.
const INVALID_UPPER: &str = "COSMOS1OWNER0000000001";
/// Punctuation / non-[a-z0-9] — fails charset gate.
const INVALID_PUNCT: &str = "creator!";
/// Backslash byte in sender: JSON encodes as `\\`; helper copies raw
/// JSON string bytes including `0x5c`, which `$pf_dst_check` rejects.
const INVALID_ESCAPE: &str = "cre\\ator";

fn gate_instance() -> common::CwInstance {
    assert_abi_schema_if_present("CallerGate");
    make_instance("CallerGate")
}

/// Instantiate with empty msg `{}` (init has zero params).
fn instantiate_as(instance: &mut CwInstance, sender: &str) -> ContractResult<Response<Empty>> {
    call_instantiate::<_, _, _, Empty>(instance, &mock_env(), &mock_info(sender, &[]), b"{}")
        .unwrap_or_else(|e| panic!("instantiate VmError: {e:?}"))
}

fn instantiate_trap_as(instance: &mut CwInstance, sender: &str) {
    match call_instantiate::<_, _, _, Empty>(instance, &mock_env(), &mock_info(sender, &[]), b"{}")
    {
        Err(_) => {}
        Ok(cr) => panic!("expected instantiate Wasm trap VmError, got ContractResult {cr:?}"),
    }
}

fn execute_as(
    instance: &mut CwInstance,
    sender: &str,
    msg: &[u8],
) -> ContractResult<Response<Empty>> {
    call_execute::<_, _, _, Empty>(instance, &mock_env(), &mock_info(sender, &[]), msg)
        .unwrap_or_else(|e| panic!("execute VmError: {e:?}"))
}

fn execute_trap_as(instance: &mut CwInstance, sender: &str, msg: &[u8]) {
    match call_execute::<_, _, _, Empty>(instance, &mock_env(), &mock_info(sender, &[]), msg) {
        Err(_) => {}
        Ok(cr) => panic!("expected Wasm trap VmError, got ContractResult {cr:?}"),
    }
}

/// Spec (a): instantiate as OWNER succeeds; layout marker present; peek==0.
#[test]
fn caller_gate_instantiate_records_owner() {
    let mut instance = gate_instance();
    let cr = instantiate_as(&mut instance, OWNER);
    let resp = expect_response_ok(cr);
    assert!(
        resp.messages.is_empty(),
        "init must not enqueue messages: {:?}",
        resp.messages
    );
    assert!(
        has_layout_marker(&mut instance),
        "layout marker must be written on instantiate"
    );
    assert_eq!(query_u64(&mut instance, "peek"), 0);
}

/// Spec (b): onlyOwner as matching sender succeeds (result attr "1").
#[test]
fn caller_gate_only_owner_match() {
    let mut instance = gate_instance();
    expect_response_ok(instantiate_as(&mut instance, OWNER));

    let cr = execute_as(&mut instance, OWNER, &method_msg_empty("onlyOwner"));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");
    assert_eq!(query_u64(&mut instance, "peek"), 0);
}

/// Spec (c): onlyOwner as stranger traps; owner unchanged so OWNER still
/// succeeds afterwards (failed execute full snapshot rollback).
#[test]
fn caller_gate_only_owner_mismatch_traps_state_holds() {
    let mut instance = gate_instance();
    expect_response_ok(instantiate_as(&mut instance, OWNER));

    execute_trap_as(&mut instance, STRANGER, &method_msg_empty("onlyOwner"));

    // Owner still OWNER: matching sender succeeds after the trap.
    let cr = execute_as(&mut instance, OWNER, &method_msg_empty("onlyOwner"));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");
}

/// Spec (d): setOwner rebinds; only the new sender may pass onlyOwner.
#[test]
fn caller_gate_set_owner_rebind() {
    let mut instance = gate_instance();
    expect_response_ok(instantiate_as(&mut instance, OWNER));

    let cr = execute_as(&mut instance, STRANGER, &method_msg_empty("setOwner"));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");

    // Old owner rejected.
    execute_trap_as(&mut instance, OWNER, &method_msg_empty("onlyOwner"));
    // New owner accepted.
    let cr = execute_as(&mut instance, STRANGER, &method_msg_empty("onlyOwner"));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");
}

/// Spec (e): multi-word bech32-shaped senders (len=20) exercise body packing
/// + high-word zero padding; match/mismatch still exact.
#[test]
fn caller_gate_long_sender_leaf_pack() {
    let mut instance = gate_instance();
    expect_response_ok(instantiate_as(&mut instance, OWNER_LONG));

    let cr = execute_as(
        &mut instance,
        OWNER_LONG,
        &method_msg_empty("onlyOwner"),
    );
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");

    execute_trap_as(
        &mut instance,
        STRANGER_LONG,
        &method_msg_empty("onlyOwner"),
    );

    // Rebind to stranger_long and confirm.
    expect_response_ok(execute_as(
        &mut instance,
        STRANGER_LONG,
        &method_msg_empty("setOwner"),
    ));
    expect_response_ok(execute_as(
        &mut instance,
        STRANGER_LONG,
        &method_msg_empty("onlyOwner"),
    ));
    execute_trap_as(&mut instance, OWNER_LONG, &method_msg_empty("onlyOwner"));
}

/// Spec (f): invalid / escaped / non-bech32 sender bytes trap at
/// `$pf_dst_check` inside `$pf_load_caller_principal` (caller-using paths).
/// Valid long bech32-shaped sender remains positive (see spec e).
#[test]
fn caller_gate_invalid_sender_charset_traps() {
    // Instantiate with uppercase sender: init uses caller → trap before state.
    {
        let mut instance = gate_instance();
        instantiate_trap_as(&mut instance, INVALID_UPPER);
        assert!(
            !has_layout_marker(&mut instance),
            "failed instantiate must not write layout marker"
        );
    }
    // Instantiate with punctuation.
    {
        let mut instance = gate_instance();
        instantiate_trap_as(&mut instance, INVALID_PUNCT);
    }
    // Instantiate with backslash (JSON-escaped in info region).
    {
        let mut instance = gate_instance();
        instantiate_trap_as(&mut instance, INVALID_ESCAPE);
    }
    // Valid instantiate, then onlyOwner with invalid senders traps; owner holds.
    let mut instance = gate_instance();
    expect_response_ok(instantiate_as(&mut instance, OWNER));
    execute_trap_as(
        &mut instance,
        INVALID_UPPER,
        &method_msg_empty("onlyOwner"),
    );
    execute_trap_as(
        &mut instance,
        INVALID_PUNCT,
        &method_msg_empty("onlyOwner"),
    );
    execute_trap_as(
        &mut instance,
        INVALID_ESCAPE,
        &method_msg_empty("onlyOwner"),
    );
    // Matching valid sender still succeeds after charset traps.
    let cr = execute_as(&mut instance, OWNER, &method_msg_empty("onlyOwner"));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");
}

/// Spec (g): mixed execute dispatcher — `ping` never reads context.caller,
/// so it must not invoke `$pf_load_caller_principal` and must succeed even
/// when MessageInfo.sender carries invalid/escaped/non-bech32 bytes.
#[test]
fn caller_gate_ping_skips_caller_load() {
    let mut instance = gate_instance();
    expect_response_ok(instantiate_as(&mut instance, OWNER));

    // Valid sender: ping returns 1.
    let cr = execute_as(&mut instance, OWNER, &method_msg_empty("ping"));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "1");

    // Invalid senders must not trap on the non-caller branch.
    for bad in [INVALID_UPPER, INVALID_PUNCT, INVALID_ESCAPE] {
        let cr = execute_as(&mut instance, bad, &method_msg_empty("ping"));
        let resp = expect_response_ok(cr);
        assert_attr(&resp, "result", "1");
    }

    // onlyOwner still enforces charset on the caller branch.
    execute_trap_as(
        &mut instance,
        INVALID_UPPER,
        &method_msg_empty("onlyOwner"),
    );
}
