//! NEAR Sandbox dual-deploy compare (ProofForge wasm vs near-sdk reference).
//!
//! Exit codes:
//!   0 — dual deploy + scenario passed
//!   1 — deploy or scenario failed (or bad CLI)
//!   2 — sandbox unavailable / skip
//!
//! Layout:
//!   kind.rs       — ContractKind
//!   report.rs     — Args, SideReport, write_dual_report
//!   host.rs       — deploy/call/view + SideCtx
//!   scenarios/*   — per-contract dual-deploy scenarios (registry)

mod host;
mod kind;
mod report;
mod scenarios;

use std::process::ExitCode;

use anyhow::{bail, Context, Result};

use crate::host::ensure_file;
use crate::kind::ContractKind;
use crate::report::{write_dual_report, Args, SideKind};
use crate::scenarios::{run_remote_call_matrix, run_side};

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            let msg = format!("{err:#}");
            eprintln!("pf-near-sandbox-dual: {msg}");
            if is_skip_error(&msg) {
                ExitCode::from(2)
            } else {
                ExitCode::from(1)
            }
        }
    }
}

fn is_skip_error(msg: &str) -> bool {
    let lower = msg.to_ascii_lowercase();
    (lower.contains("sandbox")
        && (lower.contains("failed to start")
            || lower.contains("not found")
            || lower.contains("could not")
            || lower.contains("download")
            || lower.contains("permission")
            || lower.contains("unsupported")
            || lower.contains("unable to")))
        || lower.contains("skip:")
}

async fn run() -> Result<()> {
    let args = Args::parse()?;
    ensure_file(&args.pf_wasm, "ProofForge wasm")?;
    ensure_file(&args.sdk_wasm, "near-sdk wasm")?;

    println!(
        "=== near-sandbox dual ({}): start sandbox ===",
        args.contract.as_str()
    );
    let worker = match near_workspaces::sandbox().await {
        Ok(w) => w,
        Err(err) => bail!("skip: failed to start NEAR sandbox: {err:#}"),
    };

    if args.contract == ContractKind::RemoteCall {
        let callee = args
            .callee_wasm
            .as_ref()
            .context("remote-call requires --callee-wasm")?;
        let repo = args
            .repo_root
            .as_ref()
            .context("remote-call requires --repo-root")?;
        println!("=== near-sandbox dual: remote-call multi-account ===");
        let (pf, sdk) =
            run_remote_call_matrix(&worker, repo, &args.pf_wasm, &args.sdk_wasm, callee).await?;
        write_dual_report(&args, pf, sdk)?;
        return Ok(());
    }

    println!("=== near-sandbox dual: deploy + run ProofForge ===");
    let pf = run_side(args.contract, &worker, &args.pf_wasm, SideKind::ProofForge).await?;

    println!("=== near-sandbox dual: deploy + run near-sdk ===");
    let sdk = run_side(args.contract, &worker, &args.sdk_wasm, SideKind::NearSdk).await?;

    write_dual_report(&args, pf, sdk)?;
    Ok(())
}
