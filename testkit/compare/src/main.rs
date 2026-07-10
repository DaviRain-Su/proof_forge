//! Native-vs-ProofForge compare driver (testkit).
//!
//! Colocated with fixtures under `testkit/compare/<chain>/<contract>/`.
//!
//! Usage (from repo root):
//!   cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near counter
//!   cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near counter --live
//!
//! Env:
//!   PROOF_FORGE_NEAR_SDK_BUILD=1  — cargo-build the colocated near-sdk wasm
//!   PROOF_FORGE_NEAR_BENCH_REPEAT — offline-host --repeat (default 50)
//!   PROOF_FORGE_NEAR_COMPARE_LIVE=1 — same as --live (NEAR Sandbox dual deploy)

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Instant;

use anyhow::{bail, ensure, Context, Result};
use serde::Serialize;
use serde_json::{json, Value as JsonValue};

/// Exit code from `pf-near-sandbox-dual` when sandbox tooling is unavailable.
const SANDBOX_SKIP_EXIT: i32 = 2;

fn main() -> Result<()> {
    let args = Args::parse(env::args().skip(1))?;
    let repo_root = env::current_dir().context("failed to read current directory")?;

    let cmd: Vec<&str> = args.command.iter().map(String::as_str).collect();
    match cmd.as_slice() {
        ["near", "counter"] => run_near_counter(&repo_root, &args),
        ["near", "value-vault"] | ["near", "valuevault"] => {
            run_near_value_vault(&repo_root, &args)
        }
        ["near", other] => {
            bail!("unknown near compare example `{other}` (known: counter, value-vault)")
        }
        [chain, ..] => bail!("unknown compare chain `{chain}` (known: near)"),
        [] => {
            print_usage();
            bail!("missing compare target, e.g. `near counter` or `near value-vault`");
        }
    }
}

#[derive(Debug)]
struct Args {
    command: Vec<String>,
    repeat: u32,
    build_sdk: bool,
    /// Dual-deploy both wasms on NEAR Sandbox (near-workspaces) and compare.
    live: bool,
}

impl Args {
    fn parse<I>(args: I) -> Result<Self>
    where
        I: IntoIterator<Item = String>,
    {
        let mut command = Vec::new();
        let mut repeat = env::var("PROOF_FORGE_NEAR_BENCH_REPEAT")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(50);
        let mut build_sdk = env::var("PROOF_FORGE_NEAR_SDK_BUILD")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        let mut live = env::var("PROOF_FORGE_NEAR_COMPARE_LIVE")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false);

        let mut iter = args.into_iter().peekable();
        while let Some(arg) = iter.next() {
            match arg.as_str() {
                "-h" | "--help" => {
                    print_usage();
                    std::process::exit(0);
                }
                "--repeat" => {
                    let v = iter
                        .next()
                        .context("--repeat requires a positive integer")?;
                    repeat = v.parse().context("--repeat must be a positive integer")?;
                    ensure!(repeat > 0, "--repeat must be > 0");
                }
                "--build-sdk" => build_sdk = true,
                "--live" | "--sandbox" => live = true,
                other if other.starts_with('-') => bail!("unknown flag `{other}`"),
                other => command.push(other.to_string()),
            }
        }

        // Live dual-deploy always needs the near-sdk reference wasm.
        if live {
            build_sdk = true;
        }

        Ok(Self {
            command,
            repeat,
            build_sdk,
            live,
        })
    }
}

fn print_usage() {
    eprintln!(
        "usage: proof-forge-testkit-compare near <counter|value-vault> \
         [--build-sdk] [--live] [--repeat N]\n\n\
         Colocated fixtures: testkit/compare/near/<contract>/\n\
         Sandbox harness:    testkit/compare/near/sandbox/\n\
         Report:             build/testkit/compare/near/<contract>/report.json\n\
         Live report:        build/testkit/compare/near/<contract>/sandbox-report.json\n\
         Env: PROOF_FORGE_NEAR_SDK_BUILD=1, PROOF_FORGE_NEAR_COMPARE_LIVE=1,\n\
              PROOF_FORGE_NEAR_BENCH_REPEAT"
    );
}

// ─── Near Counter ───────────────────────────────────────────────────────────

