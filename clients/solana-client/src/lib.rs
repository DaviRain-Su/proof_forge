//! ProofForge generic Solana offline engineering artifact verifier.
//!
//! Layers:
//! - `output_set`: generic `proof-forge.output.v1` Solana OutputSet self-consistency
//! - `profile`: closed current profile dispatch (plan / elf / cpi-elf)
//! - `program_adapter`: optional fixture pins (TransferSol only when selected)
//!
//! This crate has no RPC, deployment, faucet, wallet, signing, or network-write surface.
//! Local executable behavior for product fixtures is exercised by `runtime-tests/solana`
//! under Mollusk.

pub mod artifact;
pub mod cli;
pub mod constants;
pub mod error;
pub mod output;
pub mod output_set;
pub mod profile;
pub mod program_adapter;
pub mod util;

pub use artifact::{
    verify_solana_artifact, verify_solana_artifact_with_adapter, verify_transfer_sol_artifact,
    verify_transfer_sol_artifact_with_source_hash, VerifiedArtifact, CANONICAL_LEAVES,
};
pub use cli::{Cli, Commands};
pub use constants::*;
pub use error::ClientError;
pub use output::{print_verify_json, run_verify_artifacts};
pub use program_adapter::ProgramAdapterId;
pub use util::sha256_hex;
