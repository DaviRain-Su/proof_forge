//! Solana deploy packaging + optional local RPC broadcast (D11).
//!
//! Default: **save-only** package (no RPC).
//! `--broadcast`: only `--network local` + loopback RPC + `solana program deploy`.
//! Never targets public Devnet/Testnet/Mainnet.

use crate::error::{PfError, PfResult};
use crate::safety::{self, NetworkKind};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug)]
pub struct DeployOutcome {
    pub network: String,
    pub endpoint: Option<String>,
    pub broadcast: bool,
    pub saved: Vec<PathBuf>,
    pub program_id: Option<String>,
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
        safety::refuse_public_chain_broadcast(req.network, "solana")?;
    }

    let so = find_primary_so(req.artifact_dir)?;
    let program = so
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Program")
        .to_string();
    let so_bytes = fs::read(&so)?;
    if so_bytes.len() < 4 || &so_bytes[..4] != b"\x7fELF" {
        return Err(PfError::Artifact(format!("not an ELF: {}", so.display())));
    }
    let so_sha = {
        use sha2::{Digest, Sha256};
        hex::encode(Sha256::digest(&so_bytes))
    };

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));
    let package = json!({
        "schema": "proof-forge.pf.solana-deploy-package.v1",
        "target": "solana",
        "program": program,
        "soPath": so.display().to_string(),
        "soSha256": so_sha,
        "soBytes": so_bytes.len(),
        "suggestedCli": format!(
            "solana program deploy {} --url <LOCAL_RPC> --keypair <PAYER.json> --program-id <PROGRAM.json>",
            so.display()
        ),
        "broadcastDefault": false,
        "notes": [
            "save-only package; no RPC performed",
            "pf deploy --broadcast requires --network local and loopback --endpoint",
            "public Devnet/Testnet/Mainnet write refused in pf v0",
            "deployable not rewritten",
            "prefer pf test (Mollusk) for offline execution evidence",
        ],
    });
    fs::write(
        &package_path,
        serde_json::to_string_pretty(&package).expect("package"),
    )?;

    if !req.broadcast {
        return Ok(DeployOutcome {
            network: req.network.as_str().into(),
            endpoint: None,
            broadcast: false,
            saved: vec![package_path],
            program_id: None,
            notes: vec![
                "save-only Solana deploy package".into(),
                "use --broadcast --network local --endpoint http://127.0.0.1:8899".into(),
            ],
        });
    }

    // Broadcast: local RPC only. Keypairs are files (not Leo-style strings).
    let endpoint = req.endpoint.ok_or_else(|| {
        PfError::Usage(
            "solana --broadcast requires --endpoint http://127.0.0.1:<port> \
             (start Surfpool/validator first; pf does not auto-start public nets)"
                .into(),
        )
    })?;
    safety::require_loopback_endpoint(endpoint)?;

    let solana = which::which("solana").map_err(|_| {
        PfError::Tool("solana CLI not on PATH (needed for local program deploy)".into())
    })?;
    let keygen = which::which("solana-keygen")
        .map_err(|_| PfError::Tool("solana-keygen not on PATH".into()))?;

    let payer_kp = resolve_or_create_keypair(
        req.private_key_env,
        &keygen,
        &req.save_dir.join("payer-keypair.json"),
        "payer",
    )?;
    let program_kp = req.save_dir.join(format!("{program}-program-keypair.json"));
    if !program_kp.is_file() {
        let st = Command::new(&keygen)
            .args(["new", "--no-bip39-passphrase", "--silent", "-o"])
            .arg(&program_kp)
            .status()
            .map_err(|e| PfError::Tool(format!("solana-keygen: {e}")))?;
        if !st.success() {
            return Err(PfError::Tool("solana-keygen new program key failed".into()));
        }
    }
    let program_id = pubkey_of(&keygen, &program_kp)?;

    let max_len = so_bytes.len() + 65536;
    let out = Command::new(&solana)
        .args([
            "program",
            "deploy",
            &so.display().to_string(),
            "--url",
            endpoint,
            "--keypair",
            &payer_kp.display().to_string(),
            "--program-id",
            &program_kp.display().to_string(),
            "--max-len",
            &max_len.to_string(),
        ])
        .output()
        .map_err(|e| PfError::Tool(format!("solana program deploy: {e}")))?;
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "solana program deploy failed:\n{}{}",
            String::from_utf8_lossy(&out.stderr),
            String::from_utf8_lossy(&out.stdout)
        )));
    }
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    let combined = format!("{stdout}{stderr}");

    let receipt_path = req
        .save_dir
        .join(format!("{program}.deployment.receipt.json"));
    let record = json!({
        "schema": "proof-forge.pf.solana-deploy-receipt.v1",
        "target": "solana",
        "network": "local",
        "endpoint": endpoint,
        "program": program,
        "programId": program_id,
        "soPath": so.display().to_string(),
        "soSha256": so_sha,
        "cliOutput": combined,
        "notes": [
            "local RPC broadcast only",
            "not public Devnet/Testnet/Mainnet",
            "not formal",
            "deployable not rewritten",
            "Mollusk remains offline execution authority (pf test)",
        ],
    });
    fs::write(
        &receipt_path,
        serde_json::to_string_pretty(&record).expect("receipt"),
    )?;

    Ok(DeployOutcome {
        network: "local".into(),
        endpoint: Some(endpoint.into()),
        broadcast: true,
        saved: vec![package_path, receipt_path, program_kp, payer_kp],
        program_id: Some(program_id),
        notes: vec![
            "local solana program deploy".into(),
            "not public network".into(),
        ],
    })
}

