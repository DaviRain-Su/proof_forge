//! #118 production-code-generated multi-account preflight runtime closure.
//!
//! The loaded ELF is generated through the real preflight authority/emitter
//! chain, but remains explicitly test-preactivation: no CPI syscall and no
//! proof-forge.output.v1 artifact are reachable in this slice.

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

fn account_roles_fields() -> [StateField; 1] {
    single_field("value")
}

fn account_roles_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&account_roles_fields(), initialized, &[value])
}

fn executable_account(owner: Pubkey, data_len: usize) -> Account {
    let mut account = Account::new(BASE_LAMPORTS, data_len, &owner);
    account.executable = true;
    account
}

fn system_program_account() -> Account {
    executable_account(Pubkey::new_from_array(NATIVE_LOADER_ID_BYTES), 0)
}

#[derive(Clone)]
struct RouteCase {
    state_key: Pubkey,
    payer_key: Pubkey,
    companion_counter_key: Pubkey,
    recipient_key: Pubkey,
    system_program_key: Pubkey,
    companion_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl RouteCase {
    fn new(program_id: Pubkey) -> Self {
        let state_key = fixed_key(0x10);
        let payer_key = fixed_key(0x11);
        let companion_counter_key = fixed_key(0x12);
        let recipient_key = fixed_key(0x13);
        let system_program_key = Pubkey::default();
        let companion_program_key = harness_companion_id();

        let state = state_account(&program_id, account_roles_state(true, 41));
        let payer = Account::new(BASE_LAMPORTS, 0, &system_program_key);
        let companion_counter = companion_counter_account(&companion_program_key, 7);
        let recipient = Account::new(BASE_LAMPORTS, 0, &system_program_key);
        let system_program = system_program_account();
        let companion_program = create_program_account_loader_v3(&companion_program_key);

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(payer_key, true),
            AccountMeta::new(companion_counter_key, false),
            AccountMeta::new(recipient_key, false),
            AccountMeta::new_readonly(system_program_key, false),
            AccountMeta::new_readonly(companion_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (payer_key, payer),
            (companion_counter_key, companion_counter),
            (recipient_key, recipient),
            (system_program_key, system_program),
            (companion_program_key, companion_program),
        ];
        Self {
            state_key,
            payer_key,
            companion_counter_key,
            recipient_key,
            system_program_key,
            companion_program_key,
            metas,
            accounts,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_preflight_ix_data(handler_id),
            self.metas.clone(),
        )
    }

    fn account_mut(&mut self, key: Pubkey) -> &mut Account {
        &mut self
            .accounts
            .iter_mut()
            .find(|(candidate, _)| *candidate == key)
            .unwrap_or_else(|| panic!("missing RouteCase account {key}"))
            .1
    }
}

fn assert_custom1_hold(mollusk: &mollusk_svm::Mollusk, program_id: Pubkey, case: &RouteCase) {
    assert_failure_preserves_exact_accounts(
        mollusk,
        &case.instruction(program_id, CPI_PREFLIGHT_ROUTE_HANDLER_ID),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn committed_manifest_and_generated_bytes_are_exact_preactivation_evidence() {
    let manifest = committed_cpi_preflight_manifest_bytes();
    validate_cpi_preflight_manifest_bytes(&manifest).expect("committed preflight manifest");
    let assembly = read_cpi_preflight_assembly();
    let text = std::str::from_utf8(&assembly).expect("preflight assembly UTF-8");
    assert!(text.contains("TEST-PREACTIVATION ONLY"));
    assert!(text.contains("not a product artifact"));
    assert!(text.contains("handler_0_init_preflight:"));
    assert!(text.contains("handler_1_route_preflight:"));
    assert!(text.contains("handler_2_inspect_preflight:"));
    assert!(!text.contains("sol_invoke"));
    assert!(!text.contains("invoke_signed"));
    let elf = read_cpi_preflight_elf();
    assert!(elf.starts_with(b"\x7fELF"));
}

#[test]
fn preflight_manifest_closed_identity_mutations_fail() {
    let raw = committed_cpi_preflight_manifest_bytes();
    validate_cpi_preflight_manifest_bytes(&raw).expect("committed preflight manifest");
    let base: serde_json::Value = serde_json::from_slice(&raw).unwrap();
    let mutations = [
        ("/schema", json!("wrong")),
        ("/issue", json!(119)),
        ("/sbpf", json!("0.2.3")),
        ("/runtimeOracle/molluskSvm", json!("0.13.5")),
        ("/fixture/sourceSha256", json!("00")),
        ("/fixture/sourceSize", json!(620)),
        ("/profile/id", json!("solana-sbpf-elf-v1")),
        ("/profile/digest", json!("00")),
        ("/extension/version", json!("1.0.1")),
        ("/boundary/productArtifact", json!(true)),
        ("/boundary/testPreactivation", json!(false)),
        ("/boundary/activationDenied", json!(false)),
        ("/programIdHex", json!("00")),
        ("/handlers/route", json!(9)),
        ("/expectedAssembly/sha256", json!("00")),
        ("/expectedElf/size", json!(0)),
        ("/reproducibilityNote", json!("")),
    ];
    for (pointer, replacement) in mutations {
        let mut mutated = base.clone();
        *mutated
            .pointer_mut(pointer)
            .unwrap_or_else(|| panic!("missing mutation path {pointer}")) = replacement;
        assert!(
            validate_cpi_preflight_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err(),
            "manifest mutation unexpectedly accepted: {pointer}"
        );
    }
    let mut unknown = base;
    unknown
        .as_object_mut()
        .unwrap()
        .insert("unknown".to_string(), json!(true));
    assert!(validate_cpi_preflight_manifest_bytes(&serde_json::to_vec(&unknown).unwrap()).is_err());
}

#[test]
fn generated_init_route_and_view_preflight_succeed_without_mutation() {
    let (mollusk, program_id) = make_cpi_preflight_mollusk();

    let init_key = fixed_key(0x20);
    let init_account = state_account(&program_id, account_roles_state(false, 99));
    let init_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_preflight_ix_data(CPI_PREFLIGHT_INIT_HANDLER_ID),
        vec![AccountMeta::new(init_key, true)],
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &init_ix,
        &[(init_key, init_account)],
        &[Check::success()],
    );

    let route = RouteCase::new(program_id);
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &route.instruction(program_id, CPI_PREFLIGHT_ROUTE_HANDLER_ID),
        &route.accounts,
        &[Check::success()],
    );

    let view_key = fixed_key(0x21);
    let view_account = state_account(&program_id, account_roles_state(true, 77));
    let view_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_preflight_ix_data(CPI_PREFLIGHT_INSPECT_HANDLER_ID),
        vec![AccountMeta::new_readonly(view_key, false)],
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &view_ix,
        &[(view_key, view_account)],
        &[Check::success()],
    );
}

