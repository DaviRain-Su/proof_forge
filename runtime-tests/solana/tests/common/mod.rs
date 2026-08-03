//! Shared ABI helpers for Solana Mollusk runtime differentials.
//!
//! Discriminator / layout formulas mirror `LowerSemanticV1` and must be
//! computed independently of the product plan (plan is only cross-checked).

use {
    mollusk_svm::{result::Check, Mollusk},
    serde::Deserialize,
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_native_token::LAMPORTS_PER_SOL,
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{
        collections::BTreeMap,
        env, fs,
        os::unix::fs::MetadataExt,
        path::{Path, PathBuf},
    },
};

/// Matches `LowerSemanticV1.discriminatorDomain`.
pub const DISCRIMINATOR_DOMAIN: &str = "proof-forge-solana-v1:";
/// Matches `LowerSemanticV1.layoutDomain`.
pub const LAYOUT_DOMAIN: &str = "proof-forge-solana-layout-v1:";
/// Matches `LowerSemanticV1.stateHeaderBytes`.
pub const STATE_HEADER_BYTES: usize = 8;
/// Matches `LowerSemanticV1.arithmeticOverflowError`.
pub const ARITHMETIC_OVERFLOW: u32 = 0x1001;
/// Matches `LowerSemanticV1.assertionFailedError`.
pub const ASSERTION_FAILED: u32 = 0x1002;
/// Matches `LowerSemanticV1.loopBoundExceededError`.
pub const LOOP_BOUND_EXCEEDED: u32 = 0x1003;
/// Matches `LowerSemanticV1.invalidShiftError`.
pub const INVALID_SHIFT: u32 = 0x1004;
/// Matches `EmitIRV1.declaredErrorBase` (0x2000).
pub const DECLARED_ERROR_BASE: u32 = 0x2000;
/// Check failure / unknown discriminator exit.
pub const CHECK_OR_UNKNOWN: u32 = 1;
pub const BASE_LAMPORTS: u64 = 10 * LAMPORTS_PER_SOL;

const OUTPUT_SCHEMA: &str = "proof-forge.output.v1";
const SOLANA_ELF_PROFILE: &str = "solana-sbpf-elf-v1";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[allow(dead_code)]
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

fn is_lower_hex_64(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn require_regular_single_link(path: &Path, label: &str) -> Result<std::fs::Metadata, String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("{label}: metadata {}: {error}", path.display()))?;
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return Err(format!(
            "{label}: expected regular non-symlink file {}",
            path.display()
        ));
    }
    if metadata.nlink() != 1 {
        return Err(format!(
            "{label}: expected single-link file {}, got nlink={}",
            path.display(),
            metadata.nlink()
        ));
    }
    Ok(metadata)
}

fn manifest_for_output(output_dir: &Path, program_name: &str) -> Result<OutputManifest, String> {
    let root_metadata = fs::symlink_metadata(output_dir)
        .map_err(|error| format!("output root {}: {error}", output_dir.display()))?;
    if root_metadata.file_type().is_symlink() || !root_metadata.file_type().is_dir() {
        return Err(format!(
            "output root must be a non-symlink directory: {}",
            output_dir.display()
        ));
    }
    let manifest_path = output_dir.join("manifest.json");
    require_regular_single_link(&manifest_path, "manifest")?;
    let bytes = fs::read(&manifest_path)
        .map_err(|error| format!("read {}: {error}", manifest_path.display()))?;
    let manifest: OutputManifest = serde_json::from_slice(&bytes)
        .map_err(|error| format!("decode {}: {error}", manifest_path.display()))?;
    if manifest.schema_version != OUTPUT_SCHEMA {
        return Err(format!(
            "manifest schema mismatch: {:?}",
            manifest.schema_version
        ));
    }
    if manifest.target != "solana"
        || manifest.codegen_profile != SOLANA_ELF_PROFILE
        || manifest.artifact_program_name != program_name
        || !manifest.deployable
    {
        return Err(format!(
            "manifest identity mismatch for {program_name}: target={:?} profile={:?} artifact={:?} deployable={}",
            manifest.target,
            manifest.codegen_profile,
            manifest.artifact_program_name,
            manifest.deployable
        ));
    }
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
        if !is_lower_hex_64(value) {
            return Err(format!("manifest {field} must be 64 lowercase hex digits"));
        }
    }

    let expected = [
        (format!("{program_name}.idl.json"), MATERIALIZED_BASE),
        (format!("{program_name}.s"), MATERIALIZED_BASE),
        (format!("{program_name}.sbpf-plan"), MATERIALIZED_BASE),
        (format!("{program_name}.so"), FINALIZED_EXTRA),
    ];
    if manifest.files.len() != expected.len() {
        return Err(format!(
            "manifest files must contain exactly four Solana ELF leaves, got {}",
            manifest.files.len()
        ));
    }
    let mut descriptors: BTreeMap<&str, &ArtifactDescriptor> = BTreeMap::new();
    for descriptor in &manifest.files {
        if descriptors.insert(&descriptor.path, descriptor).is_some() {
            return Err(format!(
                "manifest contains duplicate artifact path {:?}",
                descriptor.path
            ));
        }
        if !is_lower_hex_64(&descriptor.content_sha256) {
            return Err(format!(
                "manifest contentSha256 for {:?} must be 64 lowercase hex digits",
                descriptor.path
            ));
        }
    }
    for (path, role) in expected {
        let descriptor = descriptors
            .get(path.as_str())
            .ok_or_else(|| format!("manifest missing exact artifact path {path:?}"))?;
        if descriptor.role != role {
            return Err(format!(
                "manifest role mismatch for {path:?}: {:?} != {role:?}",
                descriptor.role
            ));
        }
    }
    Ok(manifest)
}

/// Resolve one exact manifest descriptor and return the same bytes that were
/// size/hash checked under a stable-read observation. Runtime consumers must
/// use these bytes directly rather than reopening or searching for the path.
/// Product inspect + the Python gate already validate full tree closure.
pub fn read_manifest_leaf_bytes(
    output_dir: &Path,
    program_name: &str,
    relative_path: &str,
    expected_role: &str,
) -> Result<Vec<u8>, String> {
    let manifest = manifest_for_output(output_dir, program_name)?;
    let matches: Vec<&ArtifactDescriptor> = manifest
        .files
        .iter()
        .filter(|descriptor| descriptor.path == relative_path)
        .collect();
    if matches.len() != 1 {
        return Err(format!(
            "manifest path {relative_path:?} must occur exactly once, got {}",
            matches.len()
        ));
    }
    let descriptor = matches[0];
    if descriptor.role != expected_role {
        return Err(format!(
            "manifest role mismatch for {relative_path:?}: {:?} != {expected_role:?}",
            descriptor.role
        ));
    }
    let path = output_dir.join(relative_path);
    let before = require_regular_single_link(&path, "artifact")?;
    if before.len() != descriptor.size {
        return Err(format!(
            "artifact size mismatch for {relative_path:?}: {} != {}",
            before.len(),
            descriptor.size
        ));
    }
    let bytes = fs::read(&path).map_err(|error| format!("read {}: {error}", path.display()))?;
    let after = require_regular_single_link(&path, "artifact post-read")?;
    if before.dev() != after.dev()
        || before.ino() != after.ino()
        || before.len() != after.len()
        || before.mtime() != after.mtime()
        || before.mtime_nsec() != after.mtime_nsec()
    {
        return Err(format!(
            "artifact changed during stable read: {relative_path:?}"
        ));
    }
    if bytes.len() as u64 != descriptor.size {
        return Err(format!(
            "artifact byte length mismatch for {relative_path:?}: {} != {}",
            bytes.len(),
            descriptor.size
        ));
    }
    let digest = hex::encode(Sha256::digest(&bytes));
    if digest != descriptor.content_sha256 {
        return Err(format!(
            "artifact contentSha256 mismatch for {relative_path:?}"
        ));
    }
    Ok(bytes)
}

