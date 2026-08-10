//! Closed Solana profile dispatch and adapters.
//!
//! Unknown `codegenProfile` values fail closed (no silent fallback).

use std::collections::BTreeMap;

use serde_json::Value;

use crate::constants::{
    BODY_ONLY_EXTENSION_DIGEST_HEX, BODY_ONLY_EXTENSION_ID, BODY_ONLY_EXTENSION_VERSION,
    CPI_BINDINGS_SCHEMA, CPI_CATALOG_DIGEST_HEX, CPI_EXTENSION_DIGEST_HEX, CPI_EXTENSION_ID,
    CPI_EXTENSION_VERSION, CPI_IDL_SCHEMA, CPI_IR_SCHEMA_LINE, CPI_PLAN_SCHEMA,
    CPI_PROFILE_DIGEST_HEX, FULL_BODY_HYBRID_IR_SCHEMA, PROFILE_CPI_ELF_V1, PROFILE_ELF_V1,
    PROFILE_PLAN_V1, SYSTEM_PACKAGE_ID, SYSTEM_PROGRAM_ID_HEX, SYSTEM_RUNTIME_NATIVE_BINDING,
};
use crate::error::ClientError;
use crate::output_set::{
    cpi_elf_expected_leaves, elf_expected_leaves, leaf_bytes_by_name, plan_expected_leaves,
    require_exact_leaf_shape, LoadedOutputSet, FULL_BODY_HYBRID_IR_DIGEST_DOMAIN, IR_DIGEST_DOMAIN,
    PLAN_DIGEST_DOMAIN,
};
use crate::util::{
    domain_separated_sha256_hex, parse_json_no_dups, require_digest_wire_eq, require_sha256_wire,
};

/// Result of profile-level joins (generic; not TransferSol-specific).
#[derive(Debug, Clone)]
pub struct ProfileJoinResult {
    pub profile_id: String,
    pub plan_digest_hex: String,
    pub profile_digest_hex: Option<String>,
    pub catalog_digest_hex: Option<String>,
    pub ir_digest_hex: Option<String>,
    pub so_path: Option<String>,
    pub so_bytes: Option<Vec<u8>>,
    pub so_sha256_hex: Option<String>,
}

/// Dispatch on closed current profile IDs; unknown → fail closed.
pub fn dispatch_profile(loaded: &LoadedOutputSet) -> Result<ProfileJoinResult, ClientError> {
    match loaded.manifest.codegen_profile.as_str() {
        PROFILE_PLAN_V1 => verify_plan_profile(loaded),
        PROFILE_ELF_V1 => verify_elf_profile(loaded),
        PROFILE_CPI_ELF_V1 => verify_cpi_elf_profile(loaded),
        other => Err(ClientError::Artifact(format!(
            "unknown Solana codegenProfile '{other}' (closed set: {PROFILE_PLAN_V1}, {PROFILE_ELF_V1}, {PROFILE_CPI_ELF_V1})"
        ))),
    }
}

