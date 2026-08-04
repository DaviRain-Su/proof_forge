//! Offline artifact verification entrypoint and JSON rendering.

use std::path::Path;

use serde_json::json;

use crate::artifact::{verify_transfer_sol_artifact, VerifiedArtifact};
use crate::error::ClientError;

pub fn run_verify_artifacts(artifact_dir: &Path) -> Result<VerifiedArtifact, ClientError> {
    verify_transfer_sol_artifact(artifact_dir)
}

pub fn print_verify_json(v: &VerifiedArtifact) -> Result<(), ClientError> {
    let out = json!({
        "ok": true,
        "command": "verify-artifacts",
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
        "soPath": v.so_path.display().to_string(),
        "maturity": {
            "formal": false,
            "hermetic": false,
            "networkWrite": false,
            "deploymentPerformed": false,
            "note": "Offline OutputSet exact-closure + domain digests + ABI join only. Local execution is verified separately by Mollusk."
        }
    });
    println!(
        "{}",
        serde_json::to_string_pretty(&out).map_err(|e| ClientError::Internal(e.to_string()))?
    );
    Ok(())
}
