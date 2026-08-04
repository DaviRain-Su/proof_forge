//! Independent `proof-forge.output.v1` exact-closure + domain digests + ABI joins.

use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Read;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde_json::Value;

use crate::constants::{
    BINDINGS_SCHEMA, CATALOG_DIGEST_HEX, DEFAULT_EXPECTED_SOURCE_HASH, EVIDENCE_NAME,
    EXPECTED_PROFILE, EXPECTED_PROGRAM_NAME, EXPECTED_SCHEMA_VERSION, EXPECTED_TARGET,
    EXTENSION_DIGEST_HEX, EXTENSION_ID, EXTENSION_VERSION, IDL_SCHEMA, IR_SCHEMA_LINE,
    MANIFEST_NAME, PLAN_SCHEMA, PROFILE_DIGEST_HEX, SYSTEM_PACKAGE_ID, SYSTEM_PROGRAM_BASE58,
    SYSTEM_PROGRAM_ID_HEX, SYSTEM_RUNTIME_NATIVE_BINDING,
};
use crate::error::ClientError;
use crate::util::{
    domain_separated_sha256_hex, encode_string_framed, encode_u32le, encode_u64le,
    parse_json_no_dups, require_bare_hex64, require_sha256_wire, sha256_hex,
};

pub const MAX_ARTIFACT_FILES: usize = 1024;
pub const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;
pub const MAX_TOTAL_BYTES: u64 = 256 * 1024 * 1024;

pub const PLAN_DIGEST_DOMAIN: &str = "pf.solana.cpi-plan.v1";
pub const IR_DIGEST_DOMAIN: &str = "pf.solana.cpi-product-ir.v1";
pub const OUTPUT_SET_DOMAIN: &str = "pf.output-set.engineering.v1";

/// Canonical leaf order for TransferSol product OutputSet.
pub const CANONICAL_LEAVES: [(&str, &str); 6] = [
    ("TransferSol.cpi-bindings.json", "materialized-base"),
    ("TransferSol.cpi-ir.json", "materialized-base"),
    ("TransferSol.cpi-plan.json", "materialized-base"),
    ("TransferSol.idl.json", "materialized-base"),
    ("TransferSol.s", "materialized-base"),
    ("TransferSol.so", "finalized-extra"),
];

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ManifestFileEntry {
    pub role: String,
    pub path: String,
    pub size: u64,
    pub content_sha256: String,
}

