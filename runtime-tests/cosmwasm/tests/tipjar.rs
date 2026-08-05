//! TipJar (pf.assets native deposit/transfer) CosmWasm mock differential — ADR-0029 C1.
//!
//! Engineering only: cosmwasm-vm mocks, not wasmd chain execution, not formal
//! Reference↔host closure. Run after `scripts/cosmwasm_runtime_test.sh` builds
//! `TipJar/TipJar.wasm` under `PROOF_FORGE_FIXTURES_DIR`.

mod common;

use {
    common::*,
    cosmwasm_std::{coin, BankMsg, CosmosMsg, ReplyOn, SubMsg},
};

/// Principal leaves for a bech32 dst string: len + 8×u64 LE body words
/// (u32le(len) || utf8 bytes, zero-padded to 64B).
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

fn tip_msg(addr: &str, amount: u64) -> Vec<u8> {
    let l = principal_leaves(addr);
    method_msg(
        "tip",
        &[
            ("dst_len", l[0]),
            ("dst_w0", l[1]),
            ("dst_w1", l[2]),
            ("dst_w2", l[3]),
            ("dst_w3", l[4]),
            ("dst_w4", l[5]),
            ("dst_w5", l[6]),
            ("dst_w6", l[7]),
            ("dst_w7", l[8]),
            ("amount", amount),
        ],
    )
}

fn execute_with_funds(
    instance: &mut CwInstance,
    msg: &[u8],
    funds: &[cosmwasm_std::Coin],
) -> cosmwasm_std::ContractResult<cosmwasm_std::Response<cosmwasm_std::Empty>> {
    cosmwasm_vm::call_execute::<_, _, _, cosmwasm_std::Empty>(
        instance,
        &cosmwasm_vm::testing::mock_env(),
        &cosmwasm_vm::testing::mock_info("tipper", funds),
        msg,
    )
    .unwrap_or_else(|e| panic!("execute VmError: {e:?}"))
}

fn execute_with_funds_trap(
    instance: &mut CwInstance,
    msg: &[u8],
    funds: &[cosmwasm_std::Coin],
) -> cosmwasm_vm::VmError {
    match cosmwasm_vm::call_execute::<_, _, _, cosmwasm_std::Empty>(
        instance,
        &cosmwasm_vm::testing::mock_env(),
        &cosmwasm_vm::testing::mock_info("tipper", funds),
        msg,
    ) {
        Err(e) => e,
        Ok(cr) => panic!("expected Wasm trap VmError, got ContractResult {cr:?}"),
    }
}

#[test]
fn tipjar_deposit_transfer_and_funds_gates() {
    let mut inst = make_instance("TipJar");
    let dst = "cosmos1dst0000";

    // init(7) with empty funds (init is requireZero) → get()==7.
    let cr = instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 7));
    expect_response_ok(cr);
    assert_eq!(query_u64(&mut inst, "get"), 7);

    // tip(dst, 1000) with exact one-coin funds [1000 stake] → ok + BankMsg::Send
    // SubMsg (reply_on=never, id=0) + get()==1007.
    let cr = execute_with_funds(&mut inst, &tip_msg(dst, 1000), &[coin(1000, "stake")]);
    let resp = expect_response_ok(cr);
    assert_eq!(resp.messages.len(), 1, "exactly one SubMsg (bank send)");
    match &resp.messages[0] {
        SubMsg {
            id,
            msg: CosmosMsg::Bank(BankMsg::Send { to_address, amount }),
            reply_on: ReplyOn::Never,
            ..
        } => {
            assert_eq!(*id, 0, "UNUSED_MSG_ID");
            assert_eq!(to_address, dst, "bank send to_address");
            assert_eq!(amount.as_slice(), &[coin(1000, "stake")], "bank send amount");
        }
        other => panic!("expected BankMsg::Send SubMsg reply_on=never, got {other:?}"),
    }
    assert_eq!(query_u64(&mut inst, "get"), 1007);

    // Second tip (idempotent shape) → get()==2007.
    let cr = execute_with_funds(&mut inst, &tip_msg(dst, 1000), &[coin(1000, "stake")]);
    expect_response_ok(cr);
    assert_eq!(query_u64(&mut inst, "get"), 2007);

    // Empty funds on the deposit entry must trap.
    execute_with_funds_trap(&mut inst, &tip_msg(dst, 1000), &[]);

    // Wrong amount (999 ≠ 1000) must trap.
    execute_with_funds_trap(&mut inst, &tip_msg(dst, 1000), &[coin(999, "stake")]);

    // Wrong denom must trap.
    execute_with_funds_trap(&mut inst, &tip_msg(dst, 1000), &[coin(1000, "atom")]);

    // Two coins must trap (exact-one-coin closing check).
    execute_with_funds_trap(
        &mut inst,
        &tip_msg(dst, 1000),
        &[coin(1000, "stake"), coin(1, "stake")],
    );

    // State holds after all rejected variants.
    assert_eq!(query_u64(&mut inst, "get"), 2007);

    println!("tipjar: deposit/transfer + funds gates ok");
}

#[test]
fn tipjar_bech32_charset_gate_traps() {
    let mut inst = make_instance("TipJar");
    instantiate_ok(&mut inst, &instantiate_msg_u64("initial", 0));

    // The emitter embeds dst raw into the BankMsg SubMsg JSON envelope, so
    // the lowercase bech32 charset [a-z0-9] gate is what keeps that embedding
    // injection-safe. A JSON quote byte in the body must trap.
    let l = principal_leaves("cosmos1dst0000");
    let build = |w0: u64| {
        method_msg(
            "tip",
            &[
                ("dst_len", l[0]),
                ("dst_w0", w0),
                ("dst_w1", l[2]),
                ("dst_w2", l[3]),
                ("dst_w3", l[4]),
                ("dst_w4", l[5]),
                ("dst_w5", l[6]),
                ("dst_w6", l[7]),
                ("dst_w7", l[8]),
                ("amount", 1000u64),
            ],
        )
    };
    execute_with_funds_trap(
        &mut inst,
        &build((l[1] & !0xffu64) | 0x22u64), // '"' in body byte 0
        &[coin(1000, "stake")],
    );
    execute_with_funds_trap(
        &mut inst,
        &build((l[1] & !0xffu64) | 0x41u64), // 'A' (uppercase) in body byte 0
        &[coin(1000, "stake")],
    );

    // State holds after the rejected variants.
    assert_eq!(query_u64(&mut inst, "get"), 0);

    println!("tipjar: bech32 charset gate traps ok");
}
