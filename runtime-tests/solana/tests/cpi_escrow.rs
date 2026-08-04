//! #124 production-code-generated composite escrow CPI runtime lane.
//!
//! Requires `PROOF_FORGE_CPI_ESCROW_OUT` from `scripts/solana_cpi_escrow_build.sh`
//! (or equivalent). Runtime reads **only** that staging directory:
//! exact-byte compare staged `manifest.json` to committed
//! `runtime-tests/solana/escrow/manifest.json`, then pin-check
//! `escrow_cpi.{s,so}` (+ ASCII `.size`/`.sha256` sidecars) and staged
//! ATA/Token ELFs against committed vendored bytes + hardcoded final pins.
//! Direct caller ELF / assembly / ATA / Token override env vars are rejected.
//! Native System is the Mollusk builtin (zero program id).
//!
//! Outer account orders (dense, state-first; Principals by param ordinal,
//! then site program/fixed roles in source site order):
//!
//! initializeVault / initializeThenOverflow (9 roles):
//!   0 state(w) 1 payer(w+s) 2 authorityPda(w) 3 seedAuthority(ro)
//!   4 vaultAta(w) 5 mint(ro) 6 system(ro) 7 ata(ro) 8 token(ro)
//!
//! deposit / depositThenOverflow (6 roles):
//!   0 state(w) 1 source(w) 2 mint(ro) 3 vaultAta(w)
//!   4 userAuthority(ro+s) 5 token(ro)
//!
//! release|refund / *ThenOverflow (7 roles):
//!   0 state(w) 1 vaultAta(w) 2 mint(ro) 3 destination(w)
//!   4 authorityPda(ro) 5 seedAuthority(ro+s) 6 token(ro)
//!
//! Sequential deposit→release→refund feeds each instruction's
//! `resulting_accounts` into the next; this is NOT multi-top-level
//! transaction atomicity.

#[allow(dead_code)]
mod common;

use {
    common::*,
    curve25519_dalek::edwards::CompressedEdwardsY,
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    solana_svm_log_collector::LogCollector,
    std::{
        collections::BTreeMap,
        env, fs,
        path::{Path, PathBuf},
        rc::Rc,
    },
};

// ---------------------------------------------------------------------------
// Frozen #124 identities
// ---------------------------------------------------------------------------

const CPI_ESCROW_PROGRAM_ID_BYTES: [u8; 32] = [0x59; 32];
const ATA_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x8c, 0x97, 0x25, 0x8f, 0x4e, 0x24, 0x89, 0xf1, 0xbb, 0x3d, 0x10, 0x29, 0x14, 0x8e, 0x0d, 0x83,
    0x0b, 0x5a, 0x13, 0x99, 0xda, 0xff, 0x10, 0x84, 0x04, 0x8e, 0x7b, 0xd8, 0xdb, 0xe9, 0xf8, 0x59,
];
const TOKEN_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x06, 0xdd, 0xf6, 0xe1, 0xd7, 0x65, 0xa1, 0x93, 0xd9, 0xcb, 0xe1, 0x46, 0xce, 0xeb, 0x79, 0xac,
    0x1c, 0xb4, 0x85, 0xed, 0x5f, 0x5b, 0x37, 0x91, 0x3a, 0x8c, 0xf5, 0x85, 0x7e, 0xff, 0x00, 0xa9,
];
const TOKEN_2022_PROGRAM_ID_BYTES: [u8; 32] = [
    0x06, 0xdd, 0xf6, 0xe1, 0xee, 0x75, 0x8f, 0xde, 0x18, 0x42, 0x5d, 0xbc, 0xe4, 0x6c, 0xcd, 0xda,
    0xb6, 0x1a, 0xfc, 0x4d, 0x83, 0xb9, 0x0d, 0x27, 0xfe, 0xbd, 0xf9, 0x28, 0xd8, 0xa1, 0x8b, 0xfc,
];
const LOADER_V3_OWNER_BYTES: [u8; 32] = [
    0x02, 0xa8, 0xf6, 0x91, 0x4e, 0x88, 0xa1, 0xb0, 0xe2, 0x10, 0x15, 0x3e, 0xf7, 0x63, 0xae, 0x2b,
    0x00, 0xc2, 0xb9, 0x3d, 0x16, 0xc1, 0x24, 0xd2, 0xc0, 0x53, 0x7a, 0x10, 0x04, 0x80, 0x00, 0x00,
];

const CPI_ESCROW_FIXTURE_SHA256: &str =
    "0424045e7cdc7e3c57b79d95c144e6047819db91b46c39607e42bf256b7c33bf";
const CPI_ESCROW_FIXTURE_SIZE: u64 = 5378;
// Final pins must match committed runtime-tests/solana/escrow/manifest.json
// expectedAssembly / expectedElf (and staged sidecars after exact manifest join).
const CPI_ESCROW_ASSEMBLY_SHA256: &str =
    "577f40646abb0a355bedebb76dd6b208ff39ae802bea1dab21ce4795ba5d102b";
const CPI_ESCROW_ASSEMBLY_SIZE: u64 = 366006;
const CPI_ESCROW_ELF_SHA256: &str =
    "28744d799b9a58208a54066d730a97a45e4363ae4f407132cf49c0bc7782b5f9";
const CPI_ESCROW_ELF_SIZE: u64 = 158536;
const ATA_CLASSIC_ELF_SHA256: &str =
    "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519";
const ATA_CLASSIC_ELF_SIZE: u64 = 111136;
const TOKEN_CLASSIC_ELF_SHA256: &str =
    "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9";
const TOKEN_CLASSIC_ELF_SIZE: u64 = 94960;
const EXTENSION_DIGEST: &str = "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020";
const PDA_SEED0_UTF8: &str = "proof-forge:pda:v1";
const PDA_SEED0_HEX: &str = "70726f6f662d666f7267653a7064613a7631";

const CPI_ESCROW_INIT_HANDLER_ID: u64 = 0;
const CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID: u64 = 1;
const CPI_ESCROW_DEPOSIT_HANDLER_ID: u64 = 2;
const CPI_ESCROW_RELEASE_HANDLER_ID: u64 = 3;
const CPI_ESCROW_REFUND_HANDLER_ID: u64 = 4;
const CPI_ESCROW_INITIALIZE_THEN_OVERFLOW_HANDLER_ID: u64 = 5;
const CPI_ESCROW_DEPOSIT_THEN_OVERFLOW_HANDLER_ID: u64 = 6;
const CPI_ESCROW_RELEASE_THEN_OVERFLOW_HANDLER_ID: u64 = 7;
const CPI_ESCROW_REFUND_THEN_OVERFLOW_HANDLER_ID: u64 = 8;
const CPI_ESCROW_INSPECT_HANDLER_ID: u64 = 9;

/// initializeVault ix: handler + seedTag + bump + pdaLamports + pdaSpace.
const CPI_ESCROW_INITIALIZE_IX_LEN: usize = 33;
/// deposit ix: handler + amount + decimals.
const CPI_ESCROW_DEPOSIT_IX_LEN: usize = 17;
/// release/refund ix: handler + seedTag + bump + amount + decimals.
const CPI_ESCROW_RELEASE_IX_LEN: usize = 26;

const CPI_ESCROW_INIT_ROLES: usize = 1;
const CPI_ESCROW_INITIALIZE_ROLES: usize = 9;
const CPI_ESCROW_DEPOSIT_ROLES: usize = 6;
const CPI_ESCROW_RELEASE_ROLES: usize = 7;

const TOKEN_TRANSFER_CHECKED_TAG: u8 = 12;
const TOKEN_MINT_DATA_BYTES: usize = 82;
const TOKEN_ACCOUNT_DATA_BYTES: usize = 165;
const TOKEN_ACCOUNT_STATE_UNINITIALIZED: u8 = 0;
const TOKEN_ACCOUNT_STATE_INITIALIZED: u8 = 1;
const TOKEN_ACCOUNT_STATE_FROZEN: u8 = 2;
const TOKEN_ERR_INSUFFICIENT_FUNDS: u32 = 1;
/// Classic Token v9 destination amount overflow (same pin as #122).
const TOKEN_ERR_DESTINATION_AMOUNT_OVERFLOW: u32 = 14;
const SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS: u32 = 1;
const ATA_RENT_LAMPORTS: u64 = 2_039_280;
/// Rent-exempt for a 0-byte System account under pinned Mollusk/Agave.
const PDA_SPACE0_RENT_LAMPORTS: u64 = 890_880;
const CPI_ESCROW_STEM: &str = "escrow_cpi";

// ---------------------------------------------------------------------------
// Manifest-bound artifact / env contract (PROOF_FORGE_CPI_ESCROW_OUT only)
// ---------------------------------------------------------------------------

fn stable_read(path: &Path, label: &str) -> Vec<u8> {
    fs::read(path).unwrap_or_else(|e| panic!("{label}: {}: {e}", path.display()))
}

fn repo_manifest_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn repo_root() -> PathBuf {
    repo_manifest_dir()
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn reject_override_env(name: &str) {
    if env::var_os(name).is_some() {
        panic!(
            "{name} is rejected: escrow runtime is manifest-bound to \
             PROOF_FORGE_CPI_ESCROW_OUT only (no direct ELF/ASM/override paths)"
        );
    }
}

fn cpi_escrow_out_dir() -> PathBuf {
    for forbidden in [
        "PF_SOLANA_CPI_ESCROW_CALLER_ELF",
        "PF_SOLANA_CPI_ESCROW_CALLER_ASM",
        "PF_SOLANA_CPI_ATA_ELF",
        "PF_SOLANA_CPI_TOKEN_ELF",
    ] {
        reject_override_env(forbidden);
    }
    PathBuf::from(env::var("PROOF_FORGE_CPI_ESCROW_OUT").expect(
        "PROOF_FORGE_CPI_ESCROW_OUT must point at scripts/solana_cpi_escrow_build.sh output \
         (staging dir with manifest.json + escrow_cpi.{{s,so}} + ATA/Token ELFs)",
    ))
}

fn committed_cpi_escrow_manifest_bytes() -> Vec<u8> {
    let path = repo_manifest_dir().join("escrow/manifest.json");
    fs::read(&path).unwrap_or_else(|e| panic!("read committed escrow manifest: {e}"))
}

/// Exact-byte join staged ↔ committed manifest, then pin-check one stem artifact
/// (`.s` / `.so`) including ASCII size/sha256 sidecars.
fn read_bound_artifact(
    suffix: &str,
    expected_sha: &str,
    expected_size: u64,
    label: &str,
) -> Vec<u8> {
    let out = cpi_escrow_out_dir();
    let committed = committed_cpi_escrow_manifest_bytes();
    let staged = stable_read(&out.join("manifest.json"), "output manifest");
    assert_eq!(
        staged, committed,
        "output manifest must equal committed bytes"
    );
    let path = out.join(format!("{CPI_ESCROW_STEM}.{suffix}"));
    let size_bytes = stable_read(
        &out.join(format!("{CPI_ESCROW_STEM}.{suffix}.size")),
        "size sidecar",
    );
    let hash_bytes = stable_read(
        &out.join(format!("{CPI_ESCROW_STEM}.{suffix}.sha256")),
        "hash sidecar",
    );
    let sidecar_size: u64 = std::str::from_utf8(&size_bytes)
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    let sidecar_hash = std::str::from_utf8(&hash_bytes).unwrap().trim();
    assert_eq!(sidecar_size, expected_size, "{label} sidecar size");
    assert_eq!(sidecar_hash, expected_sha, "{label} sidecar hash");
    let bytes = stable_read(&path, label);
    assert_eq!(bytes.len() as u64, expected_size, "{label} size");
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        expected_sha,
        "{label} sha"
    );
    bytes
}

