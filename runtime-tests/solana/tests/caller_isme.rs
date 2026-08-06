//! # ADR-0031 S1 / ADR-0030 E3 CallerIsMe Mollusk product acceptance.
//!
//! Builds `runtime-tests/solana/fixtures/CallerIsMe.lean` through ordinary
//! `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! and loads the manifest-bound `CallerIsMe.so` into Mollusk.
//!
//! Solana honesty: `context.caller` = ABI-specified `pf_caller` signer role
//! pubkey (AccountInfo.key + is_signer), materialized as Principal wire
//! `u32le(32)||pubkey32` → 9×UInt64 LE leaves (len + 8 body words; high 32
//! body bytes zero). NOT tx.origin / fee-payer. Does **not** open arbitrary
//! Principal→Solana address/callee semantics.
//!
//! Product surface:
//! - `isMe(who)` handlerId=0
//!   ix = handlerId u64 LE (8 B) || who Principal T12 9×u64 LE (72 B) = 80 B
//! - outer roles (dense): pf_caller only (handlerCaller, outerSigner,
//!   System-owned empty data). `who` is T12 ix-data, not an account role.
//!
//! Env (optional):
//! - `PROOF_FORGE_CALLER_ISME_OUT` — existing product output tree.

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, BASE_LAMPORTS, CHECK_OR_UNKNOWN,
    },
    mollusk_svm::{result::Check, Mollusk},
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

const OUTPUT_SCHEMA: &str = "proof-forge.output.v1";
const CPI_PROFILE: &str = "solana-sbpf-cpi-elf-v1";
const PROGRAM_NAME: &str = "CallerIsMe";
const MODULE_NAME: &str = "Examples.CallerIsMe";
const SOURCE_REL: &str = "runtime-tests/solana/fixtures/CallerIsMe.lean";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

const IS_ME_HANDLER_ID: u64 = 0;
/// handlerId (8) + Principal T12 9×u64 (72)
const IS_ME_IX_LEN: usize = 8 + 72;
const PRINCIPAL_LEAF_COUNT: usize = 9;

// Dense outer roles: pf_caller only
const ROLE_CALLER: usize = 0;
const OUTER_ROLE_COUNT: usize = 1;

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
        "CPI product files must be exactly six leaves"
    );
    for (descriptor, (path, role)) in manifest.files.iter().zip(expected.iter()) {
        assert_eq!(descriptor.path.as_str(), path.as_str());
        assert_eq!(descriptor.role.as_str(), *role);
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
    assert_eq!(matches.len(), 1, "manifest path {relative_path:?} once");
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
        if let Ok(existing) = env::var("PROOF_FORGE_CALLER_ISME_OUT") {
            let path = PathBuf::from(existing);
            let so = format!("{PROGRAM_NAME}.so");
            let _elf = read_manifest_leaf_bytes(&path, &so, FINALIZED_EXTRA);
            return path;
        }

        let root = repo_root();
        let out = root.join("build/v2/solana-caller-isme");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }

        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior CallerIsMe product out");
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
            "product CLI build failed for CallerIsMe (status={status})"
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
            asm_text.contains("contextReadCaller"),
            "product assembly must emit contextReadCaller"
        );
        assert!(
            asm_text.contains("not tx.origin"),
            "product assembly must document caller≠tx.origin honesty"
        );
        assert!(
            asm_text.contains("principalLeafEqIx"),
            "product assembly must emit principalLeafEqIx"
        );
        assert!(
            asm_text.contains("is_signer required"),
            "product assembly must site-time check is_signer"
        );
        assert!(
            asm_text.contains("lddw r3, 32"),
            "product assembly must materialize Principal len=32 leaf"
        );
        assert!(
            asm_text.contains("validatePrincipalIx"),
            "product assembly must emit validatePrincipalIx before comparison"
        );
        assert!(
            asm_text.contains("high-tail body bytes zero"),
            "product assembly must document high-tail zero canonical gate"
        );
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    Pubkey::new_from_array([0x43; 32]) // 'C' for Caller
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

