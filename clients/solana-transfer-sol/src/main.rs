//! Offline `solana-transfer-sol` artifact verifier entrypoint.

use clap::Parser;
use solana_transfer_sol::{print_verify_json, run_verify_artifacts, Cli, ClientError, Commands};

fn main() {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            error.print().ok();
            std::process::exit(2);
        }
    };

    if let Err(error) = dispatch(cli) {
        eprintln!("error: {error}");
        std::process::exit(error.exit_code());
    }
}

fn dispatch(cli: Cli) -> Result<(), ClientError> {
    match cli.command {
        Commands::VerifyArtifacts { artifact_dir } => {
            let verified = run_verify_artifacts(&artifact_dir)?;
            print_verify_json(&verified)
        }
    }
}
