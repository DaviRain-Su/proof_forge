use std::collections::HashMap;
use std::env;
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use proof_forge_testkit_core::{
    assert_expectations, assert_trace_equivalence, discover_scenarios, ChainHarness, DiagnosticRun,
    HarnessRun, ScenarioCase, TargetTrace,
};
use proof_forge_testkit_harness_evm::EvmHarness;
use proof_forge_testkit_harness_near::NearHarness;
use proof_forge_testkit_harness_quint::{run_mbt, QuintRun};
use proof_forge_testkit_harness_solana::SolanaHarness;

fn main() -> Result<()> {
    let args = Args::parse(env::args().skip(1))?;
    let repo_root = env::current_dir().context("failed to read current directory")?;
    let scenario_dir = repo_root.join(&args.scenario_dir);
    let scenarios = discover_scenarios(&scenario_dir)?;

    match args.command {
        CommandKind::List => list_scenarios(&scenarios),
        CommandKind::Run => run_scenarios(&repo_root, &scenarios, &args),
    }
}

#[derive(Debug)]
struct Args {
    command: CommandKind,
    scenario: Option<String>,
    target: Option<String>,
    scenario_dir: PathBuf,
    trace: bool,
    /// PF-P2-01: CI mode — skipped target/diagnostic/quint runs are failures.
    deny_skip: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CommandKind {
    Run,
    List,
}

impl Args {
    fn parse<I>(args: I) -> Result<Self>
    where
        I: IntoIterator<Item = String>,
    {
        let mut command = CommandKind::Run;
        let mut scenario = None;
        let mut target = None;
        let mut scenario_dir = PathBuf::from("testkit/scenarios");
        let mut trace = false;
        let mut deny_skip = false;

        let mut args = args.into_iter().peekable();
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "run" => command = CommandKind::Run,
                "list" => command = CommandKind::List,
                "--scenario" => scenario = Some(take_arg(&mut args, "--scenario")?),
                "--target" => target = Some(take_arg(&mut args, "--target")?),
                "--scenarios-dir" => {
                    scenario_dir = PathBuf::from(take_arg(&mut args, "--scenarios-dir")?);
                }
                "--trace" => trace = true,
                "--deny-skip" => deny_skip = true,
                "-h" | "--help" => {
                    print_usage();
                    std::process::exit(0);
                }
                other => bail!("unknown testkit argument `{other}`"),
            }
        }

        Ok(Self {
            command,
            scenario,
            target,
            scenario_dir,
            trace,
            deny_skip,
        })
    }
}

fn take_arg<I>(args: &mut std::iter::Peekable<I>, option: &str) -> Result<String>
where
    I: Iterator<Item = String>,
{
    args.next()
        .ok_or_else(|| anyhow::anyhow!("{option} requires a value"))
}

fn print_usage() {
    eprintln!(
        "usage: proof-forge-testkit [run|list] [--scenario NAME] [--target ID] [--scenarios-dir DIR] [--trace] [--deny-skip]"
    );
}

fn list_scenarios(scenarios: &[ScenarioCase]) -> Result<()> {
    for case in scenarios {
        println!(
            "{} fixture={} targets=[{}]",
            case.manifest.scenario.name,
            case.manifest.scenario.fixture,
            case.manifest.scenario.targets.join(",")
        );
    }
    Ok(())
}

