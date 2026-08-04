//! Offline `proof-forge-solana-client` artifact verifier entrypoint.

use clap::Parser;
use proof_forge_solana_client::{
    print_verify_json, run_verify_artifacts, Cli, ClientError, Commands,
};

fn main() {
    // `Parser::parse` preserves clap's exit contract: help/version exit 0,
    // malformed usage exits 2. Runtime verification errors use ClientError.
    let cli = Cli::parse();

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
            let verified = run_verify_artifacts(&artifact_dir, program_adapter)?;
            print_verify_json(&verified)
        }
    }
}
