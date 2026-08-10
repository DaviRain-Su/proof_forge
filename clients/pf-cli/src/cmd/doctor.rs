use crate::cmd::{compiler_json, emit};
use crate::{compiler, error::PfResult, result_json::PfOk, tools_leo};
use serde_json::json;
use std::path::PathBuf;

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
    ok.extra = Some(json!({"compiler": compiler_json(&out.stdout)?, "leo": leo}));
    emit(ok, json, || {
        println!("proof-forge-next: ok");
        match leo {
            Some(p) => println!("leo: {p}"),
            None => println!("leo: not found (host-optional)"),
        }
    })
}

/// `pf setup` — doctor + install/path guidance (D9).
///
/// Does **not** silently download random tools into Tool Lock.
/// Prints a concrete checklist so developers can wire `PROOF_FORGE_CLI` and
/// optional chain tools. With `--yes`, may invoke `proof-forge-next install`
/// when the compiler supports it and monorepo root is known.
pub fn setup(target: &str, yes: bool, json: bool) -> PfResult<()> {
    let compiler_path = compiler::resolve_compiler().ok();
    let leo = tools_leo::resolve_leo().ok();
    let root = compiler::resolve_package_root();
    let solana_client = resolve_optional_solana_client();
    let tool_root = std::env::var_os("PROOF_FORGE_TOOL_ROOT")
        .map(PathBuf::from)
        .or_else(default_tool_root_if_exists);

    let mut steps: Vec<String> = Vec::new();
    let mut ready = true;

    match &compiler_path {
        Some(p) => steps.push(format!("ok  compiler: {}", p.display())),
        None => {
            ready = false;
            steps.push(
                "NEED compiler: set PROOF_FORGE_CLI=/path/to/proof-forge-next \
                 (or place it next to `pf`, or build via `lake build proof_forge_next`)"
                    .into(),
            );
        }
    }

    match target {
        "aleo" => match &leo {
            Some(p) => steps.push(format!("ok  leo (host-optional): {}", p.display())),
            None => steps.push(
                "info leo: not found — `pf run`/`pf deploy` need Leo 4.x on PATH or \
                 PROOF_FORGE_ALEO_LEO (Aleo materialize is zero-tool; leo is runtime only)"
                    .into(),
            ),
        },
        "evm" => {
            match &tool_root {
                Some(tr) if tr.join("anvil").is_file() && tr.join("cast").is_file() => {
                    steps.push(format!("ok  anvil+cast under {}", tr.display()));
                }
                _ => {
                    ready = false;
                    steps.push(
                        "NEED EVM tools: locked anvil+cast under PROOF_FORGE_TOOL_ROOT \
                         (see docs / `proof-forge-next install` when available)"
                            .into(),
                    );
                }
            }
            if root.is_some() {
                steps.push(
                    "ok  monorepo root — `pf test -t evm` can use scripts/pf_evm_test.sh".into(),
                );
            } else {
                steps.push(
                    "info monorepo root missing — `pf test -t evm` needs PROOF_FORGE_ROOT \
                     (Anvil matrix script is monorepo-oriented today)"
                        .into(),
                );
            }
        }
        "solana" => {
            match &solana_client {
                Some(p) => steps.push(format!("ok  solana-client (verify): {}", p.display())),
                None => steps.push(
                    "NEED-FOR-VERIFY solana-client: separate binary proof-forge-solana-client \
                     (NOT in crates.io pf package). Set PROOF_FORGE_SOLANA_CLIENT or use \
                     Release/monorepo build of clients/solana-client"
                        .into(),
                ),
            }
            match &tool_root {
                Some(tr) if tr.join("sbpf").is_file() => {
                    steps.push(format!("ok  sbpf under {}", tr.display()));
                }
                _ => steps.push(
                    "info sbpf: not found under PROOF_FORGE_TOOL_ROOT — needed for \
                     `pf build -t solana` finalize on some hosts"
                        .into(),
                ),
            }
            if root.is_some() {
                steps.push(
                    "ok  monorepo root — `pf test -t solana` can use scripts/ + runtime-tests"
                        .into(),
                );
            } else {
                steps.push(
                    "info monorepo root missing — `pf test -t solana` needs PROOF_FORGE_ROOT \
                     (Mollusk harness is monorepo-only today; crates.io install alone is not enough)"
                        .into(),
                );
            }
        }
        _ => steps.push(format!(
            "info target '{target}': build may work via proof-forge-next; \
             developer test/deploy adapters may be limited"
        )),
    }

    // Optional: try compiler install when --yes and root known (never force PATH pollution).
    let mut install_note = None;
    if yes {
        if let (Some(cli), Some(root)) = (&compiler_path, &root) {
            let status = std::process::Command::new(cli)
                .args(["install", "--targets", target, "--yes"])
                .current_dir(root)
                .status();
            match status {
                Ok(s) if s.success() => {
                    install_note = Some(format!(
                        "ran `{} install --targets {target} --yes` under {}",
                        cli.display(),
                        root.display()
                    ));
                }
                Ok(s) => {
                    install_note = Some(format!(
                        "compiler install exited {:?} (non-fatal for setup report)",
                        s.code()
                    ));
                }
                Err(e) => {
                    install_note = Some(format!("compiler install spawn failed: {e}"));
                }
            }
        } else {
            install_note = Some(
                "skipped auto-install: need resolved proof-forge-next + PROOF_FORGE_ROOT/monorepo"
                    .into(),
            );
        }
    }

    // Always surface compiler doctor when possible.
    if compiler_path.is_some() {
        let _ = run(&[target.to_string()], json);
    }

    let mut ok = PfOk::new("setup");
    ok.target = Some(target.into());
    ok.extra = Some(json!({
        "ready": ready,
        "yes": yes,
        "steps": steps,
        "installNote": install_note,
        "paths": {
            "compiler": compiler_path.as_ref().map(|p| p.display().to_string()),
            "leo": leo.as_ref().map(|p| p.display().to_string()),
            "solanaClient": solana_client.as_ref().map(|p| p.display().to_string()),
            "toolRoot": tool_root.as_ref().map(|p| p.display().to_string()),
            "packageRoot": root.as_ref().map(|p| p.display().to_string()),
        },
        "next": next_commands(target),
    }));
    ok.notes = Some(vec![
        "setup never rewrites deployable".into(),
        "does not download unsigned third-party tools into Tool Lock without compiler install"
            .into(),
        "not formal Stage-0".into(),
    ]);

    emit(ok, json, || {
        println!("pf setup — target={target}");
        for s in &steps {
            println!("  {s}");
        }
        if let Some(n) = &install_note {
            println!("  install: {n}");
        }
        println!();
        if ready {
            println!("status: ready enough to try the short path below");
        } else {
            println!("status: missing required pieces — fix NEED lines, then re-run `pf setup`");
        }
        println!("next:");
        for line in next_commands(target) {
            println!("  {line}");
        }
        println!();
        println!("layers: orchestrator(pf) ≠ compiler(proof-forge-next) ≠ host tools ≠ monorepo companions");
        println!("install: INSTALL.md · architecture: ARCHITECTURE.md · publish: PUBLISH.md");
    })
}

