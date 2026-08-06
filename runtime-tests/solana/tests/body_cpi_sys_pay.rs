//! # Product-path BodyCpiSysPay Mollusk differential (ADR-0032 U1 / P3-e).
//!
//! Builds `Examples/BodyCpiSysPay.lean` through ordinary
//! `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! and loads **only** the manifest-bound `BodyCpiSysPay.so` into Mollusk with
//! the native System program (`Mollusk::default()`).
//!
//! Surface (full-body + multi-role system.transfer):
//! - handlers: initialize / credit / pay / get (disc = LowerSemantic formula)
//! - pay outer roles (4): state (w), payer (w+s), recipient (w), System (ro)
//! - pay ix data = disc u64 LE + 18×u64 Principal leaves (2×9) + amount u64 LE
//!   (160 bytes). Principal leaves are ABI padding for T12 wire; CPI metas bind
//!   outer account keys (P3-e multi-role AccountMeta).
//! - program `bal` state is independent of lamport movement; pay subtracts
//!   amount from bal then invokes native System transfer.
//!
//! Env (optional):
//! - `PROOF_FORGE_BODY_CPI_SYS_PAY_OUT` — existing product output tree.
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
        SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
    },
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
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
const PROGRAM_NAME: &str = "BodyCpiSysPay";
const MODULE_NAME: &str = "Examples.BodyCpiSysPay";
const SOURCE_REL: &str = "Examples/BodyCpiSysPay.lean";
/// Canonical ProgramV1 source identity for the tracked fixture above.
const EXPECTED_SOURCE_HASH: &str =
    "73e8ebcc19f5f4e157e942beb5f2c8cdabfdd00cd0d391b795a47989cb6f6dd8";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

/// Principal expands to 9×UInt64 instruction leaves (len + 8 body words).
const PRINCIPAL_LEAF_COUNT: usize = 9;
/// pay(payer Principal, recipient Principal, amount UInt64) → 19 u64 leaves.
const PAY_PARAM_U64_COUNT: usize = PRINCIPAL_LEAF_COUNT * 2 + 1;
/// disc(8) + 19×8 = 160.
const PAY_IX_DATA_LEN: usize = 8 + PAY_PARAM_U64_COUNT * 8;

const ROLE_STATE: usize = 0;
const ROLE_PAYER: usize = 1;
const ROLE_RECIPIENT: usize = 2;
const ROLE_SYSTEM: usize = 3;
const OUTER_ROLE_COUNT: usize = 4;

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
        "product output must remain bound to the tracked BodyCpiSysPay source"
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
        if let Ok(existing) = env::var("PROOF_FORGE_BODY_CPI_SYS_PAY_OUT") {
            let path = PathBuf::from(existing);
            let so = format!("{PROGRAM_NAME}.so");
            let _elf = read_manifest_leaf_bytes(&path, &so, FINALIZED_EXTRA);
            return path;
        }

        let root = repo_root();
        let out = root.join("build/v2/solana-body-cpi-sys-pay");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            if read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA)
                .starts_with(b"\x7fELF")
            {
                return out;
            }
        }

        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior BodyCpiSysPay product out");
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
            "product CLI build failed for BodyCpiSysPay (status={status})"
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
            asm_text.contains("product_mr_xfer"),
            "product assembly must emit multi-role system.transfer site"
        );
        assert!(
            asm_text.contains("num_accounts == 4"),
            "multi-role handler checks must expect outerRoleCount=4"
        );
        // Temps must sit at unified frame base (r10-1096+), not clobber ix_data slot.
        assert!(
            asm_text.contains("[r10 - 1096]"),
            "multi-role body temps must use productEscrowTempBaseV1"
        );
        out
    })
    .clone()
}

