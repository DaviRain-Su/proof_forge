mod artifact;
mod cmd;
mod compiler;
mod error;
mod result_json;
mod safety;
mod targets;
mod tools_leo;

use clap::{Args, Parser, Subcommand};
use error::PfResult;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "pf", version, about = "ProofForge developer CLI")]
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
    Setup {
        #[arg(long)]
        target: String,
    },
    Doctor {
        #[arg(long)]
        target: Vec<String>,
    },
    Build(BuildArgs),
    Check(CheckArgs),
    Inspect {
        #[arg(long)]
        artifact: PathBuf,
    },
    Local {
        #[command(subcommand)]
        command: LocalCommands,
    },
    Deploy(NetworkArgs),
    Execute(ExecuteArgs),
    Version,
    ListTargets,
}

#[derive(Args)]
struct BuildArgs {
    source: PathBuf,
    #[arg(long)]
    module: String,
    #[arg(long)]
    target: String,
    #[arg(long)]
    root: Option<PathBuf>,
    #[arg(short = 'o', long, default_value = "build/v2")]
    output: PathBuf,
    #[arg(long)]
    profile: Option<String>,
}

#[derive(Args)]
struct CheckArgs {
    source: PathBuf,
    #[arg(long)]
    module: String,
    #[arg(long)]
    root: Option<PathBuf>,
}

#[derive(Subcommand)]
enum LocalCommands {
    Run(LocalRunArgs),
}

#[derive(Args)]
struct LocalRunArgs {
    #[arg(long)]
    target: String,
    #[arg(long)]
    artifact: PathBuf,
    #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
    args: Vec<String>,
}

#[derive(Args)]
struct NetworkArgs {
    #[arg(long)]
    target: String,
    #[arg(long)]
    artifact: PathBuf,
    #[arg(long)]
    network: String,
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
        Commands::Setup { .. } => "setup",
        Commands::Doctor { .. } => "doctor",
        Commands::Build(_) => "build",
        Commands::Check(_) => "check",
        Commands::Inspect { .. } => "inspect",
        Commands::Local { .. } => "local run",
        Commands::Deploy(_) => "deploy",
        Commands::Execute(_) => "execute",
        Commands::Version => "version",
        Commands::ListTargets => "list-targets",
    }
}

fn dispatch(cli: Cli) -> PfResult<()> {
    let json = cli.json;
    match cli.command {
        Commands::Setup { target } => cmd::doctor::setup(&target, cli.yes, json),
        Commands::Doctor { target } => cmd::doctor::run(&target, json),
        Commands::Build(a) => cmd::build::run(
            &a.source,
            &a.module,
            &a.target,
            a.root.as_deref(),
            &a.output,
            a.profile.as_deref(),
            json,
        ),
        Commands::Check(a) => cmd::check::run(&a.source, &a.module, a.root.as_deref(), json),
        Commands::Inspect { artifact } => cmd::inspect::run(&artifact, json),
        Commands::Local {
            command: LocalCommands::Run(a),
        } => cmd::local_run::run(&a.target, &a.artifact, &a.args[0], &a.args[1..], json),
        Commands::Deploy(a) => cmd::deploy::run(
            &a.target,
            &a.artifact,
            &a.network,
            a.endpoint.as_deref(),
            a.broadcast,
            a.private_key_env.as_deref(),
            a.save.as_deref(),
            json,
        ),
        Commands::Execute(a) => cmd::execute::run(
            &a.network.target,
            &a.network.artifact,
            &a.network.network,
            a.network.endpoint.as_deref(),
            a.network.broadcast,
            a.network.private_key_env.as_deref(),
            a.network.save.as_deref(),
            &a.args[0],
            &a.args[1..],
            json,
        ),
        Commands::Version => cmd::version::run(json),
        Commands::ListTargets => cmd::list_targets::run(json),
    }
}
