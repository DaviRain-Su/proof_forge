//! # Product-path BodyCpiTokenPay Mollusk differential (ADR-0030 M4b).
//!
//! Builds `Examples/BodyCpiTokenPay.lean` through ordinary
//! `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! and loads the manifest-bound `BodyCpiTokenPay.so` into Mollusk with
//! vendored classic Token + ATA programs + native System.
//!
//! Surface (full-body multi-role token.transfer):
//! - handlers: initialize / credit / pay / get (disc = LowerSemantic formula)
//! - multi-role entry requires exact outerRoleCount=10 on every handler
//! - pay: paid ≥ amount → debit paid + ATA ensure×2 + transferCheckedPda
//! - pay ix data = disc u64 LE + 18×u64 Principal leaves + amount u64 LE (160 B)
//!
//! Env (optional):
//! - `PROOF_FORGE_BODY_CPI_TOKEN_PAY_OUT` — existing product output tree.
//! - `PROOF_FORGE_TOOL_ROOT` — locked sbpf tool root (finalize).
//!
//! Engineering only — not formal TASK-D5 / hermetic / mainnet.

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, instruction_data, instruction_discriminator,
        instruction_discriminator_with_widths, single_field, state_account, state_data,
        system_program_keyed_account, BASE_LAMPORTS, CHECK_OR_UNKNOWN,
    },
    mollusk_svm::{
        program::{create_program_account_loader_v3, loader_keys::LOADER_V3},
        result::Check,
        Mollusk,
    },
    serde::Deserialize,
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{error::InstructionError, AccountMeta, Instruction},
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

const OUTPUT_SCHEMA: &str = "proof-forge.output.v1";
const CPI_PROFILE: &str = "solana-sbpf-cpi-elf-v1";
const PROGRAM_NAME: &str = "BodyCpiTokenPay";
const MODULE_NAME: &str = "Examples.BodyCpiTokenPay";
const SOURCE_REL: &str = "Examples/BodyCpiTokenPay.lean";
/// Canonical ProgramV1 source identity for the tracked fixture above.
const EXPECTED_SOURCE_HASH: &str =
    "d2e9ff16d6fc3cddc8165e95cf43e28445b7a43e9f5a44db8f6f984b02cfd17e";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

const VAULT_SEED0: &[u8] = b"proof-forge:vault:v1";
const MINT_DECIMALS: u8 = 9;
const TOKEN_ACCOUNT_DATA_BYTES: usize = 165;
const TOKEN_MINT_DATA_BYTES: usize = 82;

const TOKEN_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x06, 0xdd, 0xf6, 0xe1, 0xd7, 0x65, 0xa1, 0x93, 0xd9, 0xcb, 0xe1, 0x46, 0xce, 0xeb, 0x79, 0xac,
    0x1c, 0xb4, 0x85, 0xed, 0x5f, 0x5b, 0x37, 0x91, 0x3a, 0x8c, 0xf5, 0x85, 0x7e, 0xff, 0x00, 0xa9,
];
const ATA_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x8c, 0x97, 0x25, 0x8f, 0x4e, 0x24, 0x89, 0xf1, 0xbb, 0x3d, 0x10, 0x29, 0x14, 0x8e, 0x0d, 0x83,
    0x0b, 0x5a, 0x13, 0x99, 0xda, 0xff, 0x10, 0x84, 0x04, 0x8e, 0x7b, 0xd8, 0xdb, 0xe9, 0xf8, 0x59,
];

/// Principal expands to 9×UInt64 instruction leaves (len + 8 body words).
const PRINCIPAL_LEAF_COUNT: usize = 9;
/// pay(mint, to, amount) → 19 u64 leaves.
const PAY_PARAM_U64_COUNT: usize = PRINCIPAL_LEAF_COUNT * 2 + 1;
const PAY_IX_DATA_LEN: usize = 8 + PAY_PARAM_U64_COUNT * 8;

