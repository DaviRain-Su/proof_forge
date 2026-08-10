use crate::artifact;
use crate::cmd::{compiler_json, emit};
use crate::compiler;
use crate::error::PfResult;
use crate::project::Project;
use crate::result_json::PfOk;
use std::path::Path;

pub struct BuildOpts<'a> {
    pub source: Option<&'a Path>,
    pub module: Option<&'a str>,
    pub target: Option<&'a str>,
    pub root: Option<&'a Path>,
    pub output: Option<&'a Path>,
    pub profile: Option<&'a str>,
    pub json: bool,
}

pub fn run(opts: BuildOpts<'_>) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(opts.target);
    let (source, module, root_from_project) =
        project.resolve_source_module(opts.source, opts.module)?;
    let root = opts.root.or(root_from_project.as_deref());
    let output = project.resolve_artifact_dir(&target, None, opts.output);

    // Compiler refuses non-empty existing -o dirs (PF-OUTPUT-COLLISION).
    // Cargo-like rebuild: replace the target output directory.
    if output.exists() {
        std::fs::remove_dir_all(&output)?;
    }
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Prefer path relative to --root when possible (external ProgramV1 contract).
    let source_arg = if let Some(r) = root {
        source
            .strip_prefix(r)
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|_| source.clone())
    } else {
        source.clone()
    };
    let mut owned = vec![
        "build".into(),
        source_arg.to_string_lossy().into_owned(),
        "--module".into(),
        module.clone(),
        "--target".into(),
        target.clone(),
        "-o".into(),
        output.to_string_lossy().into_owned(),
        "--json".into(),
    ];
    if let Some(v) = root {
        owned.extend(["--root".into(), v.to_string_lossy().into_owned()]);
    }
    if let Some(v) = opts.profile {
        owned.extend(["--profile".into(), v.into()]);
    }
    let refs: Vec<&str> = owned.iter().map(String::as_str).collect();
    let out = compiler::run_compiler_checked(&refs, None)?;
    if target == "aleo" {
        artifact::load_aleo_artifact(&output)?;
    }
    let mut ok = PfOk::new("build");
    ok.target = Some(target.clone());
    ok.artifact_dir = Some(output.display().to_string());
    ok.extra = Some(compiler_json(&out.stdout)?);
    emit(ok, opts.json, || {
        println!("    Finished `{target}` → {}", output.display());
        let stderr = String::from_utf8_lossy(&out.stderr);
        if !stderr.trim().is_empty() {
            eprint!("{stderr}");
        }
    })
}
