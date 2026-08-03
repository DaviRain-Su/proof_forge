//! #119 production-code-generated unsigned companion CPI runtime closure.
//!
//! The loaded ELF is generated through the real Semantic→preflight→unsigned
//! IR→emitter chain. It remains explicitly test-preactivation: dual-program
//! with the #115 companion, real `sol_invoke_signed_c`, no
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

const NATIVE_LOADER_ID_BYTES: [u8; 32] = [
    0x05, 0x87, 0x84, 0xbf, 0x14, 0x8b, 0xa4, 0x28, 0x2f, 0xb0, 0x12, 0x57, 0x48, 0x88, 0xa9, 0xf1,
    0x53, 0xa0, 0x7d, 0xad, 0xf7, 0x65, 0xc0, 0x45, 0x5c, 0x9a, 0x97, 0x03, 0x80, 0x00, 0x00, 0x00,
];

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn companion_cpi_fields() -> [StateField; 1] {
    single_field("value")
}

fn companion_cpi_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&companion_cpi_fields(), initialized, &[value])
}

fn executable_account(owner: Pubkey, data_len: usize) -> Account {
    let mut account = Account::new(BASE_LAMPORTS, data_len, &owner);
    account.executable = true;
    account
}

#[derive(Clone)]
struct InvokeCase {
    state_key: Pubkey,
    account_key: Pubkey,
    companion_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl InvokeCase {
    fn new(program_id: Pubkey, companion_id: Pubkey, state_value: u64, counter: u64) -> Self {
        let state_key = fixed_key(0x20);
        let account_key = fixed_key(0x21);
        let companion_program_key = companion_id;

        let state = state_account(&program_id, companion_cpi_state(true, state_value));
        let companion_counter = companion_counter_account(&companion_id, counter);
        let companion_program = create_program_account_loader_v3(&companion_program_key);

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(account_key, false),
            AccountMeta::new_readonly(companion_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (account_key, companion_counter),
            (companion_program_key, companion_program),
        ];
        Self {
            state_key,
            account_key,
            companion_program_key,
            metas,
            accounts,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, delta: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_unsigned_ix_data(handler_id, &[delta]),
            self.metas.clone(),
        )
    }

    fn account_mut(&mut self, key: Pubkey) -> &mut Account {
        &mut self
            .accounts
            .iter_mut()
            .find(|(candidate, _)| *candidate == key)
            .unwrap_or_else(|| panic!("missing InvokeCase account {key}"))
            .1
    }
}

#[test]
fn committed_manifest_and_generated_bytes_are_exact_preactivation_evidence() {
    let manifest = committed_cpi_unsigned_manifest_bytes();
    validate_cpi_unsigned_manifest_bytes(&manifest).expect("committed unsigned manifest");
    let assembly = read_cpi_unsigned_assembly();
    let text = std::str::from_utf8(&assembly).expect("unsigned assembly UTF-8");
    assert!(text.contains("TEST-PREACTIVATION ONLY"));
    assert!(text.contains("not a product artifact"));
    assert!(text.contains("handler_0_init_unsigned:"));
    assert!(text.contains("handler_1_invokeOnce_unsigned:"));
    assert!(text.contains("handler_2_failOnce_unsigned:"));
    assert!(text.contains("handler_3_inspect_unsigned:"));
    assert!(text.contains("call sol_invoke_signed_c"));
    assert!(text.contains("call sol_set_return_data"));
    assert!(!text.contains("0xec01"));
    assert!(!text.contains("ACC0_"));
    // Failure path: cpi_failed is immediate exit (static proof no later store/call).
    let after_fail = text
        .split_once("cpi_failed:")
        .map(|(_, rest)| rest)
        .expect("cpi_failed label");
    let head: String = after_fail.lines().take(4).collect::<Vec<_>>().join("\n");
    assert!(head.contains("exit"), "cpi_failed must exit");
    assert!(!head.contains("stxdw"), "no store after cpi_failed");
    assert!(
        !head.contains("call sol_invoke"),
        "no invoke after cpi_failed"
    );
    let elf = read_cpi_unsigned_elf();
    assert!(elf.starts_with(b"\x7fELF"));
}

#[test]
fn unsigned_manifest_closed_identity_mutations_fail() {
    let raw = committed_cpi_unsigned_manifest_bytes();
    validate_cpi_unsigned_manifest_bytes(&raw).expect("committed unsigned manifest");
    let base: serde_json::Value = serde_json::from_slice(&raw).unwrap();
    let mutations = [
        ("/schema", json!("wrong")),
        ("/issue", json!(118)),
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
        ("/handlers/invokeOnce", json!(9)),
        ("/expectedAssembly/sha256", json!("00")),
        ("/expectedElf/size", json!(0)),
        ("/reproducibilityNote", json!("")),
    ];
    for (pointer, replacement) in mutations {
        let mut mutated = base.clone();
        *mutated
            .pointer_mut(pointer)
            .unwrap_or_else(|| panic!("missing mutation path {pointer}")) = replacement;
        let encoded = serde_json::to_vec(&mutated).unwrap();
        let result = validate_cpi_unsigned_manifest_bytes(&encoded);
        assert!(
            result.is_err(),
            "manifest mutation unexpectedly accepted: {pointer} ({result:?})"
        );
    }
}

#[test]
fn invoke_success_updates_companion_once_and_commits_caller_pre_post_writes() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let case = InvokeCase::new(program_id, companion_id, 10, 7);
    let ix = case.instruction(program_id, CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, 5);
    // Pre: caller state 10; post success: value = 10+1+2 = 13; companion 7+5 = 12.
    // return data = final value 13.
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
        companion_cpi_state(true, 13),
        "caller state must commit pre-CPI (+1) and post-CPI (+2) writes"
    );
    assert_eq!(
        post_counter.data,
        12u64.to_le_bytes().to_vec(),
        "companion counter must be mutated exactly once"
    );

    // Full success snapshot: only the two expected data payloads may change;
    // lamports/owner/executable/rent_epoch and the program account stay exact.
    let mut expected_accounts = case.accounts.clone();
    expected_accounts
        .iter_mut()
        .find(|(key, _)| *key == case.state_key)
        .expect("expected state")
        .1
        .data = companion_cpi_state(true, 13);
    expected_accounts
        .iter_mut()
        .find(|(key, _)| *key == case.account_key)
        .expect("expected counter")
        .1
        .data = 12u64.to_le_bytes().to_vec();
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
fn high_byte_uint64_delta_reaches_companion_exactly() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let case = InvokeCase::new(program_id, companion_id, 10, 7);
    // Bit 63 set: proves all 8 LE limbs of the delta survive outer encode,
    // account-info walk, and the real companion checked_add path.
    let delta = 0x8000_0000_0000_0005u64;
    let expected_counter = 7u64.wrapping_add(delta);
    assert_ne!(
        expected_counter.to_le_bytes()[7],
        0,
        "high-byte coverage requires a non-zero MSB after companion add"
    );
    let ix = case.instruction(program_id, CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, delta);
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

    // Full success snapshot still holds: only counter data carries the high
    // byte; caller-state (+1/+2) and companion program metadata stay exact.
    let mut expected_accounts = case.accounts.clone();
    expected_accounts
        .iter_mut()
        .find(|(key, _)| *key == case.state_key)
        .expect("expected state")
        .1
        .data = companion_cpi_state(true, 13);
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
        snapshot_exact_accounts(&expected_keys, &actual_observed)
            .expect("actual high-byte success snapshot"),
        snapshot_exact_accounts(&expected_keys, &expected_observed)
            .expect("expected high-byte success snapshot"),
        "high-byte success may change only caller-state and companion-counter data"
    );
}

