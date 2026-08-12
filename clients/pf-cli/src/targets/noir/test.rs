//! Lightweight artifact smoke for Noir builds.
//!
//! Accepts either source-relations layout (`*.noir-relations.json` + `relations/`)
//! or ACIR extras when present. Does **not** invoke nargo (host-heavy; doctor
//! checklist covers nargo separately).

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
            "noir artifact dir missing: {}",
            artifact_dir.display()
        )));
    }
    let manifest = artifact_dir.join("manifest.json");
    if !manifest.is_file() {
        return Err(PfError::Artifact(format!(
            "noir: missing manifest.json under {}",
            artifact_dir.display()
        )));
    }

    let mut evidence = vec![format!("manifest={}", manifest.display())];
    let relations = find_first_with_suffix(artifact_dir, ".noir-relations.json")?;
    if let Some(p) = relations {
        evidence.push(format!("relationsJson={}", p.display()));
        let rel_dir = artifact_dir.join("relations");
        if rel_dir.is_dir() {
            evidence.push(format!("relationsDir={}", rel_dir.display()));
        }
        // Prefer at least one main.nr under relations/
        if let Some(nr) = find_named_under(artifact_dir, "main.nr") {
            evidence.push(format!("mainNr={}", nr.display()));
        }
        return Ok(TestOutcome {
            skipped: false,
            skip_reason: None,
            summary: "noir source-relations artifact smoke ok".into(),
            evidence,
        });
    }

    // ACIR package path: look for ProgramArtifact-ish JSON extras
    if let Some(acir) = find_acir_json(artifact_dir)? {
        evidence.push(format!("acirJson={}", acir.display()));
        return Ok(TestOutcome {
            skipped: false,
            skip_reason: None,
            summary: "noir ACIR artifact smoke ok (no nargo re-run)".into(),
            evidence,
        });
    }

    Err(PfError::Artifact(format!(
        "noir: no *.noir-relations.json or ACIR program JSON under {}",
        artifact_dir.display()
    )))
}

fn find_first_with_suffix(dir: &Path, suffix: &str) -> PfResult<Option<PathBuf>> {
    let mut found = None;
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let p = ent.path();
        if p.is_file() {
            if let Some(name) = p.file_name().and_then(|s| s.to_str()) {
                if name.ends_with(suffix) {
                    found = Some(p);
                    break;
                }
            }
        }
    }
    Ok(found)
}

fn find_named_under(root: &Path, name: &str) -> Option<PathBuf> {
    fn walk(dir: &Path, name: &str, depth: usize) -> Option<PathBuf> {
        if depth > 6 {
            return None;
        }
        let rd = fs::read_dir(dir).ok()?;
        for ent in rd.flatten() {
            let p = ent.path();
            if p.is_file() && p.file_name().and_then(|s| s.to_str()) == Some(name) {
                return Some(p);
            }
            if p.is_dir() {
                if let Some(hit) = walk(&p, name, depth + 1) {
                    return Some(hit);
                }
            }
        }
        None
    }
    walk(root, name, 0)
}

fn find_acir_json(dir: &Path) -> PfResult<Option<PathBuf>> {
    // Shallow + one-level: *.json that is not manifest / relations.
    let mut cands = Vec::new();
    collect_json(dir, 0, &mut cands)?;
    for p in cands {
        let name = p
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        if name == "manifest.json" || name.ends_with(".noir-relations.json") {
            continue;
        }
        if let Ok(txt) = fs::read_to_string(&p) {
            if txt.contains("\"noir_version\"")
                || txt.contains("\"bytecode\"")
                || txt.contains("\"abi\"")
            {
                return Ok(Some(p));
            }
        }
    }
    Ok(None)
}

fn collect_json(dir: &Path, depth: usize, out: &mut Vec<PathBuf>) -> PfResult<()> {
    if depth > 3 {
        return Ok(());
    }
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let p = ent.path();
        if p.is_file() {
            if p.extension().and_then(|s| s.to_str()) == Some("json") {
                out.push(p);
            }
        } else if p.is_dir() {
            collect_json(&p, depth + 1, out)?;
        }
    }
    Ok(())
}