fn run_scenarios(repo_root: &Path, scenarios: &[ScenarioCase], args: &Args) -> Result<()> {
    let harnesses = harnesses();
    let selected: Vec<&ScenarioCase> = scenarios
        .iter()
        .filter(|case| {
            let scenario_matches = args
                .scenario
                .as_ref()
                .map(|name| case.manifest.scenario.name == *name)
                .unwrap_or(true);
            let target_matches = args
                .target
                .as_ref()
                .map(|target| {
                    case.manifest
                        .scenario
                        .targets
                        .iter()
                        .any(|candidate| candidate == target)
                })
                .unwrap_or(true);
            scenario_matches && target_matches
        })
        .collect();

    if selected.is_empty() {
        bail!("no scenarios matched");
    }

    println!("testkit: discovered {} scenario(s)", selected.len());
    let mut target_runs = 0usize;
    let mut diagnostic_runs = 0usize;
    let mut quint_runs = 0usize;
    let mut skipped_runs = 0usize;
    let run_quint = args
        .target
        .as_deref()
        .map(|target| target == "quint")
        .unwrap_or(true);
    let run_chain_targets = args
        .target
        .as_deref()
        .map(|target| target != "quint")
        .unwrap_or(true);
    for case in selected {
        let targets: Vec<&str> = case
            .manifest
            .scenario
            .targets
            .iter()
            .map(String::as_str)
            .filter(|target| args.target.as_deref().map(|t| t == *target).unwrap_or(true))
            .collect();
        if targets.is_empty() {
            bail!(
                "scenario `{}` has no targets after filtering",
                case.manifest.scenario.name
            );
        }

        if run_quint {
            for quint in &case.manifest.quint {
                match run_mbt(case, quint, repo_root)? {
                    QuintRun::Passed => {
                        println!(
                            "scenario {} quint {}: ok",
                            case.manifest.scenario.name, quint.name
                        );
                        quint_runs += 1;
                    }
                    QuintRun::Skipped { reason } => {
                        if args.deny_skip {
                            bail!(
                                "scenario {} quint {}: skipped under --deny-skip ({reason})",
                                case.manifest.scenario.name,
                                quint.name
                            );
                        }
                        println!(
                            "scenario {} quint {}: skipped ({reason})",
                            case.manifest.scenario.name, quint.name
                        );
                        skipped_runs += 1;
                    }
                }
            }
        }

        if !run_chain_targets {
            continue;
        }

        for diagnostic in case.manifest.diagnostics.iter().filter(|diagnostic| {
            args.target
                .as_deref()
                .map(|target| diagnostic.target == target)
                .unwrap_or(true)
        }) {
            let Some(harness) = harnesses.get(diagnostic.target.as_str()) else {
                bail!(
                    "scenario `{}` targets unsupported `{}`",
                    case.manifest.scenario.name,
                    diagnostic.target
                );
            };
            match harness.run_diagnostic(case, diagnostic, repo_root)? {
                DiagnosticRun::Passed => {
                    println!(
                        "scenario {} target {} diagnostic {}: ok",
                        case.manifest.scenario.name, diagnostic.target, diagnostic.name
                    );
                    diagnostic_runs += 1;
                }
                DiagnosticRun::Skipped { reason } => {
                    if args.deny_skip {
                        bail!(
                            "scenario {} target {} diagnostic {}: skipped under --deny-skip ({reason})",
                            case.manifest.scenario.name,
                            diagnostic.target,
                            diagnostic.name
                        );
                    }
                    println!(
                        "scenario {} target {} diagnostic {}: skipped ({reason})",
                        case.manifest.scenario.name, diagnostic.target, diagnostic.name
                    );
                    skipped_runs += 1;
                }
            }
        }

        if case.manifest.steps.is_empty() {
            continue;
        }

        let mut runs = Vec::new();
        let target_count = targets.len();
        for target in &targets {
            let Some(harness) = harnesses.get(*target) else {
                bail!(
                    "scenario `{}` targets unsupported `{target}`",
                    case.manifest.scenario.name
                );
            };
            match harness.run_scenario(case, repo_root)? {
                HarnessRun::Passed(outcomes) => {
                    if args.trace {
                        for outcome in &outcomes {
                            println!("{}", outcome.raw_line);
                        }
                    }
                    assert_expectations(case, target, &outcomes)?;
                    println!(
                        "scenario {} target {}: ok ({} call outcome(s))",
                        case.manifest.scenario.name,
                        target,
                        outcomes.len()
                    );
                    runs.push(((*target).to_string(), outcomes));
                    target_runs += 1;
                }
                HarnessRun::Skipped { reason } => {
                    if args.deny_skip {
                        bail!(
                            "scenario {} target {}: skipped under --deny-skip ({reason})",
                            case.manifest.scenario.name,
                            target
                        );
                    }
                    println!(
                        "scenario {} target {}: skipped ({reason})",
                        case.manifest.scenario.name, target
                    );
                    skipped_runs += 1;
                }
            }
        }

        let traces: Vec<TargetTrace<'_>> = runs
            .iter()
            .map(|(target, outcomes)| TargetTrace {
                target_id: target.as_str(),
                outcomes,
            })
            .collect();
        // PF-P2-01: never claim multi-target parity with fewer than two executed targets.
        if args.deny_skip && target_count > 1 && traces.len() < 2 {
            bail!(
                "scenario {} trace parity refused under --deny-skip: need ≥2 executed targets, got {}",
                case.manifest.scenario.name,
                traces.len()
            );
        }
        assert_trace_equivalence(case, &traces)?;
        if traces.len() > 1 {
            println!(
                "scenario {} trace parity: ok ({} target(s))",
                case.manifest.scenario.name,
                traces.len()
            );
        } else if traces.len() == 1 && target_count > 1 {
            println!(
                "scenario {} trace parity: partial (1 of {} target(s) executed; not parity success)",
                case.manifest.scenario.name,
                target_count
            );
        }
    }
    print_summary(target_runs, diagnostic_runs, quint_runs, skipped_runs);
    Ok(())
}

fn print_summary(
    target_runs: usize,
    diagnostic_runs: usize,
    quint_runs: usize,
    skipped_runs: usize,
) {
    let mut parts = vec![format!("{target_runs} target run(s)")];
    if diagnostic_runs > 0 {
        parts.push(format!("{diagnostic_runs} diagnostic run(s)"));
    }
    if quint_runs > 0 {
        parts.push(format!("{quint_runs} quint run(s)"));
    }
    if skipped_runs > 0 {
        parts.push(format!("{skipped_runs} skipped"));
    }
    println!("testkit: ok ({})", parts.join(", "));
}

fn harnesses() -> HashMap<&'static str, Box<dyn ChainHarness>> {
    let mut harnesses: HashMap<&'static str, Box<dyn ChainHarness>> = HashMap::new();
    let evm = EvmHarness::new();
    harnesses.insert(evm.target_id(), Box::new(evm));
    let near = NearHarness::new();
    harnesses.insert(near.target_id(), Box::new(near));
    let solana = SolanaHarness::new();
    harnesses.insert(solana.target_id(), Box::new(solana));
    harnesses
}
