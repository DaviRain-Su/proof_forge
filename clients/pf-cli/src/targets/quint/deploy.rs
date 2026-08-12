//! Quint deploy packaging (save-only).
//!
//! Quint is a model/spec surface — not a chain deploy target. Package the
//! emitted `.qnt` for external model-based testing tools. Broadcast refused.

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
            "quint: pf deploy --broadcast is refused (model surface; no chain write; \
             use external Quint/Apalache tooling outside product scope)"
                .into(),
        ));
    }
    if req.private_key_env.is_some() {
        return Err(PfError::Usage(
            "quint: --private-key-env is refused without broadcast; save-only never reads keys"
                .into(),
        ));
    }
    if !req.artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "quint artifact dir missing: {}",
            req.artifact_dir.display()
        )));
    }

    let qnt = find_first_qnt(req.artifact_dir)?;
    let Some(qnt) = qnt else {
        return Err(PfError::Artifact(format!(
            "quint: no *.qnt under {}",
            req.artifact_dir.display()
        )));
    };
    let program = qnt
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Spec")
        .to_string();
    let qnt_bytes = fs::read(&qnt)?;
    let qnt_sha = {
        use sha2::{Digest, Sha256};
        hex::encode(Sha256::digest(&qnt_bytes))
    };
    let manifest = req.artifact_dir.join("manifest.json");

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));

    let package = json!({
        "schema": "proof-forge.pf.quint-deploy-package.v1",
        "target": "quint",
        "program": program,
        "qntPath": qnt.display().to_string(),
        "qntSha256": qnt_sha,
        "qntBytes": qnt_bytes.len(),
        "manifestPath": if manifest.is_file() { Some(manifest.display().to_string()) } else { None },
        "networkCatalogHint": "n/a-model-surface",
        "endpointHint": req.endpoint,
        "broadcastDefault": false,
        "notes": [
            "save-only package; no Quint CLI / Apalache / TLC invoked (ADR-0026)",
            "pf deploy --broadcast refused for Quint",
            "external model-based testing is out of product path"
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
            "quint save-only model package".into(),
            "broadcast refused".into(),
        ],
    })
}

fn find_first_qnt(dir: &Path) -> PfResult<Option<PathBuf>> {
    let mut found = None;
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let p = ent.path();
        if p.is_file() && p.extension().and_then(|s| s.to_str()) == Some("qnt") {
            found = Some(p);
            break;
        }
    }
    Ok(found)
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
        fs::write(art.join("Spec.qnt"), "module Spec {\n}\n").unwrap();
        let err = deploy(DeployRequest {
            artifact_dir: &art,
            network: NetworkKind::Local,
            endpoint: None,
            broadcast: true,
            private_key_env: None,
            save_dir: &dir.path().join("tx"),
        })
        .unwrap_err();
        assert!(err.to_string().contains("broadcast"));
    }

    #[test]
    fn save_only_ok() {
        let dir = tempdir().unwrap();
        let art = dir.path().join("art");
        fs::create_dir_all(&art).unwrap();
        fs::write(art.join("manifest.json"), "{}").unwrap();
        fs::write(art.join("Spec.qnt"), "module Spec {\n}\n").unwrap();
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