fn verify_plan_profile(loaded: &LoadedOutputSet) -> Result<ProfileJoinResult, ClientError> {
    let name = &loaded.manifest.artifact_program_name;
    let expected = plan_expected_leaves(name);
    require_exact_leaf_shape(loaded, &expected)?;
    if loaded.manifest.deployable {
        return Err(ClientError::Artifact(
            "solana-sbpf-plan-v1 deployable must be false".into(),
        ));
    }
    let plan_path = format!("{name}.sbpf-plan");
    let idl_path = format!("{name}.idl.json");
    let plan = leaf_bytes_by_name(loaded, &plan_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing plan leaf {plan_path}")))?;
    let idl = leaf_bytes_by_name(loaded, &idl_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing idl leaf {idl_path}")))?;
    let plan_text = String::from_utf8(plan.to_vec())
        .map_err(|e| ClientError::AbiJoin(format!("legacy plan must be UTF-8: {e}")))?;
    validate_legacy_plan(&plan_text, name)?;
    let idl_v = parse_json_no_dups(idl)?;
    validate_legacy_idl(&idl_v, name, PROFILE_PLAN_V1, false)?;
    Ok(ProfileJoinResult {
        profile_id: PROFILE_PLAN_V1.into(),
        plan_digest_hex: loaded.manifest.plan_digest.clone(),
        profile_digest_hex: None,
        catalog_digest_hex: None,
        ir_digest_hex: None,
        so_path: None,
        so_bytes: None,
        so_sha256_hex: None,
    })
}

fn verify_elf_profile(loaded: &LoadedOutputSet) -> Result<ProfileJoinResult, ClientError> {
    let name = &loaded.manifest.artifact_program_name;
    let expected = elf_expected_leaves(name);
    require_exact_leaf_shape(loaded, &expected)?;
    if !loaded.manifest.deployable {
        return Err(ClientError::Artifact(
            "solana-sbpf-elf-v1 deployable must be true".into(),
        ));
    }
    let plan_path = format!("{name}.sbpf-plan");
    let idl_path = format!("{name}.idl.json");
    let asm_path = format!("{name}.s");
    let so_path = format!("{name}.so");
    let plan = leaf_bytes_by_name(loaded, &plan_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing plan leaf {plan_path}")))?;
    let idl = leaf_bytes_by_name(loaded, &idl_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing idl leaf {idl_path}")))?;
    let asm = leaf_bytes_by_name(loaded, &asm_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing assembly leaf {asm_path}")))?;
    let so = leaf_bytes_by_name(loaded, &so_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing ELF leaf {so_path}")))?;
    let plan_text = String::from_utf8(plan.to_vec())
        .map_err(|e| ClientError::AbiJoin(format!("legacy plan must be UTF-8: {e}")))?;
    validate_legacy_plan(&plan_text, name)?;
    let asm_text = String::from_utf8(asm.to_vec())
        .map_err(|e| ClientError::AbiJoin(format!("legacy assembly must be UTF-8: {e}")))?;
    validate_legacy_assembly(&asm_text)?;
    let idl_v = parse_json_no_dups(idl)?;
    validate_legacy_idl(&idl_v, name, PROFILE_ELF_V1, true)?;
    require_elf_magic(so, &so_path)?;
    Ok(ProfileJoinResult {
        profile_id: PROFILE_ELF_V1.into(),
        plan_digest_hex: loaded.manifest.plan_digest.clone(),
        profile_digest_hex: None,
        catalog_digest_hex: None,
        ir_digest_hex: None,
        so_path: Some(so_path),
        so_sha256_hex: Some(crate::util::sha256_hex(so)),
        so_bytes: Some(so.to_vec()),
    })
}

const LEGACY_IDL_VERSION: &str = "proof-forge-solana-idl/v1";
const LEGACY_PLAN_PROFILE: &str = "solana-sbpf-plan-v1";

fn validate_legacy_idl(
    idl: &Value,
    program_name: &str,
    profile_id: &str,
    deployable: bool,
) -> Result<(), ClientError> {
    require_str(idl, "version", LEGACY_IDL_VERSION)?;
    require_str(idl, "name", program_name)?;
    require_str(idl, "codegenProfile", profile_id)?;
    if idl.get("deployable").and_then(Value::as_bool) != Some(deployable) {
        return Err(ClientError::AbiJoin(format!(
            "idl.deployable mismatch: expected={deployable}"
        )));
    }
    if as_array(idl, "instructions")?.is_empty() {
        return Err(ClientError::AbiJoin(
            "idl.instructions must be non-empty".into(),
        ));
    }
    Ok(())
}

fn validate_legacy_plan(plan: &str, program_name: &str) -> Result<(), ClientError> {
    let exact_markers = [
        "; PROOF-FORGE-SBPF-PLAN v1".to_string(),
        format!("; codegen-profile: {LEGACY_PLAN_PROFILE}"),
        format!("; program: {program_name}"),
    ];
    for marker in exact_markers {
        if !plan.lines().any(|line| line == marker) {
            return Err(ClientError::AbiJoin(format!(
                "legacy plan missing exact marker {marker}"
            )));
        }
    }
    if !plan
        .lines()
        .any(|line| line.starts_with("; PLAN-ONLY NON-EXECUTABLE:"))
    {
        return Err(ClientError::AbiJoin(
            "legacy plan missing non-executable marker".into(),
        ));
    }
    Ok(())
}

fn validate_legacy_assembly(asm: &str) -> Result<(), ClientError> {
    if !asm.contains("; PROOF-FORGE-SBPF-ASM v1") {
        return Err(ClientError::AbiJoin(
            "legacy assembly missing PROOF-FORGE-SBPF-ASM v1 marker".into(),
        ));
    }
    Ok(())
}

fn require_elf_magic(so: &[u8], label: &str) -> Result<(), ClientError> {
    if so.len() < 4 || &so[0..4] != b"\x7fELF" {
        return Err(ClientError::Artifact(format!(
            "{label} must begin with 7fELF"
        )));
    }
    Ok(())
}

/// Generic CPI profile adapter: dynamic programName leaf shape + pinned
/// profile/catalog/extension digests + Plan/IR/IDL/bindings cross joins.
/// Does **not** assume a single transfer handler.
fn verify_cpi_elf_profile(loaded: &LoadedOutputSet) -> Result<ProfileJoinResult, ClientError> {
    let name = &loaded.manifest.artifact_program_name;
    let expected = cpi_elf_expected_leaves(name);
    require_exact_leaf_shape(loaded, &expected)?;
    if !loaded.manifest.deployable {
        return Err(ClientError::Artifact(
            "solana-sbpf-cpi-elf-v1 deployable must be true".into(),
        ));
    }

    let bindings_path = format!("{name}.cpi-bindings.json");
    let ir_path = format!("{name}.cpi-ir.json");
    let plan_path = format!("{name}.cpi-plan.json");
    let idl_path = format!("{name}.idl.json");
    let asm_path = format!("{name}.s");
    let so_path = format!("{name}.so");

    let plan_bytes = leaf_bytes_by_name(loaded, &plan_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing plan leaf {plan_path}")))?;
    let ir_bytes = leaf_bytes_by_name(loaded, &ir_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing ir leaf {ir_path}")))?;
    let bindings_bytes = leaf_bytes_by_name(loaded, &bindings_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing bindings leaf {bindings_path}")))?;
    let idl_bytes = leaf_bytes_by_name(loaded, &idl_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing idl leaf {idl_path}")))?;
    let asm_bytes = leaf_bytes_by_name(loaded, &asm_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing assembly leaf {asm_path}")))?;
    let so_bytes = leaf_bytes_by_name(loaded, &so_path)
        .ok_or_else(|| ClientError::Artifact(format!("missing ELF leaf {so_path}")))?;

    require_elf_magic(so_bytes, &so_path)?;

    let plan_digest = domain_separated_sha256_hex(PLAN_DIGEST_DOMAIN, plan_bytes);
    if plan_digest != loaded.manifest.plan_digest {
        return Err(ClientError::Artifact(format!(
            "planDigest domain recompute mismatch: actual={plan_digest} manifest={}",
            loaded.manifest.plan_digest
        )));
    }
    let ir_text = String::from_utf8(ir_bytes.to_vec())
        .map_err(|e| ClientError::AbiJoin(format!("ir utf-8: {e}")))?;
    let hybrid = is_full_body_hybrid_ir_text(&ir_text);
    let ir_digest = if hybrid {
        domain_separated_sha256_hex(FULL_BODY_HYBRID_IR_DIGEST_DOMAIN, ir_bytes)
    } else {
        domain_separated_sha256_hex(IR_DIGEST_DOMAIN, ir_bytes)
    };
    validate_cpi_evidence_note(
        &loaded.evidence.note,
        &loaded.manifest.plan_digest,
        &ir_digest,
    )?;

    let plan_v = parse_json_no_dups(plan_bytes)?;
    let idl_v = parse_json_no_dups(idl_bytes)?;
    let bindings_v = parse_json_no_dups(bindings_bytes)?;
    let asm_text = String::from_utf8(asm_bytes.to_vec())
        .map_err(|e| ClientError::AbiJoin(format!("assembly must be UTF-8: {e}")))?;

    if hybrid {
        join_cpi_full_body_hybrid(
            name,
            &loaded.manifest.plan_digest,
            &plan_v,
            &idl_v,
            &bindings_v,
            &ir_text,
            &asm_text,
            &ir_digest,
        )?;
    } else {
        join_cpi_generic(
            name,
            &loaded.manifest.plan_digest,
            &plan_v,
            &idl_v,
            &bindings_v,
            &ir_text,
            &asm_text,
            &ir_digest,
        )?;
    }

    Ok(ProfileJoinResult {
        profile_id: PROFILE_CPI_ELF_V1.into(),
        plan_digest_hex: loaded.manifest.plan_digest.clone(),
        profile_digest_hex: Some(CPI_PROFILE_DIGEST_HEX.into()),
        catalog_digest_hex: Some(CPI_CATALOG_DIGEST_HEX.into()),
        ir_digest_hex: Some(ir_digest),
        so_path: Some(so_path),
        so_sha256_hex: Some(crate::util::sha256_hex(so_bytes)),
        so_bytes: Some(so_bytes.to_vec()),
    })
}

fn validate_cpi_evidence_note(
    note: &str,
    plan_digest: &str,
    expected_ir_digest: &str,
) -> Result<(), ClientError> {
    let lower = note.to_ascii_lowercase();
    if lower.contains("preactivation")
        || lower.contains("activationdenied")
        || lower.contains("activation-denied")
        || lower.contains("test-preactivation")
    {
        return Err(ClientError::Artifact(
            "evidence.note contains preactivation marker".into(),
        ));
    }
    if !note.contains(&format!("profile={PROFILE_CPI_ELF_V1}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing active profile marker".into(),
        ));
    }
    if !note.contains(&format!("profileDigest=sha256:{CPI_PROFILE_DIGEST_HEX}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing profileDigest join".into(),
        ));
    }
    if !note.contains(&format!("catalogDigest=sha256:{CPI_CATALOG_DIGEST_HEX}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing catalogDigest join".into(),
        ));
    }
    if !note.contains(&format!("planDigest=sha256:{plan_digest}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing planDigest join to manifest".into(),
        ));
    }
    if !note.contains(&format!("irDigest=sha256:{expected_ir_digest}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing exact irDigest join".into(),
        ));
    }
    Ok(())
}


fn is_full_body_hybrid_ir_text(ir_text: &str) -> bool {
    ir_text.contains(&format!("\"schema\":\"{FULL_BODY_HYBRID_IR_SCHEMA}\""))
        || ir_text.contains(&format!("\"schema\": \"{FULL_BODY_HYBRID_IR_SCHEMA}\""))
}

/// Body-only / Map full-body hybrid product joins (P3-c/g).
/// Marker IR is compact JSON (not escrow product line-oriented IR).
#[allow(clippy::too_many_arguments)]
fn join_cpi_full_body_hybrid(
    program_name: &str,
    plan_digest: &str,
    plan: &Value,
    idl: &Value,
    bindings: &Value,
    ir_text: &str,
    asm_text: &str,
    expected_ir_digest: &str,
) -> Result<(), ClientError> {
    // ---- Plan (body-only admission extension) ----
    require_str(plan, "schema", CPI_PLAN_SCHEMA)?;
    require_str(plan, "programName", program_name)?;
    require_str(plan, "profileId", PROFILE_CPI_ELF_V1)?;
    require_digest_wire_eq(
        "plan.profileDigest",
        plan_str(plan, "profileDigest")?,
        CPI_PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "plan.calleeCatalogDigest",
        plan_str(plan, "calleeCatalogDigest")?,
        CPI_CATALOG_DIGEST_HEX,
    )?;

    let ext = plan
        .get("extensionRequirement")
        .ok_or_else(|| ClientError::AbiJoin("plan missing extensionRequirement".into()))?;
    require_str(ext, "id", BODY_ONLY_EXTENSION_ID)?;
    require_str(ext, "version", BODY_ONLY_EXTENSION_VERSION)?;
    require_digest_wire_eq(
        "plan.extensionRequirement.digest",
        plan_str(ext, "digest")?,
        BODY_ONLY_EXTENSION_DIGEST_HEX,
    )?;
    if !as_array(ext, "predicates")?.is_empty() {
        return Err(ClientError::AbiJoin(
            "plan.extensionRequirement.predicates must be empty".into(),
        ));
    }

    let handlers = as_array(plan, "handlers")?;
    if handlers.is_empty() {
        return Err(ClientError::AbiJoin(
            "plan.handlers must be non-empty".into(),
        ));
    }
    for (i, h) in handlers.iter().enumerate() {
        if h.get("handlerId").and_then(Value::as_u64) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "handlers[{i}].handlerId must be {i}"
            )));
        }
        if h.get("name").and_then(Value::as_str).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "handlers[{i}].name must be a string"
            )));
        }
        if h.get("mode").and_then(Value::as_str).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "handlers[{i}].mode must be a string"
            )));
        }
    }
    let sites = as_array(plan, "cpiSites")?;
    if !sites.is_empty() {
        return Err(ClientError::AbiJoin(
            "full-body hybrid plan.cpiSites must be empty".into(),
        ));
    }
    let assumptions = plan
        .get("computeAssumptions")
        .ok_or_else(|| ClientError::AbiJoin("plan.computeAssumptions missing".into()))?;
    require_str(
        assumptions,
        "implementationState",
        "product-exact-synchronous-call-active-v1",
    )?;

    // ---- Bindings (hybrid compact shape) ----
    require_str(bindings, "schema", CPI_BINDINGS_SCHEMA)?;
    if bindings.get("fullBodyHybrid").and_then(Value::as_bool) != Some(true) {
        return Err(ClientError::AbiJoin(
            "hybrid bindings.fullBodyHybrid must be true".into(),
        ));
    }
    require_str(bindings, "programName", program_name)?;
    require_str(bindings, "frameMode", "bodyOnly")?;
    if bindings.get("frameBytes").and_then(Value::as_u64) != Some(4096) {
        return Err(ClientError::AbiJoin(
            "hybrid bindings.frameBytes must be 4096".into(),
        ));
    }
    if bindings.get("cpiSites").and_then(Value::as_u64) != Some(0) {
        return Err(ClientError::AbiJoin(
            "hybrid bindings.cpiSites must be 0".into(),
        ));
    }
    let bind_ir = require_sha256_wire("bindings.irDigest", plan_str(bindings, "irDigest")?)?;
    if bind_ir != expected_ir_digest {
        return Err(ClientError::AbiJoin(format!(
            "hybrid bindings.irDigest domain recompute mismatch: bindings={bind_ir} recomputed={expected_ir_digest}"
        )));
    }

    // ---- IDL ----
    require_str(idl, "schema", CPI_IDL_SCHEMA)?;
    require_str(idl, "programName", program_name)?;
    require_str(idl, "profileId", PROFILE_CPI_ELF_V1)?;
    require_digest_wire_eq(
        "idl.profileDigest",
        plan_str(idl, "profileDigest")?,
        CPI_PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "idl.catalogDigest",
        plan_str(idl, "catalogDigest")?,
        CPI_CATALOG_DIGEST_HEX,
    )?;
    let idl_plan = require_sha256_wire("idl.planDigest", plan_str(idl, "planDigest")?)?;
    if idl_plan != plan_digest {
        return Err(ClientError::AbiJoin(
            "idl.planDigest != manifest.planDigest".into(),
        ));
    }
    let instructions = as_array(idl, "instructions")?;
    if instructions.len() != handlers.len() {
        return Err(ClientError::AbiJoin(format!(
            "idl.instructions length {} must equal plan.handlers length {}",
            instructions.len(),
            handlers.len()
        )));
    }
    for (i, ix) in instructions.iter().enumerate() {
        if ix.get("handlerId").and_then(Value::as_u64) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "idl.instructions[{i}].handlerId must be {i}"
            )));
        }
        let plan_name = handlers[i]
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("");
        let ix_name = ix.get("name").and_then(Value::as_str).unwrap_or("");
        if ix_name != plan_name {
            return Err(ClientError::AbiJoin(format!(
                "idl.instructions[{i}].name '{ix_name}' != plan.handlers[{i}].name '{plan_name}'"
            )));
        }
    }

    // ---- Hybrid IR marker JSON ----
    validate_full_body_hybrid_ir_json(ir_text)?;

    // ---- Assembly (body-only S1b surface; not composite CPI product markers) ----
    validate_full_body_hybrid_assembly(asm_text)?;

    Ok(())
}

