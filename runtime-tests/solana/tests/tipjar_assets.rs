//! # ADR-0029 Phase B1 TipJarAssets Mollusk product acceptance.
//!
//! Builds `runtime-tests/solana/fixtures/TipJarAssets.lean` through ordinary
//! `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! and loads **only** the manifest-bound `TipJarAssets.so` into Mollusk with
//! the native System program (`Mollusk::default()`).
//!
//! Product surface (stateful CPI + pf.assets):
//! - `init(initial)` handlerId=0, ix = handlerId u64 LE + initial u64 LE (16 B)
//! - `tip(dst, amount)` handlerId=1, ix = handlerId u64 LE + amount u64 LE (16 B)
//!   Principal `dst` is account-bound (role `tip_dst`); amount is the sole
//!   non-Principal param.
//! - `get()` handlerId=2, ix = handlerId u64 LE (8 B)
//! - tip outer roles (dense): state, tip_dst, system_v1, pf_caller (sole outer
//!   signer), pf_vault (canonical PDA seeds `proof-forge:vault:v1` + bump 255..1)
//!
//! Env (optional):
//! - `PROOF_FORGE_TIPJAR_ASSETS_OUT` — existing product output tree; when unset
//!   the test builds into `build/v2/solana-tipjar-assets` (or reuses a script-
//!   prebuilt tree under that path).
//! - `PROOF_FORGE_TOOL_ROOT` — locked sbpf tool root (finalize).

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, single_field, state_account, state_data,
        system_program_keyed_account, unused_system_create_target_account, BASE_LAMPORTS,
        CHECK_OR_UNKNOWN, SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
    },
    mollusk_svm::{result::Check, Mollusk},
    serde::Deserialize,
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{
        collections::BTreeMap,
        env, fs,
        os::unix::fs::MetadataExt,
        path::{Path, PathBuf},
        process::Command,
        sync::OnceLock,
    },
};

const OUTPUT_SCHEMA: &str = "proof-forge.output.v1";
const CPI_PROFILE: &str = "solana-sbpf-cpi-elf-v1";
const PROGRAM_NAME: &str = "TipJarAssets";
const MODULE_NAME: &str = "Examples.TipJarAssets";
const SOURCE_REL: &str = "runtime-tests/solana/fixtures/TipJarAssets.lean";
/// Canonical ProgramV1 source identity for the tracked fixture above.
const EXPECTED_SOURCE_HASH: &str =
    "cd0e3215bbf007208ccc70bb86da2dcf7c95a10f08506221ea8d8b89048768d1";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

const INIT_HANDLER_ID: u64 = 0;
const TIP_HANDLER_ID: u64 = 1;
const GET_HANDLER_ID: u64 = 2;

const INIT_IX_LEN: usize = 16;
const TIP_IX_LEN: usize = 16;
const GET_IX_LEN: usize = 8;

/// ADR-0029 B1 vault seed0: ASCII `proof-forge:vault:v1`.
const VAULT_SEED0: &[u8] = b"proof-forge:vault:v1";
/// Frozen rent-exempt lamports for zero-data vault account.
const VAULT_RENT_EXEMPT_LAMPORTS: u64 = 890_880;

