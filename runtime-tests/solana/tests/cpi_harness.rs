//! Mollusk dual-program CPI harness tests (#115).
//!
//! Requires `PROOF_FORGE_HARNESS_OUT` from `scripts/solana_harness_build.sh`.
//! This is pinned-runtime feasibility evidence only: no product profile,
//! resolver support, or catalog admission is enabled here.

#[allow(dead_code)]
mod common;

use {
    common::*,
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
    solana_account::Account,
    solana_instruction::{error::InstructionError, AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
};

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn companion_program_meta(companion_id: Pubkey) -> (Pubkey, Account) {
    (
        companion_id,
        create_program_account_loader_v3(&companion_id),
    )
}

fn unsigned_accounts(
    companion_id: Pubkey,
    counter_key: Pubkey,
    counter: Account,
    counter_writable: bool,
    counter_signer: bool,
) -> (Vec<AccountMeta>, Vec<(Pubkey, Account)>) {
    let (program_key, program_account) = companion_program_meta(companion_id);
    let counter_meta = if counter_writable {
        AccountMeta::new(counter_key, counter_signer)
    } else {
        AccountMeta::new_readonly(counter_key, counter_signer)
    };
    (
        vec![counter_meta, AccountMeta::new_readonly(program_key, false)],
        vec![(counter_key, counter), (program_key, program_account)],
    )
}

struct SignedCase {
    counter_key: Pubkey,
    seed_authority: Pubkey,
    authority_pda: Pubkey,
    bump: u8,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

fn signed_case(
    caller_id: Pubkey,
    companion_id: Pubkey,
    count: u64,
    seed_tag: u64,
    seed_authority_signer: bool,
) -> SignedCase {
    let counter_key = fixed_key(0x10);
    let seed_authority = fixed_key(0x11);
    let (authority_pda, bump) =
        find_pda_current_program_tagged_v1(&caller_id, &seed_authority, seed_tag);
    let counter = companion_counter_account(&companion_id, count);
    let pda_account = Account::new(BASE_LAMPORTS, 0, &caller_id);
    let authority_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
    let (program_key, program_account) = companion_program_meta(companion_id);
    let metas = vec![
        AccountMeta::new(counter_key, false),
        AccountMeta::new_readonly(authority_pda, false),
        AccountMeta::new_readonly(seed_authority, seed_authority_signer),
        AccountMeta::new_readonly(program_key, false),
    ];
    let accounts = vec![
        (counter_key, counter),
        (authority_pda, pda_account),
        (seed_authority, authority_account),
        (program_key, program_account),
    ];
    SignedCase {
        counter_key,
        seed_authority,
        authority_pda,
        bump,
        metas,
        accounts,
    }
}

fn parser_only_roles(
    companion_id: Pubkey,
    count: usize,
) -> (Vec<AccountMeta>, Vec<(Pubkey, Account)>) {
    if count == 0 {
        return (Vec::new(), Vec::new());
    }
    let mut metas = Vec::with_capacity(count);
    let mut accounts = Vec::with_capacity(count);
    for index in 0..count - 1 {
        let key = fixed_key(0x60 + index as u8);
        let data_len = index % 9;
        let account = Account::new(BASE_LAMPORTS, data_len, &Pubkey::default());
        metas.push(AccountMeta::new_readonly(key, false));
        accounts.push((key, account));
    }
    let (program_key, program_account) = companion_program_meta(companion_id);
    metas.push(AccountMeta::new_readonly(program_key, false));
    accounts.push((program_key, program_account));
    (metas, accounts)
}

#[test]
fn assembly_parser_exercises_zero_one_sixteen_and_rejects_seventeen_roles() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    for count in [0usize, 1, 16, 17] {
        let (metas, accounts) = parser_only_roles(companion_id, count);
        let ix = Instruction::new_with_bytes(
            caller_id,
            &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 0),
            metas,
        );
        assert_failure_preserves_exact_accounts(
            &mollusk,
            &ix,
            &accounts,
            Check::err(ProgramError::Custom(1)),
        );
    }
}