fn read_cpi_escrow_assembly() -> Vec<u8> {
    let bytes = read_bound_artifact(
        "s",
        CPI_ESCROW_ASSEMBLY_SHA256,
        CPI_ESCROW_ASSEMBLY_SIZE,
        "assembly",
    );
    assert!(
        bytes
            .windows(b"TEST-PREACTIVATION ONLY".len())
            .any(|w| w == b"TEST-PREACTIVATION ONLY"),
        "assembly missing TEST-PREACTIVATION ONLY banner"
    );
    for req in [
        b"sol_invoke_signed_c" as &[u8],
        b"sol_try_find_program_address",
        b"sol_set_return_data",
    ] {
        assert!(
            bytes.windows(req.len()).any(|w| w == req),
            "assembly missing {}",
            String::from_utf8_lossy(req)
        );
    }
    // No harness/stub residue.
    for banned in [b"0xec01" as &[u8], b"ACC0_"] {
        assert!(
            !bytes.windows(banned.len()).any(|w| w == banned),
            "assembly contains banned stub residue {}",
            String::from_utf8_lossy(banned)
        );
    }
    bytes
}

fn read_cpi_escrow_caller_elf() -> Vec<u8> {
    let bytes = read_bound_artifact(
        "so",
        CPI_ESCROW_ELF_SHA256,
        CPI_ESCROW_ELF_SIZE,
        "caller ELF",
    );
    assert!(bytes.starts_with(b"\x7fELF"));
    bytes
}

fn read_vendored_ata_elf() -> Vec<u8> {
    let out = cpi_escrow_out_dir();
    let staged = stable_read(&out.join("ata_classic_v1.so"), "staged ATA ELF");
    let committed = stable_read(
        &repo_manifest_dir().join("ata/ata_classic_v1.so"),
        "committed ATA ELF",
    );
    assert_eq!(
        staged, committed,
        "staged ATA ELF must equal committed bytes"
    );
    assert_eq!(staged.len() as u64, ATA_CLASSIC_ELF_SIZE, "ATA ELF size");
    assert_eq!(
        hex::encode(Sha256::digest(&staged)),
        ATA_CLASSIC_ELF_SHA256,
        "ATA ELF sha"
    );
    assert!(staged.starts_with(b"\x7fELF"));
    staged
}

fn read_vendored_token_elf() -> Vec<u8> {
    let out = cpi_escrow_out_dir();
    let staged = stable_read(&out.join("token_classic_v1.so"), "staged Token ELF");
    let committed = stable_read(
        &repo_manifest_dir().join("token/token_classic_v1.so"),
        "committed Token ELF",
    );
    assert_eq!(
        staged, committed,
        "staged Token ELF must equal committed bytes"
    );
    assert_eq!(
        staged.len() as u64,
        TOKEN_CLASSIC_ELF_SIZE,
        "Token ELF size"
    );
    assert_eq!(
        hex::encode(Sha256::digest(&staged)),
        TOKEN_CLASSIC_ELF_SHA256,
        "Token ELF sha"
    );
    assert!(staged.starts_with(b"\x7fELF"));
    staged
}

fn cpi_escrow_program_id() -> Pubkey {
    Pubkey::new_from_array(CPI_ESCROW_PROGRAM_ID_BYTES)
}
fn ata_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(ATA_CLASSIC_PROGRAM_ID_BYTES)
}
fn token_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_CLASSIC_PROGRAM_ID_BYTES)
}
fn token_2022_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_2022_PROGRAM_ID_BYTES)
}
fn loader_v3_owner() -> Pubkey {
    Pubkey::new_from_array(LOADER_V3_OWNER_BYTES)
}

/// Single Mollusk instance: manifest-bound caller + staged ATA/Token; System native.
fn make_cpi_escrow_mollusk() -> (Mollusk, Pubkey, Pubkey, Pubkey) {
    let program_id = cpi_escrow_program_id();
    let ata_id = ata_classic_program_id();
    let token_id = token_classic_program_id();
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_cpi_escrow_caller_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &ata_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_ata_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &token_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_token_elf(),
    );
    (mollusk, program_id, ata_id, token_id)
}

// ---------------------------------------------------------------------------
// Packing / PDA / ix-data helpers
// ---------------------------------------------------------------------------

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn coption_pubkey_none() -> [u8; 36] {
    [0u8; 36]
}

fn coption_pubkey_some(key: &Pubkey) -> [u8; 36] {
    let mut out = [0u8; 36];
    out[0..4].copy_from_slice(&1u32.to_le_bytes());
    out[4..36].copy_from_slice(key.as_ref());
    out
}

fn pack_classic_mint(
    mint_authority: &Pubkey,
    supply: u64,
    decimals: u8,
    is_initialized: u8,
) -> Vec<u8> {
    let mut data = vec![0u8; TOKEN_MINT_DATA_BYTES];
    data[0..36].copy_from_slice(&coption_pubkey_some(mint_authority));
    data[36..44].copy_from_slice(&supply.to_le_bytes());
    data[44] = decimals;
    data[45] = is_initialized;
    data[46..82].copy_from_slice(&coption_pubkey_none());
    data
}

fn pack_classic_token_account(
    mint: &Pubkey,
    owner: &Pubkey,
    amount: u64,
    state: u8,
    delegate: Option<&Pubkey>,
) -> Vec<u8> {
    let mut data = vec![0u8; TOKEN_ACCOUNT_DATA_BYTES];
    data[0..32].copy_from_slice(mint.as_ref());
    data[32..64].copy_from_slice(owner.as_ref());
    data[64..72].copy_from_slice(&amount.to_le_bytes());
    match delegate {
        None => data[72..108].copy_from_slice(&coption_pubkey_none()),
        Some(d) => data[72..108].copy_from_slice(&coption_pubkey_some(d)),
    }
    data[108] = state;
    data
}

fn token_account_amount(data: &[u8]) -> u64 {
    assert_eq!(data.len(), TOKEN_ACCOUNT_DATA_BYTES);
    u64::from_le_bytes(data[64..72].try_into().unwrap())
}

fn escrow_fields() -> [StateField; 1] {
    single_field("value")
}

fn escrow_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&escrow_fields(), initialized, &[value])
}

fn cpi_escrow_init_ix_data(handler_id: u64, initial: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(16);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&initial.to_le_bytes());
    data
}

fn cpi_escrow_simple_ix_data(handler_id: u64) -> Vec<u8> {
    handler_id.to_le_bytes().to_vec()
}

fn cpi_escrow_initialize_ix_data(
    handler_id: u64,
    seed_tag: u64,
    bump: u8,
    pda_lamports: u64,
    pda_space: u64,
) -> Vec<u8> {
    let mut data = Vec::with_capacity(CPI_ESCROW_INITIALIZE_IX_LEN);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&seed_tag.to_le_bytes());
    data.push(bump);
    data.extend_from_slice(&pda_lamports.to_le_bytes());
    data.extend_from_slice(&pda_space.to_le_bytes());
    debug_assert_eq!(data.len(), CPI_ESCROW_INITIALIZE_IX_LEN);
    data
}

fn cpi_escrow_deposit_ix_data(handler_id: u64, amount: u64, decimals: u8) -> Vec<u8> {
    let mut data = Vec::with_capacity(CPI_ESCROW_DEPOSIT_IX_LEN);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&amount.to_le_bytes());
    data.push(decimals);
    debug_assert_eq!(data.len(), CPI_ESCROW_DEPOSIT_IX_LEN);
    data
}

fn cpi_escrow_release_ix_data(
    handler_id: u64,
    seed_tag: u64,
    bump: u8,
    amount: u64,
    decimals: u8,
) -> Vec<u8> {
    let mut data = Vec::with_capacity(CPI_ESCROW_RELEASE_IX_LEN);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&seed_tag.to_le_bytes());
    data.push(bump);
    data.extend_from_slice(&amount.to_le_bytes());
    data.push(decimals);
    debug_assert_eq!(data.len(), CPI_ESCROW_RELEASE_IX_LEN);
    data
}

const PDA_MARKER: &[u8] = b"ProgramDerivedAddress";

/// SDK-independent Solana PDA candidate oracle: SHA-256 + Ed25519 compressed
/// point rejection. Does not call `Pubkey::{create,find}_program_address`.
fn independent_create_program_address(seeds: &[&[u8]], program_id: &Pubkey) -> Option<Pubkey> {
    assert!(seeds.len() <= 16);
    assert!(seeds.iter().all(|s| s.len() <= 32));
    let mut hasher = Sha256::new();
    for seed in seeds {
        hasher.update(seed);
    }
    hasher.update(program_id.as_ref());
    hasher.update(PDA_MARKER);
    let hash: [u8; 32] = hasher.finalize().into();
    if CompressedEdwardsY(hash).decompress().is_some() {
        None
    } else {
        Some(Pubkey::new_from_array(hash))
    }
}

fn independent_find_pda_current_program_tagged_v1(
    program_id: &Pubkey,
    seed_authority: &Pubkey,
    seed_tag: u64,
) -> (Pubkey, u8) {
    let tag_le = seed_tag.to_le_bytes();
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[
            HARNESS_PDA_SEED0,
            seed_authority.as_ref(),
            &tag_le,
            &bump_slice,
        ];
        if let Some(addr) = independent_create_program_address(seeds, program_id) {
            return (addr, bump);
        }
    }
    panic!("no canonical authority PDA bump in 255..1");
}

fn find_ata_classic_v1(wallet: &Pubkey, mint: &Pubkey) -> (Pubkey, u8) {
    let token = token_classic_program_id();
    let ata_program = ata_classic_program_id();
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[wallet.as_ref(), token.as_ref(), mint.as_ref(), &bump_slice];
        if let Some(addr) = independent_create_program_address(seeds, &ata_program) {
            return (addr, bump);
        }
    }
    panic!("no canonical ATA bump in 255..1");
}

fn find_ata_sdk(wallet: &Pubkey, mint: &Pubkey) -> (Pubkey, u8) {
    let token = token_classic_program_id();
    let ata_program = ata_classic_program_id();
    Pubkey::find_program_address(
        &[wallet.as_ref(), token.as_ref(), mint.as_ref()],
        &ata_program,
    )
}

fn find_pda_sdk(program_id: &Pubkey, seed_authority: &Pubkey, seed_tag: u64) -> (Pubkey, u8) {
    let tag_le = seed_tag.to_le_bytes();
    Pubkey::find_program_address(
        &[HARNESS_PDA_SEED0, seed_authority.as_ref(), &tag_le],
        program_id,
    )
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
        if let Some(addr) = independent_create_program_address(seeds, program_id) {
            return (addr, bump);
        }
    }
    panic!("no noncanonical bump below canonical");
}

