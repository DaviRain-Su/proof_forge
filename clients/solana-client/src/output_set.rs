//! Generic `proof-forge.output.v1` Solana OutputSet verifier.
//!
//! Validates manifest/evidence exact schema, closed roles, canonical role/path
//! order, safe relative paths, exact disk closure, no-follow/single-link/bounded
//! reads, leaf/evidence hashes, and the engineering output-set digest.
//!
//! Does **not** hardcode TransferSol filenames, sourceHash, or ABI pins.

use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Read;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::constants::{
    EVIDENCE_NAME, EXPECTED_SCHEMA_VERSION, EXPECTED_TARGET, MANIFEST_NAME, ROLE_FINALIZED_EXTRA,
    ROLE_MATERIALIZED_BASE,
};
use crate::error::ClientError;
use crate::util::{
    domain_separated_sha256_hex, encode_string_framed, encode_u32le, encode_u64le,
    parse_json_no_dups, require_bare_hex64, sha256_hex,
};

pub const MAX_ARTIFACT_FILES: usize = 1024;
pub const MAX_ARTIFACT_PATH_BYTES: usize = 240;
pub const MAX_FILE_BYTES: u64 = 64 * 1024 * 1024;
pub const MAX_TOTAL_BYTES: u64 = 256 * 1024 * 1024;

pub const PLAN_DIGEST_DOMAIN: &str = "pf.solana.cpi-plan.v1";
pub const IR_DIGEST_DOMAIN: &str = "pf.solana.cpi-product-ir.v1";
/// Domain for full-body hybrid marker `*.cpi-ir.json` (P3-g).
pub const FULL_BODY_HYBRID_IR_DIGEST_DOMAIN: &str = "pf.solana.full-body-hybrid-ir.v1";
pub const OUTPUT_SET_DOMAIN: &str = "pf.output-set.engineering.v1";

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

