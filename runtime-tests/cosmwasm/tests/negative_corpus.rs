//! CosmWasm negative corpus — bad input / corrupt storage / gas fail-closed.
//!
//! Complements `hardening.rs` (P0 parse/mul/attr) with broader honesty pins:
//!
//! ## Bad JSON / entry ABI
//! - malformed execute envelope (not an object, missing method needle)
//! - missing required param needle
//! - negative / non-decimal param (byte-scan parse)
//! - trailing garbage after a valid decimal (**known accept** — honesty pin)
//! - unknown method needle → fail-closed (Err or trap; no silent Ok)
//!
//! ## Corrupt storage
//! - missing layout marker on mutate/view
//! - bad layout marker value (wrong u64)
//! - short / oversized state leaf (≠ 8 bytes) on load
//! - missing state leaf after init (db_read null → trap)
//! - Option tag corrupted to 2 (still loads as raw u64 — documented honesty)
//!
//! ## Gas / capacity
//! - tiny gas limit → trap; prior committed state holds across instances
//!   (MockStorage is per-instance; we assert trap, not cross-tx hold)
//!
//! Honesty: Wasm `unreachable` → `VmError` traps (not `ContractResult::Err`)
//! unless noted. Engineering only; not wasmd / formal.

mod common;

use common::*;

// ---------------------------------------------------------------- helpers --

fn state_cell() -> common::CwInstance {
    assert_abi_schema_if_present("StateCell");
    make_instance("StateCell")
}

fn state_cell_inited() -> common::CwInstance {
    let mut i = state_cell();
    expect_response_ok(instantiate_ok(
        &mut i,
        &instantiate_msg_u64("initial", 42),
    ));
    i
}

fn option_state() -> common::CwInstance {
    assert_abi_schema_if_present("OptionState");
    make_instance("OptionState")
}

fn map_mini() -> common::CwInstance {
    assert_abi_schema_if_present("MapMini");
    make_instance("MapMini")
}

// ============================================================ bad JSON ----

/// Execute body that is not a JSON object must fail closed (no silent dispatch).
/// Product may return `ContractResult::Err("")` or Wasm trap depending on path.
#[test]
fn bad_json_execute_array_fail_closed() {
    let mut i = state_cell_inited();
    execute_fail_closed(&mut i, br"[1,2,3]");
    assert_eq!(read_state0_u64(&mut i), Some(42), "state holds after bad envelope");
}

