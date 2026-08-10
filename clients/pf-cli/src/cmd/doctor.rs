use crate::cmd::{compiler_json, emit};
use crate::{compiler, error::PfResult, result_json::PfOk, tools_leo};

pub fn run(targets: &[String], json: bool) -> PfResult<()> {
    let mut owned = vec!["doctor".to_string(), "--json".into()];
    for target in targets {
        owned.extend(["--target".into(), target.clone()]);
    }
    let refs: Vec<&str> = owned.iter().map(String::as_str).collect();
    let out = compiler::run_compiler_checked(&refs, None)?;
    let leo = tools_leo::resolve_leo()
        .ok()
        .map(|p| p.display().to_string());
    let mut ok = PfOk::new("doctor");
    ok.extra = Some(serde_json::json!({"compiler": compiler_json(&out.stdout)?, "leo": leo}));
    emit(ok, json, || {
        println!("proof-forge-next: ok");
        match leo {
            Some(p) => println!("leo: {p}"),
            None => println!("leo: not found (host-optional)"),
        }
    })
}

pub fn setup(target: &str, yes: bool, json: bool) -> PfResult<()> {
    // Aleo's product materializer is zero-tool; setup is intentionally a diagnostic.
    run(&[target.to_string()], json)?;
    if !json {
        println!("setup complete for {target} (yes={yes}); no tools were installed");
    }
    Ok(())
}