/// Pack Solana pubkey as Principal T12 9 leaves: len=32 + 4×u64 LE key + 4 zero words.
fn principal_leaves_from_pubkey(key: &Pubkey) -> [u64; PRINCIPAL_LEAF_COUNT] {
    let mut leaves = [0u64; PRINCIPAL_LEAF_COUNT];
    leaves[0] = 32;
    let bytes = key.to_bytes();
    for i in 0..4 {
        let mut word = [0u8; 8];
        word.copy_from_slice(&bytes[i * 8..(i + 1) * 8]);
        leaves[1 + i] = u64::from_le_bytes(word);
    }
    // leaves[5..9] already zero
    leaves
}

/// Raw T12 Principal leaves (len + 8 body words). Used for noncanonical negatives.
fn principal_leaves_raw(len: u64, body: &[u8; 64]) -> [u64; PRINCIPAL_LEAF_COUNT] {
    let mut leaves = [0u64; PRINCIPAL_LEAF_COUNT];
    leaves[0] = len;
    for i in 0..8 {
        let mut word = [0u8; 8];
        word.copy_from_slice(&body[i * 8..(i + 1) * 8]);
        leaves[1 + i] = u64::from_le_bytes(word);
    }
    leaves
}

fn is_me_ix_data_from_leaves(leaves: &[u64; PRINCIPAL_LEAF_COUNT]) -> Vec<u8> {
    let mut data = Vec::with_capacity(IS_ME_IX_LEN);
    data.extend_from_slice(&IS_ME_HANDLER_ID.to_le_bytes());
    for leaf in leaves {
        data.extend_from_slice(&leaf.to_le_bytes());
    }
    debug_assert_eq!(data.len(), IS_ME_IX_LEN);
    data
}

fn is_me_ix_data(who: &Pubkey) -> Vec<u8> {
    is_me_ix_data_from_leaves(&principal_leaves_from_pubkey(who))
}

/// System-owned empty-data account (pf_caller constraint).
fn system_empty_account(lamports: u64) -> Account {
    Account::new(lamports, 0, &Pubkey::default())
}

fn account_by_key<'a>(accounts: &'a [(Pubkey, Account)], key: &Pubkey) -> &'a Account {
    &accounts
        .iter()
        .find(|(k, _)| k == key)
        .unwrap_or_else(|| panic!("missing account {key}"))
        .1
}

#[test]
fn is_me_ix_shape() {
    let who = fixed_key(0xA1);
    let data = is_me_ix_data(&who);
    assert_eq!(data.len(), IS_ME_IX_LEN);
    assert_eq!(&data[..8], &IS_ME_HANDLER_ID.to_le_bytes());
    // leaf0 = 32
    assert_eq!(&data[8..16], &32u64.to_le_bytes());
    // high body words zero
    assert_eq!(&data[IS_ME_IX_LEN - 32..], &[0u8; 32]);
}

/// Positive: who Principal wire equals pf_caller pubkey and pf_caller is_signer → 1.
#[test]
fn is_me_true_when_who_equals_signer_caller() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller_key = fixed_key(0xA1);
    // who wire identity == pf_caller pubkey (T12 ix leaves, not a second account).
    let who_key = caller_key;
    let caller_acc = system_empty_account(BASE_LAMPORTS);
    let metas = vec![AccountMeta::new_readonly(caller_key, true)]; // is_signer
    assert_eq!(metas.len(), OUTER_ROLE_COUNT);
    assert_eq!(ROLE_CALLER, 0);
    let accounts = vec![(caller_key, caller_acc.clone())];
    let ix = Instruction::new_with_bytes(program_id, &is_me_ix_data(&who_key), metas);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::success(),
            Check::return_data(&1u64.to_le_bytes()),
        ],
    );
    // View must not mutate accounts
    let post_caller = account_by_key(&result.resulting_accounts, &caller_key);
    assert_eq!(post_caller.data, caller_acc.data);
    assert_eq!(post_caller.lamports, caller_acc.lamports);
}