fn validate_full_body_hybrid_ir_json(ir_text: &str) -> Result<(), ClientError> {
    let v: Value = serde_json::from_str(ir_text)
        .map_err(|e| ClientError::AbiJoin(format!("hybrid ir json: {e}")))?;
    require_str(&v, "schema", FULL_BODY_HYBRID_IR_SCHEMA)?;
    // marker fields — engineering honesty, not provenance
    if v.get("synthesize").and_then(Value::as_str).is_none() {
        return Err(ClientError::AbiJoin(
            "hybrid ir missing synthesize".into(),
        ));
    }
    if v.get("frameMode").and_then(Value::as_str) != Some("bodyOnly") {
        return Err(ClientError::AbiJoin(
            "hybrid ir frameMode must be bodyOnly".into(),
        ));
    }
    if v.get("frameBytes").and_then(Value::as_u64) != Some(4096) {
        return Err(ClientError::AbiJoin(
            "hybrid ir frameBytes must be 4096".into(),
        ));
    }
    if v.get("cpiSites").and_then(Value::as_u64) != Some(0) {
        return Err(ClientError::AbiJoin(
            "hybrid ir cpiSites must be 0".into(),
        ));
    }
    Ok(())
}

/// Generic CPI Plan/IR/IDL/bindings joins (no transfer-handler assumption).
#[allow(clippy::too_many_arguments)]
fn join_cpi_generic(
    program_name: &str,
    plan_digest: &str,
    plan: &Value,
    idl: &Value,
    bindings: &Value,
    ir_text: &str,
    asm_text: &str,
    expected_ir_digest: &str,
) -> Result<(), ClientError> {
    // ---- Plan ----
    require_str(plan, "schema", CPI_PLAN_SCHEMA)?;
    require_str(plan, "programName", program_name)?;
    require_str(plan, "profileId", PROFILE_CPI_ELF_V1)?;
    require_digest_wire_eq(
        "plan.profileDigest",
        plan_str(plan, "profileDigest")?,
        CPI_PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "plan.calleeCatalogDigest",
        plan_str(plan, "calleeCatalogDigest")?,
        CPI_CATALOG_DIGEST_HEX,
    )?;

    let ext = plan
        .get("extensionRequirement")
        .ok_or_else(|| ClientError::AbiJoin("plan missing extensionRequirement".into()))?;
    require_str(ext, "id", CPI_EXTENSION_ID)?;
    require_str(ext, "version", CPI_EXTENSION_VERSION)?;
    require_digest_wire_eq(
        "plan.extensionRequirement.digest",
        plan_str(ext, "digest")?,
        CPI_EXTENSION_DIGEST_HEX,
    )?;
    if !as_array(ext, "predicates")?.is_empty() {
        return Err(ClientError::AbiJoin(
            "plan.extensionRequirement.predicates must be empty".into(),
        ));
    }

    let handlers = as_array(plan, "handlers")?;
    if handlers.is_empty() {
        return Err(ClientError::AbiJoin(
            "plan.handlers must be non-empty".into(),
        ));
    }
    // Canonical source order, without pinning any business handler name/count.
    for (i, h) in handlers.iter().enumerate() {
        if h.get("handlerId").and_then(Value::as_u64) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "handlers[{i}].handlerId must be {i}"
            )));
        }
        if h.get("name").and_then(Value::as_str).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "handlers[{i}].name must be a string"
            )));
        }
        if h.get("mode").and_then(Value::as_str).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "handlers[{i}].mode must be a string"
            )));
        }
    }

    let roles = as_array(plan, "accountRoles")?;
    if roles.is_empty() {
        return Err(ClientError::AbiJoin(
            "plan.accountRoles must be non-empty".into(),
        ));
    }
    for (i, r) in roles.iter().enumerate() {
        if r.get("roleId").and_then(|v| v.as_u64()) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "accountRoles[{i}].roleId must be {i}"
            )));
        }
        if r.get("name").and_then(|v| v.as_str()).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "accountRoles[{i}].name must be a string"
            )));
        }
    }

    let sites = as_array(plan, "cpiSites")?;
    // CPI sites are dense and point into the generic handler table.
    for (i, site) in sites.iter().enumerate() {
        if site.get("siteId").and_then(Value::as_u64) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "cpiSites[{i}].siteId must be {i}"
            )));
        }
        let handler_id = site
            .get("handlerId")
            .and_then(Value::as_u64)
            .ok_or_else(|| {
                ClientError::AbiJoin(format!("cpiSites[{i}].handlerId must be a number"))
            })?;
        if handler_id >= handlers.len() as u64 {
            return Err(ClientError::AbiJoin(format!(
                "cpiSites[{i}].handlerId out of range: {handler_id}"
            )));
        }
        if site.get("packageId").and_then(Value::as_str).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "cpiSites[{i}].packageId must be a string"
            )));
        }
        if site.get("qn").and_then(Value::as_str).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "cpiSites[{i}].qn must be a string"
            )));
        }
    }

    let assumptions = plan
        .get("computeAssumptions")
        .ok_or_else(|| ClientError::AbiJoin("plan.computeAssumptions missing".into()))?;
    require_str(
        assumptions,
        "implementationState",
        "product-exact-synchronous-call-active-v1",
    )?;

    // ---- Bindings ----
    require_str(bindings, "schema", CPI_BINDINGS_SCHEMA)?;
    require_str(bindings, "profileId", PROFILE_CPI_ELF_V1)?;
    require_digest_wire_eq(
        "bindings.profileDigest",
        plan_str(bindings, "profileDigest")?,
        CPI_PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "bindings.calleeCatalogDigest",
        plan_str(bindings, "calleeCatalogDigest")?,
        CPI_CATALOG_DIGEST_HEX,
    )?;
    let bind_plan = require_sha256_wire("bindings.planDigest", plan_str(bindings, "planDigest")?)?;
    if bind_plan != plan_digest {
        return Err(ClientError::AbiJoin(
            "bindings.planDigest != manifest.planDigest".into(),
        ));
    }
    let bind_ir = require_sha256_wire("bindings.irDigest", plan_str(bindings, "irDigest")?)?;
    if bind_ir != expected_ir_digest {
        return Err(ClientError::AbiJoin(format!(
            "bindings.irDigest domain recompute mismatch: bindings={bind_ir} recomputed={expected_ir_digest}"
        )));
    }
    require_str(
        bindings,
        "implementationState",
        "product-exact-synchronous-call-active-v1",
    )?;
    let pkgs = as_array(bindings, "referencedPackages")?;
    for (i, pkg) in pkgs.iter().enumerate() {
        if pkg.get("packageId").and_then(|v| v.as_str()).is_none() {
            return Err(ClientError::AbiJoin(format!(
                "referencedPackages[{i}].packageId missing"
            )));
        }
        if pkg
            .get("admittedForMaterialization")
            .and_then(|v| v.as_bool())
            != Some(true)
        {
            return Err(ClientError::AbiJoin(format!(
                "referencedPackages[{i}].admittedForMaterialization must be true"
            )));
        }
    }
    // If system-v1 is referenced, pin exact native binding (cross-digest honesty).
    for pkg in pkgs {
        if pkg.get("packageId").and_then(|v| v.as_str()) == Some(SYSTEM_PACKAGE_ID) {
            require_str(pkg, "programIdHex", SYSTEM_PROGRAM_ID_HEX)?;
            require_str(pkg, "executionClass", "native-system")?;
            require_str(pkg, "artifactBinding", SYSTEM_RUNTIME_NATIVE_BINDING)?;
        }
    }

    // ---- IDL ----
    require_str(idl, "schema", CPI_IDL_SCHEMA)?;
    require_str(idl, "programName", program_name)?;
    require_str(idl, "profileId", PROFILE_CPI_ELF_V1)?;
    require_digest_wire_eq(
        "idl.profileDigest",
        plan_str(idl, "profileDigest")?,
        CPI_PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "idl.catalogDigest",
        plan_str(idl, "catalogDigest")?,
        CPI_CATALOG_DIGEST_HEX,
    )?;
    let idl_plan = require_sha256_wire("idl.planDigest", plan_str(idl, "planDigest")?)?;
    if idl_plan != plan_digest {
        return Err(ClientError::AbiJoin(
            "idl.planDigest != manifest.planDigest".into(),
        ));
    }
    let instructions = as_array(idl, "instructions")?;
    if instructions.len() != handlers.len() {
        return Err(ClientError::AbiJoin(format!(
            "idl.instructions length {} must equal plan.handlers length {}",
            instructions.len(),
            handlers.len()
        )));
    }
    for (i, (instruction, handler)) in instructions.iter().zip(handlers).enumerate() {
        if instruction.get("handlerId").and_then(Value::as_u64) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "idl.instructions[{i}].handlerId must be {i}"
            )));
        }
        for field in ["name", "mode"] {
            let idl_value = plan_str(instruction, field)?;
            let plan_value = plan_str(handler, field)?;
            if idl_value != plan_value {
                return Err(ClientError::AbiJoin(format!(
                    "idl.instructions[{i}].{field} diverges from plan.handlers[{i}]"
                )));
            }
        }
    }
    let idl_sites = as_array(idl, "cpiSites")?;
    if idl_sites.len() != sites.len() {
        return Err(ClientError::AbiJoin(format!(
            "idl.cpiSites length {} must equal plan.cpiSites length {}",
            idl_sites.len(),
            sites.len()
        )));
    }
    for (i, (idl_site, plan_site)) in idl_sites.iter().zip(sites).enumerate() {
        for field in ["siteId", "handlerId"] {
            if idl_site.get(field).and_then(Value::as_u64)
                != plan_site.get(field).and_then(Value::as_u64)
            {
                return Err(ClientError::AbiJoin(format!(
                    "idl.cpiSites[{i}].{field} diverges from plan.cpiSites[{i}]"
                )));
            }
        }
        for field in ["packageId", "qn"] {
            if plan_str(idl_site, field)? != plan_str(plan_site, field)? {
                return Err(ClientError::AbiJoin(format!(
                    "idl.cpiSites[{i}].{field} diverges from plan.cpiSites[{i}]"
                )));
            }
        }
    }

    // ---- IR text ----
    validate_cpi_ir_text(ir_text, plan_digest, handlers.len())?;

    // ---- Assembly ----
    validate_cpi_assembly(asm_text)?;

    Ok(())
}

