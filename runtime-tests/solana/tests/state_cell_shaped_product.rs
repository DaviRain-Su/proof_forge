//! Generic StateCell-shaped Mollusk lane for developer CLI `pf test -t solana`.
//!
//! Works for **any** program name that matches the `pf new` / Examples.StateCell
//! surface:
//!   init(initial) / entry increment(delta) / view get()
//! with a single UInt64 `count` state field.
//!
//! Env (required):
//! - `PROOF_FORGE_SOLANA_TEST_OUT` — OutputSet dir (`manifest.json` + `{Name}.so`)
//!
//! Unlike `state_cell.rs` (pinned product name `StateCell`) and
//! `transfer_sol_product.rs` (CPI TransferSol gold), this lane is the
//! **default developer path** for `pf new hello && pf build && pf test`.
//!
//! Not formal / not mainnet / not full solana-runtime corpus.

#[allow(dead_code)]
mod common;

use {
    common::{
        build_ix, instruction_discriminator, make_mollusk, single_field, state_account,
        state_data, ARITHMETIC_OVERFLOW, STATE_HEADER_BYTES,
    },
    mollusk_svm::result::Check,
    serde::Deserialize,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{env, fs, path::PathBuf},
};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct OutputManifest {
    target: String,
    codegen_profile: String,
    artifact_program_name: String,
    deployable: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdlDoc {
    program_name: String,
    #[serde(default)]
    instructions: Vec<IdlIx>,
    #[serde(default)]
    state_schemas: Vec<IdlStateSchema>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdlIx {
    name: String,
    mode: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdlStateSchema {
    exact_data_len: usize,
}

fn output_dir() -> PathBuf {
    PathBuf::from(env::var("PROOF_FORGE_SOLANA_TEST_OUT").expect(
        "PROOF_FORGE_SOLANA_TEST_OUT must point at a StateCell-shaped OutputSet \
         (from `pf build -t solana`)",
    ))
}

fn load_manifest(out: &std::path::Path) -> OutputManifest {
    let bytes = fs::read(out.join("manifest.json")).expect("read manifest.json");
    serde_json::from_slice(&bytes).expect("decode manifest.json")
}

fn load_idl(out: &std::path::Path, program: &str) -> IdlDoc {
    let path = out.join(format!("{program}.idl.json"));
    let bytes = fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_slice(&bytes).unwrap_or_else(|e| panic!("decode {}: {e}", path.display()))
}

/// Surface `init` lowers to handler name `initialize` in asm/discriminators.
fn assert_state_cell_shaped(idl: &IdlDoc) {
    let modes: Vec<(&str, &str)> = idl
        .instructions
        .iter()
        .map(|i| (i.name.as_str(), i.mode.as_str()))
        .collect();
    let has_init = modes
        .iter()
        .any(|(n, m)| (*n == "init" || *n == "initialize") && *m == "initialize");
    let has_inc = modes
        .iter()
        .any(|(n, m)| *n == "increment" && *m == "entry");
    let has_get = modes.iter().any(|(n, m)| *n == "get" && *m == "view");
    assert!(
        has_init && has_inc && has_get,
        "not StateCell-shaped IDL (need init/initialize + increment + get); got {modes:?}"
    );
    let schema = idl
        .state_schemas
        .first()
        .expect("StateCell-shaped programs need one state schema");
    assert_eq!(
        schema.exact_data_len,
        STATE_HEADER_BYTES + 8,
        "expected single UInt64 state (exactDataLen=16), got {}",
        schema.exact_data_len
    );
}

fn count_state(initialized: bool, count: u64) -> Vec<u8> {
    state_data(&single_field("count"), initialized, &[count])
}

fn program_setup() -> (PathBuf, String, MolluskHandle) {
    let out = output_dir();
    let manifest = load_manifest(&out);
    assert_eq!(manifest.target, "solana");
    assert_eq!(manifest.codegen_profile, "solana-sbpf-cpi-elf-v1");
    assert!(
        manifest.deployable,
        "artifact must be deployable for Mollusk load"
    );
    let program = manifest.artifact_program_name.clone();
    let idl = load_idl(&out, &program);
    assert_eq!(idl.program_name, program);
    assert_state_cell_shaped(&idl);
    let program_id = Pubkey::new_unique();
    let mollusk = make_mollusk(&program_id, &out, &program);
    (out, program, MolluskHandle { mollusk, program_id })
}

struct MolluskHandle {
    mollusk: mollusk_svm::Mollusk,
    program_id: Pubkey,
}

#[test]
fn shaped_initialize_sets_count() {
    let (_out, _program, h) = program_setup();
    let state_key = Pubkey::new_unique();
    // Product lowers surface `init` → handler name `initialize` for discriminators.
    let disc = instruction_discriminator("initialize", 1);
    let ix = build_ix(h.program_id, state_key, &disc, &[5], true, true);
    let account = state_account(&h.program_id, count_state(false, 0));
    h.mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::account(&state_key)
                .data(&count_state(true, 5))
                .build(),
        ],
    );
}

#[test]
fn shaped_increment_updates_and_returns() {
    let (_out, _program, h) = program_setup();
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);
    let ix = build_ix(h.program_id, state_key, &disc, &[3], true, false);
    let account = state_account(&h.program_id, count_state(true, 5));
    let expected_return = 8u64.to_le_bytes();
    h.mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&expected_return),
            Check::account(&state_key)
                .data(&count_state(true, 8))
                .build(),
        ],
    );
}

#[test]
fn shaped_get_returns_count() {
    let (_out, _program, h) = program_setup();
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("get", 0);
    let ix = build_ix(h.program_id, state_key, &disc, &[], false, false);
    let account = state_account(&h.program_id, count_state(true, 8));
    let expected_return = 8u64.to_le_bytes();
    h.mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::success(),
            Check::return_data(&expected_return),
            Check::account(&state_key)
                .data(&count_state(true, 8))
                .build(),
        ],
    );
}

#[test]
fn shaped_increment_overflow_holds() {
    let (_out, _program, h) = program_setup();
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator("increment", 1);
    let pre = count_state(true, u64::MAX);
    let ix = build_ix(h.program_id, state_key, &disc, &[1], true, false);
    let account = state_account(&h.program_id, pre.clone());
    h.mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, account)],
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

#[test]
fn shaped_unknown_discriminator_custom_1() {
    let (_out, _program, h) = program_setup();
    let state_key = Pubkey::new_unique();
    let unknown = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];
    let ix = Instruction::new_with_bytes(
        h.program_id,
        &unknown,
        vec![AccountMeta::new(state_key, false)],
    );
    let account = state_account(&h.program_id, count_state(true, 0));
    common::assert_custom1_preserves_exact_accounts(&h.mollusk, &ix, &[(state_key, account)]);
}
