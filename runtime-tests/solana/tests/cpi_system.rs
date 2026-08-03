//! #121 production-code-generated native System CPI runtime closure.
//!
//! The loaded ELF is generated through the real Semantic→preflight→System
//! IR→emitter chain (resolveSolanaCpiSystemIRV1 + emitCpiSystemSbpfV1). It
//! remains explicitly test-preactivation: real native System Program via
//! `Mollusk::default()` + `keyed_account_for_system_program()`, real
//! `sol_invoke_signed_c` (transfer unsigned / createPda signed), no
//! proof-forge.output.v1 artifact, and no product sync capability.
//!
//! Assembly/ELF bytes are exact-manifest-bound and mandatory for runtime
//! cases; no placeholder, fallback, or soft-skip path remains.

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

fn system_cpi_fields() -> [StateField; 1] {
    single_field("value")
}

fn system_cpi_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&system_cpi_fields(), initialized, &[value])
}

/// Outer roles for transfer / transferThenOverflow:
///   0 state (writable)
///   1 payer (writable, outer signer)
///   2 recipient (writable)
///   3 system program (readonly executable, native)
#[derive(Clone)]
struct TransferCase {
    state_key: Pubkey,
    payer_key: Pubkey,
    recipient_key: Pubkey,
    system_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    payer_lamports: u64,
    recipient_lamports: u64,
}

impl TransferCase {
    fn new(
        program_id: Pubkey,
        state_value: u64,
        payer_lamports: u64,
        recipient_lamports: u64,
    ) -> Self {
        let state_key = fixed_key(0x20);
        let payer_key = fixed_key(0x21);
        let recipient_key = fixed_key(0x22);
        let (system_program_key, system_program) = system_program_keyed_account();
        assert_eq!(system_program_key, Pubkey::default());

        let state = state_account(&program_id, system_cpi_state(true, state_value));
        let payer = Account::new(payer_lamports, 0, &Pubkey::default());
        let recipient = Account::new(recipient_lamports, 0, &Pubkey::default());

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(payer_key, true),
            AccountMeta::new(recipient_key, false),
            AccountMeta::new_readonly(system_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (payer_key, payer),
            (recipient_key, recipient),
            (system_program_key, system_program),
        ];
        Self {
            state_key,
            payer_key,
            recipient_key,
            system_program_key,
            metas,
            accounts,
            payer_lamports,
            recipient_lamports,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, lamports: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_system_transfer_ix_data(handler_id, lamports),
            self.metas.clone(),
        )
    }
}

/// Outer roles for createPdaAccount:
///   0 state (writable)
///   1 payer (writable, outer signer)
///   2 pda (writable, not outer signer; CPI signer via PDA seeds)
///   3 seedAuthority (readonly, not outer signer)
///   4 system program (readonly executable, native)
#[derive(Clone)]
struct CreateCase {
    state_key: Pubkey,
    payer_key: Pubkey,
    pda_key: Pubkey,
    seed_authority: Pubkey,
    seed_tag: u64,
    bump: u8,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    payer_lamports: u64,
}

impl CreateCase {
    fn new(
        program_id: Pubkey,
        state_value: u64,
        seed_tag: u64,
        payer_lamports: u64,
        seed_authority_signer: bool,
    ) -> Self {
        let state_key = fixed_key(0x30);
        let payer_key = fixed_key(0x31);
        let seed_authority = fixed_key(0x32);
        let (pda_key, bump) =
            find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
        let (system_program_key, system_program) = system_program_keyed_account();

        let state = state_account(&program_id, system_cpi_state(true, state_value));
        let payer = Account::new(payer_lamports, 0, &Pubkey::default());
        // Create target must be an explicit unused System-owned account.
        let pda_account = unused_system_create_target_account();
        let authority_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(payer_key, true),
            AccountMeta::new(pda_key, false),
            AccountMeta::new_readonly(seed_authority, seed_authority_signer),
            AccountMeta::new_readonly(system_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (payer_key, payer),
            (pda_key, pda_account),
            (seed_authority, authority_account),
            (system_program_key, system_program),
        ];
        Self {
            state_key,
            payer_key,
            pda_key,
            seed_authority,
            seed_tag,
            bump,
            metas,
            accounts,
            payer_lamports,
        }
    }

