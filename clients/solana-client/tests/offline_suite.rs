//! Offline tests only: no network, no airdrop, no send.
//! Covers generic OutputSet path, profile dispatch, and TransferSol adapter pins.

use std::fs;
use std::path::{Path, PathBuf};

use proof_forge_solana_client::artifact::{
    read_regular_single_link_file, verify_solana_artifact, verify_solana_artifact_with_adapter,
    verify_transfer_sol_artifact, verify_transfer_sol_artifact_with_source_hash, CANONICAL_LEAVES,
    IR_DIGEST_DOMAIN, MAX_FILE_BYTES, PLAN_DIGEST_DOMAIN,
};
use proof_forge_solana_client::constants::{
    CATALOG_DIGEST_HEX, DEFAULT_EXPECTED_SOURCE_HASH, EXTENSION_DIGEST_HEX, EXTENSION_ID,
    EXTENSION_VERSION, PROFILE_CPI_ELF_V1, PROFILE_DIGEST_HEX, PROFILE_ELF_V1, PROFILE_PLAN_V1,
    SYSTEM_RUNTIME_NATIVE_BINDING, TRANSFER_SOL_PROGRAM_NAME,
};
use proof_forge_solana_client::output_set::{
    cpi_elf_expected_leaves, elf_expected_leaves, plan_expected_leaves,
};
use proof_forge_solana_client::program_adapter::ProgramAdapterId;
use proof_forge_solana_client::sha256_hex;
use proof_forge_solana_client::util::{
    domain_separated_sha256_hex, encode_string_framed, encode_u32le, encode_u64le,
    parse_json_no_dups,
};
use tempfile::tempdir;

const SEMANTIC_HASH: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const BUILD_ID: &str = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
const SUPPORT: &str = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";
const REGISTRY: &str = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
const SOURCE_IR: &str = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
const OTHER_SOURCE: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

fn write(path: &Path, bytes: &[u8]) {
    fs::write(path, bytes).unwrap();
}

fn plan_json(program_name: &str, handler_name: &str) -> String {
    serde_json::json!({
        "schema": "proof-forge.solana.cpi-plan.v1",
        "programName": program_name,
        "profileId": "solana-sbpf-cpi-elf-v1",
        "profileDigest": format!("sha256:{PROFILE_DIGEST_HEX}"),
        "calleeCatalogDigest": format!("sha256:{CATALOG_DIGEST_HEX}"),
        "extensionRequirement": {
            "id": EXTENSION_ID,
            "version": EXTENSION_VERSION,
            "digest": format!("sha256:{EXTENSION_DIGEST_HEX}"),
            "predicates": []
        },
        "accountRoles": [
            {
                "name": "transfer_payer",
                "roleId": 0,
                "keyPolicy": {"kind": "accountParameter", "callableId": 0, "paramOrdinal": 0},
                "constraint": {"data": {"kind": "notRead"}, "executable": "forbidden", "initialization": "any", "owner": {"kind": "any"}, "provisioning": "mustExist"}
            },
            {
                "name": "transfer_recipient",
                "roleId": 1,
                "keyPolicy": {"kind": "accountParameter", "callableId": 0, "paramOrdinal": 1},
                "constraint": {"data": {"kind": "notRead"}, "executable": "forbidden", "initialization": "any", "owner": {"kind": "any"}, "provisioning": "mustExist"}
            },
            {
                "name": "system_v1_program",
                "roleId": 2,
                "keyPolicy": {"kind": "fixedProgram", "packageId": "system-v1"},
                "constraint": {"data": {"kind": "catalogProgram"}, "executable": "required", "initialization": "catalogPackageAdmitted", "owner": {"kind": "catalogExecutionClass"}, "provisioning": "mustExist"}
            }
        ],
        "handlers": [{
            "handlerId": 0,
            "callableId": 0,
            "name": handler_name,
            "mode": "entry",
            "cpiSiteIds": [0],
            "accountUses": [
                {"roleId": 0, "position": 0, "outerSigner": true, "outerWritable": true, "directSignerContribution": false, "directWritableContribution": false},
                {"roleId": 1, "position": 1, "outerSigner": false, "outerWritable": true, "directSignerContribution": false, "directWritableContribution": false},
                {"roleId": 2, "position": 2, "outerSigner": false, "outerWritable": false, "directSignerContribution": false, "directWritableContribution": false}
            ]
        }],
        "cpiSites": [{
            "siteId": 0,
            "handlerId": 0,
            "packageId": "system-v1",
            "qn": "solana.system.transfer",
            "programRoleId": 2,
            "programKey": "0000000000000000000000000000000000000000000000000000000000000000",
            "accountInfoRoleIds": [0, 1, 2],
            "instructionCodec": {
                "length": 12,
                "segments": [
                    {"kind": "hex", "hex": "02000000"},
                    {"kind": "arg", "name": "lamports", "encoding": "uint64Le"}
                ]
            },
            "metas": [
                {"metaIndex": 0, "roleId": 0, "spec": {"cpiSigner": true, "cpiWritable": true, "outerSignerContribution": true, "outerWritableContribution": true}},
                {"metaIndex": 1, "roleId": 1, "spec": {"cpiSigner": false, "cpiWritable": true, "outerSignerContribution": false, "outerWritableContribution": true}}
            ],
            "args": [],
            "outerOnlyAccounts": [],
            "pda": {"kind": "none"},
            "preflight": [],
            "signerGroups": [],
            "failurePolicy": {},
            "returnDataPolicy": {},
            "sitePredicates": [],
            "anchor": {"callableId": 0, "blockId": 0, "instructionIndex": 0, "effectId": 0}
        }],
        "pdaRules": [],
        "stateSchemas": [],
        "computeAssumptions": {
            "implementationState": "product-exact-synchronous-call-active-v1"
        }
    })
    .to_string()
}