// tip outer role positions
const ROLE_DST: usize = 1;
const ROLE_CALLER: usize = 3;
const ROLE_VAULT: usize = 4;
const TIP_OUTER_ROLE_COUNT: usize = 5;

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
    assert_eq!(
        manifest.schema_version, OUTPUT_SCHEMA,
        "manifest schema must be proof-forge.output.v1"
    );
    assert_eq!(manifest.target, "solana");
    assert_eq!(
        manifest.codegen_profile, CPI_PROFILE,
        "product CPI profile binding"
    );
    assert_eq!(manifest.artifact_program_name, PROGRAM_NAME);
    assert_eq!(
        manifest.source_hash, EXPECTED_SOURCE_HASH,
        "product output must remain bound to the tracked TipJarAssets source"
    );
    assert!(
        manifest.deployable,
        "product CPI artifact must be deployable"
    );
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
        assert_eq!(
            descriptor.path.as_str(),
            path.as_str(),
            "manifest path order"
        );
        assert_eq!(
            descriptor.role.as_str(),
            *role,
            "manifest role order for {path}"
        );
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

    let mut descriptors: BTreeMap<&str, &ArtifactDescriptor> = BTreeMap::new();
    for descriptor in &manifest.files {
        assert!(
            is_lower_hex_64(&descriptor.content_sha256),
            "contentSha256 for {:?} must be 64 lowercase hex",
            descriptor.path
        );
        assert!(
            descriptors
                .insert(descriptor.path.as_str(), descriptor)
                .is_none(),
            "duplicate artifact path {:?}",
            descriptor.path
        );
    }
    for (path, role) in &expected {
        let descriptor = descriptors
            .get(path.as_str())
            .unwrap_or_else(|| panic!("manifest missing exact artifact path {path:?}"));
        assert_eq!(
            descriptor.role, *role,
            "manifest role mismatch for {path:?}"
        );
    }
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
    assert_eq!(
        descriptor.role, expected_role,
        "manifest role mismatch for {relative_path:?}"
    );
    let path = output_dir.join(relative_path);
    let before = require_regular_single_link(&path, "artifact");
    assert_eq!(
        before.len(),
        descriptor.size,
        "artifact size mismatch for {relative_path:?}"
    );
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
    assert_eq!(
        bytes.len() as u64,
        descriptor.size,
        "artifact byte length mismatch for {relative_path:?}"
    );
    let digest = hex::encode(Sha256::digest(&bytes));
    assert_eq!(
        digest, descriptor.content_sha256,
        "artifact contentSha256 mismatch for {relative_path:?}"
    );
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
        if let Ok(existing) = env::var("PROOF_FORGE_TIPJAR_ASSETS_OUT") {
            let path = PathBuf::from(existing);
            let so = format!("{PROGRAM_NAME}.so");
            let _elf = read_manifest_leaf_bytes(&path, &so, FINALIZED_EXTRA);
            return path;
        }

        let root = repo_root();
        let out = root.join("build/v2/solana-tipjar-assets");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }

        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior TipJarAssets product out");
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
            "product CLI build failed for TipJarAssets (status={status})"
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
            asm_text.contains("proof-forge:vault:v1"),
            "product assembly must pin vault seed0"
        );
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    // Distinct fixed id for Mollusk registration (not System zero id).
    Pubkey::new_from_array([0x54; 32])
}

fn make_product_mollusk() -> (Mollusk, Pubkey) {
    let out = ensure_product_output();
    let program_id = product_program_id();
    let elf = read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA);
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &elf,
    );
    (mollusk, program_id)
}

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn tips_fields() -> [common::StateField; 1] {
    single_field("tips")
}

fn tips_state(initialized: bool, tips: u64) -> Vec<u8> {
    state_data(&tips_fields(), initialized, &[tips])
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

fn init_ix_data(initial: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(INIT_IX_LEN);
    data.extend_from_slice(&INIT_HANDLER_ID.to_le_bytes());
    data.extend_from_slice(&initial.to_le_bytes());
    debug_assert_eq!(data.len(), INIT_IX_LEN);
    data
}

fn tip_ix_data(amount: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(TIP_IX_LEN);
    data.extend_from_slice(&TIP_HANDLER_ID.to_le_bytes());
    data.extend_from_slice(&amount.to_le_bytes());
    debug_assert_eq!(data.len(), TIP_IX_LEN);
    data
}

fn get_ix_data() -> Vec<u8> {
    GET_HANDLER_ID.to_le_bytes().to_vec()
}

fn account_by_key<'a>(
    accounts: &'a [(Pubkey, Account)],
    key: &Pubkey,
) -> &'a Account {
    accounts
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, a)| a)
        .unwrap_or_else(|| panic!("missing account {key}"))
}

// ---------------------------------------------------------------------------
// Case builders
// ---------------------------------------------------------------------------