    fn instruction(
        &self,
        program_id: Pubkey,
        handler_id: u64,
        seed_tag: u64,
        bump: u8,
        lamports: u64,
        space: u64,
    ) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_system_create_ix_data(handler_id, seed_tag, bump, lamports, space),
            self.metas.clone(),
        )
    }

    fn instruction_canonical(
        &self,
        program_id: Pubkey,
        handler_id: u64,
        lamports: u64,
        space: u64,
    ) -> Instruction {
        self.instruction(
            program_id,
            handler_id,
            self.seed_tag,
            self.bump,
            lamports,
            space,
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

// ---------------------------------------------------------------------------
// Pure / committed-manifest tests (no generated ELF required)
// ---------------------------------------------------------------------------

#[test]
fn committed_manifest_schema_is_exact_preactivation_evidence() {
    let manifest = committed_cpi_system_manifest_bytes();
    validate_cpi_system_manifest_bytes(&manifest).expect("committed system manifest");
    let value: serde_json::Value = serde_json::from_slice(&manifest).unwrap();
    assert_eq!(
        value["schema"],
        json!("proof-forge.solana.cpi-system-runtime.v1")
    );
    assert_eq!(value["issue"], json!(121));
    assert_eq!(value["boundary"]["productArtifact"], json!(false));
    assert_eq!(value["boundary"]["testPreactivation"], json!(true));
    assert_eq!(value["boundary"]["activationDenied"], json!(true));
    assert_eq!(value["system"]["package"], json!("system-v1"));
    assert_eq!(
        value["system"]["programIdHex"],
        json!("0000000000000000000000000000000000000000000000000000000000000000")
    );
    assert_eq!(value["system"]["executionClass"], json!("nativeSystem"));
    assert_eq!(value["system"]["artifactBinding"], json!("runtime-native"));
    assert_eq!(
        value["system"]["agaveCommit"],
        json!("2a165e7a90af75c76426d1e031ed0284211d5d1e")
    );
    assert_eq!(
        value["system"]["instructionSurface"]["transferDataBytes"],
        json!(12)
    );
    assert_eq!(
        value["system"]["instructionSurface"]["createAccountDataBytes"],
        json!(52)
    );
    assert_eq!(
        value["system"]["instructionSurface"]["createOwner"],
        json!("current-program-id")
    );
    assert_eq!(
        value["system"]["instructionSurface"]["maxSpace"],
        json!(4096)
    );
    assert_eq!(value["pda"]["canonicalBumpSearch"], json!("255..1"));
    assert_eq!(value["pda"]["bump0Rejected"], json!(true));
    assert_eq!(value["handlers"]["createThenOverflow"], json!(4));
    assert_eq!(value["handlers"]["inspect"], json!(5));
    assert_eq!(
        value["fixture"]["sourceSha256"],
        json!("02efaf633a51aa6aa702e88d0eec48a894a3138f6dae90a030181022db7d4bd0")
    );
    assert_eq!(value["fixture"]["sourceSize"], json!(2262));
    assert_eq!(value["expectedAssembly"]["size"], json!(101762));
    assert_eq!(
        value["expectedAssembly"]["sha256"],
        json!("eac15e4f65edf2af6c179c396185881ad1c72cd471e1a6ee1def31745e29aa89")
    );
    assert_eq!(value["expectedElf"]["size"], json!(41576));
    assert_eq!(
        value["expectedElf"]["sha256"],
        json!("e92259e5065ba4b181b8822afbce7c2194724e463a856d506c341271b5ca314e")
    );
}

#[test]
fn system_manifest_closed_identity_mutations_fail() {
    let raw = committed_cpi_system_manifest_bytes();
    validate_cpi_system_manifest_bytes(&raw).expect("committed system manifest");
    let base: serde_json::Value = serde_json::from_slice(&raw).unwrap();
    let mutations = [
        ("/schema", json!("wrong")),
        ("/issue", json!(120)),
        ("/sbpf", json!("0.2.3")),
        ("/runtimeOracle/molluskSvm", json!("0.13.5")),
        ("/fixture/sourceSha256", json!("00")),
        ("/profile/id", json!("solana-sbpf-elf-v1")),
        ("/extension/version", json!("1.0.1")),
        ("/boundary/productArtifact", json!(true)),
        ("/boundary/activationDenied", json!(false)),
        ("/programIdHex", json!("00")),
        ("/system/package", json!("wrong")),
        ("/system/programIdHex", json!("11".repeat(32))),
        ("/system/executionClass", json!("loaderV3Sbpf")),
        ("/system/artifactBinding", json!("generated-elf")),
        ("/system/agaveCommit", json!("deadbeef")),
        ("/system/instructionSurface/transferDataBytes", json!(11)),
        (
            "/system/instructionSurface/createAccountDataBytes",
            json!(51),
        ),
        ("/system/instructionSurface/maxSpace", json!(4097)),
        ("/handlers/transfer", json!(9)),
        ("/handlers/createPdaAccount", json!(9)),
        ("/handlers/createThenOverflow", json!(9)),
        ("/handlers/inspect", json!(9)),
        ("/pda/recipe", json!("wrong")),
        ("/pda/canonicalBumpSearch", json!("255..0")),
        ("/pda/bump0Rejected", json!(false)),
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
        let result = validate_cpi_system_manifest_bytes(&encoded);
        assert!(
            result.is_err(),
            "manifest mutation unexpectedly accepted: {pointer} ({result:?})"
        );
    }
}

#[test]
fn transfer_ix_layout_is_exactly_16_bytes() {
    let data = cpi_system_transfer_ix_data(CPI_SYSTEM_TRANSFER_HANDLER_ID, 42);
    assert_eq!(data.len(), CPI_SYSTEM_TRANSFER_IX_LEN);
    assert_eq!(&data[0..8], &CPI_SYSTEM_TRANSFER_HANDLER_ID.to_le_bytes());
    assert_eq!(&data[8..16], &42u64.to_le_bytes());
}

#[test]
fn create_ix_layout_is_exactly_33_bytes() {
    let data = cpi_system_create_ix_data(CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 7, 252, 1000, 64);
    assert_eq!(data.len(), CPI_SYSTEM_CREATE_IX_LEN);
    assert_eq!(&data[0..8], &CPI_SYSTEM_CREATE_PDA_HANDLER_ID.to_le_bytes());
    assert_eq!(&data[8..16], &7u64.to_le_bytes());
    assert_eq!(data[16], 252);
    assert_eq!(&data[17..25], &1000u64.to_le_bytes());
    assert_eq!(&data[25..33], &64u64.to_le_bytes());
}

#[test]
fn high_byte_lamports_and_space_layout_coverage() {
    let lamports = 0x8000_0000_0000_0005u64;
    let space = 0x8000_0000_0000_0040u64;
    let transfer = cpi_system_transfer_ix_data(CPI_SYSTEM_TRANSFER_HANDLER_ID, lamports);
    assert_ne!(transfer[15], 0, "transfer lamports high-byte coverage");
    let create = cpi_system_create_ix_data(
        CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
        0x8000_0000_0000_002Au64,
        1,
        lamports,
        space,
    );
    assert_ne!(create[15], 0, "seedTag high-byte coverage");
    assert_ne!(create[24], 0, "create lamports high-byte coverage");
    assert_ne!(create[32], 0, "space high-byte coverage");
}

#[test]
fn keyed_system_program_helper_is_native_zero_id() {
    let (key, account) = system_program_keyed_account();
    assert_eq!(key, Pubkey::default());
    assert!(account.executable);
    assert_eq!(
        account.owner,
        Pubkey::new_from_array([
            0x05, 0x87, 0x84, 0xbf, 0x14, 0x8b, 0xa4, 0x28, 0x2f, 0xb0, 0x12, 0x57, 0x48, 0x88,
            0xa9, 0xf1, 0x53, 0xa0, 0x7d, 0xad, 0xf7, 0x65, 0xc0, 0x45, 0x5c, 0x9a, 0x97, 0x03,
            0x80, 0x00, 0x00, 0x00,
        ])
    );
    let unused = unused_system_create_target_account();
    assert_eq!(unused.lamports, 0);
    assert!(unused.data.is_empty());
    assert!(!unused.executable);
    assert_eq!(unused.owner, Pubkey::default());
}

// ---------------------------------------------------------------------------
// Generated artifact + Mollusk matrix (requires Lean System export + pins)
// ---------------------------------------------------------------------------

#[test]
fn generated_assembly_and_elf_are_exact_preactivation() {
    let assembly = read_cpi_system_assembly();
    let text = std::str::from_utf8(&assembly).expect("system assembly UTF-8");
    assert!(text.contains("TEST-PREACTIVATION ONLY"));
    assert!(text.contains("not a product artifact"));
    assert!(text.contains("call sol_invoke_signed_c"));
    assert!(text.contains("call sol_try_find_program_address"));
    assert!(text.contains("call sol_set_return_data"));
    assert!(!text.contains("0xec01"));
    assert!(!text.contains("ACC0_"));
    let elf = read_cpi_system_elf();
    assert!(elf.starts_with(b"\x7fELF"));
}

#[test]
fn transfer_success_exact_lamport_delta_and_state_order() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let transfer_amount = 42_000u64;
    let case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    // High-byte coverage on a second path is separate; here assert exact delta.
    let ix = case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, transfer_amount);
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
        .expect("state");
    let post_payer = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.payer_key)
        .map(|(_, a)| a)
        .expect("payer");
    let post_recipient = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.recipient_key)
        .map(|(_, a)| a)
        .expect("recipient");
    assert_eq!(
        post_state.data,
        system_cpi_state(true, 13),
        "caller state must commit pre-CPI (+1) and post-CPI (+2)"
    );
    assert_eq!(
        post_payer.lamports,
        case.payer_lamports - transfer_amount,
        "exact payer lamport debit"
    );
    assert_eq!(
        post_recipient.lamports,
        case.recipient_lamports + transfer_amount,
        "exact recipient lamport credit"
    );
    // Full 8-byte LE delta (no high-byte truncation): amount fits low bytes here.
    assert_eq!(&transfer_amount.to_le_bytes()[4..], &[0, 0, 0, 0]);
}