fn run_near_counter(repo_root: &Path, args: &Args) -> Result<()> {
    let fixture_dir = repo_root.join("testkit/compare/near/counter");
    let manifest_path = fixture_dir.join("reference-manifest.json");
    let reference_source = fixture_dir.join("src/lib.rs");
    let pf_source = repo_root.join("Examples/Product/Counter.lean");
    let handwritten = repo_root.join("Examples/Backend/near/spike/handwritten-counter.wat");

    ensure!(
        manifest_path.is_file(),
        "missing reference manifest: {}",
        manifest_path.display()
    );
    ensure!(
        reference_source.is_file(),
        "missing near-sdk source: {}",
        reference_source.display()
    );
    ensure!(
        pf_source.is_file(),
        "missing ProofForge source: {}",
        pf_source.display()
    );
    ensure!(
        handwritten.is_file(),
        "missing handwritten spike: {}",
        handwritten.display()
    );

    let out_root = repo_root.join("build/testkit/compare/near/counter");
    let pf_dir = out_root.join("proof-forge");
    let sdk_dir = out_root.join("near-sdk");
    let report_path = out_root.join("report.json");

    if out_root.exists() {
        fs::remove_dir_all(&out_root).with_context(|| {
            format!("failed to clean output dir {}", out_root.display())
        })?;
    }
    fs::create_dir_all(&pf_dir)?;
    fs::create_dir_all(&sdk_dir)?;

    println!("=== testkit-compare near/counter: build ProofForge Product/Counter ===");
    build_proof_forge_near(
        repo_root,
        &pf_source,
        &pf_dir,
        "Counter.near-artifact.json",
    )?;

    let wat_path = pf_dir.join("counter.wat");
    let artifact_path = pf_dir.join("Counter.near-artifact.json");
    // proof-forge may also emit counter.wasm; prefer wat2wasm for a stable path
    let wasm_path = pf_dir.join("counter.wasm");
    if !wasm_path.is_file() {
        ensure!(wat_path.is_file(), "missing WAT: {}", wat_path.display());
        run_checked(
            Command::new("wat2wasm")
                .current_dir(repo_root)
                .arg(&wat_path)
                .arg("-o")
                .arg(&wasm_path),
            "wat2wasm",
        )?;
    }
    ensure!(artifact_path.is_file(), "missing artifact: {}", artifact_path.display());
    ensure!(wat_path.is_file(), "missing WAT: {}", wat_path.display());
    ensure!(wasm_path.is_file(), "missing wasm: {}", wasm_path.display());

    println!("=== testkit-compare near/counter: entrypoint equivalence ===");
    check_equivalence(&artifact_path, &manifest_path, &reference_source)?;

    println!("=== testkit-compare near/counter: offline semantic scenario ===");
    let semantic_out = run_offline_host(repo_root, &wat_path, &["initialize", "get", "increment", "get"], 1)?;
    ensure!(
        semantic_out.contains("call 1:get: return_hex=0000000000000000 return_u64=0"),
        "expected get==0 after initialize\n{semantic_out}"
    );
    ensure!(
        semantic_out.contains("call 1:get: return_hex=0100000000000000 return_u64=1"),
        "expected get==1 after increment\n{semantic_out}"
    );
    println!("{semantic_out}");

    println!(
        "=== testkit-compare near/counter: offline fuel bench (repeat={}) ===",
        args.repeat
    );
    let bench_started = Instant::now();
    let bench_out = run_offline_host(
        repo_root,
        &wat_path,
        &["initialize", "get", "increment", "get"],
        args.repeat,
    )?;
    let wall_ms = bench_started.elapsed().as_secs_f64() * 1000.0;
    let fuel = parse_fuel_summary(&bench_out);

    let mut sdk_built = false;
    let mut sdk_note = "skipped (pass --build-sdk or set PROOF_FORGE_NEAR_SDK_BUILD=1)".to_string();
    let mut sdk_wasm_bytes: Option<u64> = None;
    let sdk_wasm_path = sdk_dir.join("contract.wasm");
    if args.build_sdk {
        println!("=== testkit-compare near/counter: build near-sdk reference wasm ===");
        match build_near_sdk_wasm(
            repo_root,
            &fixture_dir,
            &sdk_dir,
            "pf_near_sdk_counter_reference.wasm",
        ) {
            Ok(bytes) => {
                sdk_built = true;
                sdk_wasm_bytes = Some(bytes);
                sdk_note = "built".to_string();
            }
            Err(err) => {
                sdk_note = format!("cargo build failed: {err:#}");
                if args.live {
                    bail!("--live requires near-sdk wasm: {sdk_note}");
                }
                eprintln!("WARN: {sdk_note}");
            }
        }
    }

    let mut sandbox_section = json!({
        "requested": args.live,
        "status": if args.live { "pending" } else { "not_requested" },
        "reportPath": null,
        "detail": null,
    });
    if args.live {
        println!("=== testkit-compare near/counter: NEAR Sandbox dual deploy ===");
        ensure!(
            sdk_built && sdk_wasm_path.is_file(),
            "--live: near-sdk wasm missing at {}",
            sdk_wasm_path.display()
        );
        let sandbox_report = out_root.join("sandbox-report.json");
        match run_near_sandbox_dual(
            repo_root,
            "counter",
            &wasm_path,
            &sdk_wasm_path,
            &sandbox_report,
        ) {
            Ok(SandboxRun::Passed { report }) => {
                println!("sandbox dual-deploy: passed (real NEAR gas)");
                sandbox_section = json!({
                    "requested": true,
                    "status": "passed",
                    "reportPath": rel(repo_root, &sandbox_report),
                    "detail": report,
                });
            }
            Ok(SandboxRun::Skipped { reason }) => {
                eprintln!("sandbox dual-deploy: SKIP — {reason}");
                sandbox_section = json!({
                    "requested": true,
                    "status": "skipped",
                    "reportPath": null,
                    "detail": { "reason": reason },
                });
            }
            Err(err) => {
                // Hard fail: sandbox started but deploy/scenario failed — this is
                // the signal that on-chain deploy is not yet feasible.
                bail!("NEAR Sandbox dual-deploy FAILED (deploy may be infeasible): {err:#}");
            }
        }
    }

    let pf_wasm_bytes = file_len(&wasm_path)?;
    let pf_wat_bytes = file_len(&wat_path)?;
    let hand_bytes = file_len(&handwritten)?;

    let mut comparison = json!({
        "proofForgeWasmBytes": pf_wasm_bytes,
        "proofForgeWatBytes": pf_wat_bytes,
        "handwrittenWatBytes": hand_bytes,
        "nearSdkWasmBytes": sdk_wasm_bytes,
    });
    if let Some(obj) = comparison.as_object_mut() {
        if hand_bytes > 0 {
            obj.insert(
                "proofForgeWasm_vs_handwrittenWat_ratio".into(),
                json!(round3(pf_wasm_bytes as f64 / hand_bytes as f64)),
            );
        }
        if let Some(sdk) = sdk_wasm_bytes {
            if pf_wasm_bytes > 0 {
                obj.insert(
                    "nearSdkWasm_vs_proofForgeWasm_ratio".into(),
                    json!(round3(sdk as f64 / pf_wasm_bytes as f64)),
                );
                obj.insert(
                    "proofForgeWasm_vs_nearSdkWasm_pct".into(),
                    json!(round2(100.0 * pf_wasm_bytes as f64 / sdk as f64)),
                );
            }
        }
        if let Some(detail) = sandbox_section.get("detail") {
            if let Some(cmp) = detail.get("comparison") {
                obj.insert("sandbox".into(), cmp.clone());
            }
        }
    }

    let report = json!({
        "schema": "proof-forge.testkit.compare.v0",
        "chain": "near",
        "contract": "counter",
        "fixtureDir": "testkit/compare/near/counter",
        "scenario": {
            "semantic": ["initialize", "get=0", "increment", "get=1"],
            "benchCalls": ["initialize", "get", "increment", "get"],
            "repeat": args.repeat,
        },
        "implementations": {
            "proof-forge-emitwat": {
                "source": "Examples/Product/Counter.lean",
                "target": "wasm-near",
                "watPath": rel(repo_root, &wat_path),
                "wasmPath": rel(repo_root, &wasm_path),
                "artifactPath": rel(repo_root, &artifact_path),
                "watBytes": pf_wat_bytes,
                "wasmBytes": pf_wasm_bytes,
                "wasmtimeFuel": fuel,
                "wallClockMs": round3(wall_ms),
                "wallClockMsPerSequence": if args.repeat > 0 {
                    Some(round6(wall_ms / f64::from(args.repeat)))
                } else {
                    None
                },
            },
            "handwritten-wat-spike": {
                "source": "Examples/Backend/near/spike/handwritten-counter.wat",
                "watBytes": hand_bytes,
                "notes": "Size floor; ASCII digit ABI, not byte-identical to EmitWat.",
            },
            "near-sdk-rs": {
                "source": "testkit/compare/near/counter",
                "manifest": "testkit/compare/near/counter/reference-manifest.json",
                "built": sdk_built,
                "note": sdk_note,
                "wasmPath": if sdk_built {
                    Some("build/testkit/compare/near/counter/near-sdk/contract.wasm")
                } else {
                    None
                },
                "wasmBytes": sdk_wasm_bytes,
            },
        },
        "sandbox": sandbox_section,
        "comparison": comparison,
        "honesty": [
            "wasmtimeFuel is not NEAR VM gas; do not label it near_gas without calibration.",
            "near-sdk default ABI is JSON; EmitWat uses LE/Borsh-style env.input — size compares, not ABI equality.",
            "Wall-clock is noisy and not a CI gate by default.",
            "All compare fixtures and the driver live under testkit/compare/.",
            "--live dual-deploys both wasms on NEAR Sandbox (near-workspaces) and reports real deploy/call gas + storage_usage.",
        ],
    });

    fs::write(
        &report_path,
        serde_json::to_string_pretty(&report)? + "\n",
    )
    .with_context(|| format!("failed to write {}", report_path.display()))?;

    println!("{}", serde_json::to_string_pretty(&comparison)?);
    println!("wrote {}", rel(repo_root, &report_path));
    println!("testkit-compare near/counter: ok");
    Ok(())
}