/// init outer roles: 0 state (w+s).
#[derive(Clone)]
struct InitCase {
    state_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl InitCase {
    fn new(program_id: Pubkey) -> Self {
        let state_key = fixed_key(0x20);
        let state = state_account(&program_id, tips_state(false, 0));
        let metas = vec![AccountMeta::new(state_key, true)];
        let accounts = vec![(state_key, state)];
        Self {
            state_key,
            metas,
            accounts,
        }
    }

    fn instruction(&self, program_id: Pubkey, initial: u64) -> Instruction {
        Instruction::new_with_bytes(program_id, &init_ix_data(initial), self.metas.clone())
    }
}

/// tip outer roles: state, tip_dst, system, pf_caller (signer), pf_vault.
#[derive(Clone)]
struct TipCase {
    dst_key: Pubkey,
    caller_key: Pubkey,
    vault_key: Pubkey,
    vault_bump: u8,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    vault_lamports: u64,
}

impl TipCase {
    /// `vault_mode`:
    /// - `UnusedSystem`: 0-lamport System-owned empty (first ensure create path)
    /// - `ProgramOwnedRent`: already-created vault (idempotent ensure skip)
    fn new(
        program_id: Pubkey,
        tips_before: u64,
        caller_lamports: u64,
        dst_lamports: u64,
        vault: VaultMode,
    ) -> Self {
        let state_key = fixed_key(0x30);
        let dst_key = fixed_key(0x31);
        let caller_key = fixed_key(0x32);
        let (vault_key, vault_bump) = find_vault_pda(&program_id);
        let (system_program_key, system_program) = system_program_keyed_account();
        assert_eq!(system_program_key, Pubkey::default());

        let state = state_account(&program_id, tips_state(true, tips_before));
        let dst = Account::new(dst_lamports, 0, &Pubkey::default());
        let caller = Account::new(caller_lamports, 0, &Pubkey::default());
        let (vault_account, vault_lamports) = match vault {
            VaultMode::UnusedSystem => (unused_system_create_target_account(), 0u64),
            VaultMode::ProgramOwnedRent => {
                let mut acc = Account::new(VAULT_RENT_EXEMPT_LAMPORTS, 0, &program_id);
                acc.data.clear();
                (acc, VAULT_RENT_EXEMPT_LAMPORTS)
            }
        };

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(dst_key, false),
            AccountMeta::new_readonly(system_program_key, false),
            AccountMeta::new(caller_key, true),
            AccountMeta::new(vault_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (dst_key, dst),
            (system_program_key, system_program),
            (caller_key, caller),
            (vault_key, vault_account),
        ];
        assert_eq!(metas.len(), TIP_OUTER_ROLE_COUNT);
        assert_eq!(accounts.len(), TIP_OUTER_ROLE_COUNT);
        Self {
            dst_key,
            caller_key,
            vault_key,
            vault_bump,
            metas,
            accounts,
            vault_lamports,
        }
    }