fn idl_json(program_name: &str, handler_name: &str, plan_digest: &str) -> String {
    serde_json::json!({
        "schema": "proof-forge.solana.cpi-idl.v1",
        "programName": program_name,
        "profileId": "solana-sbpf-cpi-elf-v1",
        "profileDigest": format!("sha256:{PROFILE_DIGEST_HEX}"),
        "catalogDigest": format!("sha256:{CATALOG_DIGEST_HEX}"),
        "planDigest": format!("sha256:{plan_digest}"),
        "instructions": [{
            "name": handler_name,
            "mode": "entry",
            "handlerId": 0,
            "cpiSiteIds": [0],
            "accounts": [
                {"name": "transfer_payer", "roleId": 0, "position": 0, "outerSigner": true, "outerWritable": true},
                {"name": "transfer_recipient", "roleId": 1, "position": 1, "outerSigner": false, "outerWritable": true},
                {"name": "system_v1_program", "roleId": 2, "position": 2, "outerSigner": false, "outerWritable": false}
            ]
        }],
        "cpiSites": [{
            "siteId": 0,
            "handlerId": 0,
            "packageId": "system-v1",
            "programIdBase58": "11111111111111111111111111111111",
            "qn": "solana.system.transfer"
        }],
        "pdaRules": [],
        "stateSchemas": []
    })
    .to_string()
}

fn bindings_json(plan_digest: &str, ir_digest: &str) -> String {
    serde_json::json!({
        "schema": "proof-forge.solana.cpi-bindings.v1",
        "profileId": "solana-sbpf-cpi-elf-v1",
        "profileDigest": format!("sha256:{PROFILE_DIGEST_HEX}"),
        "calleeCatalogDigest": format!("sha256:{CATALOG_DIGEST_HEX}"),
        "planDigest": format!("sha256:{plan_digest}"),
        "irDigest": format!("sha256:{ir_digest}"),
        "implementationState": "product-exact-synchronous-call-active-v1",
        "referencedPackages": [{
            "packageId": "system-v1",
            "programIdHex": "0000000000000000000000000000000000000000000000000000000000000000",
            "executionClass": "native-system",
            "admittedForMaterialization": true,
            "artifactBinding": SYSTEM_RUNTIME_NATIVE_BINDING
        }]
    })
    .to_string()
}

fn ir_text(plan_digest: &str, handler_name: &str) -> String {
    format!(
        "schema=proof-forge.solana.cpi-product-ir.v1\n\
sourcePlanDigest=sha256:{plan_digest}\n\
sourceIrDigest=sha256:{SOURCE_IR}\n\
profileId=solana-sbpf-cpi-elf-v1\n\
profileDigest=sha256:{PROFILE_DIGEST_HEX}\n\
catalogDigest=sha256:{CATALOG_DIGEST_HEX}\n\
maxOuterRoles=16\n\
maxFrameBytes=4096\n\
handler:0:0:{handler_name}:entry:roles3:probe16:temps1:entry[]:body[loadParamU64:0@8;invokeEscrow:0:transfer:solana.system.transfer:system-v1:prog2:len12;returnU64:0]\n"
    )
}

fn asm_text() -> &'static str {
    "; PRODUCT ARTIFACT\n; isProductArtifact=true\n.text\ncall sol_invoke_signed_c\ncall sol_set_return_data\n"
}

