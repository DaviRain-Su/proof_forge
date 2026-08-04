//! #123 production-code-generated classic ATA CreateIdempotent runtime closure.
//!
//! Caller ELF via SolanaCpiAtaExportV1 + locked sbpf 0.2.2.
//! Vendored ATA program@v8.0.0 (`ata_classic_v1.so`) + classic Token
//! program@v9.0.0 + native System. Catalog ATA/Token `artifactBinding`
//! remains `absent`; boundary is testPreactivation + activationDenied.
//!
//! Outer roles (dense): state, payer, ata, wallet, mint, ata-program,
//! system, token. CPI metas (6): payer(w+s), ata(w), wallet(ro), mint(ro),
//! system(ro), token(ro). Instruction data is handler-id only (8 bytes).
//!
//! Requires `PROOF_FORGE_CPI_ATA_OUT` from `scripts/solana_cpi_ata_build.sh`.

#[allow(dead_code)]
mod common;

use {
    common::*,
    curve25519_dalek::edwards::CompressedEdwardsY,
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
    serde_json::{json, Map, Value},
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    solana_svm_log_collector::LogCollector,
    std::{
        collections::BTreeSet,
        env, fs,
        path::{Path, PathBuf},
        rc::Rc,
    },
};

// ---------------------------------------------------------------------------
// Frozen #123 identities
// ---------------------------------------------------------------------------

const CPI_ATA_PROGRAM_ID_BYTES: [u8; 32] = [0x58; 32];
const ATA_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x8c, 0x97, 0x25, 0x8f, 0x4e, 0x24, 0x89, 0xf1, 0xbb, 0x3d, 0x10, 0x29, 0x14, 0x8e, 0x0d, 0x83,
    0x0b, 0x5a, 0x13, 0x99, 0xda, 0xff, 0x10, 0x84, 0x04, 0x8e, 0x7b, 0xd8, 0xdb, 0xe9, 0xf8, 0x59,
];
const TOKEN_CLASSIC_PROGRAM_ID_BYTES: [u8; 32] = [
    0x06, 0xdd, 0xf6, 0xe1, 0xd7, 0x65, 0xa1, 0x93, 0xd9, 0xcb, 0xe1, 0x46, 0xce, 0xeb, 0x79, 0xac,
    0x1c, 0xb4, 0x85, 0xed, 0x5f, 0x5b, 0x37, 0x91, 0x3a, 0x8c, 0xf5, 0x85, 0x7e, 0xff, 0x00, 0xa9,
];
const TOKEN_2022_PROGRAM_ID_BYTES: [u8; 32] = [
    0x06, 0xdd, 0xf6, 0xe1, 0xee, 0x75, 0x8f, 0xde, 0x18, 0x42, 0x5d, 0xbc, 0xe4, 0x6c, 0xcd, 0xda,
    0xb6, 0x1a, 0xfc, 0x4d, 0x83, 0xb9, 0x0d, 0x27, 0xfe, 0xbd, 0xf9, 0x28, 0xd8, 0xa1, 0x8b, 0xfc,
];
const LOADER_V3_OWNER_BYTES: [u8; 32] = [
    0x02, 0xa8, 0xf6, 0x91, 0x4e, 0x88, 0xa1, 0xb0, 0xe2, 0x10, 0x15, 0x3e, 0xf7, 0x63, 0xae, 0x2b,
    0x00, 0xc2, 0xb9, 0x3d, 0x16, 0xc1, 0x24, 0xd2, 0xc0, 0x53, 0x7a, 0x10, 0x04, 0x80, 0x00, 0x00,
];

const CPI_ATA_FIXTURE_SHA256: &str =
    "7262c3400dba450217fb910aee2e3be57e674ef68c5f00c1b1f54c3dbdab454d";
const CPI_ATA_FIXTURE_SIZE: u64 = 1447;
const CPI_ATA_ASSEMBLY_SHA256: &str =
    "80ea42196a9a37a13012d4bcc720b50d97d6167e42dde88da501ef928d6364b9";
const CPI_ATA_ASSEMBLY_SIZE: u64 = 108322;
const CPI_ATA_ELF_SHA256: &str = "9902eb1e8a251b3352a08b4469e32003d7f82b980bc0f33b8557f0cf37d13e37";
const CPI_ATA_ELF_SIZE: u64 = 46872;
const ATA_CLASSIC_ELF_SHA256: &str =
    "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519";
const ATA_CLASSIC_ELF_SIZE: u64 = 111136;
const TOKEN_CLASSIC_ELF_SHA256: &str =
    "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9";
const TOKEN_CLASSIC_ELF_SIZE: u64 = 94960;
const CATALOG_DIGEST: &str = "41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351";
const ATA_TAG_OBJECT: &str = "de77f367fdc0341879b1b9f0224c6b86107e1769";
const ATA_PEELED_COMMIT: &str = "0b867b5340cd001e5980d8ca7928effc4e10015c";
const ATA_RECIPE_MANIFEST_DIGEST: &str =
    "f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2";
const TOKEN_TAG_OBJECT: &str = "5c37ac99c248567bd7d50b965af8cbd45b6ced96";
const TOKEN_PEELED_COMMIT: &str = "dfb260231c761be7d9c8b63728e770a102b86495";
const SYSTEM_AGAVE_COMMIT: &str = "2a165e7a90af75c76426d1e031ed0284211d5d1e";
const PROFILE_DIGEST: &str = "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1";
const EXTENSION_DIGEST: &str = "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020";
const ATA_REPO: &str = "https://github.com/solana-program/associated-token-account";

const GOLDEN_WALLET_HEX: &str = "3131313131313131313131313131313131313131313131313131313131313131";
const GOLDEN_MINT_HEX: &str = "4141414141414141414141414141414141414141414141414141414141414141";
const GOLDEN_ATA_ADDRESS_HEX: &str =
    "3af639c2730fe3226143abb59a0e253e3a93991c9b44eb86304943ef75e8668d";
const GOLDEN_ATA_ADDRESS_BASE58: &str = "4yAQm6WURBF5ipetVEtw8sjHF9yHEKfLPyySQ8cARWPE";
const GOLDEN_ATA_BUMP: u8 = 254;

const CPI_ATA_INIT_HANDLER_ID: u64 = 0;
const CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID: u64 = 1;
const CPI_ATA_CREATE_IDEMPOTENT_THEN_OVERFLOW_HANDLER_ID: u64 = 2;
const CPI_ATA_INSPECT_HANDLER_ID: u64 = 3;

const CPI_ATA_CREATE_IX_LEN: usize = 8;
const ATA_CREATE_IDEMPOTENT_TAG: u8 = 1;
const ATA_CREATE_IDEMPOTENT_DATA_BYTES: usize = 1;
const ATA_CPI_META_COUNT: usize = 6;
const ATA_OUTER_ROLE_COUNT: usize = 8;
const TOKEN_MINT_DATA_BYTES: usize = 82;
const TOKEN_ACCOUNT_DATA_BYTES: usize = 165;
const TOKEN_ACCOUNT_STATE_UNINITIALIZED: u8 = 0;
const TOKEN_ACCOUNT_STATE_INITIALIZED: u8 = 1;
const TOKEN_ACCOUNT_STATE_FROZEN: u8 = 2;
const TOKEN_TRANSFER_CHECKED_TAG: u8 = 12;
const CPI_ATA_STEM: &str = "ata_cpi";

/// Pinned Mollusk/Agave rent-exempt funding for a 165-byte classic Token account.
const ATA_RENT_LAMPORTS: u64 = 2_039_280;
/// System ResultWithNegativeLamports under Mollusk / Agave (same numeric as
/// CHECK_OR_UNKNOWN=1). Underfunded create reaches native System via ATA CPI.
const SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS: u32 = 1;

const EXPECTED_FINAL_ELF_CALLS: &[&str] = &[
    "sol_try_find_program_address",
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_try_find_program_address",
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_set_return_data",
];

const EXPECTED_NON_CLAIMS: &[&str] = &[
    "not mainnet parity",
    "not cross-host reproducible",
    "not hermetic",
    "not formal",
    "not release",
    "not proof-forge.output.v1",
    "not activated sync",
    "not package-owner-published",
    "not package-owned locked release asset",
    "not mollusk-embedded ATA program",
];

