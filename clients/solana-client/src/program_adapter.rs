//! Optional program adapters (fixture pins). Default verification selects none.

use clap::ValueEnum;
use serde_json::Value;

use crate::constants::{
    PROGRAM_ADAPTER_TRANSFER_SOL_V1, SYSTEM_PACKAGE_ID, SYSTEM_PROGRAM_BASE58,
    SYSTEM_PROGRAM_ID_HEX, TRANSFER_SOL_PROGRAM_NAME, TRANSFER_SOL_SOURCE_HASH,
};
use crate::error::ClientError;
use crate::output_set::{leaf_bytes_by_name, LoadedOutputSet};
use crate::profile::ProfileJoinResult;
use crate::util::parse_json_no_dups;

/// Closed program-adapter IDs accepted on the CLI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum ProgramAdapterId {
    /// Frozen TransferSol sourceHash + exact handler/accounts/System CPI pins.
    #[value(name = "transfer-sol-v1")]
    TransferSolV1,
}

impl ProgramAdapterId {
    pub fn parse(s: &str) -> Result<Self, ClientError> {
        match s {
            PROGRAM_ADAPTER_TRANSFER_SOL_V1 => Ok(Self::TransferSolV1),
            other => Err(ClientError::Artifact(format!(
                "unknown program adapter '{other}' (closed set: {PROGRAM_ADAPTER_TRANSFER_SOL_V1})"
            ))),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::TransferSolV1 => PROGRAM_ADAPTER_TRANSFER_SOL_V1,
        }
    }

    pub fn trust_anchor_note(self) -> &'static str {
        match self {
            Self::TransferSolV1 => {
                "Examples/TransferSol.lean frozen sourceHash pin + TransferSol ABI fixture"
            }
        }
    }
}

/// Apply opt-in program adapter pins after generic OutputSet + profile joins.
pub fn apply_program_adapter(
    loaded: &LoadedOutputSet,
    profile: &ProfileJoinResult,
    adapter: ProgramAdapterId,
) -> Result<(), ClientError> {
    match adapter {
        ProgramAdapterId::TransferSolV1 => apply_transfer_sol_v1(loaded, profile),
    }
}

fn apply_transfer_sol_v1(
    loaded: &LoadedOutputSet,
    profile: &ProfileJoinResult,
) -> Result<(), ClientError> {
    if loaded.manifest.artifact_program_name != TRANSFER_SOL_PROGRAM_NAME {
        return Err(ClientError::Artifact(format!(
            "program adapter transfer-sol-v1 requires artifactProgramName={TRANSFER_SOL_PROGRAM_NAME}, got {}",
            loaded.manifest.artifact_program_name
        )));
    }
    if loaded.manifest.source_hash != TRANSFER_SOL_SOURCE_HASH {
        return Err(ClientError::Artifact(format!(
            "sourceHash trust-anchor mismatch: actual={} expected={}",
            loaded.manifest.source_hash, TRANSFER_SOL_SOURCE_HASH
        )));
    }
    if profile.profile_id != crate::constants::PROFILE_CPI_ELF_V1 {
        return Err(ClientError::Artifact(format!(
            "transfer-sol-v1 requires profile {}, got {}",
            crate::constants::PROFILE_CPI_ELF_V1,
            profile.profile_id
        )));
    }

    let name = TRANSFER_SOL_PROGRAM_NAME;
    let plan_bytes = leaf_bytes_by_name(loaded, &format!("{name}.cpi-plan.json"))
        .ok_or_else(|| ClientError::AbiJoin("TransferSol plan leaf missing".into()))?;
    let idl_bytes = leaf_bytes_by_name(loaded, &format!("{name}.idl.json"))
        .ok_or_else(|| ClientError::AbiJoin("TransferSol idl leaf missing".into()))?;
    let ir_bytes = leaf_bytes_by_name(loaded, &format!("{name}.cpi-ir.json"))
        .ok_or_else(|| ClientError::AbiJoin("TransferSol ir leaf missing".into()))?;

    let plan = parse_json_no_dups(plan_bytes)?;
    let idl = parse_json_no_dups(idl_bytes)?;
    let ir_text = String::from_utf8(ir_bytes.to_vec())
        .map_err(|e| ClientError::AbiJoin(format!("ir utf-8: {e}")))?;

    join_transfer_sol_abi(&plan, &idl, &ir_text)?;
    Ok(())
}

