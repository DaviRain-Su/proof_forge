use crate::cmd::emit;
use crate::{compiler, error::PfResult, result_json::PfOk, tools_leo};

pub fn run(json: bool) -> PfResult<()> {
    let compiler_path = compiler::resolve_compiler().ok();
    let compiler_version = compiler_path.as_ref().and_then(|cli| {
        let out = std::process::Command::new(cli)
            .args(["version", "--json"])
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        serde_json::from_slice::<serde_json::Value>(&out.stdout).ok()
    });
    let leo_line = tools_leo::resolve_leo()
        .ok()
        .map(|p| tools_leo::leo_version_line(&p))
        .filter(|s| !s.is_empty());
    let version = env!("CARGO_PKG_VERSION");
    let host_mode = std::env::var("PROOF_FORGE_HOST_MODE").unwrap_or_else(|_| "dev".into());
    let tool_root = std::env::var("PROOF_FORGE_TOOL_ROOT").ok();
    let package_root = compiler::resolve_package_root().map(|p| p.display().to_string());
    let mut ok = PfOk::new("version");
    ok.extra = Some(serde_json::json!({
        "schema": "proof-forge.pf.version.v1",
        "pfVersion": version,
        "channel": "engineering-dist",
        "compilerPath": compiler_path.as_ref().map(|p| p.display().to_string()),
        "compilerVersion": compiler_version,
        "hostMode": host_mode,
        "toolRoot": tool_root,
        "packageRoot": package_root,
        "leo": leo_line,
    }));
    emit(ok, json, || {
        println!("pf {version} (crate proof-forge-pf — orchestrator; engineering-dist)");
        match &compiler_path {
            Some(cli) => {
                println!("compiler: {}", cli.display());
                if let Some(v) = &compiler_version {
                    if let Some(cv) = v.get("version").and_then(|x| x.as_str()) {
                        println!("compilerVersion: {cv}");
                    }
                }
            }
            None => {
                println!(
                    "compiler: NOT FOUND — fix: pf bootstrap --from proof-forge-bundle-*.tar.gz"
                );
            }
        }
        println!("hostMode: {host_mode} (default dev; hermetic = lock-native only)");
        if let Some(tr) = &tool_root {
            println!("toolRoot: {tr}");
        }
        if let Some(pr) = &package_root {
            println!("packageRoot: {pr}");
        }
        if let Some(v) = leo_line {
            println!("leo: {v}");
        }
        println!("docs: docs/product/14-external-author-mvp.md · ADR-0040");
    })
}
