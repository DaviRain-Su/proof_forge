use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::targets::{self, evm};
use std::path::Path;

/// `pf test` — host-optional local runtime checks (D7c: EVM Anvil).
pub fn run(target_cli: Option<&str>, artifact_cli: Option<&Path>, json: bool) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);

    match targets::TargetId::parse(&target) {
        targets::TargetId::Evm => {}
        targets::TargetId::Solana => {
            return Err(PfError::NotImplemented(
                "solana: `pf test` Mollusk pending D7b; use `pf verify -t solana` (offline) for now"
                    .into(),
            ));
        }
        targets::TargetId::Aleo => {
            return Err(PfError::NotImplemented(
                "aleo: `pf test` not in v0; use `pf run -- <fn> …` for local VM".into(),
            ));
        }
        targets::TargetId::Other => {
            return Err(PfError::NotImplemented(format!(
                "target '{target}': {}",
                targets::capability_note(&target)
            )));
        }
    }

    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    let outcome = evm::test::run_anvil_test(&dir)?;

    let mut ok = PfOk::new("test");
    ok.target = Some(target.clone());
    ok.artifact_dir = Some(dir.display().to_string());
    ok.extra = Some(serde_json::json!({
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
        // Prefer the script ok line.
        for line in outcome.stdout.lines().chain(outcome.stderr.lines()) {
            if line.contains("pf-evm-test: ok") || line.contains("pf-evm-test: notes") {
                println!("  {line}");
            }
        }
    })
}
