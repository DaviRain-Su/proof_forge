//! # ADR-0030 E4 M4c MiniAmmAssets Mollusk dual-mint engineering pin.
//!
//! Builds `Examples/MiniAmmAssets.lean` through ordinary
//! `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! (full-body multi-role: Map Principal + multi-site `pf.assets.token.transfer`)
//! and loads the manifest-bound `MiniAmmAssets.so` into Mollusk with vendored
//! classic Token + ATA + native System.
//!
//! Product surface (EmitSbpfAsm discriminator ABI + multi-role outer accounts):
//! - multi-role entry requires **exact outerRoleCount=21** on every handler
//! - `initialize` / `addLiquidity` (LP mint, pre-fund vault ATAs off-program)
//! - `swap0to1(mint1,to,amountIn,minOut)` → vault mint1 ATA → dst mint1 ATA
//! - `removeLiquidity(mint0,mint1,to,lp)` → dual transfer
//! - views `getReserve*` / `getTotalSupply` / `balanceOf(who)`
//!
//! Pre-fund honesty (ADR-0033): user credits vault ATAs before add/swap;
//! AMM revert does not auto-refund.
//!
//! Engineering only — not formal TASK-D5 / hermetic / mainnet.
//!
//! Env (optional):
//! - `PROOF_FORGE_MINIAMM_ASSETS_OUT` — existing product output tree
//! - `PROOF_FORGE_TOOL_ROOT` — locked sbpf tool root (finalize)

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, instruction_data,
        instruction_discriminator, instruction_discriminator_with_widths, layout_marker,
        state_account, StateField, BASE_LAMPORTS, CHECK_OR_UNKNOWN, STATE_HEADER_BYTES,
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
const PROGRAM_NAME: &str = "MiniAmmAssets";
const MODULE_NAME: &str = "Examples.MiniAmmAssets";
const SOURCE_REL: &str = "Examples/MiniAmmAssets.lean";
const EXPECTED_SOURCE_HASH: &str =
    "d3cf1146ebf07b834420591f5d7ecbce1ab29cac42f92979f3bc5fc85cac57a6";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

const SCALAR_COUNT: usize = 5;
const MAP_LEAF_COUNT: usize = 44;
const TOTAL_FIELDS: usize = SCALAR_COUNT + MAP_LEAF_COUNT; // 49
const EXACT_DATA_LEN: usize = STATE_HEADER_BYTES + TOTAL_FIELDS * 8; // 400
const MAP_SLOTS: usize = 4;
const MAP_LEAVES_PER_SLOT: usize = 11;
const PRINCIPAL_LEAF_COUNT: usize = 9;
const EXPECTED_LAYOUT_MARKER_HEX: &str = "b8d352cbbfe6cd3b";

const OUTER_ROLE_COUNT: usize = 21;
const ROLE_STATE: usize = 0;
const ROLE_CALLER: usize = 1;
// Global role table (accountRoles source order) — see cpi-plan.
// 2/3 swap0to1 mint1/to; 7/8 vault/dst ATA mint1; 9 vault
// 10/11 swap1to0 mint0/to; 12/13 vault/dst ATA mint0
// 14/15/16 remove mint0/mint1/to; 17/18 vault/dst mint0; 19/20 vault/dst mint1

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
    assert_eq!(metadata.nlink(), 1, "{label}: single-link {}", path.display());
    metadata
}

