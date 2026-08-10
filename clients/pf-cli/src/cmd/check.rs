use crate::cmd::{compiler_json, emit};
use crate::{compiler, error::PfResult, result_json::PfOk};
use std::path::Path;

pub fn run(source: &Path, module: &str, root: Option<&Path>, json: bool) -> PfResult<()> {
    let mut owned = vec![
        "check".into(),
        source.to_string_lossy().into_owned(),
        "--module".into(),
        module.into(),
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
        println!("check passed: {} ({module})", source.display())
    })
}
