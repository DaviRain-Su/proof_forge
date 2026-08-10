mod artifact;
mod cmd;
mod compiler;
mod error;
mod project;
mod result_json;
mod safety;
mod targets;
mod tools_leo;

use clap::{Args, Parser, Subcommand};
use error::PfResult;
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "pf",
    version,
    about = "ProofForge developer CLI (cargo-like)",
    long_about = "Project-oriented wrapper around proof-forge-next and official chain tools.\n\
\n\
Typical flow:\n  pf new hello && cd hello\n  pf build\n  pf run -- initialize 5u64\n  pf deploy --network testnet\n\
\n\
Defaults come from pf.toml (default-target=aleo, out-dir=build/<target>/)."
)]
struct Cli {
    #[arg(long, global = true)]
    json: bool,
    #[arg(long, short = 'y', global = true)]
    yes: bool,
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new ProofForge project from the StateCell template
    New {
        /// Package directory / name
        name: String,
        /// Default build target written into pf.toml
        #[arg(long, default_value = "aleo")]
        target: String,
        /// Optional path (default: ./<name>)
        #[arg(long)]
        path: Option<PathBuf>,
    },
    /// Show toolchain status (compiler + host Leo when present)
    Setup {
        #[arg(long)]
        target: Option<String>,
    },
    Doctor {
        #[arg(long)]
        target: Vec<String>,
    },
    /// Build the project (default target from pf.toml → build/<target>/)
    Build(BuildArgs),
    /// Remove all build artifacts under the configured out-dir
    Clean,
    /// Typecheck / validate without writing artifacts
    Check(CheckArgs),
    /// Validate an artifact directory (default: build/<target>/)
    Inspect {
        #[arg(long)]
        artifact: Option<PathBuf>,
        #[arg(long)]
        target: Option<String>,
    },
    /// Offline chain verify (Solana: proof-forge-solana-client)
    Verify {
        #[arg(long, short = 't')]
        target: Option<String>,
        #[arg(long)]
        artifact: Option<PathBuf>,
        /// Solana program adapter id (e.g. transfer-sol-v1)
        #[arg(long)]
        adapter: Option<String>,
    },
    /// Local runtime test (EVM Anvil / Solana Mollusk / Aleo leo smoke).
    /// Multi-target: `-t evm,solana` runs sequentially; any hard fail → non-zero.
    Test {
        /// Target or comma-list (default: pf.toml default-target)
        #[arg(long, short = 't')]
        target: Option<String>,
        /// Artifact dir (single-target only; multi-target uses build/<target>/)
        #[arg(long)]
        artifact: Option<PathBuf>,
    },
    /// Local run (Aleo VM). Alias of `local run`.
    Run(RunArgs),
    Local {
        #[command(subcommand)]
        command: LocalCommands,
    },
    /// Materialize deploy tx (save-only unless --broadcast)
    Deploy(NetworkArgs),
    /// Materialize execute tx (save-only unless --broadcast)
    Execute(ExecuteArgs),
    Version,
    ListTargets,
}

#[derive(Args)]
struct BuildArgs {
    /// Optional source override (default: pf.toml package.source)
    source: Option<PathBuf>,
    #[arg(long)]
    module: Option<String>,
    /// Override default-target from pf.toml / PF_TARGET
    #[arg(long, short = 't')]
    target: Option<String>,
    #[arg(long)]
    root: Option<PathBuf>,
    /// Override output directory (default: build/<target>/)
    #[arg(short = 'o', long)]
    output: Option<PathBuf>,
    #[arg(long)]
    profile: Option<String>,
}

#[derive(Args)]
struct CheckArgs {
    source: Option<PathBuf>,
    #[arg(long)]
    module: Option<String>,
    #[arg(long)]
    root: Option<PathBuf>,
}

#[derive(Subcommand)]
enum LocalCommands {
    Run(RunArgs),
}

#[derive(Args)]
struct RunArgs {
    #[arg(long, short = 't')]
    target: Option<String>,
    #[arg(long)]
    artifact: Option<PathBuf>,
    /// Print full Leo toolchain chatter (default: summary only)
    #[arg(long, short = 'v')]
    verbose: bool,
    /// Function and inputs after `--`, e.g. `initialize 5u64`
    #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
    args: Vec<String>,
}

