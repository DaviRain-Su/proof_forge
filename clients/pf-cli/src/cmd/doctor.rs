//! `pf doctor` / `pf setup` — toolchain checklist with copy-paste install commands.

use crate::cmd::{compiler_json, emit};
use crate::{compiler, error::PfResult, result_json::PfOk, tools_leo};
use serde_json::json;
use std::path::PathBuf;
use std::process::Command;

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

/// One installable dependency for human + JSON output.
#[derive(Debug, Clone)]
struct Dep {
    id: &'static str,
    status: &'static str, // "ok" | "need" | "info"
    summary: String,
    /// Shell lines the user can copy (install / export).
    install: Vec<String>,
    path: Option<String>,
}

/// `pf setup` — print what is missing and **exact install commands**.
///
/// With `--yes`, best-effort auto-install of crates.io companions when `cargo`
/// is available (never force-downloads random unsigned host tools into Tool Lock
/// without the compiler's own install path).
pub fn setup(target: &str, yes: bool, json: bool) -> PfResult<()> {
    let mut auto_notes: Vec<String> = Vec::new();
    if yes {
        auto_notes.extend(try_auto_install(target));
    }

    let mut deps = collect_deps(target);
    // Re-scan after auto-install attempts.
    if yes {
        deps = collect_deps(target);
    }

    let ready = deps.iter().all(|d| d.status != "need");
    let install_block: Vec<String> = {
        let mut lines = Vec::new();
        for d in &deps {
            if d.status == "need" || (d.status == "info" && !d.install.is_empty()) {
                lines.push(format!("# --- {} ---", d.id));
                lines.extend(d.install.iter().cloned());
                lines.push(String::new());
            }
        }
        lines
    };

    // Surface compiler doctor JSON when possible (non-fatal).
    if compiler::resolve_compiler().is_ok() {
        let _ = run(&[target.to_string()], json);
    }

    let mut ok = PfOk::new("setup");
    ok.target = Some(target.into());
    ok.extra = Some(json!({
        "ready": ready,
        "yes": yes,
        "autoInstallNotes": auto_notes,
        "dependencies": deps.iter().map(|d| json!({
            "id": d.id,
            "status": d.status,
            "summary": d.summary,
            "install": d.install,
            "path": d.path,
        })).collect::<Vec<_>>(),
        "installCommands": install_block,
        "next": next_commands(target),
    }));
    ok.notes = Some(vec![
        "run `pf setup` first after cargo install".into(),
        "setup never rewrites deployable".into(),
        "crates.io companions: proof-forge-pf + proof-forge-solana-client".into(),
        "compiler proof-forge-next is NOT on crates.io".into(),
        "not formal Stage-0".into(),
    ]);

    emit(ok, json, || {
        println!("pf setup — target={target}");
        println!();
        println!("checklist:");
        for d in &deps {
            let mark = match d.status {
                "ok" => "ok  ",
                "need" => "NEED",
                _ => "info",
            };
            println!("  [{mark}] {}: {}", d.id, d.summary);
            if let Some(p) = &d.path {
                println!("           path: {p}");
            }
        }
        if !auto_notes.is_empty() {
            println!();
            println!("auto-install (--yes):");
            for n in &auto_notes {
                println!("  • {n}");
            }
        }
        if !install_block.iter().all(|l| l.is_empty()) {
            println!();
            println!("install commands (copy-paste):");
            println!("```bash");
            for line in &install_block {
                println!("{line}");
            }
            println!("```");
        }
        println!();
        if ready {
            println!("status: ready — try the short path below");
        } else {
            println!(
                "status: missing NEED items — install, then re-run: pf setup --target {target}"
            );
        }
        println!();
        println!("next:");
        for line in next_commands(target) {
            println!("  {line}");
        }
        println!();
        println!("layers: pf(orchestrator) ≠ proof-forge-next(compiler) ≠ host tools ≠ monorepo test harness");
        println!("docs: INSTALL.md · ARCHITECTURE.md");
    })
}