fn manifest_for_cpi_product(output_dir: &Path) -> OutputManifest {
    let root_metadata = fs::symlink_metadata(output_dir)
        .unwrap_or_else(|error| panic!("output root {}: {error}", output_dir.display()));
    assert!(
        !root_metadata.file_type().is_symlink() && root_metadata.file_type().is_dir(),
        "output root must be a non-symlink directory"
    );
    let manifest_path = output_dir.join("manifest.json");
    require_regular_single_link(&manifest_path, "manifest");
    let bytes = fs::read(&manifest_path).expect("read manifest");
    let manifest: OutputManifest = serde_json::from_slice(&bytes).expect("manifest json");
    assert_eq!(manifest.schema_version, OUTPUT_SCHEMA);
    assert_eq!(manifest.target, "solana");
    assert_eq!(manifest.codegen_profile, CPI_PROFILE);
    assert_eq!(manifest.artifact_program_name, PROGRAM_NAME);
    assert_eq!(
        manifest.source_hash, EXPECTED_SOURCE_HASH,
        "product tree must stay bound to tracked MiniAmmAssets source"
    );
    assert!(manifest.deployable);
    for value in [
        &manifest.source_hash,
        &manifest.semantic_hash,
        &manifest.build_identity_digest,
        &manifest.plan_digest,
        &manifest.support_claim_digest,
        &manifest.engineering_registry_root_digest,
        &manifest.output_set_digest,
        &manifest.evidence_sha256,
    ] {
        assert!(is_lower_hex_64(value));
    }
    let expected = [
        (format!("{PROGRAM_NAME}.cpi-bindings.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.cpi-ir.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.cpi-plan.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.idl.json"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.s"), MATERIALIZED_BASE),
        (format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA),
    ];
    assert_eq!(manifest.files.len(), expected.len());
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
        .expect("read dir")
        .map(|e| e.expect("entry").file_name().into_string().expect("utf8"))
        .collect();
    actual_physical.sort();
    assert_eq!(actual_physical, expected_physical);
    for name in &actual_physical {
        require_regular_single_link(&output_dir.join(name), "closure leaf");
    }
    let evidence = fs::read(output_dir.join("evidence.json")).expect("evidence");
    assert_eq!(hex::encode(Sha256::digest(&evidence)), manifest.evidence_sha256);
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
        .filter(|d| d.path == relative_path)
        .collect();
    assert_eq!(matches.len(), 1);
    let descriptor = matches[0];
    assert_eq!(descriptor.role, expected_role);
    let path = output_dir.join(relative_path);
    let before = require_regular_single_link(&path, "artifact");
    assert_eq!(before.len(), descriptor.size);
    let bytes = fs::read(&path).expect("read artifact");
    let after = require_regular_single_link(&path, "artifact post-read");
    assert!(
        before.dev() == after.dev()
            && before.ino() == after.ino()
            && before.len() == after.len()
            && before.mtime() == after.mtime()
            && before.mtime_nsec() == after.mtime_nsec()
    );
    assert_eq!(bytes.len() as u64, descriptor.size);
    assert_eq!(hex::encode(Sha256::digest(&bytes)), descriptor.content_sha256);
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
        other => panic!("unsupported host OS: {other}"),
    }
}

fn ensure_product_output() -> PathBuf {
    static OUT: OnceLock<PathBuf> = OnceLock::new();
    OUT.get_or_init(|| {
        if let Ok(existing) = env::var("PROOF_FORGE_MINIAMM_ASSETS_OUT") {
            let path = PathBuf::from(existing);
            let _ = read_manifest_leaf_bytes(
                &path,
                &format!("{PROGRAM_NAME}.so"),
                FINALIZED_EXTRA,
            );
            return path;
        }
        let root = repo_root();
        let out = root.join("build/v2/solana-miniamm-assets");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file()
        {
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }
        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior MiniAmmAssets out");
        }
        fs::create_dir_all(out.parent().expect("parent")).expect("mkdir");
        let tool_root = env::var("PROOF_FORGE_TOOL_ROOT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| default_tool_root());
        assert!(
            tool_root.join("sbpf").is_file(),
            "sbpf missing under {}",
            tool_root.display()
        );
        let cli = root.join(".lake/build/bin/proof-forge-next");
        assert!(cli.is_file(), "proof-forge-next missing; lake build proof_forge_next");
        let source = root.join(SOURCE_REL);
        assert!(source.is_file(), "missing {}", source.display());
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
        assert!(status.success(), "product CLI build failed for MiniAmmAssets");
        let elf = read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA);
        assert!(elf.starts_with(b"\x7fELF"));
        let asm_bytes = read_manifest_leaf_bytes(
            &out,
            &format!("{PROGRAM_NAME}.s"),
            MATERIALIZED_BASE,
        );
        let asm = String::from_utf8_lossy(&asm_bytes);
        assert!(asm.contains("product_mr_token_0"));
        assert!(asm.contains("product_mr_token_3"));
        assert!(asm.contains(".equ ROLE_BASE, 0x540"));
        assert!(!asm.contains("TEST-PREACTIVATION"));
        let ir_bytes = read_manifest_leaf_bytes(
            &out,
            &format!("{PROGRAM_NAME}.cpi-ir.json"),
            MATERIALIZED_BASE,
        );
        let ir = String::from_utf8_lossy(&ir_bytes);
        assert!(ir.contains("m4b-token-transfer-multi-role"));
        assert!(ir.contains("\"outerRoleCount\":21"));
        assert!(ir.contains("\"cpiSites\":4"));
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    Pubkey::new_from_array([0x5d; 32])
}

fn token_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_CLASSIC_PROGRAM_ID_BYTES)
}

fn ata_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(ATA_CLASSIC_PROGRAM_ID_BYTES)
}

fn read_vendored_token_elf() -> Vec<u8> {
    let path = repo_root().join("runtime-tests/solana/token/token_classic_v1.so");
    let committed = fs::read(&path).expect("Token ELF");
    assert_eq!(committed.len() as u64, 94960);
    assert_eq!(
        hex::encode(Sha256::digest(&committed)),
        "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"
    );
    committed
}

