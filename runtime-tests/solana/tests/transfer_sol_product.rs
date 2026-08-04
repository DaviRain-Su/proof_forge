//! # Product-path TransferSol Mollusk regression.
//!
//! Builds `Examples/TransferSol.lean` through ordinary `proof-forge-next build
//! --target solana --profile solana-sbpf-cpi-elf-v1`
//! and loads **only** the manifest-bound `TransferSol.so` into Mollusk with
//! the native System program (`Mollusk::default()`).
//!
//! Fixture surface (stateless product):
//! - single entry `transfer(payer, recipient, lamports) : UInt64`
//! - handlerId = 0
//! - instruction data = exactly 16 bytes: handlerId u64 LE + lamports u64 LE
//! - outer account order: payer (w+s), recipient (w), System (ro, native zero id)
//!
//! Env (optional):
//! - `PROOF_FORGE_TRANSFER_SOL_OUT` — existing product output tree; when unset
//!   the test builds into `build/v2/solana-transfer-sol-product`.
//! - `PROOF_FORGE_TOOL_ROOT` — locked sbpf tool root (finalize).
//! - `CARGO_MANIFEST_DIR` — crate root (runtime-tests/solana).

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, system_program_keyed_account, BASE_LAMPORTS,
        CHECK_OR_UNKNOWN, SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
    },
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
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
const PROGRAM_NAME: &str = "TransferSol";
const MODULE_NAME: &str = "Examples.TransferSol";
const SOURCE_REL: &str = "Examples/TransferSol.lean";
/// Canonical ProgramV1 source identity for the tracked fixture above.
const EXPECTED_SOURCE_HASH: &str =
    "1fc319e8857f121fda9639596c4922aec42a1c92e43482e5a0aef5749a5f5e29";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

/// Single-entry transfer handlerId (only entry in TransferSol).
const TRANSFER_HANDLER_ID: u64 = 0;
/// handlerId u64 LE + lamports u64 LE.
const TRANSFER_IX_DATA_LEN: usize = 16;
/// Outer role order from product Plan: payer, recipient, system.
const ROLE_PAYER: usize = 0;
const ROLE_RECIPIENT: usize = 1;
const ROLE_SYSTEM: usize = 2;
const OUTER_ROLE_COUNT: usize = 3;

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
    // CARGO_MANIFEST_DIR = …/runtime-tests/solana
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
        "product output must remain bound to the tracked TransferSol source"
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
        if let Ok(existing) = env::var("PROOF_FORGE_TRANSFER_SOL_OUT") {
            let path = PathBuf::from(existing);
            let so = format!("{PROGRAM_NAME}.so");
            // Re-bind existing tree through manifest authority.
            let _elf = read_manifest_leaf_bytes(&path, &so, FINALIZED_EXTRA);
            return path;
        }

        let root = repo_root();
        let out = root.join("build/v2/solana-transfer-sol-product");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            // Reuse prior product tree if still valid; re-bind via manifest.
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }

        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior TransferSol product out");
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
            "product CLI build failed for TransferSol (status={status})"
        );

        let so = format!("{PROGRAM_NAME}.so");
        let elf = read_manifest_leaf_bytes(&out, &so, FINALIZED_EXTRA);
        assert!(elf.starts_with(b"\x7fELF"), "product .so must be ELF");
        // Product path must not emit preactivation banners.
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
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    // Distinct fixed id for Mollusk registration (not System zero id).
    Pubkey::new_from_array([0x57; 32])
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

fn transfer_ix_data(handler_id: u64, lamports: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(TRANSFER_IX_DATA_LEN);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&lamports.to_le_bytes());
    debug_assert_eq!(data.len(), TRANSFER_IX_DATA_LEN);
    data
}

/// Outer roles: 0 payer (w+s), 1 recipient (w), 2 system (ro native).
#[derive(Clone)]
struct TransferCase {
    payer_key: Pubkey,
    recipient_key: Pubkey,
    system_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    payer_lamports: u64,
    recipient_lamports: u64,
}

impl TransferCase {
    fn new(payer_lamports: u64, recipient_lamports: u64) -> Self {
        let payer_key = fixed_key(0x21);
        let recipient_key = fixed_key(0x22);
        let (system_program_key, system_program) = system_program_keyed_account();
        assert_eq!(system_program_key, Pubkey::default());

        let payer = Account::new(payer_lamports, 0, &Pubkey::default());
        let recipient = Account::new(recipient_lamports, 0, &Pubkey::default());

        let metas = vec![
            AccountMeta::new(payer_key, true),
            AccountMeta::new(recipient_key, false),
            AccountMeta::new_readonly(system_program_key, false),
        ];
        let accounts = vec![
            (payer_key, payer),
            (recipient_key, recipient),
            (system_program_key, system_program),
        ];
        assert_eq!(metas.len(), OUTER_ROLE_COUNT);
        assert_eq!(accounts.len(), OUTER_ROLE_COUNT);
        Self {
            payer_key,
            recipient_key,
            system_program_key,
            metas,
            accounts,
            payer_lamports,
            recipient_lamports,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, lamports: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &transfer_ix_data(handler_id, lamports),
            self.metas.clone(),
        )
    }
}

// ---------------------------------------------------------------------------
// Pure layout / product tree identity
// ---------------------------------------------------------------------------

