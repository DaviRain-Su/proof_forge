//! # CAP-2 / CAP-D-SOL-TIME: `context.unixTimeSeconds` Mollusk product acceptance.
//!
//! Fixture: `runtime-tests/solana/fixtures/UnixTimeSeconds.lean`, built through
//! ordinary `proof-forge-next build --target solana` (sole rail
//! `solana-sbpf-cpi-elf-v1`) by `scripts/solana_runtime_test.sh` into
//! `PROOF_FORGE_FIXTURES_DIR/UnixTimeSeconds/`.
//!
//! Solana honesty: `context.unixTimeSeconds` = `Clock.unix_timestamp` via the
//! real `sol_get_clock_sysvar` syscall (i64 at byte offset 32). The i64 bits
//! are returned as UInt64 with no extra sign/range guard. No Clock account
//! meta — the syscall reads the runtime sysvar cache. Two distinct timestamps
//! prove the returned value tracks the runtime Clock and is not a baked-in
//! constant.
//!
//! Engineering gate only — not formal, not hermetic, not mainnet.

mod common;

use {
    common::{
        assert_discriminators_match_plan, build_ix, fixture_plan_bytes, instruction_discriminator,
        make_fixture_mollusk, read_manifest_leaf_bytes, single_field, state_account, state_data,
        StateField,
    },
    mollusk_svm::{result::Check, Mollusk},
    solana_pubkey::Pubkey,
};

const PROGRAM: &str = "UnixTimeSeconds";

fn unix_time_fields() -> [StateField; 1] {
    single_field("pad")
}

fn unix_time_state(initialized: bool, pad: u64) -> Vec<u8> {
    state_data(&unix_time_fields(), initialized, &[pad])
}

fn assert_unix_time_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_bytes(PROGRAM),
        &[("initialize", 1), ("stamp", 0), ("now", 0), ("get", 0)],
    );
}

fn clock_mollusk(program_id: &Pubkey, unix_timestamp: i64) -> Mollusk {
    let mut mollusk = make_fixture_mollusk(program_id, PROGRAM);
    mollusk.sysvars.clock.unix_timestamp = unix_timestamp;
    assert_eq!(
        mollusk.sysvars.clock.unix_timestamp, unix_timestamp,
        "must set Clock.unix_timestamp"
    );
    mollusk
}

fn timestamp_le(ts: i64) -> [u8; 8] {
    (ts as u64).to_le_bytes()
}

/// View `now()` returns exactly the Clock.unix_timestamp bits as UInt64.
#[test]
fn now_returns_set_unix_timestamp() {
    assert_unix_time_plan();
    let program_id = Pubkey::new_unique();
    let ts = 1_700_000_000i64;
    let mollusk = clock_mollusk(&program_id, ts);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("now", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let pre = unix_time_state(true, 7);
    let account = state_account(&program_id, pre.clone());
    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&timestamp_le(ts)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Second distinct timestamp proves the value tracks the runtime Clock
/// (not a constant baked into the ELF).
#[test]
fn now_tracks_second_distinct_timestamp() {
    assert_unix_time_plan();
    let program_id = Pubkey::new_unique();
    let ts = 1_234_567_890i64;
    let mollusk = clock_mollusk(&program_id, ts);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("now", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let pre = unix_time_state(true, 0);
    let account = state_account(&program_id, pre.clone());
    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&timestamp_le(ts)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Entry `stamp()` stores the current unix timestamp into state and returns it;
/// a follow-up `get()` reads the stored value back without the syscall.
#[test]
fn stamp_stores_current_unix_time_then_get_reads_it() {
    assert_unix_time_plan();
    let program_id = Pubkey::new_unique();
    let ts = 1_600_000_000i64;
    let mollusk = clock_mollusk(&program_id, ts);
    let state_key = Pubkey::new_unique();
    let stored = ts as u64;

    let stamp_disc = instruction_discriminator("stamp", 0);
    let stamp_ix = build_ix(program_id, state_key, &stamp_disc, &[], true, false);
    let result = mollusk.process_and_validate_instruction(
        &stamp_ix,
        &[(state_key, state_account(&program_id, unix_time_state(true, 1)))],
        &[
            Check::success(),
            Check::return_data(&timestamp_le(ts)),
            Check::account(&state_key)
                .data(&unix_time_state(true, stored))
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
            Check::return_data(&timestamp_le(ts)),
            Check::account(&state_key)
                .data(&unix_time_state(true, stored))
                .build(),
        ],
    );
}

/// Assembly honesty pin: real syscall emission and the offset-32 load.
#[test]
fn product_assembly_emits_clock_unix_timestamp() {
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
    assert!(
        text.contains("clock_unix_timestamp"),
        "assembly must annotate clock_unix_timestamp"
    );
    assert!(
        text.contains("unix_timestamp @32"),
        "assembly must load Clock.unix_timestamp at offset 32"
    );
    assert!(
        !text.contains("TEST-PREACTIVATION"),
        "product assembly must not carry preactivation banner"
    );
}
