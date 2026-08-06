//! # ADR-0030 E4 + ADR-0032 U1 MiniAmmHybrid Mollusk engineering pin.
//!
//! Builds `runtime-tests/solana/fixtures/MiniAmmHybrid.lean` through ordinary
//! `proof-forge-next build --target solana --profile solana-sbpf-cpi-elf-v1`
//! (full-body hybrid: zero CPI sites, multi-block/Map + context.caller) and
//! loads the manifest-bound `MiniAmmHybrid.so` into Mollusk.
//!
//! Product surface (EmitSbpfAsm discriminator ABI, not handlerId):
//! - `initialize()` disc `initialize()` — state w+s (plan); hybrid asm wants 2
//! - `addLiquidity(amount0, amount1)` — state w + pf_caller signer
//! - `swap0to1(amountIn)` — state w (plan); hybrid asm still checks 2 accounts
//! - views `getReserve0` / `getReserve1` / `getTotalSupply` / `balanceOf(who)`
//!
//! State layout (exactDataLen=392):
//! - header layout marker + reserve0/1 + totalSupply + scratch (4×UInt64)
//! - balances: Map Principal UInt64 dense cap-4 → 44 leaves
//!   (per slot: occ + 9 Principal key leaves + val)
//!
//! **Account ABI (sole CPI-rail hybrid)**: every handler requires
//! `num_accounts == 2` — account[0] state + account[1] zero-data `pf_caller`
//! (signer when used as `context.caller`). Instruction data sits after both
//! accounts' ABIv1 virtual growth spans (EmitSbpfAsm `computeInputLayoutWithCallerV1`).
//!
//! Engineering only: non-formal, non-mainnet, hybrid has no sol_invoke*.
//!
//! Env (optional):
//! - `PROOF_FORGE_MINIAMM_HYBRID_OUT` — existing product output tree
//! - `PROOF_FORGE_TOOL_ROOT` — locked sbpf tool root (finalize)

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, instruction_data, instruction_discriminator,
        layout_marker, state_account, StateField, BASE_LAMPORTS, CHECK_OR_UNKNOWN,
        STATE_HEADER_BYTES,
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
const PROGRAM_NAME: &str = "MiniAmmHybrid";
const MODULE_NAME: &str = "Examples.MiniAmmHybrid";
const SOURCE_REL: &str = "runtime-tests/solana/fixtures/MiniAmmHybrid.lean";
/// Canonical ProgramV1 source identity for the tracked fixture above.
const EXPECTED_SOURCE_HASH: &str =
    "604c96c008649e53e35a59d8f5fbf7b10e632b53764c65fb2c23e4656afc4e18";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

/// Plan/LowerSemantic: 4 scalar UInt64 + Map Principal UInt64 cap-4 (44 leaves).
const SCALAR_COUNT: usize = 4;
const MAP_LEAF_COUNT: usize = 44;
const TOTAL_FIELDS: usize = SCALAR_COUNT + MAP_LEAF_COUNT; // 48
const EXACT_DATA_LEN: usize = STATE_HEADER_BYTES + TOTAL_FIELDS * 8; // 392
const MAP_SLOTS: usize = 4;
const MAP_LEAVES_PER_SLOT: usize = 11; // occ + 9 principal + val
const PRINCIPAL_LEAF_COUNT: usize = 9;

