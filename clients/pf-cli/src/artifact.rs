//! Read engineering OutputSet directories for developer workflows.

use crate::error::{PfError, PfResult};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct AleoArtifact {
    pub dir: PathBuf,
    pub aleo_path: PathBuf,
    pub program_id: String,   // e.g. statecell.aleo
    pub program_stem: String, // e.g. statecell
    pub content: String,
    pub sha256_hex: String,
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    hex::encode(h.finalize())
}

pub fn load_aleo_artifact(dir: &Path) -> PfResult<AleoArtifact> {
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir is not a directory: {}",
            dir.display()
        )));
    }
    let manifest = dir.join("manifest.json");
    if !manifest.is_file() {
        return Err(PfError::Artifact(format!(
            "missing manifest.json under {}",
            dir.display()
        )));
    }
    let man_txt = fs::read_to_string(&manifest)?;
    let man: Value = serde_json::from_str(&man_txt)
        .map_err(|e| PfError::Artifact(format!("manifest.json is not JSON: {e}")))?;
    // Best-effort schema check; do not require every field.
    if let Some(sv) = man.get("schemaVersion").and_then(|v| v.as_str()) {
        if sv != "proof-forge.output.v1" && !sv.contains("proof-forge") {
            // still allow if files look right
        }
    }

    let mut aleo_files: Vec<PathBuf> = Vec::new();
    for ent in fs::read_dir(dir)? {
        let ent = ent?;
        let p = ent.path();
        if !p.is_file() {
            continue;
        }
        let name = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
        if name.ends_with(".aleo") && !name.contains("query-contract") {
            aleo_files.push(p);
        }
    }
    if aleo_files.is_empty() {
        return Err(PfError::Artifact(format!(
            "no primary *.aleo under {}",
            dir.display()
        )));
    }
    if aleo_files.len() != 1 {
        return Err(PfError::Artifact(format!(
            "expected exactly one primary *.aleo under {}, found {}",
            dir.display(),
            aleo_files.len()
        )));
    }
    let aleo_path = aleo_files.remove(0);
    let content = fs::read_to_string(&aleo_path)?;
    let sha256_hex = sha256_hex(content.as_bytes());
    let (program_id, program_stem) = parse_program_header(&content)?;
    Ok(AleoArtifact {
        dir: dir.to_path_buf(),
        aleo_path,
        program_id,
        program_stem,
        content,
        sha256_hex,
    })
}

/// Parse `program foo.aleo;` header.
pub fn parse_program_header(content: &str) -> PfResult<(String, String)> {
    for line in content.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("program ") {
            let id = rest.trim().trim_end_matches(';').trim();
            if !id.ends_with(".aleo") {
                return Err(PfError::Artifact(format!(
                    "program header id must end with .aleo, got '{id}'"
                )));
            }
            let stem = id.trim_end_matches(".aleo").to_string();
            if stem.is_empty() {
                return Err(PfError::Artifact("empty program stem".into()));
            }
            return Ok((id.to_string(), stem));
        }
    }
    Err(PfError::Artifact(
        "missing 'program <id>.aleo;' header in .aleo file".into(),
    ))
}

/// Rewrite `program old.aleo` / `old.aleo/` references to a new program id.
pub fn rewrite_program_id(content: &str, old_stem: &str, new_stem: &str) -> String {
    let old_id = format!("{old_stem}.aleo");
    let new_id = format!("{new_stem}.aleo");
    content.replace(&old_id, &new_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_header() {
        let c = "program statecell.aleo;\n\nmapping x:\n";
        let (id, stem) = parse_program_header(c).unwrap();
        assert_eq!(id, "statecell.aleo");
        assert_eq!(stem, "statecell");
    }

    #[test]
    fn rewrite_id() {
        let c = "program statecell.aleo;\noutput r1 as statecell.aleo/initialize.future;\n";
        let r = rewrite_program_id(c, "statecell", "pfsc1");
        assert!(r.contains("program pfsc1.aleo;"));
        assert!(r.contains("pfsc1.aleo/initialize.future"));
        assert!(!r.contains("statecell.aleo"));
    }
}
