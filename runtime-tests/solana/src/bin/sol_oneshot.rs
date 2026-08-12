//! One-shot Mollusk runner for `pf run -t solana -- <method> [u64…]`.
//!
//! Engineering only. Not mainnet / formal. Body-only StateCell-shaped programs:
//! single state account + u64 params. CPI / multi-role programs stay on `pf test`.
//!
//! Env:
//!   PF_SOL_ARTIFACT_DIR — OutputSet with *.so + *.idl.json (required)
//!   PF_SOL_METHOD       — method name (init|increment|get|…)
//!   PF_SOL_ARGS         — space-separated u64 decimals
//!   PF_SOL_INIT_ARGS    — auto-init u64 args when method is not init (default: 0)
//!
//! Protocol: discriminator = sha256("proof-forge-solana-v1:{name}({u64,…})")[:8]
//! init → disc name `initialize`.

use {
    mollusk_svm::result::Check,
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_pubkey::Pubkey,
    std::{env, fs, path::PathBuf, process},
};

const DISC_DOMAIN: &str = "proof-forge-solana-v1:";
const LAYOUT_DOMAIN: &str = "proof-forge-solana-layout-v1:";

fn die(msg: impl AsRef<str>) -> ! {
    eprintln!("sol-oneshot: FAIL: {}", msg.as_ref());
    process::exit(1);
}

fn env_req(name: &str) -> String {
    env::var(name).unwrap_or_else(|_| die(format!("missing env {name}")))
}

fn env_opt(name: &str) -> Option<String> {
    env::var(name).ok().filter(|s| !s.is_empty())
}

fn parse_u64s(s: &str) -> Vec<u64> {
    if s.trim().is_empty() {
        return vec![];
    }
    s.split_whitespace()
        .map(|tok| {
            let cleaned = tok.trim_end_matches("u64").trim_end_matches('u');
            cleaned
                .parse::<u64>()
                .unwrap_or_else(|_| die(format!("arg must be u64 decimal, got {tok}")))
        })
        .collect()
}

fn disc_hex(name: &str, param_count: usize) -> String {
    let params = vec!["u64"; param_count].join(",");
    let preimage = format!("{DISC_DOMAIN}{name}({params})");
    let digest = Sha256::digest(preimage.as_bytes());
    hex::encode(&digest[..8])
}

fn disc_bytes(hex16: &str) -> [u8; 8] {
    let raw = hex::decode(hex16).expect("hex");
    let mut out = [0u8; 8];
    out.copy_from_slice(&raw);
    out
}

fn ix_data(disc_hex: &str, params: &[u64]) -> Vec<u8> {
    let mut out = disc_bytes(disc_hex).to_vec();
    for p in params {
        out.extend_from_slice(&p.to_le_bytes());
    }
    out
}

/// Ordinary StateCell layout marker (mirrors tests/common::layout_marker).
/// signature: `1|0:count:0:8:8:u64-le` under domain `proof-forge-solana-layout-v1:`.
fn layout_marker_count() -> u64 {
    let layout_sig = "1|0:count:0:8:8:u64-le";
    let digest = Sha256::digest(format!("{LAYOUT_DOMAIN}{layout_sig}").as_bytes());
    let mut value: u64 = 0;
    for &b in &digest[..8] {
        value = (value << 8) | u64::from(b);
    }
    value
}

fn state_bytes(initialized: bool, count: u64) -> Vec<u8> {
    let mut data = vec![0u8; 16];
    if initialized {
        data[..8].copy_from_slice(&layout_marker_count().to_le_bytes());
        data[8..16].copy_from_slice(&count.to_le_bytes());
    }
    data
}

fn state_account(program_id: &Pubkey, data: Vec<u8>) -> Account {
    Account {
        lamports: 1_000_000_000,
        data,
        owner: *program_id,
        executable: false,
        rent_epoch: 0,
    }
}

/// Map product IDL method name → discriminator name (init → initialize).
fn disc_name(method: &str, mode: &str) -> String {
    if method == "init"
        || mode == "initialize"
        || mode == "initializer"
    {
        "initialize".into()
    } else {
        method.into()
    }
}

#[derive(Debug)]
struct IdlIx {
    name: String,
    mode: String,
    outer_signer: bool,
    outer_writable: bool,
    param_count: usize,
}

fn load_idl(path: &std::path::Path) -> Vec<IdlIx> {
    let text = fs::read_to_string(path).unwrap_or_else(|e| die(format!("read idl: {e}")));
    let v: serde_json::Value =
        serde_json::from_str(&text).unwrap_or_else(|e| die(format!("idl json: {e}")));
    let ixs = v
        .get("instructions")
        .and_then(|x| x.as_array())
        .cloned()
        .unwrap_or_default();
    ixs.into_iter()
        .filter_map(|ix| {
            let name = ix.get("name")?.as_str()?.to_string();
            let mode = ix
                .get("mode")
                .and_then(|m| m.as_str())
                .unwrap_or("entry")
                .to_string();
            let accounts = ix.get("accounts")?.as_array()?;
            let acc0 = accounts.first()?;
            let outer_signer = acc0
                .get("outerSigner")
                .and_then(|b| b.as_bool())
                .unwrap_or(false);
            let outer_writable = acc0
                .get("outerWritable")
                .and_then(|b| b.as_bool())
                .unwrap_or(true);
            // Param count from idl if present; else infer later from CLI args.
            let param_count = ix
                .get("args")
                .and_then(|a| a.as_array())
                .map(|a| a.len())
                .or_else(|| {
                    // Fallback: many PF idls omit args; use mode heuristics.
                    None
                })
                .unwrap_or(usize::MAX); // sentinel → fill from CLI
            Some(IdlIx {
                name,
                mode,
                outer_signer,
                outer_writable,
                param_count,
            })
        })
        .collect()
}