#[test]
fn transfer_ix_layout_is_exactly_handler0_data16() {
    let data = transfer_ix_data(TRANSFER_HANDLER_ID, 42);
    assert_eq!(data.len(), TRANSFER_IX_DATA_LEN);
    assert_eq!(&data[0..8], &TRANSFER_HANDLER_ID.to_le_bytes());
    assert_eq!(&data[8..16], &42u64.to_le_bytes());
    assert_eq!(TRANSFER_HANDLER_ID, 0, "stateless single-entry → handler 0");
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
    assert_eq!(handlers.len(), 1, "single transfer entry");
    assert_eq!(handlers[0]["handlerId"], serde_json::json!(0));
    assert_eq!(handlers[0]["name"], serde_json::json!("transfer"));
    let uses = handlers[0]["accountUses"].as_array().expect("accountUses");
    assert_eq!(uses.len(), OUTER_ROLE_COUNT);
    assert_eq!(uses[ROLE_PAYER]["outerSigner"], serde_json::json!(true));
    assert_eq!(uses[ROLE_PAYER]["outerWritable"], serde_json::json!(true));
    assert_eq!(
        uses[ROLE_RECIPIENT]["outerSigner"],
        serde_json::json!(false)
    );
    assert_eq!(
        uses[ROLE_RECIPIENT]["outerWritable"],
        serde_json::json!(true)
    );
    assert_eq!(uses[ROLE_SYSTEM]["outerSigner"], serde_json::json!(false));
    assert_eq!(uses[ROLE_SYSTEM]["outerWritable"], serde_json::json!(false));

    let roles = plan["accountRoles"].as_array().expect("accountRoles");
    assert_eq!(roles[0]["name"], serde_json::json!("transfer_payer"));
    assert_eq!(roles[1]["name"], serde_json::json!("transfer_recipient"));
    assert_eq!(roles[2]["name"], serde_json::json!("system_v1_program"));

    let ir = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-ir.json"),
        MATERIALIZED_BASE,
    );
    let ir_text = String::from_utf8(ir).expect("ir utf-8");
    assert!(
        ir_text.contains("probe16"),
        "product IR must pin probeIxDataLen=16"
    );
    assert!(
        ir_text.contains("roles3"),
        "product IR must pin localRoleCount=3"
    );
    assert!(
        ir_text.contains("handler:0:"),
        "product IR must dispatch handler 0"
    );
}

// ---------------------------------------------------------------------------
// Mollusk runtime matrix (native System)
// ---------------------------------------------------------------------------

#[test]
fn transfer_success_exact_lamport_delta_and_u64_return() {
    let (mollusk, program_id) = make_product_mollusk();
    let transfer_amount = 42_000u64;
    let case = TransferCase::new(BASE_LAMPORTS, BASE_LAMPORTS);
    let ix = case.instruction(program_id, TRANSFER_HANDLER_ID, transfer_amount);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&transfer_amount.to_le_bytes()),
        ],
    );
    let post_payer = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.payer_key)
        .map(|(_, a)| a)
        .expect("payer");
    let post_recipient = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.recipient_key)
        .map(|(_, a)| a)
        .expect("recipient");
    assert_eq!(
        post_payer.lamports,
        case.payer_lamports - transfer_amount,
        "exact payer lamport debit"
    );
    assert_eq!(
        post_recipient.lamports,
        case.recipient_lamports + transfer_amount,
        "exact recipient lamport credit"
    );
}

#[test]
fn raw_adjacent_meta_swap_without_privilege_rebinding_fails() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = TransferCase::new(BASE_LAMPORTS, BASE_LAMPORTS);
    // Canonical order succeeds in the positive test. Swapping the raw metas
    // and accounts also moves the signer privilege away from role 0, so the
    // product preflight must fail before the System CPI and preserve all state.
    let mut swapped = case.clone();
    swapped.metas.swap(ROLE_PAYER, ROLE_RECIPIENT);
    swapped.accounts.swap(ROLE_PAYER, ROLE_RECIPIENT);
    std::mem::swap(&mut swapped.payer_key, &mut swapped.recipient_key);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &swapped.instruction(program_id, TRANSFER_HANDLER_ID, 1000),
        &swapped.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn missing_payer_signer_fails_full_snapshot() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TransferCase::new(BASE_LAMPORTS, BASE_LAMPORTS);
    case.metas[ROLE_PAYER] = AccountMeta::new(case.payer_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn wrong_system_program_key_fails_full_snapshot() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = TransferCase::new(BASE_LAMPORTS, BASE_LAMPORTS);
    let wrong = fixed_key(0x75);
    case.metas[ROLE_SYSTEM] = AccountMeta::new_readonly(wrong, false);
    let mut fake = create_program_account_loader_v3(&wrong);
    fake.executable = true;
    case.system_program_key = wrong;
    case.accounts[ROLE_SYSTEM] = (wrong, fake);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, TRANSFER_HANDLER_ID, 1000),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn underfunded_inner_failure_exact_snapshot_rollback() {
    let (mollusk, program_id) = make_product_mollusk();
    // Payer has fewer lamports than requested transfer. Native System transfer
    // returns SystemError::ResultWithNegativeLamports (= Custom(1)); product
    // CPI propagates that status and rolls back every outer account field.
    let case = TransferCase::new(1_000, BASE_LAMPORTS);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(program_id, TRANSFER_HANDLER_ID, 50_000),
        &case.accounts,
        Check::err(ProgramError::Custom(
            SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
        )),
    );
}