#[test]
fn transfer_high_byte_lamports_reach_system() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    // Need payer balance > amount with MSB set in LE encoding of amount.
    let transfer_amount = 0x0000_0001_0000_0000u64; // 2^32, byte[4] non-zero
    let payer_balance = transfer_amount + BASE_LAMPORTS;
    let case = TransferCase::new(program_id, 10, payer_balance, BASE_LAMPORTS);
    assert_ne!(transfer_amount.to_le_bytes()[4], 0);
    let ix = case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, transfer_amount);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let post_payer = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.payer_key)
        .map(|(_, a)| a)
        .expect("payer");
    let post_recipient = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.recipient_key)
        .map(|(_, a)| a)
        .expect("recipient");
    assert_eq!(post_payer.lamports, payer_balance - transfer_amount);
    assert_eq!(
        post_recipient.lamports,
        BASE_LAMPORTS + transfer_amount,
        "all eight little-endian lamports bytes must reach System transfer"
    );
}

#[test]
fn create_success_canonical_key_bump_owner_data_and_lamports() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let space = 64u64;
    let create_lamports = 5_000_000u64;
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    assert_ne!(case.bump, 0);
    let ix = case.instruction_canonical(
        program_id,
        CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
        create_lamports,
        space,
    );
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
        .expect("state");
    let post_payer = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.payer_key)
        .map(|(_, a)| a)
        .expect("payer");
    let post_pda = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.pda_key)
        .map(|(_, a)| a)
        .expect("pda");
    assert_eq!(post_state.data, system_cpi_state(true, 13));
    assert_eq!(post_payer.lamports, case.payer_lamports - create_lamports);
    assert_eq!(post_pda.lamports, create_lamports);
    assert_eq!(post_pda.owner, program_id, "create owner = current program");
    assert_eq!(post_pda.data.len() as u64, space);
    assert!(
        post_pda.data.iter().all(|b| *b == 0),
        "create data must be zero-filled"
    );
    assert!(!post_pda.executable);
}