/// Closed, source-order evidence index of every runtime acceptance `#[test]`.
const FORCING_MATRIX_CASES: &[&str] = &[
    "generated_assembly_and_elf_are_exact_preactivation",
    "create_idempotent_fresh_success_exact_layout_and_state_order",
    "create_idempotent_replay_is_exactly_idempotent",
    "created_ata_is_usable_by_classic_token_transfer_checked",
    "create_idempotent_then_overflow_full_snapshot_rollback",
    "underfunded_payer_inner_failure_full_snapshot",
    "inspect_reads_initialized_state",
    "one_mutation_ata_key_and_fresh_prestate_negatives",
    "one_mutation_existing_ata_shape_and_join_negatives",
    "one_mutation_mint_account_negatives",
    "one_mutation_payer_and_wallet_negatives",
    "one_mutation_privilege_and_flag_negatives",
    "one_mutation_alias_negatives",
    "one_mutation_role_count_and_order_negatives",
    "ata_program_identity_loader_and_executable_negatives",
    "classic_token_and_token2022_program_negatives",
    "native_system_program_identity_negatives",
    "wrong_wallet_mint_or_token_seed_derivation_fails",
];

fn schema_keys(path: &str) -> Option<&'static [&'static str]> {
    match path {
        "" => Some(&[
            "schema",
            "issue",
            "sbpf",
            "runtimeOracle",
            "fixture",
            "profile",
            "extension",
            "boundary",
            "programIdHex",
            "catalogDigest",
            "ata",
            "tokenDependency",
            "systemDependency",
            "token2022Negative",
            "handlers",
            "pda",
            "generation",
            "expectedAssembly",
            "expectedElf",
            "expectedFinalElfCalls",
            "forcingMatrix",
            "reproducibilityNote",
        ]),
        "/runtimeOracle" => Some(&["molluskSvm", "agaveSyscalls", "solanaProgramRuntime"]),
        "/fixture" => Some(&["path", "module", "sourceSha256", "sourceSize"]),
        "/profile" => Some(&["id", "digest"]),
        "/extension" => Some(&["id", "version", "digest"]),
        "/boundary" => Some(&["productArtifact", "testPreactivation", "activationDenied"]),
        "/ata" => Some(&[
            "package",
            "programIdHex",
            "executionClass",
            "artifactBinding",
            "interface",
            "instructionSurface",
            "vendoredSourceBuiltElf",
        ]),
        "/ata/interface" => Some(&[
            "repo",
            "tag",
            "tagObject",
            "peeledCommit",
            "programVersion",
            "interfaceVersion",
        ]),
        "/ata/instructionSurface" => Some(&[
            "createIdempotentTag",
            "createIdempotentDataBytes",
            "cpiMetaCount",
            "outerRoleCount",
            "mintDataBytes",
            "tokenAccountDataBytes",
        ]),
        "/ata/vendoredSourceBuiltElf" => Some(&[
            "status",
            "path",
            "sha256",
            "size",
            "source",
            "recipe",
            "nonClaims",
            "note",
        ]),
        "/ata/vendoredSourceBuiltElf/source" => Some(&["repo", "tag", "tagObject", "peeledCommit"]),
        "/ata/vendoredSourceBuiltElf/recipe" => Some(&[
            "command",
            "solanaCli",
            "cargoBuildSbf",
            "platformTools",
            "sbfRustc",
            "sourceRustToolchain",
            "host",
            "recipeManifestDigest",
            "sameHostRepeat",
        ]),
        "/tokenDependency" => Some(&[
            "package",
            "programIdHex",
            "path",
            "sha256",
            "size",
            "tag",
            "tagObject",
            "peeledCommit",
            "artifactBinding",
        ]),
        "/systemDependency" => Some(&[
            "package",
            "programIdHex",
            "executionClass",
            "agaveCommit",
            "artifactBinding",
        ]),
        "/token2022Negative" => Some(&["programIdBase58", "programIdHex", "note"]),
        "/handlers" => Some(&[
            "init",
            "createIdempotent",
            "createIdempotentThenOverflow",
            "inspect",
        ]),
        "/pda" => Some(&[
            "recipe",
            "seeds",
            "derivationProgram",
            "canonicalBumpSearch",
            "bumpInInstructionData",
            "signerEligibleForCaller",
            "golden",
        ]),
        "/pda/golden" => Some(&[
            "walletHex",
            "mintHex",
            "addressHex",
            "addressBase58",
            "bump",
        ]),
        "/generation" => Some(&["status", "blockers", "note"]),
        "/expectedAssembly" => Some(&["sha256", "size"]),
        "/expectedElf" => Some(&["sha256", "size"]),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Manifest validation
// ---------------------------------------------------------------------------

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root")
}

fn committed_cpi_ata_manifest_bytes() -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("ata/manifest.json");
    fs::read(&path).unwrap_or_else(|e| panic!("read committed ata manifest: {e}"))
}

fn exact_keys_at(obj: &Map<String, Value>, path: &str, expected: &[&str]) -> Result<(), String> {
    let got: BTreeSet<&str> = obj.keys().map(String::as_str).collect();
    let want: BTreeSet<&str> = expected.iter().copied().collect();
    if got != want {
        return Err(format!(
            "exact keys mismatch at {path:?}: got {:?}, want {:?}",
            got.iter().copied().collect::<Vec<_>>(),
            want.iter().copied().collect::<Vec<_>>()
        ));
    }
    Ok(())
}

