use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::PfResult;
use crate::result_json::PfOk;
use crate::targets::{self, aleo::local_run};
use std::path::Path;

pub fn run(
    target_id: &str,
    dir: &Path,
    function: &str,
    inputs: &[String],
    json: bool,
) -> PfResult<()> {
    targets::require_aleo(target_id)?;
    let artifact = load_aleo_artifact(dir)?;
    let outcome = local_run::run_local(&artifact, function, inputs)?;
    let mut ok = PfOk::new("local run");
    ok.target = Some(target_id.into());
    ok.artifact_dir = Some(dir.display().to_string());
    ok.extra = Some(
        serde_json::json!({"stdout": outcome.stdout, "importSha256": outcome.import_sha256_hex}),
    );
    emit(ok, json, || {
        print!("{}", outcome.stdout);
        eprint!("{}", outcome.stderr);
    })
}