fn next_commands(target: &str) -> Vec<String> {
    match target {
        "aleo" => vec![
            "export PROOF_FORGE_CLI=/path/to/proof-forge-next".into(),
            "pf new hello --target aleo && cd hello".into(),
            "pf build && pf run -- initialize 5u64".into(),
        ],
        "solana" => vec![
            "export PROOF_FORGE_CLI=/path/to/proof-forge-next".into(),
            "pf new counter --target solana && cd counter".into(),
            "pf build && pf test".into(),
        ],
        "evm" => vec![
            "export PROOF_FORGE_CLI=/path/to/proof-forge-next".into(),
            "export PROOF_FORGE_TOOL_ROOT=/path/to/locked-foundry".into(),
            "pf new cell --target evm && cd cell".into(),
            "pf build && pf test".into(),
        ],
        _ => vec![
            "export PROOF_FORGE_CLI=/path/to/proof-forge-next".into(),
            format!("pf build -t {target}"),
        ],
    }
}

fn resolve_optional_solana_client() -> Option<PathBuf> {
    crate::targets::solana::verify::resolve_solana_client().ok()
}

fn default_tool_root_if_exists() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let cand = match std::env::consts::OS {
        "macos" => PathBuf::from(&home).join(".cache/proof-forge-v2/tool-root/darwin-arm64"),
        "linux" => PathBuf::from(&home).join(format!(
            ".cache/proof-forge-v2/tool-root/linux-{}",
            std::env::consts::ARCH
        )),
        _ => return None,
    };
    if cand.is_dir() {
        Some(cand)
    } else {
        None
    }
}