const OUTER_ROLE_COUNT: usize = 10;
const ROLE_STATE: usize = 0;
const ROLE_MINT: usize = 1;
const ROLE_TO: usize = 2;
const ROLE_CALLER: usize = 3;
const ROLE_SYSTEM: usize = 4;
const ROLE_ATA_PROG: usize = 5;
const ROLE_TOKEN_PROG: usize = 6;
const ROLE_VAULT_ATA: usize = 7;
const ROLE_DST_ATA: usize = 8;
const ROLE_VAULT: usize = 9;

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

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn is_lower_hex_64(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn require_regular_single_link(path: &Path, label: &str) -> std::fs::Metadata {
    let metadata = fs::symlink_metadata(path)
        .unwrap_or_else(|error| panic!("{label}: metadata {}: {error}", path.display()));
    assert!(
        !metadata.file_type().is_symlink() && metadata.file_type().is_file(),
        "{label}: expected regular non-symlink file {}",
        path.display()
    );
    assert_eq!(
        metadata.nlink(),
        1,
        "{label}: expected single-link file {}, got nlink={}",
        path.display(),
        metadata.nlink()
    );
    metadata
}

fn manifest_for_cpi_product(output_dir: &Path) -> OutputManifest {
    let root_metadata = fs::symlink_metadata(output_dir)
        .unwrap_or_else(|error| panic!("output root {}: {error}", output_dir.display()));
    assert!(
        !root_metadata.file_type().is_symlink() && root_metadata.file_type().is_dir(),
        "output root must be a non-symlink directory: {}",
        output_dir.display()
    );
    let manifest_path = output_dir.join("manifest.json");
    require_regular_single_link(&manifest_path, "manifest");
    let bytes = fs::read(&manifest_path)
        .unwrap_or_else(|error| panic!("read {}: {error}", manifest_path.display()));
    let manifest: OutputManifest = serde_json::from_slice(&bytes)
        .unwrap_or_else(|error| panic!("decode {}: {error}", manifest_path.display()));
    assert_eq!(manifest.schema_version, OUTPUT_SCHEMA);
    assert_eq!(manifest.target, "solana");
    assert_eq!(manifest.codegen_profile, CPI_PROFILE);
    assert_eq!(manifest.artifact_program_name, PROGRAM_NAME);
    assert_eq!(
        manifest.source_hash, EXPECTED_SOURCE_HASH,
        "product output must remain bound to the tracked BodyCpiTokenPay source"
    );
    assert!(manifest.deployable, "product CPI artifact must be deployable");
    for (field, value) in [
        ("sourceHash", &manifest.source_hash),
        ("semanticHash", &manifest.semantic_hash),
        ("buildIdentityDigest", &manifest.build_identity_digest),
        ("planDigest", &manifest.plan_digest),
        ("supportClaimDigest", &manifest.support_claim_digest),
        (
            "engineeringRegistryRootDigest",
            &manifest.engineering_registry_root_digest,
        ),
        ("outputSetDigest", &manifest.output_set_digest),
        ("evidenceSha256", &manifest.evidence_sha256),
    ] {
        assert!(
            is_lower_hex_64(value),
            "manifest {field} must be 64 lowercase hex digits"
        );
    }

    let expected = [
        (
            format!("{PROGRAM_NAME}.cpi-bindings.json"),
            MATERIALIZED_BASE,
        ),
        (format!("{PROGRAM_NAME}.cpi-ir.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.cpi-plan.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.idl.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.s"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA),
    ];
    assert_eq!(
        manifest.files.len(),
        expected.len(),
        "CPI product files must be exactly six leaves, got {}",
        manifest.files.len()
    );
    for (descriptor, (path, role)) in manifest.files.iter().zip(expected.iter()) {
        assert_eq!(descriptor.path.as_str(), path.as_str());
        assert_eq!(descriptor.role.as_str(), *role);
    }

    let mut expected_physical: Vec<String> =
        expected.iter().map(|(path, _)| path.clone()).collect();
    expected_physical.push("evidence.json".to_string());
    expected_physical.push("manifest.json".to_string());
    expected_physical.sort();
    let mut actual_physical: Vec<String> = fs::read_dir(output_dir)
        .unwrap_or_else(|error| panic!("read output directory {}: {error}", output_dir.display()))
        .map(|entry| {
            entry
                .expect("output directory entry")
                .file_name()
                .into_string()
                .expect("output filename must be UTF-8")
        })
        .collect();
    actual_physical.sort();
    assert_eq!(
        actual_physical, expected_physical,
        "product output must have an exact eight-file physical closure"
    );
    for name in &actual_physical {
        require_regular_single_link(&output_dir.join(name), "product closure leaf");
    }

    let evidence_path = output_dir.join("evidence.json");
    let evidence_bytes = fs::read(&evidence_path)
        .unwrap_or_else(|error| panic!("read {}: {error}", evidence_path.display()));
    assert_eq!(
        hex::encode(Sha256::digest(&evidence_bytes)),
        manifest.evidence_sha256,
        "manifest evidenceSha256 must bind evidence.json"
    );
    manifest
}

fn read_manifest_leaf_bytes(
    output_dir: &Path,
    relative_path: &str,
    expected_role: &str,
) -> Vec<u8> {
    let manifest = manifest_for_cpi_product(output_dir);
    let matches: Vec<&ArtifactDescriptor> = manifest
        .files
        .iter()
        .filter(|descriptor| descriptor.path == relative_path)
        .collect();
    assert_eq!(
        matches.len(),
        1,
        "manifest path {relative_path:?} must occur exactly once"
    );
    let descriptor = matches[0];
    assert_eq!(descriptor.role, expected_role);
    let path = output_dir.join(relative_path);
    let before = require_regular_single_link(&path, "artifact");
    assert_eq!(before.len(), descriptor.size);
    let bytes = fs::read(&path).unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    let after = require_regular_single_link(&path, "artifact post-read");
    assert!(
        before.dev() == after.dev()
            && before.ino() == after.ino()
            && before.len() == after.len()
            && before.mtime() == after.mtime()
            && before.mtime_nsec() == after.mtime_nsec(),
        "artifact changed during stable read: {relative_path:?}"
    );
    assert_eq!(bytes.len() as u64, descriptor.size);
    let digest = hex::encode(Sha256::digest(&bytes));
    assert_eq!(digest, descriptor.content_sha256);
    bytes
}

fn default_tool_root() -> PathBuf {
    match env::consts::OS {
        "macos" => PathBuf::from(env::var("HOME").expect("HOME"))
            .join(".cache/proof-forge-v2/tool-root/darwin-arm64"),
        "linux" => PathBuf::from(env::var("HOME").expect("HOME")).join(format!(
            ".cache/proof-forge-v2/tool-root/linux-{}",
            env::consts::ARCH
        )),
        other => panic!("unsupported host OS for tool root: {other}"),
    }
}

fn ensure_product_output() -> PathBuf {
    static OUT: OnceLock<PathBuf> = OnceLock::new();
    OUT.get_or_init(|| {
        if let Ok(existing) = env::var("PROOF_FORGE_BODY_CPI_TOKEN_PAY_OUT") {
            let path = PathBuf::from(existing);
            let so = format!("{PROGRAM_NAME}.so");
            let _elf = read_manifest_leaf_bytes(&path, &so, FINALIZED_EXTRA);
            return path;
        }

        let root = repo_root();
        let out = root.join("build/v2/solana-body-cpi-token-pay");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }

        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior BodyCpiTokenPay product out");
        }
        fs::create_dir_all(out.parent().expect("product parent")).expect("mkdir product parent");

        let tool_root = env::var("PROOF_FORGE_TOOL_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| default_tool_root());
        assert!(
            tool_root.join("sbpf").is_file(),
            "sbpf missing under PROOF_FORGE_TOOL_ROOT={}",
            tool_root.display()
        );

        let cli = root.join(".lake/build/bin/proof-forge-next");
        assert!(
            cli.is_file(),
            "proof-forge-next missing at {}; run `lake build proof_forge_next`",
            cli.display()
        );

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
            .expect("spawn proof-forge-next product build");
        assert!(
            status.success(),
            "product CLI build failed for BodyCpiTokenPay (status={status})"
        );

        let so = format!("{PROGRAM_NAME}.so");
        let elf = read_manifest_leaf_bytes(&out, &so, FINALIZED_EXTRA);
        assert!(elf.starts_with(b"\x7fELF"), "product .so must be ELF");
        let assembly =
            read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.s"), MATERIALIZED_BASE);
        let asm_text = String::from_utf8_lossy(&assembly);
        assert!(
            !asm_text.contains("TEST-PREACTIVATION"),
            "product assembly must not carry preactivation banner"
        );
        assert!(
            asm_text.contains("sol_invoke_signed_c"),
            "product assembly must invoke via sol_invoke_signed_c"
        );
        assert!(
            asm_text.contains("mr_parse_role"),
            "product assembly must walk multi-role outer accounts"
        );
        assert!(
            asm_text.contains("product_mr_token"),
            "product assembly must emit multi-role token.transfer site"
        );
        assert!(
            asm_text.contains("TransferChecked"),
            "product assembly must emit TransferChecked"
        );
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    Pubkey::new_from_array([0x5c; 32])
}

fn token_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_CLASSIC_PROGRAM_ID_BYTES)
}

fn ata_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(ATA_CLASSIC_PROGRAM_ID_BYTES)
}

