//! CosmWasm mock-runtime differential for product StateCell WASM.
//!
//! Reference intent (engineering, not formal TST-SEM-002/003):
//!   init(7) → increment(5) → query get == 12
//!   init(u64::MAX - 7) → increment(8) traps; query still MAX-7
//!
//! Env: `PROOF_FORGE_FIXTURES_DIR` with `StateCell/StateCell.wasm`.
//!
//! Honesty: arithmetic overflow uses Wasm `unreachable` → `VmError` trap.
//! That is **not** `ContractResult::Err` (which is reserved for explicit
//! `revert` → `{"error":...}`). Store is skipped so MockStorage is unchanged.
//! Not wasmd / formal host rollback ceremony.

mod common;

use {
    common::*,
    cosmwasm_std::{ContractResult, Empty, Response},
};

fn state_cell_instance() -> common::CwInstance {
    assert_abi_schema_if_present("StateCell");
    make_instance("StateCell")
}

/// Spec (a): instantiate with initial=7 succeeds; layout marker present; get==7.
#[test]
fn state_cell_instantiate_init_7() {
    let mut instance = state_cell_instance();
    let cr = instantiate_ok(&mut instance, &instantiate_msg_u64("initial", 7));
    let resp = expect_response_ok(cr);
    // Unit init: no synthetic result attribute required.
    assert!(
        resp.messages.is_empty(),
        "init must not enqueue messages: {:?}",
        resp.messages
    );
    assert!(
        has_layout_marker(&mut instance),
        "layout marker must be written on instantiate"
    );
    assert_eq!(read_state0_u64(&mut instance), Some(7));
    assert_eq!(query_u64(&mut instance, "get"), 7);
}

/// Spec (b)+(c): after init(7), increment(5) → result attr 12, get==12.
#[test]
fn state_cell_increment_and_query() {
    let mut instance = state_cell_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 7),
    ));

    let cr = execute_ok(&mut instance, &method_msg("increment", &[("delta", 5)]));
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "12");
    assert_eq!(read_state0_u64(&mut instance), Some(12));
    assert_eq!(query_u64(&mut instance, "get"), 12);
}

/// Spec (d): overflow trap; state holds at UInt64.max−7.
///
/// Product emitter lowers checked add to add+unsigned-carry guard →
/// `unreachable` on overflow. cosmwasm-vm surfaces this as `VmError`, not
/// `ContractResult::Err({"error":...})`. Documented intentional mismatch
/// vs wasmd soft-error UX; still proves store-before-trap absence.
#[test]
fn state_cell_increment_overflow_traps_state_unchanged() {
    let mut instance = state_cell_instance();
    let start = u64::MAX - 7;
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", start),
    ));
    assert_eq!(query_u64(&mut instance, "get"), start);

    let err = execute_trap(
        &mut instance,
        &method_msg("increment", &[("delta", 8)]),
    );
    // Trap class is host-dependent (RuntimeErr / Communication); only require Err.
    let _ = err;

    // State must not advance past start (store after checked add never ran).
    assert_eq!(read_state0_u64(&mut instance), Some(start));
    assert_eq!(query_u64(&mut instance, "get"), start);
}

/// Happy path multi-step holds: init(0) → inc(1) → inc(2) → get 3; result attrs.
#[test]
fn state_cell_multi_increment_result_attributes() {
    let mut instance = state_cell_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 0),
    ));

    let r1 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("increment", &[("delta", 1)]),
    ));
    assert_attr(&r1, "result", "1");

    let r2 = expect_response_ok(execute_ok(
        &mut instance,
        &method_msg("increment", &[("delta", 2)]),
    ));
    assert_attr(&r2, "result", "3");
    assert_eq!(query_u64(&mut instance, "get"), 3);
}

/// Unknown execute method → ContractResult::Err("") (empty error JSON from emitter).
#[test]
fn state_cell_unknown_execute_is_contract_err() {
    let mut instance = state_cell_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 1),
    ));
    let cr: ContractResult<Response<Empty>> =
        execute_ok(&mut instance, br#"{"no_such_method":{}}"#);
    match cr {
        ContractResult::Err(e) => {
            // Emitter builds {"error":""} for miss; message may be empty.
            assert!(
                e.is_empty() || e.contains("error") || e.contains("unknown"),
                "unexpected err text: {e:?}"
            );
        }
        ContractResult::Ok(r) => panic!("unknown method must be ContractResult::Err, got {r:?}"),
    }
}
