//! Mollusk runtime differential for the product Counter ELF.
//!
//! Reference authority: `Tests/Semantic/ReferenceV1.lean` `testCounterReferenceSlice`
//! (init → increment → get → arithmeticOverflow on UInt64 max+1) and
//! `ProofForgeV2/Examples/Counter.lean`.
//!
//! Env (required; no hard-coded product paths):
//! - `PROOF_FORGE_SO_DIR`  — directory containing `Counter.so`
//! - `PROOF_FORGE_PLAN`    — path to `Counter.sbpf-plan` (discriminator cross-check)
//!
//! Mollusk API used (mollusk-svm 0.13.4 / mollusk-svm-result 0.13.4):
//! - `Mollusk::new(&program_id, program_name)` loads `{program_name}.so`
//!   via absolute path (Path::join with absolute second component) or
//!   `SBF_OUT_DIR` / cwd search.
//! - `process_and_validate_instruction(ix, accounts, checks)`
//! - `Check::success()`, `Check::err(ProgramError::Custom(code))`,
//!   `Check::return_data(&[u8])`, `Check::account(&pk).data(&[u8]).build()`
//!
//! Program exit codes map through the BPF loader to
//! `ProgramError::Custom(u32)` (r0 = 0 success; r0 = 0x1001 overflow;
//! r0 = 1 check failure / unknown discriminator).

use {
    mollusk_svm::{result::Check, Mollusk},
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_native_token::LAMPORTS_PER_SOL,
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{
        collections::BTreeMap,
        env, fs,
        path::{Path, PathBuf},
    },
};

/// Matches `LowerSemanticV1.discriminatorDomain`.
const DISCRIMINATOR_DOMAIN: &str = "proof-forge-solana-v1:";
/// Matches `LowerSemanticV1.layoutDomain`.
const LAYOUT_DOMAIN: &str = "proof-forge-solana-layout-v1:";
/// Matches `LowerSemanticV1.stateHeaderBytes` + one UInt64 field.
const EXACT_DATA_LEN: usize = 16;
/// Matches `LowerSemanticV1.arithmeticOverflowError`.
const ARITHMETIC_OVERFLOW: u32 = 0x1001;
/// Check failure / unknown discriminator exit (EmitSbpfAsmV1 err_check / err_unknown_disc).
const CHECK_OR_UNKNOWN: u32 = 1;
const BASE_LAMPORTS: u64 = 10 * LAMPORTS_PER_SOL;

/// Independent ABI: sha256 hex of `domain ++ name(u64,...)` → first 16 hex chars.
fn instruction_discriminator(name: &str, param_count: usize) -> String {
    let params = std::iter::repeat("u64")
        .take(param_count)
        .collect::<Vec<_>>()
        .join(",");
    let preimage = format!("{DISCRIMINATOR_DOMAIN}{name}({params})");
    let digest = Sha256::digest(preimage.as_bytes());
    hex::encode(digest)[..16].to_string()
}

/// Hex discriminator → 8 instruction-data bytes (byte 0 = first hex pair).
/// Matches `EmitSbpfAsmV1.discriminatorToLeU64V1` (LE load of these bytes).
fn discriminator_bytes(hex16: &str) -> [u8; 8] {
    let raw = hex::decode(hex16).expect("discriminator must be hex");
    assert_eq!(raw.len(), 8, "discriminator must be 8 bytes");
    let mut out = [0u8; 8];
    out.copy_from_slice(&raw);
    out
}

/// Counter single-field layout marker (`LowerSemanticV1.layoutMarker` firstWordBE).
fn counter_initialized_marker() -> u64 {
    // field sourceId=0 name=count account=0 offset=8 width=8 u64-le
    let field_sig = "0:count:0:8:8:u64-le";
    let layout_sig = format!("1|{field_sig}");
    let digest = Sha256::digest(format!("{LAYOUT_DOMAIN}{layout_sig}").as_bytes());
    let mut value: u64 = 0;
    for &b in &digest[..8] {
        value = (value << 8) | u64::from(b);
    }
    value
}

fn so_dir() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_SO_DIR")
            .expect("PROOF_FORGE_SO_DIR must point at the directory containing Counter.so"),
    )
}