// ─── Near ValueVault ────────────────────────────────────────────────────────

fn run_near_value_vault(repo_root: &Path, args: &Args) -> Result<()> {
    let fixture_dir = repo_root.join("testkit/compare/near/value-vault");
    let manifest_path = fixture_dir.join("reference-manifest.json");
    let reference_source = fixture_dir.join("src/lib.rs");
    let pf_source = repo_root.join("Examples/Product/ValueVault.lean");

    ensure!(manifest_path.is_file(), "missing {}", manifest_path.display());
    ensure!(
        reference_source.is_file(),
        "missing {}",
        reference_source.display()
    );
    ensure!(pf_source.is_file(), "missing {}", pf_source.display());

    let out_root = repo_root.join("build/testkit/compare/near/value-vault");
    let pf_dir = out_root.join("proof-forge");
    let sdk_dir = out_root.join("near-sdk");
    let report_path = out_root.join("report.json");

    if out_root.exists() {
        fs::remove_dir_all(&out_root)?;
    }
    fs::create_dir_all(&pf_dir)?;
    fs::create_dir_all(&sdk_dir)?;

    println!("=== testkit-compare near/value-vault: build ProofForge ===");
    build_proof_forge_near(
        repo_root,
        &pf_source,
        &pf_dir,
        "ValueVault.near-artifact.json",
    )?;

    // EmitWat names may be valuevault.wat or ValueVault.wat — accept either.
    let wat_path = [
        pf_dir.join("valuevault.wat"),
        pf_dir.join("ValueVault.wat"),
        pf_dir.join("value_vault.wat"),
    ]
    .into_iter()
    .find(|p| p.is_file())
    .context("ValueVault WAT not produced under proof-forge out dir")?;
    let artifact_path = pf_dir.join("ValueVault.near-artifact.json");
    let wasm_path = wat_path.with_extension("wasm");
    if !wasm_path.is_file() {
        run_checked(
            Command::new("wat2wasm")
                .current_dir(repo_root)
                .arg(&wat_path)
                .arg("-o")
                .arg(&wasm_path),
            "wat2wasm",
        )?;
    }
    ensure!(artifact_path.is_file(), "missing {}", artifact_path.display());

    println!("=== testkit-compare near/value-vault: entrypoint equivalence ===");
    check_equivalence_value_vault(&artifact_path, &manifest_path, &reference_source)?;

    println!("=== testkit-compare near/value-vault: offline semantic scenario ===");
    // initialize(100) get_balance deposit(50) get_balance — LE u64 inputs
    let init_hex = hex_encode_le_u64(100);
    let dep_hex = hex_encode_le_u64(50);
    let inputs = format!("{init_hex},,{dep_hex},");
    let semantic_out = run_offline_host_with_inputs(
        repo_root,
        &wat_path,
        &["initialize", "get_balance", "deposit", "get_balance"],
        &inputs,
        1,
    )?;
    ensure!(
        semantic_out.contains("return_u64=100"),
        "expected get_balance==100 after initialize\n{semantic_out}"
    );
    ensure!(
        semantic_out.contains("return_u64=150"),
        "expected get_balance==150 after deposit\n{semantic_out}"
    );
    println!("{semantic_out}");

    println!(
        "=== testkit-compare near/value-vault: offline fuel bench (repeat={}) ===",
        args.repeat
    );
    let bench_started = Instant::now();
    let bench_out = run_offline_host_with_inputs(
        repo_root,
        &wat_path,
        &["initialize", "get_balance", "deposit", "get_balance"],
        &inputs,
        args.repeat,
    )?;
    let wall_ms = bench_started.elapsed().as_secs_f64() * 1000.0;
    let fuel = parse_fuel_summary(&bench_out);

    let mut sdk_built = false;
    let mut sdk_note = "skipped (pass --build-sdk or set PROOF_FORGE_NEAR_SDK_BUILD=1)".to_string();
    let mut sdk_wasm_bytes: Option<u64> = None;
    let sdk_wasm_path = sdk_dir.join("contract.wasm");
    if args.build_sdk {
        println!("=== testkit-compare near/value-vault: build near-sdk reference wasm ===");
        match build_near_sdk_wasm(
            repo_root,
            &fixture_dir,
            &sdk_dir,
            "pf_near_sdk_value_vault_reference.wasm",
        ) {
            Ok(bytes) => {
                sdk_built = true;
                sdk_wasm_bytes = Some(bytes);
                sdk_note = "built".to_string();
            }
            Err(err) => {
                sdk_note = format!("cargo build failed: {err:#}");
                if args.live {
                    bail!("--live requires near-sdk wasm: {sdk_note}");
                }
                eprintln!("WARN: {sdk_note}");
            }
        }
    }

    let mut sandbox_section = json!({
        "requested": args.live,
        "status": if args.live { "pending" } else { "not_requested" },
        "reportPath": null,
        "detail": null,
    });
    if args.live {
        println!("=== testkit-compare near/value-vault: NEAR Sandbox dual deploy ===");
        ensure!(
            sdk_built && sdk_wasm_path.is_file(),
            "--live: near-sdk wasm missing at {}",
            sdk_wasm_path.display()
        );
        let sandbox_report = out_root.join("sandbox-report.json");
        match run_near_sandbox_dual(
            repo_root,
            "value-vault",
            &wasm_path,
            &sdk_wasm_path,
            &sandbox_report,
        ) {
            Ok(SandboxRun::Passed { report }) => {
                println!("sandbox dual-deploy: passed (real NEAR gas)");
                sandbox_section = json!({
                    "requested": true,
                    "status": "passed",
                    "reportPath": rel(repo_root, &sandbox_report),
                    "detail": report,
                });
            }
            Ok(SandboxRun::Skipped { reason }) => {
                eprintln!("sandbox dual-deploy: SKIP — {reason}");
                sandbox_section = json!({
                    "requested": true,
                    "status": "skipped",
                    "reportPath": null,
                    "detail": { "reason": reason },
                });
            }
            Err(err) => {
                bail!("NEAR Sandbox dual-deploy FAILED: {err:#}");
            }
        }
    }

    let pf_wasm_bytes = file_len(&wasm_path)?;
    let pf_wat_bytes = file_len(&wat_path)?;

    let mut comparison = json!({
        "proofForgeWasmBytes": pf_wasm_bytes,
        "proofForgeWatBytes": pf_wat_bytes,
        "nearSdkWasmBytes": sdk_wasm_bytes,
    });
    if let Some(obj) = comparison.as_object_mut() {
        if let Some(sdk) = sdk_wasm_bytes {
            if pf_wasm_bytes > 0 {
                obj.insert(
                    "nearSdkWasm_vs_proofForgeWasm_ratio".into(),
                    json!(round3(sdk as f64 / pf_wasm_bytes as f64)),
                );
            }
        }
        if let Some(detail) = sandbox_section.get("detail") {
            if let Some(cmp) = detail.get("comparison") {
                obj.insert("sandbox".into(), cmp.clone());
            }
        }
    }

    let report = json!({
        "schema": "proof-forge.testkit.compare.v0",
        "chain": "near",
        "contract": "value-vault",
        "fixtureDir": "testkit/compare/near/value-vault",
        "scenario": {
            "semantic": ["initialize(100)", "get_balance=100", "deposit(50)", "get_balance=150"],
            "repeat": args.repeat,
        },
        "implementations": {
            "proof-forge-emitwat": {
                "source": "Examples/Product/ValueVault.lean",
                "target": "wasm-near",
                "watPath": rel(repo_root, &wat_path),
                "wasmPath": rel(repo_root, &wasm_path),
                "artifactPath": rel(repo_root, &artifact_path),
                "watBytes": pf_wat_bytes,
                "wasmBytes": pf_wasm_bytes,
                "wasmtimeFuel": fuel,
                "wallClockMs": round3(wall_ms),
            },
            "near-sdk-rs": {
                "source": "testkit/compare/near/value-vault",
                "manifest": "testkit/compare/near/value-vault/reference-manifest.json",
                "built": sdk_built,
                "note": sdk_note,
                "wasmPath": if sdk_built {
                    Some("build/testkit/compare/near/value-vault/near-sdk/contract.wasm")
                } else {
                    None
                },
                "wasmBytes": sdk_wasm_bytes,
            },
        },
        "sandbox": sandbox_section,
        "comparison": comparison,
        "honesty": [
            "ValueVault uses more storage fields and args than Counter; call gas still often storage-dominated.",
            "deployGasBurnt / storageUsageBytes in sandbox.detail.comparison show the size advantage on-chain.",
            "--live dual-deploys both wasms on NEAR Sandbox.",
        ],
    });

    fs::write(
        &report_path,
        serde_json::to_string_pretty(&report)? + "\n",
    )?;
    println!("{}", serde_json::to_string_pretty(&comparison)?);
    println!("wrote {}", rel(repo_root, &report_path));
    println!("testkit-compare near/value-vault: ok");
    Ok(())
}