fn validate_recursive_exact_keys(value: &Value, path: &str) -> Result<(), String> {
    match value {
        Value::Object(map) => {
            if let Some(expected) = schema_keys(path) {
                exact_keys_at(map, path, expected)?;
            } else if !map.is_empty() {
                return Err(format!(
                    "unexpected nested object at {path:?} keys={:?}",
                    map.keys().collect::<Vec<_>>()
                ));
            }
            for (k, v) in map {
                let child = if path.is_empty() {
                    format!("/{k}")
                } else {
                    format!("{path}/{k}")
                };
                validate_recursive_exact_keys(v, &child)?;
            }
            Ok(())
        }
        Value::Array(items) => {
            for (i, item) in items.iter().enumerate() {
                if item.is_object() {
                    return Err(format!("unexpected object element in array at {path}[{i}]"));
                }
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

fn expect_eq(value: &Value, pointer: &str, expected: Value) -> Result<(), String> {
    let got = value
        .pointer(pointer)
        .ok_or_else(|| format!("missing {pointer}"))?;
    if got != &expected {
        return Err(format!("{pointer}: got {got}, want {expected}"));
    }
    Ok(())
}

fn lower_hex64(s: &str, label: &str) -> Result<(), String> {
    if s.len() != 64 || s.bytes().any(|b| !matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return Err(format!("{label} must be 64 lowercase hex digits"));
    }
    Ok(())
}

fn validate_cpi_ata_manifest_bytes(bytes: &[u8]) -> Result<(), String> {
    let value: Value = serde_json::from_slice(bytes).map_err(|e| format!("decode: {e}"))?;
    validate_recursive_exact_keys(&value, "")?;

    expect_eq(
        &value,
        "/schema",
        json!("proof-forge.solana.cpi-ata-runtime.v1"),
    )?;
    expect_eq(&value, "/issue", json!(123))?;
    expect_eq(&value, "/sbpf", json!("0.2.2"))?;
    expect_eq(&value, "/runtimeOracle/molluskSvm", json!("0.13.4"))?;
    expect_eq(&value, "/runtimeOracle/agaveSyscalls", json!("4.0.0"))?;
    expect_eq(
        &value,
        "/runtimeOracle/solanaProgramRuntime",
        json!("4.0.0"),
    )?;
    expect_eq(
        &value,
        "/fixture/path",
        json!("runtime-tests/solana/fixtures/AtaCpi.lean"),
    )?;
    expect_eq(&value, "/fixture/module", json!("Examples.AtaCpi"))?;
    expect_eq(
        &value,
        "/fixture/sourceSha256",
        json!(CPI_ATA_FIXTURE_SHA256),
    )?;
    expect_eq(&value, "/fixture/sourceSize", json!(CPI_ATA_FIXTURE_SIZE))?;
    expect_eq(&value, "/profile/id", json!("solana-sbpf-cpi-elf-v1"))?;
    expect_eq(&value, "/profile/digest", json!(PROFILE_DIGEST))?;
    expect_eq(&value, "/extension/id", json!("solana.cpi.accounts"))?;
    expect_eq(&value, "/extension/version", json!("1.0.0"))?;
    expect_eq(&value, "/extension/digest", json!(EXTENSION_DIGEST))?;
    expect_eq(&value, "/boundary/productArtifact", json!(false))?;
    expect_eq(&value, "/boundary/testPreactivation", json!(true))?;
    expect_eq(&value, "/boundary/activationDenied", json!(true))?;
    expect_eq(
        &value,
        "/programIdHex",
        json!(hex::encode(CPI_ATA_PROGRAM_ID_BYTES)),
    )?;
    expect_eq(&value, "/catalogDigest", json!(CATALOG_DIGEST))?;

    expect_eq(&value, "/ata/package", json!("ata-classic-v1"))?;
    expect_eq(
        &value,
        "/ata/programIdHex",
        json!(hex::encode(ATA_CLASSIC_PROGRAM_ID_BYTES)),
    )?;
    expect_eq(&value, "/ata/executionClass", json!("loaderV3Sbpf"))?;
    expect_eq(&value, "/ata/artifactBinding", json!("absent"))?;
    expect_eq(&value, "/ata/interface/repo", json!(ATA_REPO))?;
    expect_eq(&value, "/ata/interface/tag", json!("program@v8.0.0"))?;
    expect_eq(&value, "/ata/interface/tagObject", json!(ATA_TAG_OBJECT))?;
    expect_eq(
        &value,
        "/ata/interface/peeledCommit",
        json!(ATA_PEELED_COMMIT),
    )?;
    expect_eq(&value, "/ata/interface/programVersion", json!("8.0.0"))?;
    expect_eq(&value, "/ata/interface/interfaceVersion", json!("2.0.0"))?;
    expect_eq(
        &value,
        "/ata/instructionSurface/createIdempotentTag",
        json!(ATA_CREATE_IDEMPOTENT_TAG),
    )?;
    expect_eq(
        &value,
        "/ata/instructionSurface/createIdempotentDataBytes",
        json!(ATA_CREATE_IDEMPOTENT_DATA_BYTES),
    )?;
    expect_eq(
        &value,
        "/ata/instructionSurface/cpiMetaCount",
        json!(ATA_CPI_META_COUNT),
    )?;
    expect_eq(
        &value,
        "/ata/instructionSurface/outerRoleCount",
        json!(ATA_OUTER_ROLE_COUNT),
    )?;
    expect_eq(
        &value,
        "/ata/instructionSurface/mintDataBytes",
        json!(TOKEN_MINT_DATA_BYTES),
    )?;
    expect_eq(
        &value,
        "/ata/instructionSurface/tokenAccountDataBytes",
        json!(TOKEN_ACCOUNT_DATA_BYTES),
    )?;
    expect_eq(&value, "/ata/vendoredSourceBuiltElf/status", json!("ready"))?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/path",
        json!("runtime-tests/solana/ata/ata_classic_v1.so"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/sha256",
        json!(ATA_CLASSIC_ELF_SHA256),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/size",
        json!(ATA_CLASSIC_ELF_SIZE),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/source/repo",
        json!(ATA_REPO),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/source/tag",
        json!("program@v8.0.0"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/source/tagObject",
        json!(ATA_TAG_OBJECT),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/source/peeledCommit",
        json!(ATA_PEELED_COMMIT),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/command",
        json!("cargo-build-sbf --manifest-path program/Cargo.toml"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/solanaCli",
        json!("3.0.0"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/cargoBuildSbf",
        json!("3.0.0"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/platformTools",
        json!("v1.51"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/sbfRustc",
        json!("1.84.1-dev"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/sourceRustToolchain",
        json!("1.86.0"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/host",
        json!("Darwin arm64"),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/recipeManifestDigest",
        json!(ATA_RECIPE_MANIFEST_DIGEST),
    )?;
    expect_eq(
        &value,
        "/ata/vendoredSourceBuiltElf/recipe/sameHostRepeat",
        json!(2),
    )?;

    let non_claims = value
        .pointer("/ata/vendoredSourceBuiltElf/nonClaims")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "nonClaims missing".to_string())?;
    let got: Vec<&str> = non_claims.iter().filter_map(|v| v.as_str()).collect();
    if got != EXPECTED_NON_CLAIMS {
        return Err(format!(
            "nonClaims exact ordered mismatch:\n  got  {got:?}\n  want {EXPECTED_NON_CLAIMS:?}"
        ));
    }

    expect_eq(
        &value,
        "/tokenDependency/package",
        json!("token-classic-v1"),
    )?;
    expect_eq(
        &value,
        "/tokenDependency/programIdHex",
        json!(hex::encode(TOKEN_CLASSIC_PROGRAM_ID_BYTES)),
    )?;
    expect_eq(
        &value,
        "/tokenDependency/path",
        json!("runtime-tests/solana/token/token_classic_v1.so"),
    )?;
    expect_eq(
        &value,
        "/tokenDependency/sha256",
        json!(TOKEN_CLASSIC_ELF_SHA256),
    )?;
    expect_eq(
        &value,
        "/tokenDependency/size",
        json!(TOKEN_CLASSIC_ELF_SIZE),
    )?;
    expect_eq(&value, "/tokenDependency/tag", json!("program@v9.0.0"))?;
    expect_eq(
        &value,
        "/tokenDependency/tagObject",
        json!(TOKEN_TAG_OBJECT),
    )?;
    expect_eq(
        &value,
        "/tokenDependency/peeledCommit",
        json!(TOKEN_PEELED_COMMIT),
    )?;
    expect_eq(&value, "/tokenDependency/artifactBinding", json!("absent"))?;

    expect_eq(&value, "/systemDependency/package", json!("system-v1"))?;
    expect_eq(
        &value,
        "/systemDependency/programIdHex",
        json!("0000000000000000000000000000000000000000000000000000000000000000"),
    )?;
    expect_eq(
        &value,
        "/systemDependency/executionClass",
        json!("nativeSystem"),
    )?;
    expect_eq(
        &value,
        "/systemDependency/agaveCommit",
        json!(SYSTEM_AGAVE_COMMIT),
    )?;
    expect_eq(
        &value,
        "/systemDependency/artifactBinding",
        json!("runtimeNative"),
    )?;

    expect_eq(
        &value,
        "/token2022Negative/programIdBase58",
        json!("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"),
    )?;
    expect_eq(
        &value,
        "/token2022Negative/programIdHex",
        json!(hex::encode(TOKEN_2022_PROGRAM_ID_BYTES)),
    )?;

    expect_eq(&value, "/handlers/init", json!(0))?;
    expect_eq(&value, "/handlers/createIdempotent", json!(1))?;
    expect_eq(&value, "/handlers/createIdempotentThenOverflow", json!(2))?;
    expect_eq(&value, "/handlers/inspect", json!(3))?;

    expect_eq(&value, "/pda/recipe", json!("ata-classic-v1"))?;
    let seeds = value
        .pointer("/pda/seeds")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "pda.seeds missing".to_string())?;
    let seed_strs: Vec<&str> = seeds.iter().filter_map(|v| v.as_str()).collect();
    if seed_strs != ["wallet", "classicTokenProgramId", "mint"] {
        return Err(format!("pda.seeds mismatch: {seed_strs:?}"));
    }
    expect_eq(
        &value,
        "/pda/derivationProgram",
        json!("classicAtaProgramId"),
    )?;
    expect_eq(&value, "/pda/canonicalBumpSearch", json!("255..1"))?;
    expect_eq(&value, "/pda/bumpInInstructionData", json!(false))?;
    expect_eq(&value, "/pda/signerEligibleForCaller", json!(false))?;
    expect_eq(&value, "/pda/golden/walletHex", json!(GOLDEN_WALLET_HEX))?;
    expect_eq(&value, "/pda/golden/mintHex", json!(GOLDEN_MINT_HEX))?;
    expect_eq(
        &value,
        "/pda/golden/addressHex",
        json!(GOLDEN_ATA_ADDRESS_HEX),
    )?;
    expect_eq(
        &value,
        "/pda/golden/addressBase58",
        json!(GOLDEN_ATA_ADDRESS_BASE58),
    )?;
    expect_eq(&value, "/pda/golden/bump", json!(GOLDEN_ATA_BUMP))?;

    expect_eq(&value, "/generation/status", json!("ready"))?;
    let blockers = value
        .pointer("/generation/blockers")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "generation.blockers missing".to_string())?;
    if !blockers.is_empty() {
        return Err(format!(
            "generation.blockers must be empty, got {blockers:?}"
        ));
    }

    expect_eq(
        &value,
        "/expectedAssembly/sha256",
        json!(CPI_ATA_ASSEMBLY_SHA256),
    )?;
    expect_eq(
        &value,
        "/expectedAssembly/size",
        json!(CPI_ATA_ASSEMBLY_SIZE),
    )?;
    expect_eq(&value, "/expectedElf/sha256", json!(CPI_ATA_ELF_SHA256))?;
    expect_eq(&value, "/expectedElf/size", json!(CPI_ATA_ELF_SIZE))?;

    let calls = value
        .pointer("/expectedFinalElfCalls")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "expectedFinalElfCalls missing".to_string())?;
    let got_calls: Vec<&str> = calls.iter().filter_map(|v| v.as_str()).collect();
    if got_calls != EXPECTED_FINAL_ELF_CALLS {
        return Err(format!(
            "expectedFinalElfCalls mismatch:\n  got  {got_calls:?}\n  want {EXPECTED_FINAL_ELF_CALLS:?}"
        ));
    }
    let matrix = value
        .pointer("/forcingMatrix")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "forcingMatrix missing".to_string())?;
    let cases: Vec<&str> = matrix.iter().filter_map(|v| v.as_str()).collect();
    if cases != FORCING_MATRIX_CASES {
        return Err(format!("forcingMatrix mismatch: got {cases:?}"));
    }

    for pointer in [
        "/fixture/sourceSha256",
        "/profile/digest",
        "/extension/digest",
        "/catalogDigest",
        "/ata/vendoredSourceBuiltElf/sha256",
        "/tokenDependency/sha256",
        "/expectedAssembly/sha256",
        "/expectedElf/sha256",
        "/ata/vendoredSourceBuiltElf/recipe/recipeManifestDigest",
        "/pda/golden/walletHex",
        "/pda/golden/mintHex",
        "/pda/golden/addressHex",
    ] {
        let s = value
            .pointer(pointer)
            .and_then(|v| v.as_str())
            .ok_or_else(|| format!("{pointer} not string"))?;
        lower_hex64(s, pointer)?;
    }
    for pointer in [
        "/ata/interface/tagObject",
        "/ata/interface/peeledCommit",
        "/ata/vendoredSourceBuiltElf/source/tagObject",
        "/ata/vendoredSourceBuiltElf/source/peeledCommit",
        "/tokenDependency/tagObject",
        "/tokenDependency/peeledCommit",
        "/systemDependency/agaveCommit",
    ] {
        let s = value
            .pointer(pointer)
            .and_then(|v| v.as_str())
            .ok_or_else(|| format!("{pointer} not string"))?;
        if s.len() != 40 || s.bytes().any(|b| !matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
            return Err(format!(
                "{pointer} must be 40 lowercase hex digits (git object)"
            ));
        }
    }

    let repro = value
        .pointer("/reproducibilityNote")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    for req in [
        "not proof-forge.output.v1",
        "not activated sync",
        "not mainnet parity",
        "ATA v8",
        "Token v9",
        "artifactBinding remains absent",
    ] {
        if !repro.contains(req) {
            return Err(format!("reproducibilityNote missing {req}"));
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Artifact binding + Mollusk
// ---------------------------------------------------------------------------

fn cpi_ata_out_dir() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_CPI_ATA_OUT")
            .expect("PROOF_FORGE_CPI_ATA_OUT must point at scripts/solana_cpi_ata_build.sh output"),
    )
}

fn stable_read(path: &Path, label: &str) -> Vec<u8> {
    fs::read(path).unwrap_or_else(|e| panic!("{label}: {}: {e}", path.display()))
}

fn read_bound_artifact(
    suffix: &str,
    expected_sha: &str,
    expected_size: u64,
    label: &str,
) -> Vec<u8> {
    let out = cpi_ata_out_dir();
    let committed = committed_cpi_ata_manifest_bytes();
    let staged = stable_read(&out.join("manifest.json"), "output manifest");
    assert_eq!(
        staged, committed,
        "output manifest must equal committed bytes"
    );
    validate_cpi_ata_manifest_bytes(&committed).expect("committed manifest");
    let path = out.join(format!("{CPI_ATA_STEM}.{suffix}"));
    let size_bytes = stable_read(
        &out.join(format!("{CPI_ATA_STEM}.{suffix}.size")),
        "size sidecar",
    );
    let hash_bytes = stable_read(
        &out.join(format!("{CPI_ATA_STEM}.{suffix}.sha256")),
        "hash sidecar",
    );
    let sidecar_size: u64 = std::str::from_utf8(&size_bytes)
        .unwrap()
        .trim()
        .parse()
        .unwrap();
    let sidecar_hash = std::str::from_utf8(&hash_bytes).unwrap().trim();
    assert_eq!(sidecar_size, expected_size, "{label} sidecar size");
    assert_eq!(sidecar_hash, expected_sha, "{label} sidecar hash");
    let bytes = stable_read(&path, label);
    assert_eq!(bytes.len() as u64, expected_size, "{label} size");
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        expected_sha,
        "{label} sha"
    );
    bytes
}

fn read_cpi_ata_assembly() -> Vec<u8> {
    let bytes = read_bound_artifact(
        "s",
        CPI_ATA_ASSEMBLY_SHA256,
        CPI_ATA_ASSEMBLY_SIZE,
        "assembly",
    );
    assert!(bytes
        .windows(b"TEST-PREACTIVATION ONLY".len())
        .any(|w| w == b"TEST-PREACTIVATION ONLY"));
    for req in [
        b"sol_invoke_signed_c" as &[u8],
        b"sol_try_find_program_address",
        b"sol_set_return_data",
        b"ataAccountPrestateClosed",
    ] {
        assert!(
            bytes.windows(req.len()).any(|w| w == req),
            "assembly missing {}",
            String::from_utf8_lossy(req)
        );
    }
    bytes
}

fn read_cpi_ata_caller_elf() -> Vec<u8> {
    let bytes = read_bound_artifact("so", CPI_ATA_ELF_SHA256, CPI_ATA_ELF_SIZE, "caller ELF");
    assert!(bytes.starts_with(b"\x7fELF"));
    bytes
}

fn read_vendored_ata_elf() -> Vec<u8> {
    let out = cpi_ata_out_dir();
    let staged = stable_read(&out.join("ata_classic_v1.so"), "staged ATA ELF");
    let committed = stable_read(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("ata/ata_classic_v1.so"),
        "committed ATA ELF",
    );
    assert_eq!(staged, committed);
    assert_eq!(staged.len() as u64, ATA_CLASSIC_ELF_SIZE);
    assert_eq!(hex::encode(Sha256::digest(&staged)), ATA_CLASSIC_ELF_SHA256);
    assert!(staged.starts_with(b"\x7fELF"));
    staged
}

fn read_vendored_token_elf() -> Vec<u8> {
    let out = cpi_ata_out_dir();
    let staged = stable_read(&out.join("token_classic_v1.so"), "staged Token ELF");
    let committed = stable_read(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("token/token_classic_v1.so"),
        "committed Token ELF",
    );
    assert_eq!(staged, committed);
    assert_eq!(staged.len() as u64, TOKEN_CLASSIC_ELF_SIZE);
    assert_eq!(
        hex::encode(Sha256::digest(&staged)),
        TOKEN_CLASSIC_ELF_SHA256
    );
    assert!(staged.starts_with(b"\x7fELF"));
    staged
}

fn cpi_ata_program_id() -> Pubkey {
    Pubkey::new_from_array(CPI_ATA_PROGRAM_ID_BYTES)
}
fn ata_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(ATA_CLASSIC_PROGRAM_ID_BYTES)
}
fn token_classic_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_CLASSIC_PROGRAM_ID_BYTES)
}
fn token_2022_program_id() -> Pubkey {
    Pubkey::new_from_array(TOKEN_2022_PROGRAM_ID_BYTES)
}
fn loader_v3_owner() -> Pubkey {
    Pubkey::new_from_array(LOADER_V3_OWNER_BYTES)
}

fn make_cpi_ata_mollusk() -> (Mollusk, Pubkey, Pubkey, Pubkey) {
    let program_id = cpi_ata_program_id();
    let ata_id = ata_classic_program_id();
    let token_id = token_classic_program_id();
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_cpi_ata_caller_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &ata_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_ata_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &token_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_token_elf(),
    );
    (mollusk, program_id, ata_id, token_id)
}

// ---------------------------------------------------------------------------
// Packing + PDA helpers
// ---------------------------------------------------------------------------

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn decode_hex32(hex64: &str) -> Pubkey {
    let raw = hex::decode(hex64).expect("hex32");
    assert_eq!(raw.len(), 32);
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&raw);
    Pubkey::new_from_array(arr)
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

fn pack_classic_mint(
    mint_authority: &Pubkey,
    supply: u64,
    decimals: u8,
    is_initialized: u8,
) -> Vec<u8> {
    let mut data = vec![0u8; TOKEN_MINT_DATA_BYTES];
    data[0..36].copy_from_slice(&coption_pubkey_some(mint_authority));
    data[36..44].copy_from_slice(&supply.to_le_bytes());
    data[44] = decimals;
    data[45] = is_initialized;
    data[46..82].copy_from_slice(&coption_pubkey_none());
    data
}

fn pack_classic_token_account(
    mint: &Pubkey,
    owner: &Pubkey,
    amount: u64,
    state: u8,
    delegate: Option<&Pubkey>,
) -> Vec<u8> {
    let mut data = vec![0u8; TOKEN_ACCOUNT_DATA_BYTES];
    data[0..32].copy_from_slice(mint.as_ref());
    data[32..64].copy_from_slice(owner.as_ref());
    data[64..72].copy_from_slice(&amount.to_le_bytes());
    match delegate {
        None => data[72..108].copy_from_slice(&coption_pubkey_none()),
        Some(d) => data[72..108].copy_from_slice(&coption_pubkey_some(d)),
    }
    data[108] = state;
    data
}

fn token_account_amount(data: &[u8]) -> u64 {
    assert_eq!(data.len(), TOKEN_ACCOUNT_DATA_BYTES);
    u64::from_le_bytes(data[64..72].try_into().unwrap())
}

fn ata_cpi_fields() -> [StateField; 1] {
    single_field("value")
}

fn ata_cpi_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&ata_cpi_fields(), initialized, &[value])
}

