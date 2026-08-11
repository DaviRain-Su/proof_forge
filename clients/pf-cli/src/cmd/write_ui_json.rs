//! `pf write-ui-json` — EVM UI attachment file for templates/evm-dapp-ui (P1-2).

use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::networks;
use crate::project::Project;
use crate::result_json::PfOk;
use serde_json::{json, Value};
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
    if target != "evm" {
        return Err(PfError::Usage(
            "write-ui-json currently supports --target evm only".into(),
        ));
    }

    let dir = if let Some(a) = opts.artifact {
        a.to_path_buf()
    } else if let Some(p) = &project {
        p.resolve_artifact_dir(&target, None, None)
    } else {
        PathBuf::from("build/evm")
    };
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build -t evm` first)",
            dir.display()
        )));
    }

    let net_id = opts.network_id.unwrap_or("evm.local.anvil");
    let net = networks::find_network(net_id)?;
    let rpc = networks::primary_rpc(&net).unwrap_or_else(|| "http://127.0.0.1:8545".into());
    let chain_id = net
        .get("chainId")
        .and_then(|c| c.as_u64())
        .unwrap_or(31337);

    let (program, abi, bytecode) = load_program_artifacts(&dir)?;
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
                "--address must be 0x-prefixed hex".into(),
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

    // Also drop abi/bin copies next to the UI file for manual public/artifacts paths.
    let side = out_path.parent().unwrap_or(Path::new("."));
    let abi_side = side.join(format!("{program}.abi.json"));
    if !abi_side.exists() {
        if let Ok(src) = find_abi(&dir, &program) {
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
        println!("      next: cp {} templates/evm-dapp-ui/public/deployment.json", out_path.display());
    })
}

fn load_program_artifacts(dir: &Path) -> PfResult<(String, Value, String)> {
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
    let abi_path = find_abi(dir, &program)?;
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

fn find_abi(dir: &Path, program: &str) -> PfResult<PathBuf> {
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
