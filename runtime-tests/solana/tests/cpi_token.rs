//! #122 production-code-generated classic Token CPI runtime closure.
//!
//! Caller ELF via SolanaCpiTokenExportV1 + locked sbpf 0.2.2.
//! Classic Token ELF is vendored source-built `program@v9.0.0`
//! (`token_classic_v1.so`). Catalog `artifactBinding` remains `absent`;
//! boundary is testPreactivation + activationDenied.
//!
//! Requires `PROOF_FORGE_CPI_TOKEN_OUT` from `scripts/solana_cpi_token_build.sh`.

#[allow(dead_code)]
mod common;

use {
    common::*,
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
    serde_json::{json, Map, Value},
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{
        collections::BTreeSet,
        env, fs,
        path::{Path, PathBuf},
    },
};

// ---------------------------------------------------------------------------
// Frozen #122 identities
// ---------------------------------------------------------------------------

const CPI_TOKEN_PROGRAM_ID_BYTES: [u8; 32] = [0x57; 32];
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

const CPI_TOKEN_FIXTURE_SHA256: &str =
    "605a7609254332a232cf4a46f3d2d86d870367dbcb3afcb19b13b8b822a0e76e";
const CPI_TOKEN_FIXTURE_SIZE: u64 = 3075;
const CPI_TOKEN_ASSEMBLY_SHA256: &str =
    "3cf744e36b5a91a441dbb06a33050613fcc366b57a03ad2b970f78cbe131e9fd";
const CPI_TOKEN_ASSEMBLY_SIZE: u64 = 160129;
const CPI_TOKEN_ELF_SHA256: &str =
    "4c7a10cc7dc5e411a9eec3109722e2080a48ac7a64868c34d4a60f7a813464c7";
const CPI_TOKEN_ELF_SIZE: u64 = 67608;
const TOKEN_CLASSIC_ELF_SHA256: &str =
    "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9";
const TOKEN_CLASSIC_ELF_SIZE: u64 = 94960;
const CATALOG_DIGEST: &str = "41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351";
const TOKEN_TAG_OBJECT: &str = "5c37ac99c248567bd7d50b965af8cbd45b6ced96";
const TOKEN_PEELED_COMMIT: &str = "dfb260231c761be7d9c8b63728e770a102b86495";
const TOKEN_RECIPE_MANIFEST_DIGEST: &str =
    "4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063";
const PROFILE_DIGEST: &str = "0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1";
const EXTENSION_DIGEST: &str = "df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020";
const PDA_SEED0_UTF8: &str = "proof-forge:pda:v1";
const PDA_SEED0_HEX: &str = "70726f6f662d666f7267653a7064613a7631";
const TOKEN_REPO: &str = "https://github.com/solana-program/token";

const CPI_TOKEN_INIT_HANDLER_ID: u64 = 0;
const CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID: u64 = 1;
const CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID: u64 = 2;
const CPI_TOKEN_TRANSFER_CHECKED_THEN_OVERFLOW_HANDLER_ID: u64 = 3;
const CPI_TOKEN_TRANSFER_CHECKED_PDA_THEN_OVERFLOW_HANDLER_ID: u64 = 4;
const CPI_TOKEN_INSPECT_HANDLER_ID: u64 = 5;

const CPI_TOKEN_TRANSFER_CHECKED_IX_LEN: usize = 17;
const CPI_TOKEN_TRANSFER_CHECKED_PDA_IX_LEN: usize = 26;
const TOKEN_TRANSFER_CHECKED_TAG: u8 = 12;
const TOKEN_TRANSFER_CHECKED_DATA_BYTES: usize = 10;
const TOKEN_MINT_DATA_BYTES: usize = 82;
const TOKEN_ACCOUNT_DATA_BYTES: usize = 165;
const TOKEN_ACCOUNT_STATE_UNINITIALIZED: u8 = 0;
const TOKEN_ACCOUNT_STATE_INITIALIZED: u8 = 1;
const TOKEN_ACCOUNT_STATE_FROZEN: u8 = 2;
const CPI_TOKEN_STEM: &str = "token_cpi";

/// Official classic Token custom codes observed under Mollusk + v9 ELF.
const TOKEN_ERR_INSUFFICIENT_FUNDS: u32 = 1;
/// Observed stable custom code when destination amount + transfer overflows u64
/// under vendored program@v9.0.0 (not InsufficientFunds=1).
const TOKEN_ERR_DESTINATION_AMOUNT_OVERFLOW: u32 = 14;

const EXPECTED_FINAL_ELF_CALLS: &[&str] = &[
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
    "sol_try_find_program_address",
    "sol_invoke_signed_c",
    "sol_set_return_data",
    "sol_set_return_data",
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
    "not p-token",
    "not mollusk-embedded token.so",
];

/// Closed, source-order evidence index of every runtime acceptance `#[test]`.
/// Pure manifest/layout tests are intentionally excluded.
const FORCING_MATRIX_CASES: &[&str] = &[
    // Artifact bind + success paths
    "generated_assembly_and_elf_are_exact_preactivation",
    "transfer_checked_success_exact_balance_delta_and_state_order",
    "transfer_checked_high_byte_amount_success",
    "transfer_checked_pda_success_canonical_bump_and_balance_delta",
    "transfer_checked_then_overflow_full_snapshot_rollback",
    "transfer_checked_pda_then_overflow_full_snapshot_rollback",
    "inner_token_failure_precise_status_empty_return_data",
    "destination_amount_overflow_inner_error_empty_return_snapshot",
    "inspect_reads_initialized_state",
    // One-mutation full-snapshot groups (table-driven)
    "one_mutation_source_account_negatives",
    "one_mutation_destination_account_negatives",
    "one_mutation_mint_account_negatives",
    "one_mutation_privilege_and_flag_negatives",
    "one_mutation_alias_negatives",
    "one_mutation_role_count_negatives",
    // Program identity / loader surface
    "token2022_wrong_key_substitution_independent",
    "token_program_account_non_executable_or_wrong_loader_owner",
    // PDA privileges + noncanonical + authority meta
    "one_mutation_pda_privilege_negatives",
    "noncanonical_bump_fails_full_snapshot",
    "wrong_authority_meta_key_fails_full_snapshot",
];