    fn instruction(&self, program_id: Pubkey, amount: u64) -> Instruction {
        Instruction::new_with_bytes(program_id, &tip_ix_data(amount), self.metas.clone())
    }
}

#[derive(Clone, Copy)]
enum VaultMode {
    /// System-owned, 0 lamports, 0 data — first-time ensure create path.
    UnusedSystem,
    /// Already program-owned, rent-exempt, empty data — ensure skip path.
    ProgramOwnedRent,
}

// ---------------------------------------------------------------------------
// Pure layout / product tree identity
// ---------------------------------------------------------------------------

#[test]
fn ix_layouts_match_handler_probe_lengths() {
    assert_eq!(init_ix_data(7).len(), INIT_IX_LEN);
    assert_eq!(&init_ix_data(7)[0..8], &INIT_HANDLER_ID.to_le_bytes());
    assert_eq!(&init_ix_data(7)[8..16], &7u64.to_le_bytes());

    assert_eq!(tip_ix_data(42).len(), TIP_IX_LEN);
    assert_eq!(&tip_ix_data(42)[0..8], &TIP_HANDLER_ID.to_le_bytes());
    assert_eq!(&tip_ix_data(42)[8..16], &42u64.to_le_bytes());

    assert_eq!(get_ix_data().len(), GET_IX_LEN);
    assert_eq!(get_ix_data(), GET_HANDLER_ID.to_le_bytes());
}

#[test]
fn vault_seed0_and_rent_pins() {
    assert_eq!(
        hex::encode(VAULT_SEED0),
        "70726f6f662d666f7267653a7661756c743a7631"
    );
    assert_eq!(VAULT_SEED0, b"proof-forge:vault:v1");
    assert_eq!(VAULT_RENT_EXEMPT_LAMPORTS, 890_880);
    let program_id = product_program_id();
    let (pda, bump) = find_vault_pda(&program_id);
    assert_ne!(bump, 0, "canonical bump search rejects 0");
    let seeds: &[&[u8]] = &[VAULT_SEED0, &[bump]];
    assert_eq!(
        Pubkey::create_program_address(seeds, &program_id).expect("canonical"),
        pda
    );
}

#[test]
fn product_tree_is_manifest_bound_cpi_profile() {
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
    assert_eq!(handlers.len(), 3, "init + tip + get");
    assert_eq!(handlers[0]["handlerId"], serde_json::json!(0));
    assert_eq!(handlers[0]["name"], serde_json::json!("init"));
    assert_eq!(handlers[1]["handlerId"], serde_json::json!(1));
    assert_eq!(handlers[1]["name"], serde_json::json!("tip"));
    assert_eq!(handlers[2]["handlerId"], serde_json::json!(2));
    assert_eq!(handlers[2]["name"], serde_json::json!("get"));

    let tip_uses = handlers[1]["accountUses"].as_array().expect("tip uses");
    assert_eq!(tip_uses.len(), TIP_OUTER_ROLE_COUNT);
    assert_eq!(tip_uses[ROLE_CALLER]["outerSigner"], serde_json::json!(true));
    assert_eq!(
        tip_uses[ROLE_CALLER]["outerWritable"],
        serde_json::json!(true)
    );
    // Exactly one outer signer on tip (deposit caller convention).
    let outer_signers: Vec<_> = tip_uses
        .iter()
        .filter(|u| u["outerSigner"] == serde_json::json!(true))
        .collect();
    assert_eq!(outer_signers.len(), 1, "tip must have exactly one outer signer");

    let roles = plan["accountRoles"].as_array().expect("accountRoles");
    assert_eq!(roles[0]["name"], serde_json::json!("state"));
    assert_eq!(roles[1]["name"], serde_json::json!("tip_dst"));
    assert_eq!(roles[2]["name"], serde_json::json!("system_v1_program"));
    assert_eq!(roles[3]["name"], serde_json::json!("pf_caller"));
    assert_eq!(roles[4]["name"], serde_json::json!("pf_vault"));

    let ir = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-ir.json"),
        MATERIALIZED_BASE,
    );
    let ir_text = String::from_utf8(ir).expect("ir utf-8");
    assert!(
        ir_text.contains("nativeDeposit"),
        "product IR must lower pf.assets.native.deposit"
    );
    assert!(
        ir_text.contains("nativeTransfer"),
        "product IR must lower pf.assets.native.transfer"
    );
    assert!(
        ir_text.contains("proof-forge:vault:v1"),
        "product IR must pin vault rule"
    );
    assert!(
        ir_text.contains("handler:1:1:tip:entry:roles5:probe16"),
        "tip must pin 5 roles + probe16"
    );
}

// ---------------------------------------------------------------------------
// Mollusk runtime matrix
// ---------------------------------------------------------------------------

/// (a) init: state tips = initial. Vault is **not** created by init (fixture
/// contract: vault may be absent pre-deposit). Creation is tip's ensure path.
#[test]
fn a_init_initializes_tips_state() {
    let (mollusk, program_id) = make_product_mollusk();
    let initial = 11u64;
    let case = InitCase::new(program_id);
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, initial),
        &case.accounts,
        &[Check::success()],
    );
    let post = account_by_key(&result.resulting_accounts, &case.state_key);
    assert_eq!(
        post.data,
        tips_state(true, initial),
        "init must write tips + layout marker"
    );
    assert_eq!(post.owner, program_id);
    assert_eq!(post.data.len(), 16);
}

