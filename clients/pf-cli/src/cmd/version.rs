use crate::cmd::emit;
use crate::{compiler, error::PfResult, result_json::PfOk, tools_leo};

pub fn run(json: bool) -> PfResult<()> {
    let compiler_line = compiler::run_compiler(&["--help"], None)
        .ok()
        .map(|o| {
            let text = String::from_utf8_lossy(&o.stdout);
            // Prefer first non-empty line; help starts with usage.
            text.lines()
                .find(|l| !l.trim().is_empty())
                .unwrap_or("proof-forge-next")
                .to_string()
        });
    let leo_line = tools_leo::resolve_leo()
        .ok()
        .map(|p| tools_leo::leo_version_line(&p))
        .filter(|s| !s.is_empty());
    let version = env!("CARGO_PKG_VERSION");
    let mut ok = PfOk::new("version");
    ok.extra = Some(serde_json::json!({
        "pfVersion": version,
        "compilerHelp": compiler_line,
        "leo": leo_line,
    }));
    emit(ok, json, || {
        println!("pf {version}");
        if let Ok(cli) = compiler::resolve_compiler() {
            println!("compiler: {}", cli.display());
        }
        if let Some(v) = leo_line {
            println!("leo: {v}");
        }
    })
}