fn join_transfer_sol_abi(plan: &Value, idl: &Value, ir_text: &str) -> Result<(), ClientError> {
    let handlers = as_array(plan, "handlers")?;
    if handlers.len() != 1 {
        return Err(ClientError::AbiJoin(format!(
            "plan.handlers length must be 1, got {}",
            handlers.len()
        )));
    }
    let h0 = &handlers[0];
    if h0.get("handlerId").and_then(|v| v.as_u64()) != Some(0) {
        return Err(ClientError::AbiJoin(
            "handlers[0].handlerId must be 0".into(),
        ));
    }
    require_str(h0, "name", "transfer")?;
    require_str(h0, "mode", "entry")?;
    if h0.get("callableId").and_then(|v| v.as_u64()) != Some(0) {
        return Err(ClientError::AbiJoin(
            "handlers[0].callableId must be 0".into(),
        ));
    }
    if as_u64_array(h0, "cpiSiteIds")? != vec![0] {
        return Err(ClientError::AbiJoin(
            "handlers[0].cpiSiteIds must be exactly [0]".into(),
        ));
    }

    let roles = as_array(plan, "accountRoles")?;
    if roles.len() != 3 {
        return Err(ClientError::AbiJoin(
            "plan.accountRoles length must be 3".into(),
        ));
    }
    require_str(&roles[0], "name", "transfer_payer")?;
    require_str(&roles[1], "name", "transfer_recipient")?;
    require_str(&roles[2], "name", "system_v1_program")?;
    for (role_index, param_ordinal) in [(0usize, 0u64), (1usize, 1u64)] {
        let key_policy = roles[role_index].get("keyPolicy").ok_or_else(|| {
            ClientError::AbiJoin(format!("accountRoles[{role_index}].keyPolicy missing"))
        })?;
        require_str(key_policy, "kind", "accountParameter")?;
        if key_policy.get("callableId").and_then(|v| v.as_u64()) != Some(0)
            || key_policy.get("paramOrdinal").and_then(|v| v.as_u64()) != Some(param_ordinal)
        {
            return Err(ClientError::AbiJoin(format!(
                "accountRoles[{role_index}] must bind callable 0 parameter {param_ordinal}"
            )));
        }
    }
    let kp2 = roles[2]
        .get("keyPolicy")
        .ok_or_else(|| ClientError::AbiJoin("role2.keyPolicy".into()))?;
    require_str(kp2, "kind", "fixedProgram")?;
    require_str(kp2, "packageId", SYSTEM_PACKAGE_ID)?;

    let uses = as_array(h0, "accountUses")?;
    if uses.len() != 3 {
        return Err(ClientError::AbiJoin(
            "handlers[0].accountUses length must be 3".into(),
        ));
    }
    check_use(&uses[0], 0, 0, true, true)?;
    check_use(&uses[1], 1, 1, false, true)?;
    check_use(&uses[2], 2, 2, false, false)?;

    let sites = as_array(plan, "cpiSites")?;
    if sites.len() != 1 {
        return Err(ClientError::AbiJoin(format!(
            "plan.cpiSites length must be 1, got {}",
            sites.len()
        )));
    }
    let site0 = &sites[0];
    require_str(site0, "packageId", SYSTEM_PACKAGE_ID)?;
    require_str(site0, "qn", "solana.system.transfer")?;
    for (field, expected) in [
        ("siteId", 0u64),
        ("handlerId", 0u64),
        ("programRoleId", 2u64),
    ] {
        if site0.get(field).and_then(|v| v.as_u64()) != Some(expected) {
            return Err(ClientError::AbiJoin(format!(
                "cpiSites[0].{field} must be {expected}"
            )));
        }
    }
    if as_u64_array(site0, "accountInfoRoleIds")? != vec![0, 1, 2] {
        return Err(ClientError::AbiJoin(
            "cpiSites[0].accountInfoRoleIds must be exactly [0,1,2]".into(),
        ));
    }
    match site0.get("programKey") {
        Some(Value::String(s)) if s == SYSTEM_PROGRAM_ID_HEX => {}
        Some(Value::Object(o)) => {
            let hex = o
                .get("hex")
                .or_else(|| o.get("programIdHex"))
                .and_then(|v| v.as_str());
            if hex != Some(SYSTEM_PROGRAM_ID_HEX) {
                return Err(ClientError::AbiJoin(
                    "cpiSites[0].programKey must be 64 zero hex".into(),
                ));
            }
        }
        other => {
            return Err(ClientError::AbiJoin(format!(
                "cpiSites[0].programKey invalid: {other:?}"
            )));
        }
    }
    let codec = site0
        .get("instructionCodec")
        .ok_or_else(|| ClientError::AbiJoin("instructionCodec".into()))?;
    if codec.get("length").and_then(|v| v.as_u64()) != Some(12) {
        return Err(ClientError::AbiJoin(
            "instructionCodec.length must be 12".into(),
        ));
    }
    let segs = as_array(codec, "segments")?;
    if segs.len() != 2 {
        return Err(ClientError::AbiJoin(
            "instructionCodec.segments length must be 2".into(),
        ));
    }
    if segs[0].get("hex").and_then(|v| v.as_str()) != Some("02000000")
        || segs[0].get("kind").and_then(|v| v.as_str()) != Some("hex")
    {
        return Err(ClientError::AbiJoin(
            "codec segment0 must be hex 02000000".into(),
        ));
    }
    if segs[1].get("kind").and_then(|v| v.as_str()) != Some("arg")
        || segs[1].get("name").and_then(|v| v.as_str()) != Some("lamports")
        || segs[1].get("encoding").and_then(|v| v.as_str()) != Some("uint64Le")
    {
        return Err(ClientError::AbiJoin(
            "codec segment1 must be arg lamports uint64Le".into(),
        ));
    }
    let metas = as_array(site0, "metas")?;
    if metas.len() != 2 {
        return Err(ClientError::AbiJoin(
            "cpiSites[0].metas must contain payer and recipient only".into(),
        ));
    }
    check_cpi_meta(&metas[0], 0, 0, true, true, true, true)?;
    check_cpi_meta(&metas[1], 1, 1, false, true, false, true)?;
    if !as_array(plan, "stateSchemas")?.is_empty() {
        return Err(ClientError::AbiJoin(
            "TransferSol plan.stateSchemas must be empty".into(),
        ));
    }

    // ---- IDL fixture pins ----
    let instructions = as_array(idl, "instructions")?;
    if instructions.len() != 1 {
        return Err(ClientError::AbiJoin(
            "idl.instructions length must be 1".into(),
        ));
    }
    let ins0 = &instructions[0];
    require_str(ins0, "name", "transfer")?;
    require_str(ins0, "mode", "entry")?;
    if ins0.get("handlerId").and_then(|v| v.as_u64()) != Some(0) {
        return Err(ClientError::AbiJoin("idl handlerId must be 0".into()));
    }
    if as_u64_array(ins0, "cpiSiteIds")? != vec![0] {
        return Err(ClientError::AbiJoin(
            "idl cpiSiteIds must be exactly [0]".into(),
        ));
    }
    let accounts = as_array(ins0, "accounts")?;
    if accounts.len() != 3 {
        return Err(ClientError::AbiJoin("idl accounts length must be 3".into()));
    }
    require_str(&accounts[0], "name", "transfer_payer")?;
    require_str(&accounts[1], "name", "transfer_recipient")?;
    require_str(&accounts[2], "name", "system_v1_program")?;
    check_idl_account(&accounts[0], 0, true, true)?;
    check_idl_account(&accounts[1], 1, false, true)?;
    check_idl_account(&accounts[2], 2, false, false)?;
    let idl_sites = as_array(idl, "cpiSites")?;
    if idl_sites.len() != 1 {
        return Err(ClientError::AbiJoin("idl.cpiSites length must be 1".into()));
    }
    let idl_site = &idl_sites[0];
    for (field, expected) in [("siteId", 0u64), ("handlerId", 0u64)] {
        if idl_site.get(field).and_then(|v| v.as_u64()) != Some(expected) {
            return Err(ClientError::AbiJoin(format!(
                "idl cpiSites[0].{field} must be {expected}"
            )));
        }
    }
    require_str(idl_site, "packageId", SYSTEM_PACKAGE_ID)?;
    require_str(idl_site, "qn", "solana.system.transfer")?;
    if idl_site.get("programIdBase58").and_then(|v| v.as_str()) != Some(SYSTEM_PROGRAM_BASE58) {
        return Err(ClientError::AbiJoin(
            "idl cpiSites[0].programIdBase58 must be System".into(),
        ));
    }
    if !as_array(idl, "stateSchemas")?.is_empty() {
        return Err(ClientError::AbiJoin(
            "TransferSol idl.stateSchemas must be empty".into(),
        ));
    }

    // ---- IR handler pin ----
    let mut handler_line: Option<&str> = None;
    for line in ir_text.lines() {
        if line.starts_with("handler:") {
            if handler_line.is_some() {
                return Err(ClientError::AbiJoin(
                    "ir must have exactly one handler line".into(),
                ));
            }
            handler_line = Some(line);
        }
    }
    let h = handler_line.ok_or_else(|| ClientError::AbiJoin("ir missing handler line".into()))?;
    if !h.starts_with("handler:0:0:transfer:entry:roles3:probe16") {
        return Err(ClientError::AbiJoin(
            "ir handler line must lock handler0 transfer entry roles3 probe16".into(),
        ));
    }
    if !h.contains("loadParamU64:0@8") {
        return Err(ClientError::AbiJoin(
            "ir handler must contain loadParamU64:0@8".into(),
        ));
    }
    if !h.contains("system-v1") || !h.contains("solana.system.transfer") {
        return Err(ClientError::AbiJoin(
            "ir handler must reference system-v1 / solana.system.transfer".into(),
        ));
    }
    if !h.contains("returnU64") {
        return Err(ClientError::AbiJoin(
            "ir handler must contain returnU64".into(),
        ));
    }
    Ok(())
}

