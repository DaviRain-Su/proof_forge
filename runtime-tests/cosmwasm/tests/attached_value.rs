//! ADR-0031 S4: AttachedValueCheck mock-runtime gate —
//! `context.attachedValue` binds CosmWasm `MessageInfo.funds` as a
//! single-denom `stake` UInt64 (empty funds = 0).
//!
//! Covers:
//!   * execute collect() with 42stake stores/returns 42
//!   * execute collect() with empty funds stores 0
//!   * wrong denom / two coins trap; state holds
//!
//! Honest scope: cosmwasm-vm MockStorage/Api; not wasmd / formal.

mod common;

use {
    common::*,
    cosmwasm_std::{coin, coins, ContractResult, Empty, Response},
    cosmwasm_vm::{
        call_execute, call_instantiate, call_query_raw,
        testing::{mock_env, mock_info},
    },
};

fn av_instance() -> common::CwInstance {
    assert_abi_schema_if_present("AttachedValueCheck");
    make_instance("AttachedValueCheck")
}

fn instantiate_ok(instance: &mut CwInstance) {
    let cr = call_instantiate::<_, _, _, Empty>(
        instance,
        &mock_env(),
        &mock_info("creator", &[]),
        &instantiate_msg_u64("initial", 0),
    )
    .unwrap_or_else(|e| panic!("instantiate VmError: {e:?}"));
    match cr {
        ContractResult::Ok(_) => {}
        ContractResult::Err(e) => panic!("instantiate Err({e})"),
    }
}

fn query_get(instance: &mut CwInstance) -> u64 {
    let env_bytes = cosmwasm_std::to_json_vec(&mock_env()).expect("env json");
    let raw = call_query_raw(instance, &env_bytes, &method_msg_empty("get"))
        .unwrap_or_else(|e| panic!("query VmError: {e:?}"));
    parse_query_ok_u64(&raw)
}

fn execute_collect(
    instance: &mut CwInstance,
    funds: &[cosmwasm_std::Coin],
) -> ContractResult<Response<Empty>> {
    call_execute::<_, _, _, Empty>(
        instance,
        &mock_env(),
        &mock_info("payer", funds),
        &method_msg_empty("collect"),
    )
    .unwrap_or_else(|e| panic!("execute VmError: {e:?}"))
}

fn execute_collect_trap(instance: &mut CwInstance, funds: &[cosmwasm_std::Coin]) {
    match call_execute::<_, _, _, Empty>(
        instance,
        &mock_env(),
        &mock_info("payer", funds),
        &method_msg_empty("collect"),
    ) {
        Err(_) => {}
        Ok(cr) => panic!("expected Wasm trap VmError, got ContractResult {cr:?}"),
    }
}

#[test]
fn attached_value_collect_stake_amount() {
    let mut inst = av_instance();
    instantiate_ok(&mut inst);
    assert_eq!(query_get(&mut inst), 0);

    let cr = execute_collect(&mut inst, &coins(42, "stake"));
    match cr {
        ContractResult::Ok(resp) => assert_attr(&resp, "result", "42"),
        ContractResult::Err(e) => panic!("collect 42stake Err({e})"),
    }
    assert_eq!(query_get(&mut inst), 42);
}

#[test]
fn attached_value_empty_funds_is_zero() {
    let mut inst = av_instance();
    instantiate_ok(&mut inst);
    let cr = execute_collect(&mut inst, &[]);
    match cr {
        ContractResult::Ok(resp) => assert_attr(&resp, "result", "0"),
        ContractResult::Err(e) => panic!("collect empty funds Err({e})"),
    }
    assert_eq!(query_get(&mut inst), 0);
}

#[test]
fn attached_value_wrong_denom_traps_and_holds() {
    let mut inst = av_instance();
    instantiate_ok(&mut inst);
    let cr = execute_collect(&mut inst, &coins(7, "stake"));
    match cr {
        ContractResult::Ok(_) => {}
        ContractResult::Err(e) => panic!("setup collect Err({e})"),
    }
    assert_eq!(query_get(&mut inst), 7);

    execute_collect_trap(&mut inst, &coins(9, "uatom"));
    assert_eq!(query_get(&mut inst), 7);

    execute_collect_trap(&mut inst, &[coin(1, "stake"), coin(1, "uatom")]);
    assert_eq!(query_get(&mut inst), 7);
}