#[test]
fn harness_manifest_closed_behavior_mutations_fail() {
    let raw = committed_harness_manifest_bytes();
    validate_harness_manifest_bytes(&raw).expect("committed manifest");
    let base: serde_json::Value = serde_json::from_slice(&raw).unwrap();
    let mutations = vec![
        ("/schema", serde_json::json!("wrong")),
        ("/issue", serde_json::json!(116)),
        ("/sbpf", serde_json::json!("0.2.3")),
        ("/runtimeOracle/molluskSvm", serde_json::json!("0.13.5")),
        ("/runtimeOracle/agaveSyscalls", serde_json::json!("4.0.1")),
        (
            "/runtimeOracle/solanaProgramRuntime",
            serde_json::json!("4.0.1"),
        ),
        ("/programIds/callerHex", serde_json::json!("00")),
        ("/programIds/companionHex", serde_json::json!("00")),
        ("/opcodes/invokeSuccess", serde_json::json!(9)),
        ("/opcodes/invokeFail", serde_json::json!(9)),
        ("/opcodes/invokeSigned", serde_json::json!(9)),
        ("/opcodes/invokeSignedFail", serde_json::json!(9)),
        ("/opcodes/forgeWritable", serde_json::json!(9)),
        ("/opcodes/forgeSigner", serde_json::json!(9)),
        (
            "/callerInstruction/unsignedLayout",
            serde_json::json!("wrong"),
        ),
        ("/callerInstruction/unsignedLen", serde_json::json!(8)),
        (
            "/callerInstruction/signedLayout",
            serde_json::json!("wrong"),
        ),
        ("/callerInstruction/signedLen", serde_json::json!(17)),
        ("/companionInstruction/layout", serde_json::json!("wrong")),
        ("/companionInstruction/len", serde_json::json!(8)),
        (
            "/companionInstruction/tags/checkedAdd",
            serde_json::json!(9),
        ),
        (
            "/companionInstruction/tags/failAfterWrite",
            serde_json::json!(9),
        ),
        (
            "/companionInstruction/tags/checkedAddRequireSigner",
            serde_json::json!(9),
        ),
        (
            "/companionInstruction/tags/failAfterWriteRequireSigner",
            serde_json::json!(9),
        ),
        ("/cStructSizes/SolInstruction", serde_json::json!(39)),
        ("/cStructSizes/SolAccountMeta", serde_json::json!(15)),
        ("/cStructSizes/SolAccountInfo", serde_json::json!(55)),
        ("/cStructSizes/SolSignerSeed", serde_json::json!(15)),
        ("/cStructSizes/SolSignerSeeds", serde_json::json!(15)),
        ("/abiV1/fullPrefixBytes", serde_json::json!(87)),
        ("/abiV1/maxPermittedDataIncrease", serde_json::json!(10239)),
        ("/abiV1/marker", serde_json::json!(254)),
        ("/abiV1/originalDataLenWire", serde_json::json!(1)),
        ("/abiV1/rentEpoch", serde_json::json!(0)),
        ("/abiV1/align", serde_json::json!(4)),
        ("/abiV1/productCaps/outerRoles", serde_json::json!(15)),
        ("/abiV1/productCaps/cpiMetas", serde_json::json!(15)),
        ("/abiV1/productCaps/signerGroups", serde_json::json!(3)),
        ("/abiV1/productCaps/seedSlices", serde_json::json!(15)),
        ("/abiV1/productCaps/bytesPerSeed", serde_json::json!(31)),
        ("/outerRoles/unsigned", serde_json::json!(["counter"])),
        ("/outerRoles/signed", serde_json::json!(["counter"])),
        ("/pda/recipe", serde_json::json!("wrong")),
        ("/pda/seed0Utf8", serde_json::json!("wrong")),
        ("/pda/seed0Hex", serde_json::json!("00")),
        ("/pda/canonicalBumpSearch", serde_json::json!("255..0")),
        ("/pda/bump0Rejected", serde_json::json!(false)),
        ("/expectedElfSha256/caller", serde_json::json!("bad")),
        ("/expectedElfSize/companion", serde_json::json!(0)),
        ("/reproducibilityNote", serde_json::json!("")),
    ];
    for (pointer, replacement) in mutations {
        let mut mutated = base.clone();
        *mutated
            .pointer_mut(pointer)
            .expect("manifest mutation path") = replacement;
        let encoded = serde_json::to_vec(&mutated).unwrap();
        assert!(
            validate_harness_manifest_bytes(&encoded).is_err(),
            "mutation unexpectedly accepted: {pointer}"
        );
    }
    let mut unknown = base;
    unknown
        .as_object_mut()
        .unwrap()
        .insert("unknown".to_string(), serde_json::json!(true));
    assert!(validate_harness_manifest_bytes(&serde_json::to_vec(&unknown).unwrap()).is_err());
}

#[test]
fn manifest_bound_dual_loader_v3_registration_executes() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    assert_eq!(caller_id, harness_caller_id());
    assert_eq!(companion_id, harness_companion_id());
    let counter_key = fixed_key(0x20);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 0),
        metas,
    );
    mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::success(),
            Check::return_data(&[]),
            Check::account(&counter_key)
                .data(&5u64.to_le_bytes())
                .build(),
        ],
    );
}

