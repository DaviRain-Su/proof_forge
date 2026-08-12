//! Lightweight artifact smoke for Quint builds.
//!
//! Source-only `.qnt` + manifest. Does **not** invoke Quint CLI / Apalache / TLC
//! (ADR-0026 zero-tool finalize).

use crate::error::{PfError, PfResult};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct TestOutcome {
    pub skipped: bool,
    pub skip_reason: Option<String>,
    pub summary: String,
    pub evidence: Vec<String>,
}

pub fn run_artifact_smoke(artifact_dir: &Path) -> PfResult<TestOutcome> {
    if !artifact_dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "quint artifact dir missing: {}",
            artifact_dir.display()
        )));
    }
    let manifest = artifact_dir.join("manifest.json");
    if !manifest.is_file() {
        return Err(PfError::Artifact(format!(
            "quint: missing manifest.json under {}",
            artifact_dir.display()
        )));
    }
    let qnt = find_first_qnt(artifact_dir)?;
    let Some(qnt) = qnt else {
        return Err(PfError::Artifact(format!(
            "quint: no *.qnt under {}",
            artifact_dir.display()
        )));
    };
    let txt = fs::read_to_string(&qnt)?;
    if !txt.contains("module ") {
        return Err(PfError::Artifact(format!(
            "quint: {} does not look like a Quint module (missing 'module ')",
            qnt.display()
        )));
    }
    Ok(TestOutcome {
        skipped: false,
        skip_reason: None,
        summary: "quint source-only artifact smoke ok (no Quint CLI)".into(),
        evidence: vec![
            format!("manifest={}", manifest.display()),
            format!("qnt={}", qnt.display()),
            format!("bytes={}", txt.len()),
        ],
    })
}

fn find_first_qnt(dir: &Path) -> PfResult<Option<PathBuf>> {
    let mut found = None;
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let p = ent.path();
        if p.is_file() && p.extension().and_then(|s| s.to_str()) == Some("qnt") {
            found = Some(p);
            break;
        }
    }
    Ok(found)
}