#[allow(clippy::too_many_arguments)]
fn recompute_output_set(
    schema: &str,
    target: &str,
    profile: &str,
    name: &str,
    files: &[(String, String, u64, String)],
    source: &str,
    semantic: &str,
    registry: &str,
    support: &str,
    build: &str,
    plan: &str,
    deployable: bool,
    evidence_sha: &str,
) -> String {
    let mut payload = Vec::new();
    payload.extend_from_slice(&encode_string_framed(schema));
    payload.extend_from_slice(&encode_string_framed(target));
    payload.extend_from_slice(&encode_string_framed(profile));
    payload.extend_from_slice(&encode_string_framed(name));
    payload.extend_from_slice(&encode_u32le(files.len() as u32));
    for (role, path, size, hash) in files {
        payload.extend_from_slice(&encode_string_framed(role));
        payload.extend_from_slice(&encode_string_framed(path));
        payload.extend_from_slice(&encode_u64le(*size));
        payload.extend_from_slice(&encode_string_framed(&format!("sha256:{hash}")));
    }
    for bare in [source, semantic, registry, support, build, plan] {
        payload.extend_from_slice(&encode_string_framed(&format!("sha256:{bare}")));
    }
    payload.extend_from_slice(&encode_string_framed(if deployable {
        "true"
    } else {
        "false"
    }));
    payload.extend_from_slice(&encode_string_framed(&format!("sha256:{evidence_sha}")));
    domain_separated_sha256_hex("pf.output-set.engineering.v1", &payload)
}

/// Build a minimal exact CPI OutputSet under `dir` with real domain digests.
fn build_cpi_artifact_tree(
    dir: &Path,
    program_name: &str,
    handler_name: &str,
    source_hash: &str,
) -> PathBuf {
    let plan = plan_json(program_name, handler_name);
    let plan_bytes = plan.as_bytes();
    let plan_digest = domain_separated_sha256_hex(PLAN_DIGEST_DOMAIN, plan_bytes);

    let ir = ir_text(&plan_digest, handler_name);
    let ir_bytes = ir.as_bytes();
    let ir_digest = domain_separated_sha256_hex(IR_DIGEST_DOMAIN, ir_bytes);

    let idl = idl_json(program_name, handler_name, &plan_digest);
    let bindings = bindings_json(&plan_digest, &ir_digest);
    let asm = asm_text();
    let so: Vec<u8> = {
        let mut v = b"\x7fELF".to_vec();
        v.extend_from_slice(b" minimal offline test so payload bytes!!!!");
        v
    };

    let leaves = cpi_elf_expected_leaves(program_name);
    let leaf_data: Vec<(String, Vec<u8>, String)> = vec![
        (
            leaves[0].0.clone(),
            bindings.as_bytes().to_vec(),
            leaves[0].1.clone(),
        ),
        (leaves[1].0.clone(), ir_bytes.to_vec(), leaves[1].1.clone()),
        (
            leaves[2].0.clone(),
            plan_bytes.to_vec(),
            leaves[2].1.clone(),
        ),
        (
            leaves[3].0.clone(),
            idl.as_bytes().to_vec(),
            leaves[3].1.clone(),
        ),
        (
            leaves[4].0.clone(),
            asm.as_bytes().to_vec(),
            leaves[4].1.clone(),
        ),
        (leaves[5].0.clone(), so, leaves[5].1.clone()),
    ];

    let mut files_meta = Vec::new();
    for (name, bytes, role) in &leaf_data {
        write(&dir.join(name), bytes);
        let hash = sha256_hex(bytes);
        files_meta.push((role.clone(), name.clone(), bytes.len() as u64, hash));
    }

    let evidence_note = format!(
        "solana-sbpf-cpi-elf-v1 profile=solana-sbpf-cpi-elf-v1 profileDigest=sha256:{PROFILE_DIGEST_HEX} catalogDigest=sha256:{CATALOG_DIGEST_HEX} planDigest=sha256:{plan_digest} irDigest=sha256:{ir_digest} completed successfully"
    );
    let evidence_body = format!(
        "{{\n  \"target\": \"solana\",\n  \"sourceHash\": \"{source_hash}\",\n  \"semanticHash\": \"{SEMANTIC_HASH}\",\n  \"deployable\": true,\n  \"note\": \"{evidence_note}\"\n}}\n"
    );
    write(&dir.join("evidence.json"), evidence_body.as_bytes());
    let evidence_sha = sha256_hex(evidence_body.as_bytes());

    let osd = recompute_output_set(
        "proof-forge.output.v1",
        "solana",
        PROFILE_CPI_ELF_V1,
        program_name,
        &files_meta,
        source_hash,
        SEMANTIC_HASH,
        REGISTRY,
        SUPPORT,
        BUILD_ID,
        &plan_digest,
        true,
        &evidence_sha,
    );

    let files_json: Vec<_> = files_meta
        .iter()
        .map(|(role, path, size, hash)| {
            serde_json::json!({
                "role": role,
                "path": path,
                "size": size,
                "contentSha256": hash,
            })
        })
        .collect();

    let manifest = serde_json::json!({
        "schemaVersion": "proof-forge.output.v1",
        "target": "solana",
        "codegenProfile": PROFILE_CPI_ELF_V1,
        "artifactProgramName": program_name,
        "sourceHash": source_hash,
        "semanticHash": SEMANTIC_HASH,
        "buildIdentityDigest": BUILD_ID,
        "planDigest": plan_digest,
        "supportClaimDigest": SUPPORT,
        "engineeringRegistryRootDigest": REGISTRY,
        "outputSetDigest": osd,
        "evidenceSha256": evidence_sha,
        "deployable": true,
        "files": files_json
    });
    write(
        &dir.join("manifest.json"),
        serde_json::to_string_pretty(&manifest).unwrap().as_bytes(),
    );
    dir.to_path_buf()
}