#[test]
fn invoke_success_updates_counter_and_clears_forced_inner_return_data() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x21);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 3),
        metas,
    );
    mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::success(),
            // Caller seeded stale:v1; companion verified CPI-entry clearing and
            // then set inner:v1. The generated success path must clear both.
            Check::return_data(&[]),
            Check::account(&counter_key)
                .data(&8u64.to_le_bytes())
                .build(),
        ],
    );
}

#[test]
fn invoke_unsigned_preserves_delta_high_byte() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x2d);
    let counter = companion_counter_account(&companion_id, 0);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let delta = 1u64 << 56;
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, delta),
        metas,
    );
    mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::success(),
            Check::return_data(&[]),
            Check::account(&counter_key)
                .data(&delta.to_le_bytes())
                .build(),
        ],
    );
}

#[test]
fn companion_failure_propagates_keeps_telemetry_and_rolls_back_accounts() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x22);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_FAIL, 3),
        metas,
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        &[
            Check::err(ProgramError::Custom(1)),
            // The failed callee wrote this after mutating its counter. Caller
            // immediately propagates and therefore must not run success clear.
            Check::return_data(HARNESS_FAILURE_RETURN_DATA),
        ],
    );
}

#[test]
fn writable_privilege_escalation_is_exact_and_rolls_back() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x23);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, false, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_FORGE_WRITABLE, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::instruction_err(InstructionError::PrivilegeEscalation),
    );
}

#[test]
fn signer_privilege_escalation_is_exact_and_rolls_back() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x24);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_FORGE_SIGNER, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::instruction_err(InstructionError::PrivilegeEscalation),
    );
}

#[test]
fn unsigned_counter_extra_outer_signer_is_rejected_before_cpi() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x2b);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, true);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn unsigned_counter_executable_flag_is_rejected_before_cpi() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x2c);
    let mut counter = companion_counter_account(&companion_id, 5);
    counter.executable = true;
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn role_permutation_is_exact_shape_failure() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x25);
    let counter = companion_counter_account(&companion_id, 5);
    let (program_key, program_account) = companion_program_meta(companion_id);
    let metas = vec![
        AccountMeta::new_readonly(program_key, false),
        AccountMeta::new(counter_key, false),
    ];
    let accounts = vec![(program_key, program_account), (counter_key, counter)];
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn duplicate_outer_role_marker_is_rejected_before_full_record_read() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x26);
    let counter = companion_counter_account(&companion_id, 5);
    let (program_key, program_account) = companion_program_meta(companion_id);
    let metas = vec![
        AccountMeta::new(counter_key, false),
        AccountMeta::new(counter_key, false),
        AccountMeta::new_readonly(program_key, false),
    ];
    let accounts = vec![(counter_key, counter), (program_key, program_account)];
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn missing_cached_program_is_exact_unsupported_program_id() {
    let caller_id = harness_caller_id();
    let companion_id = harness_companion_id();
    let caller_elf = read_harness_elf("caller");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &caller_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &caller_elf,
    );

    let counter_key = fixed_key(0x27);
    let counter = companion_counter_account(&companion_id, 5);
    let (metas, accounts) = unsigned_accounts(companion_id, counter_key, counter, true, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::instruction_err(InstructionError::UnsupportedProgramId),
    );
}

#[test]
fn non_executable_program_substitution_is_exact_shape_failure() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x28);
    let counter = companion_counter_account(&companion_id, 5);
    let mut fake = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
    fake.executable = false;
    let metas = vec![
        AccountMeta::new(counter_key, false),
        AccountMeta::new_readonly(companion_id, false),
    ];
    let accounts = vec![(counter_key, counter), (companion_id, fake)];
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn wrong_executable_program_key_is_exact_shape_failure() {
    let (mollusk, caller_id, _companion_id) = make_harness_mollusk();
    let wrong_program_id = fixed_key(0x44);
    let counter_key = fixed_key(0x29);
    let counter = companion_counter_account(&harness_companion_id(), 5);
    let wrong_program_account = create_program_account_loader_v3(&wrong_program_id);
    let metas = vec![
        AccountMeta::new(counter_key, false),
        AccountMeta::new_readonly(wrong_program_id, false),
    ];
    let accounts = vec![
        (counter_key, counter),
        (wrong_program_id, wrong_program_account),
    ];
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn invoke_signed_success_uses_exact_pda_group_and_all_outer_infos() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, seed_tag, case.bump),
        case.metas,
    );
    mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&[]),
            Check::account(&case.counter_key)
                .data(&15u64.to_le_bytes())
                .build(),
        ],
    );
}

#[test]
fn invoke_signed_preserves_delta_high_byte() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let case = signed_case(caller_id, companion_id, 0, seed_tag, true);
    let delta = 1u64 << 56;
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, delta, seed_tag, case.bump),
        case.metas,
    );
    mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&[]),
            Check::account(&case.counter_key)
                .data(&delta.to_le_bytes())
                .build(),
        ],
    );
}

