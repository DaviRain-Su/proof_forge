//! EVM deploy packaging + optional local Anvil broadcast (D11).
//!
//! Default: **save-only** deployment package under `<artifact>/tx/`.
//! `--broadcast`: only `--network local` + loopback RPC (or ephemeral Anvil).

use crate::error::{PfError, PfResult};
use crate::safety::{self, NetworkKind};
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::Duration;

#[derive(Debug)]
pub struct DeployOutcome {
    pub network: String,
    pub endpoint: Option<String>,
    pub broadcast: bool,
    pub saved: Vec<PathBuf>,
    pub contract_address: Option<String>,
    pub notes: Vec<String>,
}

pub struct DeployRequest<'a> {
    pub artifact_dir: &'a Path,
    pub network: NetworkKind,
    pub endpoint: Option<&'a str>,
    pub broadcast: bool,
    pub private_key_env: Option<&'a str>,
    pub save_dir: &'a Path,
    /// Optional constructor uint64 (StateCell-shaped default 0).
    pub constructor_initial: u64,
}

pub fn deploy(req: DeployRequest<'_>) -> PfResult<DeployOutcome> {
    safety::refuse_mainnet(req.network)?;
    if req.broadcast {
        safety::refuse_public_chain_broadcast(req.network, "evm")?;
    }

    let bin = find_primary_bin(req.artifact_dir)?;
    let program = bin
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Contract")
        .to_string();
    let bytecode = fs::read_to_string(&bin)?
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect::<String>();
    if bytecode.is_empty() {
        return Err(PfError::Artifact(format!(
            "empty bytecode: {}",
            bin.display()
        )));
    }

    fs::create_dir_all(req.save_dir)?;
    let package_path = req
        .save_dir
        .join(format!("{program}.deployment.package.json"));
    let package = json!({
        "schema": "proof-forge.pf.evm-deploy-package.v1",
        "target": "evm",
        "program": program,
        "bytecodePath": bin.display().to_string(),
        "bytecode": format!("0x{bytecode}"),
        "constructor": {
            "signature": "constructor(uint64)",
            "args": [req.constructor_initial],
        },
        "suggestedCast": format!(
            "cast send --rpc-url <RPC> --private-key <KEY> --create $(cast concat-hex 0x{bytecode} $(cast abi-encode 'constructor(uint64)' {}))",
            req.constructor_initial
        ),
        "broadcastDefault": false,
        "notes": [
            "save-only package; not mainnet",
            "pf deploy --broadcast requires --network local",
            "deployable field never rewritten",
        ],
    });
    fs::write(
        &package_path,
        serde_json::to_string_pretty(&package).expect("package json"),
    )?;

    if !req.broadcast {
        return Ok(DeployOutcome {
            network: req.network.as_str().into(),
            endpoint: None,
            broadcast: false,
            saved: vec![package_path],
            contract_address: None,
            notes: vec![
                "save-only EVM deploy package".into(),
                "use --broadcast --network local for Anvil/local RPC".into(),
            ],
        });
    }

    // Broadcast path: local only.
    // Prefer --private-key-env; else Anvil default account #0 (local-only, never public).
    const ANVIL_DEFAULT_0: &str =
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    let key = if let Some(name) = req.private_key_env {
        safety::resolve_private_key_for_mode(true, Some(name))?
    } else {
        ANVIL_DEFAULT_0.to_string()
    };
    let pk = normalize_hex_key(&key)?;

    let (endpoint, mut child) = resolve_local_rpc(req.endpoint)?;
    safety::require_loopback_endpoint(&endpoint)?;

    let cast = resolve_cast()?;
    let encoded = Command::new(&cast)
        .args([
            "abi-encode",
            "constructor(uint64)",
            &req.constructor_initial.to_string(),
        ])
        .output()
        .map_err(|e| PfError::Tool(format!("cast abi-encode: {e}")))?;
    if !encoded.status.success() {
        let _ = cleanup_anvil(&mut child);
        return Err(PfError::Tool(format!(
            "cast abi-encode failed: {}",
            String::from_utf8_lossy(&encoded.stderr)
        )));
    }
    let enc = String::from_utf8_lossy(&encoded.stdout).trim().to_string();
    let create_data = format!("0x{bytecode}{}", enc.trim_start_matches("0x"));

    let send = Command::new(&cast)
        .args([
            "send",
            "--json",
            "--rpc-url",
            &endpoint,
            "--private-key",
            &pk,
            "--create",
            &create_data,
        ])
        .output()
        .map_err(|e| PfError::Tool(format!("cast send: {e}")))?;
    if !send.status.success() {
        let _ = cleanup_anvil(&mut child);
        return Err(PfError::Tool(format!(
            "cast send --create failed: {}{}",
            String::from_utf8_lossy(&send.stderr),
            String::from_utf8_lossy(&send.stdout)
        )));
    }
    let receipt: Value = serde_json::from_slice(&send.stdout).map_err(|e| {
        let _ = cleanup_anvil(&mut child);
        PfError::Tool(format!("cast receipt json: {e}"))
    })?;
    let addr = receipt
        .get("contractAddress")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if addr.is_empty() || addr == "null" {
        let _ = cleanup_anvil(&mut child);
        return Err(PfError::Tool(
            "cast send produced no contractAddress".into(),
        ));
    }

    let receipt_path = req
        .save_dir
        .join(format!("{program}.deployment.receipt.json"));
    let record = json!({
        "schema": "proof-forge.pf.evm-deploy-receipt.v1",
        "target": "evm",
        "network": "local",
        "endpoint": endpoint,
        "program": program,
        "contractAddress": addr,
        "constructorInitial": req.constructor_initial,
        "receipt": receipt,
        "notes": [
            "local broadcast only",
            "not mainnet",
            "not formal",
            "deployable not rewritten",
        ],
    });
    fs::write(
        &receipt_path,
        serde_json::to_string_pretty(&record).expect("receipt"),
    )?;

    let _ = cleanup_anvil(&mut child);

    Ok(DeployOutcome {
        network: "local".into(),
        endpoint: Some(endpoint),
        broadcast: true,
        saved: vec![package_path, receipt_path],
        contract_address: Some(addr),
        notes: vec![
            "local Anvil/RPC broadcast".into(),
            "not mainnet / not public chain".into(),
        ],
    })
}