fn read_vendored_token_elf() -> Vec<u8> {
    let path = repo_root().join("runtime-tests/solana/token/token_classic_v1.so");
    let meta = require_regular_single_link(&path, "committed Token ELF");
    let committed = fs::read(&path).expect("read Token ELF");
    assert_eq!(meta.len(), 94960);
    assert_eq!(committed.len() as u64, 94960);
    assert_eq!(
        hex::encode(Sha256::digest(&committed)),
        "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
    );
    assert!(committed.starts_with(b"\x7fELF"));
    committed
}

fn read_vendored_ata_elf() -> Vec<u8> {
    let path = repo_root().join("runtime-tests/solana/ata/ata_classic_v1.so");
    let meta = require_regular_single_link(&path, "committed ATA ELF");
    let committed = fs::read(&path).expect("read ATA ELF");
    assert_eq!(meta.len(), 111136);
    assert_eq!(committed.len() as u64, 111136);
    assert_eq!(
        hex::encode(Sha256::digest(&committed)),
        "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
    );
    assert!(committed.starts_with(b"\x7fELF"));
    committed
}

fn make_product_mollusk() -> (Mollusk, Pubkey) {
    let out = ensure_product_output();
    let program_id = product_program_id();
    let elf = read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA);
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&program_id, &LOADER_V3, &elf);
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

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn paid_fields() -> [common::StateField; 1] {
    single_field("paid")
}

