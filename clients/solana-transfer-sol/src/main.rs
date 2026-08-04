//! solana-transfer-sol CLI entrypoint.

use clap::Parser;
use solana_transfer_sol::{
    print_receipt_json, print_verify_json, reject_secret_argv, run_devnet_call,
    run_verify_artifacts, validate_devnet_bounds, Cli, ClientError, Commands, DevnetCallArgs,
};

fn main() {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    if let Err(e) = reject_secret_argv(&raw) {
        eprintln!("error: {e}");
        std::process::exit(e.exit_code());
    }

    let cli = match Cli::try_parse() {
        Ok(c) => c,
        Err(e) => {
            e.print().ok();
            std::process::exit(2);
        }
    };

    if let Err(e) = dispatch(cli) {
        // Errors use redacted endpoints only (rpc display form).
        eprintln!("error: {e}");
        std::process::exit(e.exit_code());
    }
}

fn dispatch(cli: Cli) -> Result<(), ClientError> {
    match cli.command {
        Commands::VerifyArtifacts { artifact_dir } => {
            let v = run_verify_artifacts(&artifact_dir)?;
            print_verify_json(&v)?;
            Ok(())
        }
        Commands::DevnetCall {
            artifact_dir,
            program_id,
            rpc_url,
            lamports,
            timeout_secs,
            wall_deadline_secs,
        } => {
            validate_devnet_bounds(lamports, timeout_secs, wall_deadline_secs)?;
            let receipt = run_devnet_call(DevnetCallArgs {
                artifact_dir: &artifact_dir,
                program_id: &program_id,
                rpc_url: &rpc_url,
                lamports,
                timeout_secs,
                wall_deadline_secs,
            })?;
            print_receipt_json(&receipt)?;
            Ok(())
        }
    }
}
