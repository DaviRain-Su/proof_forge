//! CosmWasm mock-runtime differential for NarrowStateCell (UInt8 multi-width).
//!
//! BL-15: body high-bit overflow trap, JSON param exact range check (no silent
//! truncation), 8-byte physical state slots with high bytes zero.
//! Engineering only — not wasmd / formal.

mod common;

use common::*;

fn narrow_instance() -> common::CwInstance {
    assert_abi_schema_if_present("NarrowStateCell");
    make_instance("NarrowStateCell")
}

/// init(7) → get == 7; state leaf is 8-byte LE with value in low byte.
#[test]
fn narrow_state_cell_init_and_query() {
    let mut instance = narrow_instance();
    let cr = instantiate_ok(&mut instance, &instantiate_msg_u64("initial", 7));
    let resp = expect_response_ok(cr);
    assert!(resp.messages.is_empty(), "init must not enqueue messages: {:?}", resp.messages);
    assert!(
        has_layout_marker(&mut instance),
        "layout marker must be written on instantiate"
    );
    assert_eq!(read_state0_u64(&mut instance), Some(7));
    assert_eq!(query_u64(&mut instance, "get"), 7);
}

/// init(7) → increment(5) → result 12, get == 12.
#[test]
fn narrow_state_cell_increment_and_query() {
    let mut instance = narrow_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 7),
    ));

    let cr = execute_ok(
        &mut instance,
        &method_msg("increment", &[("delta", 5)]),
    );
    let resp = expect_response_ok(cr);
    assert_attr(&resp, "result", "12");
    assert_eq!(read_state0_u64(&mut instance), Some(12));
    assert_eq!(query_u64(&mut instance, "get"), 12);
}

/// UInt8 overflow: init(250) → increment(10) traps; state holds 250.
/// Product emitter: i64.add + high-bit guard (shr_u 8 ≠ 0) → unreachable.
#[test]
fn narrow_state_cell_overflow_traps_state_unchanged() {
    let mut instance = narrow_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 250),
    ));
    assert_eq!(query_u64(&mut instance, "get"), 250);

    let _err = execute_trap(
        &mut instance,
        &method_msg("increment", &[("delta", 10)]),
    );

    assert_eq!(read_state0_u64(&mut instance), Some(250));
    assert_eq!(query_u64(&mut instance, "get"), 250);
}

/// UInt8 max boundary accepted on init.
#[test]
fn narrow_state_cell_accepts_u8_max() {
    let mut instance = narrow_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 255),
    ));
    assert_eq!(read_state0_u64(&mut instance), Some(255));
    assert_eq!(query_u64(&mut instance, "get"), 255);
}

/// JSON param 256 is out of UInt8 range — must trap at entry (no silent
/// truncation). Parse accepts the decimal as u64, then shr_u 8 range guard.
#[test]
fn narrow_state_cell_param_out_of_range_traps() {
    let mut instance = narrow_instance();
    let msg = br#"{"initial":256}"#.to_vec();
    let _ = instantiate_trap(&mut instance, &msg);
    assert!(
        read_state0_u64(&mut instance).is_none(),
        "no state may be written after out-of-range param trap"
    );
}

/// Increment delta out of UInt8 range also traps before body.
#[test]
fn narrow_state_cell_increment_param_out_of_range_traps() {
    let mut instance = narrow_instance();
    expect_response_ok(instantiate_ok(
        &mut instance,
        &instantiate_msg_u64("initial", 1),
    ));
    let msg = br#"{"increment":{"delta":300}}"#.to_vec();
    let _ = execute_trap(&mut instance, &msg);
    assert_eq!(
        read_state0_u64(&mut instance),
        Some(1),
        "state must hold after out-of-range delta trap"
    );
}