#[derive(Args)]
struct NetworkArgs {
    #[arg(long, short = 't')]
    target: Option<String>,
    #[arg(long)]
    artifact: Option<PathBuf>,
    /// local|testnet|devnet (mainnet refused). Aleo default=testnet; EVM/Solana deploy default=local
    #[arg(long, short = 'n')]
    network: Option<String>,
    #[arg(long)]
    endpoint: Option<String>,
    #[arg(long)]
    broadcast: bool,
    #[arg(long)]
    private_key_env: Option<String>,
    #[arg(long)]
    save: Option<PathBuf>,
}

#[derive(Args)]
struct ExecuteArgs {
    #[command(flatten)]
    network: NetworkArgs,
    #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
    args: Vec<String>,
}

fn main() {
    let cli = Cli::parse();
    let json = cli.json;
    let command_name = command_name(&cli.command);
    if let Err(error) = dispatch(cli) {
        if json {
            result_json::print_err(command_name, &error);
        } else {
            eprintln!("error: {error}");
        }
        std::process::exit(if error.exit_code() == std::process::ExitCode::from(2) {
            2
        } else {
            1
        });
    }
}

fn command_name(command: &Commands) -> &'static str {
    match command {
        Commands::New { .. } => "new",
        Commands::Setup { .. } => "setup",
        Commands::Doctor { .. } => "doctor",
        Commands::Build(_) => "build",
        Commands::Clean => "clean",
        Commands::Check(_) => "check",
        Commands::Inspect { .. } => "inspect",
        Commands::Verify { .. } => "verify",
        Commands::Test { .. } => "test",
        Commands::Run(_) | Commands::Local { .. } => "run",
        Commands::Deploy(_) => "deploy",
        Commands::Execute(_) => "execute",
        Commands::Version => "version",
        Commands::ListTargets => "list-targets",
    }
}

fn dispatch(cli: Cli) -> PfResult<()> {
    let json = cli.json;
    match cli.command {
        Commands::New { name, target, path } => {
            cmd::new::run(&name, Some(&target), path.as_ref(), json)
        }
        Commands::Setup { target } => {
            let t = target.unwrap_or_else(|| project::DEFAULT_TARGET.into());
            cmd::doctor::setup(&t, cli.yes, json)
        }
        Commands::Doctor { target } => {
            let targets = if target.is_empty() {
                vec![project::DEFAULT_TARGET.to_string()]
            } else {
                target
            };
            cmd::doctor::run(&targets, json)
        }
        Commands::Build(a) => cmd::build::run(cmd::build::BuildOpts {
            source: a.source.as_deref(),
            module: a.module.as_deref(),
            target: a.target.as_deref(),
            root: a.root.as_deref(),
            output: a.output.as_deref(),
            profile: a.profile.as_deref(),
            json,
        }),
        Commands::Clean => cmd::clean::run(json),
        Commands::Check(a) => cmd::check::run(
            a.source.as_deref(),
            a.module.as_deref(),
            a.root.as_deref(),
            json,
        ),
        Commands::Inspect { artifact, target } => {
            cmd::inspect::run(artifact.as_deref(), target.as_deref(), json)
        }
        Commands::Verify {
            target,
            artifact,
            adapter,
        } => cmd::verify::run(
            target.as_deref(),
            artifact.as_deref(),
            adapter.as_deref(),
            json,
        ),
        Commands::Test { target, artifact } => {
            cmd::test::run(target.as_deref(), artifact.as_deref(), json)
        }
        Commands::Run(a) => cmd::local_run::run(
            a.target.as_deref(),
            a.artifact.as_deref(),
            &a.args,
            json,
            a.verbose,
        ),
        Commands::Local {
            command: LocalCommands::Run(a),
        } => cmd::local_run::run(
            a.target.as_deref(),
            a.artifact.as_deref(),
            &a.args,
            json,
            a.verbose,
        ),
        Commands::Deploy(a) => cmd::deploy::run(
            a.target.as_deref(),
            a.artifact.as_deref(),
            a.network.as_deref(),
            a.endpoint.as_deref(),
            a.broadcast,
            a.private_key_env.as_deref(),
            a.save.as_deref(),
            json,
        ),
        Commands::Execute(a) => cmd::execute::run(
            a.network.target.as_deref(),
            a.network.artifact.as_deref(),
            a.network.network.as_deref(),
            a.network.endpoint.as_deref(),
            a.network.broadcast,
            a.network.private_key_env.as_deref(),
            a.network.save.as_deref(),
            &a.args,
            json,
        ),
        Commands::Version => cmd::version::run(json),
        Commands::ListTargets => cmd::list_targets::run(json),
    }
}