#[test]
fn create_space_4096_success() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 7u64;
    let space = SYSTEM_CREATE_MAX_SPACE;
    let create_lamports = 50_000_000u64;
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    let ix = case.instruction_canonical(
        program_id,
        CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
        create_lamports,
        space,
    );
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let post_pda = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.pda_key)
        .map(|(_, a)| a)
        .expect("pda");
    assert_eq!(post_pda.data.len() as u64, 4096);
    assert_eq!(post_pda.owner, program_id);
    assert_eq!(post_pda.lamports, create_lamports);
}

#[test]
fn wrong_system_program_key_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    let wrong = fixed_key(0x75);
    case.metas[3] = AccountMeta::new_readonly(wrong, false);
    // Fake executable program account is not the native System Program.
    let mut fake = create_program_account_loader_v3(&wrong);
    fake.executable = true;
    case.system_program_key = wrong;
    case.accounts[3] = (wrong, fake);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn non_executable_system_program_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    // Keep the zero System id but strip executable / wrong owner → preflight FC.
    case.accounts[3].1.executable = false;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn missing_payer_signer_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    case.metas[1] = AccountMeta::new(case.payer_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn missing_payer_writable_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    case.metas[1] = AccountMeta::new_readonly(case.payer_key, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn missing_recipient_writable_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    case.metas[2] = AccountMeta::new_readonly(case.recipient_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn transfer_account_order_swap_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    case.metas.swap(1, 2);
    case.accounts.swap(1, 2);
    std::mem::swap(&mut case.payer_key, &mut case.recipient_key);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn transfer_alias_payer_recipient_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let mut case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    case.metas[2] = AccountMeta::new(case.payer_key, false);
    case.accounts[2].0 = case.payer_key;
    case.accounts[2].1 = case.accounts[1].1.clone();
    case.recipient_key = case.payer_key;
    let pre = case.accounts.clone();
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
    assert_eq!(
        result.resulting_accounts, pre,
        "aliased failure must preserve every full account record in order"
    );
}

#[test]
fn transfer_insufficient_funds_propagates_system_error_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    // Payer has fewer lamports than requested transfer. Native System transfer
    // returns SystemError::ResultWithNegativeLamports (= Custom(1)), not
    // InstructionError::InsufficientFunds; cpi_failed exits with that code.
    let case = TransferCase::new(program_id, 10, 1_000, BASE_LAMPORTS);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 50_000),
        &case.accounts,
        Check::err(ProgramError::Custom(
            SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
        )),
    );
}