fn build_minimal_artifact_tree(dir: &Path, source_hash: &str) -> PathBuf {
    build_cpi_artifact_tree(dir, TRANSFER_SOL_PROGRAM_NAME, "transfer", source_hash)
}

fn build_plan_profile_tree(dir: &Path, program_name: &str) -> PathBuf {
    let leaves = plan_expected_leaves(program_name);
    let idl = serde_json::json!({
        "version": "proof-forge-solana-idl/v1",
        "name": program_name,
        "codegenProfile": PROFILE_PLAN_V1,
        "deployable": false,
        "instructions": [{"name": "view", "mode": "view"}]
    })
    .to_string();
    let plan = format!(
        "; PROOF-FORGE-SBPF-PLAN v1\n\
; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present\n\
; codegen-profile: solana-sbpf-plan-v1\n\
; program: {program_name}\n"
    );
    let leaf_data = vec![
        (
            leaves[0].0.clone(),
            idl.as_bytes().to_vec(),
            leaves[0].1.clone(),
        ),
        (
            leaves[1].0.clone(),
            plan.as_bytes().to_vec(),
            leaves[1].1.clone(),
        ),
    ];
    write_simple_tree(
        dir,
        program_name,
        PROFILE_PLAN_V1,
        false,
        &leaf_data,
        "no pinned/approved sBPF assembler is configured; typed plan and IDL artifacts are non-executable",
        "0".repeat(64),
    )
}

fn build_elf_profile_tree(dir: &Path, program_name: &str) -> PathBuf {
    let leaves = elf_expected_leaves(program_name);
    let idl = serde_json::json!({
        "version": "proof-forge-solana-idl/v1",
        "name": program_name,
        "codegenProfile": PROFILE_ELF_V1,
        "deployable": true,
        "instructions": [{"name": "entry", "mode": "entry"}]
    })
    .to_string();
    let plan = format!(
        "; PROOF-FORGE-SBPF-PLAN v1\n\
; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present\n\
; codegen-profile: solana-sbpf-plan-v1\n\
; program: {program_name}\n"
    );
    let asm = "; PROOF-FORGE-SBPF-ASM v1 (test)\n.text\n";
    let so = {
        let mut v = b"\x7fELF".to_vec();
        v.extend_from_slice(b" elf profile test so");
        v
    };
    let leaf_data = vec![
        (
            leaves[0].0.clone(),
            idl.as_bytes().to_vec(),
            leaves[0].1.clone(),
        ),
        (
            leaves[1].0.clone(),
            asm.as_bytes().to_vec(),
            leaves[1].1.clone(),
        ),
        (
            leaves[2].0.clone(),
            plan.as_bytes().to_vec(),
            leaves[2].1.clone(),
        ),
        (leaves[3].0.clone(), so, leaves[3].1.clone()),
    ];
    write_simple_tree(
        dir,
        program_name,
        PROFILE_ELF_V1,
        true,
        &leaf_data,
        "sbpf 0.2.2 completed successfully",
        "1".repeat(64),
    )
}