#[test]
fn fail_once_rolls_back_caller_and_companion_and_keeps_fail_return_data() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let case = InvokeCase::new(program_id, companion_id, 10, 7);
    let ix = case.instruction(program_id, CPI_UNSIGNED_FAIL_ONCE_HANDLER_ID, 5);
    // Companion writes then returns Custom(1) with fail:v1! return data.
    // Top-level must roll back both caller (+1 pre-write) and companion (+5).
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
fn init_and_inspect_without_cpi() {
    let (mollusk, program_id, _companion_id) = make_cpi_unsigned_mollusk();

    let init_key = fixed_key(0x30);
    let init_account = state_account(&program_id, companion_cpi_state(false, 0));
    let init_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_unsigned_ix_data(CPI_UNSIGNED_INIT_HANDLER_ID, &[41]),
        vec![AccountMeta::new(init_key, true)],
    );
    let result = mollusk.process_and_validate_instruction(
        &init_ix,
        &[(init_key, init_account)],
        &[Check::success()],
    );
    let post = &result.resulting_accounts[0].1;
    assert_eq!(post.data, companion_cpi_state(true, 41));

    let view_key = fixed_key(0x31);
    let view_account = state_account(&program_id, companion_cpi_state(true, 77));
    let view_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_unsigned_ix_data(CPI_UNSIGNED_INSPECT_HANDLER_ID, &[]),
        vec![AccountMeta::new_readonly(view_key, false)],
    );
    mollusk.process_and_validate_instruction(
        &view_ix,
        &[(view_key, view_account)],
        &[Check::success(), Check::return_data(&77u64.to_le_bytes())],
    );
}

