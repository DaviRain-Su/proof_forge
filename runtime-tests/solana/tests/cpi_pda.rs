//! #120 production-code-generated PDA / signed companion CPI runtime closure.
//!
//! The loaded ELF is generated through the real Semantic→preflight→PDA
//! IR→emitter chain (resolveSolanaCpiPdaIRV1 + emitCpiPdaSbpfV1). It remains
//! explicitly test-preactivation: dual-program with the #115 companion, real
//! `sol_try_find_program_address` + `sol_invoke_signed_c`, no
//! proof-forge.output.v1 artifact, and no product sync capability.

#[allow(dead_code)]
mod common;

use {
    common::*,
    mollusk_svm::{program::create_program_account_loader_v3, result::Check},
    serde_json::json,
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
};

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn companion_pda_fields() -> [StateField; 1] {
    single_field("value")
}

fn companion_pda_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&companion_pda_fields(), initialized, &[value])
}

/// Outer roles for signed invoke:
///   0 state (writable)
///   1 account / companion counter (writable)
///   2 authorityPda (readonly, not outer business signer)
///   3 seedAuthority (readonly, required business signer)
///   4 companion program (readonly executable)
#[derive(Clone)]
struct SignedInvokeCase {
    state_key: Pubkey,
    account_key: Pubkey,
    authority_pda: Pubkey,
    seed_authority: Pubkey,
    companion_program_key: Pubkey,
    seed_tag: u64,
    bump: u8,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl SignedInvokeCase {
    fn new(
        program_id: Pubkey,
        companion_id: Pubkey,
        state_value: u64,
        counter: u64,
        seed_tag: u64,
        seed_authority_signer: bool,
    ) -> Self {
        let state_key = fixed_key(0x20);
        let account_key = fixed_key(0x21);
        let seed_authority = fixed_key(0x22);
        let (authority_pda, bump) =
            find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
        let companion_program_key = companion_id;

        let state = state_account(&program_id, companion_pda_state(true, state_value));
        let companion_counter = companion_counter_account(&companion_id, counter);
        let pda_account = Account::new(BASE_LAMPORTS, 0, &program_id);
        let authority_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let companion_program = create_program_account_loader_v3(&companion_program_key);

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(account_key, false),
            AccountMeta::new_readonly(authority_pda, false),
            AccountMeta::new_readonly(seed_authority, seed_authority_signer),
            AccountMeta::new_readonly(companion_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (account_key, companion_counter),
            (authority_pda, pda_account),
            (seed_authority, authority_account),
            (companion_program_key, companion_program),
        ];
        Self {
            state_key,
            account_key,
            authority_pda,
            seed_authority,
            companion_program_key,
            seed_tag,
            bump,
            metas,
            accounts,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, delta: u64) -> Instruction {
        self.instruction_with_seed(program_id, handler_id, self.seed_tag, self.bump, delta)
    }

    fn instruction_with_seed(
        &self,
        program_id: Pubkey,
        handler_id: u64,
        seed_tag: u64,
        bump: u8,
        delta: u64,
    ) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_pda_signed_ix_data(handler_id, seed_tag, bump, delta),
            self.metas.clone(),
        )
    }
}

fn find_noncanonical_pda_below(
    program_id: &Pubkey,
    seed_authority: &Pubkey,
    seed_tag: u64,
    canonical_bump: u8,
) -> (Pubkey, u8) {
    let tag_le = seed_tag.to_le_bytes();
    for bump in (1..canonical_bump).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[
            HARNESS_PDA_SEED0,
            seed_authority.as_ref(),
            &tag_le,
            &bump_slice,
        ];
        if let Ok(address) = Pubkey::create_program_address(seeds, program_id) {
            return (address, bump);
        }
    }
    panic!("chosen fixture has no valid noncanonical bump below canonical bump");
}

fn assert_success_exact_snapshot(
    result: &mollusk_svm::result::InstructionResult,
    case: &SignedInvokeCase,
    expected_state: u64,
    expected_counter: u64,
) {
    let mut expected_accounts = case.accounts.clone();
    expected_accounts
        .iter_mut()
        .find(|(key, _)| *key == case.state_key)
        .expect("expected state")
        .1
        .data = companion_pda_state(true, expected_state);
    expected_accounts
        .iter_mut()
        .find(|(key, _)| *key == case.account_key)
        .expect("expected counter")
        .1
        .data = expected_counter.to_le_bytes().to_vec();
    let expected_keys: Vec<Pubkey> = expected_accounts.iter().map(|(key, _)| *key).collect();
    let expected_observed: Vec<(Pubkey, Option<Account>)> = expected_accounts
        .iter()
        .map(|(key, account)| (*key, Some(account.clone())))
        .collect();
    let actual_observed: Vec<(Pubkey, Option<Account>)> = result
        .resulting_accounts
        .iter()
        .map(|(key, account)| (*key, Some(account.clone())))
        .collect();
    assert_eq!(
        snapshot_exact_accounts(&expected_keys, &actual_observed).expect("actual success snapshot"),
        snapshot_exact_accounts(&expected_keys, &expected_observed)
            .expect("expected success snapshot"),
        "success may change only caller-state and companion-counter data"
    );
}