fn find_primary_so(dir: &Path) -> PfResult<PathBuf> {
    // Prefer TransferSol / single so / first so
    for name in ["TransferSol.so", "StateCell.so"] {
        let p = dir.join(name);
        if p.is_file() {
            return Ok(p);
        }
    }
    let mut sos: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| PfError::Io(e.to_string()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|x| x.to_str()) == Some("so"))
        .collect();
    sos.sort();
    sos.into_iter().next().ok_or_else(|| {
        PfError::Artifact(format!(
            "no *.so under {} (run `pf build -t solana` first)",
            dir.display()
        ))
    })
}

fn resolve_or_create_keypair(
    private_key_env: Option<&str>,
    keygen: &Path,
    default_path: &Path,
    label: &str,
) -> PfResult<PathBuf> {
    if let Some(name) = private_key_env {
        let v = std::env::var(name).map_err(|_| {
            PfError::Safety(format!(
                "--broadcast: env '{name}' not set (expected path to solana keypair json)"
            ))
        })?;
        let p = PathBuf::from(v.trim());
        if p.is_file() {
            return Ok(p);
        }
        return Err(PfError::Safety(format!(
            "--broadcast: env '{name}' must be a keypair file path for solana (got missing file)"
        )));
    }
    if !default_path.is_file() {
        let st = Command::new(keygen)
            .args(["new", "--no-bip39-passphrase", "--silent", "-o"])
            .arg(default_path)
            .status()
            .map_err(|e| PfError::Tool(format!("solana-keygen {label}: {e}")))?;
        if !st.success() {
            return Err(PfError::Tool(format!(
                "solana-keygen failed to create {label} keypair"
            )));
        }
    }
    Ok(default_path.to_path_buf())
}

fn pubkey_of(keygen: &Path, kp: &Path) -> PfResult<String> {
    let out = Command::new(keygen)
        .args(["pubkey"])
        .arg(kp)
        .output()
        .map_err(|e| PfError::Tool(format!("solana-keygen pubkey: {e}")))?;
    if !out.status.success() {
        return Err(PfError::Tool("solana-keygen pubkey failed".into()));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}