fn find_so_and_idl(dir: &std::path::Path) -> (PathBuf, PathBuf, String) {
    let so = if dir.join("StateCell.so").is_file() {
        dir.join("StateCell.so")
    } else {
        let mut found = None;
        if let Ok(rd) = fs::read_dir(dir) {
            for ent in rd.flatten() {
                let p = ent.path();
                if p.extension().and_then(|e| e.to_str()) == Some("so") {
                    found = Some(p);
                    break;
                }
            }
        }
        found.unwrap_or_else(|| die(format!("no *.so under {}", dir.display())))
    };
    let stem = so
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("program")
        .to_string();
    let idl = {
        let direct = dir.join(format!("{stem}.idl.json"));
        if direct.is_file() {
            direct
        } else {
            let mut found = None;
            if let Ok(rd) = fs::read_dir(dir) {
                for ent in rd.flatten() {
                    let p = ent.path();
                    let n = p.file_name().and_then(|x| x.to_str()).unwrap_or("");
                    if n.ends_with(".idl.json") {
                        found = Some(p);
                        break;
                    }
                }
            }
            found.unwrap_or_else(|| die("no *.idl.json under artifact dir"))
        }
    };
    (so, idl, stem)
}

fn main() {
    let artifact = PathBuf::from(env_req("PF_SOL_ARTIFACT_DIR"));
    let method = env_req("PF_SOL_METHOD");
    let args = parse_u64s(&env_opt("PF_SOL_ARGS").unwrap_or_default());
    let init_args = parse_u64s(&env_opt("PF_SOL_INIT_ARGS").unwrap_or_default());

    if !artifact.join("manifest.json").is_file() {
        die("missing manifest.json (run pf build -t solana first)");
    }
    let (so_path, idl_path, _stem) = find_so_and_idl(&artifact);
    let elf = fs::read(&so_path).unwrap_or_else(|e| die(format!("read so: {e}")));
    let idl = load_idl(&idl_path);

    let program_id = Pubkey::new_unique();
    let state_key = Pubkey::new_unique();
    let mut mollusk = mollusk_svm::Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &program_id,
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &elf,
    );

    let find_ix = |name: &str| -> &IdlIx {
        idl.iter()
            .find(|i| i.name == name)
            .unwrap_or_else(|| die(format!("idl missing method {name}")))
    };

    let run_one = |mollusk: &mollusk_svm::Mollusk,
                   state_data: Vec<u8>,
                   ix_spec: &IdlIx,
                   params: &[u64]|
     -> (Vec<u8>, Option<Vec<u8>>) {
        let dname = disc_name(&ix_spec.name, &ix_spec.mode);
        let nparams = if ix_spec.param_count == usize::MAX {
            params.len()
        } else {
            ix_spec.param_count
        };
        if params.len() != nparams {
            die(format!(
                "method {} wants {nparams} u64 args, got {}",
                ix_spec.name,
                params.len()
            ));
        }
        let disc = disc_hex(&dname, nparams);
        let data = ix_data(&disc, params);
        let meta = if ix_spec.outer_writable {
            AccountMeta::new(state_key, ix_spec.outer_signer)
        } else {
            AccountMeta::new_readonly(state_key, ix_spec.outer_signer)
        };
        let ix = Instruction::new_with_bytes(program_id, &data, vec![meta]);
        let account = state_account(&program_id, state_data);
        let result = mollusk.process_and_validate_instruction(
            &ix,
            &[(state_key, account)],
            &[Check::success()],
        );
        // Post-state data
        let post = result
            .resulting_accounts
            .iter()
            .find(|(pk, _)| pk == &state_key)
            .map(|(_, acc)| acc.data.clone())
            .unwrap_or_default();
        // mollusk-svm 0.13: return_data is Option<Vec<u8>> (or empty).
        let ret = if result.return_data.is_empty() {
            None
        } else {
            Some(result.return_data.clone())
        };
        (post, ret)
    };

    let is_init = method == "init"
        || method == "initialize"
        || method == "constructor"
        || method == "deploy";

    if is_init {
        let ix = find_ix("init");
        let params = if args.is_empty() { vec![0u64] } else { args };
        let (_post, ret) = run_one(&mollusk, state_bytes(false, 0), ix, &params);
        if let Some(rd) = ret {
            if rd.len() >= 8 {
                let v = u64::from_le_bytes(rd[..8].try_into().unwrap());
                println!("{v}");
            } else {
                println!("ok");
            }
        } else {
            println!("ok");
        }
        eprintln!(
            "sol-oneshot: ok mode=init method=init program={}",
            so_path.display()
        );
        return;
    }

    // Auto-init then method.
    let init_ix = find_ix("init");
    let init_params = if init_args.is_empty() {
        vec![0u64]
    } else {
        init_args
    };
    let (after_init, _) = run_one(&mollusk, state_bytes(false, 0), init_ix, &init_params);

    let ix = find_ix(&method);
    let (_post, ret) = run_one(&mollusk, after_init, ix, &args);
    if let Some(rd) = ret {
        if rd.len() >= 8 {
            // Print all full u64 words LE
            let mut words = Vec::new();
            let mut i = 0;
            while i + 8 <= rd.len() {
                words.push(u64::from_le_bytes(rd[i..i + 8].try_into().unwrap()).to_string());
                i += 8;
            }
            if words.is_empty() {
                println!("{}", hex::encode(&rd));
            } else {
                println!("{}", words.join(" "));
            }
        } else if rd.is_empty() {
            println!("ok");
        } else {
            println!("{}", hex::encode(&rd));
        }
    } else {
        println!("ok");
    }
    eprintln!(
        "sol-oneshot: ok mode=call method={method} program={}",
        so_path.display()
    );
}
