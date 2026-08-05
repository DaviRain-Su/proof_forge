//! ADR-0030 E2-4-CW: EnvReadJar mock-runtime gate — pf.assets env-read
//! (native.balanceOfSelf via `query_chain` bank query, token.balanceOfSelf
//! via `query_chain` CW20 smart query). Asserts exact balances against a
//! seeded MockQuerier plus wire-shape/error negatives.
//!
//! Honest scope: the mock querier is seeded directly (update_balance /
//! update_wasm); C1-style BankMsg::Send execution is not dispatched by the
//! mock, so no balance-delta-from-SubMsg is claimed here.

mod common;

use {
    common::*,
    cosmwasm_std::{to_json_binary, ContractResult, SystemResult, WasmQuery},
    serde_json::json,
};

/// cosmwasm-std testing default contract address (mock_env().contract.address).
const CONTRACT_ADDR: &str =
    "cosmwasm1jpev2csrppg792t22rn8z8uew8h3sjcpglcd0qv9g8gj8ky922tscp8avs";
const MINT_ADDR: &str = "cosmos1mint0002";

/// Principal leaves for a bech32 address string: len + 8×u64 LE body words
/// (u32le(len) || utf8 bytes, zero-padded to 64B). Same encoding as the
/// tokenjar test.
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

fn token_balance_msg(mint: &str) -> Vec<u8> {
    let m = principal_leaves(mint);
    method_msg(
        "tokenBalance",
        &[
            ("mint_len", m[0]),
            ("mint_w0", m[1]),
            ("mint_w1", m[2]),
            ("mint_w2", m[3]),
            ("mint_w3", m[4]),
            ("mint_w4", m[5]),
            ("mint_w5", m[6]),
            ("mint_w6", m[7]),
            ("mint_w7", m[8]),
        ],
    )
}

fn token_balance_msg_raw(mint_len: u64, mint_w0: u64) -> Vec<u8> {
    method_msg(
        "tokenBalance",
        &[
            ("mint_len", mint_len),
            ("mint_w0", mint_w0),
            ("mint_w1", 0u64),
            ("mint_w2", 0u64),
            ("mint_w3", 0u64),
            ("mint_w4", 0u64),
            ("mint_w5", 0u64),
            ("mint_w6", 0u64),
            ("mint_w7", 0u64),
        ],
    )
}

fn query_view_u64(instance: &mut CwInstance, method: &str) -> u64 {
    let raw = query_raw(instance, &method_msg_empty(method));
    parse_query_ok_u64(&raw)
}

fn query_view_u64_msg(instance: &mut CwInstance, msg: &[u8]) -> u64 {
    let raw = query_raw(instance, msg);
    parse_query_ok_u64(&raw)
}

#[test]
fn envread_native_balance_bank_query_exact() {
    let mut inst = make_instance("EnvReadJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));

    // Seed the bank balance of the contract account: 2000 stake.
    inst.with_querier(|q| {
        q.update_balance(CONTRACT_ADDR, vec![cosmwasm_std::coin(2000, "stake")]);
        Ok(())
    })
    .unwrap();
    assert_eq!(
        query_view_u64(&mut inst, "nativeBalance"),
        2000,
        "native balance must read the seeded 2000 stake via query_chain"
    );

    // Re-seed to 3500 → exact new value (fresh query each time).
    inst.with_querier(|q| {
        q.update_balance(CONTRACT_ADDR, vec![cosmwasm_std::coin(3500, "stake")]);
        Ok(())
    })
    .unwrap();
    assert_eq!(query_view_u64(&mut inst, "nativeBalance"), 3500);

    // Empty balance → bank query returns amount "0".
    inst.with_querier(|q| {
        q.update_balance(CONTRACT_ADDR, vec![]);
        Ok(())
    })
    .unwrap();
    assert_eq!(query_view_u64(&mut inst, "nativeBalance"), 0);

    println!("envreadjar: native balanceOfSelf via query_chain exact ok");
}

#[test]
fn envread_token_balance_smart_query_exact_and_negatives() {
    let mut inst = make_instance("EnvReadJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));

    // Seed the CW20 smart-query responder: BalanceResponse { balance: "2000" }
    // for the pinned mint; any other contract errors (unknown token contract).
    inst.with_querier(|q| {
        q.update_wasm(|query: &WasmQuery| -> cosmwasm_std::QuerierResult {
            match query {
                WasmQuery::Smart { contract_addr, msg } => {
                    if contract_addr != MINT_ADDR {
                        return SystemResult::Ok(ContractResult::Err(
                            "no such token contract".to_string(),
                        ));
                    }
                    let v: serde_json::Value =
                        serde_json::from_slice(msg.as_slice()).expect("balance msg json");
                    assert_eq!(
                        v,
                        json!({"balance": {"address": CONTRACT_ADDR}}),
                        "smart query msg must be CW20 balance of the contract"
                    );
                    SystemResult::Ok(ContractResult::Ok(
                        to_json_binary(&json!({"balance": "2000"})).unwrap(),
                    ))
                }
                other => panic!("unexpected wasm query: {other:?}"),
            }
        });
        Ok(())
    })
    .unwrap();
    assert_eq!(
        query_view_u64_msg(&mut inst, &token_balance_msg(MINT_ADDR)),
        2000,
        "token balance must decode CW20 BalanceResponse.balance"
    );

    // Negative: malformed mint wire shape (len=0) traps the view → VmError.
    let env = cosmwasm_std::to_json_vec(&cosmwasm_vm::testing::mock_env()).unwrap();
    let raw = cosmwasm_vm::call_query_raw(&mut inst, &env, &token_balance_msg_raw(0, 0));
    assert!(
        raw.is_err(),
        "malformed mint wire shape must trap the view, got {raw:?}"
    );

    // Negative: smart-query contract error (unknown token contract) traps the
    // view (no inner ok needle → unreachable → VmError).
    let raw2 = cosmwasm_vm::call_query_raw(
        &mut inst,
        &env,
        &token_balance_msg("cosmos1unknown999"),
    );
    assert!(
        raw2.is_err(),
        "unknown mint smart query must trap the view, got {raw2:?}"
    );

    println!("envreadjar: token balanceOfSelf via query_chain exact + negatives ok");
}