/// (a′) first tip creates vault via ensure (fresh System-owned zero account),
/// then deposit+transfer with vault net-zero and tips++.
#[test]
fn a_first_tip_creates_vault_and_succeeds() {
    let (mollusk, program_id) = make_product_mollusk();
    let amount = 50_000u64;
    let tips_before = 0u64;
    let caller_lamports = BASE_LAMPORTS + VAULT_RENT_EXEMPT_LAMPORTS + amount;
    let dst_before = BASE_LAMPORTS;
    let case = TipCase::new(
        program_id,
        tips_before,
        caller_lamports,
        dst_before,
        VaultMode::UnusedSystem,
    );
    assert_eq!(case.vault_lamports, 0);
    assert_ne!(case.vault_bump, 0);
    let expected_tips = tips_before + amount;
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, amount),
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&expected_tips.to_le_bytes()),
        ],
    );
    let post_caller = account_by_key(&result.resulting_accounts, &case.caller_key);
    let post_dst = account_by_key(&result.resulting_accounts, &case.dst_key);
    let post_vault = account_by_key(&result.resulting_accounts, &case.vault_key);
    let post_state = account_by_key(&result.resulting_accounts, &case.metas[0].pubkey);
    // Caller pays rent-exempt create + amount; vault ends at rent-exempt only
    // (deposit then transfer same amount → vault net +rent only on first tip).
    assert_eq!(
        post_caller.lamports,
        caller_lamports - VAULT_RENT_EXEMPT_LAMPORTS - amount,
        "caller debited rent-exempt create + tip amount"
    );
    assert_eq!(
        post_dst.lamports,
        dst_before + amount,
        "dst credited tip amount"
    );
    assert_eq!(
        post_vault.lamports, VAULT_RENT_EXEMPT_LAMPORTS,
        "vault holds rent-exempt only after net-zero deposit/transfer"
    );
    assert_eq!(post_vault.owner, program_id, "ensure assigns current program");
    assert_eq!(post_vault.data.len(), 0, "vault remains space=0");
    assert_eq!(
        post_state.data,
        tips_state(true, expected_tips),
        "tips += amount"
    );
}

/// (b) tip with existing program-owned rent vault: ensure skip + deposit+transfer
/// (vault lamports net-zero) and tips++.
#[test]
fn b_tip_existing_vault_succeeds_with_ensure_skip() {
    let (mollusk, program_id) = make_product_mollusk();
    let amount = 42_000u64;
    let tips_before = 11u64;
    let case = TipCase::new(
        program_id,
        tips_before,
        BASE_LAMPORTS,
        BASE_LAMPORTS,
        VaultMode::ProgramOwnedRent,
    );
    let expected_tips = tips_before + amount;
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, amount),
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&expected_tips.to_le_bytes()),
        ],
    );
    let post_caller = account_by_key(&result.resulting_accounts, &case.caller_key);
    let post_dst = account_by_key(&result.resulting_accounts, &case.dst_key);
    let post_vault = account_by_key(&result.resulting_accounts, &case.vault_key);
    let post_state = account_by_key(&result.resulting_accounts, &case.metas[0].pubkey);
    assert_eq!(
        post_caller.lamports,
        BASE_LAMPORTS - amount,
        "caller debited tip amount only (no re-create)"
    );
    assert_eq!(
        post_dst.lamports,
        BASE_LAMPORTS + amount,
        "dst credited tip amount"
    );
    assert_eq!(
        post_vault.lamports, VAULT_RENT_EXEMPT_LAMPORTS,
        "vault net-zero: still rent-exempt only"
    );
    assert_eq!(post_vault.owner, program_id);
    assert_eq!(
        post_state.data,
        tips_state(true, expected_tips),
        "tips += amount"
    );
}

