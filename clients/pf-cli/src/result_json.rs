//! Structured JSON results (`proof-forge.pf.result.v1`).

use crate::error::PfError;
use serde::Serialize;
use serde_json::{json, Value};

pub const SCHEMA: &str = "proof-forge.pf.result.v1";

#[derive(Debug, Serialize)]
pub struct PfOk {
    pub schema: &'static str,
    pub command: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub network: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub broadcast: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifact_dir: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub saved: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub extra: Option<Value>,
}

impl PfOk {
    pub fn new(command: impl Into<String>) -> Self {
        Self {
            schema: SCHEMA,
            command: command.into(),
            ok: true,
            target: None,
            network: None,
            broadcast: None,
            artifact_dir: None,
            saved: None,
            notes: Some(vec![
                "deployable not rewritten".into(),
                "not formal/hermetic/mainnet".into(),
            ]),
            extra: None,
        }
    }
}

pub fn print_ok(v: &PfOk) {
    println!("{}", serde_json::to_string_pretty(v).expect("serialize ok"));
}

pub fn print_err(command: &str, err: &PfError) {
    let v = json!({
        "schema": SCHEMA,
        "command": command,
        "ok": false,
        "error": {
            "code": err.code_str(),
            "message": err.to_string(),
        }
    });
    println!(
        "{}",
        serde_json::to_string_pretty(&v).expect("serialize err")
    );
}