fn ata_program_account() -> Account {
    create_program_account_loader_v3(&ata_classic_program_id())
}

fn token_program_account() -> Account {
    create_program_account_loader_v3(&token_classic_program_id())
}

fn account_by_key<'a>(accounts: &'a [(Pubkey, Account)], key: &Pubkey) -> &'a Account {
    accounts
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, a)| a)
        .expect("account key")
}

fn assert_custom_failure_snapshot(
    mollusk: &Mollusk,
    ix: &Instruction,
    accounts: &[(Pubkey, Account)],
    code: u32,
) {
    assert_failure_preserves_exact_accounts(
        mollusk,
        ix,
        accounts,
        Check::err(ProgramError::Custom(code)),
    );
}

/// Overlay world for multi-step single-state chaining: every returned account
/// pair is upserted; the next handler pulls exact role-order accounts from it.
fn world_upsert(world: &mut BTreeMap<Pubkey, Account>, pairs: &[(Pubkey, Account)]) {
    for (key, account) in pairs {
        world.insert(*key, account.clone());
    }
}

fn world_require(world: &BTreeMap<Pubkey, Account>, key: &Pubkey, label: &str) -> Account {
    world
        .get(key)
        .unwrap_or_else(|| panic!("world missing {label}: {key}"))
        .clone()
}

fn accounts_from_world(
    world: &BTreeMap<Pubkey, Account>,
    keys: &[Pubkey],
) -> Vec<(Pubkey, Account)> {
    keys.iter()
        .map(|k| (*k, world_require(world, k, "role key")))
        .collect()
}

fn state_value_u64(data: &[u8]) -> u64 {
    // layout marker (8) + value u64 LE at STATE_HEADER_BYTES.
    assert!(data.len() >= STATE_HEADER_BYTES + 8);
    u64::from_le_bytes(
        data[STATE_HEADER_BYTES..STATE_HEADER_BYTES + 8]
            .try_into()
            .unwrap(),
    )
}

// ---------------------------------------------------------------------------
// Cases
// ---------------------------------------------------------------------------

/// initializeVault outer roles (9).
#[derive(Clone)]
struct InitializeVaultCase {
    state_key: Pubkey,
    payer_key: Pubkey,
    authority_pda: Pubkey,
    seed_authority: Pubkey,
    seed_tag: u64,
    bump: u8,
    vault_ata: Pubkey,
    mint_key: Pubkey,
    ata_program_key: Pubkey,
    system_program_key: Pubkey,
    token_program_key: Pubkey,
    mint_authority: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    payer_lamports: u64,
    pda_lamports: u64,
    pda_space: u64,
    decimals: u8,
}