fn read_vendored_ata_elf() -> Vec<u8> {
    let path = repo_root().join("runtime-tests/solana/ata/ata_classic_v1.so");
    let committed = fs::read(&path).expect("ATA ELF");
    assert_eq!(committed.len() as u64, 111136);
    assert_eq!(
        hex::encode(Sha256::digest(&committed)),
        "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"
    );
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

fn balance_leaf_names() -> &'static [&'static str] {
    static NAMES: OnceLock<Vec<&'static str>> = OnceLock::new();
    NAMES
        .get_or_init(|| {
            (0..MAP_LEAF_COUNT)
                .map(|i| Box::leak(format!("balances_{i}").into_boxed_str()) as &'static str)
                .collect()
        })
        .as_slice()
}

fn miniamm_fields() -> Vec<StateField> {
    let mut fields = Vec::with_capacity(TOTAL_FIELDS);
    let scalars: [(&'static str, u64); 5] = [
        ("reserve0", 0),
        ("reserve1", 1),
        ("totalSupply", 2),
        ("scratch", 3),
        ("scratch2", 4),
    ];
    for (i, (name, sid)) in scalars.iter().enumerate() {
        fields.push(StateField {
            source_id: *sid,
            name,
            byte_offset: STATE_HEADER_BYTES + i * 8,
            byte_width: 8,
        });
    }
    for (i, name) in balance_leaf_names().iter().enumerate() {
        fields.push(StateField {
            source_id: 5,
            name,
            byte_offset: STATE_HEADER_BYTES + (SCALAR_COUNT + i) * 8,
            byte_width: 8,
        });
    }
    assert_eq!(fields.len(), TOTAL_FIELDS);
    fields
}

fn layout_marker_u64() -> u64 {
    let marker = layout_marker(&miniamm_fields());
    assert_eq!(format!("{marker:016x}"), EXPECTED_LAYOUT_MARKER_HEX);
    marker
}

fn principal_leaves_from_pubkey(key: &Pubkey) -> [u64; PRINCIPAL_LEAF_COUNT] {
    let mut leaves = [0u64; PRINCIPAL_LEAF_COUNT];
    leaves[0] = 32;
    let bytes = key.to_bytes();
    for i in 0..4 {
        let mut word = [0u8; 8];
        word.copy_from_slice(&bytes[i * 8..(i + 1) * 8]);
        leaves[1 + i] = u64::from_le_bytes(word);
    }
    leaves
}

fn empty_initialized_state() -> Vec<u8> {
    let mut data = vec![0u8; EXACT_DATA_LEN];
    data[..8].copy_from_slice(&layout_marker_u64().to_le_bytes());
    data
}

fn uninitialized_state() -> Vec<u8> {
    vec![0u8; EXACT_DATA_LEN]
}

fn state_with(
    reserve0: u64,
    reserve1: u64,
    total_supply: u64,
    scratch: u64,
    scratch2: u64,
    entries: &[([u64; PRINCIPAL_LEAF_COUNT], u64)],
) -> Vec<u8> {
    assert!(entries.len() <= MAP_SLOTS);
    let mut data = empty_initialized_state();
    data[8..16].copy_from_slice(&reserve0.to_le_bytes());
    data[16..24].copy_from_slice(&reserve1.to_le_bytes());
    data[24..32].copy_from_slice(&total_supply.to_le_bytes());
    data[32..40].copy_from_slice(&scratch.to_le_bytes());
    data[40..48].copy_from_slice(&scratch2.to_le_bytes());
    let map_base = STATE_HEADER_BYTES + SCALAR_COUNT * 8;
    for (slot, (key_leaves, val)) in entries.iter().enumerate() {
        let base = map_base + slot * MAP_LEAVES_PER_SLOT * 8;
        data[base..base + 8].copy_from_slice(&1u64.to_le_bytes());
        for (i, leaf) in key_leaves.iter().enumerate() {
            let off = base + 8 + i * 8;
            data[off..off + 8].copy_from_slice(&leaf.to_le_bytes());
        }
        let val_off = base + 8 + PRINCIPAL_LEAF_COUNT * 8;
        data[val_off..val_off + 8].copy_from_slice(&val.to_le_bytes());
    }
    data
}

fn read_u64_le(data: &[u8], off: usize) -> u64 {
    u64::from_le_bytes(data[off..off + 8].try_into().unwrap())
}

fn find_vault_pda(program_id: &Pubkey) -> (Pubkey, u8) {
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[VAULT_SEED0, &bump_slice];
        if let Ok(addr) = Pubkey::create_program_address(seeds, program_id) {
            return (addr, bump);
        }
    }
    panic!("no vault PDA bump");
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

// --- discriminators (LowerSemantic formula; Principal = 9×u64 leaves) ---

fn disc_initialize() -> String {
    instruction_discriminator("initialize", 0)
}
fn disc_add_liquidity() -> String {
    instruction_discriminator("addLiquidity", 2)
}
fn disc_swap0to1() -> String {
    instruction_discriminator_with_widths("swap0to1", &vec![8usize; PRINCIPAL_LEAF_COUNT * 2 + 2])
}
fn disc_swap1to0() -> String {
    instruction_discriminator_with_widths("swap1to0", &vec![8usize; PRINCIPAL_LEAF_COUNT * 2 + 2])
}
fn disc_remove_liquidity() -> String {
    instruction_discriminator_with_widths(
        "removeLiquidity",
        &vec![8usize; PRINCIPAL_LEAF_COUNT * 3 + 1],
    )
}
fn disc_get_reserve0() -> String {
    instruction_discriminator("getReserve0", 0)
}
fn disc_get_reserve1() -> String {
    instruction_discriminator("getReserve1", 0)
}
fn disc_get_total_supply() -> String {
    instruction_discriminator("getTotalSupply", 0)
}
fn disc_balance_of() -> String {
    instruction_discriminator_with_widths("balanceOf", &vec![8usize; PRINCIPAL_LEAF_COUNT])
}

fn ix_data_swap(amount_in: u64, amount_out_min: u64) -> Vec<u8> {
    // disc + 18 Principal zero leaves + amountIn + amountOutMin
    let mut leaves = vec![0u64; PRINCIPAL_LEAF_COUNT * 2 + 2];
    leaves[PRINCIPAL_LEAF_COUNT * 2] = amount_in;
    leaves[PRINCIPAL_LEAF_COUNT * 2 + 1] = amount_out_min;
    instruction_data(&disc_swap0to1(), &leaves)
}

fn ix_data_swap1to0(amount_in: u64, amount_out_min: u64) -> Vec<u8> {
    let mut leaves = vec![0u64; PRINCIPAL_LEAF_COUNT * 2 + 2];
    leaves[PRINCIPAL_LEAF_COUNT * 2] = amount_in;
    leaves[PRINCIPAL_LEAF_COUNT * 2 + 1] = amount_out_min;
    instruction_data(&disc_swap1to0(), &leaves)
}

fn ix_data_remove(lp_amount: u64) -> Vec<u8> {
    let mut leaves = vec![0u64; PRINCIPAL_LEAF_COUNT * 3 + 1];
    leaves[PRINCIPAL_LEAF_COUNT * 3] = lp_amount;
    instruction_data(&disc_remove_liquidity(), &leaves)
}

fn ix_data_balance_of(who: &Pubkey) -> Vec<u8> {
    instruction_data(&disc_balance_of(), &principal_leaves_from_pubkey(who))
}

/// Unique 32-byte key for multi-role non-dup ABIv1 slots (marker 0xff requires
/// pairwise-distinct outer keys — cannot reuse the same pubkey in two roles).
fn unique_role_key(slot: usize) -> Pubkey {
    let mut b = [0u8; 32];
    b[0] = 0xA0;
    b[1] = slot as u8;
    b[2] = 0x5A;
    b[3] = (slot as u8).wrapping_mul(17);
    b[31] = 0xEE;
    Pubkey::new_from_array(b)
}

/// Full 21-role outer vector: every role has a **distinct** pubkey (multi-role
/// walk rejects Solana account aliasing). Per-handler, overwrite only the
/// slots that handler's CPI/caller path needs with real mint/ATA/vault keys.
struct World {
    state_key: Pubkey,
    caller_key: Pubkey,
    mint0_key: Pubkey,
    mint1_key: Pubkey,
    to_key: Pubkey,
    vault_key: Pubkey,
    vault_ata0: Pubkey,
    vault_ata1: Pubkey,
    dst_ata0: Pubkey,
    dst_ata1: Pubkey,
    /// Dense roleId → pubkey (always length 21, all distinct).
    role_keys: [Pubkey; OUTER_ROLE_COUNT],
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl World {
    /// Base world: state + caller + programs + vault PDA + dual mint ATAs funded.
    /// Role slots start unique; call `wire_swap0`, `wire_remove`, etc. to map
    /// real keys into the slots that handler uses.
    fn new(program_id: &Pubkey, state: Account, vault0_amt: u64, vault1_amt: u64) -> Self {
        let state_key = fixed_key(0x70);
        let caller_key = fixed_key(0x71);
        let mint0_key = fixed_key(0x72);
        let mint1_key = fixed_key(0x73);
        let to_key = fixed_key(0x74);
        let (vault_key, _) = find_vault_pda(program_id);
        let (vault_ata0, _) = find_ata(&vault_key, &mint0_key);
        let (vault_ata1, _) = find_ata(&vault_key, &mint1_key);
        let (dst_ata0, _) = find_ata(&to_key, &mint0_key);
        let (dst_ata1, _) = find_ata(&to_key, &mint1_key);

        let (system_key, system) = common::system_program_keyed_account();
        let token_key = token_classic_program_id();
        let ata_key = ata_classic_program_id();

        // 21 pairwise-distinct keys (required by multi-role non-dup walk).
        let mut role_keys: [Pubkey; OUTER_ROLE_COUNT] =
            std::array::from_fn(unique_role_key);
        role_keys[0] = state_key;
        role_keys[1] = caller_key;
        role_keys[4] = system_key;
        role_keys[5] = ata_key;
        role_keys[6] = token_key;
        role_keys[9] = vault_key;

        let mint0 = token_owner_account(
            4_000_000,
            pack_classic_mint(&vault_key, 1_000_000, MINT_DECIMALS),
        );
        let mint1 = token_owner_account(
            4_000_000,
            pack_classic_mint(&vault_key, 1_000_000, MINT_DECIMALS),
        );
        let vault_ata0_acc = token_owner_account(
            4_000_000,
            pack_classic_token_account(&mint0_key, &vault_key, vault0_amt),
        );
        let vault_ata1_acc = token_owner_account(
            4_000_000,
            pack_classic_token_account(&mint1_key, &vault_key, vault1_amt),
        );
        let dst_ata0_acc = token_owner_account(
            4_000_000,
            pack_classic_token_account(&mint0_key, &to_key, 0),
        );
        let dst_ata1_acc = token_owner_account(
            4_000_000,
            pack_classic_token_account(&mint1_key, &to_key, 0),
        );

        let mut accounts: Vec<(Pubkey, Account)> = role_keys
            .iter()
            .map(|&k| (k, Account::new(1_000_000, 0, &Pubkey::default())))
            .collect();
        // Overlay real accounts by key.
        let overlays = vec![
            (state_key, state),
            (caller_key, Account::new(20_000_000, 0, &Pubkey::default())),
            (system_key, system),
            (
                ata_key,
                create_program_account_loader_v3(&ata_key),
            ),
            (
                token_key,
                create_program_account_loader_v3(&token_key),
            ),
            (vault_key, Account::new(890_880, 0, program_id)),
            (mint0_key, mint0),
            (mint1_key, mint1),
            (vault_ata0, vault_ata0_acc),
            (vault_ata1, vault_ata1_acc),
            (dst_ata0, dst_ata0_acc),
            (dst_ata1, dst_ata1_acc),
            (to_key, Account::new(2_000_000, 0, &Pubkey::default())),
        ];
        for (k, a) in overlays {
            if let Some((_, slot)) = accounts.iter_mut().find(|(kk, _)| *kk == k) {
                *slot = a;
            } else {
                accounts.push((k, a));
            }
        }

        let metas: Vec<AccountMeta> = role_keys
            .iter()
            .enumerate()
            .map(|(i, k)| {
                // Default: readonly non-signer; callers specialize.
                if i == ROLE_STATE {
                    AccountMeta::new(*k, false)
                } else if i == ROLE_CALLER {
                    AccountMeta::new(*k, true)
                } else if i == 7 || i == 8 || i == 12 || i == 13 || i == 17 || i == 18 || i == 19
                    || i == 20
                {
                    AccountMeta::new(*k, false)
                } else {
                    AccountMeta::new_readonly(*k, false)
                }
            })
            .collect();

        assert_eq!(metas.len(), OUTER_ROLE_COUNT);
        // pairwise distinct
        for i in 0..OUTER_ROLE_COUNT {
            for j in (i + 1)..OUTER_ROLE_COUNT {
                assert_ne!(
                    role_keys[i], role_keys[j],
                    "role keys must be pairwise distinct for multi-role non-dup walk"
                );
            }
        }

        Self {
            state_key,
            caller_key,
            mint0_key,
            mint1_key,
            to_key,
            vault_key,
            vault_ata0,
            vault_ata1,
            dst_ata0,
            dst_ata1,
            role_keys,
            metas,
            accounts,
        }
    }

    fn set_role_key(&mut self, role: usize, key: Pubkey, writable: bool, signer: bool) {
        let old = self.role_keys[role];
        self.role_keys[role] = key;
        self.metas[role] = if writable {
            AccountMeta::new(key, signer)
        } else {
            AccountMeta::new_readonly(key, signer)
        };
        // Ensure accounts vec has the key (may already exist from overlays).
        if !self.accounts.iter().any(|(k, _)| *k == key) {
            // migrate dummy account if needed
            if let Some((_, acc)) = self.accounts.iter().find(|(k, _)| *k == old) {
                let a = acc.clone();
                self.accounts.push((key, a));
            }
        }
    }

    /// Wire roles used by swap0to1 CPI: mint1/to/vault_ata1/dst_ata1 (+ shared).
    fn wire_swap0(&mut self) {
        self.set_role_key(2, self.mint1_key, false, false);
        self.set_role_key(3, self.to_key, false, false);
        self.set_role_key(7, self.vault_ata1, true, false);
        self.set_role_key(8, self.dst_ata1, true, false);
        self.set_role_key(9, self.vault_key, false, false);
        self.metas[ROLE_CALLER] = AccountMeta::new(self.caller_key, true);
        self.assert_distinct();
    }

    /// Wire roles used by removeLiquidity dual CPI.
    fn wire_remove(&mut self) {
        self.set_role_key(14, self.mint0_key, false, false);
        self.set_role_key(15, self.mint1_key, false, false);
        self.set_role_key(16, self.to_key, false, false);
        self.set_role_key(17, self.vault_ata0, true, false);
        self.set_role_key(18, self.dst_ata0, true, false);
        self.set_role_key(19, self.vault_ata1, true, false);
        self.set_role_key(20, self.dst_ata1, true, false);
        self.set_role_key(9, self.vault_key, false, false);
        self.metas[ROLE_CALLER] = AccountMeta::new(self.caller_key, true);
        self.assert_distinct();
    }

    fn assert_distinct(&self) {
        for i in 0..OUTER_ROLE_COUNT {
            for j in (i + 1)..OUTER_ROLE_COUNT {
                assert_ne!(
                    self.role_keys[i], self.role_keys[j],
                    "roles {i} and {j} collided after wire"
                );
            }
        }
    }

    fn with_state_signer(mut self, signer: bool, writable: bool) -> Self {
        self.metas[ROLE_STATE] = if writable {
            AccountMeta::new(self.state_key, signer)
        } else {
            AccountMeta::new_readonly(self.state_key, signer)
        };
        self
    }

    fn replace_state(&mut self, state: Account) {
        if let Some((_, a)) = self.accounts.iter_mut().find(|(k, _)| *k == self.state_key) {
            *a = state;
        }
    }

    fn accounts_for_mollusk(&self) -> Vec<(Pubkey, Account)> {
        // One entry per role key in order; pull Account from map (clone).
        self.role_keys
            .iter()
            .map(|k| {
                let acc = self
                    .accounts
                    .iter()
                    .find(|(kk, _)| kk == k)
                    .map(|(_, a)| a.clone())
                    .unwrap_or_else(|| Account::new(1_000_000, 0, &Pubkey::default()));
                (*k, acc)
            })
            .collect()
    }
}

fn oracle_swap0to1(amount_in: u64, reserve0: u64, reserve1: u64) -> u64 {
    amount_in
        .checked_mul(reserve1)
        .unwrap()
        .checked_div(reserve0.checked_add(amount_in).unwrap())
        .unwrap()
}

fn oracle_remove_amount0(lp: u64, reserve0: u64, total: u64) -> u64 {
    lp.checked_mul(reserve0).unwrap().checked_div(total).unwrap()
}

fn oracle_remove_amount1(lp: u64, reserve1: u64, total: u64) -> u64 {
    lp.checked_mul(reserve1).unwrap().checked_div(total).unwrap()
}

// ---------------------------------------------------------------------------
// Product tree pin
// ---------------------------------------------------------------------------

#[test]
fn product_tree_is_manifest_bound_multi_role_dual_mint() {
    let out = ensure_product_output();
    let manifest = manifest_for_cpi_product(&out);
    assert_eq!(manifest.artifact_program_name, PROGRAM_NAME);
    assert!(manifest.deployable);

    let plan_bytes = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-plan.json"),
        MATERIALIZED_BASE,
    );
    let plan: serde_json::Value = serde_json::from_slice(&plan_bytes).unwrap();
    assert_eq!(plan["profileId"], serde_json::json!(CPI_PROFILE));
    assert_eq!(plan["programName"], serde_json::json!(PROGRAM_NAME));
    let roles = plan["accountRoles"].as_array().unwrap();
    assert_eq!(roles.len(), OUTER_ROLE_COUNT);
    let sites = plan["cpiSites"].as_array().unwrap();
    assert_eq!(sites.len(), 4);
    let schemas = plan["stateSchemas"].as_array().unwrap();
    assert_eq!(schemas[0]["exactDataLen"], serde_json::json!(EXACT_DATA_LEN));
    assert_eq!(
        schemas[0]["initializedMarker"],
        serde_json::json!(EXPECTED_LAYOUT_MARKER_HEX)
    );

    let ir_bytes = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-ir.json"),
        MATERIALIZED_BASE,
    );
    let ir = String::from_utf8_lossy(&ir_bytes);
    assert!(ir.contains("m4b-token-transfer-multi-role"));
    assert!(ir.contains("\"outerRoleCount\":21"));
    assert!(ir.contains("\"cpiSites\":4"));
    assert!(ir.contains("unifiedCpi"));

    let asm_bytes = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.s"),
        MATERIALIZED_BASE,
    );
    let asm = String::from_utf8_lossy(&asm_bytes);
    assert!(asm.contains("product_mr_token_0"));
    assert!(asm.contains("product_mr_token_3"));
    assert!(asm.contains(".equ ROLE_BASE, 0x540"));
    assert!(asm.contains("handler addLiquidity (temps=102)"));
    assert!(asm.contains("handler removeLiquidity (temps=102)"));
}