fn write_simple_tree(
    dir: &Path,
    program_name: &str,
    profile: &str,
    deployable: bool,
    leaf_data: &[(String, Vec<u8>, String)],
    evidence_note: &str,
    plan_digest: String,
) -> PathBuf {
    let mut files_meta = Vec::new();
    for (name, bytes, role) in leaf_data {
        write(&dir.join(name), bytes);
        files_meta.push((
            role.clone(),
            name.clone(),
            bytes.len() as u64,
            sha256_hex(bytes),
        ));
    }
    let evidence_body = format!(
        "{{\n  \"target\": \"solana\",\n  \"sourceHash\": \"{OTHER_SOURCE}\",\n  \"semanticHash\": \"{SEMANTIC_HASH}\",\n  \"deployable\": {deployable},\n  \"note\": \"{evidence_note}\"\n}}\n"
    );
    write(&dir.join("evidence.json"), evidence_body.as_bytes());
    let evidence_sha = sha256_hex(evidence_body.as_bytes());
    let osd = recompute_output_set(
        "proof-forge.output.v1",
        "solana",
        profile,
        program_name,
        &files_meta,
        OTHER_SOURCE,
        SEMANTIC_HASH,
        REGISTRY,
        SUPPORT,
        BUILD_ID,
        &plan_digest,
        deployable,
        &evidence_sha,
    );
    let files_json: Vec<_> = files_meta
        .iter()
        .map(|(role, path, size, hash)| {
            serde_json::json!({
                "role": role,
                "path": path,
                "size": size,
                "contentSha256": hash,
            })
        })
        .collect();
    let manifest = serde_json::json!({
        "schemaVersion": "proof-forge.output.v1",
        "target": "solana",
        "codegenProfile": profile,
        "artifactProgramName": program_name,
        "sourceHash": OTHER_SOURCE,
        "semanticHash": SEMANTIC_HASH,
        "buildIdentityDigest": BUILD_ID,
        "planDigest": plan_digest,
        "supportClaimDigest": SUPPORT,
        "engineeringRegistryRootDigest": REGISTRY,
        "outputSetDigest": osd,
        "evidenceSha256": evidence_sha,
        "deployable": deployable,
        "files": files_json
    });
    write(
        &dir.join("manifest.json"),
        serde_json::to_string_pretty(&manifest).unwrap().as_bytes(),
    );
    dir.to_path_buf()
}

// ---------------------------------------------------------------------------
// Generic path + profile dispatch
// ---------------------------------------------------------------------------

#[test]
fn generic_path_accepts_non_transfer_sol_cpi_output_set() {
    let dir = tempdir().unwrap();
    build_cpi_artifact_tree(dir.path(), "DemoCounter", "increment", OTHER_SOURCE);
    let v = verify_solana_artifact(dir.path()).unwrap();
    assert_eq!(v.manifest.artifact_program_name, "DemoCounter");
    assert_eq!(v.profile_id, PROFILE_CPI_ELF_V1);
    assert!(v.program_adapter.is_none());
    assert!(v.trust_anchor.contains("self-consistency"));
    assert!(v.verification_scope.contains("output-set-self-consistency"));
    assert_eq!(v.profile_digest_hex.as_deref(), Some(PROFILE_DIGEST_HEX));
}

#[test]
fn transfer_sol_adapter_rejects_non_transfer_program() {
    let dir = tempdir().unwrap();
    build_cpi_artifact_tree(dir.path(), "DemoCounter", "increment", OTHER_SOURCE);
    let err =
        verify_solana_artifact_with_adapter(dir.path(), Some(ProgramAdapterId::TransferSolV1))
            .unwrap_err();
    assert!(
        err.to_string().contains("artifactProgramName=TransferSol")
            || err.to_string().contains("transfer-sol-v1"),
        "{err}"
    );
}

#[test]
fn unknown_profile_fail_closed() {
    let dir = tempdir().unwrap();
    build_plan_profile_tree(dir.path(), "DemoPlan");
    // Tamper profile after seal to an unknown id and recompute OSD only.
    let mut m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    m["codegenProfile"] = serde_json::json!("solana-sbpf-unknown-v9");
    let files_meta: Vec<(String, String, u64, String)> = m["files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| {
            (
                f["role"].as_str().unwrap().to_string(),
                f["path"].as_str().unwrap().to_string(),
                f["size"].as_u64().unwrap(),
                f["contentSha256"].as_str().unwrap().to_string(),
            )
        })
        .collect();
    let osd = recompute_output_set(
        "proof-forge.output.v1",
        "solana",
        "solana-sbpf-unknown-v9",
        "DemoPlan",
        &files_meta,
        OTHER_SOURCE,
        SEMANTIC_HASH,
        REGISTRY,
        SUPPORT,
        BUILD_ID,
        m["planDigest"].as_str().unwrap(),
        false,
        m["evidenceSha256"].as_str().unwrap(),
    );
    m["outputSetDigest"] = serde_json::json!(osd);
    write(
        &dir.path().join("manifest.json"),
        serde_json::to_string_pretty(&m).unwrap().as_bytes(),
    );
    let err = verify_solana_artifact(dir.path()).unwrap_err();
    assert!(
        err.to_string().contains("unknown Solana codegenProfile"),
        "{err}"
    );
}