fn collect_deps(target: &str) -> Vec<Dep> {
    let mut deps = Vec::new();

    // --- always: compiler ---
    match compiler::resolve_compiler() {
        Ok(p) => deps.push(Dep {
            id: "proof-forge-next",
            status: "ok",
            summary: "compiler binary resolved".into(),
            install: vec![],
            path: Some(p.display().to_string()),
        }),
        Err(_) => deps.push(Dep {
            id: "proof-forge-next",
            status: "need",
            summary: "Lean product compiler (NOT on crates.io)".into(),
            install: vec![
                "# pick ONE:".into(),
                "# A) monorepo".into(),
                "git clone https://github.com/DaviRain-Su/proof_forge && cd proof_forge".into(),
                "lake build proof_forge_next".into(),
                "export PROOF_FORGE_CLI=\"$PWD/.lake/build/bin/proof-forge-next\"".into(),
                "# B) side-by-side Release / just pf-cli-dist bundle — place next to `pf`".into(),
                "# export PROOF_FORGE_CLI=/path/to/proof-forge-next".into(),
            ],
            path: None,
        }),
    }

    // --- always remind pf itself ---
    deps.push(Dep {
        id: "proof-forge-pf",
        status: "ok",
        summary: format!("this binary (v{})", env!("CARGO_PKG_VERSION")),
        install: vec![
            "cargo install proof-forge-pf --locked".into(),
            "# binary name: pf".into(),
        ],
        path: std::env::current_exe()
            .ok()
            .map(|p| p.display().to_string()),
    });

    match target {
        "aleo" => match tools_leo::resolve_leo() {
            Ok(p) => deps.push(Dep {
                id: "leo",
                status: "ok",
                summary: "Leo host tool (run/deploy)".into(),
                install: vec![],
                path: Some(p.display().to_string()),
            }),
            Err(_) => deps.push(Dep {
                id: "leo",
                status: "info",
                summary: "optional for pf run/deploy — install Leo 4.x".into(),
                install: vec![
                    "# official Leo (example — check docs.leo-lang.org for current)".into(),
                    "cargo install leo-lang --locked || true".into(),
                    "# or: https://github.com/ProvableHQ/leo#installation".into(),
                    "export PROOF_FORGE_ALEO_LEO=\"$(command -v leo)\"".into(),
                ],
                path: None,
            }),
        },
        "evm" => {
            let tr = tool_root();
            let anvil_ok = tr.as_ref().is_some_and(|t| t.join("anvil").is_file());
            let cast_ok = tr.as_ref().is_some_and(|t| t.join("cast").is_file());
            if anvil_ok && cast_ok {
                deps.push(Dep {
                    id: "anvil+cast",
                    status: "ok",
                    summary: "Foundry tools for pf test / local deploy".into(),
                    install: vec![],
                    path: tr.map(|p| p.display().to_string()),
                });
            } else {
                deps.push(Dep {
                    id: "anvil+cast",
                    status: "need",
                    summary: "Foundry anvil+cast (local EVM)".into(),
                    install: vec![
                        "curl -L https://foundry.paradigm.xyz | bash".into(),
                        "foundryup".into(),
                        "# point Tool Lock / env at the install:".into(),
                        "export PROOF_FORGE_TOOL_ROOT=\"$HOME/.foundry/bin\"".into(),
                        "# or: export FOUNDRY_BIN=\"$HOME/.foundry/bin\"".into(),
                    ],
                    path: None,
                });
            }
            let root = compiler::resolve_package_root();
            if root.is_none() {
                deps.push(Dep {
                    id: "evm-test-harness",
                    status: "info",
                    summary: "pf test -t evm still uses monorepo scripts/pf_evm_test.sh today"
                        .into(),
                    install: vec![
                        "# full EVM test matrix: clone monorepo and set:".into(),
                        "export PROOF_FORGE_ROOT=/path/to/proof_forge".into(),
                        "# save-only package works without monorepo: pf deploy -t evm".into(),
                    ],
                    path: None,
                });
            }
        }
        "solana" => {
            match crate::targets::solana::verify::resolve_solana_client() {
                Ok(p) => deps.push(Dep {
                    id: "proof-forge-solana-client",
                    status: "ok",
                    summary: "offline verifier for pf verify -t solana".into(),
                    install: vec![],
                    path: Some(p.display().to_string()),
                }),
                Err(_) => deps.push(Dep {
                    id: "proof-forge-solana-client",
                    status: "need",
                    summary: "offline Solana OutputSet verifier (crates.io)".into(),
                    install: vec![
                        "cargo install proof-forge-solana-client --locked".into(),
                        "export PROOF_FORGE_SOLANA_CLIENT=\"$(command -v proof-forge-solana-client)\"".into(),
                        "# or place binary next to `pf`".into(),
                        "# monorepo alt:".into(),
                        "# cargo build --manifest-path clients/solana-client/Cargo.toml --release".into(),
                        "# export PROOF_FORGE_SOLANA_CLIENT=$PWD/clients/solana-client/target/release/proof-forge-solana-client".into(),
                    ],
                    path: None,
                }),
            }
            let tr = tool_root();
            if tr.as_ref().is_some_and(|t| t.join("sbpf").is_file()) {
                deps.push(Dep {
                    id: "sbpf",
                    status: "ok",
                    summary: "Solana eBPF assembler/linker for build finalize".into(),
                    install: vec![],
                    path: tr.map(|p| p.display().to_string()),
                });
            } else {
                deps.push(Dep {
                    id: "sbpf",
                    status: "info",
                    summary: "may be required for pf build -t solana finalize".into(),
                    install: vec![
                        "# provided by proof-forge-next install / Tool Lock when available:".into(),
                        "export PROOF_FORGE_TOOL_ROOT=$HOME/.cache/proof-forge-v2/tool-root/$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/arm64/arm64/;s/x86_64/x86_64/')".into(),
                        "# monorepo: lake/env after proof-forge-next install --targets solana".into(),
                    ],
                    path: None,
                });
            }
            if compiler::resolve_package_root().is_none() {
                deps.push(Dep {
                    id: "solana-mollusk-harness",
                    status: "info",
                    summary: "pf test -t solana needs monorepo runtime-tests (Mollusk) today"
                        .into(),
                    install: vec![
                        "export PROOF_FORGE_ROOT=/path/to/proof_forge   # monorepo checkout".into(),
                        "# offline joins without Mollusk:".into(),
                        "pf verify -t solana".into(),
                    ],
                    path: None,
                });
            }
            if which::which("solana").is_err() {
                deps.push(Dep {
                    id: "solana-cli",
                    status: "info",
                    summary: "only for pf deploy --broadcast --network local".into(),
                    install: vec![
                        "sh -c \"$(curl -sSfL https://release.anza.xyz/stable/install)\"".into(),
                        "export PATH=\"$HOME/.local/share/solana/install/active_release/bin:$PATH\"".into(),
                    ],
                    path: None,
                });
            }
        }
        "psy" => {
            match crate::targets::psy::simulate::resolve_psy_user_cli() {
                Ok(p) => deps.push(Dep {
                    id: "psy_user_cli",
                    status: "ok",
                    summary: "official DPN simulate / deploy-contract CLI".into(),
                    install: vec![],
                    path: Some(p.display().to_string()),
                }),
                Err(_) => deps.push(Dep {
                    id: "psy_user_cli",
                    status: "need",
                    summary: "required for pf test/run -t psy (official VM)".into(),
                    install: vec![
                        "curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | sh".into(),
                        "psyup install".into(),
                        "export PATH=\"$HOME/.psy/bin:$PATH\"".into(),
                        "# or: export PROOF_FORGE_PSY_USER_CLI=$HOME/.psy/bin/psy_user_cli".into(),
                    ],
                    path: None,
                }),
            }
        }
        _ => {}
    }

    deps
}