#[test]
fn independent_layout_marker_matches_plan() {
    assert_eq!(format!("{:016x}", layout_marker_u64()), EXPECTED_LAYOUT_MARKER_HEX);
    assert_eq!(EXACT_DATA_LEN, 400);
}

// ---------------------------------------------------------------------------
// Runtime matrix
// ---------------------------------------------------------------------------

#[test]
fn initialize_then_add_liquidity_mints_lp() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut world = World::new(
        &program_id,
        state_account(&program_id, uninitialized_state()),
        0,
        0,
    )
    .with_state_signer(true, true);

    // init
    let init_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_initialize(), &[]),
        world.metas.clone(),
    );
    let init_res = mollusk.process_and_validate_instruction(
        &init_ix,
        &world.accounts_for_mollusk(),
        &[Check::success()],
    );
    let state_after_init = account_by_key(&init_res.resulting_accounts, &world.state_key)
        .data
        .clone();
    assert_eq!(&state_after_init[..8], &layout_marker_u64().to_le_bytes());
    assert_eq!(read_u64_le(&state_after_init, 8), 0);

    // Pre-fund vault ATAs then addLiquidity(1000,2000) first mint → LP=1000
    world.replace_state(state_account(&program_id, state_after_init));
    // Rebuild vault ATAs with funding — construct new world from funded state
    let mut funded = World::new(
        &program_id,
        state_account(&program_id, empty_initialized_state()),
        1000,
        2000,
    )
    .with_state_signer(false, true);
    // state writable, caller signer for ATA ensure (not needed on addLiquidity path)
    funded.metas[ROLE_CALLER] = AccountMeta::new(funded.caller_key, true);

    let add_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_add_liquidity(), &[1000, 2000]),
        funded.metas.clone(),
    );
    let add_res = mollusk.process_and_validate_instruction(
        &add_ix,
        &funded.accounts_for_mollusk(),
        &[
            Check::success(),
            Check::return_data(&1000u64.to_le_bytes()),
        ],
    );
    let st = &account_by_key(&add_res.resulting_accounts, &funded.state_key).data;
    assert_eq!(read_u64_le(st, 8), 1000, "reserve0");
    assert_eq!(read_u64_le(st, 16), 2000, "reserve1");
    assert_eq!(read_u64_le(st, 24), 1000, "totalSupply first mint = amount0");
    // LP map entry for caller
    let caller_leaves = principal_leaves_from_pubkey(&funded.caller_key);
    let map_base = STATE_HEADER_BYTES + SCALAR_COUNT * 8;
    assert_eq!(read_u64_le(st, map_base), 1, "occ");
    assert_eq!(read_u64_le(st, map_base + 8), caller_leaves[0]);
    assert_eq!(read_u64_le(st, map_base + 8 + PRINCIPAL_LEAF_COUNT * 8), 1000);
}