const EXPECTED_LAYOUT_MARKER_HEX: &str = "59796935962de4e1";

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
        "product output must remain bound to the tracked MiniAmmHybrid source"
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
        if let Ok(existing) = env::var("PROOF_FORGE_MINIAMM_HYBRID_OUT") {
            let path = PathBuf::from(existing);
            let so = format!("{PROGRAM_NAME}.so");
            let _elf = read_manifest_leaf_bytes(&path, &so, FINALIZED_EXTRA);
            return path;
        }

        let root = repo_root();
        let out = root.join("build/v2/solana-miniamm-hybrid");
        if out.join("manifest.json").is_file() && out.join(format!("{PROGRAM_NAME}.so")).is_file() {
            if let Ok(elf) =
                std::panic::catch_unwind(|| read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.so"), FINALIZED_EXTRA))
            {
                if elf.starts_with(b"\x7fELF") {
                    // Re-validate source hash binding; rebuild if fixture drifted.
                    if let Ok(bytes) = fs::read(out.join("manifest.json")) {
                        if let Ok(manifest) = serde_json::from_slice::<OutputManifest>(&bytes) {
                            if manifest.source_hash == EXPECTED_SOURCE_HASH {
                                return out;
                            }
                        }
                    }
                }
            }
        }

        if out.exists() {
            fs::remove_dir_all(&out).expect("clean prior MiniAmmHybrid product out");
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
            "product CLI build failed for MiniAmmHybrid (status={status})"
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
            !asm_text.contains("sol_invoke"),
            "full-body hybrid must not emit sol_invoke (zero CPI sites)"
        );
        assert!(
            asm_text.contains("caller_principal_leaf"),
            "product assembly must load caller principal for context.caller"
        );
        assert!(
            asm_text.contains("addLiquidity"),
            "product assembly must export addLiquidity"
        );
        assert!(
            asm_text.contains("swap0to1"),
            "product assembly must export swap0to1"
        );
        out
    })
    .clone()
}

fn product_assembly_text() -> String {
    let out = ensure_product_output();
    let assembly =
        read_manifest_leaf_bytes(&out, &format!("{PROGRAM_NAME}.s"), MATERIALIZED_BASE);
    String::from_utf8(assembly).expect("assembly utf-8")
}

/// Residual signature: entrypoint forces 1 account while caller handlers need 2.
/// When this returns false, multi-account hybrid layout is ready for success paths.
fn multi_account_layout_residual_present(asm: &str) -> bool {
    asm.contains("check num_accounts == 1")
        && asm.contains("check num_accounts == 2")
        && asm.contains("caller_principal_leaf")
}

fn product_program_id() -> Pubkey {
    // Distinct fixed id for Mollusk registration ('M' for MiniAmm).
    Pubkey::new_from_array([0x4d; 32])
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

// ---------------------------------------------------------------------------
// Independent layout + math oracles (not product plan)
// ---------------------------------------------------------------------------

fn balance_leaf_names() -> &'static [&'static str] {
    static NAMES: OnceLock<Vec<&'static str>> = OnceLock::new();
    NAMES
        .get_or_init(|| {
            (0..MAP_LEAF_COUNT)
                .map(|i| {
                    Box::leak(format!("balances_{i}").into_boxed_str()) as &'static str
                })
                .collect()
        })
        .as_slice()
}