// Recursive exact-key schema: path → required keys (sorted for reporting).
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
            "token",
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
        "/token" => Some(&[
            "package",
            "programIdHex",
            "executionClass",
            "artifactBinding",
            "interface",
            "instructionSurface",
            "vendoredSourceBuiltElf",
        ]),
        "/token/interface" => Some(&[
            "repo",
            "tag",
            "tagObject",
            "peeledCommit",
            "programVersion",
            "interfaceVersion",
        ]),
        "/token/instructionSurface" => Some(&[
            "transferCheckedTag",
            "transferCheckedDataBytes",
            "mintDataBytes",
            "tokenAccountDataBytes",
        ]),
        "/token/vendoredSourceBuiltElf" => Some(&[
            "status",
            "path",
            "sha256",
            "size",
            "source",
            "recipe",
            "nonClaims",
            "note",
        ]),
        "/token/vendoredSourceBuiltElf/source" => {
            Some(&["repo", "tag", "tagObject", "peeledCommit"])
        }
        "/token/vendoredSourceBuiltElf/recipe" => Some(&[
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
        "/token2022Negative" => Some(&["programIdBase58", "programIdHex", "note"]),
        "/handlers" => Some(&[
            "init",
            "transferChecked",
            "transferCheckedPda",
            "transferCheckedThenOverflow",
            "transferCheckedPdaThenOverflow",
            "inspect",
        ]),
        "/pda" => Some(&[
            "recipe",
            "seed0Utf8",
            "seed0Hex",
            "canonicalBumpSearch",
            "bump0Rejected",
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

fn committed_cpi_token_manifest_bytes() -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("token/manifest.json");
    fs::read(&path).unwrap_or_else(|e| panic!("read committed token manifest: {e}"))
}

fn committed_cpi_token_manifest_value() -> Value {
    serde_json::from_slice(&committed_cpi_token_manifest_bytes()).expect("decode manifest")
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
                // Unknown nested object under a leaf we don't model: reject to
                // keep the closed schema honest.
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
    if s.len() != 64
        || !s
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    {
        // allow only lowercase hex
        if s.len() != 64 || s.bytes().any(|b| !matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
            return Err(format!("{label} must be 64 lowercase hex digits"));
        }
    }
    Ok(())
}

fn validate_cpi_token_manifest_bytes(bytes: &[u8]) -> Result<(), String> {
    let value: Value = serde_json::from_slice(bytes).map_err(|e| format!("decode: {e}"))?;
    validate_recursive_exact_keys(&value, "")?;

    expect_eq(
        &value,
        "/schema",
        json!("proof-forge.solana.cpi-token-runtime.v1"),
    )?;
    expect_eq(&value, "/issue", json!(122))?;
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
        json!("runtime-tests/solana/fixtures/TokenCpi.lean"),
    )?;
    expect_eq(&value, "/fixture/module", json!("Examples.TokenCpi"))?;
    expect_eq(
        &value,
        "/fixture/sourceSha256",
        json!(CPI_TOKEN_FIXTURE_SHA256),
    )?;
    expect_eq(&value, "/fixture/sourceSize", json!(CPI_TOKEN_FIXTURE_SIZE))?;
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
        json!(hex::encode(CPI_TOKEN_PROGRAM_ID_BYTES)),
    )?;
    expect_eq(&value, "/catalogDigest", json!(CATALOG_DIGEST))?;

    expect_eq(&value, "/token/package", json!("token-classic-v1"))?;
    expect_eq(
        &value,
        "/token/programIdHex",
        json!(hex::encode(TOKEN_CLASSIC_PROGRAM_ID_BYTES)),
    )?;
    expect_eq(&value, "/token/executionClass", json!("loaderV3Sbpf"))?;
    expect_eq(&value, "/token/artifactBinding", json!("absent"))?;
    expect_eq(&value, "/token/interface/repo", json!(TOKEN_REPO))?;
    expect_eq(&value, "/token/interface/tag", json!("program@v9.0.0"))?;
    expect_eq(
        &value,
        "/token/interface/tagObject",
        json!(TOKEN_TAG_OBJECT),
    )?;
    expect_eq(
        &value,
        "/token/interface/peeledCommit",
        json!(TOKEN_PEELED_COMMIT),
    )?;
    expect_eq(&value, "/token/interface/programVersion", json!("9.0.0"))?;
    expect_eq(&value, "/token/interface/interfaceVersion", json!("2.0.0"))?;
    expect_eq(
        &value,
        "/token/instructionSurface/transferCheckedTag",
        json!(TOKEN_TRANSFER_CHECKED_TAG),
    )?;
    expect_eq(
        &value,
        "/token/instructionSurface/transferCheckedDataBytes",
        json!(TOKEN_TRANSFER_CHECKED_DATA_BYTES),
    )?;
    expect_eq(
        &value,
        "/token/instructionSurface/mintDataBytes",
        json!(TOKEN_MINT_DATA_BYTES),
    )?;
    expect_eq(
        &value,
        "/token/instructionSurface/tokenAccountDataBytes",
        json!(TOKEN_ACCOUNT_DATA_BYTES),
    )?;

    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/status",
        json!("ready"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/path",
        json!("runtime-tests/solana/token/token_classic_v1.so"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/sha256",
        json!(TOKEN_CLASSIC_ELF_SHA256),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/size",
        json!(TOKEN_CLASSIC_ELF_SIZE),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/source/repo",
        json!(TOKEN_REPO),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/source/tag",
        json!("program@v9.0.0"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/source/tagObject",
        json!(TOKEN_TAG_OBJECT),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/source/peeledCommit",
        json!(TOKEN_PEELED_COMMIT),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/command",
        json!("cargo-build-sbf --manifest-path program/Cargo.toml"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/solanaCli",
        json!("3.0.0"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/cargoBuildSbf",
        json!("3.0.0"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/platformTools",
        json!("v1.51"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/sbfRustc",
        json!("1.84.1-dev"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/sourceRustToolchain",
        json!("1.86.0"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/host",
        json!("Darwin arm64"),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/recipeManifestDigest",
        json!(TOKEN_RECIPE_MANIFEST_DIGEST),
    )?;
    expect_eq(
        &value,
        "/token/vendoredSourceBuiltElf/recipe/sameHostRepeat",
        json!(2),
    )?;

    let non_claims = value
        .pointer("/token/vendoredSourceBuiltElf/nonClaims")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "nonClaims missing".to_string())?;
    let got: Vec<&str> = non_claims.iter().filter_map(|v| v.as_str()).collect();
    if got != EXPECTED_NON_CLAIMS {
        return Err(format!(
            "nonClaims exact ordered mismatch:\n  got  {got:?}\n  want {EXPECTED_NON_CLAIMS:?}"
        ));
    }

    expect_eq(&value, "/handlers/init", json!(0))?;
    expect_eq(&value, "/handlers/transferChecked", json!(1))?;
    expect_eq(&value, "/handlers/transferCheckedPda", json!(2))?;
    expect_eq(&value, "/handlers/transferCheckedThenOverflow", json!(3))?;
    expect_eq(&value, "/handlers/transferCheckedPdaThenOverflow", json!(4))?;
    expect_eq(&value, "/handlers/inspect", json!(5))?;

    expect_eq(&value, "/pda/recipe", json!("current-program-tagged-v1"))?;
    expect_eq(&value, "/pda/seed0Utf8", json!(PDA_SEED0_UTF8))?;
    expect_eq(&value, "/pda/seed0Hex", json!(PDA_SEED0_HEX))?;
    if hex::encode(PDA_SEED0_UTF8.as_bytes()) != PDA_SEED0_HEX {
        return Err("seed0Utf8/hex internal inconsistency".into());
    }
    expect_eq(&value, "/pda/canonicalBumpSearch", json!("255..1"))?;
    expect_eq(&value, "/pda/bump0Rejected", json!(true))?;

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
        json!(CPI_TOKEN_ASSEMBLY_SHA256),
    )?;
    expect_eq(
        &value,
        "/expectedAssembly/size",
        json!(CPI_TOKEN_ASSEMBLY_SIZE),
    )?;
    expect_eq(&value, "/expectedElf/sha256", json!(CPI_TOKEN_ELF_SHA256))?;
    expect_eq(&value, "/expectedElf/size", json!(CPI_TOKEN_ELF_SIZE))?;

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
        "/token/vendoredSourceBuiltElf/sha256",
        "/expectedAssembly/sha256",
        "/expectedElf/sha256",
        "/token/vendoredSourceBuiltElf/recipe/recipeManifestDigest",
    ] {
        let s = value
            .pointer(pointer)
            .and_then(|v| v.as_str())
            .ok_or_else(|| format!("{pointer} not string"))?;
        lower_hex64(s, pointer)?;
    }
    for pointer in [
        "/token/interface/tagObject",
        "/token/interface/peeledCommit",
        "/token/vendoredSourceBuiltElf/source/tagObject",
        "/token/vendoredSourceBuiltElf/source/peeledCommit",
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
        "not an activated CPI artifact",
        "not mainnet parity",
        "program@v9.0.0",
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

fn cpi_token_out_dir() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_CPI_TOKEN_OUT").expect(
            "PROOF_FORGE_CPI_TOKEN_OUT must point at scripts/solana_cpi_token_build.sh output",
        ),
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
    let out = cpi_token_out_dir();
    let committed = committed_cpi_token_manifest_bytes();
    let staged = stable_read(&out.join("manifest.json"), "output manifest");
    assert_eq!(
        staged, committed,
        "output manifest must equal committed bytes"
    );
    validate_cpi_token_manifest_bytes(&committed).expect("committed manifest");
    let path = out.join(format!("{CPI_TOKEN_STEM}.{suffix}"));
    let size_bytes = stable_read(
        &out.join(format!("{CPI_TOKEN_STEM}.{suffix}.size")),
        "size sidecar",
    );
    let hash_bytes = stable_read(
        &out.join(format!("{CPI_TOKEN_STEM}.{suffix}.sha256")),
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

fn read_cpi_token_assembly() -> Vec<u8> {
    let bytes = read_bound_artifact(
        "s",
        CPI_TOKEN_ASSEMBLY_SHA256,
        CPI_TOKEN_ASSEMBLY_SIZE,
        "assembly",
    );
    assert!(bytes
        .windows(b"TEST-PREACTIVATION ONLY".len())
        .any(|w| w == b"TEST-PREACTIVATION ONLY"));
    for req in [
        b"sol_invoke_signed_c" as &[u8],
        b"sol_try_find_program_address",
        b"sol_set_return_data",
    ] {
        assert!(bytes.windows(req.len()).any(|w| w == req));
    }
    bytes
}

fn read_cpi_token_caller_elf() -> Vec<u8> {
    let bytes = read_bound_artifact("so", CPI_TOKEN_ELF_SHA256, CPI_TOKEN_ELF_SIZE, "caller ELF");
    assert!(bytes.starts_with(b"\x7fELF"));
    bytes
}

fn read_vendored_token_elf() -> Vec<u8> {
    let out = cpi_token_out_dir();
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

fn cpi_token_program_id() -> Pubkey {
    Pubkey::new_from_array(CPI_TOKEN_PROGRAM_ID_BYTES)
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

fn make_cpi_token_mollusk() -> (Mollusk, Pubkey, Pubkey) {
    let program_id = cpi_token_program_id();
    let token_id = token_classic_program_id();
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_cpi_token_caller_elf(),
    );
    mollusk.add_program_with_loader_and_elf(
        &token_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &read_vendored_token_elf(),
    );
    (mollusk, program_id, token_id)
}

// ---------------------------------------------------------------------------
// Packing helpers
// ---------------------------------------------------------------------------

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
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

fn token_cpi_fields() -> [StateField; 1] {
    single_field("value")
}

fn token_cpi_state(initialized: bool, value: u64) -> Vec<u8> {
    state_data(&token_cpi_fields(), initialized, &[value])
}

fn cpi_token_transfer_checked_ix_data(handler_id: u64, amount: u64, decimals: u8) -> Vec<u8> {
    let mut data = Vec::with_capacity(CPI_TOKEN_TRANSFER_CHECKED_IX_LEN);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&amount.to_le_bytes());
    data.push(decimals);
    data
}

fn cpi_token_transfer_checked_pda_ix_data(
    handler_id: u64,
    seed_tag: u64,
    bump: u8,
    amount: u64,
    decimals: u8,
) -> Vec<u8> {
    let mut data = Vec::with_capacity(CPI_TOKEN_TRANSFER_CHECKED_PDA_IX_LEN);
    data.extend_from_slice(&handler_id.to_le_bytes());
    data.extend_from_slice(&seed_tag.to_le_bytes());
    data.push(bump);
    data.extend_from_slice(&amount.to_le_bytes());
    data.push(decimals);
    data
}

fn cpi_token_simple_ix_data(handler_id: u64, params: &[u64]) -> Vec<u8> {
    let mut data = Vec::with_capacity(8 + params.len() * 8);
    data.extend_from_slice(&handler_id.to_le_bytes());
    for p in params {
        data.extend_from_slice(&p.to_le_bytes());
    }
    data
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
// Cases
// ---------------------------------------------------------------------------

#[derive(Clone)]
struct TransferCheckedCase {
    state_key: Pubkey,
    source_key: Pubkey,
    mint_key: Pubkey,
    destination_key: Pubkey,
    authority_key: Pubkey,
    token_program_key: Pubkey,
    mint_authority: Pubkey,
    dest_owner: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    source_amount: u64,
    destination_amount: u64,
    decimals: u8,
}

impl TransferCheckedCase {
    fn new(
        program_id: Pubkey,
        state_value: u64,
        source_amount: u64,
        destination_amount: u64,
        decimals: u8,
        authority_is_signer: bool,
    ) -> Self {
        let state_key = fixed_key(0x60);
        let source_key = fixed_key(0x61);
        let mint_key = fixed_key(0x62);
        let destination_key = fixed_key(0x63);
        let authority_key = fixed_key(0x64);
        let token_program_key = token_classic_program_id();
        let mint_authority = fixed_key(0x70);
        let dest_owner = fixed_key(0x71);

        let state = state_account(&program_id, token_cpi_state(true, state_value));
        let mint = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(
                &mint_authority,
                source_amount.saturating_add(destination_amount),
                decimals,
                1,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let source = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &authority_key,
                source_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let destination = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &dest_owner,
                destination_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let authority = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let token_program = token_program_account();
        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(source_key, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new(destination_key, false),
            AccountMeta::new_readonly(authority_key, authority_is_signer),
            AccountMeta::new_readonly(token_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (source_key, source),
            (mint_key, mint),
            (destination_key, destination),
            (authority_key, authority),
            (token_program_key, token_program),
        ];
        Self {
            state_key,
            source_key,
            mint_key,
            destination_key,
            authority_key,
            token_program_key,
            mint_authority,
            dest_owner,
            metas,
            accounts,
            source_amount,
            destination_amount,
            decimals,
        }
    }

    fn instruction(&self, program_id: Pubkey, handler_id: u64, amount: u64) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_token_transfer_checked_ix_data(handler_id, amount, self.decimals),
            self.metas.clone(),
        )
    }

    fn instruction_decimals(
        &self,
        program_id: Pubkey,
        handler_id: u64,
        amount: u64,
        decimals: u8,
    ) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_token_transfer_checked_ix_data(handler_id, amount, decimals),
            self.metas.clone(),
        )
    }
}

#[derive(Clone)]
struct TransferCheckedPdaCase {
    state_key: Pubkey,
    source_key: Pubkey,
    mint_key: Pubkey,
    destination_key: Pubkey,
    authority_pda: Pubkey,
    seed_authority: Pubkey,
    seed_tag: u64,
    bump: u8,
    token_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
    source_amount: u64,
    destination_amount: u64,
    decimals: u8,
}

impl TransferCheckedPdaCase {
    fn new(
        program_id: Pubkey,
        state_value: u64,
        seed_tag: u64,
        source_amount: u64,
        destination_amount: u64,
        decimals: u8,
        seed_authority_signer: bool,
    ) -> Self {
        let state_key = fixed_key(0x80);
        let source_key = fixed_key(0x81);
        let mint_key = fixed_key(0x82);
        let destination_key = fixed_key(0x83);
        let seed_authority = fixed_key(0x84);
        let (authority_pda, bump) =
            find_pda_current_program_tagged_v1(&program_id, &seed_authority, seed_tag);
        let token_program_key = token_classic_program_id();
        let mint_authority = fixed_key(0x90);
        let dest_owner = fixed_key(0x91);

        let state = state_account(&program_id, token_cpi_state(true, state_value));
        let mint = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_mint(
                &mint_authority,
                source_amount.saturating_add(destination_amount),
                decimals,
                1,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let source = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &authority_pda,
                source_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let destination = Account {
            lamports: BASE_LAMPORTS,
            data: pack_classic_token_account(
                &mint_key,
                &dest_owner,
                destination_amount,
                TOKEN_ACCOUNT_STATE_INITIALIZED,
                None,
            ),
            owner: token_program_key,
            executable: false,
            rent_epoch: 0,
        };
        let pda_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let authority_account = Account::new(BASE_LAMPORTS, 0, &Pubkey::default());
        let token_program = token_program_account();
        let metas = vec![
            AccountMeta::new(state_key, false),
            AccountMeta::new(source_key, false),
            AccountMeta::new_readonly(mint_key, false),
            AccountMeta::new(destination_key, false),
            AccountMeta::new_readonly(authority_pda, false),
            AccountMeta::new_readonly(seed_authority, seed_authority_signer),
            AccountMeta::new_readonly(token_program_key, false),
        ];
        let accounts = vec![
            (state_key, state),
            (source_key, source),
            (mint_key, mint),
            (destination_key, destination),
            (authority_pda, pda_account),
            (seed_authority, authority_account),
            (token_program_key, token_program),
        ];
        Self {
            state_key,
            source_key,
            mint_key,
            destination_key,
            authority_pda,
            seed_authority,
            seed_tag,
            bump,
            token_program_key,
            metas,
            accounts,
            source_amount,
            destination_amount,
            decimals,
        }
    }

    fn instruction_canonical(
        &self,
        program_id: Pubkey,
        handler_id: u64,
        amount: u64,
    ) -> Instruction {
        Instruction::new_with_bytes(
            program_id,
            &cpi_token_transfer_checked_pda_ix_data(
                handler_id,
                self.seed_tag,
                self.bump,
                amount,
                self.decimals,
            ),
            self.metas.clone(),
        )
    }
}

fn find_noncanonical_pda_below(
    program_id: &Pubkey,
    seed_authority: &Pubkey,
    seed_tag: u64,
    canonical_bump: u8,
) -> (Pubkey, u8) {
    let tag_le = seed_tag.to_le_bytes();
    for bump in (1..canonical_bump).rev() {
        let bump_slice = [bump];
        let seeds: &[&[u8]] = &[
            HARNESS_PDA_SEED0,
            seed_authority.as_ref(),
            &tag_le,
            &bump_slice,
        ];
        if let Ok(address) = Pubkey::create_program_address(seeds, program_id) {
            return (address, bump);
        }
    }
    panic!("no noncanonical bump below canonical");
}

// ---------------------------------------------------------------------------
// Pure tests
// ---------------------------------------------------------------------------

#[test]
fn committed_manifest_schema_is_exact_preactivation_evidence() {
    let raw = committed_cpi_token_manifest_bytes();
    validate_cpi_token_manifest_bytes(&raw).expect("committed token manifest");
    let value = committed_cpi_token_manifest_value();
    assert_eq!(value["generation"]["status"], json!("ready"));
    assert_eq!(value["token"]["artifactBinding"], json!("absent"));
    assert_eq!(
        value["token"]["vendoredSourceBuiltElf"]["size"],
        json!(TOKEN_CLASSIC_ELF_SIZE)
    );
    assert_eq!(value["pda"]["seed0Utf8"], json!(PDA_SEED0_UTF8));
    assert_eq!(value["pda"]["seed0Hex"], json!(PDA_SEED0_HEX));
}

#[test]
fn fixture_source_matches_committed_identity() {
    let path = repo_root().join("runtime-tests/solana/fixtures/TokenCpi.lean");
    let bytes = fs::read(&path).unwrap();
    assert_eq!(bytes.len() as u64, CPI_TOKEN_FIXTURE_SIZE);
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        CPI_TOKEN_FIXTURE_SHA256
    );
    let text = String::from_utf8_lossy(&bytes);
    assert!(text.contains("vendored source-built"));
    assert!(text.contains("activationDenied"));
    assert!(text.contains("testPreactivation") || text.contains("test-preactivation"));
    assert!(text.contains("artifactBinding remains absent") || text.contains("artifactBinding"));
    assert!(text.contains("Not proof-forge.output.v1"));
    assert!(!text.contains("package-owned locked"));
    assert!(!text.contains("remains fail-closed until"));
}

#[test]
fn vendored_token_elf_matches_committed_v9_pin() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("token/token_classic_v1.so");
    let bytes = fs::read(&path).unwrap();
    assert!(bytes.starts_with(b"\x7fELF"));
    assert_eq!(bytes.len() as u64, TOKEN_CLASSIC_ELF_SIZE);
    assert_eq!(
        hex::encode(Sha256::digest(&bytes)),
        TOKEN_CLASSIC_ELF_SHA256
    );
}

#[test]
fn token_manifest_closed_identity_mutations_fail() {
    let raw = committed_cpi_token_manifest_bytes();
    validate_cpi_token_manifest_bytes(&raw).unwrap();
    let base: Value = serde_json::from_slice(&raw).unwrap();

    // Scalar / value mutations
    let mutations = [
        ("/schema", json!("wrong")),
        ("/issue", json!(121)),
        ("/catalogDigest", json!("00".repeat(32))),
        ("/token/interface/tagObject", json!("00".repeat(32))),
        ("/token/interface/peeledCommit", json!("00".repeat(32))),
        (
            "/token/vendoredSourceBuiltElf/sha256",
            json!("00".repeat(32)),
        ),
        ("/token/vendoredSourceBuiltElf/size", json!(1)),
        ("/pda/seed0Utf8", json!("wrong")),
        ("/pda/seed0Hex", json!("00")),
        ("/expectedAssembly/sha256", json!("00".repeat(32))),
        ("/expectedElf/size", json!(1)),
        ("/expectedFinalElfCalls", json!([])),
        ("/generation/status", json!("blocked")),
        ("/token/artifactBinding", json!("present")),
        ("/reproducibilityNote", json!("")),
    ];
    for (pointer, replacement) in mutations {
        let mut mutated = base.clone();
        *mutated.pointer_mut(pointer).expect(pointer) = replacement;
        assert!(
            validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err(),
            "accepted mutation {pointer}"
        );
    }

    // Extra root key
    {
        let mut mutated = base.clone();
        mutated
            .as_object_mut()
            .unwrap()
            .insert("extraRoot".into(), json!(true));
        assert!(validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err());
    }
    // Missing root key
    {
        let mut mutated = base.clone();
        mutated.as_object_mut().unwrap().remove("catalogDigest");
        assert!(validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err());
    }
    // Extra nested key under token.interface
    {
        let mut mutated = base.clone();
        mutated
            .pointer_mut("/token/interface")
            .unwrap()
            .as_object_mut()
            .unwrap()
            .insert("extra".into(), json!(1));
        assert!(validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err());
    }
    // Missing nested key under vendored recipe
    {
        let mut mutated = base.clone();
        mutated
            .pointer_mut("/token/vendoredSourceBuiltElf/recipe")
            .unwrap()
            .as_object_mut()
            .unwrap()
            .remove("sameHostRepeat");
        assert!(validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err());
    }
    // nonClaims order / membership drift
    {
        let mut mutated = base.clone();
        *mutated
            .pointer_mut("/token/vendoredSourceBuiltElf/nonClaims")
            .unwrap() = json!(["not formal"]);
        assert!(validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err());
    }
    // expectedFinalElfCalls order drift
    {
        let mut mutated = base.clone();
        let mut calls = EXPECTED_FINAL_ELF_CALLS.to_vec();
        calls.swap(0, 1);
        *mutated.pointer_mut("/expectedFinalElfCalls").unwrap() = json!(calls);
        assert!(validate_cpi_token_manifest_bytes(&serde_json::to_vec(&mutated).unwrap()).is_err());
    }
}

#[test]
fn transfer_checked_ix_layout_is_exactly_17_bytes() {
    let data = cpi_token_transfer_checked_ix_data(CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 42, 6);
    assert_eq!(data.len(), 17);
    assert_eq!(&data[8..16], &42u64.to_le_bytes());
    assert_eq!(data[16], 6);
}

#[test]
fn transfer_checked_pda_ix_layout_is_exactly_26_bytes() {
    let data = cpi_token_transfer_checked_pda_ix_data(
        CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID,
        7,
        252,
        1000,
        9,
    );
    assert_eq!(data.len(), 26);
    assert_eq!(data[16], 252);
    assert_eq!(data[25], 9);
}

#[test]
fn classic_layouts_and_program_ids() {
    let mint = pack_classic_mint(&fixed_key(1), 1, 6, 1);
    assert_eq!(mint.len(), 82);
    assert_eq!(mint[45], 1);
    let acct = pack_classic_token_account(
        &fixed_key(2),
        &fixed_key(3),
        9,
        TOKEN_ACCOUNT_STATE_INITIALIZED,
        None,
    );
    assert_eq!(acct.len(), 165);
    assert_eq!(token_account_amount(&acct), 9);
    let with_del = pack_classic_token_account(
        &fixed_key(2),
        &fixed_key(3),
        9,
        TOKEN_ACCOUNT_STATE_INITIALIZED,
        Some(&fixed_key(4)),
    );
    assert_eq!(&with_del[72..76], &1u32.to_le_bytes());
    assert_ne!(token_classic_program_id(), token_2022_program_id());
    assert_eq!(hex::encode(PDA_SEED0_UTF8.as_bytes()), PDA_SEED0_HEX);
}

#[test]
fn case_role_counts_and_flags() {
    let program_id = cpi_token_program_id();
    let tc = TransferCheckedCase::new(program_id, 10, 1000, 0, 6, true);
    assert_eq!(tc.metas.len(), 6);
    assert!(tc.metas[1].is_writable);
    assert!(!tc.metas[2].is_writable);
    assert!(tc.metas[3].is_writable);
    assert!(tc.metas[4].is_signer);
    assert!(!tc.metas[4].is_writable);
    // Consume identity fields so they are not dead.
    assert_ne!(tc.mint_authority, tc.dest_owner);
    assert_eq!(tc.token_program_key, token_classic_program_id());
    assert_eq!(tc.source_key, fixed_key(0x61));
    assert_eq!(tc.mint_key, fixed_key(0x62));
    assert_eq!(tc.destination_key, fixed_key(0x63));
    assert_eq!(tc.authority_key, fixed_key(0x64));
    assert_eq!(tc.state_key, fixed_key(0x60));

    let pda = TransferCheckedPdaCase::new(program_id, 10, 42, 1000, 0, 6, true);
    assert_eq!(pda.metas.len(), 7);
    assert!(!pda.metas[4].is_signer);
    assert!(!pda.metas[4].is_writable);
    assert!(pda.metas[5].is_signer);
    assert!(!pda.metas[5].is_writable);
    assert_ne!(pda.bump, 0);
    assert_eq!(pda.source_key, fixed_key(0x81));
    assert_eq!(pda.mint_key, fixed_key(0x82));
    assert_eq!(pda.destination_key, fixed_key(0x83));
    assert_eq!(pda.token_program_key, token_classic_program_id());
    assert_ne!(pda.authority_pda, pda.seed_authority);
}

#[test]
fn forcing_matrix_enumeration_is_closed() {
    let value = committed_cpi_token_manifest_value();
    let cases: Vec<&str> = value["forcingMatrix"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    assert_eq!(
        cases.len(),
        FORCING_MATRIX_CASES.len(),
        "forcingMatrix length must equal closed runtime acceptance groups"
    );
    assert_eq!(
        cases, FORCING_MATRIX_CASES,
        "forcingMatrix must be exact ordered runtime acceptance index"
    );
    // Stable group count for this lane: 20 runtime `#[test]` functions.
    assert_eq!(FORCING_MATRIX_CASES.len(), 20);
    // Spot-check required evidence groups are present exactly once.
    for required in [
        "one_mutation_source_account_negatives",
        "one_mutation_destination_account_negatives",
        "one_mutation_mint_account_negatives",
        "one_mutation_privilege_and_flag_negatives",
        "one_mutation_alias_negatives",
        "one_mutation_role_count_negatives",
        "token2022_wrong_key_substitution_independent",
        "token_program_account_non_executable_or_wrong_loader_owner",
        "one_mutation_pda_privilege_negatives",
        "transfer_checked_high_byte_amount_success",
        "destination_amount_overflow_inner_error_empty_return_snapshot",
        "inspect_reads_initialized_state",
    ] {
        assert_eq!(
            cases.iter().filter(|c| **c == required).count(),
            1,
            "forcingMatrix must contain exactly one {required}"
        );
    }
}

#[test]
fn build_script_is_strict_pin_gate() {
    let text = fs::read_to_string(repo_root().join("scripts/solana_cpi_token_build.sh")).unwrap();
    assert!(text.contains("vendoredSourceBuiltElf"));
    assert!(text.contains(TOKEN_CLASSIC_ELF_SHA256));
    assert!(text.contains("94960"));
    assert!(text.contains("program@v9.0.0"));
    assert!(text.contains(TOKEN_PEELED_COMMIT));
    assert!(text.contains("vendored source-built"));
}

// ---------------------------------------------------------------------------
// Artifact + success paths
// ---------------------------------------------------------------------------

#[test]
fn generated_assembly_and_elf_are_exact_preactivation() {
    let _ = read_cpi_token_assembly();
    assert!(read_cpi_token_caller_elf().starts_with(b"\x7fELF"));
    let token = read_vendored_token_elf();
    assert_eq!(token.len() as u64, 94960);
    let calls: Vec<String> = serde_json::from_slice(&stable_read(
        &cpi_token_out_dir().join("token_cpi.calls.json"),
        "calls",
    ))
    .unwrap();
    assert_eq!(
        calls.iter().map(String::as_str).collect::<Vec<_>>(),
        EXPECTED_FINAL_ELF_CALLS
    );
}

#[test]
fn transfer_checked_success_exact_balance_delta_and_state_order() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let amount = 100u64;
    let case = TransferCheckedCase::new(program_id, 10, 1000, 0, 6, true);
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, amount),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &case.state_key).data,
        token_cpi_state(true, 13)
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &case.source_key).data),
        case.source_amount - amount
    );
    assert_eq!(
        token_account_amount(
            &account_by_key(&result.resulting_accounts, &case.destination_key).data
        ),
        case.destination_amount + amount
    );
}

#[test]
fn transfer_checked_high_byte_amount_success() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    // 2^32 has non-zero LE byte[4] — proves full u64 amount reaches Token.
    let amount = 0x0000_0001_0000_0000u64;
    let case = TransferCheckedCase::new(program_id, 10, amount + 10, 0, 6, true);
    assert_ne!(amount.to_le_bytes()[4], 0);
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, amount),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &case.source_key).data),
        10
    );
    assert_eq!(
        token_account_amount(
            &account_by_key(&result.resulting_accounts, &case.destination_key).data
        ),
        amount
    );
}

