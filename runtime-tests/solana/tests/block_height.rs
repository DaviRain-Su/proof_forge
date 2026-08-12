//! # ADR-0031 S2 residual: `context.blockHeight` Mollusk product acceptance.
//!
//! Fixture: `runtime-tests/solana/fixtures/BlockHeight.lean`, built through
//! ordinary `proof-forge-next build --target solana` (sole rail
//! `solana-sbpf-cpi-elf-v1`) by `scripts/solana_runtime_test.sh` into
//! `PROOF_FORGE_FIXTURES_DIR/BlockHeight/`.
//!
//! Solana honesty: `context.blockHeight` = `Clock.slot` via the real
//! `sol_get_clock_sysvar` syscall (physical ≈400ms slot, **not** a logical
//! block number). No Clock account meta — the syscall reads the runtime
//! sysvar cache, which these tests set through Mollusk's
//! `sysvars.warp_to_slot`. Two distinct warped slots prove the returned
//! value tracks the runtime Clock and is not a baked-in constant.
//!
//! Engineering gate only — not formal, not hermetic, not mainnet.

mod common;

use {
    common::{
        assert_discriminators_match_plan, build_ix, fixture_plan_bytes, instruction_discriminator,
        make_fixture_mollusk, single_field, state_account, state_data, StateField,
    },
    mollusk_svm::{result::Check, Mollusk},
    solana_pubkey::Pubkey,
};

const PROGRAM: &str = "BlockHeight";

fn block_height_fields() -> [StateField; 1] {
    single_field("pad")
}

fn block_height_state(initialized: bool, pad: u64) -> Vec<u8> {
    state_data(&block_height_fields(), initialized, &[pad])
}

fn assert_block_height_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes(PROGRAM),
        &[("initialize", 1), ("stamp", 0), ("height", 0), ("get", 0)],
    );
}

fn warped_mollusk(program_id: &Pubkey, slot: u64) -> Mollusk {
    let mut mollusk = make_fixture_mollusk(program_id, PROGRAM);
    mollusk.sysvars.warp_to_slot(slot);
    assert_eq!(mollusk.sysvars.clock.slot, slot, "warp_to_slot must set Clock.slot");
    mollusk
}

/// View `height()` returns exactly the warped Clock.slot; state holds.
#[test]
fn height_returns_warped_slot() {
    assert_block_height_plan();
    let program_id = Pubkey::new_unique();
    let slot = 4242u64;
    let mollusk = warped_mollusk(&program_id, slot);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("height", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let pre = block_height_state(true, 7);
    let account = state_account(&program_id, pre.clone());
    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&slot.to_le_bytes()),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Second distinct warped slot proves the value tracks the runtime Clock
/// (not a constant baked into the ELF).
#[test]
fn height_tracks_second_distinct_slot() {
    assert_block_height_plan();
    let program_id = Pubkey::new_unique();
    let slot = 987_654_321u64;
    let mollusk = warped_mollusk(&program_id, slot);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("height", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let pre = block_height_state(true, 0);
    let account = state_account(&program_id, pre.clone());
    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&slot.to_le_bytes()),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Entry `stamp()` stores the current slot into state and returns it;
/// a follow-up `get()` reads the stored slot back without the syscall.
#[test]
fn stamp_stores_current_slot_then_get_reads_it() {
    assert_block_height_plan();
    let program_id = Pubkey::new_unique();
    let slot = 123_456u64;
    let mollusk = warped_mollusk(&program_id, slot);
    let state_key = Pubkey::new_unique();

    let stamp_disc = instruction_discriminator("stamp", 0);
    let stamp_ix = build_ix(program_id, state_key, &stamp_disc, &[], true, false);
    let result = mollusk.process_and_validate_instruction(
        &stamp_ix,
        &[(state_key, state_account(&program_id, block_height_state(true, 1)))],
        &[
            Check::success(),
            Check::return_data(&slot.to_le_bytes()),
            Check::account(&state_key)
                .data(&block_height_state(true, slot))
                .build(),
        ],
    );
    let after_stamp = result
        .resulting_accounts
        .into_iter()
        .find(|(k, _)| k == &state_key)
        .expect("state account after stamp")
        .1;

    let get_disc = instruction_discriminator("get", 0);
    let get_ix = build_ix(program_id, state_key, &get_disc, &[], false, false);
    mollusk.process_and_validate_instruction(
        &get_ix,
        &[(state_key, after_stamp)],
        &[
            Check::success(),
            Check::return_data(&slot.to_le_bytes()),
            Check::account(&state_key)
                .data(&block_height_state(true, slot))
                .build(),
        ],
    );
}

/// Assembly honesty pin: real syscall emission and the physical-slot caveat.
#[test]
fn product_assembly_emits_clock_sysvar_syscall() {
    use common::read_manifest_leaf_bytes;
    let out = common::fixture_output_dir(PROGRAM);
    let assembly = read_manifest_leaf_bytes(
        &out,
        PROGRAM,
        &format!("{PROGRAM}.s"),
        "materialized-base",
    )
    .unwrap_or_else(|error| panic!("{PROGRAM} assembly binding failed: {error}"));
    let text = String::from_utf8_lossy(&assembly);
    assert!(
        text.contains("call sol_get_clock_sysvar"),
        "assembly must call sol_get_clock_sysvar"
    );
    assert!(text.contains("clock_slot"), "assembly must annotate clock_slot");
    assert!(
        !text.contains("TEST-PREACTIVATION"),
        "product assembly must not carry preactivation banner"
    );
}
