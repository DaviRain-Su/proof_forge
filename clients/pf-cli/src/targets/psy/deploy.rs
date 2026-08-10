//! Psy deploy: wrap official `psy_user_cli deploy-contract`.
//!
//! Default: **save-only** (`--output-path`, no `--is-deploy`).
//! `--broadcast`: passes `--is-deploy` to the official CLI.
//!   - local: requires loopback RPC config (default ~/.psy/config.json localhost)
//!   - testnet/devnet: allowed with funded key (like Aleo testnet lane)
//!   - mainnet / ethereum production: refused
//!
//! Never invents a second deployer — only shells to psy_user_cli.

use super::simulate::{self, find_dpn, resolve_psy_user_cli};
use crate::error::{PfError, PfResult};
use crate::safety::{self, NetworkKind};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug)]
pub struct DeployOutcome {
    pub network: String,
    pub rpc_config: PathBuf,
    pub broadcast: bool,
    pub saved: Vec<PathBuf>,
    pub contract_path: PathBuf,
    pub notes: Vec<String>,
    pub stdout_tail: String,
}

pub struct DeployRequest<'a> {
    pub artifact_dir: &'a Path,
    pub network: NetworkKind,
    pub rpc_config: Option<&'a Path>,
    pub broadcast: bool,
    pub private_key_env: Option<&'a str>,
    pub save_dir: &'a Path,
    pub abi_path: Option<&'a Path>,
}

fn resolve_rpc_config(network: NetworkKind, override_path: Option<&Path>) -> PfResult<PathBuf> {
    if let Some(p) = override_path {
        if p.is_file() {
            return Ok(p.to_path_buf());
        }
        return Err(PfError::Usage(format!(
            "rpc config not found: {}",
            p.display()
        )));
    }
    if let Ok(p) = std::env::var("RPC_CONFIG") {
        let pb = PathBuf::from(&p);
        if pb.is_file() {
            // If user wants testnet but config defaultNetwork is localhost, materialize a sibling.
            return maybe_rewrite_default_network(pb, network);
        }
    }
    let home = std::env::var_os("HOME").map(PathBuf::from);
    if let Some(h) = home {
        let cand = h.join(".psy/config.json");
        if cand.is_file() {
            return maybe_rewrite_default_network(cand, network);
        }
        let cand2 = h.join(".psy/toolchains/psy-0.1.0/config.json");
        if cand2.is_file() {
            return maybe_rewrite_default_network(cand2, network);
        }
    }
    Err(PfError::Tool(
        "Psy RPC config not found — run `pf setup --target psy --yes` / psyup install".into(),
    ))
}

/// Official CLI reads `defaultNetwork` from config. For testnet/devnet deploys we write a
/// temp config with defaultNetwork=sepolia (or keep localhost for local) without mutating ~/.psy.
fn maybe_rewrite_default_network(base: PathBuf, network: NetworkKind) -> PfResult<PathBuf> {
    let want = match network {
        NetworkKind::Local => "localhost",
        NetworkKind::Testnet | NetworkKind::Devnet => "sepolia",
        NetworkKind::Mainnet => {
            return Err(PfError::Safety("mainnet refused".into()));
        }
    };
    let text = fs::read_to_string(&base).map_err(|e| PfError::Tool(e.to_string()))?;
    let mut v: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| PfError::Tool(format!("rpc config: {e}")))?;
    let cur = v
        .get("defaultNetwork")
        .and_then(|x| x.as_str())
        .unwrap_or("");
    if cur == want {
        return Ok(base);
    }
    // Ensure network block exists
    if let Some(nets) = v.get("networks").and_then(|n| n.as_object()) {
        if !nets.contains_key(want) {
            return Err(PfError::Tool(format!(
                "rpc config {} has no networks.{want} block",
                base.display()
            )));
        }
    }
    if let Some(obj) = v.as_object_mut() {
        obj.insert("defaultNetwork".into(), serde_json::Value::String(want.into()));
    }
    let dir = std::env::temp_dir().join("proof-forge-psy");
    fs::create_dir_all(&dir)?;
    let out = dir.join(format!("rpc-{}-{}.json", want, std::process::id()));
    fs::write(
        &out,
        serde_json::to_string_pretty(&v).map_err(|e| PfError::Tool(e.to_string()))?,
    )?;
    Ok(out)
}

/// Refuse production ethereum/mainnet-style Psy networks.
fn refuse_psy_mainnet(network: NetworkKind) -> PfResult<()> {
    safety::refuse_mainnet(network)?;
    Ok(())
}