fn validate_cpi_ir_text(
    ir_text: &str,
    plan_digest: &str,
    expected_handler_lines: usize,
) -> Result<(), ClientError> {
    let mut keys: BTreeMap<&str, &str> = BTreeMap::new();
    let mut handler_lines = 0usize;
    for line in ir_text.lines() {
        if let Some((k, v)) = line.split_once('=') {
            if keys.insert(k, v).is_some() {
                return Err(ClientError::AbiJoin(format!("ir duplicate top key: {k}")));
            }
        } else if line.starts_with("handler:") {
            handler_lines += 1;
        } else if !line.is_empty() {
            return Err(ClientError::AbiJoin(format!("ir unexpected line: {line}")));
        }
    }
    let required = [
        "schema",
        "sourcePlanDigest",
        "sourceIrDigest",
        "profileId",
        "profileDigest",
        "catalogDigest",
        "maxOuterRoles",
        "maxFrameBytes",
    ];
    for k in required {
        if !keys.contains_key(k) {
            return Err(ClientError::AbiJoin(format!("ir missing key {k}")));
        }
    }
    if keys.len() != required.len() {
        return Err(ClientError::AbiJoin(format!(
            "ir top keys must be exactly {} entries, got {:?}",
            required.len(),
            keys.keys().collect::<Vec<_>>()
        )));
    }
    if keys["schema"] != CPI_IR_SCHEMA_LINE {
        return Err(ClientError::AbiJoin("ir schema mismatch".into()));
    }
    if keys["profileId"] != PROFILE_CPI_ELF_V1 {
        return Err(ClientError::AbiJoin("ir profileId mismatch".into()));
    }
    require_digest_wire_eq(
        "ir.profileDigest",
        keys["profileDigest"],
        CPI_PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "ir.catalogDigest",
        keys["catalogDigest"],
        CPI_CATALOG_DIGEST_HEX,
    )?;
    let ir_plan = require_sha256_wire("ir.sourcePlanDigest", keys["sourcePlanDigest"])?;
    if ir_plan != plan_digest {
        return Err(ClientError::AbiJoin(
            "ir.sourcePlanDigest != manifest.planDigest".into(),
        ));
    }
    let _ = require_sha256_wire("ir.sourceIrDigest", keys["sourceIrDigest"])?;
    if keys["maxOuterRoles"] != "16" {
        return Err(ClientError::AbiJoin("ir maxOuterRoles must be 16".into()));
    }
    if keys["maxFrameBytes"] != "4096" {
        return Err(ClientError::AbiJoin("ir maxFrameBytes must be 4096".into()));
    }
    if handler_lines != expected_handler_lines {
        return Err(ClientError::AbiJoin(format!(
            "ir handler line count {handler_lines} must equal plan.handlers length {expected_handler_lines}"
        )));
    }
    Ok(())
}