fn plan_path() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_PLAN")
            .expect("PROOF_FORGE_PLAN must point at Counter.sbpf-plan"),
    )
}

/// Parse `.handler <hex16> <name> ...` lines from the product plan text.
fn parse_plan_handlers(plan_text: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for line in plan_text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix(".handler ") {
            let mut parts = rest.split_whitespace();
            let Some(hex) = parts.next() else { continue };
            let Some(name) = parts.next() else { continue };
            out.insert(name.to_string(), hex.to_string());
        }
    }
    out
}

/// Cross-check independent Rust discriminators against the product plan.
fn assert_discriminators_match_plan() {
    let plan = fs::read_to_string(plan_path()).expect("read PROOF_FORGE_PLAN");
    let from_plan = parse_plan_handlers(&plan);
    let expected = [
        ("initialize", 1usize),
        ("increment", 1),
        ("get", 0),
    ];
    for (name, arity) in expected {
        let independent = instruction_discriminator(name, arity);
        let plan_hex = from_plan
            .get(name)
            .unwrap_or_else(|| panic!("plan missing .handler for {name}"));
        assert_eq!(
            plan_hex, &independent,
            "ABI drift: plan discriminator for {name} ({plan_hex}) != independent ({independent})"
        );
    }
    // Plan must not silently gain extra Counter handlers without a test update.
    assert_eq!(
        from_plan.len(),
        expected.len(),
        "unexpected handlers in plan: {from_plan:?}"
    );
}

fn make_mollusk(program_id: &Pubkey) -> Mollusk {
    let so = so_dir();
    assert!(
        so.join("Counter.so").is_file(),
        "Counter.so missing under {}",
        so.display()
    );
    // Absolute program_name so load_program_elf finds `{name}.so` via Path::join.
    let program_name = so.join("Counter");
    Mollusk::new(program_id, program_name.to_str().expect("utf-8 so path"))
}

fn instruction_data(disc_hex: &str, params: &[u64]) -> Vec<u8> {
    let mut data = discriminator_bytes(disc_hex).to_vec();
    for p in params {
        data.extend_from_slice(&p.to_le_bytes());
    }
    data
}

fn state_data(initialized: bool, count: u64) -> Vec<u8> {
    let mut data = vec![0u8; EXACT_DATA_LEN];
    if initialized {
        data[..8].copy_from_slice(&counter_initialized_marker().to_le_bytes());
    }
    data[8..16].copy_from_slice(&count.to_le_bytes());
    data
}

fn state_account(program_id: &Pubkey, data: Vec<u8>) -> Account {
    let mut account = Account::new(BASE_LAMPORTS, EXACT_DATA_LEN, program_id);
    account.data = data;
    account
}

fn build_ix(
    program_id: Pubkey,
    state_key: Pubkey,
    disc_hex: &str,
    params: &[u64],
    writable: bool,
    signer: bool,
) -> Instruction {
    let meta = if writable {
        AccountMeta::new(state_key, signer)
    } else {
        AccountMeta::new_readonly(state_key, signer)
    };
    Instruction::new_with_bytes(program_id, &instruction_data(disc_hex, params), vec![meta])
}

/// Reference: init(7) → state count=7, Unit return (no return_data).
/// Spec case (a) uses init(5); same path as Reference init.
#[test]
fn counter_initialize_sets_count() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("initialize", 1);

    let ix = build_ix(program_id, state_key, &disc, &[5], true, true);
    let account = state_account(&program_id, state_data(false, 0));

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&state_data(true, 5))
                .build(),
        ],
    );
}

/// Reference: entry increment(5) on count=7 → 12 returned + stored.
/// Spec (b): after init(5), increment(3) → 8.
#[test]
fn counter_increment_updates_and_returns() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);

    let ix = build_ix(program_id, state_key, &disc, &[3], true, false);
    let account = state_account(&program_id, state_data(true, 5));
    let expected_return = 8u64.to_le_bytes();

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&expected_return),
            Check::account(&state_key)
                .data(&state_data(true, 8))
                .build(),
        ],
    );
}