#[test]
fn committed_manifest_schema_is_exact_preactivation_evidence() {
    let manifest = committed_cpi_pda_manifest_bytes();
    validate_cpi_pda_manifest_bytes(&manifest).expect("committed PDA manifest");
    let value: serde_json::Value = serde_json::from_slice(&manifest).unwrap();
    assert_eq!(
        value["schema"],
        json!("proof-forge.solana.cpi-pda-runtime.v1")
    );
    assert_eq!(value["issue"], json!(120));
    assert_eq!(value["boundary"]["productArtifact"], json!(false));
    assert_eq!(value["boundary"]["testPreactivation"], json!(true));
    assert_eq!(value["boundary"]["activationDenied"], json!(true));
    assert_eq!(value["pda"]["canonicalBumpSearch"], json!("255..1"));
    assert_eq!(value["pda"]["bump0Rejected"], json!(true));
    assert_eq!(
        value["companion"]["elfSha256"],
        json!("c8738f1220c49c309ffe820ca397ae25540d6be29c6153934abd8548fa08c4b9")
    );
    assert_eq!(value["companion"]["elfSize"], json!(1776));
    assert_eq!(value["expectedAssembly"]["size"], json!(62066));
    assert_eq!(
        value["expectedAssembly"]["sha256"],
        json!("6c149fa76e24873cc170f3f5ca9c053d1a9f8e463a036bce679f74f9a72bbf6b")
    );
    assert_eq!(value["expectedElf"]["size"], json!(24856));
    assert_eq!(
        value["expectedElf"]["sha256"],
        json!("f7c167adf28beb4f4d63f6538312ecc148a2a0d825115697489a529489c47c0d")
    );
}

#[test]
fn pda_manifest_closed_identity_mutations_fail() {
    let raw = committed_cpi_pda_manifest_bytes();
    validate_cpi_pda_manifest_bytes(&raw).expect("committed PDA manifest");
    let base: serde_json::Value = serde_json::from_slice(&raw).unwrap();
    let mutations = [
        ("/schema", json!("wrong")),
        ("/issue", json!(119)),
        ("/sbpf", json!("0.2.3")),
        ("/runtimeOracle/molluskSvm", json!("0.13.5")),
        ("/fixture/sourceSha256", json!("00")),
        ("/profile/id", json!("solana-sbpf-elf-v1")),
        ("/extension/version", json!("1.0.1")),
        ("/boundary/productArtifact", json!(true)),
        ("/boundary/activationDenied", json!(false)),
        ("/programIdHex", json!("00")),
        ("/companionProgramIdHex", json!("00")),
        ("/companion/elfSha256", json!("00")),
        ("/companion/elfSize", json!(1777)),
        ("/handlers/invokeSigned", json!(9)),
        ("/handlers/invokeSignedThenOverflow", json!(9)),
        ("/pda/recipe", json!("wrong")),
        ("/pda/canonicalBumpSearch", json!("255..0")),
        ("/pda/bump0Rejected", json!(false)),
        ("/expectedAssembly/sha256", json!("00")),
        ("/expectedElf/size", json!(1)),
        ("/reproducibilityNote", json!("")),
    ];
    for (pointer, replacement) in mutations {
        let mut mutated = base.clone();
        *mutated
            .pointer_mut(pointer)
            .unwrap_or_else(|| panic!("missing mutation path {pointer}")) = replacement;
        let encoded = serde_json::to_vec(&mutated).unwrap();
        let result = validate_cpi_pda_manifest_bytes(&encoded);
        assert!(
            result.is_err(),
            "manifest mutation unexpectedly accepted: {pointer} ({result:?})"
        );
    }
}

#[test]
fn signed_ix_layout_is_exactly_25_bytes() {
    let data = cpi_pda_signed_ix_data(CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 42, 252, 5);
    assert_eq!(data.len(), CPI_PDA_SIGNED_IX_LEN);
    assert_eq!(&data[0..8], &CPI_PDA_INVOKE_SIGNED_HANDLER_ID.to_le_bytes());
    assert_eq!(&data[8..16], &42u64.to_le_bytes());
    assert_eq!(data[16], 252);
    assert_eq!(&data[17..25], &5u64.to_le_bytes());
}