fn cpi_ata_simple_ix_data(handler_id: u64) -> Vec<u8> {
    handler_id.to_le_bytes().to_vec()
}

fn cpi_ata_init_ix_data(handler_id: u64, initial: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(16);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&initial.to_le_bytes());
    data
}

const PDA_MARKER: &[u8] = b"ProgramDerivedAddress";

/// SDK-independent Solana PDA candidate oracle: direct SHA-256 followed by
/// Ed25519 compressed-point rejection. This intentionally does not call any
/// `Pubkey::{create,find}_program_address` API.
fn independent_create_program_address(seeds: &[&[u8]], program_id: &Pubkey) -> Option<Pubkey> {
    assert!(seeds.len() <= 16, "Solana PDA seed-count bound");
    assert!(
        seeds.iter().all(|seed| seed.len() <= 32),
        "Solana PDA seed-length bound"
    );
    let mut hasher = Sha256::new();
    for seed in seeds {
        hasher.update(seed);
    }
    hasher.update(program_id.as_ref());
    hasher.update(PDA_MARKER);
    let hash: [u8; 32] = hasher.finalize().into();
    if CompressedEdwardsY(hash).decompress().is_some() {
        None
    } else {
        Some(Pubkey::new_from_array(hash))
    }
}

/// Independent ATA PDA search (255..1): seeds = [wallet, classic Token, mint]
/// under the classic ATA program. Bump 0 is never searched.
fn find_ata_classic_v1(wallet: &Pubkey, mint: &Pubkey) -> (Pubkey, u8) {
    let token = token_classic_program_id();
    let ata_program = ata_classic_program_id();
    for bump in (1u8..=255).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[wallet.as_ref(), token.as_ref(), mint.as_ref(), &bump_slice];
        if let Some(addr) = independent_create_program_address(seeds, &ata_program) {
            return (addr, bump);
        }
    }
    panic!("no canonical ATA bump in 255..1");
}