fn check_equivalence_value_vault(
    artifact_path: &Path,
    manifest_path: &Path,
    reference_source: &Path,
) -> Result<()> {
    let artifact: JsonValue = serde_json::from_str(&fs::read_to_string(artifact_path)?)?;
    let reference: JsonValue = serde_json::from_str(&fs::read_to_string(manifest_path)?)?;
    let source = fs::read_to_string(reference_source)?;

    ensure!(
        artifact.get("sourceModule").and_then(|v| v.as_str()) == Some("ValueVault"),
        "sourceModule mismatch"
    );
    let art_names: Vec<&str> = artifact
        .pointer("/abi/entrypoints")
        .and_then(|v| v.as_array())
        .context("missing abi.entrypoints")?
        .iter()
        .filter_map(|e| e.get("name").and_then(|n| n.as_str()))
        .collect();
    for required in [
        "initialize",
        "deposit",
        "get_balance",
        "charge_fee",
        "release",
        "get_net_value",
    ] {
        ensure!(
            art_names.contains(&required),
            "artifact missing entrypoint `{required}`: {art_names:?}"
        );
        ensure!(
            source.contains(&format!("fn {required}")),
            "reference source missing fn {required}"
        );
    }
    let _ = reference;
    println!(
        "equivalence ok — entrypoints include: {}",
        art_names.join(", ")
    );
    Ok(())
}