fn validate_full_body_hybrid_assembly(asm: &str) -> Result<(), ClientError> {
    let lower = asm.to_ascii_lowercase();
    if lower.contains("preactivation")
        || lower.contains("activationdenied")
        || lower.contains("activation-denied")
        || lower.contains("test-preactivation")
        || lower.contains("callx")
    {
        return Err(ClientError::AbiJoin(
            "hybrid assembly contains a preactivation/indirect-call marker".into(),
        ));
    }
    // Body-only / Map programs use the ordinary S1b emitter, not the composite
    // CPI product banner (PRODUCT ARTIFACT / sol_invoke_signed_c).
    for marker in ["PROOF-FORGE-SBPF-ASM", ".globl entrypoint", "entrypoint:"] {
        if !asm.contains(marker) {
            return Err(ClientError::AbiJoin(format!(
                "hybrid assembly missing marker {marker}"
            )));
        }
    }
    Ok(())
}

fn validate_cpi_assembly(asm: &str) -> Result<(), ClientError> {
    let lower = asm.to_ascii_lowercase();
    if lower.contains("preactivation")
        || lower.contains("activationdenied")
        || lower.contains("activation-denied")
        || lower.contains("test-preactivation")
        || lower.contains("0xec01")
        || lower.contains("callx")
    {
        return Err(ClientError::AbiJoin(
            "assembly contains a preactivation/indirect-call marker".into(),
        ));
    }
    for marker in [
        "PRODUCT ARTIFACT",
        "isProductArtifact=true",
        "sol_invoke_signed_c",
        "sol_set_return_data",
    ] {
        if !asm.contains(marker) {
            return Err(ClientError::AbiJoin(format!(
                "assembly missing exact product marker {marker}"
            )));
        }
    }
    Ok(())
}

fn as_array<'a>(v: &'a Value, key: &str) -> Result<&'a Vec<Value>, ClientError> {
    v.get(key)
        .and_then(|x| x.as_array())
        .ok_or_else(|| ClientError::AbiJoin(format!("missing array field {key}")))
}

fn plan_str<'a>(v: &'a Value, key: &str) -> Result<&'a str, ClientError> {
    v.get(key)
        .and_then(|x| x.as_str())
        .ok_or_else(|| ClientError::AbiJoin(format!("missing string field {key}")))
}

fn require_str(v: &Value, key: &str, expected: &str) -> Result<(), ClientError> {
    let actual = plan_str(v, key)?;
    if actual != expected {
        return Err(ClientError::AbiJoin(format!(
            "{key} mismatch: actual={actual} expected={expected}"
        )));
    }
    Ok(())
}