impl InitializeVaultCase {
    fn fresh(
        program_id: Pubkey,
        state_value: u64,
        seed_tag: u64,
        payer_lamports: u64,
        pda_lamports: u64,
        pda_space: u64,
        decimals: u8,
    ) -> Self {
        let state_key = fixed_key(0x20);
        let payer_key = fixed_key(0x21);
        let seed_authority = fixed_key(0x22);
        let mint_key = fixed_key(0x23);
        let mint_authority = fixed_key(0x70);
        let (authority_pda, bump) =
            independent_find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
        let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
        let ata_program_key = ata_classic_program_id();
        let token_program_key = token_classic_program_id();
        let (system_program_key, system_program) = system_program_keyed_account();

        let state = state_account(&program_id, escrow_state(true, state_value));
        let payer = Account::new(payer_lamports, 0, &Pubkey::default());
        let pda_account = unused_system_create_target_account();
        let authority_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let vault_ata_account = unused_system_create_target_account();
        let mint = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(&mint_authority, 1_000_000, decimals, 1),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let ata_program = ata_program_account();
        let token_program = token_program_account();

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(payer_key, true),
            AccountMeta::new(authority_pda, false),
            AccountMeta::new_readonly(seed_authority, false),
            AccountMeta::new(vault_ata, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new_readonly(system_program_key, false),
            AccountMeta::new_readonly(ata_program_key, false),
            AccountMeta::new_readonly(token_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (payer_key, payer),
            (authority_pda, pda_account),
            (seed_authority, authority_account),
            (vault_ata, vault_ata_account),
            (mint_key, mint),
            (system_program_key, system_program),
            (ata_program_key, ata_program),
            (token_program_key, token_program),
        ];
        assert_eq!(metas.len(), CPI_ESCROW_INITIALIZE_ROLES);
        assert_eq!(accounts.len(), CPI_ESCROW_INITIALIZE_ROLES);
        Self {
            state_key,
            payer_key,
            authority_pda,
            seed_authority,
            seed_tag,
            bump,
            vault_ata,
            mint_key,
            ata_program_key,
            system_program_key,
            token_program_key,
            mint_authority,
            metas,
            accounts,
            payer_lamports,
            pda_lamports,
            pda_space,
            decimals,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_initialize_ix_data(
                handler_id,
                self.seed_tag,
                self.bump,
                self.pda_lamports,
                self.pda_space,
            ),
            self.metas.clone(),
        )
    }
}

/// deposit outer roles (6).
#[derive(Clone)]
struct DepositCase {
    source_key: Pubkey,
    mint_key: Pubkey,
    vault_ata: Pubkey,
    user_authority: Pubkey,
    vault_owner: Pubkey,
    token_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    source_amount: u64,
    vault_amount: u64,
    decimals: u8,
}

impl DepositCase {
    fn new(
        program_id: Pubkey,
        state_value: u64,
        source_amount: u64,
        vault_amount: u64,
        decimals: u8,
        authority_is_signer: bool,
        vault_ata: Pubkey,
        vault_owner: Pubkey,
        mint_key: Pubkey,
    ) -> Self {
        let state_key = fixed_key(0x40);
        let source_key = fixed_key(0x41);
        let user_authority = fixed_key(0x42);
        let token_program_key = token_classic_program_id();
        let mint_authority = fixed_key(0x71);

        let state = state_account(&program_id, escrow_state(true, state_value));
        let mint = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(
                &mint_authority,
                source_amount.saturating_add(vault_amount),
                decimals,
                1,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let source = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &user_authority,
                source_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let vault = Account {
            lamports: ATA_RENT_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &vault_owner,
                vault_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let authority = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let token_program = token_program_account();
        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(source_key, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new(vault_ata, false),
            AccountMeta::new_readonly(user_authority, authority_is_signer),
            AccountMeta::new_readonly(token_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (source_key, source),
            (mint_key, mint),
            (vault_ata, vault),
            (user_authority, authority),
            (token_program_key, token_program),
        ];
        assert_eq!(metas.len(), CPI_ESCROW_DEPOSIT_ROLES);
        Self {
            source_key,
            mint_key,
            vault_ata,
            user_authority,
            vault_owner,
            token_program_key,
            metas,
            accounts,
            source_amount,
            vault_amount,
            decimals,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, amount: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_deposit_ix_data(handler_id, amount, self.decimals),
            self.metas.clone(),
        )
    }
}

/// release / refund outer roles (7). Distinct destination keys for the two paths.
#[derive(Clone)]
struct ReleaseRefundCase {
    vault_ata: Pubkey,
    mint_key: Pubkey,
    destination_key: Pubkey,
    authority_pda: Pubkey,
    seed_authority: Pubkey,
    seed_tag: u64,
    bump: u8,
    dest_owner: Pubkey,
    token_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    vault_amount: u64,
    destination_amount: u64,
    decimals: u8,
}

impl ReleaseRefundCase {
    fn new(
        program_id: Pubkey,
        state_value: u64,
        seed_tag: u64,
        vault_amount: u64,
        destination_amount: u64,
        decimals: u8,
        seed_authority_signer: bool,
        destination_key: Pubkey,
        dest_owner: Pubkey,
    ) -> Self {
        let state_key = fixed_key(0x50);
        let mint_key = fixed_key(0x51);
        let seed_authority = fixed_key(0x52);
        let (authority_pda, bump) =
            independent_find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
        let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
        let token_program_key = token_classic_program_id();
        let mint_authority = fixed_key(0x72);

        let state = state_account(&program_id, escrow_state(true, state_value));
        let mint = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(
                &mint_authority,
                vault_amount.saturating_add(destination_amount),
                decimals,
                1,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let vault = Account {
            lamports: ATA_RENT_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &authority_pda,
                vault_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let destination = Account {
            lamports: ATA_RENT_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &dest_owner,
                destination_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let pda_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let authority_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let token_program = token_program_account();
        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(vault_ata, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new(destination_key, false),
            AccountMeta::new_readonly(authority_pda, false),
            AccountMeta::new_readonly(seed_authority, seed_authority_signer),
            AccountMeta::new_readonly(token_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (vault_ata, vault),
            (mint_key, mint),
            (destination_key, destination),
            (authority_pda, pda_account),
            (seed_authority, authority_account),
            (token_program_key, token_program),
        ];
        assert_eq!(metas.len(), CPI_ESCROW_RELEASE_ROLES);
        Self {
            vault_ata,
            mint_key,
            destination_key,
            authority_pda,
            seed_authority,
            seed_tag,
            bump,
            dest_owner,
            token_program_key,
            metas,
            accounts,
            vault_amount,
            destination_amount,
            decimals,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, amount: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_release_ix_data(
                handler_id,
                self.seed_tag,
                self.bump,
                amount,
                self.decimals,
            ),
            self.metas.clone(),
        )
    }
}

// ---------------------------------------------------------------------------
// Pure / fixture-facing tests (no caller ELF)
// ---------------------------------------------------------------------------

#[test]
fn handler_ids_are_dense_source_order() {
    assert_eq!(CPI_ESCROW_INIT_HANDLER_ID, 0);
    assert_eq!(CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID, 1);
    assert_eq!(CPI_ESCROW_DEPOSIT_HANDLER_ID, 2);
    assert_eq!(CPI_ESCROW_RELEASE_HANDLER_ID, 3);
    assert_eq!(CPI_ESCROW_REFUND_HANDLER_ID, 4);
    assert_eq!(CPI_ESCROW_INITIALIZE_THEN_OVERFLOW_HANDLER_ID, 5);
    assert_eq!(CPI_ESCROW_DEPOSIT_THEN_OVERFLOW_HANDLER_ID, 6);
    assert_eq!(CPI_ESCROW_RELEASE_THEN_OVERFLOW_HANDLER_ID, 7);
    assert_eq!(CPI_ESCROW_REFUND_THEN_OVERFLOW_HANDLER_ID, 8);
    assert_eq!(CPI_ESCROW_INSPECT_HANDLER_ID, 9);
}

#[test]
fn fixture_source_identity_and_extension_digest() {
    let path = repo_root().join("runtime-tests/solana/fixtures/EscrowCpi.lean");
    let bytes = fs::read(&path).expect("read EscrowCpi.lean");
    assert_eq!(bytes.len() as u64, CPI_ESCROW_FIXTURE_SIZE);
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        CPI_ESCROW_FIXTURE_SHA256
    );
    let text = String::from_utf8_lossy(&bytes);
    assert!(text.contains("program EscrowCpi where"));
    assert!(text.contains(EXTENSION_DIGEST));
    assert!(text.contains("initializeVault"));
    assert!(text.contains("deposit"));
    assert!(text.contains("release"));
    assert!(text.contains("refund"));
    assert!(text.contains("initializeThenOverflow"));
    assert!(text.contains("depositThenOverflow"));
    assert!(text.contains("releaseThenOverflow"));
    assert!(text.contains("refundThenOverflow"));
    assert!(text.contains("inspect"));
    assert!(text.contains("solana.system.createPdaAccount"));
    assert!(text.contains("solana.ata.createIdempotent"));
    assert!(text.contains("solana.token.transferChecked"));
    assert!(text.contains("solana.token.transferCheckedPda"));
    assert!(text.contains("test-preactivation") || text.contains("testPreactivation"));
    assert!(
        text.contains("Not proof-forge.output.v1") || text.contains("not proof-forge.output.v1")
    );
}

#[test]
fn init_and_inspect_ix_layouts() {
    let init = cpi_escrow_init_ix_data(CPI_ESCROW_INIT_HANDLER_ID, 99);
    assert_eq!(init.len(), 16);
    assert_eq!(&init[0..8], &CPI_ESCROW_INIT_HANDLER_ID.to_le_bytes());
    assert_eq!(&init[8..16], &99u64.to_le_bytes());
    let inspect = cpi_escrow_simple_ix_data(CPI_ESCROW_INSPECT_HANDLER_ID);
    assert_eq!(inspect.len(), 8);
    assert_eq!(&inspect[0..8], &CPI_ESCROW_INSPECT_HANDLER_ID.to_le_bytes());
}

#[test]
fn initialize_ix_layout_is_exactly_33_bytes() {
    let data =
        cpi_escrow_initialize_ix_data(CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID, 7, 252, 1_000_000, 0);
    assert_eq!(data.len(), CPI_ESCROW_INITIALIZE_IX_LEN);
    assert_eq!(
        &data[0..8],
        &CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID.to_le_bytes()
    );
    assert_eq!(&data[8..16], &7u64.to_le_bytes());
    assert_eq!(data[16], 252);
    assert_eq!(&data[17..25], &1_000_000u64.to_le_bytes());
    assert_eq!(&data[25..33], &0u64.to_le_bytes());
}

#[test]
fn deposit_ix_layout_is_exactly_17_bytes() {
    let data = cpi_escrow_deposit_ix_data(CPI_ESCROW_DEPOSIT_HANDLER_ID, 42, 6);
    assert_eq!(data.len(), CPI_ESCROW_DEPOSIT_IX_LEN);
    assert_eq!(&data[0..8], &CPI_ESCROW_DEPOSIT_HANDLER_ID.to_le_bytes());
    assert_eq!(&data[8..16], &42u64.to_le_bytes());
    assert_eq!(data[16], 6);
    assert_eq!(TOKEN_TRANSFER_CHECKED_TAG, 12);
}

#[test]
fn release_refund_ix_layout_is_exactly_26_bytes() {
    let release = cpi_escrow_release_ix_data(CPI_ESCROW_RELEASE_HANDLER_ID, 9, 254, 100, 6);
    let refund = cpi_escrow_release_ix_data(CPI_ESCROW_REFUND_HANDLER_ID, 9, 254, 100, 6);
    assert_eq!(release.len(), CPI_ESCROW_RELEASE_IX_LEN);
    assert_eq!(refund.len(), CPI_ESCROW_RELEASE_IX_LEN);
    assert_eq!(&release[0..8], &CPI_ESCROW_RELEASE_HANDLER_ID.to_le_bytes());
    assert_eq!(&refund[0..8], &CPI_ESCROW_REFUND_HANDLER_ID.to_le_bytes());
    assert_eq!(&release[8..16], &9u64.to_le_bytes());
    assert_eq!(release[16], 254);
    assert_eq!(&release[17..25], &100u64.to_le_bytes());
    assert_eq!(release[25], 6);
    // Distinct handler IDs fix the two business paths; body layout is shared.
    assert_ne!(release[0..8], refund[0..8]);
}

#[test]
fn high_byte_scalar_layout_coverage() {
    let seed_tag = 0x8000_0000_0000_002Au64;
    let lamports = 0x8000_0000_0000_0005u64;
    let space = 0x8000_0000_0000_0040u64;
    let amount = 0x8000_0000_0000_0011u64;
    let init = cpi_escrow_initialize_ix_data(1, seed_tag, 1, lamports, space);
    assert_ne!(init[15], 0, "seedTag high-byte");
    assert_ne!(init[24], 0, "pdaLamports high-byte");
    assert_ne!(init[32], 0, "pdaSpace high-byte");
    let dep = cpi_escrow_deposit_ix_data(2, amount, 9);
    assert_ne!(dep[15], 0, "deposit amount high-byte");
    let rel = cpi_escrow_release_ix_data(3, seed_tag, 1, amount, 9);
    assert_ne!(rel[15], 0, "release seedTag high-byte");
    assert_ne!(rel[24], 0, "release amount high-byte");
}

#[test]
fn case_role_counts_and_flags() {
    let program_id = cpi_escrow_program_id();
    let init = InitializeVaultCase::fresh(
        program_id,
        0,
        7,
        BASE_LAMPORTS,
        PDA_SPACE0_RENT_LAMPORTS,
        0,
        6,
    );
    assert_eq!(init.metas.len(), CPI_ESCROW_INITIALIZE_ROLES);
    assert!(init.metas[1].is_signer);
    assert!(init.metas[1].is_writable);
    assert!(!init.metas[2].is_signer);
    assert!(init.metas[2].is_writable);
    assert!(!init.metas[3].is_signer);
    assert!(!init.metas[3].is_writable);
    assert!(init.metas[4].is_writable);
    assert!(!init.metas[5].is_writable);
    assert!(!init.metas[6].is_writable);
    assert!(!init.metas[7].is_writable);
    assert!(!init.metas[8].is_writable);
    assert_eq!(init.decimals, 6);
    assert_eq!(init.mint_authority, fixed_key(0x70));

    let dep = DepositCase::new(
        program_id,
        0,
        100,
        0,
        6,
        true,
        fixed_key(0xaa),
        fixed_key(0xbb),
        fixed_key(0xcc),
    );
    assert_eq!(dep.metas.len(), CPI_ESCROW_DEPOSIT_ROLES);
    assert!(dep.metas[4].is_signer);
    assert!(!dep.metas[4].is_writable);
    assert_eq!(dep.source_amount, 100);
    assert_eq!(dep.vault_amount, 0);

    let rel = ReleaseRefundCase::new(
        program_id,
        0,
        7,
        50,
        0,
        6,
        true,
        fixed_key(0x60),
        fixed_key(0x61),
    );
    assert_eq!(rel.metas.len(), CPI_ESCROW_RELEASE_ROLES);
    assert!(!rel.metas[4].is_signer);
    assert!(rel.metas[5].is_signer);
    assert!(!rel.metas[5].is_writable);
    assert_eq!(rel.token_program_key, token_classic_program_id());
    assert_eq!(CPI_ESCROW_INIT_ROLES, 1);
}

#[test]
fn independent_authority_pda_oracle_cross_checks_sdk() {
    assert_eq!(hex::encode(PDA_SEED0_UTF8.as_bytes()), PDA_SEED0_HEX);
    let program_id = cpi_escrow_program_id();
    let seed_authority = fixed_key(0x31);
    let seed_tag = 42u64;
    let (ind, ind_bump) =
        independent_find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
    let (sdk, sdk_bump) = find_pda_sdk(&program_id, &seed_authority, seed_tag);
    let (common, common_bump) =
        find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
    assert_eq!(ind, sdk);
    assert_eq!(ind_bump, sdk_bump);
    assert_eq!(ind, common);
    assert_eq!(ind_bump, common_bump);
    assert_ne!(ind_bump, 0, "canonical bump rejects 0");
    // Bump 0 is never searched by the independent oracle.
    let tag_le = seed_tag.to_le_bytes();
    let zero = independent_create_program_address(
        &[HARNESS_PDA_SEED0, seed_authority.as_ref(), &tag_le, &[0u8]],
        &program_id,
    );
    // Whether or not off-curve at bump 0, canonical search excludes it.
    let _ = zero;
    assert!(ind_bump >= 1);
}

#[test]
fn independent_vault_ata_oracle_cross_checks_sdk() {
    let program_id = cpi_escrow_program_id();
    let seed_authority = fixed_key(0x31);
    let mint = fixed_key(0x41);
    let (authority_pda, _) =
        independent_find_pda_current_program_tagged_v1(&program_id, &seed_authority, 7);
    let (ind, ind_bump) = find_ata_classic_v1(&authority_pda, &mint);
    let (sdk, sdk_bump) = find_ata_sdk(&authority_pda, &mint);
    assert_eq!(ind, sdk);
    assert_eq!(ind_bump, sdk_bump);
    assert_ne!(ind_bump, 0);
    // Recipe: wallet=authorityPda, classic Token, mint under classic ATA program.
    let token = token_classic_program_id();
    let ata = ata_classic_program_id();
    let bump_slice = [ind_bump];
    let rebuilt = independent_create_program_address(
        &[
            authority_pda.as_ref(),
            token.as_ref(),
            mint.as_ref(),
            &bump_slice,
        ],
        &ata,
    )
    .expect("canonical ATA candidate");
    assert_eq!(rebuilt, ind);
}

#[test]
fn program_id_pin_is_all_0x59() {
    assert_eq!(CPI_ESCROW_PROGRAM_ID_BYTES, [0x59; 32]);
    assert_eq!(
        cpi_escrow_program_id().to_bytes(),
        CPI_ESCROW_PROGRAM_ID_BYTES
    );
}

#[test]
fn vendored_ata_and_token_elf_pins_are_exact() {
    let _ = read_vendored_ata_elf();
    let _ = read_vendored_token_elf();
}

// ---------------------------------------------------------------------------
// Generated-ELF Mollusk matrix (requires caller ELF env)
// ---------------------------------------------------------------------------

#[test]
fn generated_caller_elf_is_loadable_preactivation() {
    let assembly = read_cpi_escrow_assembly();
    let text = std::str::from_utf8(&assembly).expect("assembly UTF-8");
    assert!(text.contains("TEST-PREACTIVATION ONLY"));
    assert!(text.contains("sol_invoke_signed_c"));
    assert!(text.contains("sol_try_find_program_address"));
    assert!(text.contains("sol_set_return_data"));
    assert!(!text.contains("0xec01"));
    assert!(!text.contains("ACC0_"));
    let elf = read_cpi_escrow_caller_elf();
    assert!(elf.starts_with(b"\x7fELF"));
    let (mollusk, program_id, ata_id, token_id) = make_cpi_escrow_mollusk();
    assert_eq!(program_id, cpi_escrow_program_id());
    assert_eq!(ata_id, ata_classic_program_id());
    assert_eq!(token_id, token_classic_program_id());
    // Smoke: inspect on initialized state.
    let state_key = fixed_key(0xa0);
    let state = state_account(&program_id, escrow_state(true, 41));
    mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_simple_ix_data(CPI_ESCROW_INSPECT_HANDLER_ID),
            vec![AccountMeta::new_readonly(state_key, false)],
        ),
        &[(state_key, state)],
        &[Check::success(), Check::return_data(&41u64.to_le_bytes())],
    );
}

#[test]
fn initialize_vault_fresh_success_exact_layout_and_state_order() {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let seed_tag = 7u64;
    let pda_space = 0u64;
    let pda_lamports = PDA_SPACE0_RENT_LAMPORTS;
    // Fund payer for PDA rent + ATA rent.
    let payer_lamports = BASE_LAMPORTS;
    let case = InitializeVaultCase::fresh(
        program_id,
        10,
        seed_tag,
        payer_lamports,
        pda_lamports,
        pda_space,
        6,
    );
    assert_ne!(case.bump, 0);
    let ix = case.instruction(program_id, CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );

    let post_state = account_by_key(&result.resulting_accounts, &case.state_key);
    assert_eq!(post_state.data, escrow_state(true, 13));
    assert_eq!(post_state.owner, program_id);

    let post_pda = account_by_key(&result.resulting_accounts, &case.authority_pda);
    assert_eq!(post_pda.owner, program_id, "PDA owner = current caller");
    assert_eq!(post_pda.data.len() as u64, pda_space);
    assert_eq!(post_pda.lamports, pda_lamports);
    assert!(!post_pda.executable);

    let post_ata = account_by_key(&result.resulting_accounts, &case.vault_ata);
    assert_eq!(post_ata.owner, case.token_program_key);
    assert_eq!(post_ata.data.len(), TOKEN_ACCOUNT_DATA_BYTES);
    assert_eq!(post_ata.lamports, ATA_RENT_LAMPORTS);
    assert_eq!(&post_ata.data[0..32], case.mint_key.as_ref());
    assert_eq!(&post_ata.data[32..64], case.authority_pda.as_ref());
    assert_eq!(token_account_amount(&post_ata.data), 0);
    assert_eq!(post_ata.data[108], TOKEN_ACCOUNT_STATE_INITIALIZED);

    let post_payer = account_by_key(&result.resulting_accounts, &case.payer_key);
    let expected_payer = payer_lamports
        .checked_sub(pda_lamports)
        .unwrap()
        .checked_sub(ATA_RENT_LAMPORTS)
        .unwrap();
    assert_eq!(post_payer.lamports, expected_payer);
}

#[test]
fn sequential_deposit_release_refund_amount_conservation() {
    // Not multi-top-level transaction atomicity: each outer instruction is an
    // independent Mollusk invocation. One shared caller state key + BTreeMap
    // world overlay carries exact resulting_accounts into the next handler.
    let (mollusk, program_id, _, token_id) = make_cpi_escrow_mollusk();
    let seed_tag = 11u64;
    let decimals = 6u8;
    let pda_lamports = PDA_SPACE0_RENT_LAMPORTS;
    let pda_space = 0u64;
    let deposit_amount = 100u64;
    let release_amount = 40u64;
    let refund_amount = 60u64;

    // 1) initialize vault (state value 0 → 3)
    let init_case = InitializeVaultCase::fresh(
        program_id,
        0,
        seed_tag,
        BASE_LAMPORTS,
        pda_lamports,
        pda_space,
        decimals,
    );
    let state_key = init_case.state_key;
    let authority_pda = init_case.authority_pda;
    let vault_ata = init_case.vault_ata;
    let mint_key = init_case.mint_key;
    let seed_authority = init_case.seed_authority;
    let bump = init_case.bump;

    let init_result = mollusk.process_and_validate_instruction(
        &init_case.instruction(program_id, CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID),
        &init_case.accounts,
        &[Check::success(), Check::return_data(&3u64.to_le_bytes())],
    );
    let mut world: BTreeMap<Pubkey, Account> = BTreeMap::new();
    world_upsert(&mut world, &init_result.resulting_accounts);
    assert_eq!(
        state_value_u64(&world_require(&world, &state_key, "state").data),
        3
    );

    // 2) deposit: inject user source + authority; reuse state/mint/vault/token from world.
    let source_key = fixed_key(0x41);
    let user_authority = fixed_key(0x42);
    world.insert(
        source_key,
        Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &user_authority,
                deposit_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_id,
            executable: false,
            rent_epoch: 0,
        },
    );
    world.insert(
        user_authority,
        Account::new(BASE_LAMPORTS, 0, &Pubkey::default()),
    );
    // Ensure token program role account is present for deposit/release/refund.
    world.entry(token_id).or_insert_with(token_program_account);

    let deposit_keys = [
        state_key,
        source_key,
        mint_key,
        vault_ata,
        user_authority,
        token_id,
    ];
    let deposit_metas = vec![
        AccountMeta::new(state_key, false),
        AccountMeta::new(source_key, false),
        AccountMeta::new_readonly(mint_key, false),
        AccountMeta::new(vault_ata, false),
        AccountMeta::new_readonly(user_authority, true),
        AccountMeta::new_readonly(token_id, false),
    ];
    let deposit_accounts = accounts_from_world(&world, &deposit_keys);
    let deposit_result = mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_deposit_ix_data(CPI_ESCROW_DEPOSIT_HANDLER_ID, deposit_amount, decimals),
            deposit_metas,
        ),
        &deposit_accounts,
        &[Check::success(), Check::return_data(&6u64.to_le_bytes())],
    );
    world_upsert(&mut world, &deposit_result.resulting_accounts);
    assert_eq!(
        state_value_u64(&world_require(&world, &state_key, "state").data),
        6
    );
    assert_eq!(
        token_account_amount(&world_require(&world, &source_key, "source").data),
        0
    );
    assert_eq!(
        token_account_amount(&world_require(&world, &vault_ata, "vault").data),
        deposit_amount
    );

    // 3) release 40 → distinct release destination (same state key).
    let release_dest = fixed_key(0x80);
    let release_owner = fixed_key(0x81);
    world.insert(
        release_dest,
        Account {
            lamports: ATA_RENT_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &release_owner,
                0,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_id,
            executable: false,
            rent_epoch: 0,
        },
    );
    let release_keys = [
        state_key,
        vault_ata,
        mint_key,
        release_dest,
        authority_pda,
        seed_authority,
        token_id,
    ];
    let release_metas = vec![
        AccountMeta::new(state_key, false),
        AccountMeta::new(vault_ata, false),
        AccountMeta::new_readonly(mint_key, false),
        AccountMeta::new(release_dest, false),
        AccountMeta::new_readonly(authority_pda, false),
        AccountMeta::new_readonly(seed_authority, true),
        AccountMeta::new_readonly(token_id, false),
    ];
    let release_accounts = accounts_from_world(&world, &release_keys);
    let release_result = mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_release_ix_data(
                CPI_ESCROW_RELEASE_HANDLER_ID,
                seed_tag,
                bump,
                release_amount,
                decimals,
            ),
            release_metas,
        ),
        &release_accounts,
        &[Check::success(), Check::return_data(&9u64.to_le_bytes())],
    );
    world_upsert(&mut world, &release_result.resulting_accounts);
    assert_eq!(
        state_value_u64(&world_require(&world, &state_key, "state").data),
        9
    );
    assert_eq!(
        token_account_amount(&world_require(&world, &vault_ata, "vault").data),
        deposit_amount - release_amount
    );
    assert_eq!(
        token_account_amount(&world_require(&world, &release_dest, "release dest").data),
        release_amount
    );