fn miniamm_fields() -> Vec<StateField> {
    let mut fields = Vec::with_capacity(TOTAL_FIELDS);
    let scalars: [(&'static str, u64); 4] = [
        ("reserve0", 0),
        ("reserve1", 1),
        ("totalSupply", 2),
        ("scratch", 3),
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
            source_id: 4,
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
    assert_eq!(
        format!("{marker:016x}"),
        EXPECTED_LAYOUT_MARKER_HEX,
        "independent layout marker must match product plan initializedMarker"
    );
    marker
}

/// Pack Principal T12 leaves from a Solana pubkey (len=32 + 4 key words + 4 zero).
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

/// Empty initialized MiniAmm state (post-init): marker + all zero fields.
fn empty_initialized_state() -> Vec<u8> {
    let mut data = vec![0u8; EXACT_DATA_LEN];
    data[..8].copy_from_slice(&layout_marker_u64().to_le_bytes());
    data
}

/// Uninitialized state account (zero header, exact length) for init.
fn uninitialized_state() -> Vec<u8> {
    vec![0u8; EXACT_DATA_LEN]
}

/// Build state with scalar reserves + optional map entries keyed by Principal leaves.
fn state_with(
    reserve0: u64,
    reserve1: u64,
    total_supply: u64,
    scratch: u64,
    entries: &[([u64; PRINCIPAL_LEAF_COUNT], u64)],
) -> Vec<u8> {
    assert!(entries.len() <= MAP_SLOTS);
    let mut data = empty_initialized_state();
    data[8..16].copy_from_slice(&reserve0.to_le_bytes());
    data[16..24].copy_from_slice(&reserve1.to_le_bytes());
    data[24..32].copy_from_slice(&total_supply.to_le_bytes());
    data[32..40].copy_from_slice(&scratch.to_le_bytes());
    let map_base = STATE_HEADER_BYTES + SCALAR_COUNT * 8;
    for (slot, (key_leaves, val)) in entries.iter().enumerate() {
        let base = map_base + slot * MAP_LEAVES_PER_SLOT * 8;
        data[base..base + 8].copy_from_slice(&1u64.to_le_bytes()); // occ
        for (i, leaf) in key_leaves.iter().enumerate() {
            let off = base + 8 + i * 8;
            data[off..off + 8].copy_from_slice(&leaf.to_le_bytes());
        }
        let val_off = base + 8 + PRINCIPAL_LEAF_COUNT * 8;
        data[val_off..val_off + 8].copy_from_slice(&val.to_le_bytes());
    }
    data
}

/// Independent MiniAmm math (Examples/MiniAmm honest subset).
fn oracle_first_mint(amount0: u64) -> u64 {
    amount0
}

fn oracle_later_mint(amount0: u64, total_supply: u64, reserve0: u64) -> u64 {
    amount0
        .checked_mul(total_supply)
        .expect("oracle mul")
        .checked_div(reserve0)
        .expect("oracle div")
}

fn oracle_swap0to1(amount_in: u64, reserve0: u64, reserve1: u64) -> u64 {
    let num = amount_in.checked_mul(reserve1).expect("oracle mul");
    let den = reserve0.checked_add(amount_in).expect("oracle add");
    num.checked_div(den).expect("oracle div")
}

fn disc_initialize() -> String {
    instruction_discriminator("initialize", 0)
}

fn disc_add_liquidity() -> String {
    instruction_discriminator("addLiquidity", 2)
}

fn disc_swap0to1() -> String {
    instruction_discriminator("swap0to1", 1)
}

fn disc_get_reserve0() -> String {
    instruction_discriminator("getReserve0", 0)
}

fn disc_get_total_supply() -> String {
    instruction_discriminator("getTotalSupply", 0)
}

fn disc_balance_of() -> String {
    instruction_discriminator("balanceOf", 9)
}

fn ix_initialize(program_id: Pubkey, state_key: Pubkey, caller_key: Pubkey) -> Instruction {
    // Sole CPI-rail hybrid: always state + pf_caller (even when body ignores caller).
    Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_initialize(), &[]),
        vec![
            AccountMeta::new(state_key, true),
            AccountMeta::new_readonly(caller_key, true),
        ],
    )
}

fn ix_add_liquidity(
    program_id: Pubkey,
    state_key: Pubkey,
    caller_key: Pubkey,
    amount0: u64,
    amount1: u64,
) -> Instruction {
    Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_add_liquidity(), &[amount0, amount1]),
        vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new_readonly(caller_key, true),
        ],
    )
}

fn ix_swap0to1(
    program_id: Pubkey,
    state_key: Pubkey,
    caller_key: Pubkey,
    amount_in: u64,
) -> Instruction {
    // Hybrid admitCaller: always two accounts (state + pf_caller), even if
    // this handler does not read context.caller.
    Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_swap0to1(), &[amount_in]),
        vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new_readonly(caller_key, true),
        ],
    )
}

// ---------------------------------------------------------------------------
// Product tree / plan / layout pins (always run)
// ---------------------------------------------------------------------------