fn paid_state(initialized: bool, paid: u64) -> Vec<u8> {
    state_data(&paid_fields(), initialized, &[paid])
}

fn initialize_disc() -> String {
    instruction_discriminator("initialize", 0)
}

fn credit_disc() -> String {
    instruction_discriminator("credit", 1)
}

fn pay_disc() -> String {
    instruction_discriminator_with_widths("pay", &vec![8usize; PAY_PARAM_U64_COUNT])
}

fn get_disc() -> String {
    instruction_discriminator("get", 0)
}

fn initialize_ix_data() -> Vec<u8> {
    instruction_data(&initialize_disc(), &[])
}

fn credit_ix_data(amount: u64) -> Vec<u8> {
    instruction_data(&credit_disc(), &[amount])
}

fn pay_ix_data(amount: u64) -> Vec<u8> {
    let mut leaves = vec![0u64; PAY_PARAM_U64_COUNT];
    leaves[PAY_PARAM_U64_COUNT - 1] = amount;
    let data = instruction_data(&pay_disc(), &leaves);
    assert_eq!(data.len(), PAY_IX_DATA_LEN);
    data
}

fn get_ix_data() -> Vec<u8> {
    instruction_data(&get_disc(), &[])
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

fn find_ata(wallet: &Pubkey, mint: &Pubkey) -> (Pubkey, u8) {
    Pubkey::find_program_address(
        &[
            wallet.as_ref(),
            token_classic_program_id().as_ref(),
            mint.as_ref(),
        ],
        &ata_classic_program_id(),
    )
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

/// Multi-role entrypoint requires exact outerRoleCount accounts on every
/// handler (including init/credit/get which only *use* state).
fn ten_role_shell(
    program_id: &Pubkey,
    state_key: Pubkey,
    state: Account,
    state_signer: bool,
    state_writable: bool,
) -> (Vec<AccountMeta>, Vec<(Pubkey, Account)>) {
    let mint_key = fixed_key(0x71);
    let to_key = fixed_key(0x72);
    let caller_key = fixed_key(0x73);
    let (vault_key, _) = find_vault_pda(program_id);
    let (vault_ata_key, _) = find_ata(&vault_key, &mint_key);
    let (dst_ata_key, _) = find_ata(&to_key, &mint_key);
    let (system_key, system) = system_program_keyed_account();
    let token_prog = (
        token_classic_program_id(),
        create_program_account_loader_v3(&token_classic_program_id()),
    );
    let ata_prog = (
        ata_classic_program_id(),
        create_program_account_loader_v3(&ata_classic_program_id()),
    );
    let state_meta = if state_writable {
        AccountMeta::new(state_key, state_signer)
    } else {
        AccountMeta::new_readonly(state_key, state_signer)
    };
    let metas = vec![
        state_meta,
        AccountMeta::new_readonly(mint_key, false),
        AccountMeta::new_readonly(to_key, false),
        AccountMeta::new(caller_key, false),
        AccountMeta::new_readonly(system_key, false),
        AccountMeta::new_readonly(ata_classic_program_id(), false),
        AccountMeta::new_readonly(token_classic_program_id(), false),
        AccountMeta::new(vault_ata_key, false),
        AccountMeta::new(dst_ata_key, false),
        AccountMeta::new_readonly(vault_key, false),
    ];
    let accounts = vec![
        (state_key, state),
        (
            mint_key,
            token_owner_account(
                4_000_000,
                pack_classic_mint(&vault_key, 1_000_000, MINT_DECIMALS),
            ),
        ),
        (to_key, Account::new(2_000_000, 0, &Pubkey::default())),
        (caller_key, Account::new(20_000_000, 0, &Pubkey::default())),
        (system_key, system),
        ata_prog,
        token_prog,
        (
            vault_ata_key,
            token_owner_account(
                4_000_000,
                pack_classic_token_account(&mint_key, &vault_key, 0),
            ),
        ),
        (
            dst_ata_key,
            token_owner_account(4_000_000, pack_classic_token_account(&mint_key, &to_key, 0)),
        ),
        (vault_key, Account::new(890_880, 0, program_id)),
    ];
    assert_eq!(metas.len(), OUTER_ROLE_COUNT);
    assert_eq!(accounts.len(), OUTER_ROLE_COUNT);
    (metas, accounts)
}

#[derive(Clone)]
struct PayCase {
    state_key: Pubkey,
    mint_key: Pubkey,
    to_key: Pubkey,
    caller_key: Pubkey,
    vault_ata_key: Pubkey,
    dst_ata_key: Pubkey,
    vault_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    paid: u64,
}

impl PayCase {
    /// `dst_ata`: `Some(amount)` pre-created initialized ATA; `None` fresh
    /// System-owned zero account (program must ensure-create).
    fn new(program_id: &Pubkey, paid: u64, vault_amount: u64, dst_ata: Option<u64>) -> Self {
        let state_key = fixed_key(0x61);
        let mint_key = fixed_key(0x62);
        let to_key = fixed_key(0x63);
        let caller_key = fixed_key(0x64);
        let (vault_key, _) = find_vault_pda(program_id);
        let (vault_ata_key, _) = find_ata(&vault_key, &mint_key);
        let (dst_ata_key, _) = find_ata(&to_key, &mint_key);

        let state = state_account(program_id, paid_state(true, paid));
        let mint = token_owner_account(
            4_000_000,
            pack_classic_mint(&vault_key, 1_000_000, MINT_DECIMALS),
        );
        let to = Account::new(2_000_000, 0, &Pubkey::default());
        let caller = Account::new(20_000_000, 0, &Pubkey::default());
        let (system_key, system) = system_program_keyed_account();
        let token_prog = (
            token_classic_program_id(),
            create_program_account_loader_v3(&token_classic_program_id()),
        );
        let ata_prog = (
            ata_classic_program_id(),
            create_program_account_loader_v3(&ata_classic_program_id()),
        );
        let vault_ata = token_owner_account(
            4_000_000,
            pack_classic_token_account(&mint_key, &vault_key, vault_amount),
        );
        let dst_ata_account = match dst_ata {
            Some(amount) => token_owner_account(
                4_000_000,
                pack_classic_token_account(&mint_key, &to_key, amount),
            ),
            None => Account::new(0, 0, &Pubkey::default()),
        };
        let vault = Account::new(890_880, 0, program_id);

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new_readonly(to_key, false),
            AccountMeta::new(caller_key, true),
            AccountMeta::new_readonly(system_key, false),
            AccountMeta::new_readonly(ata_classic_program_id(), false),
            AccountMeta::new_readonly(token_classic_program_id(), false),
            AccountMeta::new(vault_ata_key, false),
            AccountMeta::new(dst_ata_key, false),
            AccountMeta::new_readonly(vault_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (mint_key, mint),
            (to_key, to),
            (caller_key, caller),
            (system_key, system),
            ata_prog,
            token_prog,
            (vault_ata_key, vault_ata),
            (dst_ata_key, dst_ata_account),
            (vault_key, vault),
        ];
        assert_eq!(metas.len(), OUTER_ROLE_COUNT);
        assert_eq!(accounts.len(), OUTER_ROLE_COUNT);
        Self {
            state_key,
            mint_key,
            to_key,
            caller_key,
            vault_ata_key,
            dst_ata_key,
            vault_key,
            metas,
            accounts,
            paid,
        }
    }

    fn pay_instruction(&self, program_id: Pubkey, amount: u64) -> Instruction {
        Instruction::new_with_bytes(program_id, &pay_ix_data(amount), self.metas.clone())
    }
}

// ---------------------------------------------------------------------------
// Pure layout / product tree identity
// ---------------------------------------------------------------------------

#[test]
fn pay_ix_layout_is_disc_plus_19_u64_leaves() {
    let data = pay_ix_data(42);
    assert_eq!(data.len(), PAY_IX_DATA_LEN);
    assert_eq!(&data[0..8], &common::discriminator_bytes(&pay_disc()));
    assert_eq!(&data[152..160], &42u64.to_le_bytes());
    assert!(data[8..152].iter().all(|&b| b == 0));
}

#[test]
fn product_tree_is_manifest_bound_multi_role_token_cpi() {
    let out = ensure_product_output();
    let manifest = manifest_for_cpi_product(&out);
    assert_eq!(manifest.codegen_profile, CPI_PROFILE);
    assert_eq!(manifest.artifact_program_name, PROGRAM_NAME);
    assert!(manifest.deployable);

    let plan_bytes = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-plan.json"),
        MATERIALIZED_BASE,
    );
    let plan: serde_json::Value =
        serde_json::from_slice(&plan_bytes).expect("cpi-plan.json object");
    assert_eq!(
        plan["schema"],
        serde_json::json!("proof-forge.solana.cpi-plan.v1")
    );
    assert_eq!(plan["profileId"], serde_json::json!(CPI_PROFILE));
    assert_eq!(plan["programName"], serde_json::json!(PROGRAM_NAME));
    let handlers = plan["handlers"].as_array().expect("handlers array");
    assert_eq!(handlers.len(), 4, "init/credit/pay/get");
    assert_eq!(handlers[0]["name"], serde_json::json!("init"));
    assert_eq!(handlers[1]["name"], serde_json::json!("credit"));
    assert_eq!(handlers[2]["name"], serde_json::json!("pay"));
    assert_eq!(handlers[3]["name"], serde_json::json!("get"));
    let pay_uses = handlers[2]["accountUses"].as_array().expect("pay uses");
    assert_eq!(pay_uses.len(), OUTER_ROLE_COUNT);
    assert_eq!(
        pay_uses[ROLE_CALLER]["outerSigner"],
        serde_json::json!(true)
    );
    assert_eq!(
        pay_uses[ROLE_VAULT_ATA]["outerWritable"],
        serde_json::json!(true)
    );
    assert_eq!(
        pay_uses[ROLE_DST_ATA]["outerWritable"],
        serde_json::json!(true)
    );

    let roles = plan["accountRoles"].as_array().expect("accountRoles");
    assert_eq!(roles.len(), OUTER_ROLE_COUNT);
    assert_eq!(roles[0]["name"], serde_json::json!("state"));
    assert_eq!(roles[1]["name"], serde_json::json!("pay_mint"));
    assert_eq!(roles[2]["name"], serde_json::json!("pay_to"));
    assert_eq!(roles[3]["name"], serde_json::json!("pf_caller"));
    assert_eq!(roles[6]["name"], serde_json::json!("token_classic_v1_program"));
    assert_eq!(roles[9]["name"], serde_json::json!("pf_vault"));

    let ir = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-ir.json"),
        MATERIALIZED_BASE,
    );
    let ir_text = String::from_utf8(ir).expect("ir utf-8");
    assert!(
        ir_text.contains("m4b-token-transfer-multi-role"),
        "product IR must mark m4b multi-role synthesize"
    );
    assert!(
        ir_text.contains("unifiedCpi"),
        "product IR must use unifiedCpi frame"
    );
    assert!(
        ir_text.contains("\"outerRoleCount\":10"),
        "product IR must pin outerRoleCount=10"
    );
    assert!(
        ir_text.contains("multi-role-token-transfer"),
        "product IR must mark multi-role-token-transfer maturity"
    );
}