/// One state field for layout-marker / account packing (declaration order).
/// `byte_width` is the physical ABI width (1/2/4/8/16/32); widths through 8
/// use an 8-byte pitch, UInt128/256 use 16/32 bytes.
#[derive(Clone, Copy, Debug)]
pub struct StateField {
    pub source_id: u64,
    pub name: &'static str,
    pub byte_offset: usize,
    pub byte_width: usize,
}

/// ABI param type string for discriminator signatures.
/// Int64 keeps historical `"u64"` (matches Lean `abiParamTypeString`).
pub fn abi_param_type_string(byte_width: usize) -> &'static str {
    match byte_width {
        1 => "u8",
        2 => "u16",
        4 => "u32",
        8 => "u64",
        16 => "u128",
        32 => "u256",
        _ => panic!("unsupported fixture ABI byte width {byte_width}"),
    }
}

/// Layout field type suffix (`u8-le` … `u256-le`).
pub fn layout_field_type_suffix(byte_width: usize) -> &'static str {
    match byte_width {
        1 => "u8-le",
        2 => "u16-le",
        4 => "u32-le",
        8 => "u64-le",
        16 => "u128-le",
        32 => "u256-le",
        _ => panic!("unsupported fixture layout byte width {byte_width}"),
    }
}

/// Independent copy of the public slot-pitch contract: widths through UInt64
/// occupy 8 bytes; UInt128/256 occupy 16/32 bytes.
pub fn slot_pitch(byte_width: usize) -> usize {
    assert!(byte_width > 0, "fixture byte width must be positive");
    let limbs = (byte_width + 7) / 8;
    if limbs <= 1 {
        8
    } else {
        limbs * 8
    }
}

/// Independent ABI: sha256 hex of `domain ++ name(u64,...)` → first 16 hex chars.
/// All params are treated as `u64` (historical Counter/LoopSum/… surface).
pub fn instruction_discriminator(name: &str, param_count: usize) -> String {
    instruction_discriminator_with_widths(name, &vec![8usize; param_count])
}

/// Discriminator with explicit per-param byte widths (T8b multi-width ABI).
pub fn instruction_discriminator_with_widths(name: &str, param_widths: &[usize]) -> String {
    let params = param_widths
        .iter()
        .map(|w| abi_param_type_string(*w))
        .collect::<Vec<_>>()
        .join(",");
    let preimage = format!("{DISCRIMINATOR_DOMAIN}{name}({params})");
    let digest = Sha256::digest(preimage.as_bytes());
    hex::encode(digest)[..16].to_string()
}

/// Hex discriminator → 8 instruction-data bytes.
pub fn discriminator_bytes(hex16: &str) -> [u8; 8] {
    let raw = hex::decode(hex16).expect("discriminator must be hex");
    assert_eq!(raw.len(), 8, "discriminator must be 8 bytes");
    let mut out = [0u8; 8];
    out.copy_from_slice(&raw);
    out
}

/// `layoutMarker` = firstWordBE(sha256(layoutDomain ++ layoutSignature)).
pub fn layout_marker(fields: &[StateField]) -> u64 {
    let field_sigs: Vec<String> = fields
        .iter()
        .map(|f| {
            format!(
                "{}:{}:0:{}:{}:{}",
                f.source_id,
                f.name,
                f.byte_offset,
                f.byte_width,
                layout_field_type_suffix(f.byte_width)
            )
        })
        .collect();
    let layout_sig = format!("{}|{}", fields.len(), field_sigs.join("|"));
    let digest = Sha256::digest(format!("{LAYOUT_DOMAIN}{layout_sig}").as_bytes());
    let mut value: u64 = 0;
    for &b in &digest[..8] {
        value = (value << 8) | u64::from(b);
    }
    value
}

/// Single-field Counter/LoopSum/MathOps/… layout (header + one u64).
pub fn single_field(name: &'static str) -> [StateField; 1] {
    [StateField {
        source_id: 0,
        name,
        byte_offset: STATE_HEADER_BYTES,
        byte_width: 8,
    }]
}

/// Single field with explicit ABI width (T8b multi-width state).
pub fn single_field_width(name: &'static str, byte_width: usize) -> [StateField; 1] {
    [StateField {
        source_id: 0,
        name,
        byte_offset: STATE_HEADER_BYTES,
        byte_width,
    }]
}

/// Two-field MultiField layout (header + a + b).
pub fn two_fields(a: &'static str, b: &'static str) -> [StateField; 2] {
    [
        StateField {
            source_id: 0,
            name: a,
            byte_offset: STATE_HEADER_BYTES,
            byte_width: 8,
        },
        StateField {
            source_id: 1,
            name: b,
            byte_offset: STATE_HEADER_BYTES + 8,
            byte_width: 8,
        },
    ]
}

/// Array UInt64 N flatten: leaf names `slots_0`… share `source_id` 0 (ArrayState).
pub fn array_u64_leaves(n: usize) -> Vec<StateField> {
    (0..n)
        .map(|i| {
            let name: &'static str = match i {
                0 => "slots_0",
                1 => "slots_1",
                2 => "slots_2",
                3 => "slots_3",
                _ => panic!("array_u64_leaves: only n≤4 supported in fixture helper"),
            };
            StateField {
                source_id: 0,
                name,
                byte_offset: STATE_HEADER_BYTES + i * 8,
                byte_width: 8,
            }
        })
        .collect()
}

