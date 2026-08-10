use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::targets::{self, evm, solana};
use std::path::Path;

/// `pf test` — host-optional local runtime checks (D7b Solana Mollusk / D7c EVM Anvil).
pub fn run(target_cli: Option<&str>, artifact_cli: Option<&Path>, json: bool) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);

    match targets::TargetId::parse(&target) {
        targets::TargetId::Evm => {
            let outcome = evm::test::run_anvil_test(&dir)?;
            let mut ok = PfOk::new("test");
            ok.target = Some(target.clone());
            ok.artifact_dir = Some(dir.display().to_string());
            ok.extra = Some(serde_json::json!({
                "lane": "anvil-statecell",
                "script": outcome.script_path.display().to_string(),
                "skipped": outcome.skipped,
                "skipReason": outcome.skip_reason,
                "stdout": outcome.stdout,
                "stderr": outcome.stderr,
            }));
            ok.notes = Some(vec![
                "local Anvil only".into(),
                "not formal/hermetic/mainnet".into(),
                "not full differential corpus".into(),
                "deployable not rewritten".into(),
            ]);
            emit(ok, json, || {
                if outcome.skipped {
                    println!(
                        "    Skipped `test` evm → {} ({})",
                        dir.display(),
                        outcome
                            .skip_reason
                            .as_deref()
                            .unwrap_or("host tools missing")
                    );
                    return;
                }
                println!("    Finished `test` evm → {}", dir.display());
                for line in outcome.stdout.lines().chain(outcome.stderr.lines()) {
                    if line.contains("pf-evm-test: ok") || line.contains("pf-evm-test: notes") {
                        println!("  {line}");
                    }
                }
            })
        }
        targets::TargetId::Solana => {
            let outcome = solana::test::run_mollusk_test(&dir)?;
            // Prefer lane marker from script output when present.
            let lane = outcome
                .stdout
                .lines()
                .chain(outcome.stderr.lines())
                .find_map(|l| {
                    l.split_whitespace()
                        .find(|t| t.starts_with("lane="))
                        .map(|t| t.trim_start_matches("lane=").to_string())
                })
                .or_else(|| {
                    if outcome.stdout.contains("state-cell-shaped")
                        || outcome.stderr.contains("state-cell-shaped")
                    {
                        Some("state-cell-shaped".into())
                    } else if outcome.stdout.contains("transfer-sol")
                        || outcome.stderr.contains("transfer-sol")
                    {
                        Some("transfer-sol-cpi-gold".into())
                    } else {
                        Some("mollusk".into())
                    }
                });
            let mut ok = PfOk::new("test");
            ok.target = Some(target.clone());
            ok.artifact_dir = Some(dir.display().to_string());
            ok.extra = Some(serde_json::json!({
                "lane": lane,
                "script": outcome.script_path.display().to_string(),
                "skipped": outcome.skipped,
                "skipReason": outcome.skip_reason,
                "stdout": outcome.stdout,
                "stderr": outcome.stderr,
            }));
            ok.notes = Some(vec![
                "local Mollusk only".into(),
                "default: StateCell-shaped (pf new template); TransferSol = CPI specialty".into(),
                "not formal/hermetic/mainnet".into(),
                "not full solana-runtime corpus".into(),
                "no RPC/wallet/deploy".into(),
                "deployable not rewritten".into(),
            ]);
            emit(ok, json, || {
                if outcome.skipped {
                    println!(
                        "    Skipped `test` solana → {} ({})",
                        dir.display(),
                        outcome
                            .skip_reason
                            .as_deref()
                            .unwrap_or("host tools missing")
                    );
                    return;
                }
                println!("    Finished `test` solana → {}", dir.display());
                for line in outcome.stdout.lines().chain(outcome.stderr.lines()) {
                    if line.contains("pf-solana-test: ok") || line.contains("pf-solana-test: notes")
                    {
                        println!("  {line}");
                    }
                }
            })
        }
        targets::TargetId::Aleo => Err(PfError::NotImplemented(
            "aleo: `pf test` not in v0; use `pf run -- <fn> …` for local VM".into(),
        )),
        targets::TargetId::Other => Err(PfError::NotImplemented(format!(
            "target '{target}': {}",
            targets::capability_note(&target)
        ))),
    }
}