// ---------------------------------------------------------------------------
// Mollusk runtime matrix
// ---------------------------------------------------------------------------

#[test]
fn initialize_then_credit_then_get_round_trip() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x51);
    let uninit = state_account(&program_id, paid_state(false, 0));
    let (init_metas, init_accounts) =
        ten_role_shell(&program_id, state_key, uninit, true, true);
    let init_ix =
        Instruction::new_with_bytes(program_id, &initialize_ix_data(), init_metas);
    let init_result = mollusk.process_and_validate_instruction(
        &init_ix,
        &init_accounts,
        &[Check::success()],
    );
    let after_init = init_result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == state_key)
        .map(|(_, a)| a.clone())
        .expect("state after init");
    assert_eq!(after_init.data, paid_state(true, 0));

    let credit_amount = 100u64;
    let (credit_metas, credit_accounts) =
        ten_role_shell(&program_id, state_key, after_init, false, true);
    let credit_ix =
        Instruction::new_with_bytes(program_id, &credit_ix_data(credit_amount), credit_metas);
    let credit_result = mollusk.process_and_validate_instruction(
        &credit_ix,
        &credit_accounts,
        &[
            Check::success(),
            Check::return_data(&credit_amount.to_le_bytes()),
        ],
    );
    let after_credit = credit_result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == state_key)
        .map(|(_, a)| a.clone())
        .expect("state after credit");
    assert_eq!(after_credit.data, paid_state(true, credit_amount));

    let (get_metas, get_accounts) =
        ten_role_shell(&program_id, state_key, after_credit, false, false);
    let get_ix = Instruction::new_with_bytes(program_id, &get_ix_data(), get_metas);
    mollusk.process_and_validate_instruction(
        &get_ix,
        &get_accounts,
        &[
            Check::success(),
            Check::return_data(&credit_amount.to_le_bytes()),
        ],
    );
}