    // 4) refund remaining 60 → distinct refund destination (same state key).
    let refund_dest = fixed_key(0x90);
    let refund_owner = fixed_key(0x91);
    world.insert(
        refund_dest,
        Account {
            lamports: ATA_RENT_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &refund_owner,
                0,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_id,
            executable: false,
            rent_epoch: 0,
        },
    );
    let refund_keys = [
        state_key,
        vault_ata,
        mint_key,
        refund_dest,
        authority_pda,
        seed_authority,
        token_id,
    ];
    let refund_metas = vec![
        AccountMeta::new(state_key, false),
        AccountMeta::new(vault_ata, false),
        AccountMeta::new_readonly(mint_key, false),
        AccountMeta::new(refund_dest, false),
        AccountMeta::new_readonly(authority_pda, false),
        AccountMeta::new_readonly(seed_authority, true),
        AccountMeta::new_readonly(token_id, false),
    ];
    let refund_accounts = accounts_from_world(&world, &refund_keys);
    let refund_result = mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_release_ix_data(
                CPI_ESCROW_REFUND_HANDLER_ID,
                seed_tag,
                bump,
                refund_amount,
                decimals,
            ),
            refund_metas,
        ),
        &refund_accounts,
        &[Check::success(), Check::return_data(&12u64.to_le_bytes())],
    );
    world_upsert(&mut world, &refund_result.resulting_accounts);
    assert_eq!(
        state_value_u64(&world_require(&world, &state_key, "state").data),
        12
    );
    assert_eq!(
        token_account_amount(&world_require(&world, &vault_ata, "vault").data),
        0
    );
    assert_eq!(
        token_account_amount(&world_require(&world, &refund_dest, "refund dest").data),
        refund_amount
    );

    // Conservation from live token account bytes (not hardcoded arithmetic theater).
    let source_amt = token_account_amount(&world_require(&world, &source_key, "source").data);
    let vault_amt = token_account_amount(&world_require(&world, &vault_ata, "vault").data);
    let release_amt =
        token_account_amount(&world_require(&world, &release_dest, "release dest").data);
    let refund_amt = token_account_amount(&world_require(&world, &refund_dest, "refund dest").data);
    assert_eq!(
        source_amt + vault_amt + release_amt + refund_amt,
        deposit_amount,
        "token conservation broken: source={source_amt} vault={vault_amt} \
         release={release_amt} refund={refund_amt}"
    );
    assert_eq!(source_amt, 0);
    assert_eq!(vault_amt, 0);
    assert_eq!(release_amt, release_amount);
    assert_eq!(refund_amt, refund_amount);
}

#[test]
fn initialize_then_overflow_full_snapshot_rollback_with_inner_logs() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let case = InitializeVaultCase::fresh(
        program_id,
        10,
        7,
        BASE_LAMPORTS,
        PDA_SPACE0_RENT_LAMPORTS,
        0,
        6,
    );
    // Pre: PDA and ATA are fresh System absence (0 lamports / 0 data).
    assert_eq!(
        account_by_key(&case.accounts, &case.authority_pda).lamports,
        0
    );
    assert!(account_by_key(&case.accounts, &case.authority_pda)
        .data
        .is_empty());
    assert_eq!(account_by_key(&case.accounts, &case.vault_ata).lamports, 0);
    assert!(account_by_key(&case.accounts, &case.vault_ata)
        .data
        .is_empty());

    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_INITIALIZE_THEN_OVERFLOW_HANDLER_ID),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(ARITHMETIC_OVERFLOW)),
            Check::return_data(&[]),
        ],
    );

    // Ordered logs: System create + ATA CreateIdempotent complete before 0x1001.
    let logs = logger.borrow().get_recorded_content().to_vec();
    let ordered = [
        "Program 11111111111111111111111111111111 success",
        "Program log: CreateIdempotent",
        "Program ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL success",
    ];
    let mut cursor = 0usize;
    for needle in ordered {
        let relative = logs[cursor..]
            .iter()
            .position(|line| line.contains(needle))
            .unwrap_or_else(|| {
                panic!("missing ordered overflow-path log {needle:?}; logs={logs:?}")
            });
        cursor += relative + 1;
    }
}