fn product_program_id() -> Pubkey {
    Pubkey::new_from_array([0x5b; 32])
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

fn bal_fields() -> [common::StateField; 1] {
    single_field("bal")
}

fn bal_state(initialized: bool, bal: u64) -> Vec<u8> {
    state_data(&bal_fields(), initialized, &[bal])
}

fn initialize_disc() -> String {
    // LowerSemantic renames init → initialize for the Solana ABI surface.
    instruction_discriminator("initialize", 0)
}

fn credit_disc() -> String {
    instruction_discriminator("credit", 1)
}

fn pay_disc() -> String {
    // Principal expands to 9×u64 leaves each; disc formula uses all leaf types.
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

/// disc + 18 zero Principal leaves + amount u64 LE (160 bytes).
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

#[derive(Clone)]
struct PayCase {
    state_key: Pubkey,
    payer_key: Pubkey,
    recipient_key: Pubkey,
    system_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    bal: u64,
    payer_lamports: u64,
    recipient_lamports: u64,
}

impl PayCase {
    fn new(
        program_id: &Pubkey,
        bal: u64,
        payer_lamports: u64,
        recipient_lamports: u64,
    ) -> Self {
        let state_key = fixed_key(0x41);
        let payer_key = fixed_key(0x42);
        let recipient_key = fixed_key(0x43);
        let (system_program_key, system_program) = system_program_keyed_account();
        assert_eq!(system_program_key, Pubkey::default());

        let state = state_account(program_id, bal_state(true, bal));
        let payer = Account::new(payer_lamports, 0, &Pubkey::default());
        let recipient = Account::new(recipient_lamports, 0, &Pubkey::default());

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(payer_key, true),
            AccountMeta::new(recipient_key, false),
            AccountMeta::new_readonly(system_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (payer_key, payer),
            (recipient_key, recipient),
            (system_program_key, system_program),
        ];
        assert_eq!(metas.len(), OUTER_ROLE_COUNT);
        Self {
            state_key,
            payer_key,
            recipient_key,
            system_program_key,
            metas,
            accounts,
            bal,
            payer_lamports,
            recipient_lamports,
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
    // amount sits at offset 152 (after 18 principal leaves).
    assert_eq!(&data[152..160], &42u64.to_le_bytes());
    // Principal leaf region is zero padding (account keys bind CPI metas).
    assert!(data[8..152].iter().all(|&b| b == 0));
}

#[test]
fn product_tree_is_manifest_bound_multi_role_cpi() {
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
    assert_eq!(pay_uses[ROLE_STATE]["outerWritable"], serde_json::json!(true));
    assert_eq!(pay_uses[ROLE_PAYER]["outerSigner"], serde_json::json!(true));
    assert_eq!(
        pay_uses[ROLE_PAYER]["outerWritable"],
        serde_json::json!(true)
    );
    assert_eq!(
        pay_uses[ROLE_RECIPIENT]["outerWritable"],
        serde_json::json!(true)
    );
    assert_eq!(
        pay_uses[ROLE_SYSTEM]["outerWritable"],
        serde_json::json!(false)
    );

    let roles = plan["accountRoles"].as_array().expect("accountRoles");
    assert_eq!(roles[0]["name"], serde_json::json!("state"));
    assert_eq!(roles[1]["name"], serde_json::json!("pay_payer"));
    assert_eq!(roles[2]["name"], serde_json::json!("pay_recipient"));
    assert_eq!(roles[3]["name"], serde_json::json!("system_v1_program"));

    let ir = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-ir.json"),
        MATERIALIZED_BASE,
    );
    let ir_text = String::from_utf8(ir).expect("ir utf-8");
    assert!(
        ir_text.contains("p3e-system-transfer-multi-role"),
        "product IR must mark p3e multi-role synthesize"
    );
    assert!(
        ir_text.contains("unifiedCpi"),
        "product IR must use unifiedCpi frame"
    );
    assert!(
        ir_text.contains("\"outerRoleCount\":4"),
        "product IR must pin outerRoleCount=4"
    );
}

// ---------------------------------------------------------------------------
// Mollusk runtime matrix
// ---------------------------------------------------------------------------

/// Multi-role entrypoint requires exact outerRoleCount accounts on every
/// handler (including init/credit/get which only *use* state).
fn four_role_shell(
    state_key: Pubkey,
    state: Account,
    state_signer: bool,
    state_writable: bool,
) -> (Vec<AccountMeta>, Vec<(Pubkey, Account)>) {
    let payer_key = fixed_key(0x62);
    let recipient_key = fixed_key(0x63);
    let (system_key, system) = system_program_keyed_account();
    let state_meta = if state_writable {
        AccountMeta::new(state_key, state_signer)
    } else {
        AccountMeta::new_readonly(state_key, state_signer)
    };
    let metas = vec![
        state_meta,
        AccountMeta::new(payer_key, false),
        AccountMeta::new(recipient_key, false),
        AccountMeta::new_readonly(system_key, false),
    ];
    let accounts = vec![
        (state_key, state),
        (payer_key, Account::new(BASE_LAMPORTS, 0, &Pubkey::default())),
        (
            recipient_key,
            Account::new(BASE_LAMPORTS, 0, &Pubkey::default()),
        ),
        (system_key, system),
    ];
    (metas, accounts)
}

#[test]
fn initialize_then_credit_then_get_round_trip() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x51);
    let uninit = state_account(&program_id, bal_state(false, 0));
    let (init_metas, init_accounts) = four_role_shell(state_key, uninit, true, true);
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
    assert_eq!(after_init.data, bal_state(true, 0));

    let credit_amount = 100u64;
    let (credit_metas, credit_accounts) =
        four_role_shell(state_key, after_init, false, true);
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
    assert_eq!(after_credit.data, bal_state(true, credit_amount));

    let (get_metas, get_accounts) = four_role_shell(state_key, after_credit, false, false);
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
fn pay_success_debits_bal_and_moves_lamports() {
    let (mollusk, program_id) = make_product_mollusk();
    // bal is program-owned logical balance (independent of payer lamports).
    // It must be ≥ amount for the then-branch System CPI to run.
    let bal = 100_000u64;
    let transfer_amount = 42_000u64;
    let case = PayCase::new(&program_id, bal, BASE_LAMPORTS, BASE_LAMPORTS);
    let result = mollusk.process_and_validate_instruction(
        &case.pay_instruction(program_id, transfer_amount),
        &case.accounts,
        &[
            Check::success(),
            Check::return_data(&(bal - transfer_amount).to_le_bytes()),
        ],
    );
    let post_state = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.state_key)
        .map(|(_, a)| a)
        .expect("state");
    assert_eq!(
        post_state.data,
        bal_state(true, bal - transfer_amount),
        "exact bal debit"
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
        "exact payer lamport debit via System CPI"
    );
    assert_eq!(
        post_recipient.lamports,
        case.recipient_lamports + transfer_amount,
        "exact recipient lamport credit via System CPI"
    );
}

#[test]
fn pay_when_bal_below_amount_skips_cpi_and_returns_bal() {
    let (mollusk, program_id) = make_product_mollusk();
    // bal=10, amount=100 → else branch: no state write, no System CPI.
    let case = PayCase::new(&program_id, 10, BASE_LAMPORTS, BASE_LAMPORTS);
    let result = mollusk.process_and_validate_instruction(
        &case.pay_instruction(program_id, 100),
        &case.accounts,
        &[Check::success(), Check::return_data(&10u64.to_le_bytes())],
    );
    let post_state = result
        .resulting_accounts
        .iter()
        .find(|(k, _)| *k == case.state_key)
        .map(|(_, a)| a)
        .expect("state");
    assert_eq!(post_state.data, bal_state(true, 10));
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
    assert_eq!(post_payer.lamports, case.payer_lamports);
    assert_eq!(post_recipient.lamports, case.recipient_lamports);
}

#[test]
fn pay_amount_zero_asserts_custom_1002() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = PayCase::new(&program_id, 100, BASE_LAMPORTS, BASE_LAMPORTS);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.pay_instruction(program_id, 0),
        &case.accounts,
        Check::err(ProgramError::Custom(0x1002)),
    );
}