#[test]
fn transfer_checked_pda_success_canonical_bump_and_balance_delta() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let amount = 55u64;
    let case = TransferCheckedPdaCase::new(program_id, 10, 42, 500, 10, 6, true);
    assert_ne!(case.bump, 0);
    let result = mollusk.process_and_validate_instruction(
        &case.instruction_canonical(
            program_id,
            CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID,
            amount,
        ),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    assert_eq!(
        account_by_key(&result.resulting_accounts, &case.state_key).data,
        token_cpi_state(true, 13)
    );
    assert_eq!(
        token_account_amount(&account_by_key(&result.resulting_accounts, &case.source_key).data),
        case.source_amount - amount
    );
    assert_eq!(
        token_account_amount(
            &account_by_key(&result.resulting_accounts, &case.destination_key).data
        ),
        case.destination_amount + amount
    );
}

#[test]
fn transfer_checked_then_overflow_full_snapshot_rollback() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let case = TransferCheckedCase::new(program_id, 10, 1000, 0, 6, true);
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(
            program_id,
            CPI_TOKEN_TRANSFER_CHECKED_THEN_OVERFLOW_HANDLER_ID,
            25,
        ),
        &case.accounts,
        ARITHMETIC_OVERFLOW,
    );
}

#[test]
fn transfer_checked_pda_then_overflow_full_snapshot_rollback() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let case = TransferCheckedPdaCase::new(program_id, 10, 7, 500, 0, 6, true);
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction_canonical(
            program_id,
            CPI_TOKEN_TRANSFER_CHECKED_PDA_THEN_OVERFLOW_HANDLER_ID,
            25,
        ),
        &case.accounts,
        ARITHMETIC_OVERFLOW,
    );
}