#[test]
fn deposit_then_overflow_full_snapshot_rollback() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let program_id_copy = program_id;
    let seed_tag = 5u64;
    let (authority_pda, _) = independent_find_pda_current_program_tagged_v1(
        &program_id_copy,
        &fixed_key(0x22),
        seed_tag,
    );
    let mint_key = fixed_key(0x23);
    let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
    let case = DepositCase::new(
        program_id,
        10,
        1000,
        0,
        6,
        true,
        vault_ata,
        authority_pda,
        mint_key,
    );
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_DEPOSIT_THEN_OVERFLOW_HANDLER_ID, 25),
        &case.accounts,
        ARITHMETIC_OVERFLOW,
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert!(
        logs.iter()
            .any(|l| l.contains("Instruction: TransferChecked")
                || l.contains("TransferChecked")
                || l.contains("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")),
        "deposit overflow must complete Token CPI first; logs={logs:?}"
    );
}

#[test]
fn release_then_overflow_full_snapshot_rollback() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let case = ReleaseRefundCase::new(
        program_id,
        10,
        7,
        500,
        0,
        6,
        true,
        fixed_key(0x60),
        fixed_key(0x61),
    );
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_RELEASE_THEN_OVERFLOW_HANDLER_ID, 25),
        &case.accounts,
        ARITHMETIC_OVERFLOW,
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert!(
        logs.iter().any(|l| l.contains("TransferChecked")
            || l.contains("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")),
        "release overflow must complete Token CPI first; logs={logs:?}"
    );
}

#[test]
fn refund_then_overflow_full_snapshot_rollback() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    // Distinct destination from release path.
    let case = ReleaseRefundCase::new(
        program_id,
        10,
        7,
        500,
        0,
        6,
        true,
        fixed_key(0x90),
        fixed_key(0x91),
    );
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_REFUND_THEN_OVERFLOW_HANDLER_ID, 25),
        &case.accounts,
        ARITHMETIC_OVERFLOW,
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert!(
        logs.iter().any(|l| l.contains("TransferChecked")
            || l.contains("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")),
        "refund overflow must complete Token CPI first; logs={logs:?}"
    );
}

#[test]
fn underfunded_initialize_inner_failure_full_snapshot() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    // Payer cannot fund PDA rent (first System createPdaAccount transfer).
    let payer_lamports = 1_000u64;
    let need_lamports = PDA_SPACE0_RENT_LAMPORTS;
    let case = InitializeVaultCase::fresh(program_id, 10, 7, payer_lamports, need_lamports, 0, 6);
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(
                SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
            )),
            Check::return_data(&[]),
        ],
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    // Exact System create transfer failure (not mere program-id presence).
    let expected =
        format!("Transfer: insufficient lamports {payer_lamports}, need {need_lamports}");
    assert!(
        logs.iter().any(|line| line.contains(&expected)),
        "underfunded initialize must hit native System create transfer with exact \
         lamports message {expected:?}; logs={logs:?}"
    );
}

fn assert_token_transfer_checked_failure_logs(logs: &[String], label: &str) {
    let mut cursor = 0usize;
    for needle in [
        "Instruction: TransferChecked",
        "Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA failed",
    ] {
        let relative = logs[cursor..]
            .iter()
            .position(|line| line.contains(needle))
            .unwrap_or_else(|| {
                panic!("{label}: missing ordered Token CPI failure log {needle:?}; logs={logs:?}")
            });
        cursor += relative + 1;
    }
}

#[test]
fn insufficient_deposit_tokens_inner_failure_full_snapshot() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let (authority_pda, _) =
        independent_find_pda_current_program_tagged_v1(&program_id, &fixed_key(0x22), 5);
    let mint_key = fixed_key(0x23);
    let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
    let case = DepositCase::new(
        program_id,
        10,
        10,
        0,
        6,
        true,
        vault_ata,
        authority_pda,
        mint_key,
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_DEPOSIT_HANDLER_ID, 11),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(TOKEN_ERR_INSUFFICIENT_FUNDS)),
            Check::return_data(&[]),
        ],
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert_token_transfer_checked_failure_logs(&logs, "insufficient_deposit");
}

#[test]
fn insufficient_vault_tokens_on_release_inner_failure_full_snapshot() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let case = ReleaseRefundCase::new(
        program_id,
        10,
        7,
        10,
        0,
        6,
        true,
        fixed_key(0x60),
        fixed_key(0x61),
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_RELEASE_HANDLER_ID, 11),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(TOKEN_ERR_INSUFFICIENT_FUNDS)),
            Check::return_data(&[]),
        ],
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert_token_transfer_checked_failure_logs(&logs, "insufficient_vault_release");
}

/// Destination amount overflow: classic Token Custom(14), admitted to CPI
/// (TransferChecked log) then full snapshot rollback.
#[test]
fn destination_amount_overflow_on_deposit_inner_failure_full_snapshot() {
    let (mut mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let (authority_pda, _) =
        independent_find_pda_current_program_tagged_v1(&program_id, &fixed_key(0x22), 5);
    let mint_key = fixed_key(0x23);
    let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
    // vault near u64::MAX; transfer 2 → Token Overflow if admitted.
    let case = DepositCase::new(
        program_id,
        10,
        10,
        u64::MAX - 1,
        6,
        true,
        vault_ata,
        authority_pda,
        mint_key,
    );
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_ESCROW_DEPOSIT_HANDLER_ID, 2),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(TOKEN_ERR_DESTINATION_AMOUNT_OVERFLOW)),
            Check::return_data(&[]),
        ],
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert_token_transfer_checked_failure_logs(&logs, "destination_amount_overflow");
}

/// High-byte amount path through generated ELF (amount = 2^32).
#[test]
fn deposit_high_byte_amount_success_exact_delta() {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let amount = 1u64 << 32;
    let (authority_pda, _) =
        independent_find_pda_current_program_tagged_v1(&program_id, &fixed_key(0x22), 5);
    let mint_key = fixed_key(0x23);
    let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
    let case = DepositCase::new(
        program_id,
        10,
        amount + 50,
        0,
        6,
        true,
        vault_ata,
        authority_pda,
        mint_key,
    );
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_ESCROW_DEPOSIT_HANDLER_ID, amount),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &case.source_key).data),
        50
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &case.vault_ata).data),
        amount
    );
}

#[test]
fn inspect_reads_initialized_state() {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let state_key = fixed_key(0xa0);
    let state = state_account(&program_id, escrow_state(true, 41));
    mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_simple_ix_data(CPI_ESCROW_INSPECT_HANDLER_ID),
            vec![AccountMeta::new_readonly(state_key, false)],
        ),
        &[(state_key, state)],
        &[Check::success(), Check::return_data(&41u64.to_le_bytes())],
    );
}

// ---------------------------------------------------------------------------
// One-mutation full-snapshot security matrix (table-driven, labeled)
// ---------------------------------------------------------------------------

fn run_initialize_mutation(label: &str, code: u32, mutate: impl FnOnce(&mut InitializeVaultCase)) {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let mut case = InitializeVaultCase::fresh(
        program_id,
        10,
        7,
        BASE_LAMPORTS,
        PDA_SPACE0_RENT_LAMPORTS,
        0,
        6,
    );
    mutate(&mut case);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID),
            &case.accounts,
            code,
        );
    }));
    if let Err(payload) = result {
        panic!("initialize mutation {label:?} failed: {payload:?}");
    }
}

fn run_deposit_mutation(label: &str, code: u32, mutate: impl FnOnce(&mut DepositCase)) {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let (authority_pda, _) =
        independent_find_pda_current_program_tagged_v1(&program_id, &fixed_key(0x22), 5);
    let mint_key = fixed_key(0x23);
    let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
    let mut case = DepositCase::new(
        program_id,
        10,
        1000,
        50,
        6,
        true,
        vault_ata,
        authority_pda,
        mint_key,
    );
    mutate(&mut case);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ESCROW_DEPOSIT_HANDLER_ID, 1),
            &case.accounts,
            code,
        );
    }));
    if let Err(payload) = result {
        panic!("deposit mutation {label:?} failed: {payload:?}");
    }
}

fn run_release_mutation(label: &str, code: u32, mutate: impl FnOnce(&mut ReleaseRefundCase)) {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let mut case = ReleaseRefundCase::new(
        program_id,
        10,
        7,
        500,
        50,
        6,
        true,
        fixed_key(0x60),
        fixed_key(0x61),
    );
    mutate(&mut case);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ESCROW_RELEASE_HANDLER_ID, 1),
            &case.accounts,
            code,
        );
    }));
    if let Err(payload) = result {
        panic!("release mutation {label:?} failed: {payload:?}");
    }
}

fn run_refund_mutation(label: &str, code: u32, mutate: impl FnOnce(&mut ReleaseRefundCase)) {
    let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
    let mut case = ReleaseRefundCase::new(
        program_id,
        10,
        7,
        500,
        50,
        6,
        true,
        fixed_key(0x90),
        fixed_key(0x91),
    );
    mutate(&mut case);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ESCROW_REFUND_HANDLER_ID, 1),
            &case.accounts,
            code,
        );
    }));
    if let Err(payload) = result {
        panic!("refund mutation {label:?} failed: {payload:?}");
    }
}

// --- A: deposit matrix ---

#[test]
fn one_mutation_deposit_state_and_privilege_flags() {
    for (label, code, mutate) in [
        (
            "state_unexpected_signer",
            CHECK_OR_UNKNOWN,
            (|c: &mut DepositCase| {
                c.metas[0] = AccountMeta::new(c.accounts[0].0, true);
            }) as fn(&mut DepositCase),
        ),
        ("state_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[0] = AccountMeta::new_readonly(c.accounts[0].0, false);
        }),
        ("source_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new_readonly(c.source_key, false);
        }),
        ("source_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.source_key, true);
        }),
        ("mint_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[2] = AccountMeta::new(c.mint_key, false);
        }),
        ("mint_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[2] = AccountMeta::new_readonly(c.mint_key, true);
        }),
        ("vault_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[3] = AccountMeta::new_readonly(c.vault_ata, false);
        }),
        ("vault_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[3] = AccountMeta::new(c.vault_ata, true);
        }),
        ("authority_missing_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[4] = AccountMeta::new_readonly(c.user_authority, false);
        }),
        ("authority_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[4] = AccountMeta::new(c.user_authority, true);
        }),
        ("token_program_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[5] = AccountMeta::new_readonly(c.token_program_key, true);
        }),
        ("token_program_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[5] = AccountMeta::new(c.token_program_key, false);
        }),
    ] {
        run_deposit_mutation(label, code, mutate);
    }
}

