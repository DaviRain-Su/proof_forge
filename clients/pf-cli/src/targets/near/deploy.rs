//! NEAR deploy packaging (save-only).
//!
//! Default: write a deployment package under `<artifact>/tx/`.
//! `--broadcast` is refused for every network in pf v0 (including local):
//! product path is `scripts/near_runtime_test.sh` / locked near-sandbox, not
//! a key-holding deploy CLI. Public testnet/mainnet write is out of scope.

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
    pub account_id: Option<String>,
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
            "near: pf deploy --broadcast is refused in v0 \
             (use scripts/near_runtime_test.sh / locked near-sandbox for local runtime; \
             public testnet/mainnet write is out of product scope)"
                .into(),
        ));
    }
    if req.private_key_env.is_some() {
        return Err(PfError::Usage(
            "near: --private-key-env is refused without broadcast; \
             save-only packaging never reads keys"
                .into(),
        ));
    }

    let wasm = find_primary_wasm(req.artifact_dir)?;
    let program = wasm
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Contract")
        .to_string();
    let wasm_bytes = fs::read(&wasm)?;
    if wasm_bytes.len() < 4 || &wasm_bytes[..4] != b"\0asm" {
        return Err(PfError::Artifact(format!(
            "not a Wasm module (bad magic): {}",
            wasm.display()
        )));
    }
    let wasm_sha = {
        use sha2::{Digest, Sha256};
        hex::encode(Sha256::digest(&wasm_bytes))
    };

    let abi = find_optional_near_abi(req.artifact_dir, &program);
    let wat = find_optional_wat(req.artifact_dir, &program);
    let manifest = req.artifact_dir.join("manifest.json");
    let manifest_ok = manifest.is_file();

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));

    let network_catalog_hint = match req.network {
        NetworkKind::Local => "near.local.sandbox",
        NetworkKind::Testnet => "near.testnet",
        NetworkKind::Devnet => "near.testnet",
        NetworkKind::Mainnet => "refused",
    };

    let package = json!({
        "schema": "proof-forge.pf.near-deploy-package.v1",
        "target": "near",
        "program": program,
        "wasmPath": wasm.display().to_string(),
        "wasmSha256": wasm_sha,
        "wasmBytes": wasm_bytes.len(),
        "nearAbiPath": abi.as_ref().map(|p| p.display().to_string()),
        "watPath": wat.as_ref().map(|p| p.display().to_string()),
        "manifestPath": if manifest_ok { Some(manifest.display().to_string()) } else { None },
        "networkCatalogHint": network_catalog_hint,
        "endpointHint": req.endpoint,
        "suggestedCli": [
            format!("# engineering runtime (preferred):"),
            format!("scripts/near_runtime_test.sh"),
            format!("# manual near-cli style (not product-supported):"),
            format!("near contract deploy <ACCOUNT> use-file {} network-config testnet", wasm.display()),
        ],
        "broadcastDefault": false,
        "notes": [
            "save-only package; no RPC performed",
            "pf deploy --broadcast refused for NEAR in v0",
            "public testnet/mainnet write refused",
            "prefer scripts/near_runtime_test.sh for locked near-sandbox evidence",
            "deployable Wasm is not rewritten",
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
        account_id: None,
        notes: vec![
            "save-only NEAR deploy package".into(),
            "broadcast refused; use near-sandbox runtime scripts for local evidence".into(),
            format!("catalog hint: {network_catalog_hint}"),
        ],
    })
}

fn find_primary_wasm(dir: &Path) -> PfResult<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    collect_wasm(dir, &mut candidates)?;
    if candidates.is_empty() {
        return Err(PfError::Artifact(format!(
            "no .wasm under {} (run pf build --target near first)",
            dir.display()
        )));
    }
    // Prefer shallowest, then shortest name (stable).
    candidates.sort_by(|a, b| {
        let da = a.strip_prefix(dir).map(|p| p.components().count()).unwrap_or(99);
        let db = b.strip_prefix(dir).map(|p| p.components().count()).unwrap_or(99);
        da.cmp(&db)
            .then_with(|| a.file_name().cmp(&b.file_name()))
            .then_with(|| a.cmp(b))
    });
    Ok(candidates.remove(0))
}

fn collect_wasm(dir: &Path, out: &mut Vec<PathBuf>) -> PfResult<()> {
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let p = ent.path();
        if p.is_dir() {
            collect_wasm(&p, out)?;
        } else if p.extension().and_then(|e| e.to_str()) == Some("wasm") {
            out.push(p);
        }
    }
    Ok(())
}

fn find_optional_near_abi(dir: &Path, program: &str) -> Option<PathBuf> {
    let direct = dir.join(format!("{program}.near-abi.json"));
    if direct.is_file() {
        return Some(direct);
    }
    // Walk one level for nested out dirs.
    if let Ok(rd) = fs::read_dir(dir) {
        for ent in rd.flatten() {
            let p = ent.path();
            if p.is_file()
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| n.ends_with(".near-abi.json"))
                    .unwrap_or(false)
            {
                return Some(p);
            }
        }
    }
    None
}

fn find_optional_wat(dir: &Path, program: &str) -> Option<PathBuf> {
    let direct = dir.join(format!("{program}.wat"));
    if direct.is_file() {
        return Some(direct);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::tempdir;

    #[test]
    fn save_only_packages_wasm() {
        let dir = tempdir().unwrap();
        let art = dir.path().join("art");
        fs::create_dir_all(&art).unwrap();
        // Minimal Wasm magic + version.
        let mut f = fs::File::create(art.join("Hello.wasm")).unwrap();
        f.write_all(&[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
            .unwrap();
        fs::write(art.join("Hello.near-abi.json"), "{\"exports\":[]}").unwrap();
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
        let pkg: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(&out.saved[0]).unwrap()).unwrap();
        assert_eq!(pkg["schema"], "proof-forge.pf.near-deploy-package.v1");
        assert_eq!(pkg["target"], "near");
        assert_eq!(pkg["program"], "Hello");
        assert_eq!(pkg["wasmBytes"], 8);
    }

    #[test]
    fn broadcast_refused() {
        let dir = tempdir().unwrap();
        let art = dir.path().join("art");
        fs::create_dir_all(&art).unwrap();
        fs::write(art.join("X.wasm"), [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]).unwrap();
        let err = deploy(DeployRequest {
            artifact_dir: &art,
            network: NetworkKind::Local,
            endpoint: Some("http://127.0.0.1:3030"),
            broadcast: true,
            private_key_env: None,
            save_dir: &dir.path().join("tx"),
        })
        .unwrap_err();
        let msg = format!("{err}");
        assert!(msg.contains("broadcast"), "{msg}");
    }
}