#[test]
fn create_already_initialized_propagates_system_error_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    // Explicit already-initialized target (non-zero lamports, still System-owned).
    // Production siteChecks require exact 0 lamports on the create target and
    // fail closed at err_shape (Custom(1)) before System CPI — so this never
    // reaches SystemError::AccountAlreadyInUse (Custom(0)). Pin actual path.
    case.accounts
        .iter_mut()
        .find(|(k, _)| *k == case.pda_key)
        .expect("pda")
        .1 = Account::new(1, 0, &Pubkey::default());
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_wrong_bump_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    let wrong_bump = if case.bump == 1 { 2 } else { case.bump - 1 };
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
            seed_tag,
            wrong_bump,
            5_000_000,
            64,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_noncanonical_key_and_bump_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    let (noncanonical_key, noncanonical_bump) =
        find_noncanonical_pda_below(&program_id, &case.seed_authority, seed_tag, case.bump);
    assert_ne!(noncanonical_key, case.pda_key);
    case.metas[2] = AccountMeta::new(noncanonical_key, false);
    case.accounts[2] = (noncanonical_key, unused_system_create_target_account());
    case.pda_key = noncanonical_key;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
            seed_tag,
            noncanonical_bump,
            5_000_000,
            64,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_wrong_pda_key_with_canonical_bump_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    let wrong_pda = fixed_key(0x77);
    case.metas[2] = AccountMeta::new(wrong_pda, false);
    case.accounts[2] = (wrong_pda, unused_system_create_target_account());
    case.pda_key = wrong_pda;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_bump_zero_rejected_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
            seed_tag,
            0,
            5_000_000,
            64,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_pda_outer_signer_privilege_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    case.metas[2] = AccountMeta::new(case.pda_key, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_seed_authority_unexpected_signer_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    // Contract: seedAuthority outerSignerContribution = false.
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_space_4097_pre_cpi_fail_closed_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(
            program_id,
            CPI_SYSTEM_CREATE_PDA_HANDLER_ID,
            5_000_000,
            SYSTEM_CREATE_MAX_SPACE + 1,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_missing_pda_writable_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    case.metas[2] = AccountMeta::new_readonly(case.pda_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_missing_payer_signer_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    // Single mutation: drop outer signer on create payer (writable kept).
    case.metas[1] = AccountMeta::new(case.payer_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_missing_payer_writable_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    // Single mutation: drop outer writable on create payer (signer kept).
    case.metas[1] = AccountMeta::new_readonly(case.payer_key, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn create_system_program_wrong_native_owner_fails_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let mut case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    // Keep the zero System program key and executable=true; only replace owner
    // so catalog native-owner preflight rejects (not key/executable checks).
    let system_idx = case
        .accounts
        .iter()
        .position(|(k, _)| *k == Pubkey::default())
        .expect("native System program account present");
    assert_eq!(case.metas[system_idx].pubkey, Pubkey::default());
    assert!(case.accounts[system_idx].1.executable);
    case.accounts[system_idx].1.owner = fixed_key(0x76);
    assert!(
        case.accounts[system_idx].1.executable,
        "executable must remain true for this owner-only mutation"
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction_canonical(program_id, CPI_SYSTEM_CREATE_PDA_HANDLER_ID, 5_000_000, 64),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn post_transfer_caller_overflow_rolls_back_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let case = TransferCase::new(program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    // Handler: value+=1; successful System transfer; value += U64::MAX → overflow.
    // Caller pre-CPI write and System lamport move must fully roll back.
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_SYSTEM_TRANSFER_THEN_OVERFLOW_HANDLER_ID,
            42_000,
        ),
        &case.accounts,
        Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
    );
}

#[test]
fn post_create_caller_overflow_rolls_back_full_snapshot() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let seed_tag = 42u64;
    let space = 64u64;
    let create_lamports = 5_000_000u64;
    // Valid canonical PDA/bump, funded payer, unused System-owned target.
    // Must reach successful native CreateAccount then caller 0x1001 overflow —
    // not an inner create failure substitute.
    let case = CreateCase::new(program_id, 10, seed_tag, BASE_LAMPORTS, false);
    assert_ne!(case.bump, 0, "canonical bump rejects 0");
    assert_eq!(
        case.accounts
            .iter()
            .find(|(k, _)| *k == case.pda_key)
            .map(|(_, a)| (a.lamports, a.data.len(), a.owner, a.executable)),
        Some((0, 0, Pubkey::default(), false)),
        "create target must start as unused System-owned empty account"
    );
    // Exact ARITHMETIC_OVERFLOW + empty return data: full snapshot proves
    // caller state, payer lamports, PDA allocation, seedAuthority, and native
    // System account all roll back to pre-state.
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction_canonical(
            program_id,
            CPI_SYSTEM_CREATE_THEN_OVERFLOW_HANDLER_ID,
            create_lamports,
            space,
        ),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::return_data(&[]),
        ],
    );
}

#[test]
fn success_return_data_is_caller_value_without_inner_leakage() {
    let (mollusk, program_id) = make_cpi_system_mollusk();
    let case = TransferCase::new(program_id, 100, BASE_LAMPORTS, BASE_LAMPORTS);
    // Final caller value = 100+1+2 = 103. System has no return data; outer must
    // publish only the caller UInt64 (no inner leak).
    mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_SYSTEM_TRANSFER_HANDLER_ID, 9),
        &case.accounts,
        &[Check::success(), Check::return_data(&103u64.to_le_bytes())],
    );
}

#[test]
fn init_and_inspect_without_cpi() {
    let (mollusk, program_id) = make_cpi_system_mollusk();

    let init_key = fixed_key(0x40);
    let init_account = state_account(&program_id, system_cpi_state(false, 0));
    let init_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_system_simple_ix_data(CPI_SYSTEM_INIT_HANDLER_ID, &[41]),
        vec![AccountMeta::new(init_key, true)],
    );
    let result = mollusk.process_and_validate_instruction(
        &init_ix,
        &[(init_key, init_account)],
        &[Check::success()],
    );
    let post = &result.resulting_accounts[0].1;
    assert_eq!(post.data, system_cpi_state(true, 41));

    let view_key = fixed_key(0x41);
    let view_account = state_account(&program_id, system_cpi_state(true, 77));
    let view_ix = Instruction::new_with_bytes(
        program_id,
        &cpi_system_simple_ix_data(CPI_SYSTEM_INSPECT_HANDLER_ID, &[]),
        vec![AccountMeta::new_readonly(view_key, false)],
    );
    mollusk.process_and_validate_instruction(
        &view_ix,
        &[(view_key, view_account)],
        &[Check::success(), Check::return_data(&77u64.to_le_bytes())],
    );
}