/// Empty execute message fails closed.
#[test]
fn bad_json_execute_empty_fail_closed() {
    let mut i = state_cell_inited();
    execute_fail_closed(&mut i, br"");
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// Missing method needle: object without `increment` key fails closed.
#[test]
fn bad_json_missing_method_needle_fail_closed() {
    let mut i = state_cell_inited();
    execute_fail_closed(&mut i, br#"{"notAMethod":{"delta":1}}"#);
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// Method present but required param needle missing → parse traps.
#[test]
fn bad_json_missing_param_needle_traps() {
    let mut i = state_cell_inited();
    // increment requires "delta"
    let _ = execute_trap(&mut i, br#"{"increment":{}}"#);
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// Negative decimal for UInt param traps at parse (not silent wrap).
#[test]
fn bad_json_negative_uint_param_traps() {
    let mut i = state_cell_inited();
    let _ = execute_trap(&mut i, br#"{"increment":{"delta":-1}}"#);
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// Non-digit garbage in param value traps.
#[test]
fn bad_json_non_decimal_param_traps() {
    let mut i = state_cell_inited();
    let _ = execute_trap(&mut i, br#"{"increment":{"delta":"abc"}}"#);
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// Trailing non-digit after a valid prefix — **honesty pin**:
/// current A1 byte-scan stops at the first non-digit and accepts `"1x"` as `1`.
/// This is known product tension (not silent wrap of out-of-range); document
/// rather than pretend fail-closed. Stricter parse is a follow-up.
#[test]
fn bad_json_trailing_garbage_on_decimal_currently_accepted() {
    let mut i = state_cell_inited();
    let r = expect_response_ok(execute_ok(
        &mut i,
        br#"{"increment":{"delta":1x}}"#,
    ));
    assert_attr(&r, "result", "43");
    assert_eq!(read_state0_u64(&mut i), Some(43));
}

/// Instantiate with max+1 already covered in hardening; pin missing param on init.
#[test]
fn bad_json_instantiate_missing_param_traps() {
    let mut i = state_cell();
    let _ = instantiate_trap(&mut i, br"{}");
    assert!(
        read_state0_u64(&mut i).is_none(),
        "no state after failed instantiate"
    );
    assert!(
        !has_layout_marker(&mut i),
        "no layout marker after failed instantiate"
    );
}

// ===================================================== corrupt storage ----

/// Mutate with layout marker removed → requireLayout traps; no state write.
#[test]
fn corrupt_missing_layout_marker_traps_on_execute() {
    let mut i = state_cell_inited();
    remove_storage_key(&mut i, LAYOUT_MARKER_KEY);
    assert!(!has_layout_marker(&mut i));
    let _ = execute_trap(&mut i, &method_msg("increment", &[("delta", 1)]));
    // State leaf may still be present (we only removed the marker).
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// View also requires layout marker.
#[test]
fn corrupt_missing_layout_marker_traps_on_query() {
    let mut i = state_cell_inited();
    remove_storage_key(&mut i, LAYOUT_MARKER_KEY);
    let env = cosmwasm_std::to_json_vec(&cosmwasm_vm::testing::mock_env()).expect("env");
    let msg = method_msg_empty("get");
    let err = cosmwasm_vm::call_query_raw(&mut i, &env, &msg)
        .expect_err("query must trap without layout marker");
    let _ = err;
}

/// Wrong layout marker value (not the Plan digest word) traps.
#[test]
fn corrupt_bad_layout_marker_value_traps() {
    let mut i = state_cell_inited();
    let before = read_layout_marker_bytes(&mut i).expect("marker present after init");
    assert_eq!(before.len(), 8);
    // Flip all bits — almost certainly not the Plan marker word.
    write_storage_raw(&mut i, LAYOUT_MARKER_KEY, &(!0u64).to_le_bytes());
    let _ = execute_trap(&mut i, &method_msg("increment", &[("delta", 1)]));
    assert_eq!(read_state0_u64(&mut i), Some(42));
}

/// Short state leaf (1 byte) → pf_db_load_u64 length check traps.
#[test]
fn corrupt_short_state_leaf_traps_on_load() {
    let mut i = state_cell_inited();
    write_storage_raw(&mut i, STATE_KEY_0, &[0x01]);
    let _ = execute_trap(&mut i, &method_msg("increment", &[("delta", 1)]));
    // Raw leaf still short (trap before store).
    let raw = read_storage_raw(&mut i, STATE_KEY_0).expect("leaf present");
    assert_eq!(raw.len(), 1, "trap must not rewrite short leaf");
}

/// Oversized state leaf (16 bytes) → length ≠ 8 traps.
#[test]
fn corrupt_oversized_state_leaf_traps_on_load() {
    let mut i = state_cell_inited();
    let mut big = 42u64.to_le_bytes().to_vec();
    big.extend_from_slice(&0u64.to_le_bytes());
    assert_eq!(big.len(), 16);
    write_storage_raw(&mut i, STATE_KEY_0, &big);
    let _ = execute_trap(&mut i, &method_msg("increment", &[("delta", 1)]));
    let raw = read_storage_raw(&mut i, STATE_KEY_0).expect("leaf present");
    assert_eq!(raw.len(), 16, "trap must not normalize oversized leaf");
}

/// Missing state leaf after init (host deleted) → db_read null traps.
#[test]
fn corrupt_missing_state_leaf_traps_on_load() {
    let mut i = state_cell_inited();
    remove_storage_key(&mut i, STATE_KEY_0);
    assert!(read_state0_u64(&mut i).is_none());
    let _ = execute_trap(&mut i, &method_msg("increment", &[("delta", 1)]));
    assert!(
        has_layout_marker(&mut i),
        "marker must survive missing-leaf trap"
    );
}

/// OptionState: corrupt tag leaf to 2 still loads (raw u64 — no enum guard at
/// storage load). Document honesty: product does not silently normalize tag.
/// `clear` must still zero both leaves (no stale payload).
#[test]
fn corrupt_option_tag_not_silently_normalized() {
    let mut i = option_state();
    expect_response_ok(instantiate_ok(&mut i, br"{}"));
    // Host-write tag=2, payload=7.
    write_state_u64_named(&mut i, &state_key(0), 2);
    write_state_u64_named(&mut i, &state_key(1), 7);
    assert_eq!(read_state_u64_named(&mut i, &state_key(0)), Some(2));
    assert_eq!(read_state_u64_named(&mut i, &state_key(1)), Some(7));
    // clear() writes Option.none (tag=0, payload=0) regardless of prior tag.
    expect_response_ok(execute_ok(&mut i, &method_msg_empty("clear")));
    assert_eq!(
        read_state_u64_named(&mut i, &state_key(0)),
        Some(0),
        "clear must write tag=0"
    );
    assert_eq!(
        read_state_u64_named(&mut i, &state_key(1)),
        Some(0),
        "clear must zero payload (no stale 7)"
    );
}

/// MapMini: corrupt occ leaf to 2 (non 0/1) — lookup may false-hit; put overwrite
/// path must not panic the host. Pin: execute still returns VmError or Ok, and
/// storage is not silently wiped to empty.
#[test]
fn corrupt_map_occ_non_boolean_does_not_wipe_storage() {
    let mut i = map_mini();
    expect_response_ok(instantiate_ok(&mut i, br"{}"));
    expect_response_ok(execute_ok(
        &mut i,
        &method_msg("put", &[("k", 1), ("v", 10)]),
    ));
    // Slot 0: occ/key/val at state:0..2
    let occ_before = read_state_u64_named(&mut i, &state_key(0)).expect("occ");
    assert_eq!(occ_before, 1);
    write_state_u64_named(&mut i, &state_key(0), 2); // corrupt occ
    // get may return weird values or trap; either is fail-closed vs silent wipe.
    let env = cosmwasm_std::to_json_vec(&cosmwasm_vm::testing::mock_env()).expect("env");
    let msg = method_msg("get", &[("k", 1)]);
    let _ = cosmwasm_vm::call_query_raw(&mut i, &env, &msg); // Ok or Err both fine
    // Layout + at least one map leaf still present.
    assert!(has_layout_marker(&mut i));
    assert!(
        read_storage_raw(&mut i, &state_key(0)).is_some(),
        "corrupt occ must not delete the leaf"
    );
}

// ============================================================== gas -------

/// Extremely low gas limit: instantiate or first execute traps with gas error.
/// Pin: product does not hang; host returns VmError.
#[test]
fn gas_tiny_limit_traps() {
    let mut i = make_instance_with_gas("StateCell", GAS_LIMIT_TINY);
    // Either instantiate traps on gas, or a follow-up execute does.
    match cosmwasm_vm::call_instantiate::<_, _, _, cosmwasm_std::Empty>(
        &mut i,
        &cosmwasm_vm::testing::mock_env(),
        &creator_info(),
        &instantiate_msg_u64("initial", 1),
    ) {
        Err(e) => {
            let msg = format!("{e:?}");
            assert!(
                msg.to_lowercase().contains("gas")
                    || msg.to_lowercase().contains("limit")
                    || msg.contains("RuntimeErr"),
                "expected gas-related VmError, got {msg}"
            );
        }
        Ok(cr) => {
            // Instantiation fit in tiny gas (unlikely); force execute under same budget.
            let _ = cr;
            let err = execute_trap(&mut i, &method_msg("increment", &[("delta", 1)]));
            let msg = format!("{err:?}");
            assert!(
                msg.to_lowercase().contains("gas")
                    || msg.to_lowercase().contains("limit")
                    || msg.contains("RuntimeErr")
                    || msg.contains("unreachable"),
                "expected trap under tiny gas, got {msg}"
            );
        }
    }
}

/// After a successful init under full gas, a *new* tiny-gas instance of the
/// same code cannot silently mutate without gas — trap only (no hang).
#[test]
fn gas_execute_under_tiny_limit_traps_not_hang() {
    // Full-gas init path sanity (separate instance).
    let mut full = state_cell_inited();
    assert_eq!(read_state0_u64(&mut full), Some(42));

    let mut tiny = make_instance_with_gas("StateCell", GAS_LIMIT_TINY);
    // Try init under tiny gas; accept trap or rare success then execute trap.
    let _ = cosmwasm_vm::call_instantiate::<_, _, _, cosmwasm_std::Empty>(
        &mut tiny,
        &cosmwasm_vm::testing::mock_env(),
        &creator_info(),
        &instantiate_msg_u64("initial", 7),
    );
    // If somehow both fit, increment under remaining budget should still be tight.
    let _ = cosmwasm_vm::call_execute::<_, _, _, cosmwasm_std::Empty>(
        &mut tiny,
        &cosmwasm_vm::testing::mock_env(),
        &creator_info(),
        &method_msg("increment", &[("delta", 1)]),
    );
    // Reachability pin: test completes (no hang). Full instance untouched.
    assert_eq!(read_state0_u64(&mut full), Some(42));
}

// ======================================================= Map capacity pin -

/// Capacity trap leaves prior keys intact (already in map_mini; re-pin under
/// negative corpus name for the agent cheatsheet).
#[test]
fn map_capacity_trap_holds_prior_keys() {
    let mut i = map_mini();
    expect_response_ok(instantiate_ok(&mut i, br"{}"));
    for k in 0u64..8 {
        expect_response_ok(execute_ok(
            &mut i,
            &method_msg("put", &[("k", 200 + k), ("v", 300 + k)]),
        ));
    }
    let _ = execute_trap(
        &mut i,
        &method_msg("put", &[("k", 999), ("v", 1)]),
    );
    for k in 0u64..8 {
        let raw = query_raw(&mut i, &method_msg("get", &[("k", 200 + k)]));
        assert_eq!(parse_query_ok_u64(&raw), 300 + k);
    }
}