/// SDK-style find_program_address (includes bump in return; same seeds).
fn find_ata_sdk(wallet: &Pubkey, mint: &Pubkey) -> (Pubkey, u8) {
    let token = token_classic_program_id();
    let ata_program = ata_classic_program_id();
    Pubkey::find_program_address(
        &[wallet.as_ref(), token.as_ref(), mint.as_ref()],
        &ata_program,
    )
}

fn ata_program_account() -> Account {
    create_program_account_loader_v3(&ata_classic_program_id())
}

fn token_program_account() -> Account {
    create_program_account_loader_v3(&token_classic_program_id())
}

fn account_by_key<'a>(accounts: &'a [(Pubkey, Account)], key: &Pubkey) -> &'a Account {
    accounts
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, a)| a)
        .expect("account key")
}

fn assert_custom_failure_snapshot(
    mollusk: &Mollusk,
    ix: &Instruction,
    accounts: &[(Pubkey, Account)],
    code: u32,
) {
    assert_failure_preserves_exact_accounts(
        mollusk,
        ix,
        accounts,
        Check::err(ProgramError::Custom(code)),
    );
}

// ---------------------------------------------------------------------------
// CreateIdempotent case: outer roles state,payer,ata,wallet,mint,ata,system,token
// ---------------------------------------------------------------------------

#[derive(Clone)]
struct CreateIdempotentCase {
    state_key: Pubkey,
    payer_key: Pubkey,
    ata_key: Pubkey,
    wallet_key: Pubkey,
    mint_key: Pubkey,
    ata_program_key: Pubkey,
    system_program_key: Pubkey,
    token_program_key: Pubkey,
    mint_authority: Pubkey,
    bump: u8,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    payer_lamports: u64,
    decimals: u8,
}

impl CreateIdempotentCase {
    /// Fresh ATA: System-owned, 0 lamports, 0 data (create path).
    fn fresh(program_id: Pubkey, state_value: u64, payer_lamports: u64, decimals: u8) -> Self {
        Self::with_ata_prestate(
            program_id,
            state_value,
            payer_lamports,
            decimals,
            unused_system_create_target_account(),
        )
    }

    /// Existing initialized classic Token ATA matching wallet+mint joins.
    fn existing_initialized(
        program_id: Pubkey,
        state_value: u64,
        payer_lamports: u64,
        decimals: u8,
        amount: u64,
    ) -> Self {
        let wallet = fixed_key(0x31);
        let mint = fixed_key(0x41);
        let (ata_key, _) = find_ata_classic_v1(&wallet, &mint);
        let token_id = token_classic_program_id();
        let ata_account = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint,
                &wallet,
                amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_id,
            executable: false,
            rent_epoch: 0,
        };
        let case = Self::with_ata_prestate(
            program_id,
            state_value,
            payer_lamports,
            decimals,
            ata_account,
        );
        // Keep keys consistent with derivation seeds used above.
        assert_eq!(case.wallet_key, wallet);
        assert_eq!(case.mint_key, mint);
        assert_eq!(case.ata_key, ata_key);
        case
    }

    fn with_ata_prestate(
        program_id: Pubkey,
        state_value: u64,
        payer_lamports: u64,
        decimals: u8,
        ata_account: Account,
    ) -> Self {
        let state_key = fixed_key(0x20);
        let payer_key = fixed_key(0x21);
        let wallet_key = fixed_key(0x31);
        let mint_key = fixed_key(0x41);
        let mint_authority = fixed_key(0x70);
        let (ata_key, bump) = find_ata_classic_v1(&wallet_key, &mint_key);
        let ata_program_key = ata_classic_program_id();
        let token_program_key = token_classic_program_id();
        let (system_program_key, system_program) = system_program_keyed_account();

        let state = state_account(&program_id, ata_cpi_state(true, state_value));
        let payer = Account::new(payer_lamports, 0, &Pubkey::default());
        let wallet = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let mint = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(&mint_authority, 1_000_000, decimals, 1),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let ata_program = ata_program_account();
        let token_program = token_program_account();

        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(payer_key, true),
            AccountMeta::new(ata_key, false),
            AccountMeta::new_readonly(wallet_key, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new_readonly(ata_program_key, false),
            AccountMeta::new_readonly(system_program_key, false),
            AccountMeta::new_readonly(token_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (payer_key, payer),
            (ata_key, ata_account),
            (wallet_key, wallet),
            (mint_key, mint),
            (ata_program_key, ata_program),
            (system_program_key, system_program),
            (token_program_key, token_program),
        ];
        assert_eq!(metas.len(), ATA_OUTER_ROLE_COUNT);
        assert_eq!(accounts.len(), ATA_OUTER_ROLE_COUNT);
        Self {
            state_key,
            payer_key,
            ata_key,
            wallet_key,
            mint_key,
            ata_program_key,
            system_program_key,
            token_program_key,
            mint_authority,
            bump,
            metas,
            accounts,
            payer_lamports,
            decimals,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_ata_simple_ix_data(handler_id),
            self.metas.clone(),
        )
    }
}

