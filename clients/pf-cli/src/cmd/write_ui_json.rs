//! `pf write-ui-json` — UI attachment JSON for dApp templates (EVM / NEAR / CosmWasm).
//!
//! EVM: abi + bytecode ± address (templates/evm-dapp-ui).
//! NEAR / CosmWasm: save-only deploy package fields + wasm sha + catalog network
//! (templates/near-dapp-ui, templates/cosmwasm-dapp-ui). Never broadcasts.

use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::networks;
use crate::project::Project;
use crate::result_json::PfOk;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

pub struct WriteUiOpts<'a> {
    pub target: Option<&'a str>,
    pub artifact: Option<&'a Path>,
    pub output: Option<&'a Path>,
    pub address: Option<&'a str>,
    pub network_id: Option<&'a str>,
    pub constructor_initial: u64,
    pub json: bool,
}

pub fn run(opts: WriteUiOpts<'_>) -> PfResult<()> {
    let project = Project::discover().ok();
    let target = opts
        .target
        .map(|s| s.to_string())
        .or_else(|| project.as_ref().map(|p| p.resolve_target(None)))
        .unwrap_or_else(|| "evm".into());
    let target_norm = match target.as_str() {
        "cw" => "cosmwasm".to_string(),
        other => other.to_string(),
    };

    let dir = if let Some(a) = opts.artifact {
        a.to_path_buf()
    } else if let Some(p) = &project {
        p.resolve_artifact_dir(&target_norm, None, None)
    } else {
        PathBuf::from(format!("build/{target_norm}"))
    };
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t {target_norm}` first)",
            dir.display()
        )));
    }

    match target_norm.as_str() {
        "evm" => write_evm(&dir, &opts),
        "near" => write_wasm_target("near", &dir, &opts, "near.local.sandbox", "templates/near-dapp-ui"),
        "cosmwasm" => write_wasm_target(
            "cosmwasm",
            &dir,
            &opts,
            "cosmwasm.local.mock",
            "templates/cosmwasm-dapp-ui",
        ),
        other => Err(PfError::Usage(format!(
            "write-ui-json supports --target evm|near|cosmwasm (got '{other}')\n\
fix: pf write-ui-json -t near   # after pf build -t near"
        ))),
    }
}

fn write_evm(dir: &Path, opts: &WriteUiOpts<'_>) -> PfResult<()> {
    let net_id = opts.network_id.unwrap_or("evm.local.anvil");
    let net = networks::find_network(net_id)?;
    let rpc = networks::primary_rpc(&net).unwrap_or_else(|| "http://127.0.0.1:8545".into());
    let chain_id = net
        .get("chainId")
        .and_then(|c| c.as_u64())
        .unwrap_or(31337);

    let (program, abi, bytecode) = load_evm_artifacts(dir)?;
    let out_path = opts
        .output
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| dir.join("ui-deployment.json"));

    let mut body = json!({
        "schema": "proof-forge.pf.evm-local-deployment.v1",
        "target": "evm",
        "network": net_id,
        "rpcUrl": rpc,
        "chainId": chain_id,
        "program": program,
        "constructorInitial": opts.constructor_initial,
        "abi": abi,
        "bytecode": bytecode,
        "notes": [
            "written by pf write-ui-json for templates/evm-dapp-ui",
            "copy to templates/evm-dapp-ui/public/deployment.json or point Vite publicDir",
            "not formal / not mainnet / deployable not rewritten",
        ],
    });

    if let Some(addr) = opts.address {
        let a = addr.trim();
        if !a.starts_with("0x") && !a.starts_with("0X") {
            return Err(PfError::Usage(
                "--address must be 0x-prefixed hex for evm".into(),
            ));
        }
        body.as_object_mut()
            .unwrap()
            .insert("contractAddress".into(), json!(a));
    }

    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(
        &out_path,
        serde_json::to_string_pretty(&body).expect("ui json"),
    )?;

    let side = out_path.parent().unwrap_or(Path::new("."));
    let abi_side = side.join(format!("{program}.abi.json"));
    if !abi_side.exists() {
        if let Ok(src) = find_evm_abi(dir, &program) {
            let _ = fs::copy(src, &abi_side);
        }
    }

    let mut ok = PfOk::new("write-ui-json");
    ok.target = Some("evm".into());
    ok.artifact_dir = Some(dir.display().to_string());
    ok.saved = Some(vec![out_path.display().to_string()]);
    ok.extra = Some(json!({
        "schema": "proof-forge.pf.evm-local-deployment.v1",
        "path": out_path.display().to_string(),
        "networkId": net_id,
        "program": program,
        "hasAddress": opts.address.is_some(),
    }));
    ok.notes = Some(vec![
        "UI template reads public/deployment.json with this schema".into(),
        "without --address the UI can still in-browser deploy from bytecode".into(),
    ]);
    emit(ok, opts.json, || {
        println!("    Wrote UI deployment → {}", out_path.display());
        println!("      network={net_id} chainId={chain_id} program={program}");
        if let Some(a) = opts.address {
            println!("      address={a}");
        } else {
            println!("      address=(none — attach later or deploy in UI)");
        }
        println!(
            "      next: cp {} templates/evm-dapp-ui/public/deployment.json",
            out_path.display()
        );
    })
}

fn write_wasm_target(
    target: &str,
    dir: &Path,
    opts: &WriteUiOpts<'_>,
    default_network: &str,
    template_dir: &str,
) -> PfResult<()> {
    let net_id = opts.network_id.unwrap_or(default_network);
    let net = networks::find_network(net_id).ok();
    let rpc = net
        .as_ref()
        .and_then(|n| networks::primary_rpc(n))
        .unwrap_or_else(|| match target {
            "near" => "http://127.0.0.1:3030".into(),
            _ => "mock://cosmwasm-vm".into(),
        });

    let wasm = find_primary_wasm(dir)?;
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
    let wasm_sha = hex::encode(Sha256::digest(&wasm_bytes));

    let abi_suffix = if target == "near" {
        ".near-abi.json"
    } else {
        ".cosmwasm-abi.json"
    };
    let abi_path = find_optional_sidecar(dir, &program, abi_suffix);
    let abi_json: Option<Value> = abi_path.as_ref().and_then(|p| {
        fs::read_to_string(p)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
    });
    let package_path = dir
        .join("tx")
        .join(format!("{program}.deployment.package.json"));
    let package_json: Option<Value> = if package_path.is_file() {
        fs::read_to_string(&package_path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
    } else {
        None
    };

    let schema = if target == "near" {
        "proof-forge.pf.near-ui-deployment.v1"
    } else {
        "proof-forge.pf.cosmwasm-ui-deployment.v1"
    };

    let out_path = opts
        .output
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| dir.join("ui-deployment.json"));

    let mut body = json!({
        "schema": schema,
        "target": target,
        "network": net_id,
        "rpcUrl": rpc,
        "program": program,
        "wasmPath": wasm.display().to_string(),
        "wasmSha256": wasm_sha,
        "wasmBytes": wasm_bytes.len(),
        "abi": abi_json,
        "deployPackagePath": if package_path.is_file() {
            Some(package_path.display().to_string())
        } else {
            None
        },
        "deployPackage": package_json,
        "broadcastDefault": false,
        "notes": [
            format!("written by pf write-ui-json for {template_dir}"),
            "save-only: pf deploy --broadcast refused for this target in v0",
            "not formal / not mainnet / deployable Wasm not rewritten",
            format!("copy to {template_dir}/public/deployment.json"),
        ],
    });

    if let Some(addr) = opts.address {
        let a = addr.trim();
        if a.is_empty() {
            return Err(PfError::Usage("--address must be non-empty".into()));
        }
        // NEAR account id or CosmWasm bech32 — no 0x requirement.
        body.as_object_mut()
            .unwrap()
            .insert("contractId".into(), json!(a));
    }

    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(
        &out_path,
        serde_json::to_string_pretty(&body).expect("ui json"),
    )?;

    // Copy wasm + abi next to UI file for public/artifacts convenience.
    let side = out_path.parent().unwrap_or(Path::new("."));
    let wasm_side = side.join(format!("{program}.wasm"));
    if !wasm_side.exists() {
        let _ = fs::copy(&wasm, &wasm_side);
    }
    if let Some(abi) = &abi_path {
        let abi_side = side.join(format!("{program}{abi_suffix}"));
        if !abi_side.exists() {
            let _ = fs::copy(abi, &abi_side);
        }
    }

    let mut ok = PfOk::new("write-ui-json");
    ok.target = Some(target.into());
    ok.artifact_dir = Some(dir.display().to_string());
    ok.saved = Some(vec![out_path.display().to_string()]);
    ok.extra = Some(json!({
        "schema": schema,
        "path": out_path.display().to_string(),
        "networkId": net_id,
        "program": program,
        "wasmSha256": wasm_sha,
        "hasContractId": opts.address.is_some(),
    }));
    ok.notes = Some(vec![
        format!("UI skeleton: {template_dir}"),
        "broadcast refused — attach contractId from external deploy tooling".into(),
    ]);
    emit(ok, opts.json, || {
        println!("    Wrote UI deployment → {}", out_path.display());
        println!("      target={target} network={net_id} program={program}");
        println!("      wasmSha256={wasm_sha}");
        if let Some(a) = opts.address {
            println!("      contractId={a}");
        } else {
            println!("      contractId=(none — set --address after external deploy)");
        }
        println!(
            "      next: cp {} {}/public/deployment.json",
            out_path.display(),
            template_dir
        );
    })
}

fn load_evm_artifacts(dir: &Path) -> PfResult<(String, Value, String)> {
    let bin = find_primary_bin(dir)?;
    let program = bin
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Contract")
        .to_string();
    let bytecode = fs::read_to_string(&bin)?
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect::<String>();
    let bytecode = if bytecode.starts_with("0x") || bytecode.starts_with("0X") {
        bytecode
    } else {
        format!("0x{bytecode}")
    };
    let abi_path = find_evm_abi(dir, &program)?;
    let abi_text = fs::read_to_string(&abi_path)?;
    let abi: Value = serde_json::from_str(&abi_text)
        .map_err(|e| PfError::Artifact(format!("invalid ABI JSON {}: {e}", abi_path.display())))?;
    Ok((program, abi, bytecode))
}

fn find_primary_bin(dir: &Path) -> PfResult<PathBuf> {
    let preferred = ["StateCell.bin", "Hello.bin"];
    for name in preferred {
        let p = dir.join(name);
        if p.is_file() {
            return Ok(p);
        }
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

fn find_evm_abi(dir: &Path, program: &str) -> PfResult<PathBuf> {
    let cand = dir.join(format!("{program}.abi.json"));
    if cand.is_file() {
        return Ok(cand);
    }
    let mut abis: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| PfError::Io(e.to_string()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.ends_with(".abi.json"))
        })
        .collect();
    abis.sort();
    abis.into_iter().next().ok_or_else(|| {
        PfError::Artifact(format!(
            "no *.abi.json under {} (run `pf build -t evm` first)",
            dir.display()
        ))
    })
}

fn find_primary_wasm(dir: &Path) -> PfResult<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    collect_wasm(dir, &mut candidates)?;
    if candidates.is_empty() {
        return Err(PfError::Artifact(format!(
            "no .wasm under {} (run pf build first)",
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
