//! Noir deploy packaging (save-only).
//!
//! Circuits are not chain-deployed by pf. This writes a package pointing at
//! the built relations/ACIR artifacts for external provers / nargo workflows.
//! `--broadcast` is always refused.

use crate::error::{PfError, PfResult};
use crate::safety::{self, NetworkKind};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct DeployOutcome {
    pub network: String,
    pub endpoint: Option<String>,
    pub broadcast: bool,
    pub saved: Vec<PathBuf>,
    pub notes: Vec<String>,
}

pub struct DeployRequest<'a> {
    pub artifact_dir: &'a Path,
    pub network: NetworkKind,
    pub endpoint: Option<&'a str>,
    pub broadcast: bool,
    pub private_key_env: Option<&'a str>,
    pub save_dir: &'a Path,
}

pub fn deploy(req: DeployRequest<'_>) -> PfResult<DeployOutcome> {
    safety::refuse_mainnet(req.network)?;
    if req.broadcast {
        return Err(PfError::Usage(
            "noir: pf deploy --broadcast is refused (circuits are not chain-deployed by pf; \
             use nargo/external prover tooling outside product scope)"
                .into(),
        ));
    }
    if req.private_key_env.is_some() {
        return Err(PfError::Usage(
            "noir: --private-key-env is refused without broadcast; save-only never reads keys"
                .into(),
        ));
    }
    if !req.artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "noir artifact dir missing: {}",
            req.artifact_dir.display()
        )));
    }

    let manifest = req.artifact_dir.join("manifest.json");
    let relations = find_suffix(req.artifact_dir, ".noir-relations.json");
    let program = relations
        .as_ref()
        .and_then(|p| p.file_stem())
        .and_then(|s| s.to_str())
        .map(|s| s.trim_end_matches(".noir-relations").to_string())
        .unwrap_or_else(|| "Circuit".into());

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));

    let package = json!({
        "schema": "proof-forge.pf.noir-deploy-package.v1",
        "target": "noir",
        "program": program,
        "artifactDir": req.artifact_dir.display().to_string(),
        "manifestPath": if manifest.is_file() { Some(manifest.display().to_string()) } else { None },
        "relationsJsonPath": relations.as_ref().map(|p| p.display().to_string()),
        "networkCatalogHint": "n/a-circuit",
        "endpointHint": req.endpoint,
        "broadcastDefault": false,
        "notes": [
            "save-only package; no prover/nargo invoked",
            "pf deploy --broadcast refused for Noir",
            "use nargo / external proving stack outside pf product path",
            "default profile is source-relations; ACIR finalize is opt-in host-heavy"
        ],
    });
    fs::write(
        &package_path,
        serde_json::to_string_pretty(&package).expect("package"),
    )?;

    Ok(DeployOutcome {
        network: req.network.as_str().into(),
        endpoint: req.endpoint.map(|s| s.to_string()),
        broadcast: false,
        saved: vec![package_path],
        notes: vec![
            "noir save-only circuit package".into(),
            "broadcast refused".into(),
        ],
    })
}

fn find_suffix(dir: &Path, suffix: &str) -> Option<PathBuf> {
    let rd = fs::read_dir(dir).ok()?;
    for ent in rd.flatten() {
        let p = ent.path();
        if p.is_file() {
            if let Some(name) = p.file_name().and_then(|s| s.to_str()) {
                if name.ends_with(suffix) {
                    return Some(p);
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::safety::NetworkKind;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn broadcast_refused() {
        let dir = tempdir().unwrap();
        let art = dir.path().join("art");
        fs::create_dir_all(&art).unwrap();
        fs::write(art.join("manifest.json"), "{}").unwrap();
        fs::write(art.join("C.noir-relations.json"), "{}").unwrap();
        let err = deploy(DeployRequest {
            artifact_dir: &art,
            network: NetworkKind::Local,
            endpoint: None,
            broadcast: true,
            private_key_env: None,
            save_dir: &dir.path().join("tx"),
        })
        .unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("broadcast"), "{msg}");
    }

    #[test]
    fn save_only_ok() {
        let dir = tempdir().unwrap();
        let art = dir.path().join("art");
        fs::create_dir_all(&art).unwrap();
        fs::write(art.join("manifest.json"), "{}").unwrap();
        fs::write(art.join("C.noir-relations.json"), "{}").unwrap();
        let save = dir.path().join("tx");
        let out = deploy(DeployRequest {
            artifact_dir: &art,
            network: NetworkKind::Local,
            endpoint: None,
            broadcast: false,
            private_key_env: None,
            save_dir: &save,
        })
        .unwrap();
        assert!(!out.broadcast);
        assert_eq!(out.saved.len(), 1);
        assert!(out.saved[0].is_file());
    }
}