#[test]
fn plan_profile_leaf_shape_accepted() {
    let dir = tempdir().unwrap();
    build_plan_profile_tree(dir.path(), "DemoPlan");
    let v = verify_solana_artifact(dir.path()).unwrap();
    assert_eq!(v.profile_id, PROFILE_PLAN_V1);
    assert!(!v.manifest.deployable);
    assert!(v.so_path.is_none());
}

#[test]
fn elf_profile_leaf_shape_accepted() {
    let dir = tempdir().unwrap();
    build_elf_profile_tree(dir.path(), "DemoElf");
    let v = verify_solana_artifact(dir.path()).unwrap();
    assert_eq!(v.profile_id, PROFILE_ELF_V1);
    assert!(v.manifest.deployable);
    assert!(v.so_bytes.as_ref().unwrap().starts_with(b"\x7fELF"));
}

#[test]
fn generic_output_set_rejects_leaf_path_over_240_utf8_bytes() {
    let dir = tempdir().unwrap();
    let long_name = "a".repeat(232);
    build_plan_profile_tree(dir.path(), &long_name);
    let err = verify_solana_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("at most 240 UTF-8 bytes"), "{err}");
}

#[test]
fn generic_output_set_rejects_control_character_leaf_path() {
    let dir = tempdir().unwrap();
    build_plan_profile_tree(dir.path(), "Bad\nName");
    let err = verify_solana_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("safe basename"), "{err}");
}

#[test]
fn cpi_profile_leaf_shape_for_dynamic_program_name() {
    let dir = tempdir().unwrap();
    build_cpi_artifact_tree(dir.path(), "AlphaBeta", "route", OTHER_SOURCE);
    let v = verify_solana_artifact(dir.path()).unwrap();
    assert_eq!(v.profile_id, PROFILE_CPI_ELF_V1);
    assert!(v.so_path.as_ref().unwrap().ends_with("AlphaBeta.so"));
}

// ---------------------------------------------------------------------------
// TransferSol adapter regressions (20 security/digest/ABI cases)
// ---------------------------------------------------------------------------

#[test]
fn verify_artifacts_accepts_minimal_exact_tree() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let v = verify_transfer_sol_artifact(dir.path()).unwrap();
    assert_eq!(v.manifest.artifact_program_name, "TransferSol");
    assert!(v.manifest.deployable);
    assert_eq!(v.profile_digest_hex.as_deref(), Some(PROFILE_DIGEST_HEX));
    assert_eq!(&v.so_bytes.as_ref().unwrap()[0..4], b"\x7fELF");
    assert_eq!(v.program_adapter.as_deref(), Some("transfer-sol-v1"));
    assert!(v.verification_scope.contains("program-adapter-pins"));
}

#[test]
fn verify_rejects_source_hash_mismatch() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err =
        verify_transfer_sol_artifact_with_source_hash(dir.path(), &"ff".repeat(32)).unwrap_err();
    assert!(err.to_string().contains("sourceHash trust-anchor mismatch"));
}

#[test]
fn verify_rejects_tampered_leaf_hash() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    write(&dir.path().join("TransferSol.so"), b"\x7fELFMUTATED");
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(
        err.to_string().contains("contentSha256") || err.to_string().contains("size mismatch"),
        "{err}"
    );
}

#[test]
fn verify_rejects_extra_file() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    write(&dir.path().join("extra.txt"), b"nope");
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("exact disk closure"), "{err}");
}

#[test]
#[cfg(unix)]
fn verify_rejects_symlink_leaf() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let so = dir.path().join("TransferSol.so");
    let backup = dir.path().join("TransferSol.so.bak");
    fs::rename(&so, &backup).unwrap();
    std::os::unix::fs::symlink(&backup, &so).unwrap();
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("symlink") || msg.contains("exact disk closure"),
        "{msg}"
    );
}

