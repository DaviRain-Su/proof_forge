use crate::artifact;
use crate::cmd::{compiler_json, emit};
use crate::compiler;
use crate::error::PfResult;
use crate::result_json::PfOk;
use std::path::Path;

pub fn run(
    source: &Path,
    module: &str,
    target: &str,
    root: Option<&Path>,
    output: &Path,
    profile: Option<&str>,
    json: bool,
) -> PfResult<()> {
    let mut owned = vec![
        "build".into(),
        source.to_string_lossy().into_owned(),
        "--module".into(),
        module.into(),
        "--target".into(),
        target.into(),
        "-o".into(),
        output.to_string_lossy().into_owned(),
        "--json".into(),
    ];
    if let Some(v) = root {
        owned.extend(["--root".into(), v.to_string_lossy().into_owned()]);
    }
    if let Some(v) = profile {
        owned.extend(["--profile".into(), v.into()]);
    }
    let refs: Vec<&str> = owned.iter().map(String::as_str).collect();
    let out = compiler::run_compiler_checked(&refs, None)?;
    if target == "aleo" {
        artifact::load_aleo_artifact(output)?;
    }
    let mut ok = PfOk::new("build");
    ok.target = Some(target.into());
    ok.artifact_dir = Some(output.display().to_string());
    ok.extra = Some(compiler_json(&out.stdout)?);
    emit(ok, json, || {
        println!("built {target} artifact: {}", output.display());
        let stderr = String::from_utf8_lossy(&out.stderr);
        if !stderr.trim().is_empty() {
            eprint!("{stderr}");
        }
    })
}