#[test]
fn product_tree_is_manifest_bound_cpi_hybrid() {
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

    let roles = plan["accountRoles"].as_array().expect("accountRoles");
    assert_eq!(roles.len(), 2);
    assert_eq!(roles[0]["name"], serde_json::json!("state"));
    assert_eq!(roles[1]["name"], serde_json::json!("pf_caller"));

    let handlers = plan["handlers"].as_array().expect("handlers");
    assert_eq!(handlers.len(), 7, "init + addLiquidity + swap + 4 views");
    assert_eq!(handlers[0]["name"], serde_json::json!("init"));
    assert_eq!(handlers[1]["name"], serde_json::json!("addLiquidity"));
    assert_eq!(handlers[2]["name"], serde_json::json!("swap0to1"));
    assert_eq!(handlers[3]["name"], serde_json::json!("getReserve0"));
    assert_eq!(handlers[4]["name"], serde_json::json!("getReserve1"));
    assert_eq!(handlers[5]["name"], serde_json::json!("getTotalSupply"));
    assert_eq!(handlers[6]["name"], serde_json::json!("balanceOf"));

    // addLiquidity must require pf_caller outer signer.
    let add_uses = handlers[1]["accountUses"].as_array().expect("add uses");
    assert_eq!(add_uses.len(), 2);
    assert_eq!(add_uses[1]["outerSigner"], serde_json::json!(true));
    assert_eq!(add_uses[1]["outerWritable"], serde_json::json!(false));

    let schemas = plan["stateSchemas"].as_array().expect("stateSchemas");
    assert_eq!(schemas[0]["exactDataLen"], serde_json::json!(EXACT_DATA_LEN));
    assert_eq!(
        schemas[0]["initializedMarker"],
        serde_json::json!(EXPECTED_LAYOUT_MARKER_HEX)
    );

    let ir = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-ir.json"),
        MATERIALIZED_BASE,
    );
    let ir_text = String::from_utf8(ir).expect("ir utf-8");
    assert!(
        ir_text.contains("proof-forge.solana.full-body-hybrid-ir.v1"),
        "cpi-ir must mark full-body hybrid"
    );
    assert!(
        ir_text.contains("\"admitCaller\":true"),
        "cpi-ir must admitCaller for context.caller"
    );

    let bindings = read_manifest_leaf_bytes(
        &out,
        &format!("{PROGRAM_NAME}.cpi-bindings.json"),
        MATERIALIZED_BASE,
    );
    let bindings_text = String::from_utf8(bindings).expect("bindings utf-8");
    assert!(bindings_text.contains("\"fullBodyHybrid\":true"));
    assert!(bindings_text.contains(PROGRAM_NAME));
}

#[test]
fn independent_layout_marker_matches_plan() {
    let marker = layout_marker_u64();
    assert_eq!(format!("{marker:016x}"), EXPECTED_LAYOUT_MARKER_HEX);
    assert_eq!(EXACT_DATA_LEN, 392);
    assert_eq!(empty_initialized_state().len(), EXACT_DATA_LEN);
}

#[test]
fn independent_math_oracle_matches_miniamm_subset() {
    // first deposit: LP = amount0
    assert_eq!(oracle_first_mint(100), 100);
    // later: LP = amount0 * totalSupply / reserve0
    assert_eq!(oracle_later_mint(50, 100, 100), 50);
    // swap0to1: amountIn * r1 / (r0 + amountIn)
    assert_eq!(oracle_swap0to1(50, 100, 200), 66);
}

#[test]
fn discriminators_match_emit_sbpf_domain() {
    // Full-body hybrid uses EmitSbpfAsm discriminator domain (not handlerId).
    assert_eq!(disc_initialize().len(), 16);
    assert_eq!(disc_add_liquidity().len(), 16);
    assert_eq!(disc_swap0to1().len(), 16);
    assert_eq!(disc_get_reserve0().len(), 16);
    assert_eq!(disc_get_total_supply().len(), 16);
    assert_eq!(disc_balance_of().len(), 16);
    // Cross-check against known LE imm constants from product assembly.
    let asm = product_assembly_text();
    let init_le = u64::from_le_bytes(hex::decode(disc_initialize()).unwrap().try_into().unwrap());
    let add_le =
        u64::from_le_bytes(hex::decode(disc_add_liquidity()).unwrap().try_into().unwrap());
    let swap_le = u64::from_le_bytes(hex::decode(disc_swap0to1()).unwrap().try_into().unwrap());
    assert!(
        asm.contains(&format!("0x{init_le:x}")) || asm.contains(&format!("0x{init_le:016x}")),
        "assembly must embed initialize discriminator"
    );
    assert!(
        asm.contains(&format!("0x{add_le:x}")) || asm.contains(&format!("0x{add_le:016x}")),
        "assembly must embed addLiquidity discriminator"
    );
    assert!(
        asm.contains(&format!("0x{swap_le:x}")) || asm.contains(&format!("0x{swap_le:016x}")),
        "assembly must embed swap0to1 discriminator"
    );
}

