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

mod common;

use {
    common::{single_field, state_account, system_program_keyed_account,
        assert_failure_preserves_exact_accounts, CHECK_OR_UNKNOWN},
    mollusk_svm::{
        program::{create_program_account_loader_v3, loader_keys::LOADER_V3},
        result::Check,
        Mollusk,
    },
    serde::Deserialize,
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{
        env, fs,
        os::unix::fs::MetadataExt,
        path::{Path, PathBuf},
        process::Command,
        sync::OnceLock,
    },
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
// Mollusk product acceptance (activated on integrated tree)
// ---------------------------------------------------------------------------

const OUTPUT_SCHEMA: &str = "proof-forge.output.v1";
const CPI_PROFILE: &str = "solana-sbpf-cpi-elf-v1";
const PROGRAM_NAME: &str = "TokenJarAssets";
const MODULE_NAME: &str = "Examples.TokenJarAssets";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";
const EXPECTED_SOURCE_HASH: &str =
    "fa7ba02b8ab857a03694ab283b5765c3fa5be7e812f12b5e5b3774c1a90ab73b";

const INIT_HANDLER_ID: u64 = 0;
const TIP_HANDLER_ID: u64 = 1;
const GET_HANDLER_ID: u64 = 2;

/// tipToken outer role positions (dense, 10 roles incl. ATA program account).
const TIP_ROLE_COUNT: usize = 10;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OutputManifest {
    schema_version: String,
    target: String,
    codegen_profile: String,
    artifact_program_name: String,
    source_hash: String,
    semantic_hash: String,
    build_identity_digest: String,
    plan_digest: String,
    support_claim_digest: String,
    engineering_registry_root_digest: String,
    output_set_digest: String,
    evidence_sha256: String,
    deployable: bool,
    files: Vec<ArtifactDescriptor>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ArtifactDescriptor {
    role: String,
    path: String,
    size: u64,
    content_sha256: String,
}

fn load_manifest(out: &Path) -> OutputManifest {
    let raw = fs::read(out.join("manifest.json")).expect("read manifest.json");
    serde_json::from_slice(&raw).expect("manifest json")
}

fn stable_read(path: &Path, label: &str) -> Vec<u8> {
    let meta = fs::symlink_metadata(path)
        .unwrap_or_else(|e| panic!("{label}: metadata: {e}"));
    assert!(meta.file_type().is_file(), "{label}: not a regular file");
    assert_eq!(meta.nlink(), 1, "{label}: must be single hard-link");
    let bytes = fs::read(path).unwrap_or_else(|e| panic!("{label}: read: {e}"));
    assert_eq!(bytes.len() as u64, meta.size(), "{label}: size changed during read");
    bytes
}

fn read_manifest_leaf_bytes(out: &Path, name: &str, role: &str) -> Vec<u8> {
    let manifest = load_manifest(out);
    assert_eq!(manifest.schema_version, OUTPUT_SCHEMA);
    let desc = manifest
        .files
        .iter()
        .find(|d| d.role == role && d.path.ends_with(name))
        .unwrap_or_else(|| panic!("manifest missing {role} leaf {name}"));
    let bytes = stable_read(&out.join(&desc.path), "manifest leaf");
    assert_eq!(bytes.len() as u64, desc.size, "manifest leaf size");
    assert_eq!(hex::encode(Sha256::digest(&bytes)), desc.content_sha256);
    bytes
}

fn repo_root2() -> PathBuf { repo_root() }

fn default_tool_root() -> PathBuf {
    let home = env::var("HOME").expect("HOME");
    PathBuf::from(home).join(".cache/proof-forge-v2/tool-root/darwin-arm64")
}

fn ensure_product_output() -> PathBuf {
    static OUT: OnceLock<PathBuf> = OnceLock::new();
    OUT.get_or_init(|| {
        if let Ok(existing) = env::var("PROOF_FORGE_TIPJAR_TOKEN_OUT") {
            let path = PathBuf::from(existing);
            let _elf = read_manifest_leaf_bytes(&path, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA);
            // The source-identity pin must hold for script-provided trees
            // too, not only for the self-build branch below (a stale or
            // foreign tree must fail closed here, not silently pass).
            let manifest = load_manifest(&path);
            assert_eq!(
                manifest.source_hash, EXPECTED_SOURCE_HASH,
                "script-provided product tree must stay bound to the tracked TokenJarAssets source"
            );
            return path;
        }
        let root = repo_root2();
        let out = root.join("build/v2/solana-tipjar-token");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }
        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior TokenJar product out");
        }
        let tool_root = env::var("PROOF_FORGE_TOOL_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| default_tool_root());
        assert!(tool_root.join("sbpf").is_file(), "sbpf missing under tool root");
        let cli = root.join(".lake/build/bin/proof-forge-next");
        assert!(cli.is_file(), "proof-forge-next missing; run lake build proof_forge_next");
        let source = root.join(SOURCE_REL);
        assert!(source.is_file(), "missing fixture {}", source.display());
        let status = Command::new("lake")
            .arg("env")
            .arg(&cli)
            .arg("build")
            .arg(SOURCE_REL)
            .arg("--module")
            .arg(MODULE_NAME)
            .arg("--target")
            .arg("solana")
            .arg("--profile")
            .arg(CPI_PROFILE)
            .arg("-o")
            .arg(&out)
            .current_dir(&root)
            .env("PROOF_FORGE_TOOL_ROOT", &tool_root)
            .status()
            .expect("spawn product build");
        assert!(status.success(), "product CLI build failed for TokenJarAssets");
        let elf = read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA);
        assert!(elf.starts_with(b"\x7fELF"), "product .so must be ELF");
        let manifest = load_manifest(&out);
        assert_eq!(manifest.source_hash, EXPECTED_SOURCE_HASH);
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    Pubkey::new_from_array([0x55; 32])
}

fn make_product_mollusk() -> (Mollusk, Pubkey) {
    let out = ensure_product_output();
    let program_id = product_program_id();
    let elf = read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA);
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &LOADER_V3,
        &elf,
    );
    mollusk.add_program_with_loader_and_elf(
        &token_classic_program_id(),
        &LOADER_V3,
        &read_vendored_token_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &ata_classic_program_id(),
        &LOADER_V3,
        &read_vendored_ata_elf(),
    );
    (mollusk, program_id)
}

