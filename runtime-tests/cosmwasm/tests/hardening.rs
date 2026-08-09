//! A1-repair hardening differentials (P0-1..P0-4 fixes).
//!
//! P0-2: JSON u64 parse overflow — boundary at UInt64 max/min+1.
//! P0-3: Int64 (-1) × min — silent-wrap hole now traps.
//! P0-4: attribute buffer capacity — bounded-for emit loop now traps instead
//!       of overflowing attr(512) into msg/valueCell buffers.
//!
//! Honesty: all three are Wasm `unreachable` → `VmError` traps (not
//! `ContractResult::Err`); MockStorage stays unchanged where asserted.
//! Engineering only; not wasmd / formal.

mod common;

use common::*;

// ---------------------------------------------------------------- P0-2 ---
/// `pf_parse_u64_field` must accept UInt64.max exactly.
#[test]
fn p02_parse_accepts_u64_max_boundary() {
    let mut instance = make_instance("StateCell");
    let msg = br#"{"initial":18446744073709551615}"#.to_vec();
    let cr = instantiate_ok(&mut instance, &msg);
    expect_response_ok(cr);
    assert_eq!(read_state0_u64(&mut instance), Some(u64::MAX));
}

/// …and must trap (not wrap) on max+1.
#[test]
fn p02_parse_traps_above_u64_max() {
    let mut instance = make_instance("StateCell");
    let msg = br#"{"initial":18446744073709551616}"#.to_vec();
    let _ = instantiate_trap(&mut instance, &msg);
    assert!(
        read_state0_u64(&mut instance).is_none(),
        "no state may be written after parse trap"
    );
}

/// Larger digit strings (e.g. 10^20) must trap as well.
#[test]
fn p02_parse_traps_on_long_decimal_overflow() {
    let mut instance = make_instance("StateCell");
    let msg = br#"{"initial":99999999999999999999}"#.to_vec();
    let _ = instantiate_trap(&mut instance, &msg);
}

// ---------------------------------------------------------------- P0-3 ---
/// `(-1) * Int64.min` used to silently produce `min` (wrapped). The fix
/// guards lhs==-1 && rhs==min with `unreachable`; state must hold.
#[test]
fn p03_neg_one_times_int64_min_traps_state_unchanged() {
    let mut instance = make_instance("IntMul");
    expect_response_ok(instantiate_ok(&mut instance, &instantiate_msg_u64("initial", 0)));
    let _ = execute_trap(&mut instance, &method_msg_empty("armMin"));
    assert_eq!(
        read_state0_i64(&mut instance),
        Some(0),
        "x must stay at its initialized value after mul trap"
    );
}

// ---------------------------------------------------------------- P0-4 ---
/// 40 emits × (4-byte key + ≤48 overhead) ≈ 2 KB >> 512-byte attr buffer.
/// Before the fix this silently bled into the msg/valueCell buffers; now the
/// capacity guard traps mid-loop and `n` never reaches 40.
#[test]
fn p04_emit_loop_traps_on_attr_capacity() {
    let mut instance = make_instance("EmitLoop");
    expect_response_ok(instantiate_ok(&mut instance, &instantiate_msg_u64("initial", 0)));
    let _ = execute_trap(&mut instance, &method_msg_empty("loop"));
    assert_eq!(
        read_state_u64_named(&mut instance, STATE_KEY_0),
        Some(0),
        "n must stay 0 after attr-capacity trap"
    );
}