/// (c) repeat tip on already-present vault is idempotent ensure (same as b).
#[test]
fn c_repeat_tip_idempotent_ensure_succeeds() {
    let (mollusk, program_id) = make_product_mollusk();
    let amount = 7_000u64;
    let tips_before = 100u64;
    let case = TipCase::new(
        program_id,
        tips_before,
        BASE_LAMPORTS,
        BASE_LAMPORTS,
        VaultMode::ProgramOwnedRent,
    );
    let expected_tips = tips_before + amount;
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, amount),
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&expected_tips.to_le_bytes()),
        ],
    );
    let post_vault = account_by_key(&result.resulting_accounts, &case.vault_key);
    let post_state = account_by_key(&result.resulting_accounts, &case.metas[0].pubkey);
    assert_eq!(post_vault.lamports, VAULT_RENT_EXEMPT_LAMPORTS);
    assert_eq!(post_vault.owner, program_id);
    assert_eq!(post_state.data, tips_state(true, expected_tips));
}

/// (d) underfunded caller: System CPI fails with ResultWithNegativeLamports
/// (Custom(1)); full account snapshot rollback.
#[test]
fn d_underfunded_caller_full_snapshot_rollback() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = TipCase::new(
        program_id,
        5,
        /*caller*/ 1_000,
        BASE_LAMPORTS,
        VaultMode::ProgramOwnedRent,
    );
    // Native System transfer returns SystemError::ResultWithNegativeLamports
    // (= Custom(1)); product CPI propagates that status via cpi_failed.
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, 50_000),
        &case.accounts,
        Check::err(ProgramError::Custom(
            SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
        )),
    );
}

/// (e) multi outer signer (extra signer beyond pf_caller) → handler reject.
/// Preflight rejects before ensure body — still a clean Custom(1) path.
#[test]
fn e_multi_outer_signer_rejected() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(
        program_id,
        0,
        BASE_LAMPORTS,
        BASE_LAMPORTS,
        VaultMode::ProgramOwnedRent,
    );
    // Mark tip_dst as an additional outer signer → violates deposit caller
    // convention (exactly one outer signer) / required=false preflight.
    case.metas[ROLE_DST] = AccountMeta::new(case.dst_key, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, 1_000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// (f) wrong vault PDA: clean Custom reject (PDA key join / shape).
#[test]
fn f_wrong_vault_pda_rejected() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(
        program_id,
        0,
        BASE_LAMPORTS,
        BASE_LAMPORTS,
        VaultMode::ProgramOwnedRent,
    );
    let wrong = fixed_key(0x77);
    case.metas[ROLE_VAULT] = AccountMeta::new(wrong, false);
    let mut wrong_acc = Account::new(VAULT_RENT_EXEMPT_LAMPORTS, 0, &program_id);
    wrong_acc.data.clear();
    case.accounts[ROLE_VAULT] = (wrong, wrong_acc);
    case.vault_key = wrong;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, 1_000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// (g) zero outer signer → reject (pf_caller must sign). Clean Custom path.
#[test]
fn g_zero_signer_rejected() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TipCase::new(
        program_id,
        0,
        BASE_LAMPORTS,
        BASE_LAMPORTS,
        VaultMode::ProgramOwnedRent,
    );
    case.metas[ROLE_CALLER] = AccountMeta::new(case.caller_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, 1_000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// View path: get returns tips without mutating accounts.
#[test]
fn get_returns_tips_readonly() {
    let (mollusk, program_id) = make_product_mollusk();
    let tips = 99u64;
    let state_key = fixed_key(0x40);
    let state = state_account(&program_id, tips_state(true, tips));
    let metas = vec![AccountMeta::new_readonly(state_key, false)];
    let accounts = vec![(state_key, state.clone())];
    let ix = Instruction::new_with_bytes(program_id, &get_ix_data(), metas);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::success(),
            Check::return_data(&tips.to_le_bytes()),
        ],
    );
    let post = account_by_key(&result.resulting_accounts, &state_key);
    assert_eq!(post.data, state.data, "view must not mutate state bytes");
    assert_eq!(post.lamports, state.lamports);
}
