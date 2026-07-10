//! NEAR Sandbox dual-deploy compare (ProofForge wasm vs near-sdk reference).
//!
//! Exit codes:
//!   0 — dual deploy + scenario passed
//!   1 — deploy or scenario failed (or bad CLI)
//!   2 — sandbox unavailable / skip
//!
//! Usage:
//!   cargo run --manifest-path testkit/compare/near/sandbox/Cargo.toml -- \
//!     --contract counter \
//!     --pf-wasm PATH --sdk-wasm PATH --report PATH

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{bail, ensure, Context, Result};
use near_gas::NearGas;
use near_workspaces::network::Sandbox;
use near_workspaces::result::ExecutionFinalResult;
use near_workspaces::{Account, Contract, Worker};
use serde::Serialize;
use serde_json::json;

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ContractKind {
    Counter,
    ValueVault,
    FungibleToken,
    Ownable,
    StakingVault,
    RoleGatedToken,
    FeeToken,
    RemoteCall,
    StatusMessage,
    GuestBook,
}

impl ContractKind {
    fn parse(s: &str) -> Result<Self> {
        match s {
            "counter" => Ok(Self::Counter),
            "value-vault" | "valuevault" | "value_vault" => Ok(Self::ValueVault),
            "fungible-token" | "ft" | "fungible_token" => Ok(Self::FungibleToken),
            "ownable" => Ok(Self::Ownable),
            "staking-vault" | "stakingvault" | "staking_vault" => Ok(Self::StakingVault),
            "role-gated-token" | "rolegatedtoken" | "rgt" => Ok(Self::RoleGatedToken),
            "fee-token" | "feetoken" => Ok(Self::FeeToken),
            "remote-call" | "remotecall" | "crosscall" => Ok(Self::RemoteCall),
            "status-message" | "statusmessage" | "status" => Ok(Self::StatusMessage),
            "guestbook" | "guest-book" => Ok(Self::GuestBook),
            other => bail!("unknown --contract `{other}`"),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Counter => "counter",
            Self::ValueVault => "value-vault",
            Self::FungibleToken => "fungible-token",
            Self::Ownable => "ownable",
            Self::StakingVault => "staking-vault",
            Self::RoleGatedToken => "role-gated-token",
            Self::FeeToken => "fee-token",
            Self::RemoteCall => "remote-call",
            Self::StatusMessage => "status-message",
            Self::GuestBook => "guestbook",
        }
    }
}

#[derive(Debug)]
struct Args {
    contract: ContractKind,
    pf_wasm: PathBuf,
    sdk_wasm: PathBuf,
    report: PathBuf,
    /// Optional peer callee wasm (remote-call).
    callee_wasm: Option<PathBuf>,
    /// Repo root for rebuild-with-peer (remote-call live).
    repo_root: Option<PathBuf>,
}

impl Args {
    fn parse() -> Result<Self> {
        let mut contract = ContractKind::Counter;
        let mut pf_wasm = None;
        let mut sdk_wasm = None;
        let mut report = None;
        let mut callee_wasm = None;
        let mut repo_root = None;
        let mut args = env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "-h" | "--help" => {
                    eprintln!(
                        "usage: pf-near-sandbox-dual --contract <name> \
                         --pf-wasm PATH --sdk-wasm PATH [--report PATH] \
                         [--callee-wasm PATH] [--repo-root PATH]"
                    );
                    std::process::exit(0);
                }
                "--contract" => {
                    contract = ContractKind::parse(
                        &args.next().context("--contract requires a value")?,
                    )?;
                }
                "--pf-wasm" => {
                    pf_wasm = Some(PathBuf::from(
                        args.next().context("--pf-wasm requires a path")?,
                    ));
                }
                "--sdk-wasm" => {
                    sdk_wasm = Some(PathBuf::from(
                        args.next().context("--sdk-wasm requires a path")?,
                    ));
                }
                "--report" => {
                    report = Some(PathBuf::from(
                        args.next().context("--report requires a path")?,
                    ));
                }
                "--callee-wasm" => {
                    callee_wasm = Some(PathBuf::from(
                        args.next().context("--callee-wasm requires a path")?,
                    ));
                }
                "--repo-root" => {
                    repo_root = Some(PathBuf::from(
                        args.next().context("--repo-root requires a path")?,
                    ));
                }
                other => bail!("unknown argument `{other}`"),
            }
        }
        let default_report = PathBuf::from(format!(
            "build/testkit/compare/near/{}/sandbox-report.json",
            contract.as_str()
        ));
        Ok(Self {
            contract,
            pf_wasm: pf_wasm.context("missing --pf-wasm")?,
            sdk_wasm: sdk_wasm.context("missing --sdk-wasm")?,
            report: report.unwrap_or(default_report),
            callee_wasm,
            repo_root,
        })
    }
}

#[derive(Debug, Serialize, Clone)]
struct SideReport {
    label: String,
    account_id: String,
    wasm_bytes: u64,
    deploy_gas_burnt: u64,
    storage_usage_bytes: u64,
    call_gas_burnt: u64,
    /// deploy + call gas (excludes views)
    total_gas_burnt: u64,
    steps: Vec<StepReport>,
}