/// Reference: view get → returns count, no state change.
/// Spec (c): get() after count=8 → return 8 LE.
#[test]
fn counter_get_returns_count() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);

    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    let account = state_account(&program_id, state_data(true, 8));
    let expected_return = 8u64.to_le_bytes();

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&expected_return),
            Check::account(&state_key)
                .data(&state_data(true, 8))
                .build(),
        ],
    );
}

/// Reference: UInt64 max + 1 → standard arithmeticOverflow; pre-state unchanged.
/// Spec (d): overflow → Custom(0x1001).
#[test]
fn counter_increment_overflow_custom_0x1001() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);

    let pre = state_data(true, u64::MAX);
    let ix = build_ix(program_id, state_key, &disc, &[1], true, false);
    let account = state_account(&program_id, pre.clone());

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            // Failed instruction must not commit state writes.
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Spec (e): unknown 8-byte discriminator → exit 1 → Custom(1).
#[test]
fn counter_unknown_discriminator_custom_1() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();

    // Non-zero bytes that are not any product handler disc (all product discs start 0x5e/0x9d/0xa4).
    let unknown = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];
    let ix = Instruction::new_with_bytes(
        program_id,
        &unknown,
        vec![AccountMeta::new(state_key, false)],
    );
    let account = state_account(&program_id, state_data(true, 0));

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
}

/// Spec (f): owner != current_program → check path exit 1.
#[test]
fn counter_wrong_owner_check_fails() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);

    let ix = build_ix(program_id, state_key, &disc, &[], false, false);
    // Owned by a foreign key, not the program id.
    let foreign = Pubkey::new_unique();
    let account = state_account(&foreign, state_data(true, 8));

    mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );
}

/// End-to-end chain matching the Reference Counter trace shape
/// (init(7) → increment(5) → get → overflow on max).
#[test]
fn counter_reference_trace_chain() {
    assert_discriminators_match_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id);
    let state_key = Pubkey::new_unique();

    let init_disc = instruction_discriminator("initialize", 1);
    let inc_disc = instruction_discriminator("increment", 1);
    let get_disc = instruction_discriminator("get", 0);

    // init(7)
    let init_ix = build_ix(program_id, state_key, &init_disc, &[7], true, true);
    let result = mollusk.process_and_validate_instruction(
        &init_ix,
        &[(state_key, state_account(&program_id, state_data(false, 0)))],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&state_data(true, 7))
                .build(),
        ],
    );
    let after_init = result
        .resulting_accounts
        .into_iter()
        .find(|(k, _)| k == &state_key)
        .expect("state account after init")
        .1;

    // increment(5) → 12
    let inc_ix = build_ix(program_id, state_key, &inc_disc, &[5], true, false);
    let result = mollusk.process_and_validate_instruction(
        &inc_ix,
        &[(state_key, after_init)],
        &[
            Check::success(),
            Check::return_data(&12u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&state_data(true, 12))
                .build(),
        ],
    );
    let after_inc = result
        .resulting_accounts
        .into_iter()
        .find(|(k, _)| k == &state_key)
        .expect("state account after increment")
        .1;

    // get → 12
    let get_ix = build_ix(program_id, state_key, &get_disc, &[], false, false);
    mollusk.process_and_validate_instruction(
        &get_ix,
        &[(state_key, after_inc)],
        &[
            Check::success(),
            Check::return_data(&12u64.to_le_bytes()),
            Check::account(&state_key)
                .data(&state_data(true, 12))
                .build(),
        ],
    );
}

/// Sanity: product plan path is readable and SO dir contains ELF magic.
#[test]
fn product_artifacts_present() {
    let so = so_dir().join("Counter.so");
    let bytes = fs::read(&so).expect("read Counter.so");
    assert!(bytes.len() > 64, "Counter.so too small: {}", bytes.len());
    assert_eq!(&bytes[..4], b"\x7fELF", "Counter.so is not ELF");
    assert!(Path::new(&plan_path()).is_file(), "plan missing");
    assert_discriminators_match_plan();
    // Fixed Counter marker must be non-zero (reserved uninitialized).
    assert_ne!(counter_initialized_marker(), 0);
}
