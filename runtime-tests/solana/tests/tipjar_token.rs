//! # ADR-0030 E1b TipJarToken Mollusk product acceptance.
//!
//! Product build via `proof-forge-next build --target solana
//! --profile solana-sbpf-cpi-elf-v1` produces `TokenJarAssets.so`.
//! Loaded into Mollusk with vendored classic Token + ATA programs.
//!
//! Product surface (pf.assets token transfer + state):
//! - `init(initial)` handlerId=0, ix = handlerId u64 LE + initial u64 LE (16 B)
//! - `tipToken(mint, dst, amount)` handlerId=1, ix = handlerId u64 LE +
//!   amount u64 LE (16 B); mint + dst are account-bound Principal parameters
//! - `get()` handlerId=2, ix = handlerId u64 LE (8 B)
//!
//! tipToken outer roles (dense): state, tipToken_mint, tipToken_dst,
//! pf_caller (sole outer signer, ATA ensure payer), token-classic-v1 program,
//! pf_vault_ata, pf_dst_ata, pf_vault (vault PDA signer),
//! system-v1 program
//!
//! Runtime expectations:
//! - Create mint (vendored Token ELF), vault ATA funded with mint tokens,
//!   tipToken success (dst ATA +amount, vault ATA -amount, tips++)
//! - Negative: insufficient balance rollback, wrong mint join, non-canonical
//!   ATA, multi/zero signer
//!
//! **Mollusk tests are activated by the main agent on the integrated tree.**
//! This file compiles and is wired into `scripts/solana_runtime_test.sh`.

#![allow(dead_code)]

use {
    mollusk_svm::{result::Check, Mollusk},
    solana_pubkey::Pubkey,
    std::path::PathBuf,
};

// ---------------------------------------------------------------------------
// Frozen identities
// ---------------------------------------------------------------------------

/// Product fixture: `runtime-tests/solana/fixtures/TokenJarAssets.lean`.
const SOURCE_REL: &str = "runtime-tests/solana/fixtures/TokenJarAssets.lean";

/// Vault seed0 = ASCII `proof-forge:vault:v1`.
const VAULT_SEED0: &[u8] = b"proof-forge:vault:v1";

/// Frozen decimals for standard SPL test mint (9).
const MINT_DECIMALS: u8 = 9;

/// Token Account data size (classic SPL).
const TOKEN_ACCOUNT_DATA_BYTES: usize = 165;

/// Mint data size (classic SPL).
const TOKEN_MINT_DATA_BYTES: usize = 82;

/// Classic Token program ID raw bytes.
const TOKEN_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x06, 0xdd, 0xf6, 0xe1, 0xd7, 0x65, 0xa1, 0x93, 0xd9, 0xcb, 0xe1, 0x46, 0xce, 0xeb, 0x79, 0xac,
    0x1c, 0xb4, 0x85, 0xed, 0x5f, 0x5b, 0x37, 0x91, 0x3a, 0x8c, 0xf5, 0x85, 0x7e, 0xff, 0x00, 0xa9,
];

/// Classic ATA program ID raw bytes.
const ATA_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x8c, 0x97, 0x25, 0x8f, 0x4e, 0x24, 0x89, 0xf1, 0xbb, 0x3d, 0x10, 0x29, 0x14, 0x8e, 0x0d, 0x83,
    0x0b, 0x5a, 0x13, 0x99, 0xda, 0xff, 0x10, 0x84, 0x04, 0x8e, 0x7b, 0xd8, 0xdb, 0xe9, 0xf8, 0x59,
];

/// Native System program ID (32 zero bytes).
const SYSTEM_PROGRAM_ID_BYTES: [u8; 32] = [0; 32];

/// Loader V3 owner bytes.
const LOADER_V3_OWNER_BYTES: [u8; 32] = [
    0x02, 0xa8, 0xf6, 0x91, 0x4e, 0x88, 0xa1, 0xb0, 0xe2, 0x10, 0x15, 0x3e, 0xf7, 0x63, 0xae, 0x2b,
    0x00, 0xc2, 0xb9, 0x3d, 0x16, 0xc1, 0x24, 0xd2, 0xc0, 0x53, 0x7a, 0x10, 0x04, 0x80, 0x00, 0x00,
];

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn token_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_CLASSIC_PROGRAM_ID_BYTES)
}

fn ata_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(ATA_CLASSIC_PROGRAM_ID_BYTES)
}

fn system_program_id() -> Pubkey {
    Pubkey::new_from_array(SYSTEM_PROGRAM_ID_BYTES)
}

// ---------------------------------------------------------------------------
// Static pin tests (compile-time + file existence)
// ---------------------------------------------------------------------------

#[test]
fn tipjar_token_fixture_exists() {
    let root = repo_root();
    let fixture = root.join(SOURCE_REL);
    assert!(fixture.is_file(), "missing fixture: {}", fixture.display());
}

#[test]
fn vault_seed0_pin() {
    assert_eq!(VAULT_SEED0, b"proof-forge:vault:v1");
    assert_eq!(MINT_DECIMALS, 9);
}

#[test]
fn frozen_program_id_pins() {
    assert_eq!(
        hex::encode(TOKEN_CLASSIC_PROGRAM_ID_BYTES),
        "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
    );
    assert_eq!(
        hex::encode(ATA_CLASSIC_PROGRAM_ID_BYTES),
        "8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859"
    );
    assert_eq!(
        hex::encode(SYSTEM_PROGRAM_ID_BYTES),
        "0000000000000000000000000000000000000000000000000000000000000000"
    );
}

#[test]
fn loader_v3_owner_pin() {
    assert_eq!(
        hex::encode(LOADER_V3_OWNER_BYTES),
        "02a8f6914e88a1b0e210153ef763ae2b00c2b93d16c124d2c0537a1004800000"
    );
}

// ---------------------------------------------------------------------------
// Mollusk tests — activated by main agent on integrated tree
// ---------------------------------------------------------------------------

// TODO: Once the main agent activates this test on the integrated tree:
// 1. Build `TokenJarAssets.so` via product CLI on the integrated tree.
// 2. `init(initial)` → state tips = initial
// 3. `tipToken(mint, dst, amount)` success:
//    - vault ATA balance -amount, dst ATA balance +amount, tips++
//    - vault PDA signs transferChecked via invoke_signed
// 4. Negative: insufficient vault ATA balance → Token CPI failure + rollback
// 5. Negative: wrong mint join → site-time predicate failure
// 6. Negative: non-canonical ATA key → ATA address check failure
// 7. Negative: multi outer signer → handler reject
// 8. Negative: zero signer → handler reject (pf_caller must sign)
// 9. `get()` → returns tips readonly
//
// The main agent will populate the Mollusk test bodies below with the
// actual ELF paths, account setup, and assertion logic.

/// Mollusk placeholder — compiles but not yet wired.
fn _make_tipjar_mollusk() -> Mollusk {
    let _token_id = token_classic_program_id();
    let _ata_id = ata_classic_program_id();
    let _system_id = system_program_id();
    Mollusk::default()
}