/// Positive: who Principal wire differs from pf_caller pubkey (signer) → 0.
#[test]
fn is_me_false_when_who_differs_from_signer_caller() {
    let (mollusk, program_id) = make_product_mollusk();
    let who_key = fixed_key(0xB2);
    let caller_key = fixed_key(0xA1);
    assert_ne!(who_key, caller_key);
    let caller_acc = system_empty_account(BASE_LAMPORTS);
    let metas = vec![AccountMeta::new_readonly(caller_key, true)];
    let accounts = vec![(caller_key, caller_acc.clone())];
    let ix = Instruction::new_with_bytes(program_id, &is_me_ix_data(&who_key), metas);
    let result = mollusk.process_and_validate_instruction(
        &ix,
        &accounts,
        &[
            Check::success(),
            Check::return_data(&0u64.to_le_bytes()),
        ],
    );
    let post_caller = account_by_key(&result.resulting_accounts, &caller_key);
    assert_eq!(post_caller.data, caller_acc.data);
    assert_eq!(post_caller.lamports, caller_acc.lamports);
}

/// Negative: pf_caller is not a signer → fail closed + full snapshot hold.
#[test]
fn is_me_rejects_non_signer_caller_role() {
    let (mollusk, program_id) = make_product_mollusk();
    let who_key = fixed_key(0xB2);
    let caller_key = fixed_key(0xA1);
    let caller_acc = system_empty_account(BASE_LAMPORTS);
    let metas = vec![AccountMeta::new_readonly(caller_key, false)]; // NOT signer
    let accounts = vec![(caller_key, caller_acc)];
    let ix = Instruction::new_with_bytes(program_id, &is_me_ix_data(&who_key), metas);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// Noncanonical ordinary Principal: len=0 → Custom(1) + exact snapshot hold.
#[test]
fn is_me_rejects_principal_len_zero() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller_key = fixed_key(0xA1);
    let caller_acc = system_empty_account(BASE_LAMPORTS);
    let metas = vec![AccountMeta::new_readonly(caller_key, true)];
    let accounts = vec![(caller_key, caller_acc)];
    let body = [0u8; 64];
    let leaves = principal_leaves_raw(0, &body);
    let ix = Instruction::new_with_bytes(
        program_id,
        &is_me_ix_data_from_leaves(&leaves),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// Noncanonical ordinary Principal: len=65 → Custom(1) + exact snapshot hold.
#[test]
fn is_me_rejects_principal_len_65() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller_key = fixed_key(0xA1);
    let caller_acc = system_empty_account(BASE_LAMPORTS);
    let metas = vec![AccountMeta::new_readonly(caller_key, true)];
    let accounts = vec![(caller_key, caller_acc)];
    let body = [0u8; 64];
    let leaves = principal_leaves_raw(65, &body);
    let ix = Instruction::new_with_bytes(
        program_id,
        &is_me_ix_data_from_leaves(&leaves),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// Noncanonical ordinary Principal: len=32 with nonzero high-tail body byte
/// (index ≥ 32) → Custom(1) + exact snapshot hold. Exact ix byte length alone
/// is insufficient — physical high-tail must be zero.
#[test]
fn is_me_rejects_principal_len32_nonzero_high_tail() {
    let (mollusk, program_id) = make_product_mollusk();
    let caller_key = fixed_key(0xA1);
    let caller_acc = system_empty_account(BASE_LAMPORTS);
    let metas = vec![AccountMeta::new_readonly(caller_key, true)];
    let accounts = vec![(caller_key, caller_acc)];
    // Canonical pubkey body in first 32 bytes; nonzero tail at body[32].
    let mut body = [0u8; 64];
    body[..32].copy_from_slice(&caller_key.to_bytes());
    body[32] = 0xff;
    let leaves = principal_leaves_raw(32, &body);
    assert_ne!(leaves[5], 0, "high-tail word must be nonzero for this negative");
    let ix = Instruction::new_with_bytes(
        program_id,
        &is_me_ix_data_from_leaves(&leaves),
        metas,
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// Assembly honesty pin (also checked at ensure_product_output).
#[test]
fn product_assembly_documents_caller_not_tx_origin() {
    let out = ensure_product_output();
    let assembly =
        read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.s"), MATERIALIZED_BASE);
    let text = String::from_utf8_lossy(&assembly);
    assert!(text.contains("not tx.origin"));
    assert!(text.contains("contextReadCaller"));
    assert!(text.contains("principalLeafEqIx"));
    assert!(text.contains("validatePrincipalIx"));
    assert!(text.contains("high-tail body bytes zero"));
    assert!(text.contains("checkEffectiveSigner"));
    assert!(text.contains("lddw r3, 32"));
}