/// Exact 14-key engineering manifest (deny_unknown_fields).
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ManifestV1 {
    pub schema_version: String,
    pub target: String,
    pub codegen_profile: String,
    pub artifact_program_name: String,
    pub source_hash: String,
    pub semantic_hash: String,
    pub build_identity_digest: String,
    pub plan_digest: String,
    pub support_claim_digest: String,
    pub engineering_registry_root_digest: String,
    pub output_set_digest: String,
    pub evidence_sha256: String,
    pub deployable: bool,
    pub files: Vec<ManifestFileEntry>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EvidenceV1 {
    pub target: String,
    pub source_hash: String,
    pub semantic_hash: String,
    pub deployable: bool,
    pub note: String,
}

#[derive(Debug, Clone)]
pub struct VerifiedArtifact {
    pub dir: PathBuf,
    pub manifest: ManifestV1,
    pub so_path: PathBuf,
    pub so_bytes: Vec<u8>,
    pub so_sha256_hex: String,
    pub plan_digest_hex: String,
    pub profile_digest_hex: String,
    pub catalog_digest_hex: String,
    pub ir_digest_hex: String,
}

#[derive(Clone, Debug)]
struct DirStamp {
    dev: u64,
    ino: u64,
    nlink: u64,
    mode: u32,
}

fn lstat_real_dir(path: &Path) -> Result<DirStamp, ClientError> {
    let meta = fs::symlink_metadata(path).map_err(|e| {
        ClientError::Artifact(format!("lstat artifact-dir {}: {e}", path.display()))
    })?;
    if meta.file_type().is_symlink() {
        return Err(ClientError::Artifact(format!(
            "artifact-dir must not be a symlink: {}",
            path.display()
        )));
    }
    if !meta.is_dir() {
        return Err(ClientError::Artifact(format!(
            "artifact-dir is not a directory: {}",
            path.display()
        )));
    }
    Ok(DirStamp {
        dev: meta.dev(),
        ino: meta.ino(),
        nlink: meta.nlink(),
        mode: meta.mode(),
    })
}

fn assert_stamp_stable(path: &Path, before: &DirStamp) -> Result<(), ClientError> {
    let after = lstat_real_dir(path)?;
    if after.dev != before.dev
        || after.ino != before.ino
        || after.nlink != before.nlink
        || after.mode != before.mode
    {
        return Err(ClientError::Artifact(
            "artifact-dir identity changed during read (TOCTOU)".into(),
        ));
    }
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct FileStamp {
    dev: u64,
    ino: u64,
    mode: u32,
    nlink: u64,
    len: u64,
    mtime: i64,
    mtime_nsec: i64,
}

fn regular_single_link_stamp_from_meta(
    path: &Path,
    meta: &fs::Metadata,
) -> Result<FileStamp, ClientError> {
    if meta.file_type().is_symlink() {
        return Err(ClientError::Artifact(format!(
            "symlink rejected: {}",
            path.display()
        )));
    }
    if !meta.is_file() {
        return Err(ClientError::Artifact(format!(
            "not a regular file: {}",
            path.display()
        )));
    }
    if meta.nlink() != 1 {
        return Err(ClientError::Artifact(format!(
            "hardlink/multi-link rejected (nlink={}): {}",
            meta.nlink(),
            path.display()
        )));
    }
    if meta.len() > MAX_FILE_BYTES {
        return Err(ClientError::Artifact(format!(
            "file exceeds 64MiB cap: {}",
            path.display()
        )));
    }
    Ok(FileStamp {
        dev: meta.dev(),
        ino: meta.ino(),
        mode: meta.mode(),
        nlink: meta.nlink(),
        len: meta.len(),
        mtime: meta.mtime(),
        mtime_nsec: meta.mtime_nsec(),
    })
}

fn regular_single_link_stamp(path: &Path) -> Result<FileStamp, ClientError> {
    let meta = fs::symlink_metadata(path)
        .map_err(|e| ClientError::Artifact(format!("lstat {}: {e}", path.display())))?;
    regular_single_link_stamp_from_meta(path, &meta)
}

/// Open and read a regular, non-symlink, single hard-link file through the same
/// descriptor. `O_NOFOLLOW` closes the lstat→open symlink race, and `take` makes
/// the 64 MiB limit an allocation/read bound rather than only a metadata check.
pub fn read_regular_single_link_file(path: &Path) -> Result<Vec<u8>, ClientError> {
    let path_before = regular_single_link_stamp(path)?;
    let mut file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)
        .map_err(|e| ClientError::Artifact(format!("open no-follow {}: {e}", path.display())))?;
    let fd_before_meta = file
        .metadata()
        .map_err(|e| ClientError::Artifact(format!("fstat {}: {e}", path.display())))?;
    let fd_before = regular_single_link_stamp_from_meta(path, &fd_before_meta)?;
    if fd_before != path_before {
        return Err(ClientError::Artifact(format!(
            "file identity changed between lstat and no-follow open: {}",
            path.display()
        )));
    }

    let expected_len = usize::try_from(fd_before.len)
        .map_err(|_| ClientError::Artifact(format!("file length overflow: {}", path.display())))?;
    let mut bytes = Vec::new();
    bytes.try_reserve_exact(expected_len).map_err(|e| {
        ClientError::Artifact(format!(
            "reserve bounded file buffer {}: {e}",
            path.display()
        ))
    })?;
    (&mut file)
        .take(MAX_FILE_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| ClientError::Artifact(format!("bounded read {}: {e}", path.display())))?;
    if bytes.len() as u64 > MAX_FILE_BYTES {
        return Err(ClientError::Artifact(format!(
            "file grew beyond 64MiB during bounded read: {}",
            path.display()
        )));
    }

    let fd_after_meta = file
        .metadata()
        .map_err(|e| ClientError::Artifact(format!("fstat after read {}: {e}", path.display())))?;
    let fd_after = regular_single_link_stamp_from_meta(path, &fd_after_meta)?;
    let path_after = regular_single_link_stamp(path)?;
    if fd_before != fd_after || fd_before != path_after || bytes.len() as u64 != fd_before.len {
        return Err(ClientError::Artifact(format!(
            "file changed during stable bounded read: {}",
            path.display()
        )));
    }
    Ok(bytes)
}

fn require_eq(field: &str, actual: &str, expected: &str) -> Result<(), ClientError> {
    if actual != expected {
        return Err(ClientError::Artifact(format!(
            "{field} mismatch: actual={actual} expected={expected}"
        )));
    }
    Ok(())
}

fn require_digest_wire_eq(
    field: &str,
    actual_wire: &str,
    expected_hex: &str,
) -> Result<(), ClientError> {
    let bare = require_sha256_wire(field, actual_wire)?;
    if bare != expected_hex {
        return Err(ClientError::AbiJoin(format!(
            "{field} digest mismatch: actual=sha256:{bare} expected=sha256:{expected_hex}"
        )));
    }
    Ok(())
}

/// Product entry: sourceHash trust anchor is the frozen TransferSol pin only.
pub fn verify_transfer_sol_artifact(artifact_dir: &Path) -> Result<VerifiedArtifact, ClientError> {
    verify_transfer_sol_artifact_with_source_hash(artifact_dir, DEFAULT_EXPECTED_SOURCE_HASH)
}

/// Test/library helper allowing an alternate expected sourceHash.
pub fn verify_transfer_sol_artifact_with_source_hash(
    artifact_dir: &Path,
    expected_source_hash: &str,
) -> Result<VerifiedArtifact, ClientError> {
    require_bare_hex64("expected_source_hash", expected_source_hash)?;
    let stamp = lstat_real_dir(artifact_dir)?;

    let manifest_path = artifact_dir.join(MANIFEST_NAME);
    let evidence_path = artifact_dir.join(EVIDENCE_NAME);
    let manifest_bytes = read_regular_single_link_file(&manifest_path)?;
    let evidence_bytes = read_regular_single_link_file(&evidence_path)?;

    // Strict JSON (no duplicate keys) before typed decode.
    let _manifest_v = parse_json_no_dups(&manifest_bytes)?;
    let _evidence_v = parse_json_no_dups(&evidence_bytes)?;

    let manifest: ManifestV1 = serde_json::from_slice(&manifest_bytes).map_err(|e| {
        ClientError::Artifact(format!(
            "manifest.json typed parse (14-key deny_unknown): {e}"
        ))
    })?;
    let evidence: EvidenceV1 = serde_json::from_slice(&evidence_bytes).map_err(|e| {
        ClientError::Artifact(format!(
            "evidence.json typed parse (5-key deny_unknown): {e}"
        ))
    })?;

    // Identity fields.
    require_eq(
        "schemaVersion",
        &manifest.schema_version,
        EXPECTED_SCHEMA_VERSION,
    )?;
    require_eq("target", &manifest.target, EXPECTED_TARGET)?;
    require_eq(
        "codegenProfile",
        &manifest.codegen_profile,
        EXPECTED_PROFILE,
    )?;
    require_eq(
        "artifactProgramName",
        &manifest.artifact_program_name,
        EXPECTED_PROGRAM_NAME,
    )?;
    if !manifest.deployable {
        return Err(ClientError::Artifact(
            "deployable must be true for TransferSol product ELF verification".into(),
        ));
    }

    // All bare digests: strict lowercase 64-hex.
    for (name, val) in [
        ("sourceHash", manifest.source_hash.as_str()),
        ("semanticHash", manifest.semantic_hash.as_str()),
        (
            "buildIdentityDigest",
            manifest.build_identity_digest.as_str(),
        ),
        ("planDigest", manifest.plan_digest.as_str()),
        ("supportClaimDigest", manifest.support_claim_digest.as_str()),
        (
            "engineeringRegistryRootDigest",
            manifest.engineering_registry_root_digest.as_str(),
        ),
        ("outputSetDigest", manifest.output_set_digest.as_str()),
        ("evidenceSha256", manifest.evidence_sha256.as_str()),
    ] {
        require_bare_hex64(name, val)?;
    }

    if manifest.source_hash != expected_source_hash {
        return Err(ClientError::Artifact(format!(
            "sourceHash trust-anchor mismatch: actual={} expected={}",
            manifest.source_hash, expected_source_hash
        )));
    }

    // Evidence join.
    require_eq("evidence.target", &evidence.target, &manifest.target)?;
    require_eq(
        "evidence.sourceHash",
        &evidence.source_hash,
        &manifest.source_hash,
    )?;
    require_eq(
        "evidence.semanticHash",
        &evidence.semantic_hash,
        &manifest.semantic_hash,
    )?;
    if evidence.deployable != manifest.deployable {
        return Err(ClientError::Artifact(
            "evidence.deployable diverges from manifest".into(),
        ));
    }
    let evidence_hash = sha256_hex(&evidence_bytes);
    if evidence_hash != manifest.evidence_sha256 {
        return Err(ClientError::Artifact(format!(
            "evidenceSha256 mismatch: manifest={} actual={}",
            manifest.evidence_sha256, evidence_hash
        )));
    }

    // Exact six leaves, canonical order.
    if manifest.files.len() != 6 {
        return Err(ClientError::Artifact(format!(
            "expected exactly 6 manifest leaves, got {}",
            manifest.files.len()
        )));
    }
    for (i, (want_path, want_role)) in CANONICAL_LEAVES.iter().enumerate() {
        let e = &manifest.files[i];
        if e.path != *want_path || e.role != *want_role {
            return Err(ClientError::Artifact(format!(
                "files[{i}] must be role={want_role} path={want_path}, got role={} path={}",
                e.role, e.path
            )));
        }
        // Exact 4-key descriptor already enforced by deny_unknown_fields on ManifestFileEntry.
        require_bare_hex64(&format!("files[{i}].contentSha256"), &e.content_sha256)?;
        if e.path.contains('/') || e.path.contains('\\') || e.path.contains("..") {
            return Err(ClientError::Artifact(format!(
                "leaf path must be basename only: {}",
                e.path
            )));
        }
    }

    // Directory inventory: every entry is a regular single-link UTF-8 name file; exact closure.
    let mut on_disk_names: Vec<String> = Vec::new();
    let mut total: u64 = 0;
    let mut entry_count = 0usize;
    for ent in fs::read_dir(artifact_dir)
        .map_err(|e| ClientError::Artifact(format!("read_dir {}: {e}", artifact_dir.display())))?
    {
        let ent = ent.map_err(|e| ClientError::Artifact(format!("dir entry: {e}")))?;
        entry_count += 1;
        if entry_count > MAX_ARTIFACT_FILES {
            return Err(ClientError::Artifact(
                "artifact-dir exceeds 1024 entries cap".into(),
            ));
        }
        let os_name = ent.file_name();
        let name = os_name
            .to_str()
            .ok_or_else(|| ClientError::Artifact("non-UTF8 directory entry".into()))?
            .to_string();
        if name == "." || name == ".." {
            continue;
        }
        let p = ent.path();
        let meta = fs::symlink_metadata(&p)
            .map_err(|e| ClientError::Artifact(format!("stat {}: {e}", p.display())))?;
        if meta.file_type().is_symlink() {
            return Err(ClientError::Artifact(format!("symlink rejected: {name}")));
        }
        if meta.is_dir() {
            return Err(ClientError::Artifact(format!(
                "subdirectory rejected: {name}"
            )));
        }
        if !meta.is_file() {
            return Err(ClientError::Artifact(format!(
                "non-regular entry rejected: {name}"
            )));
        }
        if meta.nlink() != 1 {
            return Err(ClientError::Artifact(format!(
                "hardlink rejected: {name} nlink={}",
                meta.nlink()
            )));
        }
        if meta.len() > MAX_FILE_BYTES {
            return Err(ClientError::Artifact(format!("file exceeds 64MiB: {name}")));
        }
        total = total.saturating_add(meta.len());
        if total > MAX_TOTAL_BYTES {
            return Err(ClientError::Artifact(
                "artifact-dir total size exceeds 256MiB".into(),
            ));
        }
        on_disk_names.push(name);
    }
    on_disk_names.sort();

    let mut expected_names: Vec<String> = vec![MANIFEST_NAME.into(), EVIDENCE_NAME.into()];
    for (path, _) in &CANONICAL_LEAVES {
        expected_names.push((*path).into());
    }
    expected_names.sort();
    if on_disk_names != expected_names {
        return Err(ClientError::Artifact(format!(
            "exact disk closure failed: on_disk={on_disk_names:?} expected={expected_names:?}"
        )));
    }

    // Read + hash each leaf.
    let mut leaf_bytes: Vec<(String, Vec<u8>)> = Vec::new();
    for (i, entry) in manifest.files.iter().enumerate() {
        let p = artifact_dir.join(&entry.path);
        let bytes = read_regular_single_link_file(&p)?;
        if bytes.len() as u64 != entry.size {
            return Err(ClientError::Artifact(format!(
                "size mismatch for {}: actual={} expected={}",
                entry.path,
                bytes.len(),
                entry.size
            )));
        }
        let hash = sha256_hex(&bytes);
        if hash != entry.content_sha256 {
            return Err(ClientError::Artifact(format!(
                "contentSha256 mismatch for {}: actual={} expected={}",
                entry.path, hash, entry.content_sha256
            )));
        }
        leaf_bytes.push((entry.path.clone(), bytes));
        let _ = i;
    }

    let so_bytes = leaf_bytes[5].1.clone();
    if so_bytes.len() < 4 || &so_bytes[0..4] != b"\x7fELF" {
        return Err(ClientError::Artifact(
            "TransferSol.so must begin with 7fELF".into(),
        ));
    }

    // Domain digests.
    let plan_bytes = &leaf_bytes[2].1;
    let ir_bytes = &leaf_bytes[1].1;
    let plan_digest = domain_separated_sha256_hex(PLAN_DIGEST_DOMAIN, plan_bytes);
    if plan_digest != manifest.plan_digest {
        return Err(ClientError::Artifact(format!(
            "planDigest domain recompute mismatch: actual={plan_digest} manifest={}",
            manifest.plan_digest
        )));
    }
    let ir_digest = domain_separated_sha256_hex(IR_DIGEST_DOMAIN, ir_bytes);
    validate_evidence_note(&evidence.note, &manifest, &ir_digest)?;

    // Recompute outputSetDigest (Lean order).
    let recomputed_osd = recompute_output_set_digest(&manifest)?;
    if recomputed_osd != manifest.output_set_digest {
        return Err(ClientError::Artifact(format!(
            "outputSetDigest recompute mismatch: actual={recomputed_osd} manifest={}",
            manifest.output_set_digest
        )));
    }

    // Parse ABI documents (no dups).
    let plan_v = parse_json_no_dups(plan_bytes)?;
    let idl_v = parse_json_no_dups(&leaf_bytes[3].1)?;
    let bindings_v = parse_json_no_dups(&leaf_bytes[0].1)?;
    let ir_text = String::from_utf8(ir_bytes.clone())
        .map_err(|e| ClientError::AbiJoin(format!("ir utf-8: {e}")))?;
    let asm_text = String::from_utf8(leaf_bytes[4].1.clone())
        .map_err(|e| ClientError::AbiJoin(format!("assembly must be UTF-8: {e}")))?;

    let join = join_abi_artifacts(
        &manifest,
        &plan_v,
        &idl_v,
        &bindings_v,
        &ir_text,
        &asm_text,
        &ir_digest,
    )?;

    assert_stamp_stable(artifact_dir, &stamp)?;

    Ok(VerifiedArtifact {
        dir: artifact_dir.to_path_buf(),
        so_path: artifact_dir.join("TransferSol.so"),
        so_sha256_hex: sha256_hex(&so_bytes),
        so_bytes,
        plan_digest_hex: join.plan_digest_hex,
        profile_digest_hex: join.profile_digest_hex,
        catalog_digest_hex: join.catalog_digest_hex,
        ir_digest_hex: join.ir_digest_hex,
        manifest,
    })
}

fn recompute_output_set_digest(m: &ManifestV1) -> Result<String, ClientError> {
    let mut payload = Vec::new();
    payload.extend_from_slice(&encode_string_framed(&m.schema_version));
    payload.extend_from_slice(&encode_string_framed(&m.target));
    payload.extend_from_slice(&encode_string_framed(&m.codegen_profile));
    payload.extend_from_slice(&encode_string_framed(&m.artifact_program_name));
    payload.extend_from_slice(&encode_u32le(m.files.len() as u32));
    for f in &m.files {
        payload.extend_from_slice(&encode_string_framed(&f.role));
        payload.extend_from_slice(&encode_string_framed(&f.path));
        payload.extend_from_slice(&encode_u64le(f.size));
        payload.extend_from_slice(&encode_string_framed(&format!(
            "sha256:{}",
            f.content_sha256
        )));
    }
    for bare in [
        &m.source_hash,
        &m.semantic_hash,
        &m.engineering_registry_root_digest,
        &m.support_claim_digest,
        &m.build_identity_digest,
        &m.plan_digest,
    ] {
        payload.extend_from_slice(&encode_string_framed(&format!("sha256:{bare}")));
    }
    payload.extend_from_slice(&encode_string_framed(if m.deployable {
        "true"
    } else {
        "false"
    }));
    payload.extend_from_slice(&encode_string_framed(&format!(
        "sha256:{}",
        m.evidence_sha256
    )));
    Ok(domain_separated_sha256_hex(OUTPUT_SET_DOMAIN, &payload))
}

fn validate_evidence_note(
    note: &str,
    manifest: &ManifestV1,
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
    // Structured active profile / catalog / plan / ir digests.
    if !note.contains("profile=solana-sbpf-cpi-elf-v1") {
        return Err(ClientError::Artifact(
            "evidence.note missing active profile marker".into(),
        ));
    }
    if !note.contains(&format!("profileDigest=sha256:{PROFILE_DIGEST_HEX}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing profileDigest join".into(),
        ));
    }
    if !note.contains(&format!("catalogDigest=sha256:{CATALOG_DIGEST_HEX}")) {
        return Err(ClientError::Artifact(
            "evidence.note missing catalogDigest join".into(),
        ));
    }
    if !note.contains(&format!("planDigest=sha256:{}", manifest.plan_digest)) {
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

struct AbiJoin {
    plan_digest_hex: String,
    profile_digest_hex: String,
    catalog_digest_hex: String,
    ir_digest_hex: String,
}

fn join_abi_artifacts(
    manifest: &ManifestV1,
    plan: &Value,
    idl: &Value,
    bindings: &Value,
    ir_text: &str,
    asm_text: &str,
    expected_ir_digest: &str,
) -> Result<AbiJoin, ClientError> {
    // ---- Plan ----
    require_str(plan, "schema", PLAN_SCHEMA)?;
    require_str(plan, "programName", EXPECTED_PROGRAM_NAME)?;
    require_str(plan, "profileId", EXPECTED_PROFILE)?;
    require_digest_wire_eq(
        "plan.profileDigest",
        plan_str(plan, "profileDigest")?,
        PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "plan.calleeCatalogDigest",
        plan_str(plan, "calleeCatalogDigest")?,
        CATALOG_DIGEST_HEX,
    )?;

    let ext = plan
        .get("extensionRequirement")
        .ok_or_else(|| ClientError::AbiJoin("plan missing extensionRequirement".into()))?;
    require_str(ext, "id", EXTENSION_ID)?;
    require_str(ext, "version", EXTENSION_VERSION)?;
    require_digest_wire_eq(
        "plan.extensionRequirement.digest",
        plan_str(ext, "digest")?,
        EXTENSION_DIGEST_HEX,
    )?;
    if !as_array(ext, "predicates")?.is_empty() {
        return Err(ClientError::AbiJoin(
            "plan.extensionRequirement.predicates must be empty".into(),
        ));
    }

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
    for (i, r) in roles.iter().enumerate() {
        if r.get("roleId").and_then(|v| v.as_u64()) != Some(i as u64) {
            return Err(ClientError::AbiJoin(format!(
                "accountRoles[{i}].roleId must be {i}"
            )));
        }
    }
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
    // programKey: 64 zero hex (product wire is bare string).
    match site0.get("programKey") {
        Some(Value::String(s)) if s == SYSTEM_PROGRAM_ID_HEX => {}
        Some(Value::Object(o)) => {
            // Tolerate object form if present with exact hex.
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
    let assumptions = plan
        .get("computeAssumptions")
        .ok_or_else(|| ClientError::AbiJoin("plan.computeAssumptions missing".into()))?;
    require_str(
        assumptions,
        "implementationState",
        "product-exact-synchronous-call-active-v1",
    )?;

    // ---- Bindings ----
    require_str(bindings, "schema", BINDINGS_SCHEMA)?;
    require_str(bindings, "profileId", EXPECTED_PROFILE)?;
    require_digest_wire_eq(
        "bindings.profileDigest",
        plan_str(bindings, "profileDigest")?,
        PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "bindings.calleeCatalogDigest",
        plan_str(bindings, "calleeCatalogDigest")?,
        CATALOG_DIGEST_HEX,
    )?;
    let bind_plan = require_sha256_wire("bindings.planDigest", plan_str(bindings, "planDigest")?)?;
    if bind_plan != manifest.plan_digest {
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
    if pkgs.len() != 1 {
        return Err(ClientError::AbiJoin(
            "bindings.referencedPackages length must be 1".into(),
        ));
    }
    let sys = &pkgs[0];
    require_str(sys, "packageId", SYSTEM_PACKAGE_ID)?;
    require_str(sys, "programIdHex", SYSTEM_PROGRAM_ID_HEX)?;
    require_str(sys, "executionClass", "native-system")?;
    require_str(sys, "artifactBinding", SYSTEM_RUNTIME_NATIVE_BINDING)?;
    if sys
        .get("admittedForMaterialization")
        .and_then(|v| v.as_bool())
        != Some(true)
    {
        return Err(ClientError::AbiJoin(
            "system-v1 admittedForMaterialization must be true".into(),
        ));
    }

    // ---- IDL ----
    require_str(idl, "schema", IDL_SCHEMA)?;
    require_str(idl, "programName", EXPECTED_PROGRAM_NAME)?;
    require_str(idl, "profileId", EXPECTED_PROFILE)?;
    require_digest_wire_eq(
        "idl.profileDigest",
        plan_str(idl, "profileDigest")?,
        PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "idl.catalogDigest",
        plan_str(idl, "catalogDigest")?,
        CATALOG_DIGEST_HEX,
    )?;
    let idl_plan = require_sha256_wire("idl.planDigest", plan_str(idl, "planDigest")?)?;
    if idl_plan != manifest.plan_digest {
        return Err(ClientError::AbiJoin(
            "idl.planDigest != manifest.planDigest".into(),
        ));
    }
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

    // ---- IR text ----
    validate_ir_text(ir_text, &manifest.plan_digest, expected_ir_digest)?;

    // ---- Assembly ----
    validate_assembly(asm_text)?;

    Ok(AbiJoin {
        plan_digest_hex: manifest.plan_digest.clone(),
        profile_digest_hex: PROFILE_DIGEST_HEX.to_string(),
        catalog_digest_hex: CATALOG_DIGEST_HEX.to_string(),
        ir_digest_hex: expected_ir_digest.to_string(),
    })
}

fn validate_ir_text(
    ir_text: &str,
    plan_digest: &str,
    expected_ir_digest: &str,
) -> Result<(), ClientError> {
    let mut keys: BTreeMap<&str, &str> = BTreeMap::new();
    let mut handler_line: Option<&str> = None;
    for line in ir_text.lines() {
        if let Some((k, v)) = line.split_once('=') {
            if keys.insert(k, v).is_some() {
                return Err(ClientError::AbiJoin(format!("ir duplicate top key: {k}")));
            }
        } else if line.starts_with("handler:") {
            if handler_line.is_some() {
                return Err(ClientError::AbiJoin(
                    "ir must have exactly one handler line".into(),
                ));
            }
            handler_line = Some(line);
        } else if !line.is_empty() {
            return Err(ClientError::AbiJoin(format!("ir unexpected line: {line}")));
        }
    }
    // Exact required keys.
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
    if keys["schema"] != IR_SCHEMA_LINE {
        return Err(ClientError::AbiJoin("ir schema mismatch".into()));
    }
    if keys["profileId"] != EXPECTED_PROFILE {
        return Err(ClientError::AbiJoin("ir profileId mismatch".into()));
    }
    require_digest_wire_eq(
        "ir.profileDigest",
        keys["profileDigest"],
        PROFILE_DIGEST_HEX,
    )?;
    require_digest_wire_eq(
        "ir.catalogDigest",
        keys["catalogDigest"],
        CATALOG_DIGEST_HEX,
    )?;
    let ir_plan = require_sha256_wire("ir.sourcePlanDigest", keys["sourcePlanDigest"])?;
    if ir_plan != plan_digest {
        return Err(ClientError::AbiJoin(
            "ir.sourcePlanDigest != manifest.planDigest".into(),
        ));
    }
    // sourceIrDigest is internal IR identity (not product irDigest domain over full text).
    let _ = require_sha256_wire("ir.sourceIrDigest", keys["sourceIrDigest"])?;
    if keys["maxOuterRoles"] != "16" {
        return Err(ClientError::AbiJoin("ir maxOuterRoles must be 16".into()));
    }
    if keys["maxFrameBytes"] != "4096" {
        return Err(ClientError::AbiJoin("ir maxFrameBytes must be 4096".into()));
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
    // Cross-check product irDigest is the domain digest of full IR bytes (caller).
    let _ = expected_ir_digest;
    Ok(())
}

fn validate_assembly(asm: &str) -> Result<(), ClientError> {
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