#[derive(Clone, Copy, Debug)]
enum InvokeMutation {
    MissingWritable,
    UnexpectedSigner,
    CompanionProgramSubstitution,
    AccountPermutation,
    AliasStateAndCounter,
    HighByteProgramKeyDelta,
    CompanionCounterWrongOwner,
}

fn mutate_invoke(mut case: InvokeCase, mutation: InvokeMutation) -> InvokeCase {
    match mutation {
        InvokeMutation::MissingWritable => {
            case.metas[1] = AccountMeta::new_readonly(case.account_key, false);
        }
        InvokeMutation::UnexpectedSigner => {
            case.metas[1] = AccountMeta::new(case.account_key, true);
        }
        InvokeMutation::CompanionProgramSubstitution => {
            let wrong = fixed_key(0x75);
            case.metas[2] = AccountMeta::new_readonly(wrong, false);
            let wrong_account = create_program_account_loader_v3(&wrong);
            case.companion_program_key = wrong;
            case.accounts[2] = (wrong, wrong_account);
        }
        InvokeMutation::AccountPermutation => {
            // Swap counter and companion program positions.
            case.metas.swap(1, 2);
            case.accounts.swap(1, 2);
            std::mem::swap(&mut case.account_key, &mut case.companion_program_key);
        }
        InvokeMutation::AliasStateAndCounter => {
            // Force duplicate keys between state and counter roles.
            case.metas[1] = AccountMeta::new(case.state_key, false);
            case.accounts[1].0 = case.state_key;
            case.accounts[1].1 = case.accounts[0].1.clone();
            case.account_key = case.state_key;
        }
        InvokeMutation::HighByteProgramKeyDelta => {
            // Corrupt only the high byte of the frozen companion program id so a
            // partial 24-byte compare cannot accept a near-miss key.
            let mut bytes = case.companion_program_key.to_bytes();
            bytes[31] ^= 0x80;
            let wrong = Pubkey::new_from_array(bytes);
            case.metas[2] = AccountMeta::new_readonly(wrong, false);
            let wrong_account = create_program_account_loader_v3(&wrong);
            case.companion_program_key = wrong;
            case.accounts[2] = (wrong, wrong_account);
        }
        InvokeMutation::CompanionCounterWrongOwner => {
            case.account_mut(case.account_key).owner = fixed_key(0x76);
        }
    }
    case
}

#[test]
fn one_mutation_negatives_fail_closed_with_full_snapshot() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let base = InvokeCase::new(program_id, companion_id, 10, 7);
    for mutation in [
        InvokeMutation::MissingWritable,
        InvokeMutation::UnexpectedSigner,
        InvokeMutation::CompanionProgramSubstitution,
        InvokeMutation::AccountPermutation,
        InvokeMutation::HighByteProgramKeyDelta,
        InvokeMutation::CompanionCounterWrongOwner,
    ] {
        let case = mutate_invoke(base.clone(), mutation);
        assert_failure_preserves_exact_accounts(
            &mollusk,
            &case.instruction(program_id, CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, 5),
            &case.accounts,
            Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
        );
    }
}

#[test]
fn alias_state_and_counter_keys_fail_closed() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let case = mutate_invoke(
        InvokeCase::new(program_id, companion_id, 10, 7),
        InvokeMutation::AliasStateAndCounter,
    );
    // Alias produces duplicate outer keys; the map-based helper deliberately
    // rejects duplicate keys, so compare the ordered full account vector.
    let pre = case.accounts.clone();
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, 5),
        &case.accounts,
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
    assert_eq!(
        result.resulting_accounts, pre,
        "aliased failure must preserve every full account record in order"
    );
}

#[test]
fn false_required_privilege_on_state_fails() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let mut case = InvokeCase::new(program_id, companion_id, 10, 7);
    // entry requires state writable; make it readonly.
    case.metas[0] = AccountMeta::new_readonly(case.state_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn wrong_role_count_fails() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let case = InvokeCase::new(program_id, companion_id, 10, 7);
    // Drop companion program role.
    let metas = case.metas[..2].to_vec();
    let accounts = case.accounts[..2].to_vec();
    let ix = Instruction::new_with_bytes(
        program_id,
        &cpi_unsigned_ix_data(CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, &[5]),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn companion_program_must_be_executable() {
    let (mollusk, program_id, companion_id) = make_cpi_unsigned_mollusk();
    let mut case = InvokeCase::new(program_id, companion_id, 10, 7);
    case.account_mut(case.companion_program_key).executable = false;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID, 5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn _native_loader_bytes_are_known() {
    // Keep the constant live for future System path tests without product use.
    assert_eq!(NATIVE_LOADER_ID_BYTES[0], 0x05);
    let _ = executable_account(Pubkey::new_from_array(NATIVE_LOADER_ID_BYTES), 0);
}
