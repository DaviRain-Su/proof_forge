//! # ADR-0030 E1b TipJarToken Mollusk product acceptance (DRAFT).
//!
//! **STATUS: DRAFT — not yet wired into `scripts/solana_runtime_test.sh`.**
//!
//! This test builds `runtime-tests/solana/fixtures/TokenJarAssets.lean` through
//! ordinary `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! and loads the manifest-bound `TokenJarAssets.so` into Mollusk with the
//! vendored classic Token + ATA programs.
//!
//! Product surface (pf.assets token transfer + state):
//! - `init(initial)` handlerId=0, ix = handlerId u64 LE + initial u64 LE (16 B)
//! - `tipToken(mint, dst, amount)` handlerId=1, ix = handlerId u64 LE +
//!   amount u64 LE (16 B); mint + dst are account-bound Principal parameters
//! - `get()` handlerId=2, ix = handlerId u64 LE (8 B)
//!
//! tipToken outer roles (dense): state, tipToken_mint, tipToken_dst,
//! pf_caller (sole outer signer, ATA ensure payer), token-classic-v1 program,
//! pf_vault_ata, pf_dst_ata, pf_vault (vault PDA signer)
//!
//! Runtime expectations:
//! - Create mint (vendored Token ELF in supply-chain), vault ATA funded with
//!   mint tokens, tipToken success (dst ATA +amount, vault ATA −amount, tips++)
//! - Negative: insufficient balance rollback, wrong mint join, non-canonical
//!   ATA, multi/zero signer
//!
//! **Wiring**: add to `scripts/solana_runtime_test.sh` after the existing
//! `tipjar_assets` test entry:
//! ```sh
//! run_test "tipjar_token" "TipJarToken" "Examples.TokenJarAssets" \
//!   "runtime-tests/solana/fixtures/TokenJarAssets.lean"
//! ```
//! The test requires the vendored Token + ATA ELFs already pinned under
//! `supply-chain/solana-cpi-assets/v1/`.
//!
//! **DEFERRED**: The composite SBPF emitter (ATA ensure ×2 + transferCheckedPda)
//! is not yet implemented; product build fails closed at emit. This test file
//! is a DRAFT that will be activated once the emitter lands.

#![allow(dead_code)]

use {
    mollusk_svm::{result::Check, Mollusk},
    solana_pubkey::Pubkey,
};

const PROGRAM_NAME: &str = "TokenJarAssets";
const SOURCE_REL: &str = "runtime-tests/solana/fixtures/TokenJarAssets.lean";

/// Placeholder: vault seed0 = ASCII `proof-forge:vault:v1`.
const VAULT_SEED0: &[u8] = b"proof-forge:vault:v1";

/// Frozen decimals for standard SPL test mint (9).
const MINT_DECIMALS: u8 = 9;

#[test]
fn tipjar_token_fixture_exists() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let fixture = root.join(SOURCE_REL);
    assert!(fixture.is_file(), "missing fixture: {}", fixture.display());
}

#[test]
fn vault_seed0_pin() {
    assert_eq!(VAULT_SEED0, b"proof-forge:vault:v1");
    assert_eq!(MINT_DECIMALS, 9);
}

// ---------------------------------------------------------------------------
// Mollusk tests — DRAFT (activated once emitter lands)
// ---------------------------------------------------------------------------

// TODO: Once the composite SBPF emitter is implemented:
// 1. `init(initial)` → state tips = initial
// 2. `tipToken(mint, dst, amount)` success:
//    - vault ATA balance −amount, dst ATA balance +amount, tips++
//    - vault PDA signs transferChecked via invoke_signed
// 3. Negative: insufficient vault ATA balance → Token CPI failure + rollback
// 4. Negative: wrong mint join → site-time predicate failure
// 5. Negative: non-canonical ATA key → ATA address check failure
// 6. Negative: multi outer signer → handler reject
// 7. Negative: zero signer → handler reject (pf_caller must sign)
// 8. `get()` → returns tips readonly