fn read_vendored_token_elf() -> Vec<u8> {
    let committed = stable_read(
        &repo_root2().join("runtime-tests/solana/token/token_classic_v1.so"),
        "committed Token ELF",
    );
    assert_eq!(committed.len() as u64, 94960);
    assert_eq!(
        hex::encode(Sha256::digest(&committed)),
        "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
    );
    assert!(committed.starts_with(b"\x7fELF"));
    committed
}

fn read_vendored_ata_elf() -> Vec<u8> {
    let committed = stable_read(
        &repo_root2().join("runtime-tests/solana/ata/ata_classic_v1.so"),
        "committed ATA ELF",
    );
    assert_eq!(committed.len() as u64, 111136);
    assert_eq!(
        hex::encode(Sha256::digest(&committed)),
        "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
    );
    assert!(committed.starts_with(b"\x7fELF"));
    committed
}

// --- packing + PDA helpers ---------------------------------------------------

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

fn pack_classic_mint(mint_authority: &Pubkey, supply: u64, decimals: u8) -> Vec<u8> {
    let mut data = vec![0u8; TOKEN_MINT_DATA_BYTES];
    data[0..36].copy_from_slice(&coption_pubkey_some(mint_authority));
    data[36..44].copy_from_slice(&supply.to_le_bytes());
    data[44] = decimals;
    data[45] = 1;
    data[46..82].copy_from_slice(&coption_pubkey_none());
    data
}

fn pack_classic_token_account(mint: &Pubkey, owner: &Pubkey, amount: u64) -> Vec<u8> {
    let mut data = vec![0u8; TOKEN_ACCOUNT_DATA_BYTES];
    data[0..32].copy_from_slice(mint.as_ref());
    data[32..64].copy_from_slice(owner.as_ref());
    data[64..72].copy_from_slice(&amount.to_le_bytes());
    data[72..108].copy_from_slice(&coption_pubkey_none());
    data[108] = 1;
    data
}

fn token_amount(data: &[u8]) -> u64 {
    assert_eq!(data.len(), TOKEN_ACCOUNT_DATA_BYTES);
    u64::from_le_bytes(data[64..72].try_into().unwrap())
}

/// Canonical vault PDA: seeds = [`proof-forge:vault:v1`, bump], search 255..1.
fn find_vault_pda(program_id: &Pubkey) -> (Pubkey, u8) {
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[VAULT_SEED0, &bump_slice];
        if let Ok(addr) = Pubkey::create_program_address(seeds, program_id) {
            return (addr, bump);
        }
    }
    panic!("no canonical vault PDA bump in 255..1");
}

