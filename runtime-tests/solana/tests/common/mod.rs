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
pub fn assert_discriminators_match_plan_widths(
    plan_bytes: &[u8],
    expected: &[(&str, Vec<usize>)],
) {
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
    PathBuf::from(env::var("PROOF_FORGE_COUNTER_OUT").expect(
        "PROOF_FORGE_COUNTER_OUT must point at the published Counter output tree",
    ))
}

pub fn counter_plan_bytes() -> Vec<u8> {
    let output = counter_output_dir();
    read_manifest_leaf_bytes(
        &output,
        "Counter",
        "Counter.sbpf-plan",
        MATERIALIZED_BASE,
    )
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
    let expected_keys: Vec<Pubkey> = accounts.iter().map(|(k, _)| *k).collect();
    let pre_obs: Vec<(Pubkey, Option<Account>)> = accounts
        .iter()
        .map(|(k, a)| (*k, Some(a.clone())))
        .collect();
    let pre = snapshot_exact_accounts(&expected_keys, &pre_obs)
        .unwrap_or_else(|e| panic!("pre exact snapshot: {e}"));

    let result = mollusk.process_and_validate_instruction(
        ix,
        accounts,
        &[Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN))],
    );

    let post_obs: Vec<(Pubkey, Option<Account>)> = result
        .resulting_accounts
        .iter()
        .map(|(key, account)| (*key, Some(account.clone())))
        .collect();
    let post = snapshot_exact_accounts(&expected_keys, &post_obs)
        .unwrap_or_else(|e| panic!("post exact snapshot: {e}"));
    assert_eq!(
        pre, post,
        "Custom({CHECK_OR_UNKNOWN}) failure must preserve full account snapshot \
         (lamports/data/owner/executable/rent_epoch for every key)"
    );
}
