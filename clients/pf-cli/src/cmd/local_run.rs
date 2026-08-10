use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::targets::{self, aleo::local_run};
use std::path::Path;

/// `pf run -- <fn> [inputs...]` or `pf local run ...`
pub fn run(
    target_cli: Option<&str>,
    artifact_cli: Option<&Path>,
    call_args: &[String],
    json: bool,
) -> PfResult<()> {
    if call_args.is_empty() {
        return Err(PfError::Usage(
            "missing function after `--` (example: pf run -- initialize 5u64)".into(),
        ));
    }
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);
    targets::require_aleo(&target)?;
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build` first)",
            dir.display()
        )));
    }
    let function = &call_args[0];
    let inputs = &call_args[1..];
    let artifact = load_aleo_artifact(&dir)?;
    let outcome = local_run::run_local(&artifact, function, inputs)?;
    let mut ok = PfOk::new("run");
    ok.target = Some(target);
    ok.artifact_dir = Some(dir.display().to_string());
    ok.extra = Some(serde_json::json!({
        "stdout": outcome.stdout,
        "importSha256": outcome.import_sha256_hex,
        "function": function,
        "inputs": inputs,
    }));
    emit(ok, json, || {
        print!("{}", outcome.stdout);
        eprint!("{}", outcome.stderr);
    })
}