#[test]
fn invoke_signed_callee_failure_keeps_telemetry_and_rolls_back() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED_FAIL, 5, seed_tag, case.bump),
        case.metas,
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(1)),
            Check::return_data(HARNESS_FAILURE_RETURN_DATA),
        ],
    );
}

#[test]
fn invoke_signed_valid_but_noncanonical_bump_is_rejected_by_canonical_preflight() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    let tag_le = seed_tag.to_le_bytes();
    let noncanonical_bump = (1u8..=255)
        .rev()
        .filter(|bump| *bump != case.bump)
        .find(|bump| {
            Pubkey::create_program_address(
                &[
                    HARNESS_PDA_SEED0,
                    case.seed_authority.as_ref(),
                    &tag_le,
                    &[*bump],
                ],
                &caller_id,
            )
            .is_ok()
        })
        .expect("valid noncanonical bump");
    let noncanonical_address = Pubkey::create_program_address(
        &[
            HARNESS_PDA_SEED0,
            case.seed_authority.as_ref(),
            &tag_le,
            &[noncanonical_bump],
        ],
        &caller_id,
    )
    .unwrap();
    assert_ne!(noncanonical_address, case.authority_pda);

    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, seed_tag, noncanonical_bump),
        case.metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn invoke_signed_matching_noncanonical_pda_and_bump_are_still_rejected() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let mut case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    let tag_le = seed_tag.to_le_bytes();
    let noncanonical_bump = (1u8..=255)
        .rev()
        .filter(|bump| *bump != case.bump)
        .find(|bump| {
            Pubkey::create_program_address(
                &[
                    HARNESS_PDA_SEED0,
                    case.seed_authority.as_ref(),
                    &tag_le,
                    &[*bump],
                ],
                &caller_id,
            )
            .is_ok()
        })
        .expect("valid noncanonical bump");
    let noncanonical_address = Pubkey::create_program_address(
        &[
            HARNESS_PDA_SEED0,
            case.seed_authority.as_ref(),
            &tag_le,
            &[noncanonical_bump],
        ],
        &caller_id,
    )
    .unwrap();
    assert_ne!(noncanonical_address, case.authority_pda);
    case.metas[1] = AccountMeta::new_readonly(noncanonical_address, false);
    case.accounts[1] = (
        noncanonical_address,
        Account::new(BASE_LAMPORTS, 0, &caller_id),
    );
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, seed_tag, noncanonical_bump),
        case.metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn invoke_signed_wrong_seed_tag_is_rejected_by_canonical_preflight() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let wrong_tag = 43u64;
    let case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    let (wrong_address, wrong_bump) =
        find_pda_current_program_tagged_v1(&caller_id, &case.seed_authority, wrong_tag);
    assert_ne!(wrong_address, case.authority_pda);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, wrong_tag, wrong_bump),
        case.metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn invoke_signed_bump_zero_is_rejected_before_syscall() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, seed_tag, 0),
        case.metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn invoke_signed_missing_seed_authority_business_signature_is_rejected() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let case = signed_case(caller_id, companion_id, 10, seed_tag, false);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, seed_tag, case.bump),
        case.metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn invoke_signed_pda_must_not_be_an_outer_business_signer() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let seed_tag = 42u64;
    let mut case = signed_case(caller_id, companion_id, 10, seed_tag, true);
    case.metas[1] = AccountMeta::new_readonly(case.authority_pda, true);
    let ix = Instruction::new_with_bytes(
        caller_id,
        &harness_ix_signed(HARNESS_OP_INVOKE_SIGNED, 5, seed_tag, case.bump),
        case.metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn resource_observation_is_nonzero_on_success_and_failure() {
    let (mollusk, caller_id, companion_id) = make_harness_mollusk();
    let counter_key = fixed_key(0x2a);
    let counter = companion_counter_account(&companion_id, 1);
    let (metas, accounts) =
        unsigned_accounts(companion_id, counter_key, counter.clone(), true, false);
    let ok = mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            caller_id,
            &harness_ix_unsigned(HARNESS_OP_INVOKE_SUCCESS, 1),
            metas.clone(),
        ),
        &accounts,
        &[Check::success()],
    );
    assert!(ok.compute_units_consumed > 0);
    let _observed_not_pinned = ok.execution_time;

    let fail = mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            caller_id,
            &harness_ix_unsigned(HARNESS_OP_INVOKE_FAIL, 1),
            metas,
        ),
        &[(counter_key, counter), companion_program_meta(companion_id)],
        &[
            Check::err(ProgramError::Custom(1)),
            Check::return_data(HARNESS_FAILURE_RETURN_DATA),
        ],
    );
    assert!(fail.compute_units_consumed > 0);
}
