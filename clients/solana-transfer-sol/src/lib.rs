//! ProofForge TransferSol offline engineering artifact verifier.
//!
//! This crate has no RPC, deployment, faucet, wallet, signing, or network-write surface.
//! Local executable behavior is exercised by `runtime-tests/solana` under Mollusk.

pub mod artifact;
pub mod cli;
pub mod constants;
pub mod error;
pub mod output;
pub mod util;

pub use artifact::{
    verify_transfer_sol_artifact, verify_transfer_sol_artifact_with_source_hash, VerifiedArtifact,
};
pub use cli::{Cli, Commands};
pub use constants::*;
pub use error::ClientError;
pub use output::{print_verify_json, run_verify_artifacts};
pub use util::sha256_hex;
