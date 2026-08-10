use crate::cmd::{compiler_json, emit};
use crate::{compiler, error::PfResult, result_json::PfOk};
use std::path::Path;

pub fn run(artifact: &Path, json: bool) -> PfResult<()> {
    let arg = artifact.to_string_lossy();
    let out = compiler::run_compiler_checked(&["inspect", "--output-dir", &arg, "--json"], None)?;
    let mut ok = PfOk::new("inspect");
    ok.artifact_dir = Some(artifact.display().to_string());
    ok.extra = Some(compiler_json(&out.stdout)?);
    emit(ok, json, || {
        println!("artifact valid: {}", artifact.display())
    })
}