#[test]
fn inner_token_failure_precise_status_empty_return_data() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let case = TransferCheckedCase::new(program_id, 10, 10, 0, 6, true);
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 11),
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(TOKEN_ERR_INSUFFICIENT_FUNDS)),
            Check::return_data(&[]),
        ],
    );
}

#[test]
fn destination_amount_overflow_inner_error_empty_return_snapshot() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    // destination near u64::MAX; transfer 2 → Token Overflow if admitted to CPI.
    let case = TransferCheckedCase::new(program_id, 10, 10, u64::MAX - 1, 6, true);
    let ix = case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 2);
    assert_checks_preserve_exact_accounts(
        &mollusk,
        &ix,
        &case.accounts,
        &[
            Check::err(ProgramError::Custom(TOKEN_ERR_DESTINATION_AMOUNT_OVERFLOW)),
            Check::return_data(&[]),
        ],
    );
}

#[test]
fn inspect_reads_initialized_state() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let state_key = fixed_key(0xa0);
    let state = state_account(&program_id, token_cpi_state(true, 41));
    mollusk.process_and_validate_instruction(
        &Instruction::new_with_bytes(
            program_id,
            &cpi_token_simple_ix_data(CPI_TOKEN_INSPECT_HANDLER_ID, &[]),
            vec![AccountMeta::new_readonly(state_key, false)],
        ),
        &[(state_key, state)],
        &[Check::success(), Check::return_data(&41u64.to_le_bytes())],
    );
}

