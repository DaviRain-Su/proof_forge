//! Network and key safety gates (SPEC-CLI-DEV-001 §3.2).

use crate::error::{PfError, PfResult};

/// Well-known Leo local-dev private key from official Leo help text.
/// Must never be used with --broadcast.
pub const LEO_WELL_KNOWN_DEV_KEY: &str =
    "APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkKind {
    /// Local node only (Anvil / local validator / Surfpool). Default for EVM/Solana deploy.
    Local,
    Devnet,
    Testnet,
    Mainnet,
}

impl NetworkKind {
    pub fn parse(s: &str) -> PfResult<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "local" | "localhost" | "anvil" | "surfpool" => Ok(Self::Local),
            "devnet" => Ok(Self::Devnet),
            "testnet" => Ok(Self::Testnet),
            "mainnet" => Ok(Self::Mainnet),
            other => Err(PfError::Usage(format!(
                "unknown network '{other}' (want local|testnet|devnet; mainnet refused in v0)"
            ))),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Local => "local",
            Self::Devnet => "devnet",
            Self::Testnet => "testnet",
            Self::Mainnet => "mainnet",
        }
    }

    pub fn default_endpoint(self) -> &'static str {
        match self {
            Self::Local => "http://127.0.0.1:8545",
            Self::Devnet => "http://localhost:3030",
            Self::Testnet => "https://api.explorer.provable.com/v1",
            Self::Mainnet => "https://api.explorer.provable.com/v1",
        }
    }

    pub fn is_local(self) -> bool {
        self == Self::Local
    }
}

/// Refuse mainnet in v0.
pub fn refuse_mainnet(net: NetworkKind) -> PfResult<()> {
    if net == NetworkKind::Mainnet {
        return Err(PfError::Safety(
            "mainnet is refused by pf v0 (product scope: local/devnet/testnet only)".into(),
        ));
    }
    Ok(())
}

/// EVM/Solana broadcast is local-node only in v0 (no public RPC write).
pub fn refuse_public_chain_broadcast(net: NetworkKind, chain: &str) -> PfResult<()> {
    refuse_mainnet(net)?;
    if !net.is_local() {
        return Err(PfError::Safety(format!(
            "{chain}: --broadcast only allowed with --network local in pf v0 \
             (no public Devnet/Testnet/Mainnet write; use save-only package or local Anvil/validator)"
        )));
    }
    Ok(())
}

/// Endpoint must be loopback for local broadcast.
pub fn require_loopback_endpoint(endpoint: &str) -> PfResult<()> {
    let e = endpoint.trim().to_ascii_lowercase();
    let ok = e.contains("127.0.0.1")
        || e.contains("localhost")
        || e.contains("[::1]")
        || e.contains("0.0.0.0"); // anvil bind; still local process
    if !ok {
        return Err(PfError::Safety(format!(
            "local broadcast endpoint must be loopback (got '{endpoint}')"
        )));
    }
    // Refuse obvious public hosts even if someone passes weird local names.
    for bad in [
        "mainnet",
        "sepolia",
        "goerli",
        "holesky",
        "alchemy.com",
        "infura.io",
        "publicnode.com",
        "ankr.com",
        "api.mainnet",
        "api.devnet.solana",
        "api.testnet.solana",
        "explorer.provable.com",
    ] {
        if e.contains(bad) {
            return Err(PfError::Safety(format!(
                "refusing non-local endpoint marker '{bad}' in '{endpoint}'"
            )));
        }
    }
    Ok(())
}

/// Validate broadcast + key policy. Returns the private key string when broadcast
/// is requested and validation passes; `None` when save-only (may still use
/// well-known key for fee estimation materialization).
pub fn resolve_private_key_for_mode(
    broadcast: bool,
    private_key_env: Option<&str>,
) -> PfResult<String> {
    if !broadcast {
        // Save-only: allow well-known key for leo deploy/execute materialization.
        if let Some(name) = private_key_env {
            let v = std::env::var(name)
                .map_err(|_| PfError::Usage(format!("environment variable '{name}' is not set")))?;
            if v.trim().is_empty() {
                return Err(PfError::Usage(format!(
                    "environment variable '{name}' is empty"
                )));
            }
            return Ok(v);
        }
        return Ok(LEO_WELL_KNOWN_DEV_KEY.to_string());
    }

    let name = private_key_env.ok_or_else(|| {
        PfError::Safety(
            "--broadcast requires --private-key-env <NAME> (no default key file scan)".into(),
        )
    })?;
    let v = std::env::var(name).map_err(|_| {
        PfError::Safety(format!(
            "--broadcast: environment variable '{name}' is not set"
        ))
    })?;
    let v = v.trim().to_string();
    if v.is_empty() {
        return Err(PfError::Safety(format!(
            "--broadcast: environment variable '{name}' is empty"
        )));
    }
    if v == LEO_WELL_KNOWN_DEV_KEY {
        return Err(PfError::Safety(
            "--broadcast refuses the well-known Leo local-dev private key".into(),
        ));
    }
    Ok(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mainnet_refused() {
        assert!(refuse_mainnet(NetworkKind::Mainnet).is_err());
        assert!(refuse_mainnet(NetworkKind::Testnet).is_ok());
        assert!(refuse_mainnet(NetworkKind::Local).is_ok());
    }

    #[test]
    fn public_broadcast_refused_for_evm_solana() {
        assert!(refuse_public_chain_broadcast(NetworkKind::Testnet, "evm").is_err());
        assert!(refuse_public_chain_broadcast(NetworkKind::Local, "solana").is_ok());
    }

    #[test]
    fn loopback_endpoint_gate() {
        assert!(require_loopback_endpoint("http://127.0.0.1:8545").is_ok());
        assert!(require_loopback_endpoint("http://localhost:8899").is_ok());
        assert!(require_loopback_endpoint("https://eth.llamarpc.com").is_err());
    }

    #[test]
    fn broadcast_requires_env() {
        let err = resolve_private_key_for_mode(true, None).unwrap_err();
        assert!(matches!(err, PfError::Safety(_)));
    }

    #[test]
    fn save_only_allows_well_known() {
        let k = resolve_private_key_for_mode(false, None).unwrap();
        assert_eq!(k, LEO_WELL_KNOWN_DEV_KEY);
    }

    #[test]
    fn broadcast_refuses_well_known() {
        std::env::set_var("PF_TEST_DEV_KEY", LEO_WELL_KNOWN_DEV_KEY);
        let err = resolve_private_key_for_mode(true, Some("PF_TEST_DEV_KEY")).unwrap_err();
        assert!(matches!(err, PfError::Safety(_)));
        std::env::remove_var("PF_TEST_DEV_KEY");
    }
}