/// Canonical classic ATA: seeds = [wallet, Token, mint] under ATA program.
fn find_ata(wallet: &Pubkey, mint: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(
        &[wallet.as_ref(), token_classic_program_id().as_ref(), mint.as_ref()],
        &ata_classic_program_id(),
    )
}

fn tips_state(initialized: bool, tips: u64) -> Vec<u8> {
    common::state_data(&single_field("tips"), initialized, &[tips])
}

fn token_owner_account(lamports: u64, data: Vec<u8>) -> Account {
    let mut account = Account::new(lamports, data.len(), &token_classic_program_id());
    account.data = data;
    account
}

fn account_by_key<'a>(accounts: &'a [(Pubkey, Account)], key: &Pubkey) -> &'a Account {
    accounts
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, a)| a)
        .unwrap_or_else(|| panic!("missing account {key}"))
}

fn init_ix_data(initial: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(16);
    data.extend_from_slice(&INIT_HANDLER_ID.to_le_bytes());
    data.extend_from_slice(&initial.to_le_bytes());
    data
}

fn tip_ix_data(amount: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(16);
    data.extend_from_slice(&TIP_HANDLER_ID.to_le_bytes());
    data.extend_from_slice(&amount.to_le_bytes());
    data
}

fn get_ix_data() -> Vec<u8> {
    GET_HANDLER_ID.to_le_bytes().to_vec()
}

// --- case builders -----------------------------------------------------------

struct TipCase {
    state_key: Pubkey,
    mint_key: Pubkey,
    dst_key: Pubkey,
    caller_key: Pubkey,
    vault_ata_key: Pubkey,
    dst_ata_key: Pubkey,
    vault_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl TipCase {
    /// `dst_ata_state`: `Some(amount)` pre-created initialized ATA;
    /// `None` fresh System-owned zero account (program must ensure-create).
    fn new(program_id: Pubkey, tips_before: u64, vault_amount: u64, dst_ata: Option<u64>) -> Self {
        let state_key = fixed_key(0x40);
        let mint_key = fixed_key(0x41);
        let dst_key = fixed_key(0x42);
        let caller_key = fixed_key(0x43);
        let (vault_key, _bump) = find_vault_pda(&program_id);
        let (vault_ata_key, _) = find_ata(&vault_key, &mint_key);
        let (dst_ata_key, _) = find_ata(&dst_key, &mint_key);

        let state = state_account(&program_id, tips_state(true, tips_before));
        let mint = token_owner_account(4_000_000, pack_classic_mint(&vault_key, 1_000_000, MINT_DECIMALS));
        let dst = Account::new(2_000_000, 0, &Pubkey::default());
        let caller = Account::new(20_000_000, 0, &Pubkey::default());
        let system_prog = system_program_keyed_account();
        let token_prog = (token_classic_program_id(), create_program_account_loader_v3(&token_classic_program_id()));
        let ata_prog = (ata_classic_program_id(), create_program_account_loader_v3(&ata_classic_program_id()));
        let vault_ata = token_owner_account(4_000_000, pack_classic_token_account(&mint_key, &vault_key, vault_amount));
        let dst_ata_account = match dst_ata {
            Some(amount) => token_owner_account(4_000_000, pack_classic_token_account(&mint_key, &dst_key, amount)),
            // Fresh on-chain ATA is a non-existent account: 0 lamports, empty
            // data, System-owned. A System-owned account with non-empty data
            // (e.g. 165B) makes createIdempotent reject with InvalidOwner.
            None => Account::new(0, 0, &Pubkey::default()),
        };
        let vault = Account::new(890_880, 0, &program_id);

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new_readonly(dst_key, false),
            AccountMeta::new(caller_key, true),
            AccountMeta::new_readonly(Pubkey::default(), false),
            AccountMeta::new_readonly(ata_classic_program_id(), false),
            AccountMeta::new_readonly(token_classic_program_id(), false),
            AccountMeta::new(vault_ata_key, false),
            AccountMeta::new(dst_ata_key, false),
            AccountMeta::new_readonly(vault_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (mint_key, mint),
            (dst_key, dst),
            (caller_key, caller),
            system_prog,
            ata_prog,
            token_prog,
            (vault_ata_key, vault_ata),
            (dst_ata_key, dst_ata_account),
            (vault_key, vault),
        ];
        assert_eq!(metas.len(), TIP_ROLE_COUNT);
        assert_eq!(accounts.len(), TIP_ROLE_COUNT);
        Self {
            state_key,
            mint_key,
            dst_key,
            caller_key,
            vault_ata_key,
            dst_ata_key,
            vault_key,
            metas,
            accounts,
        }
    }

    fn instruction(&self, program_id: Pubkey, amount: u64) -> Instruction {
        Instruction::new_with_bytes(program_id, &tip_ix_data(amount), self.metas.clone())
    }
}

// --- tests -------------------------------------------------------------------

#[test]
fn ix_layouts_match_handler_probe_lengths() {
    assert_eq!(init_ix_data(7).len(), 16);
    assert_eq!(tip_ix_data(42).len(), 16);
    assert_eq!(get_ix_data().len(), 8);
}

#[test]
fn init_initializes_tips_state() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x40);
    let state = state_account(&program_id, tips_state(false, 0));
    let ix = Instruction::new_with_bytes(
        program_id,
        &init_ix_data(7),
        vec![AccountMeta::new(state_key, true)],
    );
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, state)],
        &[Check::success()],
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &state_key).data,
        tips_state(true, 7)
    );
}