#[test]
fn one_mutation_deposit_source_account_shape() {
    for (label, code, mutate) in [
        (
            "source_wrong_token_owner",
            CHECK_OR_UNKNOWN,
            (|c: &mut DepositCase| {
                c.accounts[1].1.owner = Pubkey::default();
            }) as fn(&mut DepositCase),
        ),
        ("source_len_164", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data.truncate(164);
        }),
        ("source_len_166", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data.push(0);
        }),
        ("source_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.user_authority,
                c.source_amount,
                TOKEN_ACCOUNT_STATE_UNINITIALIZED,
                None,
            );
        }),
        ("source_frozen", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.user_authority,
                c.source_amount,
                TOKEN_ACCOUNT_STATE_FROZEN,
                None,
            );
        }),
        ("source_mint_mismatch", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &fixed_key(0xef),
                &c.user_authority,
                c.source_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            );
        }),
        ("source_authority_mismatch", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &c.mint_key,
                &fixed_key(0xed),
                c.source_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            );
        }),
    ] {
        run_deposit_mutation(label, code, mutate);
    }
}

#[test]
fn one_mutation_deposit_mint_and_vault_account_shape() {
    for (label, code, mutate) in [
        (
            "mint_wrong_owner",
            CHECK_OR_UNKNOWN,
            (|c: &mut DepositCase| {
                c.accounts[2].1.owner = Pubkey::default();
            }) as fn(&mut DepositCase),
        ),
        ("mint_len_81", CHECK_OR_UNKNOWN, |c| {
            c.accounts[2].1.data.truncate(81);
        }),
        ("mint_len_83", CHECK_OR_UNKNOWN, |c| {
            c.accounts[2].1.data.push(0);
        }),
        ("mint_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[2].1.data = pack_classic_mint(&fixed_key(0x71), 1000, c.decimals, 0);
        }),
        ("mint_decimals_mismatch_via_ix", CHECK_OR_UNKNOWN, |c| {
            // Keep mint decimals=6; force instruction decimals=9 outside mutate.
            // Marker path: rewrite mint decimals field itself.
            c.accounts[2].1.data[44] = 9;
        }),
        ("vault_wrong_token_owner", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.owner = Pubkey::default();
        }),
        ("vault_len_164", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data.truncate(164);
        }),
        ("vault_len_166", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data.push(0);
        }),
        ("vault_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.vault_owner,
                c.vault_amount,
                TOKEN_ACCOUNT_STATE_UNINITIALIZED,
                None,
            );
        }),
        ("vault_frozen", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.vault_owner,
                c.vault_amount,
                TOKEN_ACCOUNT_STATE_FROZEN,
                None,
            );
        }),
        ("vault_mint_mismatch", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data = pack_classic_token_account(
                &fixed_key(0xce),
                &c.vault_owner,
                c.vault_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            );
        }),
    ] {
        run_deposit_mutation(label, code, mutate);
    }
}

#[test]
fn one_mutation_deposit_token_program_and_aliases() {
    for (label, code, mutate) in [
        (
            "token_program_wrong_key",
            CHECK_OR_UNKNOWN,
            (|c: &mut DepositCase| {
                let wrong = fixed_key(0xab);
                c.metas[5] = AccountMeta::new_readonly(wrong, false);
                c.accounts[5] = (wrong, create_program_account_loader_v3(&wrong));
                c.token_program_key = wrong;
            }) as fn(&mut DepositCase),
        ),
        ("token_program_non_executable", CHECK_OR_UNKNOWN, |c| {
            c.accounts[5].1.executable = false;
        }),
        ("token_program_wrong_loader_owner", CHECK_OR_UNKNOWN, |c| {
            c.accounts[5].1.owner = Pubkey::default();
        }),
        ("token2022_substitution", CHECK_OR_UNKNOWN, |c| {
            let t22 = token_2022_program_id();
            c.metas[5] = AccountMeta::new_readonly(t22, false);
            c.accounts[5] = (t22, create_program_account_loader_v3(&t22));
            c.token_program_key = t22;
        }),
        ("alias_source_meta_eq_vault", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.vault_ata, false);
        }),
        ("alias_source_meta_eq_mint", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.mint_key, false);
        }),
        ("alias_vault_meta_eq_source", CHECK_OR_UNKNOWN, |c| {
            c.metas[3] = AccountMeta::new(c.source_key, false);
        }),
        ("state_wrong_owner", CHECK_OR_UNKNOWN, |c| {
            c.accounts[0].1.owner = Pubkey::new_from_array([0xee; 32]);
        }),
    ] {
        run_deposit_mutation(label, code, mutate);
    }
    // Wrong mint decimals via ix (mint stays 6).
    {
        let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
        let (authority_pda, _) =
            independent_find_pda_current_program_tagged_v1(&program_id, &fixed_key(0x22), 5);
        let mint_key = fixed_key(0x23);
        let (vault_ata, _) = find_ata_classic_v1(&authority_pda, &mint_key);
        let case = DepositCase::new(
            program_id,
            10,
            1000,
            0,
            6,
            true,
            vault_ata,
            authority_pda,
            mint_key,
        );
        let ix = Instruction::new_with_bytes(
            program_id,
            &cpi_escrow_deposit_ix_data(CPI_ESCROW_DEPOSIT_HANDLER_ID, 1, 9),
            case.metas.clone(),
        );
        assert_custom_failure_snapshot(&mollusk, &ix, &case.accounts, CHECK_OR_UNKNOWN);
    }
}

// --- B: release / refund PDA matrix ---

#[test]
fn one_mutation_release_privilege_seed_and_program_flags() {
    for (label, code, mutate) in [
        (
            "state_unexpected_signer",
            CHECK_OR_UNKNOWN,
            (|c: &mut ReleaseRefundCase| {
                c.metas[0] = AccountMeta::new(c.accounts[0].0, true);
            }) as fn(&mut ReleaseRefundCase),
        ),
        ("state_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[0] = AccountMeta::new_readonly(c.accounts[0].0, false);
        }),
        ("vault_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new_readonly(c.vault_ata, false);
        }),
        ("vault_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.vault_ata, true);
        }),
        ("mint_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[2] = AccountMeta::new(c.mint_key, false);
        }),
        ("dest_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[3] = AccountMeta::new_readonly(c.destination_key, false);
        }),
        ("authority_pda_outer_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[4] = AccountMeta::new_readonly(c.authority_pda, true);
        }),
        ("authority_pda_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[4] = AccountMeta::new(c.authority_pda, false);
        }),
        ("seed_authority_missing_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[5] = AccountMeta::new_readonly(c.seed_authority, false);
        }),
        (
            "seed_authority_unexpected_writable",
            CHECK_OR_UNKNOWN,
            |c| {
                c.metas[5] = AccountMeta::new(c.seed_authority, true);
            },
        ),
        ("wrong_seed_tag", CHECK_OR_UNKNOWN, |c| {
            c.seed_tag = c.seed_tag.wrapping_add(1);
        }),
        ("bump_zero", CHECK_OR_UNKNOWN, |c| {
            c.bump = 0;
        }),
        ("token_program_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[6] = AccountMeta::new_readonly(c.token_program_key, true);
        }),
        ("token_program_non_executable", CHECK_OR_UNKNOWN, |c| {
            c.accounts[6].1.executable = false;
        }),
        ("token2022_substitution", CHECK_OR_UNKNOWN, |c| {
            let t22 = token_2022_program_id();
            c.metas[6] = AccountMeta::new_readonly(t22, false);
            c.accounts[6] = (t22, create_program_account_loader_v3(&t22));
            c.token_program_key = t22;
        }),
    ] {
        run_release_mutation(label, code, mutate);
    }
}

#[test]
fn one_mutation_release_token_account_shapes() {
    for (label, code, mutate) in [
        (
            "vault_wrong_owner",
            CHECK_OR_UNKNOWN,
            (|c: &mut ReleaseRefundCase| {
                c.accounts[1].1.owner = Pubkey::default();
            }) as fn(&mut ReleaseRefundCase),
        ),
        ("vault_len_164", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data.truncate(164);
        }),
        ("vault_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.authority_pda,
                c.vault_amount,
                TOKEN_ACCOUNT_STATE_UNINITIALIZED,
                None,
            );
        }),
        ("vault_frozen", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.authority_pda,
                c.vault_amount,
                TOKEN_ACCOUNT_STATE_FROZEN,
                None,
            );
        }),
        ("vault_mint_mismatch", CHECK_OR_UNKNOWN, |c| {
            c.accounts[1].1.data = pack_classic_token_account(
                &fixed_key(0xef),
                &c.authority_pda,
                c.vault_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            );
        }),
        ("dest_wrong_owner", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.owner = Pubkey::default();
        }),
        ("dest_len_166", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data.push(0);
        }),
        ("dest_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.dest_owner,
                c.destination_amount,
                TOKEN_ACCOUNT_STATE_UNINITIALIZED,
                None,
            );
        }),
        ("dest_frozen", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data = pack_classic_token_account(
                &c.mint_key,
                &c.dest_owner,
                c.destination_amount,
                TOKEN_ACCOUNT_STATE_FROZEN,
                None,
            );
        }),
        ("dest_mint_mismatch", CHECK_OR_UNKNOWN, |c| {
            c.accounts[3].1.data = pack_classic_token_account(
                &fixed_key(0xce),
                &c.dest_owner,
                c.destination_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            );
        }),
        ("mint_len_81", CHECK_OR_UNKNOWN, |c| {
            c.accounts[2].1.data.truncate(81);
        }),
        ("mint_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[2].1.data = pack_classic_mint(&fixed_key(0x72), 500, c.decimals, 0);
        }),
    ] {
        run_release_mutation(label, code, mutate);
    }
}

