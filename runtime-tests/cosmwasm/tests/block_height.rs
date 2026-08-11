//! ADR-0031 S2: BlockHeightCheck mock-runtime gate —
//! `context.blockHeight` binds CosmWasm `Env.block.height` (bare u64).
//!
//! Covers:
//!   * query `height()` equals the Env height passed into the call
//!   * execute `stamp()` stores that height; query `get()` matches
//!   * a second call with a higher Env height returns the new value
//!
//! Honest scope: cosmwasm-vm MockStorage/Api; not wasmd / formal.

mod common;

use {
    common::*,
    cosmwasm_std::{to_json_vec, ContractResult, Empty, Env, Response},
    cosmwasm_vm::{
        call_execute, call_instantiate, call_query_raw,
        testing::{mock_env, mock_info},
    },
};

fn bh_instance() -> common::CwInstance {
    assert_abi_schema_if_present("BlockHeightCheck");
    make_instance("BlockHeightCheck")
}

fn env_at_height(height: u64) -> Env {
    let mut env = mock_env();
    env.block.height = height;
    env
}

fn instantiate_at(instance: &mut CwInstance, height: u64, initial: u64) {
    let env = env_at_height(height);
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

fn execute_at(
    instance: &mut CwInstance,
    height: u64,
    msg: &[u8],
) -> Response<Empty> {
    let env = env_at_height(height);
    let cr = call_execute::<_, _, _, Empty>(instance, &env, &mock_info("creator", &[]), msg)
        .unwrap_or_else(|e| panic!("execute VmError: {e:?}"));
    match cr {
        ContractResult::Ok(r) => r,
        ContractResult::Err(e) => panic!("execute Err({e})"),
    }
}

fn query_at(instance: &mut CwInstance, height: u64, method: &str) -> u64 {
    let env = env_at_height(height);
    let env_bytes = to_json_vec(&env).expect("env json");
    let raw = call_query_raw(instance, &env_bytes, &method_msg_empty(method))
        .unwrap_or_else(|e| panic!("query VmError: {e:?}"));
    parse_query_ok_u64(&raw)
}

/// query height() tracks Env.block.height under mock_env default (12345).
#[test]
fn block_height_query_matches_env() {
    let mut instance = bh_instance();
    let h0 = mock_env().block.height;
    instantiate_at(&mut instance, h0, 0);
    assert_eq!(query_at(&mut instance, h0, "get"), 0);
    assert_eq!(query_at(&mut instance, h0, "height"), h0);

    let h1 = h0 + 7;
    assert_eq!(query_at(&mut instance, h1, "height"), h1);
}

/// stamp() stores the execute-time Env height into pad; get() returns it.
#[test]
fn block_height_stamp_stores_execute_height() {
    let mut instance = bh_instance();
    let h0 = mock_env().block.height;
    instantiate_at(&mut instance, h0, 0);

    let stamp_h = h0 + 11;
    let resp = execute_at(&mut instance, stamp_h, &method_msg_empty("stamp"));
    assert_attr(&resp, "result", &stamp_h.to_string());

    // get() reads state — independent of current Env height.
    assert_eq!(query_at(&mut instance, h0 + 99, "get"), stamp_h);
    // height() still tracks the Env passed to the query call.
    assert_eq!(query_at(&mut instance, h0 + 99, "height"), h0 + 99);
}