#[test]
fn tip_token_success_existing_atas_balance_delta() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = TipCase::new(program_id, 0, 2000, Some(0));
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, 1000),
        &case.accounts,
        &[Check::success()],
    );
    assert_eq!(
        token_amount(&account_by_key(&result.resulting_accounts, &case.vault_ata_key).data),
        1000,
        "vault ATA must be debited"
    );
    assert_eq!(
        token_amount(&account_by_key(&result.resulting_accounts, &case.dst_ata_key).data),
        1000,
        "dst ATA must be credited"
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &case.state_key).data,
        tips_state(true, 1000),
        "tips must advance by amount"
    );
}

#[test]
fn tip_token_success_creates_fresh_dst_ata() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = TipCase::new(program_id, 0, 2000, None);
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, 1000),
        &case.accounts,
        &[Check::success()],
    );
    let dst_ata = account_by_key(&result.resulting_accounts, &case.dst_ata_key);
    assert_eq!(dst_ata.owner, token_classic_program_id(), "ensure must assign Token owner");
    assert_eq!(token_amount(&dst_ata.data), 1000, "fresh dst ATA created + credited");
    assert_eq!(
        token_amount(&account_by_key(&result.resulting_accounts, &case.vault_ata_key).data),
        1000
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &case.state_key).data,
        tips_state(true, 1000)
    );
}

#[test]
fn tip_token_insufficient_vault_balance_full_rollback() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = TipCase::new(program_id, 0, 500, Some(0));
    let ix = case.instruction(program_id, 1000);
    // SPL Token InsufficientFunds (custom 1) propagated by the cpi_failed path.
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn tip_token_wrong_mint_join_fails() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(program_id, 0, 2000, Some(0));
    // Swap the mint account for a different mint (join mismatch).
    let wrong_mint = fixed_key(0x44);
    case.accounts[1] = (
        wrong_mint,
        token_owner_account(4_000_000, pack_classic_mint(&case.vault_key, 1_000_000, MINT_DECIMALS)),
    );
    case.metas[1] = AccountMeta::new_readonly(wrong_mint, false);
    let ix = case.instruction(program_id, 1000);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn tip_token_noncanonical_dst_ata_fails() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(program_id, 0, 2000, Some(0));
    // Pass a wrong (non-canonical) dst ATA address with an otherwise valid account.
    let wrong_ata = fixed_key(0x45);
    case.accounts[7] = (
        wrong_ata,
        token_owner_account(4_000_000, pack_classic_token_account(&case.mint_key, &case.dst_key, 0)),
    );
    case.metas[7] = AccountMeta::new(wrong_ata, false);
    let ix = case.instruction(program_id, 1000);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn tip_token_multi_outer_signer_rejected() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(program_id, 0, 2000, Some(0));
    // Second outer signer (state) violates the exactly-one-caller convention.
    case.metas[0] = AccountMeta::new(case.state_key, true);
    let ix = case.instruction(program_id, 1000);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn tip_token_zero_signer_rejected() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(program_id, 0, 2000, Some(0));
    case.metas[3] = AccountMeta::new(case.caller_key, false);
    let ix = case.instruction(program_id, 1000);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn get_returns_tips_readonly() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x40);
    let state = state_account(&program_id, tips_state(true, 42));
    let ix = Instruction::new_with_bytes(
        program_id,
        &get_ix_data(),
        vec![AccountMeta::new_readonly(state_key, false)],
    );
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &[(state_key, state)],
        &[Check::success(), Check::return_data(&42u64.to_le_bytes())],
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &state_key).data,
        tips_state(true, 42)
    );
}
