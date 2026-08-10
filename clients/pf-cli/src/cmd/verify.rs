use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::targets::{self, solana};
use std::path::Path;

/// `pf verify` — offline chain-artifact verification (Solana D7a).
pub fn run(
    target_cli: Option<&str>,
    artifact_cli: Option<&Path>,
    program_adapter: Option<&str>,
    json: bool,
) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);

    match targets::TargetId::parse(&target) {
        targets::TargetId::Solana => {}
        targets::TargetId::Aleo => {
            return Err(PfError::Usage(
                "aleo: use `pf inspect` for OutputSet checks (no solana-style verify client)"
                    .into(),
            ));
        }
        targets::TargetId::Evm => {
            return Err(PfError::NotImplemented(
                "evm: use `pf test -t evm` (local Anvil); offline verify client not separate"
                    .into(),
            ));
        }
        targets::TargetId::Psy => {
            return Err(PfError::Usage(
                "psy: use `pf inspect` for OutputSet checks and `pf test -t psy` for official DPN simulate"
                    .into(),
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
    let outcome = solana::verify::verify_artifacts(&dir, program_adapter)?;

    let mut ok = PfOk::new("verify");
    ok.target = Some(target.clone());
    ok.artifact_dir = Some(dir.display().to_string());
    ok.extra = Some(serde_json::json!({
        "client": outcome.client_path.display().to_string(),
        "programAdapter": program_adapter,
        "result": outcome.parsed,
    }));
    ok.notes = Some(vec![
        "offline OutputSet self-consistency only".into(),
        "not formal/hermetic/network-write".into(),
        "deployable not rewritten".into(),
    ]);

    emit(ok, json, || {
        println!("    Finished `verify` solana → {}", dir.display());
        if let Some(v) = &outcome.parsed {
            if let Some(name) = v.get("programName").and_then(|x| x.as_str()) {
                println!("  program: {name}");
            }
            if let Some(profile) = v.get("codegenProfile").and_then(|x| x.as_str()) {
                println!("  profile: {profile}");
            }
            if let Some(so) = v.get("soPath").and_then(|x| x.as_str()) {
                println!("  so:      {so}");
            }
            if let Some(adapter) = v.get("programAdapter").and_then(|x| x.as_str()) {
                println!("  adapter: {adapter}");
            }
            println!("  ok:      true (offline joins)");
        } else {
            print!("{}", outcome.stdout);
        }
        if !outcome.stderr.trim().is_empty() {
            eprint!("{}", outcome.stderr);
        }
    })
}