#[test]
fn swap0to1_pays_mint1_and_updates_reserves() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller = fixed_key(0x71);
    let caller_leaves = principal_leaves_from_pubkey(&caller);
    // Pre-state: reserves 1000/2000, LP 1000 for caller; vault has mint1 for payout
    let pre = state_with(1000, 2000, 1000, 0, 0, &[(caller_leaves, 1000)]);
    let amount_in = 100u64;
    let out = oracle_swap0to1(amount_in, 1000, 2000);
    assert!(out > 0 && out < 2000);

    // Vault mint1 must hold enough for transfer out; vault mint0 unused on this swap
    // Pre-fund: user already credited amount_in of mint0 off-program into vault_ata0
    // (declared amountIn). Vault mint1 pays `out`.
    let mut world = World::new(
        &program_id,
        state_account(&program_id, pre),
        amount_in, // vault0 pre-funded (declared)
        2000,      // vault1 has reserve-like stock for payout
    )
    .with_state_signer(false, true);
    // Map swap0to1 site roles onto real mint1/to/vault_ata1/dst_ata1 (ATA seeds).
    world.wire_swap0();

    let ix = Instruction::new_with_bytes(
        program_id,
        &ix_data_swap(amount_in, out), // minOut = exact oracle
        world.metas.clone(),
    );
    let res = mollusk.process_and_validate_instruction(
        &ix,
        &world.accounts_for_mollusk(),
        &[
            Check::success(),
            Check::return_data(&out.to_le_bytes()),
        ],
    );
    let st = &account_by_key(&res.resulting_accounts, &world.state_key).data;
    assert_eq!(read_u64_le(st, 8), 1000 + amount_in, "reserve0");
    assert_eq!(read_u64_le(st, 16), 2000 - out, "reserve1");
    assert_eq!(
        token_amount(&account_by_key(&res.resulting_accounts, &world.vault_ata1).data),
        2000 - out,
        "vault mint1 debited"
    );
    assert_eq!(
        token_amount(&account_by_key(&res.resulting_accounts, &world.dst_ata1).data),
        out,
        "dst mint1 credited"
    );
}

