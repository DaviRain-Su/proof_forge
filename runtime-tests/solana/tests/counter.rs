//! Mollusk runtime differential for the product Counter ELF (S3a).
//!
//! Reference authority: `Tests/Semantic/ReferenceV1.lean` `testCounterReferenceSlice`
//! (init → increment → get → arithmeticOverflow on UInt64 max+1) and
//! `ProofForgeV2/Examples/Counter.lean`.
//!
//! Env (required; no hard-coded product paths):
//! - `PROOF_FORGE_COUNTER_OUT` — complete published Counter output tree.
//!
//! Both `Counter.so` and `Counter.sbpf-plan` are resolved from exact manifest
//! descriptors and rehashed immediately before use.
//!
//! Mollusk API used (mollusk-svm 0.13.4 / mollusk-svm-result 0.13.4):
//! - verified ELF bytes are registered with `add_program_with_loader_and_elf`
//! - `process_and_validate_instruction(ix, accounts, checks)`
//! - `Check::success()`, `Check::err(ProgramError::Custom(code))`,
//!   `Check::return_data(&[u8])`, `Check::account(&pk).data(&[u8]).build()`
//! - **No** `Check::logs` / log fields on `InstructionResult` (0.13.4).
//!   Event log assertion (S3b Events) uses `Mollusk.logger = Some(LogCollector)`.

mod common;

use {
    common::*,
    mollusk_svm::result::Check,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
};

fn counter_fields() -> [StateField; 1] {
    single_field("count")
}

fn counter_state(initialized: bool, count: u64) -> Vec<u8> {
    state_data(&counter_fields(), initialized, &[count])
}

fn assert_counter_plan() {
    assert_discriminators_match_plan(
        &counter_plan_bytes(),
        &[("initialize", 1), ("increment", 1), ("get", 0)],
    );
}

/// Reference: init(7) → state count=7, Unit return (no return_data).
#[test]
fn counter_initialize_sets_count() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 1);

    let ix = build_ix(program_id, state_key, &disc, &[5], true, true);
    let account = state_account(&program_id, counter_state(false, 0));

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&counter_state(true, 5))
                .build(),
        ],
    );
}

/// Spec (b): after init(5), increment(3) → 8.
#[test]
fn counter_increment_updates_and_returns() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);

    let ix = build_ix(program_id, state_key, &disc, &[3], true, false);
    let account = state_account(&program_id, counter_state(true, 5));
    let expected_return = 8u64.to_le_bytes();

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&expected_return),
            Check::account(&state_key)
                .data(&counter_state(true, 8))
                .build(),
        ],
    );
}

/// Spec (c): get() after count=8 → return 8 LE.
#[test]
fn counter_get_returns_count() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);

    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let account = state_account(&program_id, counter_state(true, 8));
    let expected_return = 8u64.to_le_bytes();

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&expected_return),
            Check::account(&state_key)
                .data(&counter_state(true, 8))
                .build(),
        ],
    );
}

/// Spec (d): overflow → Custom(0x1001).
#[test]
fn counter_increment_overflow_custom_0x1001() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);

    let pre = counter_state(true, u64::MAX);
    let ix = build_ix(program_id, state_key, &disc, &[1], true, false);
    let account = state_account(&program_id, pre.clone());

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Spec (e): unknown 8-byte discriminator → exit 1 → Custom(1).
#[test]
fn counter_unknown_discriminator_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();

    let unknown = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];
    let ix = Instruction::new_with_bytes(
        program_id,
        &unknown,
        vec![AccountMeta::new(state_key, false)],
    );
    let account = state_account(&program_id, counter_state(true, 0));

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
}

/// Spec (f): owner != current_program → check path exit 1.
#[test]
fn counter_wrong_owner_check_fails() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);

    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let foreign = Pubkey::new_unique();
    let account = state_account(&foreign, counter_state(true, 8));

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
}

/// End-to-end chain matching the Reference Counter trace shape.
#[test]
fn counter_reference_trace_chain() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();

    let init_disc = instruction_discriminator("initialize", 1);
    let inc_disc = instruction_discriminator("increment", 1);
    let get_disc = instruction_discriminator("get", 0);

    let init_ix = build_ix(program_id, state_key, &init_disc, &[7], true, true);
    let result = mollusk.process_and_validate_instruction(
        &init_ix,
        &[(state_key, state_account(&program_id, counter_state(false, 0)))],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&counter_state(true, 7))
                .build(),
        ],
    );
    let after_init = result
        .resulting_accounts
        .into_iter()
        .find(|(k, _)| k == &state_key)
        .expect("state account after init")
        .1;

    let inc_ix = build_ix(program_id, state_key, &inc_disc, &[5], true, false);
    let result = mollusk.process_and_validate_instruction(
        &inc_ix,
        &[(state_key, after_init)],
        &[
            Check::success(),
            Check::return_data(&12u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&counter_state(true, 12))
                .build(),
        ],
    );
    let after_inc = result
        .resulting_accounts
        .into_iter()
        .find(|(k, _)| k == &state_key)
        .expect("state account after increment")
        .1;

    let get_ix = build_ix(program_id, state_key, &get_disc, &[], false, false);
    mollusk.process_and_validate_instruction(
        &get_ix,
        &[(state_key, after_inc)],
        &[
            Check::success(),
            Check::return_data(&12u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&counter_state(true, 12))
                .build(),
        ],
    );
}

/// Sanity: the manifest-bound Plan is nonempty and ELF bytes have ELF magic.
#[test]
fn product_artifacts_present() {
    let output = counter_output_dir();
    let bytes = read_manifest_leaf_bytes(
        &output,
        "Counter",
        "Counter.so",
        "finalized-extra",
    )
    .expect("Counter ELF binding");
    assert!(bytes.len() > 64, "Counter.so too small: {}", bytes.len());
    assert_eq!(&bytes[..4], b"\x7fELF", "Counter.so is not ELF");
    assert!(!counter_plan_bytes().is_empty(), "plan missing or empty");
    assert_counter_plan();
    assert_ne!(layout_marker(&counter_fields()), 0);
}
