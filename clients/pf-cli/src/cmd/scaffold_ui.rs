//! `pf scaffold-ui` — copy dApp UI template + align with pf build artifacts (P1-7).

use crate::cmd::emit;
use crate::cmd::write_ui_json;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

const SKIP_DIR_NAMES: &[&str] = &[
    "node_modules",
    "dist",
    ".git",
    ".DS_Store",
    "target",
];

pub struct ScaffoldOpts<'a> {
    pub template: &'a str,
    pub out: Option<&'a Path>,
    pub artifact: Option<&'a Path>,
    pub address: Option<&'a str>,
    pub network_id: Option<&'a str>,
    pub constructor_initial: u64,
    pub force: bool,
    pub no_sync_artifacts: bool,
    pub json: bool,
}

pub fn run(opts: ScaffoldOpts<'_>) -> PfResult<()> {
    let template_id = normalize_template(opts.template)?;
    let src = resolve_template_dir(template_id)?;
    let project = Project::discover().ok();
    let dest = resolve_dest(opts.out, project.as_ref(), template_id)?;

    if dest.exists() {
        if !opts.force {
            // Allow empty dir
            let empty = fs::read_dir(&dest)
                .map(|mut d| d.next().is_none())
                .unwrap_or(false);
            if !empty {
                return Err(PfError::Usage(format!(
                    "destination exists and is not empty: {}\n\
fix: pf scaffold-ui --template {template_id} --force\n\
# or: --out <other-dir>",
                    dest.display()
                )));
            }
        } else {
            // force: remove and recreate
            fs::remove_dir_all(&dest)?;
        }
    }
    fs::create_dir_all(&dest)?;

    let mut copied = 0usize;
    copy_tree(&src, &dest, &mut copied)?;

    let mut saved = vec![dest.display().to_string()];
    let mut notes = vec![
        format!("template source: {}", src.display()),
        "excluded node_modules/dist from copy".into(),
        "run npm install && npm run dev inside the UI dir".into(),
    ];

    // Sync EVM artifacts into public/ when possible.
    let mut ui_json_path: Option<PathBuf> = None;
    if !opts.no_sync_artifacts && template_id == "evm-dapp" {
        match sync_evm_artifacts(
            project.as_ref(),
            opts.artifact,
            &dest,
            opts.address,
            opts.network_id,
            opts.constructor_initial,
        ) {
            Ok(paths) => {
                for p in paths {
                    saved.push(p.display().to_string());
                    if p.file_name().and_then(|n| n.to_str()) == Some("deployment.json") {
                        ui_json_path = Some(p);
                    }
                }
                notes.push("synced abi/bin (+ optional deployment.json) into public/".into());
            }
            Err(e) => {
                notes.push(format!(
                    "artifact sync skipped: {e} (run pf build -t evm then pf scaffold-ui again, or pf write-ui-json)"
                ));
            }
        }
    }

    let mut ok = PfOk::new("scaffold-ui");
    ok.target = Some(match template_id {
        "evm-dapp" => "evm",
        "solana-dapp" => "solana",
        "aleo-dapp" => "aleo",
        "psy-dapp" => "psy",
        _ => "unknown",
    }.into());
    ok.saved = Some(saved.clone());
    ok.notes = Some(notes.clone());
    ok.extra = Some(json!({
        "schema": "proof-forge.pf.scaffold-ui.v1",
        "template": template_id,
        "source": src.display().to_string(),
        "destination": dest.display().to_string(),
        "filesCopied": copied,
        "deploymentJson": ui_json_path.as_ref().map(|p| p.display().to_string()),
    }));

    emit(ok, opts.json, || {
        println!("    Scaffolded `{template_id}` → {}", dest.display());
        println!("      files: {copied}");
        println!("      source: {}", src.display());
        for n in &notes {
            println!("      note: {n}");
        }
        println!();
        println!("next:");
        println!("  cd {}", dest.display());
        println!("  npm install");
        println!("  npm run dev");
        if template_id == "evm-dapp" {
            println!("  # after pf build -t evm:");
            println!(
                "  # pf write-ui-json -o {}/public/deployment.json",
                dest.display()
            );
        }
    })
}

fn normalize_template(raw: &str) -> PfResult<&'static str> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "evm" | "evm-dapp" | "evm-dapp-ui" => Ok("evm-dapp"),
        "solana" | "solana-dapp" | "solana-dapp-ui" => Ok("solana-dapp"),
        "aleo" | "aleo-dapp" | "aleo-dapp-ui" => Ok("aleo-dapp"),
        "psy" | "psy-dapp" | "psy-dapp-ui" => Ok("psy-dapp"),
        other => Err(PfError::Usage(format!(
            "unknown UI template '{other}'\n\
want: evm-dapp | solana-dapp | aleo-dapp | psy-dapp\n\
fix: pf scaffold-ui --template evm-dapp"
        ))),
    }
}

fn template_folder_name(id: &str) -> &'static str {
    match id {
        "evm-dapp" => "evm-dapp-ui",
        "solana-dapp" => "solana-dapp-ui",
        "aleo-dapp" => "aleo-dapp-ui",
        "psy-dapp" => "psy-dapp-ui",
        _ => "evm-dapp-ui",
    }
}

