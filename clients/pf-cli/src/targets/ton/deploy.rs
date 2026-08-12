//! TON deploy packaging (save-only).
//!
//! Packages Tolk/BoC build outputs. `--broadcast` refused in pf v0.

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
            "ton: pf deploy --broadcast is refused in v0 \
             (use scripts / @ton/sandbox engineering path; public write out of product scope)"
                .into(),
        ));
    }
    if req.private_key_env.is_some() {
        return Err(PfError::Usage(
            "ton: --private-key-env is refused without broadcast; save-only never reads keys"
                .into(),
        ));
    }
    if !req.artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "ton artifact dir missing: {}",
            req.artifact_dir.display()
        )));
    }

    let manifest = req.artifact_dir.join("manifest.json");
    if !manifest.is_file() {
        return Err(PfError::Artifact(format!(
            "ton: missing manifest.json under {}",
            req.artifact_dir.display()
        )));
    }

    // Collect interesting artifacts: .tolk / .boc / .fif / .fc if present
    let mut files: Vec<String> = Vec::new();
    for ent in fs::read_dir(req.artifact_dir)? {
        let ent = ent?;
        let p = ent.path();
        if !p.is_file() {
            continue;
        }
        let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("");
        if matches!(ext, "tolk" | "boc" | "fif" | "fc" | "pkg" | "json" | "tvm") {
            files.push(p.display().to_string());
        }
    }
    if files.is_empty() {
        return Err(PfError::Artifact(format!(
            "ton: no deployable-looking files under {}",
            req.artifact_dir.display()
        )));
    }

    let program = files
        .iter()
        .find_map(|f| {
            let p = Path::new(f);
            if p.extension().and_then(|s| s.to_str()) == Some("tolk") {
                p.file_stem().and_then(|s| s.to_str()).map(|s| s.to_string())
            } else {
                None
            }
        })
        .unwrap_or_else(|| "Contract".into());

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));

    let package = json!({
        "schema": "proof-forge.pf.ton-deploy-package.v1",
        "target": "ton",
        "program": program,
        "artifactDir": req.artifact_dir.display().to_string(),
        "files": files,
        "manifestPath": manifest.display().to_string(),
        "networkCatalogHint": match req.network {
            NetworkKind::Local => "ton.local.sandbox",
            NetworkKind::Testnet => "ton.testnet",
            NetworkKind::Devnet => "ton.testnet",
            NetworkKind::Mainnet => "refused",
        },
        "endpointHint": req.endpoint,
        "broadcastDefault": false,
        "notes": [
            "save-only package; no TON RPC performed",
            "pf deploy --broadcast refused for TON in v0",
            "prefer pf test / @ton/sandbox corpus for engineering evidence"
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
            "ton save-only package".into(),
            "broadcast refused".into(),
        ],
    })
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
        fs::write(art.join("C.tolk"), "// tolk\n").unwrap();
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
        fs::write(art.join("C.tolk"), "// tolk\n").unwrap();
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