#[derive(Clone, Copy, Debug)]
enum RouteMutation {
    StateMarker,
    StateOwner,
    StateExecutable,
    StateReadonly,
    PayerMissingSigner,
    PayerReadonly,
    PayerOwner,
    PayerDataLen,
    CompanionCounterOwner,
    CompanionCounterDataLen,
    RecipientExecutable,
    SystemProgramKey,
    SystemProgramOwner,
    SystemProgramExecutable,
    CompanionProgramKey,
    CompanionProgramOwner,
    CompanionProgramExecutable,
    RolePermutation,
    DuplicateRoleKey,
    ExtraRole,
    MissingRole,
    UnexpectedAuthoritySigner,
}

fn mutate_route(mut case: RouteCase, mutation: RouteMutation) -> RouteCase {
    match mutation {
        RouteMutation::StateMarker => case.account_mut(case.state_key).data[0] ^= 1,
        RouteMutation::StateOwner => case.account_mut(case.state_key).owner = fixed_key(0x70),
        RouteMutation::StateExecutable => case.account_mut(case.state_key).executable = true,
        RouteMutation::StateReadonly => {
            case.metas[0] = AccountMeta::new_readonly(case.state_key, false)
        }
        RouteMutation::PayerMissingSigner => {
            case.metas[1] = AccountMeta::new(case.payer_key, false)
        }
        RouteMutation::PayerReadonly => {
            case.metas[1] = AccountMeta::new_readonly(case.payer_key, true)
        }
        RouteMutation::PayerOwner => case.account_mut(case.payer_key).owner = fixed_key(0x71),
        RouteMutation::PayerDataLen => case.account_mut(case.payer_key).data.push(0),
        RouteMutation::CompanionCounterOwner => {
            case.account_mut(case.companion_counter_key).owner = fixed_key(0x72)
        }
        RouteMutation::CompanionCounterDataLen => {
            case.account_mut(case.companion_counter_key).data.pop();
        }
        RouteMutation::RecipientExecutable => {
            case.account_mut(case.recipient_key).executable = true
        }
        RouteMutation::SystemProgramKey => {
            let wrong = fixed_key(0x73);
            case.metas[4] = AccountMeta::new_readonly(wrong, false);
            let (_, account) = &mut case.accounts[4];
            case.system_program_key = wrong;
            case.accounts[4] = (wrong, account.clone());
        }
        RouteMutation::SystemProgramOwner => {
            case.account_mut(case.system_program_key).owner = fixed_key(0x74)
        }
        RouteMutation::SystemProgramExecutable => {
            case.account_mut(case.system_program_key).executable = false
        }
        RouteMutation::CompanionProgramKey => {
            let wrong = fixed_key(0x75);
            case.metas[5] = AccountMeta::new_readonly(wrong, false);
            let wrong_account = create_program_account_loader_v3(&wrong);
            case.companion_program_key = wrong;
            case.accounts[5] = (wrong, wrong_account);
        }
        RouteMutation::CompanionProgramOwner => {
            case.account_mut(case.companion_program_key).owner = fixed_key(0x76)
        }
        RouteMutation::CompanionProgramExecutable => {
            case.account_mut(case.companion_program_key).executable = false
        }
        RouteMutation::RolePermutation => case.metas.swap(2, 3),
        RouteMutation::DuplicateRoleKey => {
            case.metas[3] = AccountMeta::new(case.payer_key, false);
            case.accounts.remove(3);
        }
        RouteMutation::ExtraRole => {
            let key = fixed_key(0x77);
            case.metas.push(AccountMeta::new_readonly(key, false));
            case.accounts
                .push((key, Account::new(BASE_LAMPORTS, 3, &fixed_key(0x78))));
        }
        RouteMutation::MissingRole => {
            case.metas.pop();
            case.accounts.pop();
        }
        RouteMutation::UnexpectedAuthoritySigner => {
            case.metas[2] = AccountMeta::new(case.companion_counter_key, true)
        }
    }
    case
}