#[test]
fn assembly_zero_cpi_and_caller_principal() {
    let asm = product_assembly_text();
    assert!(!asm.contains("sol_invoke"));
    assert!(asm.contains("caller_principal_leaf"));
    assert!(asm.contains(".globl entrypoint"));
    assert!(asm.contains("addLiquidity"));
    assert!(asm.contains("swap0to1"));
}

// ---------------------------------------------------------------------------
// Multi-account layout pin (sole CPI-rail hybrid)
// ---------------------------------------------------------------------------

#[test]
fn admit_caller_layout_entrypoint_and_init() {
    let asm = product_assembly_text();
    assert!(
        !multi_account_layout_residual_present(&asm),
        "entrypoint/handler account-count residual must be closed"
    );
    assert!(
        !asm.contains("check num_accounts == 1"),
        "admitCaller hybrid must not emit single-account entrypoint gate"
    );
    assert!(
        asm.contains("check num_accounts == 2"),
        "admitCaller hybrid requires num_accounts == 2"
    );
    assert!(
        asm.contains("ACC1_HEADER"),
        "admitCaller layout must define ACC1_HEADER equ"
    );
    // One-account IX fails closed at entrypoint.
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x20);
    let state = state_account(&program_id, uninitialized_state());
    let one_account_ix = Instruction::new_with_bytes(
        program_id,
        &instruction_data(&disc_initialize(), &[]),
        vec![AccountMeta::new(state_key, true)],
    );
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &one_account_ix,
        &[(state_key, state.clone())],
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
    // Two-account init succeeds.
    let caller_key = fixed_key(0x21);
    let result = mollusk.process_and_validate_instruction(
        &ix_initialize(program_id, state_key, caller_key),
        &[
            (state_key, state),
            (caller_key, system_empty_account(BASE_LAMPORTS)),
        ],
        &[Check::success()],
    );
    let post = account_by_key(&result.resulting_accounts, &state_key);
    assert_eq!(post.data, empty_initialized_state());
}

// ---------------------------------------------------------------------------
// Success-path Mollusk (sole CPI-rail hybrid, state + pf_caller)
// ---------------------------------------------------------------------------

/// (a) init zeros state and writes layout marker.
#[test]
fn a_init_initializes_empty_pool() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x30);
    let caller_key = fixed_key(0x31);
    let state = state_account(&program_id, uninitialized_state());
    let result = mollusk.process_and_validate_instruction(
        &ix_initialize(program_id, state_key, caller_key),
        &[
            (state_key, state),
            (caller_key, system_empty_account(BASE_LAMPORTS)),
        ],
        &[Check::success()],
    );
    let post = account_by_key(&result.resulting_accounts, &state_key);
    assert_eq!(post.data, empty_initialized_state());
    assert_eq!(post.data.len(), EXACT_DATA_LEN);
    assert_eq!(post.owner, program_id);
}

