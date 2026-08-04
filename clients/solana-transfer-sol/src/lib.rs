//! ProofForge TransferSol engineering client library.
//!
//! Offline OutputSet verification + explicit opt-in Devnet call helpers.
//! Not formal, not hermetic, not a deployment tool.

pub mod artifact;
pub mod cli;
pub mod constants;
pub mod devnet;
pub mod error;
pub mod ix;
pub mod loader_v3;
pub mod receipt;
pub mod rpc;
pub mod util;

pub use artifact::{
    verify_transfer_sol_artifact, verify_transfer_sol_artifact_with_source_hash, VerifiedArtifact,
};
pub use cli::{reject_secret_argv, validate_devnet_bounds, Cli, Commands};
pub use constants::*;
pub use devnet::{
    print_receipt_json, print_verify_json, run_devnet_call, run_verify_artifacts, DevnetCallArgs,
};
pub use error::ClientError;
pub use util::sha256_hex;
