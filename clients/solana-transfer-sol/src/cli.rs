//! CLI parsing. Rejects keypair/wallet/secret flags. No sourceHash override on product surface.

use std::path::PathBuf;

use clap::{Parser, Subcommand};

use crate::constants::{
    DEFAULT_DEVNET_RPC_URL, DEFAULT_RPC_TIMEOUT_SECS, DEFAULT_TRANSFER_LAMPORTS,
    MAX_AIRDROP_LAMPORTS,
};
use crate::error::ClientError;

/// Default wall-clock deadline for confirmation / getTransaction poll (seconds).
pub const DEFAULT_WALL_DEADLINE_SECS: u64 = 120;

#[derive(Debug, Parser)]
#[command(
    name = "solana-transfer-sol",
    about = "Verify ProofForge TransferSol OutputSet and opt-in Solana Devnet transfer call",
    long_about = "Engineering client only. No formal/hermetic/mainnet/deployment claims.\n\
ProofForge does not deploy programs; operators own deployment and --program-id.\n\
Network writes require the explicit `devnet-call` subcommand.\n\
sourceHash trust anchor is the frozen Examples/TransferSol.lean product pin (not overridable)."
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

    /// Explicit opt-in Devnet call: bind deployed program, airdrop ephemeral payer, send once, receipt.
    DevnetCall {
        /// Path to the product OutputSet directory.
        #[arg(long)]
        artifact_dir: PathBuf,

        /// Public base58 program id of the operator-deployed TransferSol binary.
        #[arg(long)]
        program_id: String,

        /// Devnet (or compatible) RPC URL. Genesis hash is still strictly checked against Devnet.
        /// Tokens in path/query are never printed (endpoint redaction).
        #[arg(long, default_value = DEFAULT_DEVNET_RPC_URL)]
        rpc_url: String,

        /// Transfer amount in lamports (outer ix data + System CPI).
        #[arg(long, default_value_t = DEFAULT_TRANSFER_LAMPORTS)]
        lamports: u64,

        /// HTTP / RPC timeout seconds (1..=300).
        #[arg(long, default_value_t = DEFAULT_RPC_TIMEOUT_SECS)]
        timeout_secs: u64,

        /// Wall-clock confirmation deadline seconds (1..=300, default 120).
        #[arg(long, default_value_t = DEFAULT_WALL_DEADLINE_SECS)]
        wall_deadline_secs: u64,
    },
}

/// Reject argv secret/keypair flags before clap (defense in depth).
pub fn reject_secret_argv(args: &[String]) -> Result<(), ClientError> {
    for a in args {
        if let Some(flag_name) = forbidden_secret_flag_name(a) {
            // Never echo the value-bearing argv token: it may itself be a secret.
            return Err(ClientError::ForbiddenSecret(format!(
                "{flag_name}: client generates process-local ephemeral keys only; \
                 no keypair/wallet/secret files or env secret material"
            )));
        }
        // Reject any attempt to override sourceHash on the product surface.
        if a == "--expected-source-hash" || a.starts_with("--expected-source-hash=") {
            return Err(ClientError::ForbiddenSecret(
                "--expected-source-hash is not accepted: product surface uses frozen TransferSol sourceHash pin only".into(),
            ));
        }
    }
    Ok(())
}

fn forbidden_secret_flag_name(flag: &str) -> Option<&str> {
    let name = flag.split_once('=').map_or(flag, |(name, _)| name);
    if matches!(
        name,
        "--keypair"
            | "--keypair-path"
            | "--keyfile"
            | "--wallet"
            | "--wallet-path"
            | "--secret"
            | "--secret-key"
            | "--private-key"
            | "--payer-keypair"
            | "--signer"
            | "--signer-path"
            | "-k"
    ) {
        Some(name)
    } else {
        None
    }
}

pub fn is_forbidden_secret_flag(flag: &str) -> bool {
    forbidden_secret_flag_name(flag).is_some()
}

pub fn validate_devnet_bounds(
    lamports: u64,
    timeout_secs: u64,
    wall_deadline_secs: u64,
) -> Result<(), ClientError> {
    if lamports == 0 {
        return Err(ClientError::DevnetConfig("--lamports must be > 0".into()));
    }
    if lamports >= MAX_AIRDROP_LAMPORTS {
        return Err(ClientError::DevnetConfig(format!(
            "--lamports {lamports} must be < airdrop ceiling {MAX_AIRDROP_LAMPORTS} so ephemeral payer can be funded"
        )));
    }
    if timeout_secs == 0 || timeout_secs > 300 {
        return Err(ClientError::DevnetConfig(
            "--timeout-secs must be in 1..=300".into(),
        ));
    }
    if wall_deadline_secs == 0 || wall_deadline_secs > 300 {
        return Err(ClientError::DevnetConfig(
            "--wall-deadline-secs must be in 1..=300".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_secret_flags_without_echoing_values() {
        let forbidden = [
            "--keypair",
            "--keypair-path=/tmp/never-echo-keypair.json",
            "--keyfile=never-echo-keyfile",
            "--wallet=/tmp/never-echo-wallet.json",
            "--wallet-path=/tmp/never-echo-wallet-path.json",
            "--secret=never-echo-secret",
            "--secret-key=never-echo-secret-key",
            "--private-key=never-echo-private-key",
            "--payer-keypair=/tmp/never-echo-payer.json",
            "--signer=never-echo-signer",
            "--signer-path=/tmp/never-echo-signer.json",
            "-k=never-echo-short-key",
        ];
        for f in forbidden {
            let err = reject_secret_argv(&[f.into()]).expect_err("secret flag must reject");
            let rendered = err.to_string();
            assert!(is_forbidden_secret_flag(f), "should classify {f}");
            assert!(!rendered.contains("never-echo"), "leaked value for {f}");
        }
        for f in ["--expected-source-hash", "--expected-source-hash=aa"] {
            assert!(
                reject_secret_argv(&[f.into()]).is_err(),
                "should reject {f}"
            );
        }
    }

    #[test]
    fn devnet_bounds() {
        assert!(validate_devnet_bounds(1000, 30, 120).is_ok());
        assert!(validate_devnet_bounds(0, 30, 120).is_err());
        assert!(validate_devnet_bounds(1000, 0, 120).is_err());
        assert!(validate_devnet_bounds(1000, 30, 0).is_err());
        assert!(validate_devnet_bounds(1000, 30, 301).is_err());
    }
}