#[derive(Debug, Serialize, Clone)]
struct StepReport {
    call: String,
    kind: String,
    ok: bool,
    gas_burnt: Option<u64>,
    return_u64: Option<u64>,
    logs: Vec<String>,
    error: Option<String>,
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

    // Remote-call needs multi-account peer deploy + PF rebuild with --peer.
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
    let pf = match args.contract {
        ContractKind::Counter => run_counter_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?,
        ContractKind::ValueVault => {
            run_value_vault_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::FungibleToken => {
            run_ft_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::Ownable => {
            run_ownable_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::StakingVault => {
            run_staking_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::RoleGatedToken => {
            run_rgt_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::FeeToken => run_fee_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?,
        ContractKind::StatusMessage => {
            run_status_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::GuestBook => {
            run_guestbook_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
        ContractKind::RemoteCall => unreachable!("handled above"),
    };

    println!("=== near-sandbox dual: deploy + run near-sdk ===");
    let sdk = match args.contract {
        ContractKind::Counter => run_counter_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?,
        ContractKind::ValueVault => {
            run_value_vault_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
        ContractKind::FungibleToken => {
            run_ft_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
        ContractKind::Ownable => run_ownable_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?,
        ContractKind::StakingVault => {
            run_staking_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
        ContractKind::RoleGatedToken => {
            run_rgt_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
        ContractKind::FeeToken => run_fee_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?,
        ContractKind::StatusMessage => {
            run_status_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
        ContractKind::GuestBook => {
            run_guestbook_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
        ContractKind::RemoteCall => unreachable!("handled above"),
    };

    write_dual_report(&args, pf, sdk)?;
    Ok(())
}

fn write_dual_report(args: &Args, pf: SideReport, sdk: SideReport) -> Result<()> {
    let deploy_ratio = ratio(sdk.deploy_gas_burnt, pf.deploy_gas_burnt);
    let call_ratio = ratio(sdk.call_gas_burnt, pf.call_gas_burnt);
    let storage_ratio = ratio(sdk.storage_usage_bytes, pf.storage_usage_bytes);
    let wasm_ratio = ratio(sdk.wasm_bytes, pf.wasm_bytes);

    let report = json!({
        "schema": "proof-forge.testkit.compare.near-sandbox.v0",
        "contract": args.contract.as_str(),
        "network": "near-sandbox",
        "proofForge": pf,
        "nearSdk": sdk,
        "comparison": {
            "semanticMatch": true,
            "wasmBytes": {
                "proofForge": pf.wasm_bytes,
                "nearSdk": sdk.wasm_bytes,
                "nearSdk_vs_proofForge_ratio": wasm_ratio,
            },
            "deployGasBurnt": {
                "proofForge": pf.deploy_gas_burnt,
                "nearSdk": sdk.deploy_gas_burnt,
                "nearSdk_vs_proofForge_ratio": deploy_ratio,
            },
            "callGasBurnt": {
                "proofForge": pf.call_gas_burnt,
                "nearSdk": sdk.call_gas_burnt,
                "nearSdk_vs_proofForge_ratio": call_ratio,
            },
            "storageUsageBytes": {
                "proofForge": pf.storage_usage_bytes,
                "nearSdk": sdk.storage_usage_bytes,
                "nearSdk_vs_proofForge_ratio": storage_ratio,
            },
            "proofForgeTotalGasBurnt": pf.call_gas_burnt,
            "nearSdkTotalGasBurnt": sdk.call_gas_burnt,
            "nearSdk_vs_proofForge_gas_ratio": call_ratio,
        },
        "honesty": [
            "deployGasBurnt is real NEAR sandbox gas for the DeployContract action.",
            "callGasBurnt sums function_call receipts only (views excluded).",
            "storageUsageBytes is account.storage_usage after deploy+scenario (code + state).",
            "Wasm size advantage shows most clearly in wasmBytes and often storageUsageBytes / deployGas.",
            "Call gas is often dominated by storage host ops, so it may not track wasm size.",
            "ABI differs: ProofForge uses raw LE args; near-sdk uses JSON.",
        ],
    });

    if let Some(parent) = args.report.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&args.report, serde_json::to_string_pretty(&report)? + "\n")
        .with_context(|| format!("write {}", args.report.display()))?;

    println!(
        "sandbox dual ok — wasm PF={} sdk={} ({}×) | deploy gas PF={} sdk={} ({}×) | call gas PF={} sdk={} ({}×) | storage PF={} sdk={} ({}×)",
        pf.wasm_bytes,
        sdk.wasm_bytes,
        fmt_opt_ratio(wasm_ratio),
        pf.deploy_gas_burnt,
        sdk.deploy_gas_burnt,
        fmt_opt_ratio(deploy_ratio),
        pf.call_gas_burnt,
        sdk.call_gas_burnt,
        fmt_opt_ratio(call_ratio),
        pf.storage_usage_bytes,
        sdk.storage_usage_bytes,
        fmt_opt_ratio(storage_ratio),
    );
    println!("wrote {}", args.report.display());
    Ok(())
}

#[derive(Clone, Copy)]
enum SideKind {
    ProofForge,
    NearSdk,
}

impl SideKind {
    fn label(self) -> &'static str {
        match self {
            Self::ProofForge => "proof-forge-emitwat",
            Self::NearSdk => "near-sdk-rs",
        }
    }
}

/// Dual-deploy RemoteCall with a live peer account:
/// 1. deploy callee wasm
/// 2. rebuild PF RemoteCall with `--peer peer.callee=<callee_id>`
/// 3. deploy PF + sdk callers; call initialize + call_remote
async fn run_status_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    let alice = contract.id().as_str().to_string();
    let alice_u64 = account_u64(&alice);

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let s = call_raw(&contract, "set_status", &7u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF set_status")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "get_status", &alice_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF get")?;
            ensure_ret(&s, 7, "PF status 7")?;
            steps.push(s);

            let s = call_raw(&contract, "set_status", &99u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF set 99")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "get_status", &alice_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF get 99")?;
            ensure_ret(&s, 99, "PF status 99")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(&contract, "set_status", json!({ "status": 7 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk set")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get_status", json!({ "account": alice })).await?;
            ensure_ok(&s, "sdk get")?;
            ensure_ret(&s, 7, "sdk status 7")?;
            steps.push(s);

            let s = call_json(&contract, "set_status", json!({ "status": 99 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk set 99")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get_status", json!({ "account": alice })).await?;
            ensure_ok(&s, "sdk get 99")?;
            ensure_ret(&s, 99, "sdk status 99")?;
            steps.push(s);
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

async fn run_guestbook_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let s = call_raw(&contract, "add_message", &11u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF add 11")?;
            steps.push(s);

            let s = call_raw(&contract, "add_message", &22u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF add 22")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "total_messages").await?;
            ensure_ok(&s, "PF total")?;
            ensure_ret(&s, 2, "PF total")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "get_message", &0u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF get0")?;
            ensure_ret(&s, 11, "PF msg0")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "get_message", &1u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF get1")?;
            ensure_ret(&s, 22, "PF msg1")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(&contract, "add_message", json!({ "code": 11 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk add 11")?;
            steps.push(s);

            let s = call_json(&contract, "add_message", json!({ "code": 22 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk add 22")?;
            steps.push(s);

            let s = view_json_u64(&contract, "total_messages", json!({})).await?;
            ensure_ok(&s, "sdk total")?;
            ensure_ret(&s, 2, "sdk total")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get_message", json!({ "index": 0 })).await?;
            ensure_ok(&s, "sdk get0")?;
            ensure_ret(&s, 11, "sdk msg0")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get_message", json!({ "index": 1 })).await?;
            ensure_ok(&s, "sdk get1")?;
            ensure_ret(&s, 22, "sdk msg1")?;
            steps.push(s);
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

async fn run_remote_call_matrix(
    worker: &Worker<Sandbox>,
    repo_root: &Path,
    _pf_stub_wasm: &Path,
    sdk_wasm: &Path,
    callee_wasm: &Path,
) -> Result<(SideReport, SideReport)> {
    ensure_file(callee_wasm, "callee wasm")?;
    ensure_file(sdk_wasm, "sdk caller wasm")?;

    // ── callee ──────────────────────────────────────────────────────────────
    let callee_bytes = fs::read(callee_wasm)?;
    let (callee, _c_deploy, _) = deploy_with_metrics(worker, &callee_bytes).await?;
    let s = call_json(&callee, "new", json!({})).await?;
    ensure_ok(&s, "callee new")?;
    let callee_id = callee.id().to_string();
    println!("remote-call: callee account = {callee_id}");

    // ── rebuild PF with peer binding ────────────────────────────────────────
    let pf_out = repo_root.join("build/testkit/compare/near/remote-call/proof-forge-live");
    if pf_out.exists() {
        let _ = fs::remove_dir_all(&pf_out);
    }
    fs::create_dir_all(&pf_out)?;
    let peer_spec = format!("peer.callee={callee_id}");
    let status = std::process::Command::new("lake")
        .current_dir(repo_root)
        .args([
            "env",
            "proof-forge",
            "build",
            "--target",
            "wasm-near",
            "--root",
            ".",
            "--peer",
            &peer_spec,
            "-o",
        ])
        .arg(&pf_out)
        .arg("Examples/Product/RemoteCall.lean")
        .status()
        .context("spawn lake env proof-forge for peer rebuild")?;
    if !status.success() {
        bail!("skip: failed to rebuild PF RemoteCall with --peer (lake/proof-forge unavailable or build failed)");
    }
    let pf_wasm_path = ["remotecall.wasm", "RemoteCall.wasm"]
        .iter()
        .map(|n| pf_out.join(n))
        .find(|p| p.is_file())
        .context("peer-rebuilt PF wasm missing")?;
    // wat2wasm if only wat present
    if !pf_wasm_path.is_file() {
        bail!("peer-rebuilt PF wasm missing at {}", pf_out.display());
    }

    // ── PF caller ───────────────────────────────────────────────────────────
    let pf_bytes = fs::read(&pf_wasm_path)?;
    let pf_wasm_bytes = pf_bytes.len() as u64;
    let (pf_contract, pf_deploy, _) = deploy_with_metrics(worker, &pf_bytes).await?;
    let mut pf_steps = Vec::new();
    let mut pf_call_gas = 0u64;

    let s = call_raw(&pf_contract, "initialize", &[]).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF initialize")?;
    pf_steps.push(s);

    let s = call_raw(&pf_contract, "call_remote", &[]).await?;
    pf_call_gas = pf_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "PF call_remote")?;
    pf_steps.push(s);

    let pf_storage = refresh_storage(&pf_contract).await?;
    let pf = SideReport {
        label: SideKind::ProofForge.label().into(),
        account_id: pf_contract.id().to_string(),
        wasm_bytes: pf_wasm_bytes,
        deploy_gas_burnt: pf_deploy,
        storage_usage_bytes: pf_storage,
        call_gas_burnt: pf_call_gas,
        total_gas_burnt: pf_deploy.saturating_add(pf_call_gas),
        steps: pf_steps,
    };

    // ── sdk caller ──────────────────────────────────────────────────────────
    let sdk_bytes = fs::read(sdk_wasm)?;
    let sdk_wasm_bytes = sdk_bytes.len() as u64;
    let (sdk_contract, sdk_deploy, _) = deploy_with_metrics(worker, &sdk_bytes).await?;
    let mut sdk_steps = Vec::new();
    let mut sdk_call_gas = 0u64;

    let s = call_json(
        &sdk_contract,
        "initialize",
        json!({ "callee": callee_id }),
    )
    .await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk initialize")?;
    sdk_steps.push(s);

    let s = call_json(&sdk_contract, "call_remote", json!({})).await?;
    sdk_call_gas = sdk_call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
    ensure_ok(&s, "sdk call_remote")?;
    sdk_steps.push(s);

    let sdk_storage = refresh_storage(&sdk_contract).await?;
    let sdk = SideReport {
        label: SideKind::NearSdk.label().into(),
        account_id: sdk_contract.id().to_string(),
        wasm_bytes: sdk_wasm_bytes,
        deploy_gas_burnt: sdk_deploy,
        storage_usage_bytes: sdk_storage,
        call_gas_burnt: sdk_call_gas,
        total_gas_burnt: sdk_deploy.saturating_add(sdk_call_gas),
        steps: sdk_steps,
    };

    Ok((pf, sdk))
}

async fn deploy_with_metrics(
    worker: &Worker<Sandbox>,
    wasm: &[u8],
) -> Result<(Contract, u64, u64)> {
    let account: Account = worker
        .dev_create_account()
        .await
        .context("dev_create_account")?;
    let execution = account
        .deploy(wasm)
        .await
        .context("account.deploy")?;
    let deploy_gas = execution.details.total_gas_burnt.as_gas();
    let contract = execution
        .into_result()
        .map_err(|e| anyhow::anyhow!("deploy failed: {e:?}"))?;
    let storage = contract
        .view_account()
        .await
        .context("view_account after deploy")?
        .storage_usage;
    Ok((contract, deploy_gas, storage))
}

async fn refresh_storage(contract: &Contract) -> Result<u64> {
    Ok(contract.view_account().await?.storage_usage)
}

// ─── Counter ────────────────────────────────────────────────────────────────

async fn run_counter_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _storage0) = deploy_with_metrics(worker, &wasm).await?;

    let mut steps = Vec::new();
    let mut call_gas = 0u64;

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "initialize", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF initialize")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "get").await?;
            ensure_ok(&s, "PF get#1")?;
            ensure_ret(&s, 0, "PF get after init")?;
            steps.push(s);

            let s = call_raw(&contract, "increment", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF increment")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "get").await?;
            ensure_ok(&s, "PF get#2")?;
            ensure_ret(&s, 1, "PF get after increment")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "initialize", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk initialize")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get", json!({})).await?;
            ensure_ok(&s, "sdk get#1")?;
            ensure_ret(&s, 0, "sdk get after init")?;
            steps.push(s);

            let s = call_json(&contract, "increment", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk increment")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get", json!({})).await?;
            ensure_ok(&s, "sdk get#2")?;
            ensure_ret(&s, 1, "sdk get after increment")?;
            steps.push(s);
        }
    }

    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

// ─── ValueVault ─────────────────────────────────────────────────────────────

async fn run_value_vault_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;

    let mut steps = Vec::new();
    let mut call_gas = 0u64;

    // Scenario: initialize(100) → get_balance=100 → deposit(50) → get_balance=150
    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "initialize", &100u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF initialize")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "get_balance").await?;
            ensure_ok(&s, "PF get_balance#1")?;
            ensure_ret(&s, 100, "PF balance after init")?;
            steps.push(s);

            let s = call_raw(&contract, "deposit", &50u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF deposit")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "get_balance").await?;
            ensure_ok(&s, "PF get_balance#2")?;
            ensure_ret(&s, 150, "PF balance after deposit")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "initialize", json!({ "initial": 100 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk initialize")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get_balance", json!({})).await?;
            ensure_ok(&s, "sdk get_balance#1")?;
            ensure_ret(&s, 100, "sdk balance after init")?;
            steps.push(s);

            let s = call_json(&contract, "deposit", json!({ "amount": 50 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk deposit")?;
            steps.push(s);

            let s = view_json_u64(&contract, "get_balance", json!({})).await?;
            ensure_ok(&s, "sdk get_balance#2")?;
            ensure_ret(&s, 150, "sdk balance after deposit")?;
            steps.push(s);
        }
    }

    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

// ─── FungibleToken ──────────────────────────────────────────────────────────

fn sha256_32(data: &[u8]) -> [u8; 32] {
    // FIPS 180-4 SHA-256 (same projection as EmitWat / compare driver).
    struct Sha256 {
        h: [u32; 8],
        len: u64,
        buf: [u8; 64],
        buf_len: usize,
    }
    impl Sha256 {
        fn new() -> Self {
            Self {
                h: [
                    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
                    0x1f83d9ab, 0x5be0cd19,
                ],
                len: 0,
                buf: [0; 64],
                buf_len: 0,
            }
        }
        fn update(&mut self, data: &[u8]) {
            for &b in data {
                self.buf[self.buf_len] = b;
                self.buf_len += 1;
                self.len += 1;
                if self.buf_len == 64 {
                    self.compress();
                    self.buf_len = 0;
                }
            }
        }
        fn compress(&mut self) {
            const K: [u32; 64] = [
                0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
                0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
                0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
                0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
                0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
                0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
                0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
                0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
                0xc67178f2,
            ];
            let mut w = [0u32; 64];
            for i in 0..16 {
                w[i] = u32::from_be_bytes([
                    self.buf[i * 4],
                    self.buf[i * 4 + 1],
                    self.buf[i * 4 + 2],
                    self.buf[i * 4 + 3],
                ]);
            }
            for i in 16..64 {
                let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
                let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[i - 7])
                    .wrapping_add(s1);
            }
            let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h) = (
                self.h[0], self.h[1], self.h[2], self.h[3], self.h[4], self.h[5], self.h[6],
                self.h[7],
            );
            for i in 0..64 {
                let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
                let ch = (e & f) ^ ((!e) & g);
                let t1 = h
                    .wrapping_add(s1)
                    .wrapping_add(ch)
                    .wrapping_add(K[i])
                    .wrapping_add(w[i]);
                let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
                let maj = (a & b) ^ (a & c) ^ (b & c);
                let t2 = s0.wrapping_add(maj);
                h = g;
                g = f;
                f = e;
                e = d.wrapping_add(t1);
                d = c;
                c = b;
                b = a;
                a = t1.wrapping_add(t2);
            }
            self.h[0] = self.h[0].wrapping_add(a);
            self.h[1] = self.h[1].wrapping_add(b);
            self.h[2] = self.h[2].wrapping_add(c);
            self.h[3] = self.h[3].wrapping_add(d);
            self.h[4] = self.h[4].wrapping_add(e);
            self.h[5] = self.h[5].wrapping_add(f);
            self.h[6] = self.h[6].wrapping_add(g);
            self.h[7] = self.h[7].wrapping_add(h);
        }
        fn finalize(mut self) -> [u8; 32] {
            let bit_len = self.len * 8;
            self.update(&[0x80]);
            while self.buf_len != 56 {
                self.update(&[0x00]);
            }
            self.update(&bit_len.to_be_bytes());
            let mut out = [0u8; 32];
            for (i, &v) in self.h.iter().enumerate() {
                out[i * 4..(i + 1) * 4].copy_from_slice(&v.to_be_bytes());
            }
            out
        }
    }
    let mut s = Sha256::new();
    s.update(data);
    s.finalize()
}

fn account_hash_borsh(account: &str, amount: Option<u64>) -> Vec<u8> {
    let mut v = sha256_32(account.as_bytes()).to_vec();
    if let Some(a) = amount {
        v.extend_from_slice(&a.to_le_bytes());
    }
    v
}

fn account_u64(account: &str) -> u64 {
    u64::from_le_bytes(sha256_32(account.as_bytes())[..8].try_into().unwrap())
}

async fn run_ft_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    // alice is the deploy account (predecessor for PF raw calls from contract account).
    // For FT mint/transfer we call from the contract's account — predecessor is
    // the signer. near-workspaces contract.call uses the contract account as
    // predecessor. Mint to that account's hash, transfer to bob (hash of
    // "bob.testnet" — balance map only, no bob account needed for PF).
    let alice = contract.id().as_str();
    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let mint_args = account_hash_borsh(alice, Some(100));
            let s = call_raw(&contract, "ft_mint", &mint_args).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF ft_mint")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "ft_total_supply", &[]).await?;
            ensure_ok(&s, "PF supply")?;
            ensure_ret(&s, 100, "PF supply after mint")?;
            steps.push(s);

            let bal_args = account_hash_borsh(alice, None);
            let s = view_raw_u64_args(&contract, "ft_balance_of", &bal_args).await?;
            ensure_ok(&s, "PF bal alice")?;
            ensure_ret(&s, 100, "PF alice bal")?;
            steps.push(s);

            let xfer = account_hash_borsh("bob.testnet", Some(30));
            let s = call_raw(&contract, "ft_transfer", &xfer).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF ft_transfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "ft_balance_of", &bal_args).await?;
            ensure_ok(&s, "PF bal alice after")?;
            ensure_ret(&s, 70, "PF alice after xfer")?;
            steps.push(s);

            let bob_args = account_hash_borsh("bob.testnet", None);
            let s = view_raw_u64_args(&contract, "ft_balance_of", &bob_args).await?;
            ensure_ok(&s, "PF bal bob")?;
            ensure_ret(&s, 30, "PF bob bal")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(
                &contract,
                "ft_mint",
                json!({ "account_id": alice, "amount": 100 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk ft_mint")?;
            steps.push(s);

            let s = view_json_u64(&contract, "ft_total_supply", json!({})).await?;
            ensure_ok(&s, "sdk supply")?;
            ensure_ret(&s, 100, "sdk supply")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "ft_balance_of",
                json!({ "account_id": alice }),
            )
            .await?;
            ensure_ok(&s, "sdk bal alice")?;
            ensure_ret(&s, 100, "sdk alice bal")?;
            steps.push(s);

            // Create bob account so LookupMap AccountId is valid; transfer as contract
            // (predecessor = contract id which we minted to).
            let bob = worker.dev_create_account().await.context("create bob")?;
            let s = call_json(
                &contract,
                "ft_transfer",
                json!({ "receiver_id": bob.id().as_str(), "amount": 30 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk ft_transfer")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "ft_balance_of",
                json!({ "account_id": alice }),
            )
            .await?;
            ensure_ok(&s, "sdk bal alice after")?;
            ensure_ret(&s, 70, "sdk alice after")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "ft_balance_of",
                json!({ "account_id": bob.id().as_str() }),
            )
            .await?;
            ensure_ok(&s, "sdk bal bob")?;
            ensure_ret(&s, 30, "sdk bob bal")?;
            steps.push(s);
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

async fn run_ownable_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    let alice = contract.id().as_str().to_string();
    let alice_u64 = account_u64(&alice);

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "owner").await?;
            ensure_ok(&s, "PF owner#1")?;
            ensure_ret(&s, alice_u64, "PF owner after init")?;
            steps.push(s);

            let bob = worker.dev_create_account().await.context("bob")?;
            let bob_u64 = account_u64(bob.id().as_str());
            let s = call_raw(&contract, "transferOwnership", &bob_u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF transferOwnership")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "owner").await?;
            ensure_ok(&s, "PF owner#2")?;
            ensure_ret(&s, bob_u64, "PF owner after transfer")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            // owner view returns AccountId string — check via view bytes/json.
            let details = contract.view("owner").args_json(json!({})).await?;
            let owner: String = details.json().context("owner AccountId")?;
            ensure!(
                owner == alice,
                "sdk owner after init: expected {alice}, got {owner}"
            );
            steps.push(StepReport {
                call: "owner".into(),
                kind: "view".into(),
                ok: true,
                gas_burnt: None,
                return_u64: None,
                logs: details.logs,
                error: None,
            });

            let bob = worker.dev_create_account().await.context("bob")?;
            let s = call_json(
                &contract,
                "transfer_ownership",
                json!({ "new_owner": bob.id().as_str() }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk transfer_ownership")?;
            steps.push(s);

            let details = contract.view("owner").args_json(json!({})).await?;
            let owner: String = details.json().context("owner2")?;
            ensure!(
                owner == bob.id().as_str(),
                "sdk owner after transfer: expected {}, got {owner}",
                bob.id()
            );
            steps.push(StepReport {
                call: "owner".into(),
                kind: "view".into(),
                ok: true,
                gas_burnt: None,
                return_u64: None,
                logs: details.logs,
                error: None,
            });
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

async fn run_staking_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let s = call_raw_deposit(&contract, "deposit", &[], 50).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF deposit")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "totalDeposits").await?;
            ensure_ok(&s, "PF total#1")?;
            ensure_ret(&s, 50, "PF total after deposit")?;
            steps.push(s);

            let s = call_raw(&contract, "withdraw", &20u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF withdraw")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "totalDeposits").await?;
            ensure_ok(&s, "PF total#2")?;
            ensure_ret(&s, 30, "PF total after withdraw")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json_deposit(&contract, "deposit", json!({}), 50).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk deposit")?;
            steps.push(s);

            let s = view_json_u64(&contract, "total_deposits", json!({})).await?;
            ensure_ok(&s, "sdk total#1")?;
            ensure_ret(&s, 50, "sdk total after deposit")?;
            steps.push(s);

            let s = call_json(&contract, "withdraw", json!({ "share_amount": 20 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk withdraw")?;
            steps.push(s);

            let s = view_json_u64(&contract, "total_deposits", json!({})).await?;
            ensure_ok(&s, "sdk total#2")?;
            ensure_ret(&s, 30, "sdk total after withdraw")?;
            steps.push(s);
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

async fn run_rgt_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    let alice = contract.id().as_str().to_string();
    let alice_u64 = account_u64(&alice);

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &[]).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            // grant minter role (1) to self
            let mut grant = 1u64.to_le_bytes().to_vec();
            grant.extend_from_slice(&alice_u64.to_le_bytes());
            let s = call_raw(&contract, "grantRole", &grant).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF grantRole")?;
            steps.push(s);

            let mut mint = alice_u64.to_le_bytes().to_vec();
            mint.extend_from_slice(&100u64.to_le_bytes());
            let s = call_raw(&contract, "mint", &mint).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF mint")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &alice_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal")?;
            ensure_ret(&s, 100, "PF bal after mint")?;
            steps.push(s);

            let bob_u64 = account_u64("bob.testnet");
            let mut xfer = bob_u64.to_le_bytes().to_vec();
            xfer.extend_from_slice(&30u64.to_le_bytes());
            let s = call_raw(&contract, "transfer", &xfer).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF transfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &alice_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal alice")?;
            ensure_ret(&s, 70, "PF alice after xfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &bob_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal bob")?;
            ensure_ret(&s, 30, "PF bob after xfer")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "totalSupply").await?;
            ensure_ok(&s, "PF supply")?;
            ensure_ret(&s, 100, "PF supply")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({})).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(
                &contract,
                "grant_role",
                json!({ "role": 1, "who": alice }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk grant_role")?;
            steps.push(s);

            let s = call_json(
                &contract,
                "mint",
                json!({ "recipient": alice, "amount": 100 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk mint")?;
            steps.push(s);

            let s = view_json_u64(&contract, "balance_of", json!({ "who": alice })).await?;
            ensure_ok(&s, "sdk bal")?;
            ensure_ret(&s, 100, "sdk bal after mint")?;
            steps.push(s);

            let bob = worker.dev_create_account().await.context("bob")?;
            let s = call_json(
                &contract,
                "transfer",
                json!({ "recipient": bob.id().as_str(), "amount": 30 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk transfer")?;
            steps.push(s);

            let s = view_json_u64(&contract, "balance_of", json!({ "who": alice })).await?;
            ensure_ok(&s, "sdk bal alice")?;
            ensure_ret(&s, 70, "sdk alice")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "balance_of",
                json!({ "who": bob.id().as_str() }),
            )
            .await?;
            ensure_ok(&s, "sdk bal bob")?;
            ensure_ret(&s, 30, "sdk bob")?;
            steps.push(s);

            let s = view_json_u64(&contract, "total_supply", json!({})).await?;
            ensure_ok(&s, "sdk supply")?;
            ensure_ret(&s, 100, "sdk supply")?;
            steps.push(s);
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

async fn run_fee_side(
    worker: &Worker<Sandbox>,
    wasm_path: &Path,
    kind: SideKind,
) -> Result<SideReport> {
    let wasm = fs::read(wasm_path)?;
    let wasm_bytes = wasm.len() as u64;
    let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
    let mut steps = Vec::new();
    let mut call_gas = 0u64;
    let alice = contract.id().as_str().to_string();
    let alice_u64 = account_u64(&alice);

    match kind {
        SideKind::ProofForge => {
            let s = call_raw(&contract, "init", &1000u64.to_le_bytes()).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF init")?;
            steps.push(s);

            let mut mint = alice_u64.to_le_bytes().to_vec();
            mint.extend_from_slice(&100u64.to_le_bytes());
            let s = call_raw(&contract, "mint", &mint).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF mint")?;
            steps.push(s);

            let bob_u64 = account_u64("bob.testnet");
            let mut xfer = bob_u64.to_le_bytes().to_vec();
            xfer.extend_from_slice(&50u64.to_le_bytes());
            let s = call_raw(&contract, "transfer", &xfer).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "PF transfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &alice_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal alice")?;
            ensure_ret(&s, 50, "PF alice after fee xfer")?;
            steps.push(s);

            let s = view_raw_u64_args(&contract, "balanceOf", &bob_u64.to_le_bytes()).await?;
            ensure_ok(&s, "PF bal bob")?;
            ensure_ret(&s, 45, "PF bob net")?;
            steps.push(s);

            let s = view_raw_u64(&contract, "totalSupply").await?;
            ensure_ok(&s, "PF supply")?;
            ensure_ret(&s, 95, "PF supply after fee")?;
            steps.push(s);
        }
        SideKind::NearSdk => {
            let s = call_json(&contract, "init", json!({ "fee_bps": 1000 })).await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk init")?;
            steps.push(s);

            let s = call_json(
                &contract,
                "mint",
                json!({ "recipient": alice, "amount": 100 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk mint")?;
            steps.push(s);

            let bob = worker.dev_create_account().await.context("bob")?;
            let s = call_json(
                &contract,
                "transfer",
                json!({ "recipient": bob.id().as_str(), "amount": 50 }),
            )
            .await?;
            call_gas = call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
            ensure_ok(&s, "sdk transfer")?;
            steps.push(s);

            let s = view_json_u64(&contract, "balance_of", json!({ "who": alice })).await?;
            ensure_ok(&s, "sdk bal alice")?;
            ensure_ret(&s, 50, "sdk alice")?;
            steps.push(s);

            let s = view_json_u64(
                &contract,
                "balance_of",
                json!({ "who": bob.id().as_str() }),
            )
            .await?;
            ensure_ok(&s, "sdk bal bob")?;
            ensure_ret(&s, 45, "sdk bob")?;
            steps.push(s);

            let s = view_json_u64(&contract, "total_supply", json!({})).await?;
            ensure_ok(&s, "sdk supply")?;
            ensure_ret(&s, 95, "sdk supply")?;
            steps.push(s);
        }
    }
    let storage = refresh_storage(&contract).await?;
    Ok(SideReport {
        label: kind.label().into(),
        account_id: contract.id().to_string(),
        wasm_bytes,
        deploy_gas_burnt: deploy_gas,
        storage_usage_bytes: storage,
        call_gas_burnt: call_gas,
        total_gas_burnt: deploy_gas.saturating_add(call_gas),
        steps,
    })
}

// ─── call helpers ───────────────────────────────────────────────────────────

async fn call_raw(contract: &Contract, method: &str, args: &[u8]) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args(args.to_vec())
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}`"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

async fn call_json(
    contract: &Contract,
    method: &str,
    args: serde_json::Value,
) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args_json(args)
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}` json"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

async fn call_raw_deposit(
    contract: &Contract,
    method: &str,
    args: &[u8],
    deposit_yocto: u128,
) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args(args.to_vec())
        .deposit(near_workspaces::types::NearToken::from_yoctonear(deposit_yocto))
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}` deposit"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

async fn call_json_deposit(
    contract: &Contract,
    method: &str,
    args: serde_json::Value,
    deposit_yocto: u128,
) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args_json(args)
        .deposit(near_workspaces::types::NearToken::from_yoctonear(deposit_yocto))
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}` deposit json"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

async fn view_raw_u64(contract: &Contract, method: &str) -> Result<StepReport> {
    view_raw_u64_args(contract, method, &[]).await
}

async fn view_raw_u64_args(
    contract: &Contract,
    method: &str,
    args: &[u8],
) -> Result<StepReport> {
    let details = contract
        .view(method)
        .args(args.to_vec())
        .await
        .with_context(|| format!("view `{method}`"))?;
    let bytes = details.result;
    let return_u64 = decode_le_u64(&bytes)?;
    Ok(StepReport {
        call: method.into(),
        kind: "view".into(),
        ok: true,
        gas_burnt: None,
        return_u64: Some(return_u64),
        logs: details.logs,
        error: None,
    })
}

async fn view_json_u64(
    contract: &Contract,
    method: &str,
    args: serde_json::Value,
) -> Result<StepReport> {
    let details = contract
        .view(method)
        .args_json(args)
        .await
        .with_context(|| format!("view `{method}` json"))?;
    let val: u64 = details.json().context("json u64")?;
    Ok(StepReport {
        call: method.into(),
        kind: "view".into(),
        ok: true,
        gas_burnt: None,
        return_u64: Some(val),
        logs: details.logs,
        error: None,
    })
}

fn decode_le_u64(bytes: &[u8]) -> Result<u64> {
    if bytes.len() == 8 {
        return Ok(u64::from_le_bytes(bytes.try_into().unwrap()));
    }
    if let Ok(v) = serde_json::from_slice::<u64>(bytes) {
        return Ok(v);
    }
    bail!("expected LE u64 (8 bytes), got {} bytes: {bytes:02x?}", bytes.len());
}

fn step_from_outcome(call: &str, kind: &str, outcome: ExecutionFinalResult) -> StepReport {
    let gas = outcome.total_gas_burnt.as_gas();
    let logs: Vec<String> = outcome.logs().iter().map(|s| (*s).to_string()).collect();
    if outcome.is_success() {
        StepReport {
            call: call.into(),
            kind: kind.into(),
            ok: true,
            gas_burnt: Some(gas),
            return_u64: None,
            logs,
            error: None,
        }
    } else {
        let err = format!("{:?}", outcome.into_result().err());
        StepReport {
            call: call.into(),
            kind: kind.into(),
            ok: false,
            gas_burnt: Some(gas),
            return_u64: None,
            logs,
            error: Some(err),
        }
    }
}

fn ensure_ok(step: &StepReport, label: &str) -> Result<()> {
    if !step.ok {
        bail!(
            "{label} failed: {}",
            step.error.as_deref().unwrap_or("unknown")
        );
    }
    Ok(())
}

fn ensure_ret(step: &StepReport, expected: u64, label: &str) -> Result<()> {
    if step.return_u64 != Some(expected) {
        bail!("{label}: expected {expected}, got {:?}", step.return_u64);
    }
    Ok(())
}

fn ensure_file(path: &Path, label: &str) -> Result<()> {
    if !path.is_file() {
        bail!("{label} missing: {}", path.display());
    }
    Ok(())
}

fn ratio(num: u64, den: u64) -> Option<f64> {
    if den == 0 {
        None
    } else {
        Some(round3(num as f64 / den as f64))
    }
}

fn fmt_opt_ratio(r: Option<f64>) -> String {
    r.map(|v| format!("{v:.3}")).unwrap_or_else(|| "n/a".into())
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}