// ---------------------------------------------------------------------------
// One-mutation full-snapshot negatives (table-driven)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct MutationCase {
    name: &'static str,
    code: u32,
}

fn run_transfer_mutation(name: &str, code: u32, mutate: impl FnOnce(&mut TransferCheckedCase)) {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let mut case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);
    mutate(&mut case);
    let _ = name;
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1),
        &case.accounts,
        code,
    );
}

#[test]
fn one_mutation_source_account_negatives() {
    let cases: &[(MutationCase, fn(&mut TransferCheckedCase))] = &[
        (
            MutationCase {
                name: "source_wrong_solana_owner",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.owner = Pubkey::default();
            },
        ),
        (
            MutationCase {
                name: "source_len_164",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data.truncate(164);
            },
        ),
        (
            MutationCase {
                name: "source_len_166",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data.push(0);
            },
        ),
        (
            MutationCase {
                name: "source_state_uninitialized",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data = pack_classic_token_account(
                    &c.mint_key,
                    &c.authority_key,
                    c.source_amount,
                    TOKEN_ACCOUNT_STATE_UNINITIALIZED,
                    None,
                );
            },
        ),
        (
            MutationCase {
                name: "source_state_frozen",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data = pack_classic_token_account(
                    &c.mint_key,
                    &c.authority_key,
                    c.source_amount,
                    TOKEN_ACCOUNT_STATE_FROZEN,
                    None,
                );
            },
        ),
        (
            MutationCase {
                name: "source_mint_mismatch",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data = pack_classic_token_account(
                    &fixed_key(0xef),
                    &c.authority_key,
                    c.source_amount,
                    TOKEN_ACCOUNT_STATE_INITIALIZED,
                    None,
                );
            },
        ),
        (
            MutationCase {
                name: "source_owner_field_mismatch",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data = pack_classic_token_account(
                    &c.mint_key,
                    &fixed_key(0xed),
                    c.source_amount,
                    TOKEN_ACCOUNT_STATE_INITIALIZED,
                    None,
                );
            },
        ),
        (
            MutationCase {
                name: "source_delegate_coption_some",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[1].1.data = pack_classic_token_account(
                    &c.mint_key,
                    &c.authority_key,
                    c.source_amount,
                    TOKEN_ACCOUNT_STATE_INITIALIZED,
                    Some(&fixed_key(0xee)),
                );
            },
        ),
    ];
    for (spec, mutate) in cases {
        run_transfer_mutation(spec.name, spec.code, mutate);
    }
}

