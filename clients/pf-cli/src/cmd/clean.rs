use crate::cmd::emit;
use crate::error::PfResult;
use crate::project::Project;
use crate::result_json::PfOk;

pub fn run(json: bool) -> PfResult<()> {
    let project = Project::discover()?;
    let output = project.output_root()?;
    let removed = output.exists();
    if removed {
        std::fs::remove_dir_all(&output)?;
    }

    let mut ok = PfOk::new("clean");
    ok.artifact_dir = Some(output.display().to_string());
    ok.extra = Some(serde_json::json!({ "removed": removed }));
    emit(ok, json, || {
        println!("     Cleaned {}", output.display());
    })
}