#[test]
#[cfg(unix)]
fn verify_rejects_root_symlink() {
    let real = tempdir().unwrap();
    build_minimal_artifact_tree(real.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let parent = tempdir().unwrap();
    let link = parent.path().join("linked-out");
    std::os::unix::fs::symlink(real.path(), &link).unwrap();
    let err = verify_transfer_sol_artifact(&link).unwrap_err();
    assert!(err.to_string().contains("symlink"), "{err}");
}

#[test]
fn verify_rejects_output_set_digest_tamper() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let mut m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    m["outputSetDigest"] = serde_json::json!("0".repeat(64));
    write(
        &dir.path().join("manifest.json"),
        serde_json::to_string_pretty(&m).unwrap().as_bytes(),
    );
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("outputSetDigest"), "{err}");
}

#[test]
fn verify_rejects_plan_domain_digest_tamper() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let mut m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    m["planDigest"] = serde_json::json!("1".repeat(64));
    write(
        &dir.path().join("manifest.json"),
        serde_json::to_string_pretty(&m).unwrap().as_bytes(),
    );
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    // planDigest participates in outputSetDigest; either surface is fail-closed.
    assert!(
        err.to_string().contains("planDigest")
            || err.to_string().contains("evidence")
            || err.to_string().contains("outputSetDigest"),
        "{err}"
    );
}

#[test]
fn verify_rejects_ir_domain_digest_mismatch() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let mut b: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(dir.path().join("TransferSol.cpi-bindings.json")).unwrap(),
    )
    .unwrap();
    b["irDigest"] = serde_json::json!(format!("sha256:{}", "2".repeat(64)));
    let bytes = serde_json::to_vec_pretty(&b).unwrap();
    write(&dir.path().join("TransferSol.cpi-bindings.json"), &bytes);
    reseal_hashes_only(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("irDigest"), "{err}");
}

#[test]
fn verify_rejects_evidence_note_preactivation() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    let plan_d = m["planDigest"].as_str().unwrap();
    let b: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(dir.path().join("TransferSol.cpi-bindings.json")).unwrap(),
    )
    .unwrap();
    let ir_d = b["irDigest"]
        .as_str()
        .unwrap()
        .strip_prefix("sha256:")
        .unwrap();
    let note = format!(
        "profile=solana-sbpf-cpi-elf-v1 profileDigest=sha256:{PROFILE_DIGEST_HEX} catalogDigest=sha256:{CATALOG_DIGEST_HEX} planDigest=sha256:{plan_d} irDigest=sha256:{ir_d} preactivation"
    );
    let evidence_body = format!(
        "{{\n  \"target\": \"solana\",\n  \"sourceHash\": \"{DEFAULT_EXPECTED_SOURCE_HASH}\",\n  \"semanticHash\": \"{SEMANTIC_HASH}\",\n  \"deployable\": true,\n  \"note\": \"{note}\"\n}}\n"
    );
    write(&dir.path().join("evidence.json"), evidence_body.as_bytes());
    reseal_hashes_only(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("preactivation"), "{err}");
}

#[test]
fn verify_rejects_evidence_ir_digest_mismatch() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    let plan_d = m["planDigest"].as_str().unwrap();
    let note = format!(
        "profile=solana-sbpf-cpi-elf-v1 profileDigest=sha256:{PROFILE_DIGEST_HEX} catalogDigest=sha256:{CATALOG_DIGEST_HEX} planDigest=sha256:{plan_d} irDigest=sha256:{} completed successfully",
        "0".repeat(64)
    );
    let evidence_body = format!(
        "{{\n  \"target\": \"solana\",\n  \"sourceHash\": \"{DEFAULT_EXPECTED_SOURCE_HASH}\",\n  \"semanticHash\": \"{SEMANTIC_HASH}\",\n  \"deployable\": true,\n  \"note\": \"{note}\"\n}}\n"
    );
    write(&dir.path().join("evidence.json"), evidence_body.as_bytes());
    reseal_hashes_only(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("exact irDigest"), "{err}");
}

#[test]
fn verify_rejects_wrong_manifest_role_order() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let mut manifest: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    manifest["files"][0]["role"] = serde_json::json!("finalized-extra");
    write(
        &dir.path().join("manifest.json"),
        serde_json::to_vec_pretty(&manifest).unwrap().as_slice(),
    );
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(
        err.to_string().contains("files[0]")
            || err.to_string().contains("canonical role/path order")
            || err.to_string().contains("must be role="),
        "{err}"
    );
}

#[test]
fn verify_rejects_assembly_without_exact_product_markers() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    write(
        &dir.path().join("TransferSol.s"),
        b".text\ncall invoke\ncall set_return_data\n",
    );
    reseal_hashes_only(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("exact product marker"), "{err}");
}