#[test]
fn one_mutation_destination_account_negatives() {
    let cases: &[(MutationCase, fn(&mut TransferCheckedCase))] = &[
        (
            MutationCase {
                name: "destination_wrong_solana_owner",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[3].1.owner = Pubkey::default();
            },
        ),
        (
            MutationCase {
                name: "destination_len_164",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[3].1.data.truncate(164);
            },
        ),
        (
            MutationCase {
                name: "destination_len_166",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[3].1.data.push(0);
            },
        ),
        (
            MutationCase {
                name: "destination_state_uninitialized",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[3].1.data = pack_classic_token_account(
                    &c.mint_key,
                    &c.dest_owner,
                    c.destination_amount,
                    TOKEN_ACCOUNT_STATE_UNINITIALIZED,
                    None,
                );
            },
        ),
        (
            MutationCase {
                name: "destination_state_frozen",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[3].1.data = pack_classic_token_account(
                    &c.mint_key,
                    &c.dest_owner,
                    c.destination_amount,
                    TOKEN_ACCOUNT_STATE_FROZEN,
                    None,
                );
            },
        ),
        (
            MutationCase {
                name: "destination_mint_mismatch",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[3].1.data = pack_classic_token_account(
                    &fixed_key(0xef),
                    &c.dest_owner,
                    c.destination_amount,
                    TOKEN_ACCOUNT_STATE_INITIALIZED,
                    None,
                );
            },
        ),
    ];
    for (spec, mutate) in cases {
        run_transfer_mutation(spec.name, spec.code, mutate);
    }
}

