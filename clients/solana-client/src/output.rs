//! Offline artifact verification entrypoint and JSON rendering.

use std::path::Path;

use serde_json::json;

use crate::artifact::{verify_solana_artifact_with_adapter, VerifiedArtifact};
use crate::error::ClientError;
use crate::program_adapter::ProgramAdapterId;

pub fn run_verify_artifacts(
    artifact_dir: &Path,
    program_adapter: Option<ProgramAdapterId>,
) -> Result<VerifiedArtifact, ClientError> {
    verify_solana_artifact_with_adapter(artifact_dir, program_adapter)
}

pub fn print_verify_json(v: &VerifiedArtifact) -> Result<(), ClientError> {
    let out = json!({
        "ok": true,
        "command": "verify-artifacts",
        "verificationScope": v.verification_scope,
        "profileAdapter": v.profile_id,
        "programAdapter": v.program_adapter,
        "trustAnchor": v.trust_anchor,
        "artifactDir": v.dir.display().to_string(),
        "programName": v.manifest.artifact_program_name,
        "target": v.manifest.target,
        "codegenProfile": v.manifest.codegen_profile,
        "deployableArtifact": v.manifest.deployable,
        "sourceHash": v.manifest.source_hash,
        "semanticHash": v.manifest.semantic_hash,
        "planDigest": v.plan_digest_hex,
        "profileDigest": v.profile_digest_hex,
        "catalogDigest": v.catalog_digest_hex,
        "irDigest": v.ir_digest_hex,
        "outputSetDigest": v.manifest.output_set_digest,
        "soSha256": v.so_sha256_hex,
        "soPath": v.so_path.as_ref().map(|p| p.display().to_string()),
        "maturity": {
            "formal": false,
            "hermetic": false,
            "networkWrite": false,
            "deploymentPerformed": false,
            "signedProvenance": false,
            "note": "Offline OutputSet exact-closure + known profile joins only. Not signed provenance, formal proof, or hermetic attestation. Local execution is verified separately by Mollusk for product fixtures."
        }
    });
    println!(
        "{}",
        serde_json::to_string_pretty(&out).map_err(|e| ClientError::Internal(e.to_string()))?
    );
    Ok(())
}
