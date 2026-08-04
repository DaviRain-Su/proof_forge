//! Offline-only CLI surface. Network, deployment, wallet, and faucet inputs do not exist.

use std::path::PathBuf;

use clap::{Parser, Subcommand};

use crate::program_adapter::ProgramAdapterId;

#[derive(Debug, Parser)]
#[command(
    name = "proof-forge-solana-client",
    about = "Verify ProofForge Solana product artifacts offline",
    long_about = "Offline engineering verifier for generic Solana OutputSets. It never deploys, \
opens an RPC connection, reads a wallet, requests funds, or sends a transaction. Local execution \
is owned by the repository Mollusk test lane. Optional program adapters pin fixture-specific \
sourceHash and ABI joins; they are not overridable via CLI flags."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    /// Pure offline verification of a Solana `proof-forge.output.v1` directory.
    VerifyArtifacts {
        /// Path to the product OutputSet directory (manifest.json + evidence + profile leaves).
        #[arg(long)]
        artifact_dir: PathBuf,

        /// Optional program adapter (e.g. `transfer-sol-v1`). Default: none (generic only).
        #[arg(long, value_enum)]
        program_adapter: Option<ProgramAdapterId>,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_offline_verify_artifacts() {
        let cli = Cli::try_parse_from([
            "proof-forge-solana-client",
            "verify-artifacts",
            "--artifact-dir",
            "build/out",
        ])
        .unwrap();
        match cli.command {
            Commands::VerifyArtifacts {
                artifact_dir,
                program_adapter,
            } => {
                assert_eq!(artifact_dir, PathBuf::from("build/out"));
                assert!(program_adapter.is_none());
            }
        }
    }

    #[test]
    fn accepts_optional_program_adapter() {
        let cli = Cli::try_parse_from([
            "proof-forge-solana-client",
            "verify-artifacts",
            "--artifact-dir",
            "build/out",
            "--program-adapter",
            "transfer-sol-v1",
        ])
        .unwrap();
        match cli.command {
            Commands::VerifyArtifacts {
                program_adapter, ..
            } => {
                assert_eq!(program_adapter, Some(ProgramAdapterId::TransferSolV1));
            }
        }
    }

    #[test]
    fn network_and_trust_override_surfaces_are_absent() {
        for args in [
            vec!["proof-forge-solana-client", "devnet-call"],
            vec!["proof-forge-solana-client", "deploy"],
            vec![
                "proof-forge-solana-client",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--rpc-url",
                "https://example.invalid",
            ],
            vec![
                "proof-forge-solana-client",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--keypair",
                "wallet.json",
            ],
            vec![
                "proof-forge-solana-client",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--expected-source-hash",
                "00",
            ],
            vec![
                "proof-forge-solana-client",
                "verify-artifacts",
                "--artifact-dir",
                "build/out",
                "--program-adapter",
                "unknown-v9",
            ],
        ] {
            assert!(Cli::try_parse_from(args).is_err());
        }
    }
}
