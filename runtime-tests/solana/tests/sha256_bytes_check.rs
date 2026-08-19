//! CAP-X-BYTES-SOL-MOLLUSK: `pf.crypto.sha256Bytes(Bytes N) -> UInt256`
//! Mollusk product acceptance.
//!
//! Fixture: `runtime-tests/solana/fixtures/Sha256BytesCheck.lean`, built
//! through ordinary `proof-forge-next build --target solana` (sole rail
//! `solana-sbpf-cpi-elf-v1`) by `scripts/solana_runtime_test.sh` into
//! `PROOF_FORGE_FIXTURES_DIR/Sha256BytesCheck/`.
//!
//! Solana honesty: the leaf is `sol_sha256` over the packed source bytes
//! (single slice, len=N), not a CPI and not the UInt256-word SHA-256 leaf.
//! Known vectors hash the raw 4-byte payload (not a 32-byte LE word):
//!   * `[0,0,0,0]` → SHA-256(4×0x00)
//!   * `b"abcd"` → SHA-256("abcd")
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
    sha2::{Digest, Sha256},
    solana_pubkey::Pubkey,
};

const PROGRAM: &str = "Sha256BytesCheck";

const HASH_BYTES_WIDTHS: [usize; 4] = [1, 1, 1, 1];

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

/// SHA-256 of the packed source bytes as four little-endian u64 limbs.
fn digest_limbs_of_bytes(payload: &[u8]) -> [u64; 4] {
    let digest = Sha256::digest(payload);
    let mut limbs = [0u64; 4];
    for i in 0..4 {
        limbs[i] = u64::from_le_bytes(digest[i * 8..(i + 1) * 8].try_into().unwrap());
    }
    limbs
}

fn hash_bytes_ix(program_id: Pubkey, state_key: Pubkey, payload: [u8; 4]) -> solana_instruction::Instruction {
    let disc = instruction_discriminator_with_widths("hashBytes", &HASH_BYTES_WIDTHS);
    build_ix_limbs(
        program_id,
        state_key,
        &disc,
        &[
            (1, &[u64::from(payload[0])]),
            (1, &[u64::from(payload[1])]),
            (1, &[u64::from(payload[2])]),
            (1, &[u64::from(payload[3])]),
        ],
        true,
        false,
    )
}

fn assert_sha256_bytes_plan() {
    assert_discriminators_match_plan_widths(
        &fixture_plan_bytes(PROGRAM),
        &[
            ("initialize", vec![]),
            ("hashBytes", HASH_BYTES_WIDTHS.to_vec()),
            ("get", vec![]),
        ],
    );
}

/// `hashBytes([0,0,0,0])` returns and stores SHA-256 of four packed zeros.
#[test]
fn hash_bytes_zero4_known_vector() {
    assert_sha256_bytes_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, PROGRAM);
    let state_key = Pubkey::new_unique();
    let payload = [0u8, 0, 0, 0];
    let expected = digest_limbs_of_bytes(&payload);
    mollusk.process_and_validate_instruction(
        &hash_bytes_ix(program_id, state_key, payload),
        &[(
            state_key,
            state_account(&program_id, sha256_state(true, [1, 2, 3, 4])),
        )],
        &[
            Check::success(),
            Check::return_data(&digest_return(expected)),
            Check::account(&state_key)
                .data(&sha256_state(true, expected))
                .build(),
        ],
    );
}

/// `hashBytes(b"abcd")` hashes the four packed ASCII bytes, not a LE word.
#[test]
fn hash_bytes_abcd_known_vector() {
    assert_sha256_bytes_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, PROGRAM);
    let state_key = Pubkey::new_unique();
    let payload = *b"abcd";
    let expected = digest_limbs_of_bytes(&payload);
    mollusk.process_and_validate_instruction(
        &hash_bytes_ix(program_id, state_key, payload),
        &[(
            state_key,
            state_account(&program_id, sha256_state(true, [0, 0, 0, 0])),
        )],
        &[
            Check::success(),
            Check::return_data(&digest_return(expected)),
            Check::account(&state_key)
                .data(&sha256_state(true, expected))
                .build(),
        ],
    );
}

/// View `get()` rereads the stored digest without invoking `sol_sha256`.
#[test]
fn get_reads_stored_digest() {
    assert_sha256_bytes_plan();
    let program_id = Pubkey::new_unique();
    let mollusk = make_fixture_mollusk(&program_id, PROGRAM);
    let state_key = Pubkey::new_unique();
    let disc = instruction_discriminator_with_widths("get", &[]);
    let stored = digest_limbs_of_bytes(b"abcd");
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

/// Assembly honesty: dedicated single-slice `sol_sha256` of length 4, never CPI.
#[test]
fn product_assembly_emits_sol_sha256_single_slice() {
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
        text.contains("lddw r2, 1"),
        "assembly must pass a single slice (r2 = 1)"
    );
    assert!(
        text.contains("lddw r1, 4"),
        "assembly slice length must be N=4"
    );
    assert!(
        !text.contains("call sol_invoke"),
        "sha256Bytes leaf must not invent a CPI invoke"
    );
}
