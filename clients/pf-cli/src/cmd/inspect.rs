use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::PfResult;
use crate::project::Project;
use crate::result_json::PfOk;
use std::path::Path;

pub fn run(artifact_cli: Option<&Path>, target_cli: Option<&str>, json: bool) -> PfResult<()> {
    let project = Project::discover()?;
    let target = project.resolve_target(target_cli);
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    // Aleo path validates primary .aleo; other targets just check dir+manifest for now.
    if target == "aleo" {
        let a = load_aleo_artifact(&dir)?;
        let mut ok = PfOk::new("inspect");
        ok.target = Some(target);
        ok.artifact_dir = Some(dir.display().to_string());
        ok.extra = Some(serde_json::json!({
            "programId": a.program_id,
            "sha256": a.sha256_hex,
        }));
        return emit(ok, json, || {
            println!("artifact ok: {}", dir.display());
            println!("  program: {}", a.program_id);
            println!("  sha256:  {}", a.sha256_hex);
        });
    }
    if !dir.join("manifest.json").is_file() {
        return Err(crate::error::PfError::Artifact(format!(
            "missing manifest.json under {}",
            dir.display()
        )));
    }
    let mut ok = PfOk::new("inspect");
    ok.target = Some(target);
    ok.artifact_dir = Some(dir.display().to_string());
    emit(ok, json, || println!("artifact ok: {}", dir.display()))
}