fn require_local_config_is_loopback(cfg: &Path) -> PfResult<()> {
    let text = fs::read_to_string(cfg).map_err(|e| PfError::Tool(e.to_string()))?;
    // Require an actual loopback URL host, not merely the key name "localhost".
    let has_loopback_url = text.contains("127.0.0.1")
        || text.contains("[::1]")
        || text.contains("http://localhost")
        || text.contains("https://localhost")
        || text.contains("ws://localhost");
    if !has_loopback_url {
        return Err(PfError::Safety(format!(
            "local Psy deploy expects loopback RPC URLs in {} (need 127.0.0.1 or http://localhost/…)",
            cfg.display()
        )));
    }
    Ok(())
}

pub fn deploy(req: DeployRequest<'_>) -> PfResult<DeployOutcome> {
    refuse_psy_mainnet(req.network)?;
    let dpn = find_dpn(req.artifact_dir)?;
    let cli = resolve_psy_user_cli()?;
    let rpc_config = resolve_rpc_config(req.network, req.rpc_config)?;

    fs::create_dir_all(req.save_dir)?;
    let out_path = req.save_dir.join("deploy_cmd.json");
    let receipt_path = req.save_dir.join("deployment.receipt.json");

    // Package metadata always written (even before official CLI).
    let package_path = req.save_dir.join("deployment.package.json");
    let package = json!({
        "schema": "proof-forge.pf.psy-deploy-package.v1",
        "target": "psy",
        "profile": "psy-dpn-v1",
        "contractPath": dpn.display().to_string(),
        "rpcConfig": rpc_config.display().to_string(),
        "network": req.network.as_str(),
        "broadcastDefault": false,
        "officialCli": format!(
            "psy_user_cli deploy-contract --contract-path {} --rpc-config {} --output-path {} [--is-deploy]",
            dpn.display(),
            rpc_config.display(),
            out_path.display()
        ),
        "notes": [
            "wraps official psy_user_cli only — no PF-owned deployer",
            "save-only omits --is-deploy; --broadcast adds --is-deploy",
            "mainnet refused; production ethereum network refused",
            "deployable flag on PF OutputSet remains false (engineering lane)",
        ],
    });
    fs::write(
        &package_path,
        serde_json::to_string_pretty(&package).expect("json"),
    )?;

    let key = if req.broadcast {
        safety::resolve_private_key_for_mode(true, req.private_key_env)?
    } else {
        // save-only: official CLI still requires --private-key; allow env or ephemeral dummy
        match req.private_key_env {
            Some(name) => std::env::var(name).map_err(|_| {
                PfError::Usage(format!(
                    "save-only Psy deploy still needs a key for psy_user_cli packaging; \
                     set --private-key-env {name} (or omit and use PF_PSY_DEPLOY_KEY / dummy)"
                ))
            })?,
            None => std::env::var("PF_PSY_DEPLOY_KEY")
                .or_else(|_| std::env::var("PRIVATE_KEY"))
                .unwrap_or_else(|_| {
                    // 32-byte hex dummy — enough for circuit packaging, not for broadcast
                    "0000000000000000000000000000000000000000000000000000000000000001".into()
                }),
        }
    };

    if req.broadcast {
        match req.network {
            NetworkKind::Local => {
                require_local_config_is_loopback(&rpc_config)?;
            }
            NetworkKind::Testnet | NetworkKind::Devnet => {
                // allowed (official sepolia / staging style configs)
            }
            NetworkKind::Mainnet => {
                return Err(PfError::Safety("mainnet refused".into()));
            }
        }
    }

    let mut cmd = Command::new(&cli);
    cmd.arg("deploy-contract")
        .arg("--contract-path")
        .arg(&dpn)
        .arg("--rpc-config")
        .arg(&rpc_config)
        .arg("--private-key")
        .arg(&key)
        .arg("--output-path")
        .arg(&out_path);
    if let Some(abi) = req.abi_path {
        if abi.is_file() {
            cmd.arg("--abi-path").arg(abi);
        }
    }
    if req.broadcast {
        cmd.arg("--is-deploy");
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("spawn psy_user_cli deploy-contract: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    let combined = format!("{stdout}{stderr}");
    if !out.status.success() {
        return Err(PfError::Network(format!(
            "psy_user_cli deploy-contract failed (exit {:?}):\n{combined}",
            out.status.code()
        )));
    }
    if !out_path.is_file() {
        return Err(PfError::Tool(format!(
            "deploy-contract succeeded but missing output {}",
            out_path.display()
        )));
    }

    let mut notes = vec![
        if req.broadcast {
            "broadcast via official --is-deploy".into()
        } else {
            "save-only package (no --is-deploy)".into()
        },
        format!("official cli: {}", cli.display()),
    ];

    // Best-effort receipt
    let receipt = json!({
        "schema": "proof-forge.pf.psy-deployment.receipt.v1",
        "target": "psy",
        "network": req.network.as_str(),
        "broadcast": req.broadcast,
        "contractPath": dpn.display().to_string(),
        "deployCmdPath": out_path.display().to_string(),
        "rpcConfig": rpc_config.display().to_string(),
        "cliTail": combined.chars().rev().take(4000).collect::<String>().chars().rev().collect::<String>(),
    });
    fs::write(
        &receipt_path,
        serde_json::to_string_pretty(&receipt).expect("json"),
    )?;

    if req.broadcast {
        notes.push("confirm on explorer / services API; PF does not rewrite deployable".into());
    } else {
        notes.push("re-run with --broadcast --private-key-env KEY to submit".into());
    }

    let tail: String = combined.chars().rev().take(800).collect::<String>().chars().rev().collect();

    Ok(DeployOutcome {
        network: req.network.as_str().into(),
        rpc_config,
        broadcast: req.broadcast,
        saved: vec![package_path, out_path, receipt_path],
        contract_path: dpn,
        notes,
        stdout_tail: tail,
    })
}

/// Probe whether localhost Psy RPC from config answers (persistent local chain).
pub fn local_chain_status(rpc_config: Option<&Path>) -> PfResult<serde_json::Value> {
    let cfg = resolve_rpc_config(NetworkKind::Local, rpc_config)?;
    let text = fs::read_to_string(&cfg).map_err(|e| PfError::Tool(e.to_string()))?;
    let v: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| PfError::Tool(format!("rpc config json: {e}")))?;

    // Collect candidate URLs
    let mut urls = Vec::new();
    if let Some(nets) = v.get("networks").and_then(|n| n.as_object()) {
        if let Some(local) = nets.get("localhost") {
            if let Some(coords) = local.get("coordinator_configs").and_then(|c| c.as_array()) {
                for c in coords {
                    if let Some(arr) = c.get("rpc_url").and_then(|u| u.as_array()) {
                        for u in arr {
                            if let Some(s) = u.as_str() {
                                urls.push(s.to_string());
                            }
                        }
                    }
                }
            }
        }
    }
    // flat public-style config
    if urls.is_empty() {
        if let Some(s) = v
            .pointer("/services/coordinator_rpc")
            .and_then(|x| x.as_str())
        {
            urls.push(s.to_string());
        }
    }

    let mut probes = Vec::new();
    let mut any_up = false;
    for url in &urls {
        let up = probe_http(url);
        if up {
            any_up = true;
        }
        probes.push(json!({"url": url, "up": up}));
    }

    Ok(json!({
        "schema": "proof-forge.pf.psy-local-chain-status.v1",
        "rpcConfig": cfg.display().to_string(),
        "probes": probes,
        "anyUp": any_up,
        "howToStart": [
            "Official local cluster is host-heavy (psy_node_cli + scylla/nats/redis or psy-node dev setup).",
            "See: https://github.com/PsyProtocol/psy-node README (locSetupV3 / local-devnet).",
            "When coordinator answers on loopback, use: pf deploy -t psy --network local --broadcast --private-key-env KEY",
            "Public testnet (sepolia config): pf deploy -t psy --network testnet --broadcast --private-key-env KEY",
        ],
        "note": "pf does not auto-start Scylla/NATS/Redis/node fabric in v0",
    }))
}

fn probe_http(url: &str) -> bool {
    // Best-effort TCP/HTTP probe without extra deps: use `curl -sS -m 1`.
    Command::new("curl")
        .args(["-sS", "-o", "/dev/null", "-m", "1", "-w", "%{http_code}", url])
        .output()
        .map(|o| {
            let code = String::from_utf8_lossy(&o.stdout);
            o.status.success() && code != "000"
        })
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::tempdir;

    #[test]
    fn package_paths_stable() {
        // smoke type linkage
        let _ = resolve_psy_user_cli();
        let _ = simulate::find_dpn;
    }

    #[test]
    fn refuse_mainnet_network() {
        assert!(refuse_psy_mainnet(NetworkKind::Mainnet).is_err());
        assert!(refuse_psy_mainnet(NetworkKind::Testnet).is_ok());
    }

    #[test]
    fn loopback_config_gate() {
        let dir = tempdir().unwrap();
        let good = dir.path().join("good.json");
        let mut f = fs::File::create(&good).unwrap();
        write!(f, r#"{{"networks":{{"localhost":{{"x":"http://127.0.0.1:1337"}}}}}}"#).unwrap();
        assert!(require_local_config_is_loopback(&good).is_ok());
        let bad = dir.path().join("bad.json");
        fs::write(&bad, r#"{"networks":{"localhost":{"x":"https://example.com"}}}"#).unwrap();
        assert!(require_local_config_is_loopback(&bad).is_err());
    }
}