/// Multi-field layout with explicit physical widths and canonical slot pitch.
pub fn fields_with_widths(specs: &[(&'static str, usize)]) -> Vec<StateField> {
    let mut next_offset = STATE_HEADER_BYTES;
    specs
        .iter()
        .enumerate()
        .map(|(i, (name, byte_width))| {
            let field = StateField {
                source_id: i as u64,
                name,
                byte_offset: next_offset,
                byte_width: *byte_width,
            };
            next_offset += slot_pitch(*byte_width);
            field
        })
        .collect()
}

pub fn exact_data_len(field_count: usize) -> usize {
    STATE_HEADER_BYTES + field_count * 8
}

pub fn exact_data_len_for_fields(fields: &[StateField]) -> usize {
    fields
        .iter()
        .map(|field| field.byte_offset + slot_pitch(field.byte_width))
        .max()
        .unwrap_or(STATE_HEADER_BYTES)
}

/// Parse `.handler <hex16> <name> ...` lines from product plan text.
pub fn parse_plan_handlers(plan_text: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for line in plan_text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix(".handler ") {
            let mut parts = rest.split_whitespace();
            let Some(hex) = parts.next() else { continue };
            let Some(name) = parts.next() else { continue };
            out.insert(name.to_string(), hex.to_string());
        }
    }
    out
}

/// Cross-check independent Rust discriminators against manifest-bound product
/// plan bytes. All params assumed u64 (historical fixtures).
pub fn assert_discriminators_match_plan(plan_bytes: &[u8], expected: &[(&str, usize)]) {
    let expected_w: Vec<(&str, Vec<usize>)> = expected
        .iter()
        .map(|(name, arity)| (*name, vec![8usize; *arity]))
        .collect();
    assert_discriminators_match_plan_widths(plan_bytes, &expected_w);
}

/// Cross-check discriminators with explicit per-handler param widths (T8b).
pub fn assert_discriminators_match_plan_widths(plan_bytes: &[u8], expected: &[(&str, Vec<usize>)]) {
    let plan = std::str::from_utf8(plan_bytes)
        .unwrap_or_else(|error| panic!("manifest-bound plan is not UTF-8: {error}"));
    let from_plan = parse_plan_handlers(plan);
    for (name, widths) in expected {
        let independent = instruction_discriminator_with_widths(name, widths);
        let plan_hex = from_plan
            .get(*name)
            .unwrap_or_else(|| panic!("plan missing .handler for {name}"));
        assert_eq!(
            plan_hex, &independent,
            "ABI drift: plan discriminator for {name} ({plan_hex}) != independent ({independent})"
        );
    }
    assert_eq!(
        from_plan.len(),
        expected.len(),
        "unexpected handlers in plan: {from_plan:?}"
    );
}

pub fn instruction_data(disc_hex: &str, params: &[u64]) -> Vec<u8> {
    let mut data = discriminator_bytes(disc_hex).to_vec();
    for p in params {
        data.extend_from_slice(&p.to_le_bytes());
    }
    data
}

/// Pack explicit-width params as little-endian u64 limbs at canonical pitch.
pub fn instruction_data_limbs(disc_hex: &str, params: &[(usize, &[u64])]) -> Vec<u8> {
    let mut data = discriminator_bytes(disc_hex).to_vec();
    for (byte_width, limbs) in params {
        let limb_count = (*byte_width + 7) / 8;
        assert_eq!(limbs.len(), limb_count, "wide param limb count");
        let start = data.len();
        for limb in *limbs {
            data.extend_from_slice(&limb.to_le_bytes());
        }
        data.resize(start + slot_pitch(*byte_width), 0);
    }
    data
}

/// Pack account data: [marker LE | field0 LE | field1 LE | …].
pub fn state_data(fields: &[StateField], initialized: bool, values: &[u64]) -> Vec<u8> {
    assert_eq!(fields.len(), values.len(), "field/value arity");
    let len = exact_data_len(fields.len());
    let mut data = vec![0u8; len];
    if initialized {
        data[..8].copy_from_slice(&layout_marker(fields).to_le_bytes());
    }
    for (i, v) in values.iter().enumerate() {
        let off = fields[i].byte_offset;
        data[off..off + 8].copy_from_slice(&v.to_le_bytes());
    }
    data
}

/// Pack state values as explicit little-endian u64 limbs. Unused pitch bytes
/// remain zero, matching freshly initialized account data.
pub fn state_data_limbs(fields: &[StateField], initialized: bool, values: &[&[u64]]) -> Vec<u8> {
    assert_eq!(fields.len(), values.len(), "wide field/value arity");
    let mut data = vec![0u8; exact_data_len_for_fields(fields)];
    if initialized {
        data[..8].copy_from_slice(&layout_marker(fields).to_le_bytes());
    }
    for (field, limbs) in fields.iter().zip(values.iter()) {
        let limb_count = (field.byte_width + 7) / 8;
        assert_eq!(limbs.len(), limb_count, "wide state limb count");
        for (i, limb) in limbs.iter().enumerate() {
            let off = field.byte_offset + i * 8;
            data[off..off + 8].copy_from_slice(&limb.to_le_bytes());
        }
    }
    data
}

pub fn state_account(program_id: &Pubkey, data: Vec<u8>) -> Account {
    let mut account = Account::new(BASE_LAMPORTS, data.len(), program_id);
    account.data = data;
    account
}

/// Byte-exact account observation used by future multi-account/CPI tests.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PresentAccountSnapshot {
    pub lamports: u64,
    pub data: Vec<u8>,
    pub owner: Pubkey,
    pub executable: bool,
    pub rent_epoch: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AccountPresenceSnapshot {
    Absent,
    Present(PresentAccountSnapshot),
}

pub type ExactAccountSnapshot = BTreeMap<Pubkey, AccountPresenceSnapshot>;

/// Snapshot an explicitly enumerated account universe. Every expected key must
/// appear exactly once in `observed`; `None` records an explicit absence. Extra,
/// duplicate, or omitted keys fail instead of being silently ignored.
pub fn snapshot_exact_accounts(
    expected_keys: &[Pubkey],
    observed: &[(Pubkey, Option<Account>)],
) -> Result<ExactAccountSnapshot, String> {
    let mut expected: BTreeMap<Pubkey, ()> = BTreeMap::new();
    for key in expected_keys {
        if expected.insert(*key, ()).is_some() {
            return Err(format!("duplicate expected account key {key}"));
        }
    }
    let mut snapshot = BTreeMap::new();
    for (key, account) in observed {
        if !expected.contains_key(key) {
            return Err(format!("unexpected account key {key}"));
        }
        let value = match account {
            None => AccountPresenceSnapshot::Absent,
            Some(account) => AccountPresenceSnapshot::Present(PresentAccountSnapshot {
                lamports: account.lamports,
                data: account.data.clone(),
                owner: account.owner,
                executable: account.executable,
                rent_epoch: account.rent_epoch,
            }),
        };
        if snapshot.insert(*key, value).is_some() {
            return Err(format!("duplicate observed account key {key}"));
        }
    }
    for key in expected.keys() {
        if !snapshot.contains_key(key) {
            return Err(format!(
                "missing explicit present/absent observation for account key {key}"
            ));
        }
    }
    Ok(snapshot)
}

pub fn build_ix(
    program_id: Pubkey,
    state_key: Pubkey,
    disc_hex: &str,
    params: &[u64],
    writable: bool,
    signer: bool,
) -> Instruction {
    let meta = if writable {
        AccountMeta::new(state_key, signer)
    } else {
        AccountMeta::new_readonly(state_key, signer)
    };
    Instruction::new_with_bytes(program_id, &instruction_data(disc_hex, params), vec![meta])
}

pub fn build_ix_limbs(
    program_id: Pubkey,
    state_key: Pubkey,
    disc_hex: &str,
    params: &[(usize, &[u64])],
    writable: bool,
    signer: bool,
) -> Instruction {
    let meta = if writable {
        AccountMeta::new(state_key, signer)
    } else {
        AccountMeta::new_readonly(state_key, signer)
    };
    Instruction::new_with_bytes(
        program_id,
        &instruction_data_limbs(disc_hex, params),
        vec![meta],
    )
}

/// Counter product env (S3a): the complete published output tree.
pub fn counter_output_dir() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_COUNTER_OUT")
            .expect("PROOF_FORGE_COUNTER_OUT must point at the published Counter output tree"),
    )
}

pub fn counter_plan_bytes() -> Vec<u8> {
    let output = counter_output_dir();
    read_manifest_leaf_bytes(&output, "Counter", "Counter.sbpf-plan", MATERIALIZED_BASE)
        .unwrap_or_else(|error| panic!("Counter plan binding failed: {error}"))
}

/// Fixture product env (S3b): `PROOF_FORGE_FIXTURES_DIR/<Name>/`.
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env::var("PROOF_FORGE_FIXTURES_DIR").expect(
        "PROOF_FORGE_FIXTURES_DIR must point at the directory containing published fixture trees",
    ))
}

pub fn fixture_output_dir(program: &str) -> PathBuf {
    fixtures_dir().join(program)
}

pub fn fixture_plan_bytes(program: &str) -> Vec<u8> {
    let output = fixture_output_dir(program);
    read_manifest_leaf_bytes(
        &output,
        program,
        &format!("{program}.sbpf-plan"),
        MATERIALIZED_BASE,
    )
    .unwrap_or_else(|error| panic!("{program} plan binding failed: {error}"))
}

pub fn make_mollusk(program_id: &Pubkey, output_dir: &Path, program_stem: &str) -> Mollusk {
    let relative_so = format!("{program_stem}.so");
    let elf = read_manifest_leaf_bytes(output_dir, program_stem, &relative_so, FINALIZED_EXTRA)
        .unwrap_or_else(|error| panic!("{program_stem} ELF binding failed: {error}"));
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &elf,
    );
    mollusk
}

pub fn make_counter_mollusk(program_id: &Pubkey) -> Mollusk {
    make_mollusk(program_id, &counter_output_dir(), "Counter")
}

pub fn make_fixture_mollusk(program_id: &Pubkey, program: &str) -> Mollusk {
    make_mollusk(program_id, &fixture_output_dir(program), program)
}