#[test]
fn one_mutation_mint_account_negatives() {
    let cases: &[(MutationCase, fn(&mut TransferCheckedCase))] = &[
        (
            MutationCase {
                name: "mint_wrong_solana_owner",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[2].1.owner = Pubkey::default();
            },
        ),
        (
            MutationCase {
                name: "mint_len_81",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[2].1.data.truncate(81);
            },
        ),
        (
            MutationCase {
                name: "mint_len_83",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[2].1.data.push(0);
            },
        ),
        (
            MutationCase {
                name: "mint_is_initialized_0",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.accounts[2].1.data = pack_classic_mint(
                    &c.mint_authority,
                    c.source_amount + c.destination_amount,
                    c.decimals,
                    0,
                );
            },
        ),
    ];
    for (spec, mutate) in cases {
        run_transfer_mutation(spec.name, spec.code, mutate);
    }

    // decimals mismatch via ix (mint stays 6)
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction_decimals(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1, 9),
        &case.accounts,
        CHECK_OR_UNKNOWN,
    );
}

#[test]
fn one_mutation_privilege_and_flag_negatives() {
    let cases: &[(MutationCase, fn(&mut TransferCheckedCase))] = &[
        (
            MutationCase {
                name: "source_missing_writable",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[1] = AccountMeta::new_readonly(c.source_key, false);
            },
        ),
        (
            MutationCase {
                name: "destination_missing_writable",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[3] = AccountMeta::new_readonly(c.destination_key, false);
            },
        ),
        (
            MutationCase {
                name: "mint_unexpected_writable",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[2] = AccountMeta::new(c.mint_key, false);
            },
        ),
        (
            MutationCase {
                name: "authority_missing_signer",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[4] = AccountMeta::new_readonly(c.authority_key, false);
            },
        ),
        (
            MutationCase {
                name: "authority_unexpected_writable",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[4] = AccountMeta::new(c.authority_key, true);
            },
        ),
        (
            MutationCase {
                name: "source_unexpected_signer",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[1] = AccountMeta::new(c.source_key, true);
            },
        ),
    ];
    for (spec, mutate) in cases {
        run_transfer_mutation(spec.name, spec.code, mutate);
    }
}

