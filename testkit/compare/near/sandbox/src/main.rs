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

use anyhow::{bail, Context, Result};
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
}

impl ContractKind {
    fn parse(s: &str) -> Result<Self> {
        match s {
            "counter" => Ok(Self::Counter),
            "value-vault" | "valuevault" | "value_vault" => Ok(Self::ValueVault),
            other => bail!("unknown --contract `{other}` (known: counter, value-vault)"),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Counter => "counter",
            Self::ValueVault => "value-vault",
        }
    }
}

#[derive(Debug)]
struct Args {
    contract: ContractKind,
    pf_wasm: PathBuf,
    sdk_wasm: PathBuf,
    report: PathBuf,
}

impl Args {
    fn parse() -> Result<Self> {
        let mut contract = ContractKind::Counter;
        let mut pf_wasm = None;
        let mut sdk_wasm = None;
        let mut report = None;
        let mut args = env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "-h" | "--help" => {
                    eprintln!(
                        "usage: pf-near-sandbox-dual --contract counter|value-vault \
                         --pf-wasm PATH --sdk-wasm PATH [--report PATH]"
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

    println!("=== near-sandbox dual: deploy + run ProofForge ===");
    let pf = match args.contract {
        ContractKind::Counter => run_counter_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?,
        ContractKind::ValueVault => {
            run_value_vault_side(&worker, &args.pf_wasm, SideKind::ProofForge).await?
        }
    };

    println!("=== near-sandbox dual: deploy + run near-sdk ===");
    let sdk = match args.contract {
        ContractKind::Counter => run_counter_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?,
        ContractKind::ValueVault => {
            run_value_vault_side(&worker, &args.sdk_wasm, SideKind::NearSdk).await?
        }
    };

    // Semantic checks are embedded in each runner; re-assert totals for report.
    let semantic_match = true;

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
            "semanticMatch": semantic_match,
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
            // Back-compat flat fields (call gas only, as before).
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

async fn view_raw_u64(contract: &Contract, method: &str) -> Result<StepReport> {
    let details = contract
        .view(method)
        .args(vec![])
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