/// Loaded OutputSet after generic self-consistency checks (pre-profile joins).
#[derive(Debug, Clone)]
pub struct LoadedOutputSet {
    pub dir: PathBuf,
    pub manifest: ManifestV1,
    pub evidence: EvidenceV1,
    /// Leaf path → bytes, in manifest `files` order.
    pub leaf_bytes: Vec<(String, Vec<u8>)>,
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

fn role_rank(role: &str) -> Result<u8, ClientError> {
    match role {
        ROLE_MATERIALIZED_BASE => Ok(0),
        ROLE_FINALIZED_EXTRA => Ok(1),
        other => Err(ClientError::Artifact(format!(
            "unknown artifact role (closed set): {other}"
        ))),
    }
}

fn require_safe_relative_path(path: &str) -> Result<(), ClientError> {
    let has_control = path.chars().any(|c| (c as u32) < 0x20);
    if path.is_empty()
        || path.len() > MAX_ARTIFACT_PATH_BYTES
        || path.contains('/')
        || path.contains('\\')
        || path.contains("..")
        || path == "."
        || path == ".."
        || has_control
    {
        return Err(ClientError::Artifact(format!(
            "leaf path must be a safe basename of at most {MAX_ARTIFACT_PATH_BYTES} UTF-8 bytes: {path:?}"
        )));
    }
    Ok(())
}

/// Recompute engineering `outputSetDigest` (role/path order as listed).
pub fn recompute_output_set_digest(m: &ManifestV1) -> Result<String, ClientError> {
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

/// Generic OutputSet self-consistency load (no profile/program pins).
pub fn load_and_verify_output_set(artifact_dir: &Path) -> Result<LoadedOutputSet, ClientError> {
    let stamp = lstat_real_dir(artifact_dir)?;

    let manifest_path = artifact_dir.join(MANIFEST_NAME);
    let evidence_path = artifact_dir.join(EVIDENCE_NAME);
    let manifest_bytes = read_regular_single_link_file(&manifest_path)?;
    let evidence_bytes = read_regular_single_link_file(&evidence_path)?;

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

    require_eq(
        "schemaVersion",
        &manifest.schema_version,
        EXPECTED_SCHEMA_VERSION,
    )?;
    require_eq("target", &manifest.target, EXPECTED_TARGET)?;
    if manifest.artifact_program_name.is_empty() {
        return Err(ClientError::Artifact(
            "artifactProgramName must be non-empty".into(),
        ));
    }
    if manifest.codegen_profile.is_empty() {
        return Err(ClientError::Artifact(
            "codegenProfile must be non-empty".into(),
        ));
    }

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

    // Evidence join (identity only — no program/source pin).
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

    if manifest.files.is_empty() {
        return Err(ClientError::Artifact(
            "manifest.files must be non-empty".into(),
        ));
    }
    let max_manifest_leaves = MAX_ARTIFACT_FILES.saturating_sub(2);
    if manifest.files.len() > max_manifest_leaves {
        return Err(ClientError::Artifact(format!(
            "manifest declares too many artifact leaves ({} > {max_manifest_leaves}); closure cap includes manifest.json and evidence.json",
            manifest.files.len()
        )));
    }

    // Closed roles, safe paths, content digests, and canonical role/path order.
    let mut prev_rank: Option<u8> = None;
    let mut prev_path: Option<&str> = None;
    let mut seen_paths = BTreeMap::new();
    for (i, e) in manifest.files.iter().enumerate() {
        let rank = role_rank(&e.role)?;
        require_safe_relative_path(&e.path)?;
        require_bare_hex64(&format!("files[{i}].contentSha256"), &e.content_sha256)?;
        if seen_paths.insert(e.path.clone(), ()).is_some() {
            return Err(ClientError::Artifact(format!(
                "duplicate leaf path in manifest: {}",
                e.path
            )));
        }
        if let Some(pr) = prev_rank {
            if rank < pr || (rank == pr && prev_path.map(|p| e.path.as_str() <= p).unwrap_or(false))
            {
                return Err(ClientError::Artifact(format!(
                    "files[{i}] breaks canonical role/path order: role={} path={}",
                    e.role, e.path
                )));
            }
        }
        prev_rank = Some(rank);
        prev_path = Some(e.path.as_str());
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
    for f in &manifest.files {
        expected_names.push(f.path.clone());
    }
    expected_names.sort();
    if on_disk_names != expected_names {
        return Err(ClientError::Artifact(format!(
            "exact disk closure failed: on_disk={on_disk_names:?} expected={expected_names:?}"
        )));
    }

    // Read + hash each leaf.
    let mut leaf_bytes: Vec<(String, Vec<u8>)> = Vec::new();
    for entry in &manifest.files {
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
    }

    let recomputed_osd = recompute_output_set_digest(&manifest)?;
    if recomputed_osd != manifest.output_set_digest {
        return Err(ClientError::Artifact(format!(
            "outputSetDigest recompute mismatch: actual={recomputed_osd} manifest={}",
            manifest.output_set_digest
        )));
    }

    assert_stamp_stable(artifact_dir, &stamp)?;

    Ok(LoadedOutputSet {
        dir: artifact_dir.to_path_buf(),
        manifest,
        evidence,
        leaf_bytes,
    })
}

/// Look up leaf bytes by exact basename.
pub fn leaf_bytes_by_name<'a>(loaded: &'a LoadedOutputSet, name: &str) -> Option<&'a [u8]> {
    loaded
        .leaf_bytes
        .iter()
        .find(|(p, _)| p == name)
        .map(|(_, b)| b.as_slice())
}

/// Expected CPI leaf basenames for `program_name` in canonical role/path order.
pub fn cpi_elf_expected_leaves(program_name: &str) -> Vec<(String, String)> {
    let base = |suffix: &str| format!("{program_name}{suffix}");
    vec![
        (base(".cpi-bindings.json"), ROLE_MATERIALIZED_BASE.into()),
        (base(".cpi-ir.json"), ROLE_MATERIALIZED_BASE.into()),
        (base(".cpi-plan.json"), ROLE_MATERIALIZED_BASE.into()),
        (base(".idl.json"), ROLE_MATERIALIZED_BASE.into()),
        (base(".s"), ROLE_MATERIALIZED_BASE.into()),
        (base(".so"), ROLE_FINALIZED_EXTRA.into()),
    ]
}

/// Expected plan-profile leaves (canonical role/path order).
pub fn plan_expected_leaves(program_name: &str) -> Vec<(String, String)> {
    // UTF-8 path order within materialized-base: .idl.json before .sbpf-plan.
    vec![
        (
            format!("{program_name}.idl.json"),
            ROLE_MATERIALIZED_BASE.into(),
        ),
        (
            format!("{program_name}.sbpf-plan"),
            ROLE_MATERIALIZED_BASE.into(),
        ),
    ]
}

/// Expected elf-profile leaves (canonical role/path order).
pub fn elf_expected_leaves(program_name: &str) -> Vec<(String, String)> {
    vec![
        (
            format!("{program_name}.idl.json"),
            ROLE_MATERIALIZED_BASE.into(),
        ),
        (format!("{program_name}.s"), ROLE_MATERIALIZED_BASE.into()),
        (
            format!("{program_name}.sbpf-plan"),
            ROLE_MATERIALIZED_BASE.into(),
        ),
        (format!("{program_name}.so"), ROLE_FINALIZED_EXTRA.into()),
    ]
}

pub fn require_exact_leaf_shape(
    loaded: &LoadedOutputSet,
    expected: &[(String, String)],
) -> Result<(), ClientError> {
    if loaded.manifest.files.len() != expected.len() {
        return Err(ClientError::Artifact(format!(
            "expected exactly {} manifest leaves for profile/program shape, got {}",
            expected.len(),
            loaded.manifest.files.len()
        )));
    }
    for (i, (want_path, want_role)) in expected.iter().enumerate() {
        let e = &loaded.manifest.files[i];
        if e.path != *want_path || e.role != *want_role {
            return Err(ClientError::Artifact(format!(
                "files[{i}] must be role={want_role} path={want_path}, got role={} path={}",
                e.role, e.path
            )));
        }
    }
    Ok(())
}
