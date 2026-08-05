//! TokenJar (pf.assets.token.transfer → CW20 Transfer) CosmWasm mock
//! differential — ADR-0030 E1-CW.
//!
//! Mirrors the C1 `tipjar.rs` pattern: cosmwasm-vm mock executes the TokenJar
//! product Wasm and the test inspects the emitted `WasmMsg::Execute` SubMsg
//! shape + the base64-decoded inner execute-msg JSON. The mock does NOT
//! dispatch SubMessages to a real CW20 contract (that requires wasmd's full
//! message pipeline or cw-multi-test with a Rust-native Contract wrapper —
//! the product TokenJar is raw Wasm bytes, not a `cw_multi_test::Contract`
//! trait object, so cw-multi-test's `App::store_code` cannot host it).
//!
//! What this gate verifies (honest scope):
//! * `tipToken(mint, dst, amount)` emits exactly one `WasmMsg::Execute`
//!   SubMsg with `reply_on=never`, `contract_addr` == mint, `funds` == [].
//! * The SubMsg `msg` Binary (base64) decodes to
//!   `{"transfer":{"recipient":"<dst>","amount":"<amount>"}}`.
//! * The TokenJar tips counter increments (state hold).
//! * Entry is non-payable: non-empty funds trap (requireZero).
//! * Malformed mint/dst wire shape (len=0) traps at runtime ($pf_dst_check).
//!
//! Engineering only: cosmwasm-vm mock, not wasmd chain execution, not formal
//! Reference↔host closure. CW20 balance deltas (jar -X, dst +X) require a real
//! CW20 contract execution which is a wasmd rung, not a cosmwasm-vm mock
//! capability — see deviation note in the report. Run after
//! `scripts/cosmwasm_runtime_test.sh` builds `TokenJar/TokenJar.wasm`.

mod common;

use {
    common::*,
    cosmwasm_std::{from_json, BankMsg, CosmosMsg, ReplyOn, SubMsg, WasmMsg},
};

/// Principal leaves for a bech32 address string: len + 8×u64 LE body words
/// (u32le(len) || utf8 bytes, zero-padded to 64B). Same encoding as the
/// native-transfer dst in the C1 tipjar test.
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

/// Build the execute message JSON for `tipToken(mint, dst, amount)`.
/// The product ABI scans for the method needle + flat decimal params.
fn tip_token_msg(mint: &str, dst: &str, amount: u64) -> Vec<u8> {
    let m = principal_leaves(mint);
    let d = principal_leaves(dst);
    method_msg(
        "tipToken",
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
            ("dst_len", d[0]),
            ("dst_w0", d[1]),
            ("dst_w1", d[2]),
            ("dst_w2", d[3]),
            ("dst_w3", d[4]),
            ("dst_w4", d[5]),
            ("dst_w5", d[6]),
            ("dst_w6", d[7]),
            ("dst_w7", d[8]),
            ("amount", amount),
        ],
    )
}

/// Build a tipToken msg with raw leaf overrides (for malformed-wire tests).
fn tip_token_msg_raw(mint_len: u64, dst_len: u64, amount: u64) -> Vec<u8> {
    method_msg(
        "tipToken",
        &[
            ("mint_len", mint_len),
            ("mint_w0", 0u64),
            ("mint_w1", 0u64),
            ("mint_w2", 0u64),
            ("mint_w3", 0u64),
            ("mint_w4", 0u64),
            ("mint_w5", 0u64),
            ("mint_w6", 0u64),
            ("mint_w7", 0u64),
            ("dst_len", dst_len),
            ("dst_w0", 0u64),
            ("dst_w1", 0u64),
            ("dst_w2", 0u64),
            ("dst_w3", 0u64),
            ("dst_w4", 0u64),
            ("dst_w5", 0u64),
            ("dst_w6", 0u64),
            ("dst_w7", 0u64),
            ("amount", amount),
        ],
    )
}

/// Decode the SubMsg `msg` Binary (base64) and verify it is the CW20
/// `{"transfer":{"recipient":"<dst>","amount":"<amount>"}}` execute message.
fn assert_cw20_transfer_msg(submsg: &SubMsg, expected_dst: &str, expected_amount: u64) {
    match submsg {
        SubMsg {
            id,
            msg: CosmosMsg::Wasm(WasmMsg::Execute { contract_addr, msg, funds }),
            reply_on: ReplyOn::Never,
            ..
        } => {
            assert_eq!(*id, 0, "UNUSED_MSG_ID");
            assert!(!contract_addr.is_empty(), "contract_addr non-empty (mint)");
            assert!(funds.is_empty(), "funds empty (non-payable token transfer)");
            // msg is cosmwasm-std Binary = base64-decoded already by the host?
            // No — the product emits raw base64 text in the JSON messages
            // buffer. The cosmwasm-vm mock parses the Response JSON and
            // re-constitutes SubMsg with Binary = decoded base64 bytes.
            // So msg.0 is the raw UTF-8 JSON of the execute message.
            let inner_json = String::from_utf8(msg.as_slice().to_vec())
                .unwrap_or_else(|e| panic!("msg not UTF-8: {e}, raw={:?}", msg));
            let v: serde_json::Value = from_json(&inner_json)
                .unwrap_or_else(|e| panic!("msg not JSON: {e}, raw={inner_json}"));
            let transfer = v.get("transfer").expect("msg has transfer key");
            let recipient = transfer
                .get("recipient")
                .and_then(|r| r.as_str())
                .unwrap_or_else(|| panic!("missing recipient, raw={inner_json}"));
            let amount_str = transfer
                .get("amount")
                .and_then(|a| a.as_str())
                .unwrap_or_else(|| panic!("missing amount, raw={inner_json}"));
            assert_eq!(recipient, expected_dst, "CW20 transfer recipient");
            assert_eq!(
                amount_str,
                expected_amount.to_string(),
                "CW20 transfer amount (decimal string)"
            );
        }
        other => panic!("expected WasmMsg::Execute SubMsg reply_on=never, got {other:?}"),
    }
}

