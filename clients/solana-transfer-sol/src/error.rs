//! Structured errors for the TransferSol client (no secrets).

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("usage: {0}")]
    Usage(String),

    #[error("forbidden secret/keypair input: {0}")]
    ForbiddenSecret(String),

    #[error("artifact: {0}")]
    Artifact(String),

    #[error("abi join: {0}")]
    AbiJoin(String),

    #[error("loader bind: {0}")]
    LoaderBind(String),

    #[error("receipt: {0}")]
    Receipt(String),

    #[error("rpc ({endpoint}): {message}")]
    Rpc { endpoint: String, message: String },

    #[error("devnet config: {0}")]
    DevnetConfig(String),

    #[error("io: {0}")]
    Io(String),

    #[error("internal: {0}")]
    Internal(String),
}

impl ClientError {
    pub fn rpc(endpoint: impl Into<String>, message: impl Into<String>) -> Self {
        Self::Rpc {
            endpoint: endpoint.into(),
            message: message.into(),
        }
    }

    pub fn exit_code(&self) -> i32 {
        match self {
            Self::Usage(_) | Self::ForbiddenSecret(_) => 2,
            Self::Artifact(_) | Self::AbiJoin(_) => 3,
            Self::LoaderBind(_) | Self::Receipt(_) => 4,
            Self::Rpc { .. } | Self::DevnetConfig(_) => 5,
            Self::Io(_) | Self::Internal(_) => 1,
        }
    }
}

impl From<std::io::Error> for ClientError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}
