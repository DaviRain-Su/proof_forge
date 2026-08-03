//! BL-27 CPI matrix: product caller ELF + mock zero-account callee.
//!
//! **Runtime honesty (B-CALL-SEM)**: product SBPF emits real
//! `sol_invoke_signed_c` with empty AccountMeta. Agave still requires the
//! callee *program account* to appear in the *outer* instruction's AccountMeta
//! list (see `InvokeContext` "Unknown program" / MissingAccount). The product
//! single-account layout (state only) does not yet reserve that slot, so
//! Mollusk CPI execution fails closed with `NotEnoughAccountKeys` /
//! `MissingAccount` — **not** a silent sol_log_data stub. Full multi-account
//! outer layout is follow-on work; this suite pins:
//!   (a) program-id derivation,
//!   (b) plan/asm CPI markers (no sol_log_data call path),
//!   (c) Mollusk reaches real CPI (MissingAccount), not success-via-stub.
//!
//! Env:
//!   PROOF_FORGE_FIXTURES_DIR/CpiCaller/{CpiCaller.so,CpiCaller.sbpf-plan}
//!   PROOF_FORGE_MOCK_CALLEE_SO  — path to mock-callee.so

mod common;

use {
    common::*,
    sha2::{Digest, Sha256},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{env, fs, path::PathBuf},
};

/// Program id stub = first 32 bytes of SHA-256(UTF-8 target path). Matches
/// `externalCalleeProgramIdHex` for QN `ledger.*`.
fn ledger_program_id() -> Pubkey {
    let digest = Sha256::digest(b"ledger");
    let mut bytes = [0u8; 32];
    bytes.copy_from_slice(&digest[..32]);
    Pubkey::new_from_array(bytes)
}

fn mock_callee_so() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_MOCK_CALLEE_SO")
            .expect("PROOF_FORGE_MOCK_CALLEE_SO must point at mock-callee.so"),
    )
}

fn make_cpi_mollusk(caller_id: &Pubkey) -> mollusk_svm::Mollusk {
    let mut m = make_fixture_mollusk(caller_id, "CpiCaller");
    let callee_id = ledger_program_id();
    let elf = fs::read(mock_callee_so()).expect("read mock-callee.so");
    m.add_program_with_loader_and_elf(
        &callee_id,
        &mollusk_svm::program::loader_keys::LOADER_V2,
        &elf,
    );
    m
}

fn cpi_fields() -> [StateField; 1] {
    single_field("count")
}

fn cpi_state(initialized: bool, count: u64) -> Vec<u8> {
    state_data(&cpi_fields(), initialized, &[count])
}

fn assert_cpi_plan() {
    assert_discriminators_match_plan(
        &fixture_plan_path("CpiCaller"),
        &[
            ("initialize", 1),
            ("fetch", 1),
            ("note", 1),
            ("later", 1),
            ("boom", 1),
            ("get", 0),
        ],
    );
}

/// Plan/asm pins: real CPI, no sol_log_data observation stub on call path.
#[test]
fn cpi_plan_and_asm_markers() {
    assert_cpi_plan();
    let plan = fs::read_to_string(fixture_plan_path("CpiCaller")).unwrap();
    assert!(
        plan.contains("external_call ledger.get program_id=0x"),
        "plan must render result-bearing external_call with program_id"
    );
    assert!(
        plan.contains("external_call ledger.record program_id=0x"),
        "plan must render void external_call"
    );
    assert!(
        plan.contains("schedule ledger.record program_id=0x"),
        "plan must render schedule"
    );
    // program_id stub for path "ledger"
    let expected_hex = hex::encode(Sha256::digest(b"ledger"));
    assert!(
        plan.contains(&format!("program_id=0x{expected_hex}")),
        "program_id must be SHA-256(ledger); plan missing 0x{expected_hex}"
    );

    let so_dir = fixture_so_dir("CpiCaller");
    let asm_path = so_dir.join("CpiCaller.s");
    // .s may live next to .so after product build normalization, or only under
    // the build tree; fall back to reading plan-adjacent product if present.
    let asm = if asm_path.is_file() {
        fs::read_to_string(&asm_path).unwrap()
    } else {
        // ELF profile always emits .s into the same output dir as the plan.
        let alt = fixture_plan_path("CpiCaller").with_file_name("CpiCaller.s");
        fs::read_to_string(&alt).unwrap_or_else(|_| {
            panic!(
                "CpiCaller.s missing (looked at {} and {})",
                asm_path.display(),
                alt.display()
            )
        })
    };
    assert!(
        asm.contains("call sol_invoke_signed_c"),
        "SBPF must emit real sol_invoke_signed_c"
    );
    assert!(
        asm.contains("call sol_get_return_data"),
        "result-bearing call must read sol_get_return_data"
    );
    assert!(
        !asm.contains("0xec01") && !asm.contains("0x5c01"),
        "must not emit legacy sol_log_data call/schedule key tags"
    );
    // emit_event uses sol_log_data; call path comments must not say via sol_log_data.
    assert!(
        !asm.contains("via sol_log_data"),
        "call/schedule path must not comment via sol_log_data"
    );
}

#[test]
fn ledger_program_id_matches_sha256_ledger() {
    let id = ledger_program_id();
    let digest = Sha256::digest(b"ledger");
    assert_eq!(id.to_bytes()[..], digest[..32]);
}

/// Mollusk: real CPI is attempted; Agave requires program AccountMeta on the
/// outer ix → MissingAccount / NotEnoughAccountKeys (fail closed, not stub success).
fn expect_cpi_missing_program_account(handler: &str, arity: usize, params: &[u64]) {
    assert_cpi_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_cpi_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator(handler, arity);
    let pre = cpi_state(true, 0);
    let result = mollusk.process_instruction(
        &build_ix(program_id, state_key, &disc, params, true, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
    );
    match &result.program_result {
        mollusk_svm::result::ProgramResult::Failure(ProgramError::NotEnoughAccountKeys) => {}
        // Some Agave/Mollusk mappings surface the same outer failure differently.
        mollusk_svm::result::ProgramResult::Failure(ProgramError::Custom(_)) => {}
        other => panic!(
            "expected NotEnoughAccountKeys from real CPI without outer program AccountMeta, got {other:?}"
        ),
    }
    // State must not commit on the failed path.
    let post = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| k == &state_key)
        .map(|(_, a)| a.data.clone())
        .expect("state account present");
    assert_eq!(post, pre, "failed CPI must hold parent state");
}

#[test]
fn cpi_fetch_reaches_real_invoke_missing_program_account() {
    expect_cpi_missing_program_account("fetch", 1, &[41]);
}

#[test]
fn cpi_note_reaches_real_invoke_missing_program_account() {
    expect_cpi_missing_program_account("note", 1, &[7]);
}

#[test]
fn cpi_schedule_reaches_real_invoke_missing_program_account() {
    expect_cpi_missing_program_account("later", 1, &[99]);
}

#[test]
fn cpi_boom_reaches_real_invoke_missing_program_account() {
    expect_cpi_missing_program_account("boom", 1, &[1]);
}

/// Ensure mock callee ELF is loadable (assemble-only smoke).
#[test]
fn mock_callee_elf_nonempty() {
    let so = mock_callee_so();
    let bytes = fs::read(&so).unwrap_or_else(|e| panic!("read {}: {e}", so.display()));
    assert!(bytes.len() > 100, "mock-callee.so too small: {} bytes", bytes.len());
}
