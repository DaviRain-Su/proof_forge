//! # ADR-0031 SYS-S5-SOLANA: `pf.crypto.sha256` Mollusk product acceptance.
//!
//! Fixture: `runtime-tests/solana/fixtures/Sha256Check.lean`, built through
//! ordinary `proof-forge-next build --target solana` (sole rail
//! `solana-sbpf-cpi-elf-v1`) by `scripts/solana_runtime_test.sh` into
//! `PROOF_FORGE_FIXTURES_DIR/Sha256Check/`.
//!
//! Solana honesty: the leaf is `sol_sha256` over the UInt256 little-endian
//! 32-byte word, not a CPI. Known vectors:
//!   * 0 → SHA-256 of 32 zero bytes
//!   * 1 → SHA-256 of LE `01 || 00^31`
//!
//! Engineering gate only — not formal, not hermetic, not EXT-CRYPTO closeout.

mod common;

use {
    common::{
        assert_discriminators_match_plan_widths, build_ix_limbs, fields_with_widths,
        fixture_plan_bytes, instruction_discriminator_with_widths, make_fixture_mollusk,
        read_manifest_leaf_bytes, state_account, state_data_limbs, StateField,
    },
    mollusk_svm::result::Check,
    solana_pubkey::Pubkey,
};

const PROGRAM: &str = "Sha256Check";

/// SHA-256(32 zero bytes) as four little-endian u64 limbs.
const ZERO_DIGEST: [u64; 4] = [
    0x77bd62f8ad7a6866,
    0x208e9f8e8bc18f6c,
    0xb333e26e85149708,
    0x25295f0d1d592a90,
];

/// SHA-256(LE encoding of UInt256 1) as four little-endian u64 limbs.
const ONE_DIGEST: [u64; 4] = [
    0xbecb1f25bdfad001,
    0xd26ab227b9b4932b,
    0xde452e157790a9a1,
    0xc5be5da4af78e6d1,
];

fn sha256_fields() -> Vec<StateField> {
    fields_with_widths(&[("last", 32)])
}

fn sha256_state(initialized: bool, last: [u64; 4]) -> Vec<u8> {
    state_data_limbs(&sha256_fields(), initialized, &[last.as_slice()])
}

fn digest_return(limbs: [u64; 4]) -> Vec<u8> {
    let mut out = Vec::with_capacity(32);
    for limb in limbs {
        out.extend_from_slice(&limb.to_le_bytes());
    }
    out
}

fn assert_sha256_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes(PROGRAM),
        &[
            ("initialize", vec![]),
            ("hashWord", vec![32]),
            ("get", vec![]),
        ],
    );
}

/// `hashWord(0)` returns and stores SHA-256 of 32 zero bytes.
#[test]
fn hash_word_zero_known_vector() {
    assert_sha256_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, PROGRAM);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("hashWord", &[32]);
    let input = [0u64, 0, 0, 0];
    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, input.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, sha256_state(true, [1, 2, 3, 4])),
        )],
        &[
            Check::success(),
            Check::return_data(&digest_return(ZERO_DIGEST)),
            Check::account(&state_key)
                .data(&sha256_state(true, ZERO_DIGEST))
                .build(),
        ],
    );
}

/// `hashWord(1)` uses the LE encoding of 1 (not the EVM big-endian word).
#[test]
fn hash_word_one_known_vector() {
    assert_sha256_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, PROGRAM);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("hashWord", &[32]);
    let input = [1u64, 0, 0, 0];
    mollusk.process_and_validate_instruction(
        &build_ix_limbs(
            program_id,
            state_key,
            &disc,
            &[(32, input.as_slice())],
            true,
            false,
        ),
        &[(
            state_key,
            state_account(&program_id, sha256_state(true, [0, 0, 0, 0])),
        )],
        &[
            Check::success(),
            Check::return_data(&digest_return(ONE_DIGEST)),
            Check::account(&state_key)
                .data(&sha256_state(true, ONE_DIGEST))
                .build(),
        ],
    );
}

/// View `get()` rereads the stored digest without invoking `sol_sha256`.
#[test]
fn get_reads_stored_digest() {
    assert_sha256_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, PROGRAM);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("get", &[]);
    let stored = ONE_DIGEST;
    let pre = sha256_state(true, stored);
    mollusk.process_and_validate_instruction(
        &build_ix_limbs(program_id, state_key, &disc, &[], false, false),
        &[(state_key, state_account(&program_id, pre.clone()))],
        &[
            Check::success(),
            Check::return_data(&digest_return(stored)),
            Check::account(&state_key).data(&pre).build(),
        ],
    );
}

/// Assembly honesty: dedicated `sol_sha256`, never a hashed CPI fallback.
#[test]
fn product_assembly_emits_sol_sha256() {
    let out = common::fixture_output_dir(PROGRAM);
    let assembly =
        read_manifest_leaf_bytes(&out, PROGRAM, &format!("{PROGRAM}.s"), "materialized-base")
            .unwrap_or_else(|error| panic!("{PROGRAM} assembly binding failed: {error}"));
    let text = String::from_utf8_lossy(&assembly);
    assert!(
        text.contains("call sol_sha256"),
        "assembly must call sol_sha256"
    );
    assert!(
        !text.contains("call sol_invoke"),
        "sha256 leaf must not invent a CPI invoke"
    );
}
