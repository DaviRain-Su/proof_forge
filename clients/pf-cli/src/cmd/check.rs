use crate::cmd::{compiler_json, emit};
use crate::compiler;
use crate::error::PfResult;
use crate::project::Project;
use crate::result_json::PfOk;
use std::path::Path;

pub fn run(
    source: Option<&Path>,
    module: Option<&str>,
    root: Option<&Path>,
    json: bool,
) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let (source, module, root_from_project) = project.resolve_source_module(source, module)?;
    let root = root.or(root_from_project.as_deref());
    let mut owned = vec![
        "check".into(),
        source.to_string_lossy().into_owned(),
        "--module".into(),
        module,
        "--json".into(),
    ];
    if let Some(v) = root {
        owned.extend(["--root".into(), v.to_string_lossy().into_owned()]);
    }
    let refs: Vec<&str> = owned.iter().map(String::as_str).collect();
    let out = compiler::run_compiler_checked(&refs, None)?;
    let mut ok = PfOk::new("check");
    ok.extra = Some(compiler_json(&out.stdout)?);
    emit(ok, json, || {
        println!("    Finished `check` ok");
        let stderr = String::from_utf8_lossy(&out.stderr);
        if !stderr.trim().is_empty() {
            eprint!("{stderr}");
        }
    })
}