#[test]
fn route_one_mutation_matrix_fails_before_business_ops_and_holds_full_snapshot() {
    let (mollusk, program_id) = make_cpi_preflight_mollusk();
    let mutations = [
        RouteMutation::StateMarker,
        RouteMutation::StateOwner,
        RouteMutation::StateExecutable,
        RouteMutation::StateReadonly,
        RouteMutation::PayerMissingSigner,
        RouteMutation::PayerReadonly,
        RouteMutation::PayerOwner,
        RouteMutation::PayerDataLen,
        RouteMutation::CompanionCounterOwner,
        RouteMutation::CompanionCounterDataLen,
        RouteMutation::RecipientExecutable,
        RouteMutation::SystemProgramKey,
        RouteMutation::SystemProgramOwner,
        RouteMutation::SystemProgramExecutable,
        RouteMutation::CompanionProgramKey,
        RouteMutation::CompanionProgramOwner,
        RouteMutation::CompanionProgramExecutable,
        RouteMutation::RolePermutation,
        RouteMutation::DuplicateRoleKey,
        RouteMutation::ExtraRole,
        RouteMutation::MissingRole,
        RouteMutation::UnexpectedAuthoritySigner,
    ];
    for mutation in mutations {
        let case = mutate_route(RouteCase::new(program_id), mutation);
        assert_custom1_hold(&mollusk, program_id, &case);
    }
}

#[test]
fn route_position_matrix_rejects_every_adjacent_swap_and_edge_insertion_removal() {
    let (mollusk, program_id) = make_cpi_preflight_mollusk();
    let role_count = RouteCase::new(program_id).metas.len();
    assert_eq!(role_count, 6, "frozen route role count");

    // Every adjacent permutation supplies valid accounts under the wrong Plan
    // positions. Exact role checks must reject each one before mutation.
    for left in 0..role_count - 1 {
        let mut case = RouteCase::new(program_id);
        case.metas.swap(left, left + 1);
        assert_custom1_hold(&mollusk, program_id, &case);
    }

    // Remove one role at the leading, middle, and trailing positions.
    for index in [0usize, role_count / 2, role_count - 1] {
        let mut case = RouteCase::new(program_id);
        case.metas.remove(index);
        case.accounts.remove(index);
        assert_custom1_hold(&mollusk, program_id, &case);
    }

    // Insert one otherwise valid account at the leading, middle, and trailing
    // positions. The exact count gate must reject all three shapes.
    for index in [0usize, role_count / 2, role_count] {
        let mut case = RouteCase::new(program_id);
        let key = fixed_key(0x90 + index as u8);
        let account = Account::new(BASE_LAMPORTS, 0, &fixed_key(0x99));
        case.metas
            .insert(index, AccountMeta::new_readonly(key, false));
        case.accounts.insert(index, (key, account));
        assert_custom1_hold(&mollusk, program_id, &case);
    }
}

#[test]
fn probe_instruction_shape_and_unknown_handler_fail_closed_with_snapshot_hold() {
    let (mollusk, program_id) = make_cpi_preflight_mollusk();
    let case = RouteCase::new(program_id);
    let base = cpi_preflight_ix_data(CPI_PREFLIGHT_ROUTE_HANDLER_ID);
    let malformed = [
        base[..7].to_vec(),
        [base.as_slice(), &[0]].concat(),
        99u64.to_le_bytes().to_vec(),
    ];
    for data in malformed {
        let ix = Instruction::new_with_bytes(program_id, &data, case.metas.clone());
        assert_failure_preserves_exact_accounts(
            &mollusk,
            &ix,
            &case.accounts,
            Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
        );
    }
}

#[test]
fn generated_walker_exercises_zero_sixteen_and_rejects_seventeen_roles() {
    let (mollusk, program_id) = make_cpi_preflight_mollusk();
    for count in [0usize, 16, 17] {
        let mut metas = Vec::with_capacity(count);
        let mut accounts = Vec::with_capacity(count);
        for index in 0..count {
            let key = fixed_key(0x80 + index as u8);
            // Non-multiple-of-eight lengths exercise the generated alignment
            // path before unknown-handler dispatch when count == 16.
            let account = Account::new(BASE_LAMPORTS, index % 8, &fixed_key(0xa0));
            metas.push(AccountMeta::new_readonly(key, false));
            accounts.push((key, account));
        }
        let ix = Instruction::new_with_bytes(program_id, &cpi_preflight_ix_data(99), metas);
        assert_failure_preserves_exact_accounts(
            &mollusk,
            &ix,
            &accounts,
            Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
        );
    }
}