#[test]
fn one_mutation_alias_negatives() {
    let cases: &[(MutationCase, fn(&mut TransferCheckedCase))] = &[
        (
            MutationCase {
                name: "source_eq_destination",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[3] = AccountMeta::new(c.source_key, false);
                // Keep accounts table length; replace dest entry key to source
                // would create duplicate keys — instead point meta at source
                // while leaving dest account present under old key (count still 6).
                // Pairwise-distinct role keys are enforced on metas/keys used.
                c.destination_key = c.source_key;
            },
        ),
        (
            MutationCase {
                name: "source_eq_mint",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[2] = AccountMeta::new_readonly(c.source_key, false);
            },
        ),
        (
            MutationCase {
                name: "authority_eq_source",
                code: CHECK_OR_UNKNOWN,
            },
            |c| {
                c.metas[4] = AccountMeta::new_readonly(c.source_key, true);
            },
        ),
    ];
    for (spec, mutate) in cases {
        run_transfer_mutation(spec.name, spec.code, mutate);
    }
}

#[test]
fn one_mutation_role_count_negatives() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);

    // Missing middle role (drop mint meta + account)
    {
        let mut metas = case.metas.clone();
        let mut accounts = case.accounts.clone();
        metas.remove(2);
        accounts.remove(2);
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_token_transfer_checked_ix_data(CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1, 6),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Missing trailing role (drop token program)
    {
        let mut metas = case.metas.clone();
        let mut accounts = case.accounts.clone();
        metas.pop();
        accounts.pop();
        assert_custom_failure_snapshot(
            &mollusk,
            &Instruction::new_with_bytes(
                program_id,
                &cpi_token_transfer_checked_ix_data(CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1, 6),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Extra role
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
                &cpi_token_transfer_checked_ix_data(CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1, 6),
                metas,
            ),
            &accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn token2022_wrong_key_substitution_independent() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let mut case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);
    let wrong = token_2022_program_id();
    case.metas[5] = AccountMeta::new_readonly(wrong, false);
    let mut fake = create_program_account_loader_v3(&wrong);
    fake.executable = true;
    case.token_program_key = wrong;
    case.accounts[5] = (wrong, fake);
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1),
        &case.accounts,
        CHECK_OR_UNKNOWN,
    );
}

#[test]
fn token_program_account_non_executable_or_wrong_loader_owner() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    // Correct Tokenkeg key, non-executable
    {
        let mut case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);
        case.accounts[5].1.executable = false;
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // Correct Tokenkeg key, wrong owner (not Loader V3)
    {
        let mut case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);
        case.accounts[5].1.owner = Pubkey::default();
        case.accounts[5].1.executable = true;
        assert_ne!(case.accounts[5].1.owner, loader_v3_owner());
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn one_mutation_pda_privilege_negatives() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let base = TransferCheckedPdaCase::new(program_id, 10, 42, 500, 0, 6, true);

    // authorityPda unexpected outer signer
    {
        let mut case = base.clone();
        case.metas[4] = AccountMeta::new_readonly(case.authority_pda, true);
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction_canonical(program_id, CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // authorityPda unexpected writable
    {
        let mut case = base.clone();
        case.metas[4] = AccountMeta::new(case.authority_pda, false);
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction_canonical(program_id, CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // seedAuthority missing signer
    {
        let mut case = base.clone();
        case.metas[5] = AccountMeta::new_readonly(case.seed_authority, false);
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction_canonical(program_id, CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
    // seedAuthority unexpected writable
    {
        let mut case = base.clone();
        case.metas[5] = AccountMeta::new(case.seed_authority, true);
        assert_custom_failure_snapshot(
            &mollusk,
            &case.instruction_canonical(program_id, CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID, 1),
            &case.accounts,
            CHECK_OR_UNKNOWN,
        );
    }
}

#[test]
fn noncanonical_bump_fails_full_snapshot() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let mut case = TransferCheckedPdaCase::new(program_id, 10, 42, 500, 0, 6, true);
    let (nc_key, nc_bump) =
        find_noncanonical_pda_below(&program_id, &case.seed_authority, case.seed_tag, case.bump);
    case.metas[4] = AccountMeta::new_readonly(nc_key, false);
    case.accounts[4] = (nc_key, Account::new(BASE_LAMPORTS, 0, &Pubkey::default()));
    assert_custom_failure_snapshot(
        &mollusk,
        &Instruction::new_with_bytes(
            program_id,
            &cpi_token_transfer_checked_pda_ix_data(
                CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID,
                case.seed_tag,
                nc_bump,
                1,
                case.decimals,
            ),
            case.metas.clone(),
        ),
        &case.accounts,
        CHECK_OR_UNKNOWN,
    );
}

#[test]
fn wrong_authority_meta_key_fails_full_snapshot() {
    let (mollusk, program_id, _) = make_cpi_token_mollusk();
    let mut case = TransferCheckedCase::new(program_id, 10, 1000, 50, 6, true);
    let wrong = fixed_key(0xed);
    case.metas[4] = AccountMeta::new_readonly(wrong, true);
    case.accounts[4] = (wrong, Account::new(BASE_LAMPORTS, 0, &Pubkey::default()));
    assert_custom_failure_snapshot(
        &mollusk,
        &case.instruction(program_id, CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1),
        &case.accounts,
        CHECK_OR_UNKNOWN,
    );
}

// Silence handler id constants used as documentation of the surface.
#[test]
fn handler_ids_are_dense() {
    assert_eq!(CPI_TOKEN_INIT_HANDLER_ID, 0);
    assert_eq!(CPI_TOKEN_TRANSFER_CHECKED_HANDLER_ID, 1);
    assert_eq!(CPI_TOKEN_TRANSFER_CHECKED_PDA_HANDLER_ID, 2);
    assert_eq!(CPI_TOKEN_TRANSFER_CHECKED_THEN_OVERFLOW_HANDLER_ID, 3);
    assert_eq!(CPI_TOKEN_TRANSFER_CHECKED_PDA_THEN_OVERFLOW_HANDLER_ID, 4);
    assert_eq!(CPI_TOKEN_INSPECT_HANDLER_ID, 5);
}