#[test]
fn generated_assembly_and_elf_are_exact_preactivation() {
    let assembly = read_cpi_pda_assembly();
    let text = std::str::from_utf8(&assembly).expect("PDA assembly UTF-8");
    assert!(text.contains("TEST-PREACTIVATION ONLY"));
    assert!(text.contains("not a product artifact"));
    assert!(text.contains("call sol_try_find_program_address"));
    assert!(text.contains("call sol_invoke_signed_c"));
    assert!(text.contains("call sol_set_return_data"));
    assert!(!text.contains("0xec01"));
    assert!(!text.contains("ACC0_"));
    let elf = read_cpi_pda_elf();
    assert!(elf.starts_with(b"\x7fELF"));
}

#[test]
fn invoke_signed_success_canonical_key_bump_and_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    assert_ne!(case.bump, 0, "canonical search rejects bump 0");
    let ix = case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5);
    // Pre: caller 10; post success: value = 10+1+2 = 13; companion 7+5 = 12.
    // Caller return data = final value 13; no inner return leakage.
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let post_state = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.state_key)
        .map(|(_, a)| a)
        .expect("state present");
    let post_counter = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.account_key)
        .map(|(_, a)| a)
        .expect("counter present");
    assert_eq!(
        post_state.data,
        companion_pda_state(true, 13),
        "caller state must commit pre-CPI (+1) and post-CPI (+2) writes"
    );
    assert_eq!(
        post_counter.data,
        12u64.to_le_bytes().to_vec(),
        "companion counter must be mutated exactly once"
    );
    assert_success_exact_snapshot(&result, &case, 13, 12);
}

#[test]
fn seed_tag_and_delta_high_bytes_reach_companion() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    // High-bit seed tag still yields a canonical PDA via independent search.
    let seed_tag = 0x8000_0000_0000_002Au64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    let delta = 0x8000_0000_0000_0005u64;
    let expected_counter = 7u64.wrapping_add(delta);
    assert_ne!(
        expected_counter.to_le_bytes()[7],
        0,
        "high-byte coverage requires a non-zero MSB after companion add"
    );
    assert_ne!(seed_tag.to_le_bytes()[7], 0, "seedTag high byte coverage");
    let ix = case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, delta);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let post_counter = result
        .resulting_accounts
        .iter()
        .find(|(key, _)| *key == case.account_key)
        .map(|(_, account)| account)
        .expect("counter present");
    assert_eq!(
        post_counter.data,
        expected_counter.to_le_bytes().to_vec(),
        "all eight little-endian delta bytes must reach the companion"
    );
    assert_success_exact_snapshot(&result, &case, 13, expected_counter);
}