// ---------------------------------------------------------------------------
// Pure / committed-manifest tests
// ---------------------------------------------------------------------------

#[test]
fn committed_manifest_schema_is_exact_preactivation_evidence() {
    let manifest = committed_cpi_ata_manifest_bytes();
    validate_cpi_ata_manifest_bytes(&manifest).expect("committed ata manifest");
    let value: Value = serde_json::from_slice(&manifest).unwrap();
    assert_eq!(
        value["schema"],
        json!("proof-forge.solana.cpi-ata-runtime.v1")
    );
    assert_eq!(value["issue"], json!(123));
    assert_eq!(value["boundary"]["productArtifact"], json!(false));
    assert_eq!(value["boundary"]["testPreactivation"], json!(true));
    assert_eq!(value["boundary"]["activationDenied"], json!(true));
    assert_eq!(value["ata"]["package"], json!("ata-classic-v1"));
    assert_eq!(value["ata"]["artifactBinding"], json!("absent"));
    assert_eq!(value["tokenDependency"]["artifactBinding"], json!("absent"));
    assert_eq!(
        value["systemDependency"]["artifactBinding"],
        json!("runtimeNative")
    );
}

#[test]
fn ata_manifest_closed_identity_mutations_fail() {
    let raw = committed_cpi_ata_manifest_bytes();
    validate_cpi_ata_manifest_bytes(&raw).expect("committed");
    let base: Value = serde_json::from_slice(&raw).unwrap();
    let mutations = [
        ("/schema", json!("wrong")),
        ("/issue", json!(122)),
        ("/sbpf", json!("0.2.3")),
        ("/boundary/productArtifact", json!(true)),
        ("/boundary/activationDenied", json!(false)),
        ("/programIdHex", json!("00".repeat(32))),
        ("/ata/package", json!("wrong")),
        ("/ata/artifactBinding", json!("generated-elf")),
        ("/ata/instructionSurface/createIdempotentTag", json!(0)),
        ("/handlers/createIdempotent", json!(9)),
        ("/pda/recipe", json!("wrong")),
        ("/pda/golden/bump", json!(0)),
        ("/expectedAssembly/sha256", json!("00".repeat(32))),
        ("/expectedElf/size", json!(0)),
        ("/tokenDependency/artifactBinding", json!("generated-elf")),
        ("/systemDependency/executionClass", json!("loaderV3Sbpf")),
    ];
    for (pointer, replacement) in mutations {
        let mut mutated = base.clone();
        *mutated
            .pointer_mut(pointer)
            .unwrap_or_else(|| panic!("missing mutation path {pointer}")) = replacement;
        let encoded = serde_json::to_vec(&mutated).unwrap();
        let result = validate_cpi_ata_manifest_bytes(&encoded);
        assert!(
            result.is_err(),
            "manifest mutation unexpectedly accepted: {pointer} ({result:?})"
        );
    }
}

#[test]
fn create_ix_layout_is_exactly_handler_id_8_bytes() {
    let data = cpi_ata_simple_ix_data(CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID);
    assert_eq!(data.len(), CPI_ATA_CREATE_IX_LEN);
    assert_eq!(
        &data[0..8],
        &CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID.to_le_bytes()
    );
}

#[test]
fn pda_oracle_sdk_and_hardcoded_golden_agree() {
    let wallet = decode_hex32(GOLDEN_WALLET_HEX);
    let mint = decode_hex32(GOLDEN_MINT_HEX);
    assert_eq!(wallet, fixed_key(0x31));
    assert_eq!(mint, fixed_key(0x41));

    let (oracle_addr, oracle_bump) = find_ata_classic_v1(&wallet, &mint);
    let (sdk_addr, sdk_bump) = find_ata_sdk(&wallet, &mint);
    let golden_addr = decode_hex32(GOLDEN_ATA_ADDRESS_HEX);

    assert_eq!(
        oracle_addr, sdk_addr,
        "independent oracle vs find_program_address"
    );
    assert_eq!(oracle_bump, sdk_bump);
    assert_eq!(
        oracle_addr, golden_addr,
        "oracle vs hardcoded golden vector"
    );
    assert_eq!(oracle_bump, GOLDEN_ATA_BUMP);
    assert_eq!(oracle_addr.to_string(), GOLDEN_ATA_ADDRESS_BASE58);
    assert_ne!(oracle_bump, 0, "bump 0 is rejected by recipe");
}

#[test]
fn forcing_matrix_names_are_closed_and_ordered() {
    let value: Value =
        serde_json::from_slice(&committed_cpi_ata_manifest_bytes()).expect("manifest");
    let matrix = value["forcingMatrix"].as_array().unwrap();
    let cases: Vec<&str> = matrix.iter().filter_map(|v| v.as_str()).collect();
    assert_eq!(cases, FORCING_MATRIX_CASES);
    for required in FORCING_MATRIX_CASES {
        assert_eq!(
            cases.iter().filter(|c| *c == required).count(),
            1,
            "forcingMatrix must contain exactly one {required}"
        );
    }
}

#[test]
fn build_script_is_strict_pin_gate() {
    let text = fs::read_to_string(repo_root().join("scripts/solana_cpi_ata_build.sh")).unwrap();
    assert!(text.contains("vendoredSourceBuiltElf") || text.contains("ATA_SHA"));
    assert!(text.contains(ATA_CLASSIC_ELF_SHA256));
    assert!(text.contains("111136"));
    assert!(text.contains("program@v8.0.0"));
    assert!(text.contains(ATA_PEELED_COMMIT));
    assert!(text.contains(TOKEN_CLASSIC_ELF_SHA256));
}

// ---------------------------------------------------------------------------
// Artifact + success paths
// ---------------------------------------------------------------------------

#[test]
fn generated_assembly_and_elf_are_exact_preactivation() {
    let _ = read_cpi_ata_assembly();
    assert!(read_cpi_ata_caller_elf().starts_with(b"\x7fELF"));
    let ata = read_vendored_ata_elf();
    assert_eq!(ata.len() as u64, ATA_CLASSIC_ELF_SIZE);
    let token = read_vendored_token_elf();
    assert_eq!(token.len() as u64, TOKEN_CLASSIC_ELF_SIZE);
    let calls: Vec<String> = serde_json::from_slice(&stable_read(
        &cpi_ata_out_dir().join("ata_cpi.calls.json"),
        "calls",
    ))
    .unwrap();
    assert_eq!(
        calls.iter().map(String::as_str).collect::<Vec<_>>(),
        EXPECTED_FINAL_ELF_CALLS
    );
}

#[test]
fn create_idempotent_fresh_success_exact_layout_and_state_order() {
    let (mollusk, program_id, _, token_id) = make_cpi_ata_mollusk();
    let case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
    assert_eq!(case.bump, GOLDEN_ATA_BUMP);
    assert_eq!(case.ata_key, decode_hex32(GOLDEN_ATA_ADDRESS_HEX));

    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );

    let post_state = account_by_key(&result.resulting_accounts, &case.state_key);
    assert_eq!(
        post_state.data,
        ata_cpi_state(true, 13),
        "caller state must commit pre-CPI (+1) and post-CPI (+2)"
    );

    let post_ata = account_by_key(&result.resulting_accounts, &case.ata_key);
    assert_eq!(
        post_ata.owner, token_id,
        "created ATA owner = classic Token"
    );
    assert_eq!(post_ata.data.len(), TOKEN_ACCOUNT_DATA_BYTES);
    assert_eq!(
        post_ata.data,
        pack_classic_token_account(
            &case.mint_key,
            &case.wallet_key,
            0,
            TOKEN_ACCOUNT_STATE_INITIALIZED,
            None,
        ),
        "created ATA must have the exact classic Token Account layout",
    );
    assert_eq!(
        &post_ata.data[0..32],
        case.mint_key.as_ref(),
        "ATA mint join"
    );
    assert_eq!(
        &post_ata.data[32..64],
        case.wallet_key.as_ref(),
        "ATA wallet-owner join"
    );
    assert_eq!(
        post_ata.data[108], TOKEN_ACCOUNT_STATE_INITIALIZED,
        "ATA initialized"
    );
    assert_eq!(token_account_amount(&post_ata.data), 0);
    assert_eq!(
        post_ata.lamports, ATA_RENT_LAMPORTS,
        "created ATA must receive the pinned 165-byte rent exemption"
    );

    let post_payer = account_by_key(&result.resulting_accounts, &case.payer_key);
    assert_eq!(
        post_payer.lamports,
        case.payer_lamports - ATA_RENT_LAMPORTS,
        "payer must fund exactly the pinned ATA rent"
    );
    assert_eq!(
        post_payer.lamports + post_ata.lamports,
        case.payer_lamports,
        "exact payer→ATA lamport conservation (no fees in Mollusk)"
    );
}

