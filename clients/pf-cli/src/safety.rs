//! Network and key safety gates (SPEC-CLI-DEV-001 §3.2).

use crate::error::{PfError, PfResult};

/// Well-known Leo local-dev private key from official Leo help text.
/// Must never be used with --broadcast.
pub const LEO_WELL_KNOWN_DEV_KEY: &str =
    "APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkKind {
    Devnet,
    Testnet,
    Mainnet,
}

impl NetworkKind {
    pub fn parse(s: &str) -> PfResult<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "devnet" => Ok(Self::Devnet),
            "testnet" => Ok(Self::Testnet),
            "mainnet" => Ok(Self::Mainnet),
            other => Err(PfError::Usage(format!(
                "unknown network '{other}' (want testnet|devnet; mainnet refused in v0)"
            ))),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Devnet => "devnet",
            Self::Testnet => "testnet",
            Self::Mainnet => "mainnet",
        }
    }

    pub fn default_endpoint(self) -> &'static str {
        match self {
            Self::Devnet => "http://localhost:3030",
            Self::Testnet => "https://api.explorer.provable.com/v1",
            Self::Mainnet => "https://api.explorer.provable.com/v1",
        }
    }
}

/// Refuse mainnet in v0.
pub fn refuse_mainnet(net: NetworkKind) -> PfResult<()> {
    if net == NetworkKind::Mainnet {
        return Err(PfError::Safety(
            "mainnet is refused by pf v0 (product scope: devnet/testnet only)".into(),
        ));
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