/// (b) first addLiquidity mints LP = amount0 to pf_caller Principal map slot.
#[test]
fn b_first_add_liquidity_mints_lp_to_caller() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x40);
    let caller_key = fixed_key(0x41);
    let amount0 = 100u64;
    let amount1 = 200u64;
    let minted = oracle_first_mint(amount0);
    let caller_leaves = principal_leaves_from_pubkey(&caller_key);
    let expected = state_with(amount0, amount1, minted, minted, &[(caller_leaves, minted)]);

    let result = mollusk.process_and_validate_instruction(
        &ix_add_liquidity(program_id, state_key, caller_key, amount0, amount1),
        &[
            (
                state_key,
                state_account(&program_id, empty_initialized_state()),
            ),
            (caller_key, system_empty_account(BASE_LAMPORTS)),
        ],
        &[
            Check::success(),
            Check::return_data(&minted.to_le_bytes()),
        ],
    );
    let post = account_by_key(&result.resulting_accounts, &state_key);
    assert_eq!(post.data, expected, "first mint LP + reserves + map upsert");
}

/// (c) swap0to1 updates reserves with constant-product amountOut.
#[test]
fn c_swap0to1_updates_reserves() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x50);
    let caller_key = fixed_key(0x51);
    let r0 = 100u64;
    let r1 = 200u64;
    let amount_in = 50u64;
    let amount_out = oracle_swap0to1(amount_in, r0, r1);
    assert_eq!(amount_out, 66);
    let caller_leaves = principal_leaves_from_pubkey(&caller_key);
    let pre = state_with(r0, r1, 100, 100, &[(caller_leaves, 100)]);
    let expected = state_with(
        r0 + amount_in,
        r1 - amount_out,
        100,
        amount_out,
        &[(caller_leaves, 100)],
    );

    let result = mollusk.process_and_validate_instruction(
        &ix_swap0to1(program_id, state_key, caller_key, amount_in),
        &[
            (state_key, state_account(&program_id, pre)),
            (caller_key, system_empty_account(BASE_LAMPORTS)),
        ],
        &[
            Check::success(),
            Check::return_data(&amount_out.to_le_bytes()),
        ],
    );
    let post = account_by_key(&result.resulting_accounts, &state_key);
    assert_eq!(post.data, expected, "swap reserves + scratch amountOut");
}

/// (d) second mint (later formula) credits existing LP balance.
#[test]
fn d_second_add_liquidity_uses_later_formula() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x60);
    let caller_key = fixed_key(0x61);
    let caller_leaves = principal_leaves_from_pubkey(&caller_key);
    // Pre: after first mint 100/200, LP=100.
    let pre = state_with(100, 200, 100, 100, &[(caller_leaves, 100)]);
    let amount0 = 50u64;
    let amount1 = 50u64;
    let minted = oracle_later_mint(amount0, 100, 100);
    assert_eq!(minted, 50);
    let expected = state_with(
        150,
        250,
        150,
        minted,
        &[(caller_leaves, 150)],
    );

    let result = mollusk.process_and_validate_instruction(
        &ix_add_liquidity(program_id, state_key, caller_key, amount0, amount1),
        &[
            (state_key, state_account(&program_id, pre)),
            (caller_key, system_empty_account(BASE_LAMPORTS)),
        ],
        &[
            Check::success(),
            Check::return_data(&minted.to_le_bytes()),
        ],
    );
    let post = account_by_key(&result.resulting_accounts, &state_key);
    assert_eq!(post.data, expected);
}

/// (e) zero amountIn on swap fails closed (assertion) with full snapshot hold.
#[test]
fn e_zero_amount_swap_fails() {
    let (mollusk, program_id) = make_product_mollusk();
    let state_key = fixed_key(0x70);
    let caller_key = fixed_key(0x71);
    let caller_leaves = principal_leaves_from_pubkey(&caller_key);
    let pre = state_with(100, 200, 100, 100, &[(caller_leaves, 100)]);
    // Assertion failed → Custom(0x1002) per LowerSemantic assertionFailedError.
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &ix_swap0to1(program_id, state_key, caller_key, 0),
        &[
            (state_key, state_account(&program_id, pre)),
            (caller_key, system_empty_account(BASE_LAMPORTS)),
        ],
        Check::err(ProgramError::Custom(common::ASSERTION_FAILED)),
    );
}