#[test]
fn one_mutation_release_pda_key_aliases_and_order() {
    for (label, code, mutate) in [
        (
            "wrong_authority_pda_key",
            CHECK_OR_UNKNOWN,
            (|c: &mut ReleaseRefundCase| {
                let wrong = fixed_key(0xee);
                c.metas[4] = AccountMeta::new_readonly(wrong, false);
                c.accounts[4] = (wrong, Account::new(BASE_LAMPORTS, 0, &Pubkey::default()));
                c.authority_pda = wrong;
            }) as fn(&mut ReleaseRefundCase),
        ),
        ("noncanonical_bump_and_key", CHECK_OR_UNKNOWN, |c| {
            let program_id = cpi_escrow_program_id();
            let (wrong, wrong_bump) =
                find_noncanonical_pda_below(&program_id, &c.seed_authority, c.seed_tag, c.bump);
            c.metas[4] = AccountMeta::new_readonly(wrong, false);
            c.accounts[4] = (wrong, Account::new(BASE_LAMPORTS, 0, &Pubkey::default()));
            c.authority_pda = wrong;
            c.bump = wrong_bump;
        }),
        ("alias_vault_meta_eq_dest", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.destination_key, false);
        }),
        ("alias_vault_meta_eq_mint", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.mint_key, false);
        }),
        (
            "alias_seed_auth_meta_eq_authority_pda",
            CHECK_OR_UNKNOWN,
            |c| {
                c.metas[5] = AccountMeta::new_readonly(c.authority_pda, true);
            },
        ),
        ("alias_token_meta_eq_vault", CHECK_OR_UNKNOWN, |c| {
            c.metas[6] = AccountMeta::new_readonly(c.vault_ata, false);
        }),
    ] {
        run_release_mutation(label, code, mutate);
    }
    // Role order swap (vault ↔ dest).
    {
        let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
        let mut case = ReleaseRefundCase::new(
            program_id,
            10,
            7,
            500,
            0,
            6,
            true,
            fixed_key(0x60),
            fixed_key(0x61),
        );
        case.metas.swap(1, 3);
        case.accounts.swap(1, 3);
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ESCROW_RELEASE_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Role count: drop seed authority.
    {
        let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
        let case = ReleaseRefundCase::new(
            program_id,
            10,
            7,
            500,
            0,
            6,
            true,
            fixed_key(0x60),
            fixed_key(0x61),
        );
        let mut metas = case.metas.clone();
        metas.remove(5);
        let mut accounts = case.accounts.clone();
        accounts.remove(5);
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_escrow_release_ix_data(
                    CPI_ESCROW_RELEASE_HANDLER_ID,
                    case.seed_tag,
                    case.bump,
                    1,
                    case.decimals,
                ),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

/// Independent refund-path wiring: wrong destination shape + seedAuthority
/// missing signer (proves refund handler is live, not only release).
#[test]
fn one_mutation_refund_destination_and_seed_authority() {
    run_refund_mutation("refund_dest_frozen", CHECK_OR_UNKNOWN, |c| {
        c.accounts[3].1.data = pack_classic_token_account(
            &c.mint_key,
            &c.dest_owner,
            c.destination_amount,
            TOKEN_ACCOUNT_STATE_FROZEN,
            None,
        );
    });
    run_refund_mutation(
        "refund_seed_authority_missing_signer",
        CHECK_OR_UNKNOWN,
        |c| {
            c.metas[5] = AccountMeta::new_readonly(c.seed_authority, false);
        },
    );
    run_refund_mutation("refund_wrong_seed_tag", CHECK_OR_UNKNOWN, |c| {
        c.seed_tag = c.seed_tag.wrapping_add(3);
    });
}

// --- C: initialize matrix ---

#[test]
fn one_mutation_initialize_privilege_and_program_flags() {
    for (label, code, mutate) in [
        (
            "state_unexpected_signer",
            CHECK_OR_UNKNOWN,
            (|c: &mut InitializeVaultCase| {
                c.metas[0] = AccountMeta::new(c.state_key, true);
            }) as fn(&mut InitializeVaultCase),
        ),
        ("state_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[0] = AccountMeta::new_readonly(c.state_key, false);
        }),
        ("payer_missing_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new(c.payer_key, false);
        }),
        ("payer_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[1] = AccountMeta::new_readonly(c.payer_key, true);
        }),
        ("authority_pda_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[2] = AccountMeta::new(c.authority_pda, true);
        }),
        ("authority_pda_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[2] = AccountMeta::new_readonly(c.authority_pda, false);
        }),
        ("seed_authority_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[3] = AccountMeta::new_readonly(c.seed_authority, true);
        }),
        (
            "seed_authority_unexpected_writable",
            CHECK_OR_UNKNOWN,
            |c| {
                c.metas[3] = AccountMeta::new(c.seed_authority, false);
            },
        ),
        ("vault_missing_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[4] = AccountMeta::new_readonly(c.vault_ata, false);
        }),
        ("vault_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[4] = AccountMeta::new(c.vault_ata, true);
        }),
        ("mint_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[5] = AccountMeta::new(c.mint_key, false);
        }),
        ("mint_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[5] = AccountMeta::new_readonly(c.mint_key, true);
        }),
        ("system_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[6] = AccountMeta::new_readonly(c.system_program_key, true);
        }),
        ("system_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[6] = AccountMeta::new(c.system_program_key, false);
        }),
        ("ata_program_unexpected_signer", CHECK_OR_UNKNOWN, |c| {
            c.metas[7] = AccountMeta::new_readonly(c.ata_program_key, true);
        }),
        ("token_program_unexpected_writable", CHECK_OR_UNKNOWN, |c| {
            c.metas[8] = AccountMeta::new(c.token_program_key, false);
        }),
    ] {
        run_initialize_mutation(label, code, mutate);
    }
}

#[test]
fn one_mutation_initialize_keys_prestate_and_identity() {
    for (label, code, mutate) in [
        (
            "state_wrong_owner",
            CHECK_OR_UNKNOWN,
            (|c: &mut InitializeVaultCase| {
                c.accounts[0].1.owner = Pubkey::new_from_array([0xee; 32]);
            }) as fn(&mut InitializeVaultCase),
        ),
        ("state_marker_corrupt", CHECK_OR_UNKNOWN, |c| {
            if c.accounts[0].1.data.len() >= 8 {
                c.accounts[0].1.data[0] ^= 0xff;
            }
        }),
        ("wrong_authority_pda_key", CHECK_OR_UNKNOWN, |c| {
            let wrong = fixed_key(0xee);
            c.metas[2] = AccountMeta::new(wrong, false);
            c.accounts[2] = (wrong, unused_system_create_target_account());
            c.authority_pda = wrong;
        }),
        ("wrong_seed_tag", CHECK_OR_UNKNOWN, |c| {
            c.seed_tag = c.seed_tag.wrapping_add(1);
        }),
        ("bump_zero", CHECK_OR_UNKNOWN, |c| {
            c.bump = 0;
        }),
        ("wrong_vault_ata_key", CHECK_OR_UNKNOWN, |c| {
            let wrong = fixed_key(0xdd);
            c.metas[4] = AccountMeta::new(wrong, false);
            c.accounts[4] = (wrong, unused_system_create_target_account());
            c.vault_ata = wrong;
        }),
        ("fresh_ata_nonzero_lamports", CHECK_OR_UNKNOWN, |c| {
            c.accounts[4].1 = Account::new(1, 0, &Pubkey::default());
        }),
        ("fresh_ata_non_system_owner", CHECK_OR_UNKNOWN, |c| {
            c.accounts[4].1.owner = c.token_program_key;
        }),
        ("mint_len_81", CHECK_OR_UNKNOWN, |c| {
            c.accounts[5].1.data.truncate(81);
        }),
        ("mint_uninitialized", CHECK_OR_UNKNOWN, |c| {
            c.accounts[5].1.data = pack_classic_mint(&c.mint_authority, 1_000_000, c.decimals, 0);
        }),
        ("system_wrong_key", CHECK_OR_UNKNOWN, |c| {
            let wrong = fixed_key(0xad);
            c.metas[6] = AccountMeta::new_readonly(wrong, false);
            c.accounts[6] = (wrong, Account::new(1, 0, &loader_v3_owner()));
            c.system_program_key = wrong;
        }),
        ("system_non_executable", CHECK_OR_UNKNOWN, |c| {
            c.accounts[6].1.executable = false;
        }),
        ("system_wrong_native_owner", CHECK_OR_UNKNOWN, |c| {
            c.accounts[6].1.owner = fixed_key(0x76);
        }),
        ("ata_program_wrong_key", CHECK_OR_UNKNOWN, |c| {
            let wrong = fixed_key(0xac);
            c.metas[7] = AccountMeta::new_readonly(wrong, false);
            c.accounts[7] = (wrong, create_program_account_loader_v3(&wrong));
            c.ata_program_key = wrong;
        }),
        ("token_program_non_executable", CHECK_OR_UNKNOWN, |c| {
            c.accounts[8].1.executable = false;
        }),
        ("alias_payer_meta_as_authority_pda", CHECK_OR_UNKNOWN, |c| {
            c.metas[2] = AccountMeta::new(c.payer_key, false);
        }),
    ] {
        run_initialize_mutation(label, code, mutate);
    }
    // Role order / count.
    {
        let (mollusk, program_id, _, _) = make_cpi_escrow_mollusk();
        let case = InitializeVaultCase::fresh(
            program_id,
            10,
            7,
            BASE_LAMPORTS,
            PDA_SPACE0_RENT_LAMPORTS,
            0,
            6,
        );
        let mut swapped = case.clone();
        swapped.metas.swap(1, 2);
        swapped.accounts.swap(1, 2);
        assert_custom_failure_snapshot(
            &mollusk,
            &swapped.instruction(program_id, CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID),
            &swapped.accounts,
            CHECK_OR_UNKNOWN,
        );
        let mut short_metas = case.metas.clone();
        short_metas.remove(5);
        let mut short_accounts = case.accounts.clone();
        short_accounts.remove(5);
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_escrow_initialize_ix_data(
                    CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID,
                    case.seed_tag,
                    case.bump,
                    case.pda_lamports,
                    case.pda_space,
                ),
                short_metas,
            ),
            &short_accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    run_initialize_mutation(
        "insufficient_lamports",
        SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
        |c| {
            c.accounts[1].1.lamports = 100;
            c.payer_lamports = 100;
        },
    );
}

/// Derivation program-id single mutation: same generated caller ELF is loaded
/// under alias `[0x5a;32]`. Instruction targets the alias, but authority PDA /
/// bump / vault ATA remain those derived for the canonical `[0x59;32]` pin.
/// Preflight must reject with Custom(1) + full snapshot — not a missing-program
/// failure.
#[test]
fn wrong_derivation_program_id_with_loaded_alias_program_fails_full_snapshot() {
    let caller_elf = read_cpi_escrow_caller_elf();
    let alias_id = Pubkey::new_from_array([0x5a; 32]);
    let canonical_id = cpi_escrow_program_id();
    assert_ne!(alias_id, canonical_id);

    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &alias_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &caller_elf,
    );
    mollusk.add_program_with_loader_and_elf(
        &ata_classic_program_id(),
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_ata_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &token_classic_program_id(),
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_token_elf(),
    );

    let seed_tag = 7u64;
    let seed_authority = fixed_key(0x22);
    let mint_key = fixed_key(0x23);
    let (canonical_pda, canonical_bump) =
        independent_find_pda_current_program_tagged_v1(&canonical_id, &seed_authority, seed_tag);
    let (vault_ata, _) = find_ata_classic_v1(&canonical_pda, &mint_key);

    let mut case = InitializeVaultCase::fresh(
        alias_id,
        10,
        seed_tag,
        BASE_LAMPORTS,
        PDA_SPACE0_RENT_LAMPORTS,
        0,
        6,
    );
    case.authority_pda = canonical_pda;
    case.bump = canonical_bump;
    case.vault_ata = vault_ata;
    case.metas[2] = AccountMeta::new(canonical_pda, false);
    case.metas[4] = AccountMeta::new(vault_ata, false);
    case.accounts[2] = (canonical_pda, unused_system_create_target_account());
    case.accounts[4] = (vault_ata, unused_system_create_target_account());

    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(alias_id, CPI_ESCROW_INITIALIZE_VAULT_HANDLER_ID),
        &case.accounts,
        CHECK_OR_UNKNOWN,
    );
}