#[test]
fn create_idempotent_replay_is_exactly_idempotent() {
    let (mollusk, program_id, _, token_id) = make_cpi_ata_mollusk();

    // First create on fresh target.
    let fresh = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
    let first = mollusk.process_and_validate_instruction(
        &fresh.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
        &fresh.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let created_ata = account_by_key(&first.resulting_accounts, &fresh.ata_key).clone();
    assert_eq!(created_ata.owner, token_id);

    // Replay the exact full resulting account set from the first invocation;
    // only instruction data changes by virtue of executing the same handler again.
    let mut replay =
        CreateIdempotentCase::existing_initialized(program_id, 13, BASE_LAMPORTS, 6, 0);
    for (key, account) in &mut replay.accounts {
        *account = account_by_key(&first.resulting_accounts, key).clone();
    }
    let payer_before = account_by_key(&replay.accounts, &replay.payer_key).clone();
    let second = mollusk.process_and_validate_instruction(
        &replay.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
        &replay.accounts,
        &[Check::success(), Check::return_data(&16u64.to_le_bytes())],
    );
    let post_ata = account_by_key(&second.resulting_accounts, &replay.ata_key);
    assert_eq!(
        post_ata, &created_ata,
        "idempotent replay must not mutate ATA data/owner/lamports/flags"
    );
    assert_eq!(
        account_by_key(&second.resulting_accounts, &replay.payer_key),
        &payer_before,
        "idempotent replay must not charge or mutate payer"
    );
    assert_eq!(
        account_by_key(&second.resulting_accounts, &replay.state_key).data,
        ata_cpi_state(true, 16)
    );
}

#[test]
fn created_ata_is_usable_by_classic_token_transfer_checked() {
    let (mollusk, program_id, _, token_id) = make_cpi_ata_mollusk();
    let case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
    let created = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let ata_post = account_by_key(&created.resulting_accounts, &case.ata_key).clone();

    // Fund a separate classic Token source owned by wallet, then TransferChecked
    // into the newly created ATA via the real Token program (not the ATA caller).
    let source_key = fixed_key(0x91);
    let source_amount = 500u64;
    let transfer_amount = 42u64;
    let source = Account {
        lamports: BASE_LAMPORTS,
        data: pack_classic_token_account(
            &case.mint_key,
            &case.wallet_key,
            source_amount,
            TOKEN_ACCOUNT_STATE_INITIALIZED,
            None,
        ),
        owner: token_id,
        executable: false,
        rent_epoch: 0,
    };
    let mint = account_by_key(&created.resulting_accounts, &case.mint_key).clone();
    let wallet = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
    let token_program = token_program_account();

    let mut transfer_data = Vec::with_capacity(10);
    transfer_data.push(TOKEN_TRANSFER_CHECKED_TAG);
    transfer_data.extend_from_slice(&transfer_amount.to_le_bytes());
    transfer_data.push(case.decimals);

    let transfer_ix = Instruction::new_with_bytes(
        token_id,
        &transfer_data,
        vec![
            AccountMeta::new(source_key, false),
            AccountMeta::new_readonly(case.mint_key, false),
            AccountMeta::new(case.ata_key, false),
            AccountMeta::new_readonly(case.wallet_key, true),
        ],
    );
    let transfer_accounts = [
        (source_key, source),
        (case.mint_key, mint),
        (case.ata_key, ata_post),
        (case.wallet_key, wallet),
        (token_id, token_program),
    ];
    let result = mollusk.process_and_validate_instruction(
        &transfer_ix,
        &transfer_accounts,
        &[Check::success()],
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &source_key).data),
        source_amount - transfer_amount
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &case.ata_key).data),
        transfer_amount,
        "created ATA must accept classic Token TransferChecked credits"
    );
}

#[test]
fn create_idempotent_then_overflow_full_snapshot_rollback() {
    let (mut mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    let case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_ATA_CREATE_IDEMPOTENT_THEN_OVERFLOW_HANDLER_ID,
        ),
        &case.accounts,
        ARITHMETIC_OVERFLOW,
    );

    // Runtime order forcing: the real ATA program must enter, its nested
    // System/Token initialization must complete, and ATA itself must report
    // success before the caller's checked-add fails with 0x1001.
    let logs = logger.borrow().get_recorded_content().to_vec();
    let ordered = [
        "Program log: CreateIdempotent",
        "Program 11111111111111111111111111111111 success",
        "Program log: Instruction: InitializeAccount3",
        "Program ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL success",
    ];
    let mut cursor = 0usize;
    for needle in ordered {
        let relative = logs[cursor..]
            .iter()
            .position(|line| line.contains(needle))
            .unwrap_or_else(|| {
                panic!("missing ordered overflow-path log {needle:?}; logs={logs:?}")
            });
        cursor += relative + 1;
    }
}

#[test]
fn underfunded_payer_inner_failure_full_snapshot() {
    let (mut mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    let logger = LogCollector::new_ref();
    mollusk.logger = Some(Rc::clone(&logger));
    // Below rent-exempt for 165-byte Token account; System create fails.
    let case = CreateIdempotentCase::fresh(program_id, 10, 1_000, 6);
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(
                SYSTEM_ERR_RESULT_WITH_NEGATIVE_LAMPORTS,
            )),
            Check::return_data(&[]),
        ],
    );
    let logs = logger.borrow().get_recorded_content().to_vec();
    assert!(
        logs.iter()
            .any(|line| line.contains("Transfer: insufficient lamports 1000, need 2039280")),
        "underfunded case must reach native System transfer; logs={logs:?}"
    );
}

#[test]
fn inspect_reads_initialized_state() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    let state_key = fixed_key(0xa0);
    let state = state_account(&program_id, ata_cpi_state(true, 41));
    mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_ata_simple_ix_data(CPI_ATA_INSPECT_HANDLER_ID),
            vec![AccountMeta::new_readonly(state_key, false)],
        ),
        &[(state_key, state)],
        &[Check::success(), Check::return_data(&41u64.to_le_bytes())],
    );
}

// ---------------------------------------------------------------------------
// One-mutation full-snapshot negatives
// ---------------------------------------------------------------------------

fn run_create_mutation(code: u32, mutate: impl FnOnce(&mut CreateIdempotentCase)) {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
    mutate(&mut case);
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
        &case.accounts,
        code,
    );
}

#[test]
fn one_mutation_ata_key_and_fresh_prestate_negatives() {
    // Wrong ATA key (not the derived address).
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        let wrong = fixed_key(0xee);
        c.metas[2] = AccountMeta::new(wrong, false);
        c.accounts[2] = (wrong, unused_system_create_target_account());
        c.ata_key = wrong;
    });
    // Fresh prestate with non-zero lamports (must be exact zero for create path).
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[2].1 = Account::new(1, 0, &Pubkey::default());
    });
    // Fresh prestate with non-empty data under System owner.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        let mut acct = unused_system_create_target_account();
        acct.data = vec![0u8; 1];
        c.accounts[2].1 = acct;
    });
    // Fresh prestate owned by non-System.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[2].1.owner = c.token_program_key;
    });
}

#[test]
fn one_mutation_existing_ata_shape_and_join_negatives() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    let base = CreateIdempotentCase::existing_initialized(program_id, 10, BASE_LAMPORTS, 6, 7);

    // Wrong mint field join inside existing ATA data.
    {
        let mut case = base.clone();
        case.accounts[2].1.data = pack_classic_token_account(
            &fixed_key(0xef),
            &case.wallet_key,
            7,
            TOKEN_ACCOUNT_STATE_INITIALIZED,
            None,
        );
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Wrong wallet-owner join.
    {
        let mut case = base.clone();
        case.accounts[2].1.data = pack_classic_token_account(
            &case.mint_key,
            &fixed_key(0xed),
            7,
            TOKEN_ACCOUNT_STATE_INITIALIZED,
            None,
        );
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Frozen existing ATA.
    {
        let mut case = base.clone();
        case.accounts[2].1.data = pack_classic_token_account(
            &case.mint_key,
            &case.wallet_key,
            7,
            TOKEN_ACCOUNT_STATE_FROZEN,
            None,
        );
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Uninitialized state byte with Token owner + 165B.
    {
        let mut case = base.clone();
        case.accounts[2].1.data = pack_classic_token_account(
            &case.mint_key,
            &case.wallet_key,
            7,
            TOKEN_ACCOUNT_STATE_UNINITIALIZED,
            None,
        );
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Wrong length 164.
    {
        let mut case = base.clone();
        case.accounts[2].1.data.truncate(164);
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn one_mutation_mint_account_negatives() {
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[4].1.owner = Pubkey::default();
    });
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[4].1.data.truncate(81);
    });
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[4].1.data.push(0);
    });
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[4].1.data = pack_classic_mint(&c.mint_authority, 1, c.decimals, 0);
    });
}

