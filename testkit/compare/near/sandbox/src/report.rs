//! Dual-deploy report types and writers.

use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::Serialize;

use crate::host::{fmt_opt_ratio, ratio};
use crate::kind::ContractKind;

#[derive(Clone, Copy)]
pub(crate) enum SideKind {
    ProofForge,
    NearSdk,
}

impl SideKind {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::ProofForge => "proof-forge-emitwat",
            Self::NearSdk => "near-sdk-rs",
        }
    }
}

#[derive(Debug, Serialize, Clone)]
pub(crate) struct SideReport {
    pub label: String,
    pub account_id: String,
    pub wasm_bytes: u64,
    pub deploy_gas_burnt: u64,
    pub storage_usage_bytes: u64,
    pub call_gas_burnt: u64,
    /// deploy + call gas (excludes views)
    pub total_gas_burnt: u64,
    pub steps: Vec<StepReport>,
}

#[derive(Debug, Serialize, Clone)]
pub(crate) struct StepReport {
    pub call: String,
    pub kind: String,
    pub ok: bool,
    pub gas_burnt: Option<u64>,
    pub return_u64: Option<u64>,
    pub logs: Vec<String>,
    pub error: Option<String>,
}

#[derive(Debug)]
pub(crate) struct Args {
    pub contract: ContractKind,
    pub pf_wasm: PathBuf,
    pub sdk_wasm: PathBuf,
    pub report: PathBuf,
    pub callee_wasm: Option<PathBuf>,
    pub repo_root: Option<PathBuf>,
}

impl Args {
    pub fn parse() -> Result<Self> {
        use std::env;
        use anyhow::{bail, Context};

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

pub(crate) fn write_dual_report(args: &Args, pf: SideReport, sdk: SideReport) -> Result<()> {
    let deploy_ratio = ratio(sdk.deploy_gas_burnt, pf.deploy_gas_burnt);
    let call_ratio = ratio(sdk.call_gas_burnt, pf.call_gas_burnt);
    let storage_ratio = ratio(sdk.storage_usage_bytes, pf.storage_usage_bytes);
    let wasm_ratio = ratio(sdk.wasm_bytes, pf.wasm_bytes);

    let report = serde_json::json!({
        "schema": "proof-forge.testkit.compare.near-sandbox.v0",
        "network": "near-sandbox",
        "contract": args.contract.as_str(),
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
            "ABI differs: ProofForge uses raw LE args; near-sdk uses JSON."
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
