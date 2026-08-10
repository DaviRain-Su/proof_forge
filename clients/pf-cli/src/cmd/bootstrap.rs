//! `pf bootstrap` — install engineering bundle (pf + proof-forge-next).

use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::result_json::PfOk;
use serde_json::json;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct BootstrapOpts<'a> {
    pub from: Option<&'a Path>,
    pub prefix: Option<&'a Path>,
    pub url: Option<&'a str>,
    pub sha256: Option<&'a str>,
    pub yes_path: bool,
    pub json: bool,
}

pub fn run(opts: BootstrapOpts<'_>) -> PfResult<()> {
    let install_sh = locate_install_sh()?;
    let mut cmd = Command::new("bash");
    cmd.arg(&install_sh);
    if let Some(from) = opts.from {
        cmd.args(["--from", &from.display().to_string()]);
    }
    if let Some(prefix) = opts.prefix {
        cmd.args(["--prefix", &prefix.display().to_string()]);
    }
    if opts.yes_path {
        cmd.arg("--yes-path");
    }
    if let Some(url) = opts.url {
        cmd.env("PROOF_FORGE_BUNDLE_URL", url);
    }
    if let Some(sha) = opts.sha256 {
        cmd.env("PROOF_FORGE_BUNDLE_SHA256", sha);
    }

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("failed to spawn install.sh: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "bootstrap failed (exit {:?})\n{stderr}{stdout}\n\
fix: download proof-forge-bundle-<ver>-<plat>.tar.gz and:\n\
  pf bootstrap --from /path/to/bundle.tar.gz\n\
see docs/product/14-external-author-mvp.md",
            out.status.code()
        )));
    }

    let mut ok = PfOk::new("bootstrap");
    ok.extra = Some(json!({
        "installScript": install_sh.display().to_string(),
        "stdout": stdout,
        "stderr": stderr,
    }));
    ok.notes = Some(vec![
        "engineering-dist only; not formal Stage-0".into(),
        "after install: export PATH to bundle bin/ and PROOF_FORGE_ROOT".into(),
        "default PROOF_FORGE_HOST_MODE=dev (no hermetic host pin)".into(),
    ]);
    emit(ok, opts.json, || {
        print!("{stdout}");
        if !stderr.trim().is_empty() {
            eprint!("{stderr}");
        }
        println!("bootstrap: ok — run `pf setup --target <t> -y` then `pf new` / `pf build`");
    })
}

fn locate_install_sh() -> PfResult<PathBuf> {
    // 1) PROOF_FORGE_ROOT / monorepo / bundle package root
    if let Some(root) = crate::compiler::resolve_package_root() {
        let p = root.join("scripts").join("install.sh");
        if p.is_file() {
            return Ok(p);
        }
    }
    // 2) sibling of current pf binary: ../scripts/install.sh (bundle) or
    //    monorepo clients/pf-cli → ../../scripts
    if let Ok(exe) = std::env::current_exe() {
        if let Some(bin) = exe.parent() {
            let cand = bin
                .parent()
                .map(|r| r.join("scripts").join("install.sh"))
                .unwrap_or_default();
            if cand.is_file() {
                return Ok(cand);
            }
            // monorepo: clients/pf-cli/target/release/pf → repo scripts/
            let mut dir = bin.to_path_buf();
            for _ in 0..6 {
                let cand = dir.join("scripts").join("install.sh");
                if cand.is_file() {
                    return Ok(cand);
                }
                if !dir.pop() {
                    break;
                }
            }
        }
    }
    Err(PfError::Tool(
        "cannot locate scripts/install.sh\n\
fix: run from a monorepo checkout, a bundle tree, or set PROOF_FORGE_ROOT\n\
  bash /path/to/proof_forge/scripts/install.sh --from bundle.tar.gz"
            .into(),
    ))
}