/// Best-effort installs when user passed `--yes`.
fn try_auto_install(target: &str) -> Vec<String> {
    let mut notes = Vec::new();
    let cargo = which::which("cargo").ok();

    // Solana offline verifier from crates.io (or monorepo path).
    if target == "solana" && crate::targets::solana::verify::resolve_solana_client().is_err() {
        if let Some(root) = compiler::resolve_package_root() {
            let mut cmd = match &cargo {
                Some(c) => Command::new(c),
                None => Command::new("cargo"),
            };
            let status = cmd
                .args([
                    "build",
                    "--manifest-path",
                    "clients/solana-client/Cargo.toml",
                    "--locked",
                    "--release",
                ])
                .current_dir(&root)
                .status();
            match status {
                Ok(s) if s.success() => {
                    let bin =
                        root.join("clients/solana-client/target/release/proof-forge-solana-client");
                    if bin.is_file() {
                        std::env::set_var("PROOF_FORGE_SOLANA_CLIENT", &bin);
                        notes.push(format!("built monorepo solana-client → {}", bin.display()));
                    }
                }
                Ok(s) => notes.push(format!(
                    "monorepo solana-client build exited {:?}",
                    s.code()
                )),
                Err(e) => notes.push(format!("monorepo solana-client build spawn failed: {e}")),
            }
        } else if let Some(cargo_bin) = &cargo {
            let status = Command::new(cargo_bin)
                .args([
                    "install",
                    "proof-forge-solana-client",
                    "--locked",
                    "--force",
                ])
                .status();
            match status {
                Ok(s) if s.success() => {
                    notes.push(
                        "cargo install proof-forge-solana-client — ensure ~/.cargo/bin on PATH"
                            .into(),
                    );
                    if let Ok(w) = which::which("proof-forge-solana-client") {
                        std::env::set_var("PROOF_FORGE_SOLANA_CLIENT", &w);
                        notes.push(format!("resolved {}", w.display()));
                    }
                }
                Ok(s) => notes.push(format!(
                    "cargo install proof-forge-solana-client exited {:?} \
                     (publish crate first if 404, or use monorepo build)",
                    s.code()
                )),
                Err(e) => notes.push(format!("cargo install spawn failed: {e}")),
            }
        } else {
            notes.push("cargo not on PATH — cannot auto-install solana-client".into());
        }
    }

    // Compiler install via proof-forge-next when monorepo root known.
    if let (Ok(cli), Some(root)) = (
        compiler::resolve_compiler(),
        compiler::resolve_package_root(),
    ) {
        let status = Command::new(&cli)
            .args(["install", "--targets", target, "--yes"])
            .current_dir(&root)
            .status();
        match status {
            Ok(s) if s.success() => notes.push(format!(
                "ran {} install --targets {target} --yes",
                cli.display()
            )),
            Ok(s) => notes.push(format!(
                "proof-forge-next install exited {:?} (may be ok if tools already locked)",
                s.code()
            )),
            Err(e) => notes.push(format!("proof-forge-next install spawn failed: {e}")),
        }
    }

    notes
}

