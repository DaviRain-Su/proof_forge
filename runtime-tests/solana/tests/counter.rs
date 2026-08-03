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

/// Spec (d): overflow → Custom(0x1001); full data hold (arithmetic path).
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

/// Spec (e): unknown 8-byte discriminator → exit 1 → Custom(1); full snapshot hold.
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
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Spec (f): owner != current_program → check path exit 1; full snapshot hold.
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
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

// ─── #113 V1 single-state-account security negative matrix ───────────────────
// Each case flips exactly one precondition and expects Custom(CHECK_OR_UNKNOWN).
// Full exact account snapshots prove no commit (not Check::data alone).

/// Initializer requires account[0] is_signer.
#[test]
fn counter_initialize_missing_signer_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 1);
    // writable=true, signer=false (missing signer)
    let ix = build_ix(program_id, state_key, &disc, &[5], true, false);
    let account = state_account(&program_id, counter_state(false, 0));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Mutation requires account[0] is_writable.
#[test]
fn counter_increment_not_writable_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);
    // writable=false, signer=false
    let ix = build_ix(program_id, state_key, &disc, &[3], false, false);
    let account = state_account(&program_id, counter_state(true, 5));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Double initialize: header must be uninitialized (0).
#[test]
fn counter_double_initialize_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 1);
    let ix = build_ix(program_id, state_key, &disc, &[9], true, true);
    let account = state_account(&program_id, counter_state(true, 1));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Entry (mutate) on uninitialized header fails closed.
#[test]
fn counter_increment_uninitialized_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);
    let ix = build_ix(program_id, state_key, &disc, &[1], true, false);
    let account = state_account(&program_id, counter_state(false, 0));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// View on uninitialized header fails closed.
#[test]
fn counter_get_uninitialized_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let account = state_account(&program_id, counter_state(false, 0));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Malformed initialized marker (nonzero but not layout marker) fails closed.
#[test]
fn counter_malformed_marker_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let mut data = counter_state(false, 7);
    // Forge a wrong header u64 while keeping field payload.
    data[..8].copy_from_slice(&0xdead_beef_u64.to_le_bytes());
    let account = state_account(&program_id, data);
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Account data shorter than exactDataLen (16) fails data_len check.
#[test]
fn counter_short_account_data_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let account = state_account(&program_id, vec![0u8; 8]);
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Account data longer than exactDataLen (16) fails data_len check.
#[test]
fn counter_long_account_data_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let mut data = counter_state(true, 3);
    data.extend_from_slice(&[0u8; 8]);
    let account = state_account(&program_id, data);
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Zero accounts in the instruction meta list (num_accounts == 0).
#[test]
fn counter_zero_accounts_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let data = instruction_data(&disc, &[]);
    let ix = Instruction::new_with_bytes(program_id, &data, vec![]);
    // State remains in the account store but is not passed to the program.
    let account = state_account(&program_id, counter_state(true, 4));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Two distinct accounts → num_accounts == 2 fails closed.
#[test]
fn counter_two_distinct_accounts_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let other_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let data = instruction_data(&disc, &[]);
    let ix = Instruction::new_with_bytes(
        program_id,
        &data,
        vec![
            AccountMeta::new_readonly(state_key, false),
            AccountMeta::new_readonly(other_key, false),
        ],
    );
    let state = state_account(&program_id, counter_state(true, 4));
    let other = state_account(&program_id, counter_state(true, 0));
    assert_custom1_preserves_exact_accounts(
        &mollusk,
        &ix,
        &[(state_key, state), (other_key, other)],
    );
}

/// Duplicate account meta encoding (same key twice) → num_accounts == 2.
#[test]
fn counter_duplicate_account_meta_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let data = instruction_data(&disc, &[]);
    let ix = Instruction::new_with_bytes(
        program_id,
        &data,
        vec![
            AccountMeta::new_readonly(state_key, false),
            AccountMeta::new_readonly(state_key, false),
        ],
    );
    let account = state_account(&program_id, counter_state(true, 4));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Instruction data length 0 (no discriminator).
#[test]
fn counter_instruction_len_0_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let ix = Instruction::new_with_bytes(
        program_id,
        &[],
        vec![AccountMeta::new_readonly(state_key, false)],
    );
    let account = state_account(&program_id, counter_state(true, 0));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Instruction data length 7 (< 8-byte discriminator).
#[test]
fn counter_instruction_len_7_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let ix = Instruction::new_with_bytes(
        program_id,
        &[1, 2, 3, 4, 5, 6, 7],
        vec![AccountMeta::new_readonly(state_key, false)],
    );
    let account = state_account(&program_id, counter_state(true, 0));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Discriminator present but param payload short of exact increment ABI (8+8).
#[test]
fn counter_instruction_short_after_disc_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);
    let mut data = instruction_data(&disc, &[]);
    // Only 4 of 8 param bytes.
    data.extend_from_slice(&1u32.to_le_bytes());
    let ix = Instruction::new_with_bytes(
        program_id,
        &data,
        vec![AccountMeta::new(state_key, false)],
    );
    let account = state_account(&program_id, counter_state(true, 5));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
}

/// Exact positive length already covered by counter_initialize/increment/get.
/// Trailing bytes after exact ABI length fail exact instruction_data_len.
#[test]
fn counter_instruction_trailing_bytes_custom_1() {
    assert_counter_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_counter_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);
    let mut data = instruction_data(&disc, &[3]);
    data.push(0xaa);
    let ix = Instruction::new_with_bytes(
        program_id,
        &data,
        vec![AccountMeta::new(state_key, false)],
    );
    let account = state_account(&program_id, counter_state(true, 5));
    assert_custom1_preserves_exact_accounts(&mollusk, &ix, &[(state_key, account)]);
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