#[test]
fn swap0to1_slippage_min_out_reverts_full_snapshot() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller = fixed_key(0x71);
    let pre = state_with(
        1000,
        2000,
        1000,
        0,
        0,
        &[(principal_leaves_from_pubkey(&caller), 1000)],
    );
    let amount_in = 100u64;
    let out = oracle_swap0to1(amount_in, 1000, 2000);
    let world = World::new(
        &program_id,
        state_account(&program_id, pre),
        amount_in,
        2000,
    )
    .with_state_signer(false, true);
    // minOut = out+1 → assert failure before CPI
    let ix = Instruction::new_with_bytes(
        program_id,
        &ix_data_swap(amount_in, out + 1),
        world.metas.clone(),
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &world.accounts_for_mollusk(),
        Check::err(ProgramError::Custom(0x1002)),
    );
}

#[test]
fn remove_liquidity_dual_transfer() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller = fixed_key(0x71);
    let caller_leaves = principal_leaves_from_pubkey(&caller);
    let reserve0 = 1000u64;
    let reserve1 = 2000u64;
    let total = 1000u64;
    let lp = 250u64;
    let out0 = oracle_remove_amount0(lp, reserve0, total);
    let out1 = oracle_remove_amount1(lp, reserve1, total);
    let pre = state_with(reserve0, reserve1, total, 0, 0, &[(caller_leaves, total)]);
    let mut world = World::new(
        &program_id,
        state_account(&program_id, pre),
        reserve0,
        reserve1,
    )
    .with_state_signer(false, true);
    // Dual-mint remove: real mint0/mint1/to + vault/dst ATAs on roles 14..20.
    world.wire_remove();

    let ix = Instruction::new_with_bytes(
        program_id,
        &ix_data_remove(lp),
        world.metas.clone(),
    );
    let res = mollusk.process_and_validate_instruction(
        &ix,
        &world.accounts_for_mollusk(),
        &[
            Check::success(),
            Check::return_data(&out0.to_le_bytes()),
        ],
    );
    let st = &account_by_key(&res.resulting_accounts, &world.state_key).data;
    assert_eq!(read_u64_le(st, 8), reserve0 - out0);
    assert_eq!(read_u64_le(st, 16), reserve1 - out1);
    assert_eq!(read_u64_le(st, 24), total - lp);
    assert_eq!(
        token_amount(&account_by_key(&res.resulting_accounts, &world.dst_ata0).data),
        out0,
        "dst mint0"
    );
    assert_eq!(
        token_amount(&account_by_key(&res.resulting_accounts, &world.dst_ata1).data),
        out1,
        "dst mint1"
    );
    assert_eq!(
        token_amount(&account_by_key(&res.resulting_accounts, &world.vault_ata0).data),
        reserve0 - out0
    );
    assert_eq!(
        token_amount(&account_by_key(&res.resulting_accounts, &world.vault_ata1).data),
        reserve1 - out1
    );
}