/// #113 / #112: failed check path must return `Custom(CHECK_OR_UNKNOWN)` and
/// preserve the full exact account snapshot (key set + lamports/data/owner/
/// executable/rent_epoch), not just account data bytes.
pub fn assert_custom1_preserves_exact_accounts(
    mollusk: &Mollusk,
    ix: &Instruction,
    accounts: &[(Pubkey, Account)],
) {
    assert_failure_preserves_exact_accounts(
        mollusk,
        ix,
        accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

/// Generalized failure + full present-account snapshot hold.
/// Accepts any Mollusk `Check` (ProgramError::Custom, InstructionError, …).
pub fn assert_failure_preserves_exact_accounts(
    mollusk: &Mollusk,
    ix: &Instruction,
    accounts: &[(Pubkey, Account)],
    failure: Check,
) {
    assert_checks_preserve_exact_accounts(mollusk, ix, accounts, &[failure]);
}

/// Run an exact check set while requiring rollback of every supplied account
/// field. This lets CPI failure tests pin both the error and return-data
/// telemetry without weakening the account snapshot oracle.
pub fn assert_checks_preserve_exact_accounts(
    mollusk: &Mollusk,
    ix: &Instruction,
    accounts: &[(Pubkey, Account)],
    checks: &[Check],
) {
    let expected_keys: Vec<Pubkey> = accounts.iter().map(|(k, _)| *k).collect();
    let pre_obs: Vec<(Pubkey, Option<Account>)> = accounts
        .iter()
        .map(|(k, a)| (*k, Some(a.clone())))
        .collect();
    let pre = snapshot_exact_accounts(&expected_keys, &pre_obs)
        .unwrap_or_else(|e| panic!("pre exact snapshot: {e}"));

    let result = mollusk.process_and_validate_instruction(ix, accounts, checks);

    let post_obs: Vec<(Pubkey, Option<Account>)> = result
        .resulting_accounts
        .iter()
        .map(|(key, account)| (*key, Some(account.clone())))
        .collect();
    let post = snapshot_exact_accounts(&expected_keys, &post_obs)
        .unwrap_or_else(|e| panic!("post exact snapshot: {e}"));
    assert_eq!(
        pre, post,
        "failure must preserve full account snapshot \
         (lamports/data/owner/executable/rent_epoch for every key)"
    );
}

// ---------------------------------------------------------------------------
// #115 harness-only CPI spike helpers (not product proof-forge.output.v1)
// ---------------------------------------------------------------------------

pub const HARNESS_CALLER_ID_BYTES: [u8; 32] = [0x42; 32];
pub const HARNESS_COMPANION_ID_BYTES: [u8; 32] = [0x43; 32];

pub const HARNESS_OP_INVOKE_SUCCESS: u8 = 0x00;
pub const HARNESS_OP_INVOKE_FAIL: u8 = 0x01;
pub const HARNESS_OP_INVOKE_SIGNED: u8 = 0x02;
pub const HARNESS_OP_INVOKE_SIGNED_FAIL: u8 = 0x03;
pub const HARNESS_OP_FORGE_WRITABLE: u8 = 0x10;
pub const HARNESS_OP_FORGE_SIGNER: u8 = 0x11;

pub const HARNESS_PDA_SEED0: &[u8] = b"proof-forge:pda:v1";
pub const HARNESS_STALE_RETURN_DATA: &[u8; 8] = b"stale:v1";
pub const HARNESS_INNER_RETURN_DATA: &[u8; 8] = b"inner:v1";
pub const HARNESS_FAILURE_RETURN_DATA: &[u8; 8] = b"fail:v1!";
pub const ABI_V1_FULL_PREFIX: usize = 88;
pub const ABI_V1_MAX_DATA_INCREASE: usize = 10240;
pub const ABI_V1_MARKER: u8 = 0xff;
pub const ABI_V1_ALIGN: usize = 8;
pub const SOLANA_CPI_MAX_OUTER_ROLES: usize = 16;
pub const SOLANA_CPI_MAX_METAS: usize = 16;
pub const SOLANA_CPI_MAX_SIGNER_GROUPS: usize = 4;
pub const SOLANA_CPI_MAX_SEED_SLICES: usize = 16;
pub const SOLANA_CPI_MAX_BYTES_PER_SEED: usize = 32;

pub fn harness_caller_id() -> Pubkey {
    Pubkey::new_from_array(HARNESS_CALLER_ID_BYTES)
}

pub fn harness_companion_id() -> Pubkey {
    Pubkey::new_from_array(HARNESS_COMPANION_ID_BYTES)
}

pub fn harness_out_dir() -> PathBuf {
    PathBuf::from(env::var("PROOF_FORGE_HARNESS_OUT").expect(
        "PROOF_FORGE_HARNESS_OUT must point at the harness bind directory \
         (scripts/solana_harness_build.sh)",
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessManifestV1 {
    schema: String,
    issue: u64,
    sbpf: String,
    runtime_oracle: HarnessRuntimeOracleV1,
    program_ids: HarnessProgramIdsV1,
    opcodes: HarnessOpcodesV1,
    caller_instruction: HarnessCallerInstructionV1,
    companion_instruction: HarnessCompanionInstructionV1,
    c_struct_sizes: HarnessCStructSizesV1,
    abi_v1: HarnessAbiV1,
    outer_roles: HarnessOuterRolesV1,
    pda: HarnessPdaV1,
    expected_elf_sha256: HarnessElfDigestsV1,
    expected_elf_size: HarnessElfSizesV1,
    reproducibility_note: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessRuntimeOracleV1 {
    mollusk_svm: String,
    agave_syscalls: String,
    solana_program_runtime: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessProgramIdsV1 {
    caller_hex: String,
    companion_hex: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessOpcodesV1 {
    invoke_success: u8,
    invoke_fail: u8,
    invoke_signed: u8,
    invoke_signed_fail: u8,
    forge_writable: u8,
    forge_signer: u8,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessCallerInstructionV1 {
    unsigned_layout: String,
    unsigned_len: usize,
    signed_layout: String,
    signed_len: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessCompanionInstructionV1 {
    layout: String,
    len: usize,
    tags: HarnessCompanionTagsV1,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessCompanionTagsV1 {
    checked_add: u8,
    fail_after_write: u8,
    checked_add_require_signer: u8,
    fail_after_write_require_signer: u8,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct HarnessCStructSizesV1 {
    #[serde(rename = "SolInstruction")]
    sol_instruction: usize,
    #[serde(rename = "SolAccountMeta")]
    sol_account_meta: usize,
    #[serde(rename = "SolAccountInfo")]
    sol_account_info: usize,
    #[serde(rename = "SolSignerSeed")]
    sol_signer_seed: usize,
    #[serde(rename = "SolSignerSeeds")]
    sol_signer_seeds: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessAbiV1 {
    full_prefix_bytes: usize,
    max_permitted_data_increase: usize,
    marker: u8,
    original_data_len_wire: u32,
    rent_epoch: u64,
    align: usize,
    product_caps: HarnessProductCapsV1,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessProductCapsV1 {
    outer_roles: usize,
    cpi_metas: usize,
    signer_groups: usize,
    seed_slices: usize,
    bytes_per_seed: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessOuterRolesV1 {
    unsigned: Vec<String>,
    signed: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HarnessPdaV1 {
    recipe: String,
    seed0_utf8: String,
    seed0_hex: String,
    canonical_bump_search: String,
    bump0_rejected: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct HarnessElfDigestsV1 {
    companion: String,
    caller: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct HarnessElfSizesV1 {
    companion: u64,
    caller: u64,
}

fn decode_harness_manifest(bytes: &[u8]) -> Result<HarnessManifestV1, String> {
    let manifest: HarnessManifestV1 = serde_json::from_slice(bytes)
        .map_err(|error| format!("decode harness manifest: {error}"))?;
    let expect = |condition: bool, message: &str| {
        if condition {
            Ok(())
        } else {
            Err(message.to_string())
        }
    };
    expect(
        manifest.schema == "proof-forge.solana.cpi-harness.v1",
        "schema",
    )?;
    expect(manifest.issue == 115, "issue")?;
    expect(manifest.sbpf == "0.2.2", "sbpf")?;
    expect(
        manifest.runtime_oracle.mollusk_svm == "0.13.4",
        "molluskSvm",
    )?;
    expect(
        manifest.runtime_oracle.agave_syscalls == "4.0.0",
        "agaveSyscalls",
    )?;
    expect(
        manifest.runtime_oracle.solana_program_runtime == "4.0.0",
        "solanaProgramRuntime",
    )?;
    expect(
        manifest.program_ids.caller_hex == hex::encode(HARNESS_CALLER_ID_BYTES),
        "callerHex",
    )?;
    expect(
        manifest.program_ids.companion_hex == hex::encode(HARNESS_COMPANION_ID_BYTES),
        "companionHex",
    )?;
    expect(
        manifest.opcodes.invoke_success == HARNESS_OP_INVOKE_SUCCESS,
        "invokeSuccess",
    )?;
    expect(
        manifest.opcodes.invoke_fail == HARNESS_OP_INVOKE_FAIL,
        "invokeFail",
    )?;
    expect(
        manifest.opcodes.invoke_signed == HARNESS_OP_INVOKE_SIGNED,
        "invokeSigned",
    )?;
    expect(
        manifest.opcodes.invoke_signed_fail == HARNESS_OP_INVOKE_SIGNED_FAIL,
        "invokeSignedFail",
    )?;
    expect(
        manifest.opcodes.forge_writable == HARNESS_OP_FORGE_WRITABLE,
        "forgeWritable",
    )?;
    expect(
        manifest.opcodes.forge_signer == HARNESS_OP_FORGE_SIGNER,
        "forgeSigner",
    )?;
    expect(
        manifest.caller_instruction.unsigned_layout == "opcode:u8 || delta:u64le"
            && manifest.caller_instruction.unsigned_len == 9,
        "caller unsigned instruction",
    )?;
    expect(
        manifest.caller_instruction.signed_layout
            == "opcode:u8 || delta:u64le || seedTag:u64le || bump:u8"
            && manifest.caller_instruction.signed_len == 18,
        "caller signed instruction",
    )?;
    expect(
        manifest.companion_instruction.layout == "tag:u8 || delta:u64le"
            && manifest.companion_instruction.len == 9,
        "companion instruction",
    )?;
    let tags = &manifest.companion_instruction.tags;
    expect(
        tags.checked_add == 0
            && tags.fail_after_write == 1
            && tags.checked_add_require_signer == 2
            && tags.fail_after_write_require_signer == 3,
        "companion tags",
    )?;
    let sizes = &manifest.c_struct_sizes;
    expect(
        sizes.sol_instruction == 40
            && sizes.sol_account_meta == 16
            && sizes.sol_account_info == 56
            && sizes.sol_signer_seed == 16
            && sizes.sol_signer_seeds == 16,
        "C struct sizes",
    )?;
    let abi = &manifest.abi_v1;
    expect(
        abi.full_prefix_bytes == ABI_V1_FULL_PREFIX
            && abi.max_permitted_data_increase == ABI_V1_MAX_DATA_INCREASE
            && abi.marker == ABI_V1_MARKER
            && abi.original_data_len_wire == 0
            && abi.rent_epoch == u64::MAX
            && abi.align == ABI_V1_ALIGN,
        "ABIv1 constants",
    )?;
    let caps = &abi.product_caps;
    expect(
        caps.outer_roles == SOLANA_CPI_MAX_OUTER_ROLES
            && caps.cpi_metas == SOLANA_CPI_MAX_METAS
            && caps.signer_groups == SOLANA_CPI_MAX_SIGNER_GROUPS
            && caps.seed_slices == SOLANA_CPI_MAX_SEED_SLICES
            && caps.bytes_per_seed == SOLANA_CPI_MAX_BYTES_PER_SEED,
        "product caps",
    )?;
    expect(
        manifest.outer_roles.unsigned == ["counter", "companion-program"],
        "unsigned roles",
    )?;
    expect(
        manifest.outer_roles.signed
            == [
                "counter",
                "authorityPda",
                "seedAuthority",
                "companion-program",
            ],
        "signed roles",
    )?;
    let pda = &manifest.pda;
    expect(
        pda.recipe == "current-program-tagged-v1"
            && pda.seed0_utf8 == "proof-forge:pda:v1"
            && pda.seed0_hex == hex::encode(HARNESS_PDA_SEED0)
            && pda.canonical_bump_search == "255..1"
            && pda.bump0_rejected,
        "PDA recipe",
    )?;
    expect(
        is_lower_hex_64(&manifest.expected_elf_sha256.companion)
            && is_lower_hex_64(&manifest.expected_elf_sha256.caller),
        "ELF digests",
    )?;
    expect(
        manifest.expected_elf_size.companion > 0 && manifest.expected_elf_size.caller > 0,
        "ELF sizes",
    )?;
    expect(
        manifest
            .reproducibility_note
            .contains("not a hermetic multi-host formal claim"),
        "reproducibility note",
    )?;
    Ok(manifest)
}

pub fn validate_harness_manifest_bytes(bytes: &[u8]) -> Result<(), String> {
    decode_harness_manifest(bytes).map(|_| ())
}

pub fn committed_harness_manifest_bytes() -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("harness/manifest.json");
    stable_read_harness_file(&path, "harness committed manifest")
}

fn stable_read_harness_file(path: &Path, label: &str) -> Vec<u8> {
    let before = require_regular_single_link(path, label).unwrap_or_else(|e| panic!("{e}"));
    let bytes = fs::read(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let after = require_regular_single_link(path, &format!("{label} post-read"))
        .unwrap_or_else(|e| panic!("{e}"));
    if before.dev() != after.dev()
        || before.ino() != after.ino()
        || before.len() != after.len()
        || before.mtime() != after.mtime()
        || before.mtime_nsec() != after.mtime_nsec()
        || bytes.len() as u64 != before.len()
    {
        panic!("{label} changed during stable read: {}", path.display());
    }
    bytes
}

fn harness_manifest_binding(stem: &str) -> (u64, String) {
    assert!(
        matches!(stem, "caller" | "companion"),
        "unknown harness stem"
    );
    let bytes = committed_harness_manifest_bytes();
    let manifest = decode_harness_manifest(&bytes).unwrap_or_else(|error| panic!("{error}"));
    match stem {
        "caller" => (
            manifest.expected_elf_size.caller,
            manifest.expected_elf_sha256.caller,
        ),
        "companion" => (
            manifest.expected_elf_size.companion,
            manifest.expected_elf_sha256.companion,
        ),
        _ => unreachable!(),
    }
}

/// Stable-read harness ELF and bind it independently to both committed
/// manifest identity and generated sidecars. Replacing a self-consistent
/// `.so/.size/.sha256` trio cannot bypass the committed byte pin.
pub fn read_harness_elf(stem: &str) -> Vec<u8> {
    let dir = harness_out_dir();
    let so = dir.join(format!("{stem}.so"));
    let size_path = dir.join(format!("{stem}.so.size"));
    let hash_path = dir.join(format!("{stem}.so.sha256"));
    let (manifest_size, manifest_hash) = harness_manifest_binding(stem);
    let sidecar_size_bytes = stable_read_harness_file(&size_path, "harness size sidecar");
    let sidecar_size: u64 = std::str::from_utf8(&sidecar_size_bytes)
        .expect("UTF-8 size sidecar")
        .trim()
        .parse()
        .unwrap_or_else(|e| panic!("parse size sidecar: {e}"));
    let sidecar_hash_bytes = stable_read_harness_file(&hash_path, "harness hash sidecar");
    let sidecar_hash = std::str::from_utf8(&sidecar_hash_bytes)
        .expect("UTF-8 hash sidecar")
        .trim();
    assert_eq!(
        sidecar_size, manifest_size,
        "harness size sidecar vs manifest"
    );
    assert_eq!(
        sidecar_hash, manifest_hash,
        "harness hash sidecar vs manifest"
    );

    let bytes = stable_read_harness_file(&so, "harness ELF");
    assert_eq!(
        bytes.len() as u64,
        manifest_size,
        "harness ELF size mismatch"
    );
    let digest = hex::encode(Sha256::digest(&bytes));
    assert_eq!(digest, manifest_hash, "harness {stem}.so sha256 mismatch");
    assert!(
        bytes.starts_with(b"\x7fELF"),
        "harness {stem}.so must be ELF"
    );
    bytes
}

/// Register caller + companion under Loader V3 with exact harness ELF bytes.
pub fn make_harness_mollusk() -> (Mollusk, Pubkey, Pubkey) {
    let caller_id = harness_caller_id();
    let companion_id = harness_companion_id();
    let caller_elf = read_harness_elf("caller");
    let companion_elf = read_harness_elf("companion");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &caller_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &caller_elf,
    );
    mollusk.add_program_with_loader_and_elf(
        &companion_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &companion_elf,
    );
    (mollusk, caller_id, companion_id)
}

pub fn harness_ix_unsigned(opcode: u8, delta: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(9);
    data.push(opcode);
    data.extend_from_slice(&delta.to_le_bytes());
    data
}

pub fn harness_ix_signed(opcode: u8, delta: u64, seed_tag: u64, bump: u8) -> Vec<u8> {
    let mut data = Vec::with_capacity(18);
    data.push(opcode);
    data.extend_from_slice(&delta.to_le_bytes());
    data.extend_from_slice(&seed_tag.to_le_bytes());
    data.push(bump);
    data
}

pub fn companion_counter_account(companion_id: &Pubkey, count: u64) -> Account {
    let mut account = Account::new(BASE_LAMPORTS, 8, companion_id);
    account.data = count.to_le_bytes().to_vec();
    account
}

/// Independent current-program-tagged-v1 PDA search (255..1), using SHA-256 +
/// `Pubkey::create_program_address` only as the off-curve oracle for candidates.
/// Seed layout is constructed here; bump 0 is never searched.
pub fn find_pda_current_program_tagged_v1(
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
        if let Ok(addr) = Pubkey::create_program_address(seeds, program_id) {
            return (addr, bump);
        }
    }
    panic!("no canonical PDA bump in 255..1 for current-program-tagged-v1");
}

// ---------------------------------------------------------------------------
// #118 production-code-generated preflight evidence (still preactivation)
// ---------------------------------------------------------------------------

pub const CPI_PREFLIGHT_PROGRAM_ID_BYTES: [u8; 32] = [0x52; 32];
pub const CPI_PREFLIGHT_INIT_HANDLER_ID: u64 = 0;
pub const CPI_PREFLIGHT_ROUTE_HANDLER_ID: u64 = 1;
pub const CPI_PREFLIGHT_INSPECT_HANDLER_ID: u64 = 2;
const CPI_PREFLIGHT_STEM: &str = "account_roles_preflight";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiPreflightManifestV1 {
    schema: String,
    issue: u64,
    sbpf: String,
    runtime_oracle: CpiPreflightRuntimeOracleV1,
    fixture: CpiPreflightFixtureV1,
    profile: CpiPreflightIdentityV1,
    extension: CpiPreflightExtensionV1,
    boundary: CpiPreflightBoundaryV1,
    program_id_hex: String,
    handlers: CpiPreflightHandlersV1,
    expected_assembly: CpiPreflightArtifactPinV1,
    expected_elf: CpiPreflightArtifactPinV1,
    reproducibility_note: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiPreflightRuntimeOracleV1 {
    mollusk_svm: String,
    agave_syscalls: String,
    solana_program_runtime: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiPreflightFixtureV1 {
    path: String,
    module: String,
    source_sha256: String,
    source_size: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CpiPreflightIdentityV1 {
    id: String,
    digest: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CpiPreflightExtensionV1 {
    id: String,
    version: String,
    digest: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiPreflightBoundaryV1 {
    product_artifact: bool,
    test_preactivation: bool,
    activation_denied: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CpiPreflightHandlersV1 {
    init: u64,
    route: u64,
    inspect: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CpiPreflightArtifactPinV1 {
    sha256: String,
    size: u64,
}

fn decode_cpi_preflight_manifest(bytes: &[u8]) -> Result<CpiPreflightManifestV1, String> {
    let manifest: CpiPreflightManifestV1 = serde_json::from_slice(bytes)
        .map_err(|error| format!("decode CPI preflight manifest: {error}"))?;
    let expect = |condition: bool, message: &str| {
        if condition {
            Ok(())
        } else {
            Err(message.to_string())
        }
    };
    expect(
        manifest.schema == "proof-forge.solana.cpi-preflight-runtime.v1",
        "schema",
    )?;
    expect(manifest.issue == 118, "issue")?;
    expect(manifest.sbpf == "0.2.2", "sbpf")?;
    expect(
        manifest.runtime_oracle.mollusk_svm == "0.13.4"
            && manifest.runtime_oracle.agave_syscalls == "4.0.0"
            && manifest.runtime_oracle.solana_program_runtime == "4.0.0",
        "runtime oracle",
    )?;
    expect(
        manifest.fixture.path == "runtime-tests/solana/fixtures/AccountRoles.lean"
            && manifest.fixture.module == "Examples.AccountRoles"
            && manifest.fixture.source_sha256
                == "9bf45003f14a028320c39890b846d0c3fd16ac01abbb1dc78d1072c6f04cc4f5"
            && manifest.fixture.source_size == 621,
        "fixture identity",
    )?;
    expect(
        manifest.profile.id == "solana-sbpf-cpi-elf-v1"
            && manifest.profile.digest
                == "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1",
        "profile identity",
    )?;
    expect(
        manifest.extension.id == "solana.cpi.accounts"
            && manifest.extension.version == "1.0.0"
            && manifest.extension.digest
                == "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020",
        "extension identity",
    )?;
    expect(
        !manifest.boundary.product_artifact
            && manifest.boundary.test_preactivation
            && manifest.boundary.activation_denied,
        "preactivation boundary",
    )?;
    expect(
        manifest.program_id_hex == hex::encode(CPI_PREFLIGHT_PROGRAM_ID_BYTES),
        "program id",
    )?;
    expect(
        manifest.handlers.init == CPI_PREFLIGHT_INIT_HANDLER_ID
            && manifest.handlers.route == CPI_PREFLIGHT_ROUTE_HANDLER_ID
            && manifest.handlers.inspect == CPI_PREFLIGHT_INSPECT_HANDLER_ID,
        "handler ids",
    )?;
    expect(
        is_lower_hex_64(&manifest.expected_assembly.sha256) && manifest.expected_assembly.size > 0,
        "assembly pin",
    )?;
    expect(
        is_lower_hex_64(&manifest.expected_elf.sha256) && manifest.expected_elf.size > 0,
        "ELF pin",
    )?;
    expect(
        manifest
            .reproducibility_note
            .contains("not proof-forge.output.v1")
            && manifest
                .reproducibility_note
                .contains("not an activated CPI artifact"),
        "preactivation reproducibility note",
    )?;
    Ok(manifest)
}

pub fn validate_cpi_preflight_manifest_bytes(bytes: &[u8]) -> Result<(), String> {
    decode_cpi_preflight_manifest(bytes).map(|_| ())
}

pub fn committed_cpi_preflight_manifest_bytes() -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("preflight/manifest.json");
    stable_read_harness_file(&path, "CPI preflight committed manifest")
}

pub fn cpi_preflight_out_dir() -> PathBuf {
    PathBuf::from(env::var("PROOF_FORGE_CPI_PREFLIGHT_OUT").expect(
        "PROOF_FORGE_CPI_PREFLIGHT_OUT must point at scripts/solana_cpi_preflight_build.sh output",
    ))
}

fn read_cpi_preflight_bound_file(
    suffix: &str,
    expected: &CpiPreflightArtifactPinV1,
    label: &str,
) -> Vec<u8> {
    let out = cpi_preflight_out_dir();
    let committed_manifest = committed_cpi_preflight_manifest_bytes();
    let output_manifest =
        stable_read_harness_file(&out.join("manifest.json"), "CPI preflight output manifest");
    assert_eq!(
        output_manifest, committed_manifest,
        "CPI preflight output manifest must be exact committed bytes"
    );
    let manifest = decode_cpi_preflight_manifest(&committed_manifest)
        .unwrap_or_else(|error| panic!("{error}"));
    let selected = match suffix {
        "s" => &manifest.expected_assembly,
        "so" => &manifest.expected_elf,
        _ => panic!("unknown CPI preflight artifact suffix {suffix}"),
    };
    assert_eq!(selected.size, expected.size, "{label} selected size pin");
    assert_eq!(
        selected.sha256, expected.sha256,
        "{label} selected hash pin"
    );

    let path = out.join(format!("{CPI_PREFLIGHT_STEM}.{suffix}"));
    let size_bytes = stable_read_harness_file(
        &out.join(format!("{CPI_PREFLIGHT_STEM}.{suffix}.size")),
        &format!("{label} size sidecar"),
    );
    let hash_bytes = stable_read_harness_file(
        &out.join(format!("{CPI_PREFLIGHT_STEM}.{suffix}.sha256")),
        &format!("{label} hash sidecar"),
    );
    let sidecar_size: u64 = std::str::from_utf8(&size_bytes)
        .expect("UTF-8 preflight size sidecar")
        .trim()
        .parse()
        .unwrap_or_else(|error| panic!("parse preflight size sidecar: {error}"));
    let sidecar_hash = std::str::from_utf8(&hash_bytes)
        .expect("UTF-8 preflight hash sidecar")
        .trim();
    assert_eq!(sidecar_size, expected.size, "{label} sidecar size");
    assert_eq!(sidecar_hash, expected.sha256, "{label} sidecar hash");

    let bytes = stable_read_harness_file(&path, label);
    assert_eq!(bytes.len() as u64, expected.size, "{label} size");
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        expected.sha256,
        "{label} sha256"
    );
    bytes
}

pub fn read_cpi_preflight_assembly() -> Vec<u8> {
    let manifest_bytes = committed_cpi_preflight_manifest_bytes();
    let manifest =
        decode_cpi_preflight_manifest(&manifest_bytes).unwrap_or_else(|error| panic!("{error}"));
    let bytes =
        read_cpi_preflight_bound_file("s", &manifest.expected_assembly, "CPI preflight assembly");
    assert!(
        bytes
            .windows(b"TEST-PREACTIVATION ONLY".len())
            .any(|window| window == b"TEST-PREACTIVATION ONLY"),
        "preflight assembly boundary banner"
    );
    assert!(
        !bytes
            .windows(b"sol_invoke".len())
            .any(|window| window == b"sol_invoke"),
        "#118 preflight assembly must not invoke"
    );
    bytes
}

pub fn read_cpi_preflight_elf() -> Vec<u8> {
    let manifest_bytes = committed_cpi_preflight_manifest_bytes();
    let manifest =
        decode_cpi_preflight_manifest(&manifest_bytes).unwrap_or_else(|error| panic!("{error}"));
    let bytes = read_cpi_preflight_bound_file("so", &manifest.expected_elf, "CPI preflight ELF");
    assert!(
        bytes.starts_with(b"\x7fELF"),
        "CPI preflight output must be ELF"
    );
    bytes
}

pub fn cpi_preflight_program_id() -> Pubkey {
    Pubkey::new_from_array(CPI_PREFLIGHT_PROGRAM_ID_BYTES)
}

pub fn make_cpi_preflight_mollusk() -> (Mollusk, Pubkey) {
    let program_id = cpi_preflight_program_id();
    let elf = read_cpi_preflight_elf();
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &elf,
    );
    (mollusk, program_id)
}

pub fn cpi_preflight_ix_data(handler_id: u64) -> [u8; 8] {
    handler_id.to_le_bytes()
}

// ---------------------------------------------------------------------------
// #119 production-code-generated unsigned companion CPI evidence (preactivation)
// ---------------------------------------------------------------------------

pub const CPI_UNSIGNED_PROGRAM_ID_BYTES: [u8; 32] = [0x55; 32];
pub const CPI_UNSIGNED_INIT_HANDLER_ID: u64 = 0;
pub const CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID: u64 = 1;
pub const CPI_UNSIGNED_FAIL_ONCE_HANDLER_ID: u64 = 2;
pub const CPI_UNSIGNED_INSPECT_HANDLER_ID: u64 = 3;
const CPI_UNSIGNED_STEM: &str = "companion_cpi_unsigned";
const CPI_UNSIGNED_COMPANION_ELF_SHA256: &str =
    "c8738f1220c49c309ffe820ca397ae25540d6be29c6153934abd8548fa08c4b9";
const CPI_UNSIGNED_COMPANION_ELF_SIZE: u64 = 1776;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiUnsignedManifestV1 {
    schema: String,
    issue: u64,
    sbpf: String,
    runtime_oracle: CpiPreflightRuntimeOracleV1,
    fixture: CpiPreflightFixtureV1,
    profile: CpiPreflightIdentityV1,
    extension: CpiPreflightExtensionV1,
    boundary: CpiPreflightBoundaryV1,
    program_id_hex: String,
    companion_program_id_hex: String,
    companion: CpiUnsignedCompanionV1,
    handlers: CpiUnsignedHandlersV1,
    expected_assembly: CpiPreflightArtifactPinV1,
    expected_elf: CpiPreflightArtifactPinV1,
    reproducibility_note: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiUnsignedCompanionV1 {
    package: String,
    program_id_hex: String,
    elf_sha256: String,
    elf_size: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CpiUnsignedHandlersV1 {
    init: u64,
    invoke_once: u64,
    fail_once: u64,
    inspect: u64,
}

fn decode_cpi_unsigned_manifest(bytes: &[u8]) -> Result<CpiUnsignedManifestV1, String> {
    let manifest: CpiUnsignedManifestV1 = serde_json::from_slice(bytes)
        .map_err(|error| format!("decode CPI unsigned manifest: {error}"))?;
    let expect = |condition: bool, message: &str| {
        if condition {
            Ok(())
        } else {
            Err(message.to_string())
        }
    };
    expect(
        manifest.schema == "proof-forge.solana.cpi-unsigned-runtime.v1",
        "schema",
    )?;
    expect(manifest.issue == 119, "issue")?;
    expect(manifest.sbpf == "0.2.2", "sbpf")?;
    expect(
        manifest.runtime_oracle.mollusk_svm == "0.13.4"
            && manifest.runtime_oracle.agave_syscalls == "4.0.0"
            && manifest.runtime_oracle.solana_program_runtime == "4.0.0",
        "runtime oracle",
    )?;
    expect(
        manifest.fixture.path == "runtime-tests/solana/fixtures/CompanionCpi.lean"
            && manifest.fixture.module == "Examples.CompanionCpi"
            && is_lower_hex_64(&manifest.fixture.source_sha256)
            && manifest.fixture.source_size > 0,
        "fixture identity",
    )?;
    expect(
        manifest.profile.id == "solana-sbpf-cpi-elf-v1"
            && manifest.profile.digest
                == "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1",
        "profile identity",
    )?;
    expect(
        manifest.extension.id == "solana.cpi.accounts"
            && manifest.extension.version == "1.0.0"
            && manifest.extension.digest
                == "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020",
        "extension identity",
    )?;
    expect(
        !manifest.boundary.product_artifact
            && manifest.boundary.test_preactivation
            && manifest.boundary.activation_denied,
        "preactivation boundary",
    )?;
    expect(
        manifest.program_id_hex == hex::encode(CPI_UNSIGNED_PROGRAM_ID_BYTES),
        "program id",
    )?;
    expect(
        manifest.companion_program_id_hex == hex::encode(HARNESS_COMPANION_ID_BYTES)
            && manifest.companion.package == "companion-v1"
            && manifest.companion.program_id_hex == hex::encode(HARNESS_COMPANION_ID_BYTES)
            && manifest.companion.elf_sha256 == CPI_UNSIGNED_COMPANION_ELF_SHA256
            && manifest.companion.elf_size == CPI_UNSIGNED_COMPANION_ELF_SIZE,
        "exact #115 companion identity",
    )?;
    expect(
        manifest.handlers.init == CPI_UNSIGNED_INIT_HANDLER_ID
            && manifest.handlers.invoke_once == CPI_UNSIGNED_INVOKE_ONCE_HANDLER_ID
            && manifest.handlers.fail_once == CPI_UNSIGNED_FAIL_ONCE_HANDLER_ID
            && manifest.handlers.inspect == CPI_UNSIGNED_INSPECT_HANDLER_ID,
        "handler ids",
    )?;
    expect(
        is_lower_hex_64(&manifest.expected_assembly.sha256) && manifest.expected_assembly.size > 0,
        "assembly pin",
    )?;
    expect(
        is_lower_hex_64(&manifest.expected_elf.sha256) && manifest.expected_elf.size > 0,
        "ELF pin",
    )?;
    expect(
        manifest
            .reproducibility_note
            .contains("not proof-forge.output.v1")
            && manifest
                .reproducibility_note
                .contains("not an activated CPI artifact"),
        "preactivation reproducibility note",
    )?;
    Ok(manifest)
}

pub fn validate_cpi_unsigned_manifest_bytes(bytes: &[u8]) -> Result<(), String> {
    decode_cpi_unsigned_manifest(bytes).map(|_| ())
}

pub fn committed_cpi_unsigned_manifest_bytes() -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("unsigned/manifest.json");
    stable_read_harness_file(&path, "CPI unsigned committed manifest")
}

pub fn cpi_unsigned_out_dir() -> PathBuf {
    PathBuf::from(env::var("PROOF_FORGE_CPI_UNSIGNED_OUT").expect(
        "PROOF_FORGE_CPI_UNSIGNED_OUT must point at scripts/solana_cpi_unsigned_build.sh output",
    ))
}

fn read_cpi_unsigned_bound_file(
    suffix: &str,
    expected: &CpiPreflightArtifactPinV1,
    label: &str,
) -> Vec<u8> {
    let out = cpi_unsigned_out_dir();
    let committed_manifest = committed_cpi_unsigned_manifest_bytes();
    let output_manifest =
        stable_read_harness_file(&out.join("manifest.json"), "CPI unsigned output manifest");
    assert_eq!(
        output_manifest, committed_manifest,
        "CPI unsigned output manifest must be exact committed bytes"
    );
    let manifest =
        decode_cpi_unsigned_manifest(&committed_manifest).unwrap_or_else(|error| panic!("{error}"));
    let selected = match suffix {
        "s" => &manifest.expected_assembly,
        "so" => &manifest.expected_elf,
        _ => panic!("unknown CPI unsigned artifact suffix {suffix}"),
    };
    assert_eq!(selected.size, expected.size, "{label} selected size pin");
    assert_eq!(
        selected.sha256, expected.sha256,
        "{label} selected hash pin"
    );

    let path = out.join(format!("{CPI_UNSIGNED_STEM}.{suffix}"));
    let size_bytes = stable_read_harness_file(
        &out.join(format!("{CPI_UNSIGNED_STEM}.{suffix}.size")),
        &format!("{label} size sidecar"),
    );
    let hash_bytes = stable_read_harness_file(
        &out.join(format!("{CPI_UNSIGNED_STEM}.{suffix}.sha256")),
        &format!("{label} hash sidecar"),
    );
    let sidecar_size: u64 = std::str::from_utf8(&size_bytes)
        .expect("UTF-8 unsigned size sidecar")
        .trim()
        .parse()
        .unwrap_or_else(|error| panic!("parse unsigned size sidecar: {error}"));
    let sidecar_hash = std::str::from_utf8(&hash_bytes)
        .expect("UTF-8 unsigned hash sidecar")
        .trim();
    assert_eq!(sidecar_size, expected.size, "{label} sidecar size");
    assert_eq!(sidecar_hash, expected.sha256, "{label} sidecar hash");

    let bytes = stable_read_harness_file(&path, label);
    assert_eq!(bytes.len() as u64, expected.size, "{label} size");
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        expected.sha256,
        "{label} sha256"
    );
    bytes
}

pub fn read_cpi_unsigned_assembly() -> Vec<u8> {
    let manifest_bytes = committed_cpi_unsigned_manifest_bytes();
    let manifest =
        decode_cpi_unsigned_manifest(&manifest_bytes).unwrap_or_else(|error| panic!("{error}"));
    let bytes =
        read_cpi_unsigned_bound_file("s", &manifest.expected_assembly, "CPI unsigned assembly");
    assert!(
        bytes
            .windows(b"TEST-PREACTIVATION ONLY".len())
            .any(|window| window == b"TEST-PREACTIVATION ONLY"),
        "unsigned assembly boundary banner"
    );
    assert!(
        bytes
            .windows(b"sol_invoke_signed_c".len())
            .any(|window| window == b"sol_invoke_signed_c"),
        "#119 unsigned assembly must call sol_invoke_signed_c"
    );
    assert!(
        !bytes
            .windows(b"0xec01".len())
            .any(|window| window == b"0xec01"),
        "#119 unsigned assembly must not contain 0xec01 stub"
    );
    bytes
}

pub fn read_cpi_unsigned_elf() -> Vec<u8> {
    let manifest_bytes = committed_cpi_unsigned_manifest_bytes();
    let manifest =
        decode_cpi_unsigned_manifest(&manifest_bytes).unwrap_or_else(|error| panic!("{error}"));
    let bytes = read_cpi_unsigned_bound_file("so", &manifest.expected_elf, "CPI unsigned ELF");
    assert!(
        bytes.starts_with(b"\x7fELF"),
        "CPI unsigned output must be ELF"
    );
    // Companion pin must hard-match the frozen #115 harness ELF bytes/size.
    let companion_elf = read_harness_elf("companion");
    let companion_digest = hex::encode(Sha256::digest(&companion_elf));
    assert_eq!(
        companion_digest, CPI_UNSIGNED_COMPANION_ELF_SHA256,
        "harness companion ELF sha must equal frozen #115 pin"
    );
    assert_eq!(
        companion_elf.len() as u64,
        CPI_UNSIGNED_COMPANION_ELF_SIZE,
        "harness companion ELF size must equal frozen #115 pin"
    );
    assert_eq!(
        manifest.companion.elf_sha256, CPI_UNSIGNED_COMPANION_ELF_SHA256,
        "unsigned companion pin must equal frozen #115 sha"
    );
    assert_eq!(
        manifest.companion.elf_size, CPI_UNSIGNED_COMPANION_ELF_SIZE,
        "unsigned companion size pin must equal frozen #115 size"
    );
    bytes
}

pub fn cpi_unsigned_program_id() -> Pubkey {
    Pubkey::new_from_array(CPI_UNSIGNED_PROGRAM_ID_BYTES)
}

/// Dual-program Mollusk: #119 caller ELF + #115 companion ELF.
pub fn make_cpi_unsigned_mollusk() -> (Mollusk, Pubkey, Pubkey) {
    let program_id = cpi_unsigned_program_id();
    let companion_id = harness_companion_id();
    let caller_elf = read_cpi_unsigned_elf();
    let companion_elf = read_harness_elf("companion");
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &caller_elf,
    );
    mollusk.add_program_with_loader_and_elf(
        &companion_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &companion_elf,
    );
    (mollusk, program_id, companion_id)
}

/// Probe instruction data: handlerId u64 LE + trailing non-Principal UInt64 params.
pub fn cpi_unsigned_ix_data(handler_id: u64, params: &[u64]) -> Vec<u8> {
    let mut data = Vec::with_capacity(8 + params.len() * 8);
    data.extend_from_slice(&handler_id.to_le_bytes());
    for p in params {
        data.extend_from_slice(&p.to_le_bytes());
    }
    data
}
