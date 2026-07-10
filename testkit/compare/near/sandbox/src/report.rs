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
    pub allow_semantic_mismatch: bool,
}

impl Args {
    pub fn parse() -> Result<Self> {
        use anyhow::{bail, Context};
        use std::env;

        let mut contract = ContractKind::Counter;
        let mut pf_wasm = None;
        let mut sdk_wasm = None;
        let mut report = None;
        let mut callee_wasm = None;
        let mut repo_root = None;
        let mut allow_semantic_mismatch = false;
        let mut args = env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "-h" | "--help" => {
                    eprintln!(
                        "usage: pf-near-sandbox-dual --contract <name> \
                         --pf-wasm PATH --sdk-wasm PATH [--report PATH] \
                         [--callee-wasm PATH] [--repo-root PATH] \
                         [--allow-semantic-mismatch]"
                    );
                    std::process::exit(0);
                }
                "--contract" => {
                    contract =
                        ContractKind::parse(&args.next().context("--contract requires a value")?)?;
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
                "--allow-semantic-mismatch" => allow_semantic_mismatch = true,
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
            allow_semantic_mismatch,
        })
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ObservationCoverage {
    pub complete: bool,
    pub covered: Vec<String>,
    pub missing: Vec<String>,
    pub comparable_return_steps: usize,
    pub missing_return_steps: usize,
    pub comparable_storage_steps: usize,
}

#[derive(Debug)]
pub(crate) struct SemanticComparison {
    pub observed_matched: bool,
    pub matched: bool,
    pub reason: String,
    pub coverage: ObservationCoverage,
}

fn normalized_call_name(name: &str) -> String {
    name.chars()
        .filter(|c| *c != '_' && *c != '-')
        .flat_map(char::to_lowercase)
        .collect()
}

pub(crate) fn semantic_comparison(pf: &SideReport, sdk: &SideReport) -> SemanticComparison {
    let mut covered = vec!["logs".to_string()];
    let mut missing = vec!["arguments".to_string(), "caller".to_string()];
    if pf.steps.len() != sdk.steps.len() {
        return SemanticComparison {
            observed_matched: false,
            matched: false,
            reason: format!(
                "observed semantics differ: step count ProofForge={} near-sdk={}",
                pf.steps.len(),
                sdk.steps.len()
            ),
            coverage: ObservationCoverage {
                complete: false,
                covered,
                missing: {
                    missing.push("callSequence".into());
                    missing.push("returnValues".into());
                    missing
                },
                comparable_return_steps: 0,
                missing_return_steps: pf.steps.len().max(sdk.steps.len()),
                comparable_storage_steps: 0,
            },
        };
    }

    covered.push("callSequence".into());
    covered.push("successStatus".into());
    let mut comparable_return_steps = 0usize;
    let mut missing_return_steps = 0usize;
    let mut comparable_storage_steps = 0usize;
    let mut observed_mismatch = None;
    for (index, (pf_step, sdk_step)) in pf.steps.iter().zip(&sdk.steps).enumerate() {
        let same_call = normalized_call_name(&pf_step.call) == normalized_call_name(&sdk_step.call);
        let same_status = pf_step.kind == sdk_step.kind && pf_step.ok == sdk_step.ok;
        if observed_mismatch.is_none() && (!same_call || !same_status || !pf_step.ok) {
            observed_mismatch = Some(format!(
                "observed semantics differ at step {index}: PF {} {} ok={}; SDK {} {} ok={}",
                pf_step.kind, pf_step.call, pf_step.ok, sdk_step.kind, sdk_step.call, sdk_step.ok
            ));
        }

        match (pf_step.return_u64, sdk_step.return_u64) {
            (Some(pf_value), Some(sdk_value)) => {
                comparable_return_steps += 1;
                if pf_step.kind == "state" && sdk_step.kind == "state" {
                    comparable_storage_steps += 1;
                }
                if observed_mismatch.is_none() && pf_value != sdk_value {
                    observed_mismatch = Some(format!(
                        "observed semantics differ at step {index}: return PF={pf_value} SDK={sdk_value}"
                    ));
                }
            }
            (None, None) => missing_return_steps += 1,
            (pf_value, sdk_value) => {
                missing_return_steps += 1;
                if observed_mismatch.is_none() {
                    observed_mismatch = Some(format!(
                        "observed semantics differ at step {index}: return PF={pf_value:?} SDK={sdk_value:?}"
                    ));
                }
            }
        }

        if observed_mismatch.is_none() && pf_step.logs != sdk_step.logs {
            observed_mismatch = Some(format!(
                "observed semantics differ at step {index}: logs PF={:?} SDK={:?}",
                pf_step.logs, sdk_step.logs
            ));
        }
    }

    if comparable_return_steps > 0 && missing_return_steps == 0 {
        covered.push("returnValues".into());
    } else {
        missing.push(format!(
            "returnValues({comparable_return_steps}/{} steps)",
            pf.steps.len()
        ));
    }
    if comparable_storage_steps > 0 {
        covered.push("storage".into());
    } else {
        missing.push("storage".into());
    }
    let complete = missing.is_empty();
    let observed_matched = observed_mismatch.is_none();
    let reason = observed_mismatch.unwrap_or_else(|| match complete {
        true => "observed return/log semantics match with complete coverage".into(),
        false => format!(
            "observed return/log semantics match, but observation coverage is incomplete: {}",
            missing.join(", ")
        ),
    });
    SemanticComparison {
        observed_matched,
        matched: observed_matched && complete,
        reason,
        coverage: ObservationCoverage {
            complete,
            covered,
            missing,
            comparable_return_steps,
            missing_return_steps,
            comparable_storage_steps,
        },
    }
}

fn enforce_semantic_gate(comparison: &SemanticComparison, allow_mismatch: bool) -> Result<()> {
    if comparison.matched || allow_mismatch {
        return Ok(());
    }
    anyhow::bail!(
        "semantic gate failed: {}; missing observation coverage: {}; use \
         --allow-semantic-mismatch only for measurement-only report generation",
        comparison.reason,
        comparison.coverage.missing.join(", ")
    )
}

pub(crate) fn write_dual_report(args: &Args, pf: SideReport, sdk: SideReport) -> Result<()> {
    let deploy_ratio = ratio(sdk.deploy_gas_burnt, pf.deploy_gas_burnt);
    let call_ratio = ratio(sdk.call_gas_burnt, pf.call_gas_burnt);
    let storage_ratio = ratio(sdk.storage_usage_bytes, pf.storage_usage_bytes);
    let wasm_ratio = ratio(sdk.wasm_bytes, pf.wasm_bytes);
    let semantic = semantic_comparison(&pf, &sdk);
    let observed_semantic_match = semantic.observed_matched;
    let coverage_complete = semantic.coverage.complete;
    let full_semantic_match = semantic.matched;
    let semantic_gate = enforce_semantic_gate(&semantic, args.allow_semantic_mismatch);

    let report = serde_json::json!({
        "schema": "proof-forge.testkit.compare.near-sandbox.v1",
        "network": "near-sandbox",
        "contract": args.contract.as_str(),
        "proofForge": pf,
        "nearSdk": sdk,
        "comparison": {
            "observedSemanticMatch": semantic.observed_matched,
            "observedSemanticReason": semantic.reason,
            "semanticMatch": semantic.matched,
            "semanticReason": if semantic.matched {
                "observed semantics match with complete observation coverage"
            } else {
                "full semantic equivalence is not established"
            },
            "observationCoverage": semantic.coverage,
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
            "observedSemanticMatch compares only the call/status, return, and log evidence recorded by the harness.",
            "semanticMatch is fail-closed until argument, caller, return, log, and storage observations are complete."
        ],
    });

    if let Some(parent) = args.report.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&args.report, serde_json::to_string_pretty(&report)? + "\n")
        .with_context(|| format!("write {}", args.report.display()))?;