fn find_primary_bin(dir: &Path) -> PfResult<PathBuf> {
    let preferred = dir.join("StateCell.bin");
    if preferred.is_file() {
        return Ok(preferred);
    }
    let mut bins: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| PfError::Io(e.to_string()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|x| x.to_str()) == Some("bin"))
        .collect();
    bins.sort();
    bins.into_iter().next().ok_or_else(|| {
        PfError::Artifact(format!(
            "no *.bin under {} (run `pf build -t evm` first)",
            dir.display()
        ))
    })
}

fn normalize_hex_key(key: &str) -> PfResult<String> {
    let k = key.trim();
    // Anvil default #0 (allowed only for local broadcast).
    let k = k.strip_prefix("0x").unwrap_or(k);
    if k.len() != 64 || !k.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(PfError::Safety(
            "evm --broadcast expects a 32-byte hex private key in --private-key-env".into(),
        ));
    }
    Ok(format!("0x{k}"))
}

fn resolve_cast() -> PfResult<PathBuf> {
    if let Ok(tr) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        let c = PathBuf::from(&tr).join("cast");
        if c.is_file() {
            return Ok(c);
        }
    }
    if let Ok(tr) = std::env::var("FOUNDRY_BIN") {
        let c = PathBuf::from(&tr).join("cast");
        if c.is_file() {
            return Ok(c);
        }
    }
    which::which("cast").map_err(|_| {
        PfError::Tool("cast not found (set PROOF_FORGE_TOOL_ROOT with locked foundry tools)".into())
    })
}

fn resolve_anvil() -> PfResult<PathBuf> {
    if let Ok(tr) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        let c = PathBuf::from(&tr).join("anvil");
        if c.is_file() {
            return Ok(c);
        }
    }
    if let Ok(tr) = std::env::var("FOUNDRY_BIN") {
        let c = PathBuf::from(&tr).join("anvil");
        if c.is_file() {
            return Ok(c);
        }
    }
    which::which("anvil").map_err(|_| {
        PfError::Tool(
            "anvil not found (set PROOF_FORGE_TOOL_ROOT or pass --endpoint to existing local RPC)"
                .into(),
        )
    })
}

/// Returns (endpoint, optional child anvil to kill).
fn resolve_local_rpc(endpoint: Option<&str>) -> PfResult<(String, Option<Child>)> {
    if let Some(ep) = endpoint {
        return Ok((ep.to_string(), None));
    }
    // Ephemeral anvil on free-ish port.
    let anvil = resolve_anvil()?;
    let port = 18500 + (std::process::id() % 500);
    let endpoint = format!("http://127.0.0.1:{port}");
    let log = std::env::temp_dir().join(format!("pf-evm-deploy-anvil-{port}.log"));
    let log_file = fs::File::create(&log).map_err(|e| PfError::Io(e.to_string()))?;
    let child = Command::new(&anvil)
        .args([
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "--silent",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::from(log_file.try_clone().unwrap()))
        .stderr(Stdio::from(log_file))
        .spawn()
        .map_err(|e| PfError::Tool(format!("spawn anvil: {e}")))?;

    let cast = resolve_cast()?;
    let mut ready = false;
    for _ in 0..50 {
        if Command::new(&cast)
            .args(["chain-id", "--rpc-url", &endpoint])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
        {
            ready = true;
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }
    if !ready {
        return Err(PfError::Tool(format!(
            "anvil failed to become ready at {endpoint} (log {})",
            log.display()
        )));
    }
    Ok((endpoint, Some(child)))
}

fn cleanup_anvil(child: &mut Option<Child>) -> PfResult<()> {
    if let Some(c) = child.as_mut() {
        let _ = c.kill();
        let _ = c.wait();
    }
    *child = None;
    Ok(())
}