#[test]
fn tokenjar_cw20_transfer_submsg_shape() {
    let mut inst = make_instance("TokenJar");
    let mint = "cosmos1mint0000";
    let dst = "cosmos1dst0000";

    // init(0) with empty funds → get()==0.
    let cr = instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));
    expect_response_ok(cr);
    assert_eq!(query_u64(&mut inst, "get"), 0);

    // tipToken(mint, dst, 1000) with empty funds (non-payable) → ok +
    // WasmMsg::Execute SubMsg (reply_on=never) + get()==1000.
    let cr = execute_ok(&mut inst, &tip_token_msg(mint, dst, 1000));
    let resp = expect_response_ok(cr);
    assert_eq!(resp.messages.len(), 1, "exactly one SubMsg (wasm execute)");
    assert_cw20_transfer_msg(&resp.messages[0], dst, 1000);
    // contract_addr should be the mint address.
    match &resp.messages[0] {
        SubMsg {
            msg: CosmosMsg::Wasm(WasmMsg::Execute { contract_addr, .. }),
            ..
        } => {
            assert_eq!(contract_addr, mint, "SubMsg contract_addr == mint");
        }
        _ => unreachable!(),
    }
    assert_eq!(query_u64(&mut inst, "get"), 1000, "tips counter == 1000");

    // Second tipToken (idempotent shape) → get()==2000.
    let cr = execute_ok(&mut inst, &tip_token_msg(mint, dst, 1000));
    expect_response_ok(cr);
    assert_eq!(query_u64(&mut inst, "get"), 2000, "tips counter == 2000");

    println!("tokenjar: CW20 transfer SubMsg shape + state ok");
}

#[test]
fn tokenjar_non_payable_funds_trap() {
    let mut inst = make_instance("TokenJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));

    // tipToken with non-empty funds must trap (entry is non-payable:
    // requireZero funds policy — token.transfer carries no info.funds).
    let msg = tip_token_msg("cosmos1mint0001", "cosmos1dst0001", 100);
    let funds = vec![cosmwasm_std::coin(100, "stake")];
    let cr = cosmwasm_vm::call_execute::<_, _, _, cosmwasm_std::Empty>(
        &mut inst,
        &cosmwasm_vm::testing::mock_env(),
        &cosmwasm_vm::testing::mock_info("tipper", &funds),
        &msg,
    );
    match cr {
        Err(_) => {} // VmError trap (requireFundsEmpty unreachable)
        Ok(contract_result) => panic!(
            "non-payable token.transfer with funds must trap, got {contract_result:?}"
        ),
    }
    println!("tokenjar: non-payable funds trap ok");
}

#[test]
fn tokenjar_malformed_mint_wire_shape_traps() {
    let mut inst = make_instance("TokenJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));

    // Malformed mint: len=0 (Principal body shorter than 1 byte → pf_dst_check
    // fails → unreachable trap).
    let msg = tip_token_msg_raw(0, 12, 100);
    execute_trap(&mut inst, &msg);

    println!("tokenjar: malformed mint wire shape trap ok");
}

#[test]
fn tokenjar_malformed_dst_wire_shape_traps() {
    let mut inst = make_instance("TokenJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));

    // Malformed dst: len=0 → pf_dst_check fails → unreachable trap.
    let msg = tip_token_msg_raw(12, 0, 100);
    execute_trap(&mut inst, &msg);

    println!("tokenjar: malformed dst wire shape trap ok");
}

#[test]
fn tokenjar_no_bank_send_on_token_transfer() {
    // Honesty gate: token.transfer must NOT emit a BankMsg (that's the native
    // transfer lane). It must emit WasmMsg::Execute only.
    let mut inst = make_instance("TokenJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));
    let cr = execute_ok(&mut inst, &tip_token_msg("cosmos1mint0002", "cosmos1dst0002", 500));
    let resp = expect_response_ok(cr);
    for msg in &resp.messages {
        match msg {
            SubMsg {
                msg: CosmosMsg::Bank(BankMsg::Send { .. }),
                ..
            } => panic!("token.transfer must not emit BankMsg::Send"),
            _ => {}
        }
    }
    println!("tokenjar: no BankMsg on token transfer ok");
}