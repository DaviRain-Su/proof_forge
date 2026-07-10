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
        ["near", "fungible-token"] | ["near", "ft"] | ["near", "fungible_token"] => {
            run_near_fungible_token(&repo_root, &args)
        }
        ["near", "ownable"] => run_near_ownable(&repo_root, &args),
        ["near", "staking-vault"] | ["near", "stakingvault"] | ["near", "staking_vault"] => {
            run_near_staking_vault(&repo_root, &args)
        }
        ["near", "role-gated-token"] | ["near", "rolegatedtoken"] | ["near", "rgt"] => {
            run_near_role_gated_token(&repo_root, &args)
        }
        ["near", "fee-token"] | ["near", "feetoken"] => run_near_fee_token(&repo_root, &args),
        ["near", "remote-call"] | ["near", "remotecall"] | ["near", "crosscall"] => {
            run_near_remote_call(&repo_root, &args)
        }
        ["near", "status-message"] | ["near", "statusmessage"] | ["near", "status"] => {
            run_near_status_message(&repo_root, &args)
        }
        ["near", "guestbook"] | ["near", "guest-book"] => {
            run_near_guestbook(&repo_root, &args)
        }
        ["near", "storage-deposit"] | ["near", "storagedeposit"] | ["near", "nep145"] => {
            run_near_storage_deposit(&repo_root, &args)
        }
        ["near", "pausable"] | ["near", "pause"] => run_near_pausable(&repo_root, &args),
        ["near", "reentrancy-guard"]
        | ["near", "reentrancyguard"]
        | ["near", "reentrancy"]
        | ["near", "rg"] => run_near_reentrancy_guard(&repo_root, &args),
        ["near", "ownable-pausable"]
        | ["near", "ownablepausable"]
        | ["near", "ownable_pausable"] => run_near_ownable_pausable(&repo_root, &args),
        ["near", "array-example"] | ["near", "arrayexample"] | ["near", "array"] => {
            run_near_array_example(&repo_root, &args)
        }
        ["near", "ownable-hash"] | ["near", "ownablehash"] | ["near", "ownable_hash"] => {
            run_near_ownable_hash(&repo_root, &args)
        }
        ["near", "host-env-probe"]
        | ["near", "hostenvprobe"]
        | ["near", "hostenv"] => run_near_host_env_probe(&repo_root, &args),
        ["near", "auth-remote-call"]
        | ["near", "authremotecall"]
        | ["near", "auth_remote"] => run_near_auth_remote_call(&repo_root, &args),
        ["near", "access-control"] | ["near", "accesscontrol"] | ["near", "acl"] => {
            run_near_access_control(&repo_root, &args)
        }
        ["near", "external-token-transfer"]
        | ["near", "externaltokentransfer"]
        | ["near", "ext-ft"] => run_near_external_token_transfer(&repo_root, &args),
        ["near", "external-vault"] | ["near", "externalvault"] | ["near", "ext-vault"] => {
            run_near_external_vault(&repo_root, &args)
        }
        ["near", "pro-rata-vault"]
        | ["near", "proratavault"]
        | ["near", "share-vault"] => run_near_pro_rata_vault(&repo_root, &args),
        ["near", "soulbound-token"]
        | ["near", "soulboundtoken"]
        | ["near", "sbt"]
        | ["near", "soulbound"] => run_near_soulbound_token(&repo_root, &args),
        ["near", "ft-peer-client"]
        | ["near", "ftpeerclient"]
        | ["near", "ft_peer"] => run_near_ft_peer_client(&repo_root, &args),
        ["near", "vesting-vault"]
        | ["near", "vestingvault"]
        | ["near", "vesting"] => run_near_vesting_vault(&repo_root, &args),
        ["near", "escrow-vault"]
        | ["near", "escrowvault"]
        | ["near", "escrow"] => run_near_escrow_vault(&repo_root, &args),
        ["near", "timelock-vault"]
        | ["near", "timelockvault"]
        | ["near", "timelock"] => run_near_timelock_vault(&repo_root, &args),
        ["near", "height-lock-vault"]
        | ["near", "heightlockvault"]
        | ["near", "height-lock"]
        | ["near", "heightlock"] => run_near_height_lock_vault(&repo_root, &args),
        ["near", other] => {
            bail!(
                "unknown near compare example `{other}` \
                 (known: counter, value-vault, fungible-token, ownable, staking-vault, \
                  role-gated-token, fee-token, remote-call, status-message, guestbook, \
                  storage-deposit, pausable, reentrancy-guard, ownable-pausable, \
                  array-example, ownable-hash, host-env-probe, auth-remote-call, \
                  access-control, external-token-transfer, external-vault, \
                  pro-rata-vault, soulbound-token, ft-peer-client, vesting-vault, \
                  escrow-vault, timelock-vault, height-lock-vault)"
            )
        }
        [chain, ..] => bail!("unknown compare chain `{chain}` (known: near)"),
        [] => {
            print_usage();
            bail!("missing compare target, e.g. `near counter` or `near fungible-token`");
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
        "usage: proof-forge-testkit-compare near <contract> \
         [--build-sdk] [--live] [--repeat N]\n\
         contracts: counter|value-vault|fungible-token|ownable|staking-vault|\n\
                    role-gated-token|fee-token|remote-call|status-message|guestbook|\n\
                    storage-deposit|pausable|reentrancy-guard|ownable-pausable|\n\
                    array-example|ownable-hash|host-env-probe|auth-remote-call|\n\
                    access-control|external-token-transfer|external-vault|\n\
                    pro-rata-vault|soulbound-token|ft-peer-client\n\n\
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

fn hex_encode_bytes(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// sha256(account_id_utf8) — matches EmitWat `callerHash` / hash account keys.
fn near_account_hash32(account_id: &str) -> [u8; 32] {
    sha256_bytes(account_id.as_bytes())
}

fn sha256_bytes(data: &[u8]) -> [u8; 32] {
    // Pure-Rust SHA-256 (minimal, no extra crate) — enough for testkit keys.
    // Algorithm matches FIPS 180-4; used for stable NEAR account → hash keys.
    struct Sha256 {
        h: [u32; 8],
        len: u64,
        buf: [u8; 64],
        buf_len: usize,
    }
    impl Sha256 {
        fn new() -> Self {
            Self {
                h: [
                    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
                    0x1f83d9ab, 0x5be0cd19,
                ],
                len: 0,
                buf: [0; 64],
                buf_len: 0,
            }
        }
        fn update(&mut self, data: &[u8]) {
            for &b in data {
                self.buf[self.buf_len] = b;
                self.buf_len += 1;
                self.len += 1;
                if self.buf_len == 64 {
                    self.compress();
                    self.buf_len = 0;
                }
            }
        }
        fn compress(&mut self) {
            const K: [u32; 64] = [
                0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
                0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
                0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
                0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
                0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
                0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
                0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
                0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
                0xc67178f2,
            ];
            let mut w = [0u32; 64];
            for i in 0..16 {
                w[i] = u32::from_be_bytes([
                    self.buf[i * 4],
                    self.buf[i * 4 + 1],
                    self.buf[i * 4 + 2],
                    self.buf[i * 4 + 3],
                ]);
            }
            for i in 16..64 {
                let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
                let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[i - 7])
                    .wrapping_add(s1);
            }
            let mut a = self.h[0];
            let mut b = self.h[1];
            let mut c = self.h[2];
            let mut d = self.h[3];
            let mut e = self.h[4];
            let mut f = self.h[5];
            let mut g = self.h[6];
            let mut h = self.h[7];
            for i in 0..64 {
                let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
                let ch = (e & f) ^ ((!e) & g);
                let t1 = h
                    .wrapping_add(s1)
                    .wrapping_add(ch)
                    .wrapping_add(K[i])
                    .wrapping_add(w[i]);
                let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
                let maj = (a & b) ^ (a & c) ^ (b & c);
                let t2 = s0.wrapping_add(maj);
                h = g;
                g = f;
                f = e;
                e = d.wrapping_add(t1);
                d = c;
                c = b;
                b = a;
                a = t1.wrapping_add(t2);
            }
            self.h[0] = self.h[0].wrapping_add(a);
            self.h[1] = self.h[1].wrapping_add(b);
            self.h[2] = self.h[2].wrapping_add(c);
            self.h[3] = self.h[3].wrapping_add(d);
            self.h[4] = self.h[4].wrapping_add(e);
            self.h[5] = self.h[5].wrapping_add(f);
            self.h[6] = self.h[6].wrapping_add(g);
            self.h[7] = self.h[7].wrapping_add(h);
        }
        fn finalize(mut self) -> [u8; 32] {
            let bit_len = self.len * 8;
            self.update(&[0x80]);
            while self.buf_len != 56 {
                self.update(&[0x00]);
            }
            self.update(&bit_len.to_be_bytes());
            let mut out = [0u8; 32];
            for (i, &v) in self.h.iter().enumerate() {
                out[i * 4..(i + 1) * 4].copy_from_slice(&v.to_be_bytes());
            }
            out
        }
    }
    let mut s = Sha256::new();
    s.update(data);
    s.finalize()
}

#[derive(Default)]
struct OfflineHostOpts<'a> {
    inputs_hex_csv: &'a str,
    predecessor: Option<&'a str>,
    attached_deposit: Option<u64>,
    /// When set, passed as `--block-timestamp` to offline-host (HostEnv time).
    block_timestamp: Option<u64>,
    /// When set, passed as `--block-index` to offline-host (HostEnv height).
    block_index: Option<u64>,
    repeat: u32,
}

fn run_offline_host_with_inputs(
    repo_root: &Path,
    wat_path: &Path,
    calls: &[&str],
    inputs_hex_csv: &str,
    repeat: u32,
) -> Result<String> {
    run_offline_host_opts(
        repo_root,
        wat_path,
        calls,
        OfflineHostOpts {
            inputs_hex_csv,
            predecessor: None,
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat,
        },
    )
}