#[test]
fn pay_missing_payer_signer_fails_full_snapshot() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = PayCase::new(&program_id, 1_000, BASE_LAMPORTS, BASE_LAMPORTS);
    // P3-e multi-role packs AccountMeta.is_signer from the recipe, but the
    // runtime still requires the outer transaction signer bit. Missing it
    // fails at invoke with PrivilegeEscalation (honest runtime error; not a
    // Custom(1) product preflight — full-body multi-role has no separate
    // signer preflight beyond the outer meta).
    case.metas[ROLE_PAYER] = AccountMeta::new(case.payer_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.pay_instruction(program_id, 1000),
        &case.accounts,
        Check::instruction_err(InstructionError::PrivilegeEscalation),
    );
}

#[test]
fn pay_wrong_system_program_key_fails_full_snapshot() {
    let (mollusk, program_id) = make_product_mollusk();
    let mut case = PayCase::new(&program_id, 1_000, BASE_LAMPORTS, BASE_LAMPORTS);
    // Full-body multi-role does not re-check catalog program id before
    // sol_invoke_signed_c; a non-registered executable key fails the runtime
    // with UnsupportedProgramId. Snapshot still rolls back (no bal debit kept).
    let wrong = fixed_key(0x75);
    case.metas[ROLE_SYSTEM] = AccountMeta::new_readonly(wrong, false);
    let mut fake = create_program_account_loader_v3(&wrong);
    fake.executable = true;
    case.system_program_key = wrong;
    case.accounts[ROLE_SYSTEM] = (wrong, fake);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.pay_instruction(program_id, 1000),
        &case.accounts,
        Check::instruction_err(InstructionError::UnsupportedProgramId),
    );
}

#[test]
fn pay_underfunded_inner_system_failure_rolls_back_bal() {
    let (mollusk, program_id) = make_product_mollusk();
    // bal allows the debit, but payer has fewer lamports than requested.
    // Native System transfer fails → outer Custom(1) + full account rollback
    // (including bal write that ran before the CPI).
    let case = PayCase::new(&program_id, 100_000, 1_000, BASE_LAMPORTS);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.pay_instruction(program_id, 50_000),
        &case.accounts,
        Check::err(ProgramError::Custom(
            SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
        )),
    );
}

#[test]
fn pay_wrong_outer_count_fails_custom_1() {
    let (mollusk, program_id) = make_product_mollusk();
    let case = PayCase::new(&program_id, 1_000, BASE_LAMPORTS, BASE_LAMPORTS);
    // Drop system role → num_accounts != 4.
    let metas = case.metas[..3].to_vec();
    let accounts = case.accounts[..3].to_vec();
    let ix = Instruction::new_with_bytes(program_id, &pay_ix_data(1000), metas);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix,
        &accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