fn resolve_template_dir(id: &str) -> PfResult<PathBuf> {
    let folder = template_folder_name(id);
    if let Ok(p) = std::env::var("PROOF_FORGE_UI_TEMPLATE_ROOT") {
        let pb = PathBuf::from(&p);
        let cand = if pb.ends_with(folder) {
            pb
        } else {
            pb.join(folder)
        };
        if cand.is_dir() && cand.join("package.json").is_file() {
            return Ok(cand);
        }
        return Err(PfError::Tool(format!(
            "PROOF_FORGE_UI_TEMPLATE_ROOT set but template missing: {}",
            cand.display()
        )));
    }

    let mut cands = Vec::new();
    if let Some(root) = crate::compiler::resolve_package_root() {
        cands.push(root.join("templates").join(folder));
    }
    if let Ok(root) = std::env::var("PROOF_FORGE_ROOT") {
        cands.push(PathBuf::from(root).join("templates").join(folder));
    }
    if let Ok(cwd) = std::env::current_dir() {
        let mut dir = cwd;
        for _ in 0..8 {
            cands.push(dir.join("templates").join(folder));
            if !dir.pop() {
                break;
            }
        }
    }

    for c in &cands {
        if c.is_dir() && c.join("package.json").is_file() {
            return Ok(c.clone());
        }
    }

    Err(PfError::Tool(format!(
        "UI template '{folder}' not found.\n\
External authors: use an engineering **bundle** that includes templates/, or clone monorepo.\n\
fix:\n\
  export PROOF_FORGE_UI_TEMPLATE_ROOT=/path/to/proof_forge/templates\n\
  # or set PROOF_FORGE_ROOT to monorepo/bundle root\n\
  pf scaffold-ui --template {id}\n\
see docs/product/14-external-author-mvp.md · templates/{folder}"
    )))
}

fn resolve_dest(
    out: Option<&Path>,
    project: Option<&Project>,
    template_id: &str,
) -> PfResult<PathBuf> {
    if let Some(o) = out {
        return Ok(o.to_path_buf());
    }
    let base = if let Some(p) = project {
        p.root.clone()
    } else {
        std::env::current_dir()?
    };
    Ok(base.join("ui").join(template_id))
}

fn copy_tree(src: &Path, dst: &Path, count: &mut usize) -> PfResult<()> {
    for entry in fs::read_dir(src).map_err(|e| PfError::Io(e.to_string()))? {
        let entry = entry.map_err(|e| PfError::Io(e.to_string()))?;
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if SKIP_DIR_NAMES.iter().any(|s| *s == name_str) {
            continue;
        }
        if name_str == "package-lock.json" || name_str.ends_with(".tsbuildinfo") {
            continue;
        }
        let from = entry.path();
        let to = dst.join(&name);
        let ft = entry.file_type().map_err(|e| PfError::Io(e.to_string()))?;
        if ft.is_dir() {
            fs::create_dir_all(&to)?;
            copy_tree(&from, &to, count)?;
        } else if ft.is_file() {
            if let Some(parent) = to.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&from, &to).map_err(|e| {
                PfError::Io(format!("copy {} → {}: {e}", from.display(), to.display()))
            })?;
            *count += 1;
        }
    }
    Ok(())
}

fn sync_evm_artifacts(
    project: Option<&Project>,
    artifact_cli: Option<&Path>,
    ui_dest: &Path,
    address: Option<&str>,
    network_id: Option<&str>,
    constructor_initial: u64,
) -> PfResult<Vec<PathBuf>> {
    let artifact_dir = if let Some(a) = artifact_cli {
        a.to_path_buf()
    } else if let Some(p) = project {
        p.resolve_artifact_dir("evm", None, None)
    } else {
        PathBuf::from("build/evm")
    };
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "no artifact dir {} — run `pf build -t evm` first",
            artifact_dir.display()
        )));
    }

    let public = ui_dest.join("public");
    let artifacts = public.join("artifacts");
    fs::create_dir_all(&artifacts)?;

    let mut out = Vec::new();
    // Copy *.abi.json and *.bin
    for entry in fs::read_dir(&artifact_dir).map_err(|e| PfError::Io(e.to_string()))? {
        let entry = entry.map_err(|e| PfError::Io(e.to_string()))?;
        let path = entry.path();
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if name.ends_with(".abi.json") || name.ends_with(".bin") {
            let dest = artifacts.join(name);
            fs::copy(&path, &dest)?;
            out.push(dest);
        }
    }

    // Prefer write-ui-json into public/deployment.json when abi+bin exist.
    let dep = public.join("deployment.json");
    match write_ui_json::run(write_ui_json::WriteUiOpts {
        target: Some("evm"),
        artifact: Some(artifact_dir.as_path()),
        output: Some(dep.as_path()),
        address,
        network_id,
        constructor_initial,
        json: true, // suppress double human noise; we report in scaffold
    }) {
        Ok(()) => out.push(dep),
        Err(e) => {
            // Still ok if only abi/bin copied.
            if out.is_empty() {
                return Err(e);
            }
        }
    }

    Ok(out)
}