fn run_offline_host_opts(
    repo_root: &Path,
    wat_path: &Path,
    calls: &[&str],
    opts: OfflineHostOpts<'_>,
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
    if !opts.inputs_hex_csv.is_empty() {
        cmd.args(["--inputs-hex", opts.inputs_hex_csv]);
    }
    if let Some(pred) = opts.predecessor {
        cmd.args(["--predecessor-account-id", pred]);
        cmd.args(["--signer-account-id", pred]);
    }
    if let Some(dep) = opts.attached_deposit {
        cmd.args(["--attached-deposit", &dep.to_string()]);
    }
    if let Some(ts) = opts.block_timestamp {
        cmd.args(["--block-timestamp", &ts.to_string()]);
    }
    if let Some(idx) = opts.block_index {
        cmd.args(["--block-index", &idx.to_string()]);
    }
    if opts.repeat != 1 {
        cmd.args(["--repeat", &opts.repeat.to_string()]);
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

/// Shared offline/live compare skeleton used by FT / Ownable / StakingVault.
fn run_near_compare_generic(
    repo_root: &Path,
    args: &Args,
    contract: &str,
    fixture_rel: &str,
    pf_source_rel: &str,
    artifact_name: &str,
    sdk_release_wasm: &str,
    wat_candidates: &[&str],
    required_entrypoints: &[&str],
    semantic: impl FnOnce(&Path, &Path) -> Result<(String, String)>,
    fuel_calls: &[&str],
    fuel_inputs: &str,
    fuel_opts: OfflineHostOpts<'_>,
    honesty: &[&str],
) -> Result<()> {
    let fixture_dir = repo_root.join(fixture_rel);
    let manifest_path = fixture_dir.join("reference-manifest.json");
    let reference_source = fixture_dir.join("src/lib.rs");
    let pf_source = repo_root.join(pf_source_rel);
    ensure!(manifest_path.is_file(), "missing {}", manifest_path.display());
    ensure!(
        reference_source.is_file(),
        "missing {}",
        reference_source.display()
    );
    ensure!(pf_source.is_file(), "missing {}", pf_source.display());

    let out_root = repo_root.join(format!("build/testkit/compare/near/{contract}"));
    let pf_dir = out_root.join("proof-forge");
    let sdk_dir = out_root.join("near-sdk");
    let report_path = out_root.join("report.json");
    if out_root.exists() {
        fs::remove_dir_all(&out_root)?;
    }
    fs::create_dir_all(&pf_dir)?;
    fs::create_dir_all(&sdk_dir)?;

    println!("=== testkit-compare near/{contract}: build ProofForge ===");
    build_proof_forge_near(repo_root, &pf_source, &pf_dir, artifact_name)?;

    let wat_path = wat_candidates
        .iter()
        .map(|n| pf_dir.join(n))
        .find(|p| p.is_file())
        .with_context(|| format!("{contract} WAT not produced under {}", pf_dir.display()))?;
    let artifact_path = pf_dir.join(artifact_name);
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

    println!("=== testkit-compare near/{contract}: entrypoint equivalence ===");
    check_equivalence_subset(
        &artifact_path,
        &reference_source,
        required_entrypoints,
    )?;

    println!("=== testkit-compare near/{contract}: offline semantic scenario ===");
    let (semantic_label, semantic_out) = semantic(repo_root, &wat_path)?;
    println!("{semantic_out}");

    println!(
        "=== testkit-compare near/{contract}: offline fuel bench (repeat={}) ===",
        args.repeat
    );
    let bench_started = Instant::now();
    let mut fuel_opts = fuel_opts;
    fuel_opts.repeat = args.repeat;
    if fuel_opts.inputs_hex_csv.is_empty() {
        fuel_opts.inputs_hex_csv = fuel_inputs;
    }
    let bench_out = run_offline_host_opts(repo_root, &wat_path, fuel_calls, fuel_opts)?;
    let wall_ms = bench_started.elapsed().as_secs_f64() * 1000.0;
    let fuel = parse_fuel_summary(&bench_out);

    let mut sdk_built = false;
    let mut sdk_note = "skipped (pass --build-sdk or set PROOF_FORGE_NEAR_SDK_BUILD=1)".to_string();
    let mut sdk_wasm_bytes: Option<u64> = None;
    let sdk_wasm_path = sdk_dir.join("contract.wasm");
    if args.build_sdk {
        println!("=== testkit-compare near/{contract}: build near-sdk reference wasm ===");
        match build_near_sdk_wasm(repo_root, &fixture_dir, &sdk_dir, sdk_release_wasm) {
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
        println!("=== testkit-compare near/{contract}: NEAR Sandbox dual deploy ===");
        ensure!(
            sdk_built && sdk_wasm_path.is_file(),
            "--live: near-sdk wasm missing at {}",
            sdk_wasm_path.display()
        );
        let sandbox_report = out_root.join("sandbox-report.json");
        match run_near_sandbox_dual(
            repo_root,
            contract,
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
            Err(err) => bail!("NEAR Sandbox dual-deploy FAILED: {err:#}"),
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
        "contract": contract,
        "fixtureDir": fixture_rel,
        "scenario": {
            "semantic": semantic_label,
            "repeat": args.repeat,
        },
        "implementations": {
            "proof-forge-emitwat": {
                "source": pf_source_rel,
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
                "source": fixture_rel,
                "manifest": format!("{fixture_rel}/reference-manifest.json"),
                "built": sdk_built,
                "note": sdk_note,
                "wasmPath": if sdk_built {
                    Some(format!("build/testkit/compare/near/{contract}/near-sdk/contract.wasm"))
                } else {
                    None
                },
                "wasmBytes": sdk_wasm_bytes,
            },
        },
        "sandbox": sandbox_section,
        "comparison": comparison,
        "honesty": honesty,
    });
    fs::write(
        &report_path,
        serde_json::to_string_pretty(&report)? + "\n",
    )?;
    println!("{}", serde_json::to_string_pretty(&comparison)?);
    println!("wrote {}", rel(repo_root, &report_path));
    println!("testkit-compare near/{contract}: ok");
    Ok(())
}

fn check_equivalence_subset(
    artifact_path: &Path,
    reference_source: &Path,
    required: &[&str],
) -> Result<()> {
    let artifact: JsonValue = serde_json::from_str(&fs::read_to_string(artifact_path)?)?;
    let source = fs::read_to_string(reference_source)?;
    let art_names: Vec<&str> = artifact
        .pointer("/abi/entrypoints")
        .and_then(|v| v.as_array())
        .context("missing abi.entrypoints")?
        .iter()
        .filter_map(|e| e.get("name").and_then(|n| n.as_str()))
        .collect();
    for req in required {
        ensure!(
            art_names.iter().any(|n| n == req),
            "artifact missing entrypoint `{req}`: {art_names:?}"
        );
        // sdk may use snake_case; accept either.
        let snake = req
            .chars()
            .enumerate()
            .flat_map(|(i, c)| {
                if c.is_uppercase() {
                    let mut v = Vec::new();
                    if i > 0 {
                        v.push('_');
                    }
                    v.push(c.to_ascii_lowercase());
                    v
                } else {
                    vec![c]
                }
            })
            .collect::<String>();
        // Allow sdk snake_case, get_ prefix views, or camelCase PF names.
        let alt_get = format!("get_{snake}");
        ensure!(
            source.contains(&format!("fn {req}"))
                || source.contains(&format!("fn {snake}"))
                || source.contains(&format!("fn {alt_get}"))
                || source.contains(&format!("pub fn {req}"))
                || source.contains(&format!("pub fn {snake}"))
                || source.contains(&format!("pub fn {alt_get}")),
            "reference source missing fn {req} (or {snake} / {alt_get})"
        );
    }
    println!(
        "equivalence ok — required entrypoints present: {}",
        required.join(", ")
    );
    Ok(())
}

fn run_near_fungible_token(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = near_account_hash32("alice.testnet");
    let bob = near_account_hash32("bob.testnet");
    let mint = {
        let mut v = alice.to_vec();
        v.extend_from_slice(&100u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let bal_a = hex_encode_bytes(&alice);
    let bal_b = hex_encode_bytes(&bob);
    let xfer = {
        let mut v = bob.to_vec();
        v.extend_from_slice(&30u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    // init, ft_mint, ft_total_supply, ft_balance_of, ft_transfer, ft_balance_of, ft_balance_of
    let inputs = format!(",{mint},,{bal_a},{xfer},{bal_a},{bal_b}");

    run_near_compare_generic(
        repo_root,
        args,
        "fungible-token",
        "testkit/compare/near/fungible-token",
        "Examples/Backend/WasmNear/FungibleToken.lean",
        "NearFungibleToken.near-artifact.json",
        "pf_near_sdk_fungible_token_reference.wasm",
        &["nearfungibletoken.wat", "NearFungibleToken.wat", "fungibletoken.wat"],
        &[
            "init",
            "ft_mint",
            "ft_transfer",
            "ft_balance_of",
            "ft_total_supply",
        ],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "ft_mint",
                    "ft_total_supply",
                    "ft_balance_of",
                    "ft_transfer",
                    "ft_balance_of",
                    "ft_balance_of",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=100"),
                "expected supply/balance 100\n{out}"
            );
            ensure!(
                out.contains("return_u64=70"),
                "expected alice balance 70 after transfer\n{out}"
            );
            ensure!(
                out.contains("return_u64=30"),
                "expected bob balance 30 after transfer\n{out}"
            );
            Ok((
                "init→mint(100 alice)→supply=100→bal_alice=100→xfer(30 bob)→bal 70/30".into(),
                out,
            ))
        },
        &[
            "init",
            "ft_mint",
            "ft_total_supply",
            "ft_balance_of",
            "ft_transfer",
            "ft_balance_of",
            "ft_balance_of",
        ],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "PF balance keys = sha256(account_id); sdk uses AccountId LookupMap.",
            "Product/FungibleToken.lean is TokenSpec intent; body is Stdlib.NearFungibleToken.",
            "Minimal NEP-141 face only (no transfer_call / NEP-145 in scenario).",
        ],
    )
}

fn run_near_ownable(repo_root: &Path, args: &Args) -> Result<()> {
    let bob_u64 = u64::from_le_bytes(near_account_hash32("bob.testnet")[..8].try_into().unwrap());
    let alice_u64 =
        u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let bob_hex = hex_encode_le_u64(bob_u64);
    let inputs = format!(",,{bob_hex},");

    run_near_compare_generic(
        repo_root,
        args,
        "ownable",
        "testkit/compare/near/ownable",
        "Examples/Product/Ownable.lean",
        "Ownable.near-artifact.json",
        "pf_near_sdk_ownable_reference.wasm",
        &["ownable.wat", "Ownable.wat"],
        &["init", "owner", "transferOwnership", "renounceOwnership"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["init", "owner", "transferOwnership", "owner"],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains(&format!("return_u64={alice_u64}")),
                "expected owner=alice u64 after init\n{out}"
            );
            ensure!(
                out.contains(&format!("return_u64={bob_u64}")),
                "expected owner=bob u64 after transfer\n{out}"
            );
            Ok((
                format!("init(alice)→owner={alice_u64}→transferOwnership(bob)→owner={bob_u64}"),
                out,
            ))
        },
        // Fuel bench cannot re-run `init` (requireZero already-initialized).
        // Measure view path only; full scenario is covered by the semantic step.
        &["owner"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "PF owner is u64 = first 8 LE bytes of sha256(predecessor_account_id).",
            "sdk owner is AccountId; live scenario checks role transitions, not raw encodings.",
        ],
    )
}

fn run_near_staking_vault(repo_root: &Path, args: &Args) -> Result<()> {
    let whex = hex_encode_le_u64(20);
    let inputs = format!(",,,{whex},");

    run_near_compare_generic(
        repo_root,
        args,
        "staking-vault",
        "testkit/compare/near/staking-vault",
        "Examples/Product/StakingVault.lean",
        "StakingVault.near-artifact.json",
        "pf_near_sdk_staking_vault_reference.wasm",
        &["stakingvault.wat", "StakingVault.wat"],
        &["init", "deposit", "withdraw", "totalDeposits"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["init", "deposit", "totalDeposits", "withdraw", "totalDeposits"],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: Some(50),
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=50"),
                "expected totalDeposits=50 after deposit\n{out}"
            );
            ensure!(
                out.contains("return_u64=30"),
                "expected totalDeposits=30 after withdraw 20\n{out}"
            );
            Ok((
                "init→deposit(50)→total=50→withdraw(20)→total=30".into(),
                out,
            ))
        },
        &["init", "deposit", "totalDeposits", "withdraw", "totalDeposits"],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: Some(50),
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "PF depositor key = u64 caller projection; sdk uses AccountId map.",
            "Attached deposit used for deposit; withdraw burns shares only in scenario.",
        ],
    )
}

fn run_near_role_gated_token(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let bob = u64::from_le_bytes(near_account_hash32("bob.testnet")[..8].try_into().unwrap());
    let grant = {
        let mut v = 1u64.to_le_bytes().to_vec(); // minter role
        v.extend_from_slice(&alice.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let mint = {
        let mut v = alice.to_le_bytes().to_vec();
        v.extend_from_slice(&100u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let bal_a = hex_encode_le_u64(alice);
    let bal_b = hex_encode_le_u64(bob);
    let xfer = {
        let mut v = bob.to_le_bytes().to_vec();
        v.extend_from_slice(&30u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    // init, grantRole, mint, balanceOf, transfer, balanceOf, balanceOf, totalSupply
    let inputs = format!(",{grant},{mint},{bal_a},{xfer},{bal_a},{bal_b},");

    run_near_compare_generic(
        repo_root,
        args,
        "role-gated-token",
        "testkit/compare/near/role-gated-token",
        "Examples/Product/RoleGatedToken.lean",
        "RoleGatedToken.near-artifact.json",
        "pf_near_sdk_role_gated_token_reference.wasm",
        &["rolegatedtoken.wat", "RoleGatedToken.wat"],
        &["init", "grantRole", "mint", "transfer", "balanceOf", "totalSupply"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "grantRole",
                    "mint",
                    "balanceOf",
                    "transfer",
                    "balanceOf",
                    "balanceOf",
                    "totalSupply",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=100"),
                "expected balance/supply 100\n{out}"
            );
            ensure!(
                out.contains("return_u64=70"),
                "expected alice bal 70\n{out}"
            );
            ensure!(
                out.contains("return_u64=30"),
                "expected bob bal 30\n{out}"
            );
            Ok((
                "init→grant minter→mint 100→xfer 30→bal 70/30 supply 100".into(),
                out,
            ))
        },
        &[
            "init",
            "grantRole",
            "mint",
            "balanceOf",
            "transfer",
            "balanceOf",
            "balanceOf",
            "totalSupply",
        ],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "PF role path is nested mapKey; sdk uses flat role:account string keys.",
            "Account identity: PF u64 sha256-prefix; sdk AccountId.",
        ],
    )
}

fn run_near_fee_token(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let bob = u64::from_le_bytes(near_account_hash32("bob.testnet")[..8].try_into().unwrap());
    let init = hex_encode_le_u64(1000); // 10% fee
    let mint = {
        let mut v = alice.to_le_bytes().to_vec();
        v.extend_from_slice(&100u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let xfer = {
        let mut v = bob.to_le_bytes().to_vec();
        v.extend_from_slice(&50u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let bal_a = hex_encode_le_u64(alice);
    let bal_b = hex_encode_le_u64(bob);
    // init, mint, transfer, balanceOf, balanceOf, totalSupply
    let inputs = format!("{init},{mint},{xfer},{bal_a},{bal_b},");

    run_near_compare_generic(
        repo_root,
        args,
        "fee-token",
        "testkit/compare/near/fee-token",
        "Examples/Backend/WasmNear/FeeToken.lean",
        "FeeToken.near-artifact.json",
        "pf_near_sdk_fee_token_reference.wasm",
        &["feetoken.wat", "FeeToken.wat"],
        &["init", "mint", "transfer", "balanceOf", "totalSupply"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "mint",
                    "transfer",
                    "balanceOf",
                    "balanceOf",
                    "totalSupply",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            // after mint 100, transfer 50 with 10% fee: alice 50, bob 45, supply 95
            ensure!(
                out.contains("return_u64=50"),
                "expected alice bal 50\n{out}"
            );
            ensure!(
                out.contains("return_u64=45"),
                "expected bob bal 45 (net after fee)\n{out}"
            );
            ensure!(
                out.contains("return_u64=95"),
                "expected supply 95 after fee burn\n{out}"
            );
            Ok((
                "init(fee=10%)→mint 100→transfer 50→bal 50/45 supply 95".into(),
                out,
            ))
        },
        &[
            "init",
            "mint",
            "transfer",
            "balanceOf",
            "balanceOf",
            "totalSupply",
        ],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Product FeeToken.lean is TokenSpec intent; body is Backend WasmNear FeeToken.",
            "Fee burns from totalSupply on both sides (not treasury credit).",
        ],
    )
}

fn run_near_status_message(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let inputs = format!(
        ",{},{},{},{}",
        hex_encode_le_u64(7),
        hex_encode_le_u64(alice),
        hex_encode_le_u64(99),
        hex_encode_le_u64(alice)
    );
    run_near_compare_generic(
        repo_root,
        args,
        "status-message",
        "testkit/compare/near/status-message",
        "Examples/Product/StatusMessage.lean",
        "StatusMessage.near-artifact.json",
        "pf_near_sdk_status_message_reference.wasm",
        &["statusmessage.wat", "StatusMessage.wat"],
        &["init", "set_status", "get_status"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["init", "set_status", "get_status", "set_status", "get_status"],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=7"), "expected status 7\n{out}");
            ensure!(out.contains("return_u64=99"), "expected status 99\n{out}");
            Ok(("init→set 7→get 7→set 99→get 99".into(), out))
        },
        &["init", "set_status", "get_status", "set_status", "get_status"],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "U64 status codes (not UTF-8 strings) until EmitWat string KV lands.",
            "Tutorial parity is control-flow + per-account map storage.",
        ],
    )
}

fn run_near_guestbook(repo_root: &Path, args: &Args) -> Result<()> {
    let inputs = format!(
        ",{},{},,{},{}",
        hex_encode_le_u64(11),
        hex_encode_le_u64(22),
        hex_encode_le_u64(0),
        hex_encode_le_u64(1)
    );
    run_near_compare_generic(
        repo_root,
        args,
        "guestbook",
        "testkit/compare/near/guestbook",
        "Examples/Product/GuestBook.lean",
        "GuestBook.near-artifact.json",
        "pf_near_sdk_guestbook_reference.wasm",
        &["guestbook.wat", "GuestBook.wat"],
        &["init", "add_message", "get_message", "total_messages"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "add_message",
                    "add_message",
                    "total_messages",
                    "get_message",
                    "get_message",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=2"), "expected total 2\n{out}");
            ensure!(out.contains("return_u64=11"), "expected msg0=11\n{out}");
            ensure!(out.contains("return_u64=22"), "expected msg1=22\n{out}");
            Ok(("init→add 11→add 22→total 2→get 11/22".into(), out))
        },
        &[
            "init",
            "add_message",
            "add_message",
            "total_messages",
            "get_message",
            "get_message",
        ],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "U64 message codes stand in for free-form strings.",
            "Append + index + count matches classic guestbook control flow.",
        ],
    )
}

fn run_near_storage_deposit(repo_root: &Path, args: &Args) -> Result<()> {
    // Fixed 32-byte account hash (matches scripts/near/target-first-smoke.sh).
    let account_hash =
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
    let inputs = format!(",,{account_hash},{account_hash},{account_hash}");
    run_near_compare_generic(
        repo_root,
        args,
        "storage-deposit",
        "testkit/compare/near/storage-deposit",
        "Examples/Product/StorageDeposit.lean",
        "StorageDeposit.near-artifact.json",
        "pf_near_sdk_storage_deposit_reference.wasm",
        &["storagedeposit.wat", "StorageDeposit.wat"],
        &[
            "init",
            "storage_balance_bounds",
            "storage_balance_of",
            "storage_deposit",
        ],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "storage_balance_bounds",
                    "storage_balance_of",
                    "storage_deposit",
                    "storage_balance_of",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: Some(7),
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=1"),
                "expected bounds=1\n{out}"
            );
            ensure!(
                out.contains("return_u64=0"),
                "expected initial balance 0\n{out}"
            );
            ensure!(
                out.contains("return_u64=7"),
                "expected balance 7 after deposit\n{out}"
            );
            Ok((
                "init→bounds 1→bal 0→deposit(7)→bal 7".into(),
                out,
            ))
        },
        &[
            "init",
            "storage_balance_bounds",
            "storage_balance_of",
            "storage_deposit",
            "storage_balance_of",
        ],
        &inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: Some(7),
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "NEP-145-lite: U64 cumulative deposits, not full StorageBalance JSON.",
            "Attached deposit via nativeValue / env::attached_deposit.",
        ],
    )
}

fn run_near_pausable(repo_root: &Path, args: &Args) -> Result<()> {
    run_near_compare_generic(
        repo_root,
        args,
        "pausable",
        "testkit/compare/near/pausable",
        "Examples/Product/Pausable.lean",
        "Pausable.near-artifact.json",
        "pf_near_sdk_pausable_reference.wasm",
        &["pausable.wat", "Pausable.wat"],
        &["paused", "pause", "unpause"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["paused", "pause", "paused", "unpause", "paused"],
                OfflineHostOpts {
                    inputs_hex_csv: "",
                    predecessor: None,
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=0"), "expected unpaused 0\n{out}");
            ensure!(out.contains("return_u64=1"), "expected paused 1\n{out}");
            Ok(("paused 0→pause→1→unpause→0".into(), out))
        },
        // Guarded transitions are not idempotent — fuel-bench the view only.
        &["paused"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: None,
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Unauthenticated emergency-stop mixin; owner-gated path is OwnablePausable.",
        ],
    )
}

fn run_near_reentrancy_guard(repo_root: &Path, args: &Args) -> Result<()> {
    run_near_compare_generic(
        repo_root,
        args,
        "reentrancy-guard",
        "testkit/compare/near/reentrancy-guard",
        "Examples/Product/ReentrancyGuard.lean",
        "ReentrancyGuard.near-artifact.json",
        "pf_near_sdk_reentrancy_guard_reference.wasm",
        &["reentrancyguard.wat", "ReentrancyGuard.wat"],
        &["acquire", "release", "locked"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["locked", "acquire", "locked", "release", "locked"],
                OfflineHostOpts {
                    inputs_hex_csv: "",
                    predecessor: None,
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=0"), "expected unlocked 0\n{out}");
            ensure!(out.contains("return_u64=1"), "expected locked 1\n{out}");
            Ok(("locked 0→acquire→1→release→0".into(), out))
        },
        &["locked"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: None,
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Lock bit + require-unlocked only; not EVM call-stack reentrancy theory.",
        ],
    )
}

fn run_near_ownable_pausable(repo_root: &Path, args: &Args) -> Result<()> {
    run_near_compare_generic(
        repo_root,
        args,
        "ownable-pausable",
        "testkit/compare/near/ownable-pausable",
        "Examples/Product/OwnablePausable.lean",
        "OwnablePausable.near-artifact.json",
        "pf_near_sdk_ownable_pausable_reference.wasm",
        &["ownablepausable.wat", "OwnablePausable.wat"],
        &["init", "owner", "paused", "pause", "unpause", "renounceOwnership"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["init", "paused", "pause", "paused", "unpause", "paused"],
                OfflineHostOpts {
                    inputs_hex_csv: "",
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=0"), "expected unpaused 0\n{out}");
            ensure!(out.contains("return_u64=1"), "expected paused 1\n{out}");
            Ok(("init→pause→unpause (owner-gated)".into(), out))
        },
        // Cannot re-init; fuel-bench the view path.
        &["paused"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Owner-gated pause/unpause (OpenZeppelin-style onlyOwner).",
            "PF owner = u64 caller projection; sdk owner = AccountId.",
        ],
    )
}

fn run_near_array_example(repo_root: &Path, args: &Args) -> Result<()> {
    run_near_compare_generic(
        repo_root,
        args,
        "array-example",
        "testkit/compare/near/array-example",
        "Examples/Product/ArrayExample.lean",
        "ArrayExample.near-artifact.json",
        "pf_near_sdk_array_example_reference.wasm",
        &["arrayexample.wat", "ArrayExample.wat"],
        &["sizeOf3", "getElem", "sumOf3"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["sizeOf3", "getElem", "sumOf3"],
                OfflineHostOpts {
                    inputs_hex_csv: "",
                    predecessor: None,
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=3"), "expected size 3\n{out}");
            ensure!(out.contains("return_u64=20"), "expected elem 20\n{out}");
            ensure!(out.contains("return_u64=60"), "expected sum 60\n{out}");
            Ok(("sizeOf3=3 getElem=20 sumOf3=60".into(), out))
        },
        &["sizeOf3", "getElem", "sumOf3"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: None,
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &["Fixed local u64x3 only; no persistent storage on either side."],
    )
}

fn run_near_ownable_hash(repo_root: &Path, args: &Args) -> Result<()> {
    let alice_hash = hex_encode_bytes(&near_account_hash32("alice.testnet"));
    let zeros = "00".repeat(32);
    run_near_compare_generic(
        repo_root,
        args,
        "ownable-hash",
        "testkit/compare/near/ownable-hash",
        "Examples/Product/OwnableHash.lean",
        "OwnableHash.near-artifact.json",
        "pf_near_sdk_ownable_hash_reference.wasm",
        &["ownablehash.wat", "OwnableHash.wat"],
        &["init", "owner", "renounceOwnership"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &["init", "owner", "renounceOwnership", "owner"],
                OfflineHostOpts {
                    inputs_hex_csv: "",
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains(&format!("return_hex={alice_hash}")),
                "expected owner=sha256(alice)\n{out}"
            );
            ensure!(
                out.contains(&format!("return_hex={zeros}")),
                "expected renounced zeros\n{out}"
            );
            Ok(("init→owner=sha256(alice)→renounce→zeros".into(), out))
        },
        &["owner"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Owner is full 32-byte sha256(predecessor), not AccountId or u64 limb.",
            "No transferOwnership on this surface (stdlib Solana constraint).",
        ],
    )
}

fn run_near_host_env_probe(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    run_near_compare_generic(
        repo_root,
        args,
        "host-env-probe",
        "testkit/compare/near/host-env-probe",
        "Examples/Product/HostEnvProbe.lean",
        "HostEnvProbe.near-artifact.json",
        "pf_near_sdk_host_env_probe_reference.wasm",
        &["hostenvprobe.wat", "HostEnvProbe.wat"],
        &["initialize", "snapshot", "getTime", "getHeight", "getSelf", "getCaller"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "initialize",
                    "getCaller",
                    "snapshot",
                    "getCaller",
                    "getSelf",
                    "getTime",
                    "getHeight",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: "",
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=0"),
                "expected zero before snapshot\n{out}"
            );
            ensure!(
                out.contains(&format!("return_u64={alice}")),
                "expected getCaller=alice limb after snapshot\n{out}"
            );
            Ok((
                format!("init→snapshot→caller={alice} (+ self/time/height)"),
                out,
            ))
        },
        &["getTime", "getHeight", "getSelf", "getCaller"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Triad-safe HostEnv only (time/height/self/caller).",
            "Absolute time/height are host-defined; identity limbs are sha256 first-8 LE.",
        ],
    )
}

fn run_near_external_protocol_client(
    repo_root: &Path,
    args: &Args,
    contract: &str,
    fixture_rel: &str,
    pf_source_rel: &str,
    artifact_name: &str,
    sdk_release_wasm: &str,
    peer_release_wasm: &str,
    wat_candidates: &[&str],
    required_entrypoints: &[&str],
    offline_calls: &[&str],
    offline_inputs: &str,
    offline_needles: &[&str],
    honesty: &[&str],
) -> Result<()> {
    let fixture_dir = repo_root.join(fixture_rel);
    let peer_dir = fixture_dir.join("peer");
    let manifest_path = fixture_dir.join("reference-manifest.json");
    let reference_source = fixture_dir.join("src/lib.rs");
    let pf_source = repo_root.join(pf_source_rel);
    ensure!(manifest_path.is_file(), "missing {}", manifest_path.display());
    ensure!(reference_source.is_file(), "missing {}", reference_source.display());
    ensure!(pf_source.is_file(), "missing {}", pf_source.display());
    ensure!(peer_dir.is_dir(), "missing peer crate {}", peer_dir.display());

    let out_root = repo_root.join(format!("build/testkit/compare/near/{contract}"));
    let pf_dir = out_root.join("proof-forge");
    let sdk_dir = out_root.join("near-sdk");
    let peer_out = out_root.join("peer");
    let report_path = out_root.join("report.json");
    if out_root.exists() {
        fs::remove_dir_all(&out_root)?;
    }
    fs::create_dir_all(&pf_dir)?;
    fs::create_dir_all(&sdk_dir)?;
    fs::create_dir_all(&peer_out)?;

    println!("=== testkit-compare near/{contract}: build ProofForge ===");
    build_proof_forge_near(repo_root, &pf_source, &pf_dir, artifact_name)?;
    let wat_path = wat_candidates
        .iter()
        .map(|n| pf_dir.join(n))
        .find(|p| p.is_file())
        .with_context(|| format!("{contract} WAT missing"))?;
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
    let artifact_path = pf_dir.join(artifact_name);

    println!("=== testkit-compare near/{contract}: entrypoint equivalence ===");
    check_equivalence_subset(&artifact_path, &reference_source, required_entrypoints)?;

    println!("=== testkit-compare near/{contract}: offline promise scenario ===");
    let semantic_out = run_offline_host_opts(
        repo_root,
        &wat_path,
        offline_calls,
        OfflineHostOpts {
            inputs_hex_csv: offline_inputs,
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
    )?;
    for needle in offline_needles {
        ensure!(
            semantic_out.contains(needle),
            "expected offline needle `{needle}`\n{semantic_out}"
        );
    }
    println!("{semantic_out}");

    println!(
        "=== testkit-compare near/{contract}: offline fuel bench (repeat={}) ===",
        args.repeat
    );
    let bench_started = Instant::now();
    let bench_out = run_offline_host_opts(
        repo_root,
        &wat_path,
        offline_calls,
        OfflineHostOpts {
            inputs_hex_csv: offline_inputs,
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: args.repeat,
        },
    )?;
    let wall_ms = bench_started.elapsed().as_secs_f64() * 1000.0;
    let fuel = parse_fuel_summary(&bench_out);

    let mut sdk_built = false;
    let mut sdk_note = "skipped".to_string();
    let mut sdk_wasm_bytes: Option<u64> = None;
    let mut peer_wasm_bytes: Option<u64> = None;
    let sdk_wasm_path = sdk_dir.join("contract.wasm");
    let peer_wasm_path = peer_out.join("contract.wasm");
    if args.build_sdk {
        println!("=== testkit-compare near/{contract}: build near-sdk client + peer ===");
        match build_near_sdk_wasm(repo_root, &fixture_dir, &sdk_dir, sdk_release_wasm) {
            Ok(bytes) => {
                sdk_built = true;
                sdk_wasm_bytes = Some(bytes);
                sdk_note = "built".to_string();
            }
            Err(err) => {
                sdk_note = format!("client build failed: {err:#}");
                if args.live {
                    bail!("--live requires sdk client: {sdk_note}");
                }
            }
        }
        match build_near_sdk_wasm(repo_root, &peer_dir, &peer_out, peer_release_wasm) {
            Ok(bytes) => peer_wasm_bytes = Some(bytes),
            Err(err) => {
                if args.live {
                    bail!("--live requires peer wasm: {err:#}");
                }
                eprintln!("WARN: peer build failed: {err:#}");
            }
        }
    }

    let mut sandbox_section = json!({
        "requested": args.live,
        "status": if args.live { "pending" } else { "not_requested" },
    });
    if args.live {
        ensure!(
            sdk_built && sdk_wasm_path.is_file() && peer_wasm_path.is_file(),
            "--live: need sdk client + peer wasms"
        );
        println!("=== testkit-compare near/{contract}: NEAR Sandbox dual deploy ===");
        let sandbox_report = out_root.join("sandbox-report.json");
        match run_near_sandbox_dual_ext(
            repo_root,
            contract,
            &wasm_path,
            &sdk_wasm_path,
            &sandbox_report,
            Some(&peer_wasm_path),
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
                    "detail": { "reason": reason },
                });
            }
            Err(err) => bail!("NEAR Sandbox dual-deploy FAILED: {err:#}"),
        }
    }

    let pf_wasm_bytes = file_len(&wasm_path)?;
    let pf_wat_bytes = file_len(&wat_path)?;
    let mut comparison = json!({
        "proofForgeWasmBytes": pf_wasm_bytes,
        "proofForgeWatBytes": pf_wat_bytes,
        "nearSdkWasmBytes": sdk_wasm_bytes,
        "peerWasmBytes": peer_wasm_bytes,
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
        "contract": contract,
        "fixtureDir": fixture_rel,
        "scenario": {
            "semantic": offline_needles.join(" + "),
            "repeat": args.repeat,
        },
        "implementations": {
            "proof-forge-emitwat": {
                "source": pf_source_rel,
                "target": "wasm-near",
                "watPath": rel(repo_root, &wat_path),
                "wasmPath": rel(repo_root, &wasm_path),
                "wasmBytes": pf_wasm_bytes,
                "watBytes": pf_wat_bytes,
                "wasmtimeFuel": fuel,
                "wallClockMs": round3(wall_ms),
            },
            "near-sdk-rs": {
                "source": fixture_rel,
                "peer": format!("{fixture_rel}/peer"),
                "built": sdk_built,
                "note": sdk_note,
                "wasmBytes": sdk_wasm_bytes,
                "peerWasmBytes": peer_wasm_bytes,
            },
        },
        "sandbox": sandbox_section,
        "comparison": comparison,
        "honesty": honesty,
    });
    fs::write(
        &report_path,
        serde_json::to_string_pretty(&report)? + "\n",
    )?;
    println!("{}", serde_json::to_string_pretty(&comparison)?);
    println!("wrote {}", rel(repo_root, &report_path));
    println!("testkit-compare near/{contract}: ok");
    Ok(())
}

fn run_near_pro_rata_vault(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let a100 = hex_encode_le_u64(100);
    let bal = hex_encode_le_u64(alice);
    // init, deposit 100, convert 100, donate 100, convert 100, deposit 100, balance, supply, assets
    let inputs = format!(",{a100},{a100},{a100},{a100},{a100},{bal},,");
    run_near_compare_generic(
        repo_root,
        args,
        "pro-rata-vault",
        "testkit/compare/near/pro-rata-vault",
        "Examples/Product/ProRataVault.lean",
        "ProRataVault.near-artifact.json",
        "pf_near_sdk_pro_rata_vault_reference.wasm",
        &["proratavault.wat", "ProRataVault.wat"],
        &[
            "init",
            "deposit",
            "donate",
            "convert_to_shares",
            "withdraw",
            "total_assets",
            "total_supply",
            "balance_of",
        ],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "deposit",
                    "convert_to_shares",
                    "donate",
                    "convert_to_shares",
                    "deposit",
                    "balance_of",
                    "total_supply",
                    "total_assets",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=100"), "expected convert 100 after first deposit\n{out}");
            ensure!(out.contains("return_u64=50"), "expected convert 50 after donate\n{out}");
            ensure!(out.contains("return_u64=150"), "expected bal/supply 150\n{out}");
            ensure!(out.contains("return_u64=300"), "expected assets 300\n{out}");
            Ok(("deposit→donate→pro-rata deposit→150/300".into(), out))
        },
        &["total_assets", "total_supply"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "ERC-4626-inspired internal vault; no IERC20 asset pulls.",
            "donate doubles assets without shares → convert_to_shares halves.",
        ],
    )
}

fn run_near_soulbound_token(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let mint = {
        let mut v = alice.to_le_bytes().to_vec();
        v.extend_from_slice(&10u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let bal = hex_encode_le_u64(alice);
    let burn = hex_encode_le_u64(10);
    // init, mint, balance, supply, burn, balance, supply
    let inputs = format!(",{mint},{bal},,{burn},{bal},");
    run_near_compare_generic(
        repo_root,
        args,
        "soulbound-token",
        "testkit/compare/near/soulbound-token",
        "Examples/Product/SoulboundTokenBody.lean",
        "SoulboundTokenBody.near-artifact.json",
        "pf_near_sdk_soulbound_token_reference.wasm",
        &["soulboundtokenbody.wat", "SoulboundTokenBody.wat"],
        &["init", "mint", "burn", "balance_of", "total_supply"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "mint",
                    "balance_of",
                    "total_supply",
                    "burn",
                    "balance_of",
                    "total_supply",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(out.contains("return_u64=10"), "expected mint bal/supply 10\n{out}");
            ensure!(out.contains("return_u64=0"), "expected after burn 0\n{out}");
            Ok(("mint 10→burn 10".into(), out))
        },
        &["total_supply"],
        "",
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "No transfer entry — soulbound honesty.",
            "TokenSpec SoulboundToken.lean is Solana plan path; body is SoulboundTokenBody.lean.",
        ],
    )
}

fn run_near_height_lock_vault(repo_root: &Path, args: &Args) -> Result<()> {
    // lock(amount=1000, unlockHeight=50)
    let lock = {
        let mut v = 1000u64.to_le_bytes().to_vec();
        v.extend_from_slice(&50u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    // init, lock, get_locked, get_unlock_height, claim, claim_balance, is_claimed, get_locked
    let inputs = format!(",{lock},,,,,,");
    let fuel_inputs = format!(",{lock},,");
    run_near_compare_generic(
        repo_root,
        args,
        "height-lock-vault",
        "testkit/compare/near/height-lock-vault",
        "Examples/Product/HeightLockVault.lean",
        "HeightLockVault.near-artifact.json",
        "pf_near_sdk_height_lock_vault_reference.wasm",
        &["heightlockvault.wat", "HeightLockVault.wat"],
        &[
            "init",
            "lock",
            "claim",
            "get_locked",
            "get_unlock_height",
            "claim_balance",
            "is_claimed",
        ],
        |repo, wat| {
            // block_index=100 >= unlockHeight=50 → claim full 1000
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "lock",
                    "get_locked",
                    "get_unlock_height",
                    "claim",
                    "claim_balance",
                    "is_claimed",
                    "get_locked",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: Some(100),
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=1000"),
                "expected locked/claim 1000\n{out}"
            );
            ensure!(
                out.contains("return_u64=50"),
                "expected unlock_height 50\n{out}"
            );
            ensure!(
                out.contains("return_u64=1"),
                "expected is_claimed 1\n{out}"
            );
            ensure!(
                out.contains("return_u64=0"),
                "expected get_locked 0 after claim\n{out}"
            );
            Ok(("init→lock 1000@height50→h=100 claim→1000".into(), out))
        },
        &["init", "lock", "claim", "claim_balance"],
        &fuel_inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: Some(100),
            repeat: 1,
        },
        &[
            "Binary height lock (checkpointId/block_index >= unlockHeight).",
            "Not wall-clock TimelockVault; not linear VestingVault.",
            "Internal claim ledger only — no external token transfer.",
            "Live: unlockHeight=1 unlocks under any real sandbox height.",
        ],
    )
}

fn run_near_timelock_vault(repo_root: &Path, args: &Args) -> Result<()> {
    // lock(amount=1000, unlockAt=50)
    let lock = {
        let mut v = 1000u64.to_le_bytes().to_vec();
        v.extend_from_slice(&50u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    // init, lock, get_locked, get_unlock_at, claim, claim_balance, is_claimed, get_locked
    let inputs = format!(",{lock},,,,,,");
    let fuel_inputs = format!(",{lock},,");
    run_near_compare_generic(
        repo_root,
        args,
        "timelock-vault",
        "testkit/compare/near/timelock-vault",
        "Examples/Product/TimelockVault.lean",
        "TimelockVault.near-artifact.json",
        "pf_near_sdk_timelock_vault_reference.wasm",
        &["timelockvault.wat", "TimelockVault.wat"],
        &[
            "init",
            "lock",
            "claim",
            "get_locked",
            "get_unlock_at",
            "claim_balance",
            "is_claimed",
        ],
        |repo, wat| {
            // t=100 >= unlockAt=50 → claim full 1000
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "lock",
                    "get_locked",
                    "get_unlock_at",
                    "claim",
                    "claim_balance",
                    "is_claimed",
                    "get_locked",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: Some(100),
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=1000"),
                "expected locked/claim 1000\n{out}"
            );
            ensure!(
                out.contains("return_u64=50"),
                "expected unlock_at 50\n{out}"
            );
            ensure!(
                out.contains("return_u64=1"),
                "expected is_claimed 1\n{out}"
            );
            ensure!(
                out.contains("return_u64=0"),
                "expected get_locked 0 after claim\n{out}"
            );
            Ok(("init→lock 1000@50→t=100 claim→1000".into(), out))
        },
        &["init", "lock", "claim", "claim_balance"],
        &fuel_inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: Some(100),
            block_index: None,
            repeat: 1,
        },
        &[
            "Binary timelock (timestamp >= unlockAt) — not linear VestingVault.",
            "Internal claim ledger only — no external token transfer.",
            "Live: unlockAt=1 fully unlocks under sandbox nanosecond time.",
        ],
    )
}

fn run_near_escrow_vault(repo_root: &Path, args: &Args) -> Result<()> {
    // init(buyer=7, seller=8), fund(1000)
    let init = {
        let mut v = 7u64.to_le_bytes().to_vec();
        v.extend_from_slice(&8u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let fund = hex_encode_le_u64(1000);
    // 8 calls: init, fund, get_status, get_amount, release, get_status, seller_claim, buyer_claim
    let inputs = format!("{init},{fund},,,,,,");
    // fuel: init, fund, release, seller_claim
    let fuel_inputs = format!("{init},{fund},,");
    run_near_compare_generic(
        repo_root,
        args,
        "escrow-vault",
        "testkit/compare/near/escrow-vault",
        "Examples/Product/EscrowVault.lean",
        "EscrowVault.near-artifact.json",
        "pf_near_sdk_escrow_vault_reference.wasm",
        &["escrowvault.wat", "EscrowVault.wat"],
        &[
            "init",
            "fund",
            "release",
            "refund",
            "get_status",
            "get_amount",
            "seller_claim",
            "buyer_claim",
            "get_buyer",
            "get_seller",
        ],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "fund",
                    "get_status",
                    "get_amount",
                    "release",
                    "get_status",
                    "seller_claim",
                    "buyer_claim",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=1"),
                "expected status Funded=1 after fund\n{out}"
            );
            ensure!(
                out.contains("return_u64=2"),
                "expected status Released=2 after release\n{out}"
            );
            ensure!(
                out.contains("return_u64=1000"),
                "expected amount/seller_claim 1000\n{out}"
            );
            ensure!(
                out.contains("return_u64=0"),
                "expected buyer_claim 0 after release\n{out}"
            );
            Ok(("init→fund 1000→release→seller_claim 1000".into(), out))
        },
        &["init", "fund", "release", "seller_claim"],
        &fuel_inputs,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "Two-party escrow state machine; internal claim ledger only.",
            "No native attached_deposit / external token transfer.",
            "release and refund are mutually exclusive once funded.",
        ],
    )
}

fn run_near_vesting_vault(repo_root: &Path, args: &Args) -> Result<()> {
    // init(who=7, total=1000, start=0, dur=100) — LE concat
    let init = {
        let mut v = 7u64.to_le_bytes().to_vec();
        v.extend_from_slice(&1000u64.to_le_bytes());
        v.extend_from_slice(&0u64.to_le_bytes());
        v.extend_from_slice(&100u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    // init, vested, releasable, release, claim_balance, released_amount, total_allocation
    let inputs = format!(",,,,,,");
    // prefix init input
    let inputs = format!("{init}{inputs}");
    run_near_compare_generic(
        repo_root,
        args,
        "vesting-vault",
        "testkit/compare/near/vesting-vault",
        "Examples/Product/VestingVault.lean",
        "VestingVault.near-artifact.json",
        "pf_near_sdk_vesting_vault_reference.wasm",
        &["vestingvault.wat", "VestingVault.wat"],
        &[
            "init",
            "vested",
            "releasable",
            "release",
            "claim_balance",
            "released_amount",
            "total_allocation",
        ],
        |repo, wat| {
            // t=50 / duration=100 → 50% of 1000 = 500 vested
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "vested",
                    "releasable",
                    "release",
                    "claim_balance",
                    "released_amount",
                    "total_allocation",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: Some(50),
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_u64=500"),
                "expected vested/releasable/claim 500 at t=50\n{out}"
            );
            ensure!(
                out.contains("return_u64=1000"),
                "expected total_allocation 1000\n{out}"
            );
            Ok(("init→t=50 half-vest→release 500".into(), out))
        },
        &["init", "release", "claim_balance", "total_allocation"],
        &format!("{init},,,"),
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: Some(50),
            block_index: None,
            repeat: 1,
        },
        &[
            "Linear vesting via HostEnv timestamp (block_timestamp).",
            "Internal claim ledger only — no external token transfer.",
            "vested/releasable are entries (scratch write; NEAR view forbids storage_write).",
            "Live: start=0 duration=1 → fully vested under sandbox ns time.",
        ],
    )
}

fn run_near_ft_peer_client(repo_root: &Path, args: &Args) -> Result<()> {
    let amt = hex_encode_le_u64(50);
    run_near_external_protocol_client(
        repo_root,
        args,
        "ft-peer-client",
        "testkit/compare/near/ft-peer-client",
        "Examples/Backend/WasmNear/FtPeerClient.lean",
        "NearFtPeerClient.near-artifact.json",
        "pf_near_sdk_ft_peer_client_reference.wasm",
        "pf_near_sdk_ft_peer_mock_reference.wasm",
        &["nearftpeerclient.wat", "NearFtPeerClient.wat", "ftpeerclient.wat"],
        &["pay", "pay_with_callback", "query_balance", "query_supply"],
        &["pay"],
        &amt,
        &["promise_create", "ft_transfer", "my_ft"],
        &[
            "Layer B protocol client (Protocols.Near.FungibleToken + Builder).",
            "Live rebuilds PF with --peer my_ft=<mock>; receiver pool is alice.near.",
            "Distinct from Product ExternalTokenTransfer (DSL external_token).",
        ],
    )
}

fn run_near_external_token_transfer(repo_root: &Path, args: &Args) -> Result<()> {
    let pay = {
        let mut v = 7u64.to_le_bytes().to_vec();
        v.extend_from_slice(&50u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let inputs = format!(",{pay}");
    run_near_external_protocol_client(
        repo_root,
        args,
        "external-token-transfer",
        "testkit/compare/near/external-token-transfer",
        "Examples/Product/ExternalTokenTransfer.lean",
        "ExternalTokenTransfer.near-artifact.json",
        "pf_near_sdk_external_token_transfer_reference.wasm",
        "pf_near_sdk_external_ft_peer_reference.wasm",
        &["externaltokentransfer.wat", "ExternalTokenTransfer.wat"],
        &["initialize", "pay", "set_allowance", "read_balance", "read_supply"],
        &["initialize", "pay"],
        &inputs,
        &["promise_create", "ft_transfer", "usdc.peer"],
        &[
            "Layer B NEP-141 peer client — not a full FT body.",
            "Live rebuilds PF with --peer usdc.peer=<mock FT>.",
            "u64 recipient → account id packing may differ (PF pool vs sdk synthetic strings).",
        ],
    )
}

fn run_near_external_vault(repo_root: &Path, args: &Args) -> Result<()> {
    let dep = {
        let mut v = 100u64.to_le_bytes().to_vec();
        v.extend_from_slice(&7u64.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let inputs = format!(",{dep}");
    run_near_external_protocol_client(
        repo_root,
        args,
        "external-vault",
        "testkit/compare/near/external-vault",
        "Examples/Product/ExternalVault.lean",
        "ExternalVault.near-artifact.json",
        "pf_near_sdk_external_vault_reference.wasm",
        "pf_near_sdk_external_vault_peer_reference.wasm",
        &["externalvault.wat", "ExternalVault.wat"],
        &["initialize", "deposit_assets", "preview_shares", "read_total_assets"],
        &["initialize", "deposit_assets"],
        &inputs,
        &["promise_create", "deposit", "vault.peer"],
        &[
            "Layer B external vault peer client — not full ERC-4626 body.",
            "Live rebuilds PF with --peer vault.peer=<mock vault>.",
            "ERC4626Vault stdlib body not in matrix (build/TokenSpec gap).",
        ],
    )
}

fn run_near_access_control(repo_root: &Path, args: &Args) -> Result<()> {
    let alice = u64::from_le_bytes(near_account_hash32("alice.testnet")[..8].try_into().unwrap());
    let bob = u64::from_le_bytes(near_account_hash32("bob.testnet")[..8].try_into().unwrap());
    let admin_args = {
        let mut v = 0u64.to_le_bytes().to_vec();
        v.extend_from_slice(&alice.to_le_bytes());
        hex_encode_bytes(&v)
    };
    let grant_args = {
        let mut v = 1u64.to_le_bytes().to_vec();
        v.extend_from_slice(&bob.to_le_bytes());
        hex_encode_bytes(&v)
    };
    // init, hasRole(0,alice), grantRole(1,bob), hasRole(1,bob), revokeRole(1,bob), hasRole(1,bob)
    let inputs = format!(",{admin_args},{grant_args},{grant_args},{grant_args},{grant_args}");
    run_near_compare_generic(
        repo_root,
        args,
        "access-control",
        "testkit/compare/near/access-control",
        "Examples/Product/AccessControl.lean",
        "AccessControl.near-artifact.json",
        "pf_near_sdk_access_control_reference.wasm",
        &["accesscontrol.wat", "AccessControl.wat"],
        &["init", "hasRole", "grantRole", "revokeRole"],
        |repo, wat| {
            let out = run_offline_host_opts(
                repo,
                wat,
                &[
                    "init",
                    "hasRole",
                    "grantRole",
                    "hasRole",
                    "revokeRole",
                    "hasRole",
                ],
                OfflineHostOpts {
                    inputs_hex_csv: &inputs,
                    predecessor: Some("alice.testnet"),
                    attached_deposit: None,
                    block_timestamp: None,
                    block_index: None,
                    repeat: 1,
                },
            )?;
            ensure!(
                out.contains("return_bool=true"),
                "expected true hasRole results\n{out}"
            );
            ensure!(
                out.contains("return_bool=false"),
                "expected false after revoke\n{out}"
            );
            Ok(("init→admin→grant minter→revoke".into(), out))
        },
        &["hasRole"],
        &admin_args,
        OfflineHostOpts {
            inputs_hex_csv: "",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
        &[
            "On wasm-near, .address params lower to U64 (sha256 limb0 of account).",
            "DEFAULT_ADMIN_ROLE=0; demo minter role=1.",
        ],
    )
}

fn run_near_auth_remote_call(repo_root: &Path, args: &Args) -> Result<()> {
    let fixture_dir = repo_root.join("testkit/compare/near/auth-remote-call");
    let callee_dir = fixture_dir.join("callee");
    let manifest_path = fixture_dir.join("reference-manifest.json");
    let reference_source = fixture_dir.join("src/lib.rs");
    let pf_source = repo_root.join("Examples/Product/AuthRemoteCall.lean");
    ensure!(manifest_path.is_file(), "missing {}", manifest_path.display());
    ensure!(reference_source.is_file(), "missing {}", reference_source.display());
    ensure!(pf_source.is_file(), "missing {}", pf_source.display());
    ensure!(callee_dir.is_dir(), "missing callee crate {}", callee_dir.display());

    let out_root = repo_root.join("build/testkit/compare/near/auth-remote-call");
    let pf_dir = out_root.join("proof-forge");
    let sdk_dir = out_root.join("near-sdk");
    let callee_out = out_root.join("callee");
    let report_path = out_root.join("report.json");
    if out_root.exists() {
        fs::remove_dir_all(&out_root)?;
    }
    fs::create_dir_all(&pf_dir)?;
    fs::create_dir_all(&sdk_dir)?;
    fs::create_dir_all(&callee_out)?;

    println!("=== testkit-compare near/auth-remote-call: build ProofForge ===");
    build_proof_forge_near(
        repo_root,
        &pf_source,
        &pf_dir,
        "AuthRemoteCall.near-artifact.json",
    )?;
    let wat_path = ["authremotecall.wat", "AuthRemoteCall.wat"]
        .iter()
        .map(|n| pf_dir.join(n))
        .find(|p| p.is_file())
        .context("AuthRemoteCall WAT missing")?;
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
    let artifact_path = pf_dir.join("AuthRemoteCall.near-artifact.json");

    println!("=== testkit-compare near/auth-remote-call: entrypoint equivalence ===");
    check_equivalence_subset(
        &artifact_path,
        &reference_source,
        &["initialize", "debit_and_forward"],
    )?;

    let amt = hex_encode_le_u64(10);
    let inputs = format!(",{amt}");
    println!("=== testkit-compare near/auth-remote-call: offline promise scenario ===");
    let semantic_out = run_offline_host_opts(
        repo_root,
        &wat_path,
        &["initialize", "debit_and_forward"],
        OfflineHostOpts {
            inputs_hex_csv: &inputs,
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
    )?;
    ensure!(
        semantic_out.contains("promise_create")
            && semantic_out.contains("receive")
            && semantic_out.contains("promise_return"),
        "expected promise_create receive/return traces\n{semantic_out}"
    );
    ensure!(
        semantic_out.contains("account=peer.callee") || semantic_out.contains("peer.callee"),
        "expected peer.callee account in promise trace\n{semantic_out}"
    );
    println!("{semantic_out}");

    println!(
        "=== testkit-compare near/auth-remote-call: offline fuel bench (repeat={}) ===",
        args.repeat
    );
    let bench_started = Instant::now();
    let bench_out = run_offline_host_opts(
        repo_root,
        &wat_path,
        &["initialize", "debit_and_forward"],
        OfflineHostOpts {
            inputs_hex_csv: &inputs,
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: args.repeat,
        },
    )?;
    let wall_ms = bench_started.elapsed().as_secs_f64() * 1000.0;
    let fuel = parse_fuel_summary(&bench_out);

    let mut sdk_built = false;
    let mut sdk_note = "skipped".to_string();
    let mut sdk_wasm_bytes: Option<u64> = None;
    let mut callee_wasm_bytes: Option<u64> = None;
    let sdk_wasm_path = sdk_dir.join("contract.wasm");
    let callee_wasm_path = callee_out.join("contract.wasm");
    if args.build_sdk {
        println!("=== testkit-compare near/auth-remote-call: build near-sdk caller + callee ===");
        match build_near_sdk_wasm(
            repo_root,
            &fixture_dir,
            &sdk_dir,
            "pf_near_sdk_auth_remote_call_reference.wasm",
        ) {
            Ok(bytes) => {
                sdk_built = true;
                sdk_wasm_bytes = Some(bytes);
                sdk_note = "built".to_string();
            }
            Err(err) => {
                sdk_note = format!("caller build failed: {err:#}");
                if args.live {
                    bail!("--live requires sdk caller: {sdk_note}");
                }
            }
        }
        match build_near_sdk_wasm(
            repo_root,
            &callee_dir,
            &callee_out,
            "pf_near_sdk_auth_remote_callee_reference.wasm",
        ) {
            Ok(bytes) => callee_wasm_bytes = Some(bytes),
            Err(err) => {
                if args.live {
                    bail!("--live requires callee wasm: {err:#}");
                }
                eprintln!("WARN: callee build failed: {err:#}");
            }
        }
    }

    let mut sandbox_section = json!({
        "requested": args.live,
        "status": if args.live { "pending" } else { "not_requested" },
    });
    if args.live {
        ensure!(
            sdk_built && sdk_wasm_path.is_file() && callee_wasm_path.is_file(),
            "--live: need sdk caller + callee wasms"
        );
        println!("=== testkit-compare near/auth-remote-call: NEAR Sandbox dual deploy ===");
        let sandbox_report = out_root.join("sandbox-report.json");
        match run_near_sandbox_dual_ext(
            repo_root,
            "auth-remote-call",
            &wasm_path,
            &sdk_wasm_path,
            &sandbox_report,
            Some(&callee_wasm_path),
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
                    "detail": { "reason": reason },
                });
            }
            Err(err) => bail!("NEAR Sandbox dual-deploy FAILED: {err:#}"),
        }
    }

    let pf_wasm_bytes = file_len(&wasm_path)?;
    let pf_wat_bytes = file_len(&wat_path)?;
    let mut comparison = json!({
        "proofForgeWasmBytes": pf_wasm_bytes,
        "proofForgeWatBytes": pf_wat_bytes,
        "nearSdkWasmBytes": sdk_wasm_bytes,
        "calleeWasmBytes": callee_wasm_bytes,
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
        "contract": "auth-remote-call",
        "fixtureDir": "testkit/compare/near/auth-remote-call",
        "scenario": {
            "semantic": "initialize → debit_and_forward(10) promise receive",
            "repeat": args.repeat,
        },
        "implementations": {
            "proof-forge-emitwat": {
                "source": "Examples/Product/AuthRemoteCall.lean",
                "target": "wasm-near",
                "watPath": rel(repo_root, &wat_path),
                "wasmPath": rel(repo_root, &wasm_path),
                "wasmBytes": pf_wasm_bytes,
                "watBytes": pf_wat_bytes,
                "wasmtimeFuel": fuel,
                "wallClockMs": round3(wall_ms),
            },
            "near-sdk-rs": {
                "source": "testkit/compare/near/auth-remote-call",
                "callee": "testkit/compare/near/auth-remote-call/callee",
                "built": sdk_built,
                "note": sdk_note,
                "wasmBytes": sdk_wasm_bytes,
                "calleeWasmBytes": callee_wasm_bytes,
            },
        },
        "sandbox": sandbox_section,
        "comparison": comparison,
        "honesty": [
            "Offline: promise_create/return host traces (peer.callee, method receive).",
            "Live: sandbox deploys receive-callee, rebuilds PF with --peer, dual-deploys callers.",
            "Promise body is raw LE u64 amount for PF/sdk interop with this callee.",
        ],
    });
    fs::write(
        &report_path,
        serde_json::to_string_pretty(&report)? + "\n",
    )?;
    println!("{}", serde_json::to_string_pretty(&comparison)?);
    println!("wrote {}", rel(repo_root, &report_path));
    println!("testkit-compare near/auth-remote-call: ok");
    Ok(())
}

fn run_near_remote_call(repo_root: &Path, args: &Args) -> Result<()> {
    let fixture_dir = repo_root.join("testkit/compare/near/remote-call");
    let callee_dir = fixture_dir.join("callee");
    let manifest_path = fixture_dir.join("reference-manifest.json");
    let reference_source = fixture_dir.join("src/lib.rs");
    let pf_source = repo_root.join("Examples/Product/RemoteCall.lean");
    ensure!(manifest_path.is_file(), "missing {}", manifest_path.display());
    ensure!(reference_source.is_file(), "missing {}", reference_source.display());
    ensure!(pf_source.is_file(), "missing {}", pf_source.display());
    ensure!(callee_dir.is_dir(), "missing callee crate {}", callee_dir.display());

    let out_root = repo_root.join("build/testkit/compare/near/remote-call");
    let pf_dir = out_root.join("proof-forge");
    let sdk_dir = out_root.join("near-sdk");
    let callee_out = out_root.join("callee");
    let report_path = out_root.join("report.json");
    if out_root.exists() {
        fs::remove_dir_all(&out_root)?;
    }
    fs::create_dir_all(&pf_dir)?;
    fs::create_dir_all(&sdk_dir)?;
    fs::create_dir_all(&callee_out)?;

    println!("=== testkit-compare near/remote-call: build ProofForge ===");
    build_proof_forge_near(
        repo_root,
        &pf_source,
        &pf_dir,
        "RemoteCall.near-artifact.json",
    )?;
    let wat_path = ["remotecall.wat", "RemoteCall.wat"]
        .iter()
        .map(|n| pf_dir.join(n))
        .find(|p| p.is_file())
        .context("RemoteCall WAT missing")?;
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
    let artifact_path = pf_dir.join("RemoteCall.near-artifact.json");

    println!("=== testkit-compare near/remote-call: entrypoint equivalence ===");
    check_equivalence_subset(
        &artifact_path,
        &reference_source,
        &["initialize", "call_remote", "call_with_args"],
    )?;

    println!("=== testkit-compare near/remote-call: offline promise scenario ===");
    let semantic_out = run_offline_host_opts(
        repo_root,
        &wat_path,
        &["initialize", "call_remote", "call_with_args"],
        OfflineHostOpts {
            inputs_hex_csv: ",,",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: 1,
        },
    )?;
    ensure!(
        semantic_out.contains("promise_create")
            && semantic_out.contains("remote_call")
            && semantic_out.contains("promise_return"),
        "expected promise_create/return traces\n{semantic_out}"
    );
    ensure!(
        semantic_out.contains("account=peer.callee") || semantic_out.contains("peer.callee"),
        "expected peer.callee account in promise trace\n{semantic_out}"
    );
    println!("{semantic_out}");

    println!(
        "=== testkit-compare near/remote-call: offline fuel bench (repeat={}) ===",
        args.repeat
    );
    let bench_started = Instant::now();
    let bench_out = run_offline_host_opts(
        repo_root,
        &wat_path,
        &["initialize", "call_remote", "call_with_args"],
        OfflineHostOpts {
            inputs_hex_csv: ",,",
            predecessor: Some("alice.testnet"),
            attached_deposit: None,
            block_timestamp: None,
            block_index: None,
            repeat: args.repeat,
        },
    )?;
    let wall_ms = bench_started.elapsed().as_secs_f64() * 1000.0;
    let fuel = parse_fuel_summary(&bench_out);

    let mut sdk_built = false;
    let mut sdk_note = "skipped".to_string();
    let mut sdk_wasm_bytes: Option<u64> = None;
    let mut callee_wasm_bytes: Option<u64> = None;
    let sdk_wasm_path = sdk_dir.join("contract.wasm");
    let callee_wasm_path = callee_out.join("contract.wasm");
    if args.build_sdk {
        println!("=== testkit-compare near/remote-call: build near-sdk caller + callee ===");
        match build_near_sdk_wasm(
            repo_root,
            &fixture_dir,
            &sdk_dir,
            "pf_near_sdk_remote_call_reference.wasm",
        ) {
            Ok(bytes) => {
                sdk_built = true;
                sdk_wasm_bytes = Some(bytes);
                sdk_note = "built".to_string();
            }
            Err(err) => {
                sdk_note = format!("caller build failed: {err:#}");
                if args.live {
                    bail!("--live requires sdk caller: {sdk_note}");
                }
            }
        }
        match build_near_sdk_wasm(
            repo_root,
            &callee_dir,
            &callee_out,
            "pf_near_sdk_remote_callee_reference.wasm",
        ) {
            Ok(bytes) => callee_wasm_bytes = Some(bytes),
            Err(err) => {
                if args.live {
                    bail!("--live requires callee wasm: {err:#}");
                }
                eprintln!("WARN: callee build failed: {err:#}");
            }
        }
    }

    let mut sandbox_section = json!({
        "requested": args.live,
        "status": if args.live { "pending" } else { "not_requested" },
    });
    if args.live {
        ensure!(
            sdk_built && sdk_wasm_path.is_file() && callee_wasm_path.is_file(),
            "--live: need sdk caller + callee wasms"
        );
        println!("=== testkit-compare near/remote-call: NEAR Sandbox dual deploy ===");
        let sandbox_report = out_root.join("sandbox-report.json");
        match run_near_sandbox_dual_ext(
            repo_root,
            "remote-call",
            &wasm_path,
            &sdk_wasm_path,
            &sandbox_report,
            Some(&callee_wasm_path),
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
                    "detail": { "reason": reason },
                });
            }
            Err(err) => bail!("NEAR Sandbox dual-deploy FAILED: {err:#}"),
        }
    }

    let pf_wasm_bytes = file_len(&wasm_path)?;
    let pf_wat_bytes = file_len(&wat_path)?;
    let mut comparison = json!({
        "proofForgeWasmBytes": pf_wasm_bytes,
        "proofForgeWatBytes": pf_wat_bytes,
        "nearSdkWasmBytes": sdk_wasm_bytes,
        "calleeWasmBytes": callee_wasm_bytes,
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
        "contract": "remote-call",
        "fixtureDir": "testkit/compare/near/remote-call",
        "scenario": {
            "semantic": "initialize → call_remote/call_with_args promise_create traces",
            "repeat": args.repeat,
        },
        "implementations": {
            "proof-forge-emitwat": {
                "source": "Examples/Product/RemoteCall.lean",
                "target": "wasm-near",
                "watPath": rel(repo_root, &wat_path),
                "wasmPath": rel(repo_root, &wasm_path),
                "wasmBytes": pf_wasm_bytes,
                "watBytes": pf_wat_bytes,
                "wasmtimeFuel": fuel,
                "wallClockMs": round3(wall_ms),
            },
            "near-sdk-rs": {
                "source": "testkit/compare/near/remote-call",
                "callee": "testkit/compare/near/remote-call/callee",
                "built": sdk_built,
                "note": sdk_note,
                "wasmBytes": sdk_wasm_bytes,
                "calleeWasmBytes": callee_wasm_bytes,
            },
        },
        "sandbox": sandbox_section,
        "comparison": comparison,
        "honesty": [
            "Offline: promise_create/return host traces (peer.callee logical id).",
            "Live: sandbox deploys callee, rebuilds PF with --peer peer.callee=<id>, dual-deploys callers.",
            "sdk initialize takes callee AccountId; PF peer string is compile-time.",
        ],
    });
    fs::write(
        &report_path,
        serde_json::to_string_pretty(&report)? + "\n",
    )?;
    println!("{}", serde_json::to_string_pretty(&comparison)?);
    println!("wrote {}", rel(repo_root, &report_path));
    println!("testkit-compare near/remote-call: ok");
    Ok(())
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
    run_near_sandbox_dual_ext(repo_root, contract, pf_wasm, sdk_wasm, report_path, None)
}

fn run_near_sandbox_dual_ext(
    repo_root: &Path,
    contract: &str,
    pf_wasm: &Path,
    sdk_wasm: &Path,
    report_path: &Path,
    callee_wasm: Option<&Path>,
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

    let mut cmd = Command::new(&cargo);
    cmd.current_dir(repo_root)
        .args(["run", "--quiet", "--manifest-path"])
        .arg(&sandbox_manifest)
        .args(["--", "--contract", contract, "--pf-wasm"])
        .arg(pf_wasm)
        .arg("--sdk-wasm")
        .arg(sdk_wasm)
        .arg("--report")
        .arg(report_path)
        .arg("--repo-root")
        .arg(repo_root);
    if let Some(c) = callee_wasm {
        cmd.arg("--callee-wasm").arg(c);
    }
    let output = cmd
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
    // Prefer rustup cargo + PATH so wasm32 std is available even when
    // Homebrew rustc sits earlier on the default PATH (no wasm32 target).
    let cargo = prefer_rustup_cargo();
    let target_dir = sdk_out.join("target");
    let mut cmd = Command::new(&cargo);
    // Drop empty / polluted RUSTC so cargo does not invoke sccache with "".
    match env::var_os("RUSTC") {
        None => {}
        Some(v) if v.is_empty() => {
            cmd.env_remove("RUSTC");
        }
        Some(_) => {
            // Prefer rustup's rustc when we control cargo via rustup.
            if let Some(rustc) = prefer_rustup_bin("rustc") {
                cmd.env("RUSTC", rustc);
            } else {
                cmd.env_remove("RUSTC");
            }
        }
    }
    if let Some(cargo_bin) = cargo.parent() {
        let mut path = cargo_bin.as_os_str().to_os_string();
        path.push(":");
        if let Some(existing) = env::var_os("PATH") {
            path.push(existing);
        }
        cmd.env("PATH", path);
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
    prefer_rustup_bin("cargo").unwrap_or_else(|| PathBuf::from("cargo"))
}

fn prefer_rustup_bin(name: &str) -> Option<PathBuf> {
    let home = env::var_os("HOME")?;
    let candidate = PathBuf::from(home).join(".cargo/bin").join(name);
    candidate.is_file().then_some(candidate)
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