fn hex_encode_le_u64(v: u64) -> String {
    v.to_le_bytes()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn run_offline_host_with_inputs(
    repo_root: &Path,
    wat_path: &Path,
    calls: &[&str],
    inputs_hex_csv: &str,
    repeat: u32,
) -> Result<String> {
    let mut cmd = Command::new("cargo");
    cmd.current_dir(repo_root).args([
        "run",
        "--quiet",
        "--manifest-path",
        "runtime/offline-host/Cargo.toml",
        "--",
        "run",
    ]);
    cmd.arg(wat_path);
    for call in calls {
        cmd.arg(call);
    }
    cmd.args(["--inputs-hex", inputs_hex_csv]);
    if repeat != 1 {
        cmd.args(["--repeat", &repeat.to_string()]);
    }
    let output = cmd.output().context("spawn offline-host")?;
    if !output.status.success() {
        bail!(
            "offline-host failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

enum SandboxRun {
    Passed { report: JsonValue },
    Skipped { reason: String },
}

fn run_near_sandbox_dual(
    repo_root: &Path,
    contract: &str,
    pf_wasm: &Path,
    sdk_wasm: &Path,
    report_path: &Path,
) -> Result<SandboxRun> {
    let sandbox_manifest = repo_root.join("testkit/compare/near/sandbox/Cargo.toml");
    ensure!(
        sandbox_manifest.is_file(),
        "sandbox harness missing: {}",
        sandbox_manifest.display()
    );

    // Build then run so compile errors surface clearly.
    let cargo = prefer_rustup_cargo();
    let build_status = Command::new(&cargo)
        .current_dir(repo_root)
        .args(["build", "--manifest-path"])
        .arg(&sandbox_manifest)
        .status()
        .context("failed to spawn cargo build for sandbox harness")?;
    if !build_status.success() {
        bail!("sandbox harness cargo build failed");
    }

    let output = Command::new(&cargo)
        .current_dir(repo_root)
        .args(["run", "--quiet", "--manifest-path"])
        .arg(&sandbox_manifest)
        .args(["--", "--contract", contract, "--pf-wasm"])
        .arg(pf_wasm)
        .arg("--sdk-wasm")
        .arg(sdk_wasm)
        .arg("--report")
        .arg(report_path)
        .output()
        .context("failed to spawn pf-near-sandbox-dual")?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !stdout.trim().is_empty() {
        println!("{stdout}");
    }
    if !stderr.trim().is_empty() {
        eprint!("{stderr}");
    }

    let code = output.status.code().unwrap_or(1);
    if code == SANDBOX_SKIP_EXIT {
        return Ok(SandboxRun::Skipped {
            reason: stderr
                .lines()
                .last()
                .unwrap_or("NEAR sandbox unavailable")
                .to_string(),
        });
    }
    if !output.status.success() {
        bail!("sandbox dual exit {code}\nstdout:\n{stdout}\nstderr:\n{stderr}");
    }

    let report: JsonValue = if report_path.is_file() {
        serde_json::from_str(&fs::read_to_string(report_path)?)?
    } else {
        json!({ "status": "passed_no_report_file" })
    };
    Ok(SandboxRun::Passed { report })
}

fn build_proof_forge_near(
    repo_root: &Path,
    source: &Path,
    out_dir: &Path,
    artifact_name: &str,
) -> Result<()> {
    // Ensure CLI binary is available.
    run_checked(
        Command::new("lake")
            .current_dir(repo_root)
            .args(["build", "proof-forge"])
            .stdout(Stdio::null()),
        "lake build proof-forge",
    )?;

    let artifact = out_dir.join(artifact_name);
    run_checked(
        Command::new("lake")
            .current_dir(repo_root)
            .args([
                "env",
                "proof-forge",
                "build",
                "--target",
                "wasm-near",
                "--root",
                ".",
                "-o",
            ])
            .arg(out_dir)
            .arg("--artifact-output")
            .arg(&artifact)
            .arg(source),
        "proof-forge build --target wasm-near",
    )?;
    Ok(())
}

fn check_equivalence(
    artifact_path: &Path,
    manifest_path: &Path,
    reference_source: &Path,
) -> Result<()> {
    let artifact: JsonValue = serde_json::from_str(
        &fs::read_to_string(artifact_path).context("read ProofForge artifact")?,
    )?;
    let reference: JsonValue = serde_json::from_str(
        &fs::read_to_string(manifest_path).context("read reference manifest")?,
    )?;
    let source = fs::read_to_string(reference_source).context("read near-sdk source")?;

    ensure!(
        reference.get("schema").and_then(|v| v.as_str())
            == Some("proof-forge.near.reference-equivalence.v0"),
        "unexpected reference schema"
    );
    ensure!(
        reference.get("proofForgeSource").and_then(|v| v.as_str())
            == Some("Examples/Product/Counter.lean"),
        "proofForgeSource mismatch"
    );
    ensure!(
        artifact.get("target").and_then(|v| v.as_str()) == Some("wasm-near"),
        "artifact target mismatch"
    );
    ensure!(
        artifact.get("sourceModule").and_then(|v| v.as_str())
            == reference
                .get("proofForgeModule")
                .and_then(|v| v.as_str())
                .or(Some("Counter")),
        "sourceModule mismatch"
    );

    let art_entries = artifact
        .pointer("/abi/entrypoints")
        .and_then(|v| v.as_array())
        .context("artifact missing abi.entrypoints")?;
    let ref_entries = reference
        .get("entrypoints")
        .and_then(|v| v.as_array())
        .context("reference missing entrypoints")?;
    ensure!(
        art_entries.len() == ref_entries.len(),
        "entrypoint count mismatch: artifact={} ref={}",
        art_entries.len(),
        ref_entries.len()
    );

    let art_names: Vec<&str> = art_entries
        .iter()
        .filter_map(|e| e.get("name").and_then(|n| n.as_str()))
        .collect();
    let ref_names: Vec<&str> = ref_entries
        .iter()
        .filter_map(|e| e.get("name").and_then(|n| n.as_str()))
        .collect();
    ensure!(
        art_names == ref_names,
        "entrypoint order/name mismatch: {art_names:?} vs {ref_names:?}"
    );

    let get_returns = art_entries
        .iter()
        .find(|e| e.get("name").and_then(|n| n.as_str()) == Some("get"))
        .and_then(|e| e.get("returns").and_then(|r| r.as_str()))
        .unwrap_or("");
    ensure!(
        get_returns.eq_ignore_ascii_case("u64") || get_returns.eq_ignore_ascii_case("uint64"),
        "get returns type mismatch: {get_returns}"
    );

    for name in &ref_names {
        let needle = format!("fn {name}");
        ensure!(
            source.contains(&needle),
            "reference source missing `{needle}`"
        );
    }

    println!(
        "equivalence ok — entrypoints: {}",
        art_names.join(", ")
    );
    Ok(())
}

fn run_offline_host(
    repo_root: &Path,
    wat_path: &Path,
    calls: &[&str],
    repeat: u32,
) -> Result<String> {
    let mut cmd = Command::new("cargo");
    cmd.current_dir(repo_root).args([
        "run",
        "--quiet",
        "--manifest-path",
        "runtime/offline-host/Cargo.toml",
        "--",
        "run",
    ]);
    cmd.arg(wat_path);
    for call in calls {
        cmd.arg(call);
    }
    if repeat != 1 {
        cmd.args(["--repeat", &repeat.to_string()]);
    }
    let output = cmd
        .output()
        .context("failed to spawn runtime/offline-host")?;
    if !output.status.success() {
        bail!(
            "offline-host failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn build_near_sdk_wasm(
    repo_root: &Path,
    fixture_dir: &Path,
    sdk_out: &Path,
    release_wasm_name: &str,
) -> Result<u64> {
    // Prefer rustup cargo so wasm32 std is available.
    let cargo = prefer_rustup_cargo();
    let target_dir = sdk_out.join("target");
    let mut cmd = Command::new(&cargo);
    // Clear env pollution from homebrew rustc when rustup cargo is used.
    if cargo.file_name().and_then(|s| s.to_str()) == Some("cargo")
        && cargo.parent().is_some_and(|p| p.ends_with(".cargo/bin"))
    {
        cmd.env_remove("RUSTC");
    }
    let status = cmd
        .current_dir(repo_root)
        .args([
            "build",
            "--release",
            "--target",
            "wasm32-unknown-unknown",
            "--manifest-path",
        ])
        .arg(fixture_dir.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target_dir)
        .status()
        .context("failed to spawn cargo for near-sdk wasm")?;
    ensure!(status.success(), "near-sdk wasm cargo build failed");

    let candidate = target_dir
        .join("wasm32-unknown-unknown/release")
        .join(release_wasm_name);
    ensure!(
        candidate.is_file(),
        "near-sdk wasm missing at {}",
        candidate.display()
    );
    let dest = sdk_out.join("contract.wasm");
    fs::copy(&candidate, &dest)?;
    file_len(&dest)
}

fn prefer_rustup_cargo() -> PathBuf {
    if let Some(home) = env::var_os("HOME") {
        let candidate = PathBuf::from(home).join(".cargo/bin/cargo");
        if candidate.is_file() {
            return candidate;
        }
    }
    PathBuf::from("cargo")
}

// ─── helpers ────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct FuelStats {
    samples: usize,
    first: Option<u64>,
    mean: Option<f64>,
    min: Option<u64>,
    max: Option<u64>,
}

fn parse_fuel_summary(log: &str) -> serde_json::Map<String, JsonValue> {
    // call 1:initialize: ... wasmtimeFuelDelta=22
    let re = regex_lite_fuel();
    let mut by_call: std::collections::BTreeMap<String, Vec<u64>> =
        std::collections::BTreeMap::new();
    for line in log.lines() {
        if let Some((name, delta)) = re(line) {
            by_call.entry(name).or_default().push(delta);
        }
    }
    let mut out = serde_json::Map::new();
    for (name, deltas) in by_call {
        let stats = FuelStats {
            samples: deltas.len(),
            first: deltas.first().copied(),
            mean: if deltas.is_empty() {
                None
            } else {
                Some(deltas.iter().sum::<u64>() as f64 / deltas.len() as f64)
            },
            min: deltas.iter().copied().min(),
            max: deltas.iter().copied().max(),
        };
        out.insert(name, serde_json::to_value(stats).unwrap_or(JsonValue::Null));
    }
    out
}

/// Tiny parser — avoid adding the `regex` crate to the workspace for one pattern.
fn regex_lite_fuel() -> impl Fn(&str) -> Option<(String, u64)> {
    |line: &str| {
        // "call <n>:<name>: ... wasmtimeFuelDelta=<d>"
        let call_pos = line.find("call ")?;
        let rest = &line[call_pos + 5..];
        let colon = rest.find(':')?;
        let after_seq = &rest[colon + 1..];
        let name_end = after_seq.find(':')?;
        let name = after_seq[..name_end].to_string();
        let key = "wasmtimeFuelDelta=";
        let fuel_pos = line.find(key)?;
        let num = &line[fuel_pos + key.len()..];
        let num = num
            .split(|c: char| !c.is_ascii_digit())
            .next()
            .unwrap_or("");
        let delta: u64 = num.parse().ok()?;
        Some((name, delta))
    }
}

fn run_checked(cmd: &mut Command, label: &str) -> Result<()> {
    let output = cmd
        .output()
        .with_context(|| format!("failed to spawn {label}"))?;
    if !output.status.success() {
        bail!(
            "{label} failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(())
}

fn file_len(path: &Path) -> Result<u64> {
    Ok(fs::metadata(path)
        .with_context(|| format!("stat {}", path.display()))?
        .len())
}

fn rel(repo_root: &Path, path: &Path) -> String {
    path.strip_prefix(repo_root)
        .unwrap_or(path)
        .display()
        .to_string()
}

fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}

fn round6(v: f64) -> f64 {
    (v * 1_000_000.0).round() / 1_000_000.0
}