fn as_u64_array(v: &Value, key: &str) -> Result<Vec<u64>, ClientError> {
    as_array(v, key)?
        .iter()
        .map(|item| {
            item.as_u64()
                .ok_or_else(|| ClientError::AbiJoin(format!("{key} must contain UInt values")))
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn check_cpi_meta(
    meta: &Value,
    meta_index: u64,
    role_id: u64,
    signer: bool,
    writable: bool,
    outer_signer: bool,
    outer_writable: bool,
) -> Result<(), ClientError> {
    for (field, expected) in [("metaIndex", meta_index), ("roleId", role_id)] {
        if meta.get(field).and_then(|v| v.as_u64()) != Some(expected) {
            return Err(ClientError::AbiJoin(format!(
                "CPI meta {meta_index} field {field} must be {expected}"
            )));
        }
    }
    let spec = meta
        .get("spec")
        .ok_or_else(|| ClientError::AbiJoin(format!("CPI meta {meta_index}.spec missing")))?;
    for (field, expected) in [
        ("cpiSigner", signer),
        ("cpiWritable", writable),
        ("outerSignerContribution", outer_signer),
        ("outerWritableContribution", outer_writable),
    ] {
        if spec.get(field).and_then(|v| v.as_bool()) != Some(expected) {
            return Err(ClientError::AbiJoin(format!(
                "CPI meta {meta_index}.spec field {field} must be {expected}"
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

fn check_use(
    u: &Value,
    role_id: u64,
    position: u64,
    signer: bool,
    writable: bool,
) -> Result<(), ClientError> {
    if u.get("roleId").and_then(|v| v.as_u64()) != Some(role_id) {
        return Err(ClientError::AbiJoin(format!(
            "accountUse roleId expected {role_id}"
        )));
    }
    if u.get("position").and_then(|v| v.as_u64()) != Some(position) {
        return Err(ClientError::AbiJoin(format!(
            "accountUse position expected {position}"
        )));
    }
    let s = u
        .get("outerSigner")
        .and_then(|v| v.as_bool())
        .ok_or_else(|| ClientError::AbiJoin("outerSigner".into()))?;
    let w = u
        .get("outerWritable")
        .and_then(|v| v.as_bool())
        .ok_or_else(|| ClientError::AbiJoin("outerWritable".into()))?;
    if s != signer || w != writable {
        return Err(ClientError::AbiJoin(format!(
            "role {role_id} outer flags signer/writable actual={s}/{w} expected={signer}/{writable}"
        )));
    }
    Ok(())
}

fn check_idl_account(
    a: &Value,
    position: u64,
    signer: bool,
    writable: bool,
) -> Result<(), ClientError> {
    if a.get("position").and_then(|v| v.as_u64()) != Some(position) {
        return Err(ClientError::AbiJoin(format!(
            "idl account position expected {position}"
        )));
    }
    let s = a
        .get("outerSigner")
        .and_then(|v| v.as_bool())
        .ok_or_else(|| ClientError::AbiJoin("idl outerSigner".into()))?;
    let w = a
        .get("outerWritable")
        .and_then(|v| v.as_bool())
        .ok_or_else(|| ClientError::AbiJoin("idl outerWritable".into()))?;
    if s != signer || w != writable {
        return Err(ClientError::AbiJoin(format!(
            "idl account flags mismatch pos={position}"
        )));
    }
    Ok(())
}
