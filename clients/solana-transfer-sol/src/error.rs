//! Structured errors for the offline TransferSol artifact verifier.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("artifact: {0}")]
    Artifact(String),

    #[error("abi join: {0}")]
    AbiJoin(String),

    #[error("io: {0}")]
    Io(String),

    #[error("internal: {0}")]
    Internal(String),
}

impl ClientError {
    pub fn exit_code(&self) -> i32 {
        match self {
            Self::Artifact(_) | Self::AbiJoin(_) => 3,
            Self::Io(_) | Self::Internal(_) => 1,
        }
    }
}

impl From<std::io::Error> for ClientError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error.to_string())
    }
}
