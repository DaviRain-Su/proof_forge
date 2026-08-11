//! UnixTimeCheck fixture: `context.unixTimeSeconds` → Env.block.time nanos ÷ 10^9.
//!
//! Covers:
//!   * query `seconds()` equals truncating whole seconds of Env.block.time
//!   * execute `stamp()` stores that second; query `get()` matches
//!   * a later Env time advances `seconds()` independently of stored pad
//!
//! Honest scope: cosmwasm-vm MockStorage/Api; not wasmd / formal.
//! Env.block.time is Timestamp nanoseconds (JSON string `"time"`); product
//! divides by 1e9 truncating (same discipline as NEAR block_timestamp).

mod common;

use {
    common::*,
    cosmwasm_std::{to_json_vec, ContractResult, Empty, Env, Response, Timestamp},
    cosmwasm_vm::{
        call_execute, call_instantiate, call_query_raw,
        testing::{mock_env, mock_info},
    },
};

fn ut_instance() -> common::CwInstance {
    assert_abi_schema_if_present("UnixTimeCheck");
    make_instance("UnixTimeCheck")
}

fn env_at_nanos(nanos: u64) -> Env {
    let mut env = mock_env();
    env.block.time = Timestamp::from_nanos(nanos);
    env
}

fn secs_of_nanos(nanos: u64) -> u64 {
    nanos / 1_000_000_000
}

fn instantiate_at(instance: &mut CwInstance, nanos: u64, initial: u64) {
    let env = env_at_nanos(nanos);
    let cr = call_instantiate::<_, _, _, Empty>(
        instance,
        &env,
        &mock_info("creator", &[]),
        &instantiate_msg_u64("initial", initial),
    )
    .unwrap_or_else(|e| panic!("instantiate VmError: {e:?}"));
    match cr {
        ContractResult::Ok(_) => {}
        ContractResult::Err(e) => panic!("instantiate Err({e})"),
    }
}

fn execute_at(instance: &mut CwInstance, nanos: u64, msg: &[u8]) -> Response<Empty> {
    let env = env_at_nanos(nanos);
    let cr = call_execute::<_, _, _, Empty>(instance, &env, &mock_info("creator", &[]), msg)
        .unwrap_or_else(|e| panic!("execute VmError: {e:?}"));
    match cr {
        ContractResult::Ok(r) => r,
        ContractResult::Err(e) => panic!("execute Err({e})"),
    }
}

fn query_at(instance: &mut CwInstance, nanos: u64, method: &str) -> u64 {
    let env = env_at_nanos(nanos);
    let env_bytes = to_json_vec(&env).expect("env json");
    let raw = call_query_raw(instance, &env_bytes, &method_msg_empty(method))
        .unwrap_or_else(|e| panic!("query VmError: {e:?}"));
    parse_query_ok_u64(&raw)
}

#[test]
fn unix_time_query_matches_env_seconds() {
    let mut instance = ut_instance();
    let n0 = mock_env().block.time.nanos();
    let s0 = secs_of_nanos(n0);
    instantiate_at(&mut instance, n0, 0);
    assert_eq!(query_at(&mut instance, n0, "get"), 0);
    assert_eq!(query_at(&mut instance, n0, "seconds"), s0);

    let n1 = n0 + 7_000_000_000; // +7s
    let s1 = secs_of_nanos(n1);
    assert_eq!(query_at(&mut instance, n1, "seconds"), s1);
    assert_ne!(s0, s1, "test setup must advance whole seconds");
}

#[test]
fn unix_time_stamp_stores_execute_seconds() {
    let mut instance = ut_instance();
    let n0 = mock_env().block.time.nanos();
    instantiate_at(&mut instance, n0, 0);

    let stamp_n = n0 + 11_000_000_000; // +11s
    let stamp_s = secs_of_nanos(stamp_n);
    let resp = execute_at(&mut instance, stamp_n, &method_msg_empty("stamp"));
    assert_attr(&resp, "result", &stamp_s.to_string());

    // get() is state — independent of current Env time.
    assert_eq!(query_at(&mut instance, n0 + 99_000_000_000, "get"), stamp_s);
    // seconds() still tracks the Env passed to the query call.
    let q_n = n0 + 99_000_000_000;
    assert_eq!(
        query_at(&mut instance, q_n, "seconds"),
        secs_of_nanos(q_n)
    );
}

/// Truncating division: sub-second nanos do not round up.
#[test]
fn unix_time_truncates_subsecond_nanos() {
    let mut instance = ut_instance();
    // 1_000_000_000 + 999_999_999 → still 1 whole second
    let n = 1_000_000_000u64 + 999_999_999;
    instantiate_at(&mut instance, n, 0);
    assert_eq!(query_at(&mut instance, n, "seconds"), 1);
}