#[test]
fn wrong_bump_with_canonical_key_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    let wrong_bump = if case.bump == 1 { 2 } else { case.bump - 1 };
    assert_ne!(wrong_bump, case.bump);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_with_seed(
            program_id,
            CPI_PDA_INVOKE_SIGNED_HANDLER_ID,
            seed_tag,
            wrong_bump,
            5,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn matching_noncanonical_key_and_bump_fail_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    let (noncanonical_key, noncanonical_bump) =
        find_noncanonical_pda_below(&program_id, &case.seed_authority, seed_tag, case.bump);
    assert_ne!(noncanonical_key, case.authority_pda);
    assert_ne!(noncanonical_bump, case.bump);
    case.metas[2] = AccountMeta::new_readonly(noncanonical_key, false);
    case.accounts[2] = (
        noncanonical_key,
        Account::new(BASE_LAMPORTS, 0, &program_id),
    );
    case.authority_pda = noncanonical_key;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_with_seed(
            program_id,
            CPI_PDA_INVOKE_SIGNED_HANDLER_ID,
            seed_tag,
            noncanonical_bump,
            5,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn wrong_key_with_canonical_bump_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    let wrong_pda = fixed_key(0x77);
    assert_ne!(wrong_pda, case.authority_pda);
    case.metas[2] = AccountMeta::new_readonly(wrong_pda, false);
    case.accounts[2] = (wrong_pda, Account::new(BASE_LAMPORTS, 0, &program_id));
    case.authority_pda = wrong_pda;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn wrong_seed_tag_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let wrong_tag = 43u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    let (wrong_address, wrong_bump) =
        find_pda_current_program_tagged_v1(&program_id, &case.seed_authority, wrong_tag);
    assert_ne!(wrong_address, case.authority_pda);
    // Keep outer metas on the original canonical key; encode the wrong tag.
    // Preflight must reject (tag/key/bump join fails).
    let _ = (wrong_address, wrong_bump);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_with_seed(
            program_id,
            CPI_PDA_INVOKE_SIGNED_HANDLER_ID,
            wrong_tag,
            case.bump,
            5,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn bump_zero_rejected_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_with_seed(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, seed_tag, 0, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn missing_seed_authority_signer_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn pda_incorrectly_outer_signer_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    case.metas[2] = AccountMeta::new_readonly(case.authority_pda, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn role_permutation_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    // Swap counter and companion program positions.
    case.metas.swap(1, 4);
    case.accounts.swap(1, 4);
    std::mem::swap(&mut case.account_key, &mut case.companion_program_key);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn alias_state_and_counter_keys_fail_closed() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    case.metas[1] = AccountMeta::new(case.state_key, false);
    case.accounts[1].0 = case.state_key;
    case.accounts[1].1 = case.accounts[0].1.clone();
    case.account_key = case.state_key;
    let pre = case.accounts.clone();
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
    assert_eq!(
        result.resulting_accounts, pre,
        "aliased failure must preserve every full account record in order"
    );
}

#[test]
fn companion_program_substitution_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    let wrong = fixed_key(0x75);
    case.metas[4] = AccountMeta::new_readonly(wrong, false);
    let wrong_account = create_program_account_loader_v3(&wrong);
    case.companion_program_key = wrong;
    case.accounts[4] = (wrong, wrong_account);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn post_cpi_caller_overflow_rolls_back_caller_and_companion() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    // Handler: value+=1; successful signed CPI; value += U64::MAX → overflow.
    // Both caller (+1) and companion (+5) must fully roll back.
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_PDA_INVOKE_SIGNED_THEN_OVERFLOW_HANDLER_ID,
            5,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
    );
}

#[test]
fn companion_checked_add_overflow_after_pda_preflight_rolls_back() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    // #120 invoke always emits companion tag 2 (checked-add + require PDA signer).
    // Counter + delta must overflow the #115 companion's checked-add so the
    // failure originates inside sol_invoke_signed_c, after full PDA preflight.
    let counter = u64::MAX - 4;
    let delta = 5u64;
    assert!(
        counter.checked_add(delta).is_none(),
        "fixture must force companion checked-add overflow (not preflight Custom(1))"
    );
    let case = SignedInvokeCase::new(program_id, companion_id, 10, counter, seed_tag, true);
    // Handler invokeSigned: value += 1 (pre-CPI store) → signed CPI → value += 2.
    // Companion returns exact Custom(0x1001) before writing the counter; caller
    // takes cpi_failed and exits without success sol_set_return_data.
    // Exact snapshot: pre-CPI caller write, companion mutation, and post-CPI
    // ops must all roll back; no success UInt64 return-data leakage.
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, delta),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::return_data(&[]),
        ],
    );
}

#[test]
fn authority_pda_wrong_owner_fails_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 42u64;
    let mut case = SignedInvokeCase::new(program_id, companion_id, 10, 7, seed_tag, true);
    // Mutate only authorityPda owner (key/bump/seedAuthority still canonical).
    // Caller siteChecks checkOwnerCurrentProgram fails closed before invoke.
    case.accounts
        .iter_mut()
        .find(|(key, _)| *key == case.authority_pda)
        .expect("authorityPda account present")
        .1
        .owner = fixed_key(0x76);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn init_and_inspect_without_cpi() {
    let (mollusk, program_id, _companion_id) = make_cpi_pda_mollusk();

    let init_key = fixed_key(0x30);
    let init_account = state_account(&program_id, companion_pda_state(false, 0));
    let init_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_pda_simple_ix_data(CPI_PDA_INIT_HANDLER_ID, &[41]),
        vec![AccountMeta::new(init_key, true)],
    );
    let result = mollusk.process_and_validate_instruction(
        &init_ix,
        &[(init_key, init_account)],
        &[Check::success()],
    );
    let post = &result.resulting_accounts[0].1;
    assert_eq!(post.data, companion_pda_state(true, 41));

    let view_key = fixed_key(0x31);
    let view_account = state_account(&program_id, companion_pda_state(true, 77));
    let view_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_pda_simple_ix_data(CPI_PDA_INSPECT_HANDLER_ID, &[]),
        vec![AccountMeta::new_readonly(view_key, false)],
    );
    mollusk.process_and_validate_instruction(
        &view_ix,
        &[(view_key, view_account)],
        &[Check::success(), Check::return_data(&77u64.to_le_bytes())],
    );
}

#[test]
fn success_return_data_is_caller_value_without_inner_leakage() {
    let (mollusk, program_id, companion_id) = make_cpi_pda_mollusk();
    let seed_tag = 7u64;
    let case = SignedInvokeCase::new(program_id, companion_id, 100, 0, seed_tag, true);
    // Final caller value = 100+1+2 = 103. Companion may write inner return data
    // during CPI; outer success path must publish only the caller UInt64.
    mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_PDA_INVOKE_SIGNED_HANDLER_ID, 9),
        &case.accounts,
        &[Check::success(), Check::return_data(&103u64.to_le_bytes())],
    );
}