#[test]
fn views_read_reserves_and_balance_of() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller = fixed_key(0x71);
    let pre = state_with(
        111,
        222,
        333,
        0,
        0,
        &[(principal_leaves_from_pubkey(&caller), 333)],
    );
    let world = World::new(
        &program_id,
        state_account(&program_id, pre),
        0,
        0,
    )
    .with_state_signer(false, false);

    for (disc, expected) in [
        (disc_get_reserve0(), 111u64),
        (disc_get_reserve1(), 222u64),
        (disc_get_total_supply(), 333u64),
    ] {
        let ix = Instruction::new_with_bytes(
            program_id,
            &instruction_data(&disc, &[]),
            world.metas.clone(),
        );
        mollusk.process_and_validate_instruction(
            &ix,
            &world.accounts_for_mollusk(),
            &[
                Check::success(),
                Check::return_data(&expected.to_le_bytes()),
            ],
        );
    }

    let bal_ix = Instruction::new_with_bytes(
        program_id,
        &ix_data_balance_of(&caller),
        world.metas.clone(),
    );
    mollusk.process_and_validate_instruction(
        &bal_ix,
        &world.accounts_for_mollusk(),
        &[
            Check::success(),
            Check::return_data(&333u64.to_le_bytes()),
        ],
    );
}