#[test]
fn pay_success_existing_atas_token_delta() {
    let (mollusk, program_id) = make_product_mollusk();
    let paid = 2000u64;
    let transfer_amount = 1000u64;
    let case = PayCase::new(&program_id, paid, 2000, Some(0));
    let result = mollusk.process_and_validate_instruction(
        &case.pay_instruction(program_id, transfer_amount),
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&(paid - transfer_amount).to_le_bytes()),
        ],
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
        paid_state(true, paid - transfer_amount),
        "exact paid debit"
    );
}

#[test]
fn pay_success_creates_fresh_dst_ata() {
    let (mollusk, program_id) = make_product_mollusk();
    let paid = 2000u64;
    let case = PayCase::new(&program_id, paid, 2000, None);
    let result = mollusk.process_and_validate_instruction(
        &case.pay_instruction(program_id, 1000),
        &case.accounts,
        &[Check::success()],
    );
    let dst_ata = account_by_key(&result.resulting_accounts, &case.dst_ata_key);
    assert_eq!(
        dst_ata.owner,
        token_classic_program_id(),
        "ensure must assign Token owner"
    );
    assert_eq!(token_amount(&dst_ata.data), 1000, "fresh dst ATA created + credited");
    assert_eq!(
        token_amount(&account_by_key(&result.resulting_accounts, &case.vault_ata_key).data),
        1000
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &case.state_key).data,
        paid_state(true, 1000)
    );
}

