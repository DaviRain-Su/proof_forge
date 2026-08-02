//! Shared ABI helpers for Solana Mollusk runtime differentials.
//!
//! Discriminator / layout formulas mirror `LowerSemanticV1` and must be
//! computed independently of the product plan (plan is only cross-checked).

use {
    mollusk_svm::Mollusk,
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_native_token::LAMPORTS_PER_SOL,
    solana_pubkey::Pubkey,
    std::{
        collections::BTreeMap,
        env, fs,
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

/// Cross-check independent Rust discriminators against the product plan.
/// All params assumed u64 (historical fixtures).
pub fn assert_discriminators_match_plan(plan_path: &Path, expected: &[(&str, usize)]) {
    let expected_w: Vec<(&str, Vec<usize>)> = expected
        .iter()
        .map(|(name, arity)| (*name, vec![8usize; *arity]))
        .collect();
    assert_discriminators_match_plan_widths(plan_path, &expected_w);
}

/// Cross-check discriminators with explicit per-handler param widths (T8b).
pub fn assert_discriminators_match_plan_widths(
    plan_path: &Path,
    expected: &[(&str, Vec<usize>)],
) {
    let plan = fs::read_to_string(plan_path)
        .unwrap_or_else(|e| panic!("read plan {}: {e}", plan_path.display()));
    let from_plan = parse_plan_handlers(&plan);
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

/// Counter product env (S3a): `PROOF_FORGE_SO_DIR` + `PROOF_FORGE_PLAN`.
pub fn counter_so_dir() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_SO_DIR")
            .expect("PROOF_FORGE_SO_DIR must point at the directory containing Counter.so"),
    )
}

pub fn counter_plan_path() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_PLAN").expect("PROOF_FORGE_PLAN must point at Counter.sbpf-plan"),
    )
}

/// Fixture product env (S3b): `PROOF_FORGE_FIXTURES_DIR/<Name>/`.
pub fn fixtures_dir() -> PathBuf {
    PathBuf::from(env::var("PROOF_FORGE_FIXTURES_DIR").expect(
        "PROOF_FORGE_FIXTURES_DIR must point at the directory containing per-program fixture builds",
    ))
}

pub fn fixture_so_dir(program: &str) -> PathBuf {
    let dir = fixtures_dir().join(program);
    assert!(
        dir.join(format!("{program}.so")).is_file(),
        "{program}.so missing under {}",
        dir.display()
    );
    dir
}

pub fn fixture_plan_path(program: &str) -> PathBuf {
    let path = fixtures_dir().join(program).join(format!("{program}.sbpf-plan"));
    assert!(path.is_file(), "plan missing: {}", path.display());
    path
}

pub fn make_mollusk(program_id: &Pubkey, so_dir: &Path, program_stem: &str) -> Mollusk {
    let so = so_dir.join(format!("{program_stem}.so"));
    assert!(so.is_file(), "{program_stem}.so missing under {}", so_dir.display());
    // Absolute program_name so load_program_elf finds `{name}.so` via Path::join.
    let program_name = so_dir.join(program_stem);
    Mollusk::new(
        program_id,
        program_name.to_str().expect("utf-8 so path"),
    )
}

pub fn make_counter_mollusk(program_id: &Pubkey) -> Mollusk {
    make_mollusk(program_id, &counter_so_dir(), "Counter")
}

pub fn make_fixture_mollusk(program_id: &Pubkey, program: &str) -> Mollusk {
    make_mollusk(program_id, &fixture_so_dir(program), program)
}
