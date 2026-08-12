//! ADR-0031 S3: SelfIdentityCheck mock-runtime gate —
//! `context.self` binds CosmWasm `Env.contract.address` as Principal.
//!
//! Covers:
//!   * query `isSelfView(contract Principal leaves)` == true
//!   * query `isSelfView(other Principal leaves)` == false
//!   * execute `isSelf(contract)` == true; `isSelf(other)` == false
//!
//! Honest scope: cosmwasm-vm MockStorage/Api; not wasmd / formal.

mod common;

use {
    common::*,
    cosmwasm_std::{ContractResult, Empty, Response},
    cosmwasm_vm::{
        call_execute, call_instantiate, call_query_raw,
        testing::{mock_env, mock_info},
    },
};

/// cosmwasm-std testing default contract address (mock_env().contract.address).
const CONTRACT_ADDR: &str =
    "cosmwasm1jpev2csrppg792t22rn8z8uew8h3sjcpglcd0qv9g8gj8ky922tscp8avs";
const OTHER_ADDR: &str = "cosmos1other0001abcdefghijklmnopqrstuv";

fn principal_leaves(addr: &str) -> [u64; 9] {
    let raw = addr.as_bytes();
    assert!((2..=64).contains(&raw.len()), "addr len must be 2..=64");
    let mut body = [0u8; 64];
    body[..raw.len()].copy_from_slice(raw);
    let mut out = [0u64; 9];
    out[0] = raw.len() as u64;
    for i in 0..8 {
        out[i + 1] = u64::from_le_bytes(body[i * 8..(i + 1) * 8].try_into().unwrap());
    }
    out
}

fn self_param_pairs(prefix: &str, addr: &str) -> Vec<(String, u64)> {
    let l = principal_leaves(addr);
    vec![
        (format!("{prefix}_len"), l[0]),
        (format!("{prefix}_w0"), l[1]),
        (format!("{prefix}_w1"), l[2]),
        (format!("{prefix}_w2"), l[3]),
        (format!("{prefix}_w3"), l[4]),
        (format!("{prefix}_w4"), l[5]),
        (format!("{prefix}_w5"), l[6]),
        (format!("{prefix}_w6"), l[7]),
        (format!("{prefix}_w7"), l[8]),
    ]
}

fn is_self_msg(method: &str, addr: &str) -> Vec<u8> {
    let pairs = self_param_pairs("a", addr);
    let refs: Vec<(&str, u64)> = pairs.iter().map(|(k, v)| (k.as_str(), *v)).collect();
    method_msg(method, &refs)
}

fn si_instance() -> CwInstance {
    assert_abi_schema_if_present("SelfIdentityCheck");
    make_instance("SelfIdentityCheck")
}

fn instantiate_ok(instance: &mut CwInstance, initial: u64) {
    let cr = call_instantiate::<_, _, _, Empty>(
        instance,
        &mock_env(),
        &mock_info("creator", &[]),
        &instantiate_msg_u64("initial", initial),
    )
    .unwrap_or_else(|e| panic!("instantiate VmError: {e:?}"));
    match cr {
        ContractResult::Ok(_) => {}
        ContractResult::Err(e) => panic!("instantiate Err({e})"),
    }
}

fn execute_bool(instance: &mut CwInstance, msg: &[u8]) -> u64 {
    let cr = call_execute::<_, _, _, Empty>(instance, &mock_env(), &mock_info("creator", &[]), msg)
        .unwrap_or_else(|e| panic!("execute VmError: {e:?}"));
    match cr {
        ContractResult::Ok(r) => {
            // Valued Bool returns as result attribute "0"/"1".
            attr_u64(&r, "result")
        }
        ContractResult::Err(e) => panic!("execute Err({e})"),
    }
}

fn query_bool(instance: &mut CwInstance, msg: &[u8]) -> u64 {
    let raw = call_query_raw(instance, &to_env_bytes(), msg)
        .unwrap_or_else(|e| panic!("query VmError: {e:?}"));
    parse_query_ok_u64(&raw)
}

fn to_env_bytes() -> Vec<u8> {
    cosmwasm_std::to_json_vec(&mock_env()).expect("env json")
}

fn attr_u64(resp: &Response<Empty>, key: &str) -> u64 {
    for a in &resp.attributes {
        if a.key == key {
            return a
                .value
                .parse::<u64>()
                .unwrap_or_else(|_| panic!("attr {key} not u64: {}", a.value));
        }
    }
    panic!("missing attribute {key} in {resp:?}")
}

#[test]
fn self_identity_query_matches_contract_addr() {
    let mut instance = si_instance();
    instantiate_ok(&mut instance, 0);
    assert_eq!(query_view_get(&mut instance), 0);

    let yes = query_bool(&mut instance, &is_self_msg("isSelfView", CONTRACT_ADDR));
    assert_eq!(yes, 1, "isSelfView(contract) must be true");

    let no = query_bool(&mut instance, &is_self_msg("isSelfView", OTHER_ADDR));
    assert_eq!(no, 0, "isSelfView(other) must be false");
}

#[test]
fn self_identity_execute_matches_contract_addr() {
    let mut instance = si_instance();
    instantiate_ok(&mut instance, 0);

    let yes = execute_bool(&mut instance, &is_self_msg("isSelf", CONTRACT_ADDR));
    assert_eq!(yes, 1, "isSelf(contract) must be true");

    let no = execute_bool(&mut instance, &is_self_msg("isSelf", OTHER_ADDR));
    assert_eq!(no, 0, "isSelf(other) must be false");
}

fn query_view_get(instance: &mut CwInstance) -> u64 {
    let raw = call_query_raw(instance, &to_env_bytes(), &method_msg_empty("get"))
        .unwrap_or_else(|e| panic!("query get VmError: {e:?}"));
    parse_query_ok_u64(&raw)
}
