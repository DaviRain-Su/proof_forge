//! Offline `proof-forge-solana-client` artifact verifier entrypoint.

use clap::Parser;
use proof_forge_solana_client::{
    print_verify_json, run_verify_artifacts, Cli, ClientError, Commands, ProgramAdapterId,
};

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
        Commands::VerifyArtifacts {
            artifact_dir,
            program_adapter,
        } => {
            let adapter = match program_adapter {
                Some(s) => Some(ProgramAdapterId::parse(&s)?),
                None => None,
            };
            let verified = run_verify_artifacts(&artifact_dir, adapter)?;
            print_verify_json(&verified)
        }
    }
}