#[test]
fn one_mutation_payer_and_wallet_negatives() {
    // Payer non-zero data (must be exact 0).
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[1].1.data = vec![0u8; 1];
    });
    // Payer wrong owner (not System).
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[1].1.owner = c.token_program_key;
    });
    // Wallet unexpected executable.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.accounts[3].1.executable = true;
    });
}

#[test]
fn one_mutation_privilege_and_flag_negatives() {
    // State missing writable.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[0] = AccountMeta::new_readonly(c.state_key, false);
    });
    // Payer missing signer.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[1] = AccountMeta::new(c.payer_key, false);
    });
    // Payer missing writable.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[1] = AccountMeta::new_readonly(c.payer_key, true);
    });
    // ATA missing writable.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[2] = AccountMeta::new_readonly(c.ata_key, false);
    });
    // ATA unexpected signer.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[2] = AccountMeta::new(c.ata_key, true);
    });
    // Wallet unexpected writable.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[3] = AccountMeta::new(c.wallet_key, false);
    });
    // Mint unexpected writable.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[4] = AccountMeta::new(c.mint_key, false);
    });
    // Writable state must not acquire signer privilege.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[0] = AccountMeta::new(c.state_key, true);
    });
    // Readonly wallet/mint must not acquire signer privilege.
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[3] = AccountMeta::new_readonly(c.wallet_key, true);
    });
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[4] = AccountMeta::new_readonly(c.mint_key, true);
    });
    // Every fixed program role is readonly and non-signer at the outer level.
    for index in 5..=7 {
        run_create_mutation(CHECK_OR_UNKNOWN, move |c| {
            let key = c.metas[index].pubkey;
            c.metas[index] = AccountMeta::new(key, false);
        });
        run_create_mutation(CHECK_OR_UNKNOWN, move |c| {
            let key = c.metas[index].pubkey;
            c.metas[index] = AccountMeta::new_readonly(key, true);
        });
    }
}

#[test]
fn one_mutation_alias_negatives() {
    // payer == ata
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[2] = AccountMeta::new(c.payer_key, false);
    });
    // wallet == mint
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[3] = AccountMeta::new_readonly(c.mint_key, false);
    });
    // ata == mint
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[2] = AccountMeta::new(c.mint_key, false);
    });
    // wallet == ata key
    run_create_mutation(CHECK_OR_UNKNOWN, |c| {
        c.metas[3] = AccountMeta::new_readonly(c.ata_key, false);
    });
}

#[test]
fn one_mutation_role_count_and_order_negatives() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    let case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);

    // Missing middle role (drop mint).
    {
        let mut metas = case.metas.clone();
        let mut accounts = case.accounts.clone();
        metas.remove(4);
        accounts.remove(4);
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_ata_simple_ix_data(CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Missing trailing token program.
    {
        let mut metas = case.metas.clone();
        let mut accounts = case.accounts.clone();
        metas.pop();
        accounts.pop();
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_ata_simple_ix_data(CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Extra role.
    {
        let extra = fixed_key(0x99);
        let mut metas = case.metas.clone();
        let mut accounts = case.accounts.clone();
        metas.push(AccountMeta::new_readonly(extra, false));
        accounts.push((extra, Account::new(BASE_LAMPORTS, 0, &Pubkey::default())));
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_ata_simple_ix_data(CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Swapped system / token order at the end.
    {
        let mut metas = case.metas.clone();
        let mut accounts = case.accounts.clone();
        metas.swap(6, 7);
        accounts.swap(6, 7);
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_ata_simple_ix_data(CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn ata_program_identity_loader_and_executable_negatives() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    // Wrong ATA program key.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        let wrong = fixed_key(0xab);
        let mut fake = create_program_account_loader_v3(&wrong);
        fake.executable = true;
        case.metas[5] = AccountMeta::new_readonly(wrong, false);
        case.accounts[5] = (wrong, fake);
        case.ata_program_key = wrong;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Correct key, non-executable.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        case.accounts[5].1.executable = false;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Correct key, wrong loader owner.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        case.accounts[5].1.owner = Pubkey::default();
        case.accounts[5].1.executable = true;
        assert_ne!(case.accounts[5].1.owner, loader_v3_owner());
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn classic_token_and_token2022_program_negatives() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();
    // Token-2022 substitution.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        let wrong = token_2022_program_id();
        let mut fake = create_program_account_loader_v3(&wrong);
        fake.executable = true;
        case.metas[7] = AccountMeta::new_readonly(wrong, false);
        case.accounts[7] = (wrong, fake);
        case.token_program_key = wrong;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Classic Token key non-executable.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        case.accounts[7].1.executable = false;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Classic Token wrong loader owner.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        case.accounts[7].1.owner = Pubkey::default();
        case.accounts[7].1.executable = true;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn native_system_program_identity_negatives() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();

    // Wrong key only: retain the exact native System account fields so the
    // mutation does not also rely on a loader-owner or executable mismatch.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        let wrong = fixed_key(0x75);
        let native = case.accounts[6].1.clone();
        case.metas[6] = AccountMeta::new_readonly(wrong, false);
        case.accounts[6] = (wrong, native);
        case.system_program_key = wrong;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Correct key, wrong native-loader owner only.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        case.accounts[6].1.owner = loader_v3_owner();
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Correct key/owner, non-executable only.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        case.accounts[6].1.executable = false;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn wrong_wallet_mint_or_token_seed_derivation_fails() {
    let (mollusk, program_id, _, _) = make_cpi_ata_mollusk();

    // Wrong wallet → derived ATA for that wallet differs from supplied ata key.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        let wrong_wallet = fixed_key(0x32);
        case.metas[3] = AccountMeta::new_readonly(wrong_wallet, false);
        case.accounts[3] = (
            wrong_wallet,
            Account::new(BASE_LAMPORTS, 0, &Pubkey::default()),
        );
        case.wallet_key = wrong_wallet;
        // Keep ata_key as original derivation for 0x31 wallet → address check fails.
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Wrong mint → derivation mismatch.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        let wrong_mint = fixed_key(0x42);
        let mint_account = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(&case.mint_authority, 1_000_000, case.decimals, 1),
            owner: case.token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        case.metas[4] = AccountMeta::new_readonly(wrong_mint, false);
        case.accounts[4] = (wrong_mint, mint_account);
        case.mint_key = wrong_mint;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // ATA address for (wallet, Token-2022, mint) under classic ATA program is
    // different — supply that key while keeping classic Token program role.
    {
        let mut case = CreateIdempotentCase::fresh(program_id, 10, BASE_LAMPORTS, 6);
        let token_2022 = token_2022_program_id();
        // Derive as if Token-2022 were the seed (wrong seed surface).
        let mut wrong_addr = None;
        for bump in (1u8..=255).rev() {
            let bump_slice = [bump];
            let seeds: &[&[u8]] = &[
                case.wallet_key.as_ref(),
                token_2022.as_ref(),
                case.mint_key.as_ref(),
                &bump_slice,
            ];
            if let Ok(addr) = Pubkey::create_program_address(seeds, &case.ata_program_key) {
                wrong_addr = Some(addr);
                break;
            }
        }
        let wrong = wrong_addr.expect("token-2022 seed PDA");
        assert_ne!(wrong, case.ata_key);
        case.metas[2] = AccountMeta::new(wrong, false);
        case.accounts[2] = (wrong, unused_system_create_target_account());
        case.ata_key = wrong;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn handler_ids_are_dense() {
    assert_eq!(CPI_ATA_INIT_HANDLER_ID, 0);
    assert_eq!(CPI_ATA_CREATE_IDEMPOTENT_HANDLER_ID, 1);
    assert_eq!(CPI_ATA_CREATE_IDEMPOTENT_THEN_OVERFLOW_HANDLER_ID, 2);
    assert_eq!(CPI_ATA_INSPECT_HANDLER_ID, 3);
    let _ = cpi_ata_init_ix_data(CPI_ATA_INIT_HANDLER_ID, 0);
}