#[test]
fn pay_when_paid_below_amount_skips_cpi_and_returns_paid() {
    let (mollusk, program_id) = make_product_mollusk();
    // paid=10, amount=100 → else branch: no state write, no token CPI.
    let case = PayCase::new(&program_id, 10, 2000, Some(0));
    let result = mollusk.process_and_validate_instruction(
        &case.pay_instruction(program_id, 100),
        &case.accounts,
        &[Check::success(), Check::return_data(&10u64.to_le_bytes())],
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &case.state_key).data,
        paid_state(true, 10)
    );
    assert_eq!(
        token_amount(&account_by_key(&result.resulting_accounts, &case.vault_ata_key).data),
        2000
    );
    assert_eq!(
        token_amount(&account_by_key(&result.resulting_accounts, &case.dst_ata_key).data),
        0
    );
}

#[test]
fn pay_amount_zero_asserts_custom_1002() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = PayCase::new(&program_id, 100, 2000, Some(0));
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.pay_instruction(program_id, 0),
        &case.accounts,
        Check::err(ProgramError::Custom(0x1002)),
    );
}

#[test]
fn pay_insufficient_vault_balance_full_rollback() {
    let (mollusk, program_id) = make_product_mollusk();
    // paid allows CPI path; vault has only 500 tokens.
    let case = PayCase::new(&program_id, 2000, 500, Some(0));
    let ix = case.pay_instruction(program_id, 1000);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        Check::err(ProgramError::Custom(1)),
    );
}