#[test]
fn wrong_account_count_fails() {
    let (mollusk, program_id) = make_product_mollusk();
    let world = World::new(
        &program_id,
        state_account(&program_id, empty_initialized_state()),
        0,
        0,
    );
    let mut metas = world.metas.clone();
    metas.pop();
    let accounts = world.accounts_for_mollusk();
    // Dropping a meta is enough for count mismatch even if accounts list is longer.
    let ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_get_reserve0(), &[]),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn add_liquidity_zero_amount_asserts() {
    let (mollusk, program_id) = make_product_mollusk();
    let world = World::new(
        &program_id,
        state_account(&program_id, empty_initialized_state()),
        1000,
        1000,
    )
    .with_state_signer(false, true);
    let ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_add_liquidity(), &[0, 1000]),
        world.metas.clone(),
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &world.accounts_for_mollusk(),
        Check::err(ProgramError::Custom(0x1002)),
    );
}

#[test]
fn frozen_token_ata_program_pins() {
    assert_eq!(
        hex::encode(TOKEN_CLASSIC_PROGRAM_ID_BYTES),
        "06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9"
    );
    assert_eq!(
        hex::encode(ATA_CLASSIC_PROGRAM_ID_BYTES),
        "8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859"
    );
    assert_eq!(VAULT_SEED0, b"proof-forge:vault:v1");
    let _ = BASE_LAMPORTS;
    let _ = InstructionError::PrivilegeEscalation;
}