    println!(
        "sandbox dual report — wasm PF={} sdk={} ({}×) | deploy gas PF={} sdk={} ({}×) | call gas PF={} sdk={} ({}×) | storage PF={} sdk={} ({}×)",
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
    println!(
        "observed semantics match={observed_semantic_match} | observation coverage complete={coverage_complete} | semantic match={full_semantic_match}"
    );
    if args.allow_semantic_mismatch && !full_semantic_match {
        eprintln!(
            "measurement-only: --allow-semantic-mismatch bypassed the semantic gate; this report is not eligible for ranking"
        );
    }
    println!("wrote {}", args.report.display());
    semantic_gate
}

#[cfg(test)]
mod tests {
    use super::*;

    fn side(label: &str, call: &str, value: Option<u64>) -> SideReport {
        SideReport {
            label: label.into(),
            account_id: format!("{label}.test"),
            wasm_bytes: 1,
            deploy_gas_burnt: 1,
            storage_usage_bytes: 1,
            call_gas_burnt: 1,
            total_gas_burnt: 2,
            steps: vec![StepReport {
                call: call.into(),
                kind: "view".into(),
                ok: true,
                gas_burnt: None,
                return_u64: value,
                logs: vec![],
                error: None,
            }],
        }
    }

    #[test]
    fn aligned_observations_match_but_incomplete_coverage_fails_closed() {
        let pf = side("pf", "totalSupply", Some(7));
        let sdk = side("sdk", "total_supply", Some(7));
        let comparison = semantic_comparison(&pf, &sdk);
        assert!(comparison.observed_matched, "{}", comparison.reason);
        assert!(!comparison.matched);
        assert!(!comparison.coverage.complete);
        assert!(comparison.coverage.covered.contains(&"returnValues".into()));
        assert!(comparison.coverage.covered.contains(&"logs".into()));
        assert!(comparison.coverage.missing.contains(&"arguments".into()));
        assert!(comparison.coverage.missing.contains(&"caller".into()));
        assert!(comparison.coverage.missing.contains(&"storage".into()));
    }

