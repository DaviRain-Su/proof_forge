//! Public verification orchestration: OutputSet → profile → optional program adapter.

use std::path::{Path, PathBuf};

use crate::error::ClientError;
use crate::output_set::{
    cpi_elf_expected_leaves, load_and_verify_output_set, LoadedOutputSet, ManifestV1,
};
use crate::profile::{dispatch_profile, ProfileJoinResult};
use crate::program_adapter::{apply_program_adapter, ProgramAdapterId};

// Re-exports for tests / library consumers.
pub use crate::output_set::{
    read_regular_single_link_file, recompute_output_set_digest, EvidenceV1, ManifestFileEntry,
    IR_DIGEST_DOMAIN, MAX_ARTIFACT_FILES, MAX_FILE_BYTES, MAX_TOTAL_BYTES, OUTPUT_SET_DOMAIN,
    PLAN_DIGEST_DOMAIN,
};

/// Canonical TransferSol CPI leaves (compat helper for fixture builders).
pub fn transfer_sol_canonical_leaves() -> Vec<(String, String)> {
    cpi_elf_expected_leaves(crate::constants::TRANSFER_SOL_PROGRAM_NAME)
}

/// Static array form used by older offline suite helpers.
pub const CANONICAL_LEAVES: [(&str, &str); 6] = [
    ("TransferSol.cpi-bindings.json", "materialized-base"),
    ("TransferSol.cpi-ir.json", "materialized-base"),
    ("TransferSol.cpi-plan.json", "materialized-base"),
    ("TransferSol.idl.json", "materialized-base"),
    ("TransferSol.s", "materialized-base"),
    ("TransferSol.so", "finalized-extra"),
];

/// Full verification result after OutputSet + profile (+ optional program) joins.
#[derive(Debug, Clone)]
pub struct VerifiedArtifact {
    pub dir: PathBuf,
    pub manifest: ManifestV1,
    pub profile_id: String,
    pub program_adapter: Option<String>,
    pub trust_anchor: String,
    pub verification_scope: String,
    pub so_path: Option<PathBuf>,
    pub so_bytes: Option<Vec<u8>>,
    pub so_sha256_hex: Option<String>,
    pub plan_digest_hex: String,
    pub profile_digest_hex: Option<String>,
    pub catalog_digest_hex: Option<String>,
    pub ir_digest_hex: Option<String>,
}

const GENERIC_SCOPE: &str = "output-set-self-consistency+known-profile-joins";
const GENERIC_TRUST: &str = "manifest-bound-self-consistency (not signed provenance)";

/// Generic verification: no program adapter selected.
pub fn verify_solana_artifact(artifact_dir: &Path) -> Result<VerifiedArtifact, ClientError> {
    verify_solana_artifact_with_adapter(artifact_dir, None)
}

/// Verification with optional program adapter.
pub fn verify_solana_artifact_with_adapter(
    artifact_dir: &Path,
    program_adapter: Option<ProgramAdapterId>,
) -> Result<VerifiedArtifact, ClientError> {
    let loaded = load_and_verify_output_set(artifact_dir)?;
    let profile = dispatch_profile(&loaded)?;
    if let Some(adapter) = program_adapter {
        apply_program_adapter(&loaded, &profile, adapter)?;
    }
    Ok(build_verified(loaded, profile, program_adapter))
}

fn build_verified(
    loaded: LoadedOutputSet,
    profile: ProfileJoinResult,
    program_adapter: Option<ProgramAdapterId>,
) -> VerifiedArtifact {
    let (program_adapter_s, trust) = match program_adapter {
        Some(a) => (
            Some(a.as_str().to_string()),
            a.trust_anchor_note().to_string(),
        ),
        None => (None, GENERIC_TRUST.to_string()),
    };
    let so_path = profile.so_path.as_ref().map(|p| loaded.dir.join(p));
    VerifiedArtifact {
        dir: loaded.dir,
        manifest: loaded.manifest,
        profile_id: profile.profile_id,
        program_adapter: program_adapter_s,
        trust_anchor: trust,
        verification_scope: GENERIC_SCOPE.to_string(),
        so_path,
        so_bytes: profile.so_bytes,
        so_sha256_hex: profile.so_sha256_hex,
        plan_digest_hex: profile.plan_digest_hex,
        profile_digest_hex: profile.profile_digest_hex,
        catalog_digest_hex: profile.catalog_digest_hex,
        ir_digest_hex: profile.ir_digest_hex,
    }
}

/// TransferSol product path with frozen sourceHash + ABI pins (explicit adapter).
pub fn verify_transfer_sol_artifact(artifact_dir: &Path) -> Result<VerifiedArtifact, ClientError> {
    verify_solana_artifact_with_adapter(artifact_dir, Some(ProgramAdapterId::TransferSolV1))
}

/// Test helper: TransferSol adapter path but with an alternate expected sourceHash
/// (used only to prove trust-anchor fail-closed; CLI has no override flag).
pub fn verify_transfer_sol_artifact_with_source_hash(
    artifact_dir: &Path,
    expected_source_hash: &str,
) -> Result<VerifiedArtifact, ClientError> {
    crate::util::require_bare_hex64("expected_source_hash", expected_source_hash)?;
    let loaded = load_and_verify_output_set(artifact_dir)?;
    if loaded.manifest.source_hash != expected_source_hash {
        return Err(ClientError::Artifact(format!(
            "sourceHash trust-anchor mismatch: actual={} expected={}",
            loaded.manifest.source_hash, expected_source_hash
        )));
    }
    // Still require full TransferSol adapter when source matches expected helper pin.
    let profile = dispatch_profile(&loaded)?;
    apply_program_adapter(&loaded, &profile, ProgramAdapterId::TransferSolV1)?;
    Ok(build_verified(
        loaded,
        profile,
        Some(ProgramAdapterId::TransferSolV1),
    ))
}