#[test]
fn verify_rejects_wrong_package_binding() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let mut b: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(dir.path().join("TransferSol.cpi-bindings.json")).unwrap(),
    )
    .unwrap();
    b["referencedPackages"][0]["artifactBinding"] = serde_json::json!("runtimeNative:deadbeef");
    write(
        &dir.path().join("TransferSol.cpi-bindings.json"),
        serde_json::to_vec_pretty(&b).unwrap().as_slice(),
    );
    reseal_hashes_only(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(
        err.to_string().contains("artifactBinding") || err.to_string().contains("mismatch"),
        "{err}"
    );
}

#[test]
fn verify_rejects_non_elf() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    write(&dir.path().join("TransferSol.so"), b"NOT_ELF_BYTES!!!!!!");
    reseal_hashes_only(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("7fELF"), "{err}");
}

#[test]
fn verify_rejects_uppercase_digest() {
    let dir = tempdir().unwrap();
    build_minimal_artifact_tree(dir.path(), DEFAULT_EXPECTED_SOURCE_HASH);
    let mut m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.path().join("manifest.json")).unwrap())
            .unwrap();
    let upper = m["sourceHash"].as_str().unwrap().to_ascii_uppercase();
    m["sourceHash"] = serde_json::json!(upper);
    write(
        &dir.path().join("manifest.json"),
        serde_json::to_string_pretty(&m).unwrap().as_bytes(),
    );
    let err = verify_transfer_sol_artifact(dir.path()).unwrap_err();
    assert!(err.to_string().contains("lowercase"), "{err}");
}

/// Reseal leaf content hashes + evidenceSha256 + outputSetDigest after leaf mutation.
fn reseal_hashes_only(dir: &Path, source_hash: &str) {
    let mut files_meta = Vec::new();
    for (path, role) in &CANONICAL_LEAVES {
        let b = fs::read(dir.join(path)).unwrap();
        files_meta.push((
            (*role).to_string(),
            (*path).to_string(),
            b.len() as u64,
            sha256_hex(&b),
        ));
    }
    let evidence = fs::read(dir.join("evidence.json")).unwrap();
    let evidence_sha = sha256_hex(&evidence);
    let mut m: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.join("manifest.json")).unwrap()).unwrap();
    let plan_d = m["planDigest"].as_str().unwrap().to_string();
    let osd = recompute_output_set(
        "proof-forge.output.v1",
        "solana",
        "solana-sbpf-cpi-elf-v1",
        "TransferSol",
        &files_meta,
        source_hash,
        SEMANTIC_HASH,
        REGISTRY,
        SUPPORT,
        BUILD_ID,
        &plan_d,
        true,
        &evidence_sha,
    );
    let files_json: Vec<_> = files_meta
        .iter()
        .map(|(role, path, size, hash)| {
            serde_json::json!({
                "role": role,
                "path": path,
                "size": size,
                "contentSha256": hash,
            })
        })
        .collect();
    m["files"] = serde_json::json!(files_json);
    m["evidenceSha256"] = serde_json::json!(evidence_sha);
    m["outputSetDigest"] = serde_json::json!(osd);
    write(
        &dir.join("manifest.json"),
        serde_json::to_string_pretty(&m).unwrap().as_bytes(),
    );
}

// ---------------------------------------------------------------------------
// Offline parser / bounded-file utility regression
// ---------------------------------------------------------------------------

#[test]
fn duplicate_json_keys_rejected() {
    assert!(parse_json_no_dups(br#"{"a":1,"a":2}"#).is_err());
}

#[test]
fn read_regular_file_ok_on_temp() {
    let dir = tempdir().unwrap();
    let p = dir.path().join("f.bin");
    write(&p, b"hi");
    let b = read_regular_single_link_file(&p).unwrap();
    assert_eq!(b, b"hi");
}

#[test]
fn read_regular_file_rejects_sparse_oversize_before_read() {
    let dir = tempdir().unwrap();
    let p = dir.path().join("oversize.bin");
    let file = fs::File::create(&p).unwrap();
    file.set_len(MAX_FILE_BYTES + 1).unwrap();
    let err = read_regular_single_link_file(&p).unwrap_err();
    assert!(err.to_string().contains("64MiB cap"), "{err}");
}

#[test]
#[cfg(unix)]
fn read_regular_file_rejects_direct_symlink_open() {
    let dir = tempdir().unwrap();
    let target = dir.path().join("target.bin");
    let link = dir.path().join("link.bin");
    write(&target, b"secret-shaped-content");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    let err = read_regular_single_link_file(&link).unwrap_err();
    assert!(err.to_string().contains("symlink"), "{err}");
}