#[test]
fn pay_missing_caller_signer_fails_full_snapshot() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = PayCase::new(&program_id, 2000, 2000, Some(0));
    case.metas[ROLE_CALLER] = AccountMeta::new(case.caller_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.pay_instruction(program_id, 1000),
        &case.accounts,
        Check::instruction_err(InstructionError::PrivilegeEscalation),
    );
}

#[test]
fn pay_wrong_account_count_fails() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = PayCase::new(&program_id, 2000, 2000, Some(0));
    // Drop last role → multi-role walk exact-count gate (Custom 1).
    let mut metas = case.metas.clone();
    metas.pop();
    let mut accounts = case.accounts.clone();
    accounts.pop();
    let ix = Instruction::new_with_bytes(program_id, &pay_ix_data(1000), metas);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn frozen_token_and_ata_program_id_pins() {
    assert_eq!(
        hex::encode(TOKEN_CLASSIC_PROGRAM_ID_BYTES),
        "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
    );
    assert_eq!(
        hex::encode(ATA_CLASSIC_PROGRAM_ID_BYTES),
        "8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859"
    );
    assert_eq!(VAULT_SEED0, b"proof-forge:vault:v1");
    assert_eq!(MINT_DECIMALS, 9);
    let _ = BASE_LAMPORTS;
}
