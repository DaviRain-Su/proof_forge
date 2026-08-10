use crate::cmd::emit;
use crate::{compiler, error::PfResult, result_json::PfOk, tools_leo};

pub fn run(json: bool) -> PfResult<()> {
    let compiler_line = compiler::run_compiler(&["--help"], None).ok().map(|o| {
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
        println!("pf {version} (crate proof-forge-pf — orchestrator only)");
        match compiler::resolve_compiler() {
            Ok(cli) => println!("compiler: {}", cli.display()),
            Err(_) => {
                println!("compiler: NOT FOUND (set PROOF_FORGE_CLI — not shipped on crates.io)")
            }
        }
        if let Some(v) = leo_line {
            println!("leo: {v}");
        }
        println!(
            "note: pf test/verify may need monorepo companions; see `pf setup` / ARCHITECTURE.md"
        );
    })
}
