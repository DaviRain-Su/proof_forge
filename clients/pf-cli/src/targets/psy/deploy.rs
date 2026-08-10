//! Psy deploy: wrap official `psy_user_cli deploy-contract`.
//!
//! Default: **save-only** (`--output-path`, no `--is-deploy`).
//! `--broadcast`: passes `--is-deploy` to the official CLI.
//!   - local: requires loopback RPC config (default ~/.psy/config.json localhost)
//!   - testnet/devnet: allowed with funded key (like Aleo testnet lane)
//!   - mainnet / ethereum production: refused
//!
//! Never invents a second deployer — only shells to psy_user_cli.

use super::abi::derive_abi_path;
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
    pub contract_uuid: Option<String>,
    pub contract_id: Option<u64>,
    pub explorer_hint: Option<String>,
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

pub fn resolve_rpc_config(network: NetworkKind, override_path: Option<&Path>) -> PfResult<PathBuf> {
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
    let derived_abi = derive_abi_path(req.artifact_dir).ok();
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
    let abi_file = req
        .abi_path
        .filter(|p| p.is_file())
        .map(|p| p.to_path_buf())
        .or(derived_abi);
    if let Some(ref abi) = abi_file {
        cmd.arg("--abi-path").arg(abi);
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

    let mut contract_uuid = parse_contract_uuid(&combined);
    let mut contract_id = None;
    if req.broadcast {
        if let Some(ref uuid) = contract_uuid {
            notes.push(format!("contract_uuid={uuid}"));
            match lookup_contract_id(&rpc_config, uuid, 30) {
                Ok(Some(id)) => {
                    contract_id = Some(id);
                    notes.push(format!("contract_id={id}"));
                }
                Ok(None) => notes.push(
                    "contract_id lookup timed out — poll services API or re-run lookup".into(),
                ),
                Err(e) => notes.push(format!("contract_id lookup: {e}")),
            }
        } else {
            notes.push("deploy log missing 'contract deployed: <uuid>' line".into());
        }
    } else {
        notes.push("re-run with --broadcast --private-key-env KEY to submit".into());
    }

    // Preserve prior broadcast ids on save-only re-runs (before writing files).
    let meta_path = req.save_dir.join("deployment.json");
    if (contract_uuid.is_none() || contract_id.is_none()) && meta_path.is_file() {
        if let Ok(prev) = serde_json::from_str::<serde_json::Value>(
            &fs::read_to_string(&meta_path).unwrap_or_default(),
        ) {
            if contract_uuid.is_none() {
                contract_uuid = prev
                    .get("contractUuid")
                    .or_else(|| prev.get("contract_uuid"))
                    .and_then(|x| x.as_str())
                    .map(|s| s.to_string());
            }
            if contract_id.is_none() {
                contract_id = prev
                    .get("contractId")
                    .or_else(|| prev.get("contract_id"))
                    .and_then(|x| {
                        x.as_u64()
                            .or_else(|| x.as_str().and_then(|s| s.parse().ok()))
                    });
            }
        }
    }

    let explorer_hint = Some("https://explorer.psy-protocol.xyz".to_string());
    let services = services_base_url(&rpc_config).ok().flatten();

    // Structured receipt (no private keys)
    let receipt = json!({
        "schema": "proof-forge.pf.psy-deployment.receipt.v1",
        "target": "psy",
        "network": req.network.as_str(),
        "broadcast": req.broadcast,
        "contractPath": dpn.display().to_string(),
        "deployCmdPath": out_path.display().to_string(),
        "rpcConfig": rpc_config.display().to_string(),
        "contractUuid": contract_uuid,
        "contractId": contract_id,
        "explorer": explorer_hint,
        "servicesBase": services,
        "cliTail": combined.chars().rev().take(2000).collect::<String>().chars().rev().collect::<String>(),
    });
    fs::write(
        &receipt_path,
        serde_json::to_string_pretty(&receipt).expect("json"),
    )?;

    // Frontend / follow-up friendly meta (uuid + id).
    let meta = json!({
        "schema": "proof-forge.pf.psy-local-deployment.v1",
        "target": "psy",
        "network": req.network.as_str(),
        "contractUuid": contract_uuid,
        "contractId": contract_id,
        "rpcConfig": rpc_config.display().to_string(),
        "contractPath": dpn.display().to_string(),
        "explorer": explorer_hint,
        "callHint": contract_id.map(|id| format!(
            "pf execute -t psy --network {} --broadcast --private-key-env KEY -- --contract-id {id} initialize 7",
            req.network.as_str()
        )),
    });
    fs::write(
        &meta_path,
        serde_json::to_string_pretty(&meta).expect("json"),
    )?;

    // psyup-compatible sidecar
    if let (Some(u), Some(id)) = (&contract_uuid, contract_id) {
        let psy_deploy = req.save_dir.join(".psy-deploy");
        let body = serde_json::json!({
            "contract_uuid": u,
            "contract_id": id,
        });
        let s = serde_json::to_string(&body).expect("json") + "\n";
        fs::write(&psy_deploy, s)?;
    }

    let mut saved = vec![package_path, out_path, receipt_path, meta_path];
    if req.save_dir.join(".psy-deploy").is_file() {
        saved.push(req.save_dir.join(".psy-deploy"));
    }

    let tail: String = combined.chars().rev().take(800).collect::<String>().chars().rev().collect();

    Ok(DeployOutcome {
        network: req.network.as_str().into(),
        rpc_config,
        broadcast: req.broadcast,
        saved,
        contract_path: dpn,
        notes,
        stdout_tail: tail,
        contract_uuid,
        contract_id,
        explorer_hint,
    })
}


/// Deployment metadata written next to deploy artifacts.
#[derive(Debug, Clone)]
pub struct DeployMeta {
    pub contract_uuid: Option<String>,
    pub contract_id: Option<u64>,
    pub network: Option<String>,
    pub path: PathBuf,
}

pub fn parse_contract_uuid(log: &str) -> Option<String> {
    for line in log.lines() {
        let lower = line.to_ascii_lowercase();
        if let Some(idx) = lower.find("contract deployed:") {
            let rest = line[idx + "contract deployed:".len()..].trim();
            // take first hex token length >= 32
            for tok in rest.split_whitespace() {
                let t = tok.trim_matches(|c: char| !c.is_ascii_hexdigit());
                if t.len() >= 32 && t.chars().all(|c| c.is_ascii_hexdigit()) {
                    return Some(t.to_ascii_lowercase());
                }
            }
        }
    }
    None
}

pub fn services_base_url(rpc_config: &Path) -> PfResult<Option<String>> {
    let text = fs::read_to_string(rpc_config).map_err(|e| PfError::Tool(e.to_string()))?;
    let v: serde_json::Value =
        serde_json::from_str(&text).map_err(|e| PfError::Tool(format!("rpc config: {e}")))?;
    let default = v
        .get("defaultNetwork")
        .and_then(|x| x.as_str())
        .unwrap_or("sepolia");
    if let Some(nets) = v.get("networks").and_then(|n| n.as_object()) {
        let net = nets.get(default).or_else(|| nets.values().next());
        if let Some(n) = net {
            if let Some(arr) = n.get("api_services_url").and_then(|a| a.as_array()) {
                if let Some(u) = arr.first().and_then(|x| x.as_str()) {
                    return Ok(Some(u.trim_end_matches('/').to_string()));
                }
            }
            if let Some(u) = n.get("api_services_url").and_then(|x| x.as_str()) {
                return Ok(Some(u.trim_end_matches('/').to_string()));
            }
        }
    }
    if let Some(u) = v.pointer("/services/psy_services").and_then(|x| x.as_str()) {
        return Ok(Some(u.trim_end_matches('/').to_string()));
    }
    Ok(None)
}

/// Poll official services API for numeric contract_id (psyup-compatible).
pub fn lookup_contract_id(
    rpc_config: &Path,
    uuid: &str,
    attempts: u32,
) -> PfResult<Option<u64>> {
    let base = services_base_url(rpc_config)?
        .ok_or_else(|| PfError::Tool("no api_services_url in rpc config".into()))?;
    let url = format!("{base}/api/v1/transaction/hash/{uuid}");
    for i in 0..attempts {
        let out = Command::new("curl")
            .args(["-sS", "-L", "--max-time", "5", &url])
            .output()
            .map_err(|e| PfError::Tool(format!("curl: {e}")))?;
        if out.status.success() {
            if let Ok(v) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                let status = v
                    .pointer("/data/status")
                    .and_then(|x| x.as_str())
                    .unwrap_or("");
                if status == "included" {
                    if let Some(id) = v
                        .pointer("/data/result/contract_id")
                        .and_then(|x| x.as_u64())
                    {
                        return Ok(Some(id));
                    }
                }
            }
        }
        if i + 1 < attempts {
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }
    Ok(None)
}

pub fn load_deployment_meta(artifact_dir: &Path) -> PfResult<Option<DeployMeta>> {
    let candidates = [
        artifact_dir.join("tx/deployment.json"),
        artifact_dir.join("deployment.json"),
        artifact_dir.join("tx/.psy-deploy"),
    ];
    for p in candidates {
        if !p.is_file() {
            continue;
        }
        let v: serde_json::Value = serde_json::from_str(
            &fs::read_to_string(&p).map_err(|e| PfError::Tool(e.to_string()))?,
        )
        .map_err(|e| PfError::Tool(format!("deployment meta {}: {e}", p.display())))?;
        let uuid = v
            .get("contractUuid")
            .or_else(|| v.get("contract_uuid"))
            .and_then(|x| x.as_str())
            .map(|s| s.to_string());
        let id = v
            .get("contractId")
            .or_else(|| v.get("contract_id"))
            .and_then(|x| {
                x.as_u64()
                    .or_else(|| x.as_str().and_then(|s| s.parse().ok()))
            });
        let network = v
            .get("network")
            .and_then(|x| x.as_str())
            .map(|s| s.to_string());
        return Ok(Some(DeployMeta {
            contract_uuid: uuid,
            contract_id: id,
            network,
            path: p,
        }));
    }
    Ok(None)
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
    fn parse_contract_uuid_from_log() {
        let log = "INFO contract deployed: 3b51455bd8ee8d829f5914bd6e6e40d07ac9c9507ad21d8f23897f04980ba3b8\n";
        assert_eq!(
            parse_contract_uuid(log).as_deref(),
            Some("3b51455bd8ee8d829f5914bd6e6e40d07ac9c9507ad21d8f23897f04980ba3b8")
        );
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