fn tool_root() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("PROOF_FORGE_TOOL_ROOT") {
        return Some(PathBuf::from(p));
    }
    if let Ok(p) = std::env::var("FOUNDRY_BIN") {
        return Some(PathBuf::from(p));
    }
    default_tool_root_if_exists()
}

fn next_commands(target: &str) -> Vec<String> {
    match target {
        "aleo" => vec![
            "pf setup --target aleo          # until checklist is green".into(),
            "pf new hello --target aleo && cd hello".into(),
            "pf build && pf run -- initialize 5u64".into(),
        ],
        "solana" => vec![
            "pf setup --target solana        # install solana-client if NEED".into(),
            "pf setup --target solana --yes  # best-effort cargo install companions".into(),
            "pf new counter --target solana && cd counter".into(),
            "pf build && pf verify           # verify needs solana-client".into(),
            "pf test                         # needs monorepo Mollusk harness today".into(),
        ],
        "evm" => vec![
            "pf setup --target evm".into(),
            "pf new cell --target evm && cd cell".into(),
            "pf build && pf deploy           # save-only always works with compiler".into(),
            "pf test                         # needs anvil+cast (+ monorepo script today)".into(),
        ],
        "psy" => vec![
            "pf setup --target psy".into(),
            "pf build -t psy                 # → *.dpn.json".into(),
            "pf test -t psy                  # multi-step session (7+5=12)".into(),
            "pf run -t psy -- initialize 7   # official psy_user_cli simulate".into(),
            "pf deploy -t psy                # save-only wraps deploy-contract".into(),
            "pf deploy -t psy --broadcast --network testnet --private-key-env KEY".into(),
            "bash scripts/psy_local_chain_status.sh".into(),
        ],
        _ => vec![
            format!("pf setup --target {target}"),
            format!("pf build -t {target}"),
        ],
    }
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
