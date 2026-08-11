//! CosmWasm deploy packaging (save-only).
//!
//! Default: write a deployment package under `<artifact>/tx/`.
//! `--broadcast` is refused for every network in pf v0.
//! Runtime evidence: `pf test -t cosmwasm` / cosmwasm-vm mock / wasmd Docker rung.

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
            "cosmwasm: pf deploy --broadcast is refused in v0 \
             (use `pf test -t cosmwasm` / cosmwasm-vm mock / wasmd Docker rung; \
             public chain write is out of product scope)"
                .into(),
        ));
    }
    if req.private_key_env.is_some() {
        return Err(PfError::Usage(
            "cosmwasm: --private-key-env is refused without broadcast; \
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

    let abi = find_optional_sidecar(req.artifact_dir, &program, ".cosmwasm-abi.json");
    let wat = find_optional_sidecar(req.artifact_dir, &program, ".wat");
    let manifest = req.artifact_dir.join("manifest.json");
    let manifest_ok = manifest.is_file();

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));

    let network_catalog_hint = match req.network {
        NetworkKind::Local => "cosmwasm.local.mock",
        NetworkKind::Testnet | NetworkKind::Devnet => "cosmwasm.testnet.catalog-only",
        NetworkKind::Mainnet => "refused",
    };

    let package = json!({
        "schema": "proof-forge.pf.cosmwasm-deploy-package.v1",
        "target": "cosmwasm",
        "program": program,
        "wasmPath": wasm.display().to_string(),
        "wasmSha256": wasm_sha,
        "wasmBytes": wasm_bytes.len(),
        "cosmwasmAbiPath": abi.as_ref().map(|p| p.display().to_string()),
        "watPath": wat.as_ref().map(|p| p.display().to_string()),
        "manifestPath": if manifest_ok { Some(manifest.display().to_string()) } else { None },
        "networkCatalogHint": network_catalog_hint,
        "endpointHint": req.endpoint,
        "suggestedCli": [
            "# engineering runtime (preferred):",
            "pf test -t cosmwasm",
            "scripts/cosmwasm_runtime_test.sh",
            "# wasmd Docker rung (host-heavy):",
            "scripts/cosmwasm_wasmd_test.sh",
        ],
        "broadcastDefault": false,
        "notes": [
            "save-only package; no RPC performed",
            "pf deploy --broadcast refused for CosmWasm in v0",
            "sync call permanent fail-closed; schedule = SubMsg reply_on=never",
            "prefer pf test -t cosmwasm for locked cosmwasm-vm evidence",
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
        notes: vec![
            "save-only CosmWasm deploy package".into(),
            "broadcast refused; use cosmwasm-vm / wasmd engineering rungs".into(),
            format!("catalog hint: {network_catalog_hint}"),
        ],
    })
}

fn find_primary_wasm(dir: &Path) -> PfResult<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    collect_wasm(dir, &mut candidates)?;
    if candidates.is_empty() {
        return Err(PfError::Artifact(format!(
            "no .wasm under {} (run pf build --target cosmwasm first)",
            dir.display()
        )));
    }
    candidates.sort_by(|a, b| {
        let da = a
            .strip_prefix(dir)
            .map(|p| p.components().count())
            .unwrap_or(99);
        let db = b
            .strip_prefix(dir)
            .map(|p| p.components().count())
            .unwrap_or(99);
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

fn find_optional_sidecar(dir: &Path, program: &str, suffix: &str) -> Option<PathBuf> {
    let direct = dir.join(format!("{program}{suffix}"));
    if direct.is_file() {
        return Some(direct);
    }
    if let Ok(rd) = fs::read_dir(dir) {
        for ent in rd.flatten() {
            let p = ent.path();
            if p.is_file()
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| n.ends_with(suffix))
                    .unwrap_or(false)
            {
                return Some(p);
            }
        }
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
        let mut f = fs::File::create(art.join("Hello.wasm")).unwrap();
        f.write_all(&[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
            .unwrap();
        fs::write(art.join("Hello.cosmwasm-abi.json"), "{\"schema\":\"proof-forge-cosmwasm-abi/v1alpha1\"}")
            .unwrap();
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
        assert_eq!(pkg["schema"], "proof-forge.pf.cosmwasm-deploy-package.v1");
        assert_eq!(pkg["target"], "cosmwasm");
        assert_eq!(pkg["program"], "Hello");
    }

    #[test]
    fn broadcast_refused() {
        let dir = tempdir().unwrap();
        let art = dir.path().join("art");
        fs::create_dir_all(&art).unwrap();
        fs::write(
            art.join("X.wasm"),
            [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00],
        )
        .unwrap();
        let err = deploy(DeployRequest {
            artifact_dir: &art,
            network: NetworkKind::Local,
            endpoint: Some("http://127.0.0.1:26657"),
            broadcast: true,
            private_key_env: None,
            save_dir: &dir.path().join("tx"),
        })
        .unwrap_err();
        let msg = format!("{err}");
        assert!(msg.contains("broadcast"), "{msg}");
    }
}
