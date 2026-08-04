//! Offline-only CLI surface. Network, deployment, wallet, and faucet inputs do not exist.

use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "solana-transfer-sol",
    about = "Verify ProofForge TransferSol product artifacts offline",
    long_about = "Offline engineering verifier only. It never deploys, opens an RPC connection, \
reads a wallet, requests funds, or sends a transaction. Local execution is owned by the \
repository Mollusk test lane. The sourceHash trust anchor is the frozen \
Examples/TransferSol.lean product pin and is not overridable."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    /// Pure offline verification of a TransferSol `proof-forge.output.v1` directory.
    VerifyArtifacts {
        /// Path to the product OutputSet directory (manifest.json + evidence + six leaves).
        #[arg(long)]
        artifact_dir: PathBuf,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_offline_verify_artifacts() {
        let cli = Cli::try_parse_from([
            "solana-transfer-sol",
            "verify-artifacts",
            "--artifact-dir",
            "build/out",
        ])
        .unwrap();
        match cli.command {
            Commands::VerifyArtifacts { artifact_dir } => {
                assert_eq!(artifact_dir, PathBuf::from("build/out"));
            }
        }
    }

    #[test]
    fn network_and_trust_override_surfaces_are_absent() {
        for args in [
            vec!["solana-transfer-sol", "devnet-call"],
            vec!["solana-transfer-sol", "deploy"],
            vec![
                "solana-transfer-sol",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--rpc-url",
                "https://example.invalid",
            ],
            vec![
                "solana-transfer-sol",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--keypair",
                "wallet.json",
            ],
            vec![
                "solana-transfer-sol",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--expected-source-hash",
                "00",
            ],
        ] {
            assert!(Cli::try_parse_from(args).is_err());
        }
    }
}
