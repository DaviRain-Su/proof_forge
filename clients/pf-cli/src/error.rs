//! Error types and process exit mapping for `pf`.

use std::process::ExitCode;
use thiserror::Error;

/// Developer-CLI failures. Exit 2 = usage/config/safety; exit 1 = operational failure.
#[derive(Debug, Error)]
pub enum PfError {
    #[error("{0}")]
    Usage(String),

    #[error("{0}")]
    Safety(String),

    #[error("{0}")]
    Artifact(String),

    #[error("{0}")]
    Compiler(String),

    #[error("{0}")]
    Tool(String),

    #[error("{0}")]
    Io(String),

    #[error("{0}")]
    Network(String),

    #[error("not implemented: {0}")]
    NotImplemented(String),
}

impl PfError {
    pub fn exit_code(&self) -> ExitCode {
        match self {
            PfError::Usage(_) | PfError::Safety(_) => ExitCode::from(2),
            _ => ExitCode::from(1),
        }
    }

    pub fn code_str(&self) -> &'static str {
        match self {
            PfError::Usage(_) => "PF-DEV-USAGE",
            PfError::Safety(_) => "PF-DEV-SAFETY",
            PfError::Artifact(_) => "PF-DEV-ARTIFACT",
            PfError::Compiler(_) => "PF-DEV-COMPILER",
            PfError::Tool(_) => "PF-DEV-TOOL",
            PfError::Io(_) => "PF-DEV-IO",
            PfError::Network(_) => "PF-DEV-NETWORK",
            PfError::NotImplemented(_) => "PF-DEV-NOT-IMPLEMENTED",
        }
    }
}

impl From<std::io::Error> for PfError {
    fn from(e: std::io::Error) -> Self {
        PfError::Io(e.to_string())
    }
}

pub type PfResult<T> = Result<T, PfError>;