    #[test]
    fn differing_observations_do_not_match() {
        let pf = side("pf", "get", Some(1));
        let sdk = side("sdk", "get", Some(2));
        let comparison = semantic_comparison(&pf, &sdk);
        assert!(!comparison.matched);
        assert!(!comparison.observed_matched);
        assert!(comparison.reason.contains("step 0"));
    }

    #[test]
    fn call_only_success_is_not_semantic_evidence() {
        let pf = side("pf", "call_remote", None);
        let sdk = side("sdk", "call_remote", None);
        let comparison = semantic_comparison(&pf, &sdk);
        assert!(!comparison.matched);
        assert!(comparison.observed_matched);
        assert!(comparison
            .coverage
            .missing
            .iter()
            .any(|item| item.starts_with("returnValues")));
    }

    #[test]
    fn comparison_is_not_hardcoded_by_contract_kind() {
        let pf = side("pf", "deposit_assets", None);
        let sdk = side("sdk", "deposit_assets", None);
        let comparison = semantic_comparison(&pf, &sdk);
        assert!(!comparison.matched);
        assert!(comparison.observed_matched);
        assert!(!comparison.reason.contains("Promise"));
    }

    #[test]
    fn differing_logs_do_not_match_observed_semantics() {
        let mut pf = side("pf", "get", Some(1));
        let mut sdk = side("sdk", "get", Some(1));
        pf.steps[0].logs.push("pf-event".into());
        sdk.steps[0].logs.push("sdk-event".into());
        let comparison = semantic_comparison(&pf, &sdk);
        assert!(!comparison.observed_matched);
        assert!(!comparison.matched);
        assert!(comparison.reason.contains("logs"));
    }

    #[test]
    fn aligned_state_observation_marks_storage_covered() {
        let mut pf = side("pf", "balance", Some(90));
        let mut sdk = side("sdk", "balance", Some(90));
        pf.steps[0].kind = "state".into();
        sdk.steps[0].kind = "state".into();
        let comparison = semantic_comparison(&pf, &sdk);
        assert!(comparison.coverage.covered.contains(&"storage".into()));
        assert!(!comparison.coverage.missing.contains(&"storage".into()));
    }

    #[test]
    fn semantic_gate_rejects_incomplete_coverage_by_default() {
        let pf = side("pf", "get", Some(7));
        let sdk = side("sdk", "get", Some(7));
        let comparison = semantic_comparison(&pf, &sdk);
        let error = enforce_semantic_gate(&comparison, false).unwrap_err();
        assert!(error.to_string().contains("--allow-semantic-mismatch"));
        enforce_semantic_gate(&comparison, true).unwrap();
    }

    #[test]
    fn canonical_remote_arguments_are_json_arrays() {
        let one: Vec<u64> = serde_json::from_slice(br#"[25]"#).unwrap();
        let two: Vec<u64> = serde_json::from_slice(br#"[100,7]"#).unwrap();
        assert_eq!(one, vec![25]);
        assert_eq!(two, vec![100, 7]);
        assert!(serde_json::from_slice::<Vec<u64>>(&25u64.to_le_bytes()).is_err());
    }
}
