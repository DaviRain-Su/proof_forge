//! Observe dual-run: compare Lean EVM plan dump with Rust storage sketch.
//!
//! This is **not** bytecode dual-run. It checks declared surface dimensions:
//! entrypoint names and scalar storage slot assignment order.

use crate::{build_evm_storage_sketch, ExportPackage};
use anyhow::{bail, Context, Result};
use serde::Deserialize;
use std::fs;
use std::path::Path;

pub const LEAN_EVM_OBSERVE_SCHEMA: &str = "lean-evm-observe.v0";

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LeanEvmObserve {
    pub schema_version: crate::SchemaVersion,
    pub observe_schema: String,
    pub module_name: String,
    pub target_id: String,
    #[serde(default)]
    pub storage: Vec<LeanStorageObserve>,
    #[serde(default)]
    pub entrypoints: Vec<LeanEntrypointObserve>,
    #[serde(default)]
    pub interface_entrypoint_names: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LeanStorageObserve {
    pub name: String,
    pub slot: u64,
    #[serde(default)]
    pub span: Option<u64>,
    #[serde(default)]
    pub kind: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LeanEntrypointObserve {
    pub name: String,
    pub mutability: String,
    #[serde(default)]
    pub selector: Option<String>,
    #[serde(default)]
    pub param_count: Option<u64>,
}

#[derive(Debug, Clone)]
pub struct ObserveCompareReport {
    pub module_name: String,
    pub entrypoints_match: bool,
    pub storage_slots_match: bool,
    pub notes: Vec<String>,
}

impl ObserveCompareReport {
    pub fn ok(&self) -> bool {
        self.entrypoints_match && self.storage_slots_match
    }

    pub fn lines(&self) -> Vec<String> {
        let mut lines = vec![
            format!("observeDualRun: module={}", self.module_name),
            format!(
                "observeDualRun: entrypoints={} storageSlots={}",
                yn(self.entrypoints_match),
                yn(self.storage_slots_match)
            ),
            format!("observeDualRun: ok={}", yn(self.ok())),
        ];
        for n in &self.notes {
            lines.push(format!("observeDualRun: note: {n}"));
        }
        lines
    }
}

fn yn(b: bool) -> &'static str {
    if b {
        "yes"
    } else {
        "no"
    }
}

pub fn load_lean_observe(path: impl AsRef<Path>) -> Result<LeanEvmObserve> {
    let path = path.as_ref();
    let text = fs::read_to_string(path).with_context(|| format!("read `{}`", path.display()))?;
    let doc: LeanEvmObserve = serde_json::from_str(&text)
        .with_context(|| format!("parse lean observe `{}`", path.display()))?;
    if doc.observe_schema != LEAN_EVM_OBSERVE_SCHEMA {
        bail!(
            "unexpected observeSchema `{}` (want {LEAN_EVM_OBSERVE_SCHEMA})",
            doc.observe_schema
        );
    }
    Ok(doc)
}

/// Compare Rust storage sketch (from package) with Lean `buildFromCore` observe dump.
pub fn compare_sketch_to_lean_observe(
    package: &ExportPackage,
    lean: &LeanEvmObserve,
) -> Result<ObserveCompareReport> {
    let sketch = build_evm_storage_sketch(package)?;
    let mut notes = Vec::new();

    if sketch.module_name != lean.module_name {
        notes.push(format!(
            "module name sketch={} lean={}",
            sketch.module_name, lean.module_name
        ));
    }

    let sketch_eps: Vec<_> = sketch.entrypoints.iter().map(|e| e.name.as_str()).collect();
    let lean_eps: Vec<_> = lean.entrypoints.iter().map(|e| e.name.as_str()).collect();
    let entrypoints_match = sketch_eps == lean_eps;
    if !entrypoints_match {
        notes.push(format!(
            "entrypoint names sketch={:?} lean={:?}",
            sketch_eps, lean_eps
        ));
    }

    // Mutability alignment when lengths match.
    if sketch.entrypoints.len() == lean.entrypoints.len() {
        for (s, l) in sketch.entrypoints.iter().zip(lean.entrypoints.iter()) {
            if s.mutability != l.mutability {
                notes.push(format!(
                    "mutability mismatch for {}: sketch={} lean={}",
                    s.name, s.mutability, l.mutability
                ));
            }
        }
    }

    let storage_slots_match = if sketch.storage_slots.len() != lean.storage.len() {
        notes.push(format!(
            "storage count sketch={} lean={}",
            sketch.storage_slots.len(),
            lean.storage.len()
        ));
        false
    } else {
        let mut ok = true;
        for (s, l) in sketch.storage_slots.iter().zip(lean.storage.iter()) {
            if s.provisional_slot != l.slot {
                notes.push(format!(
                    "slot mismatch state/index: sketchSlot={} leanSlot={} leanName={}",
                    s.provisional_slot, l.slot, l.name
                ));
                ok = false;
            }
            if let Some(kind) = &l.kind {
                if kind == "scalar" && s.shape != "scalar" {
                    notes.push(format!(
                        "shape mismatch leanName={}: sketch={} lean={}",
                        l.name, s.shape, kind
                    ));
                    ok = false;
                }
            }
        }
        ok
    };

    Ok(ObserveCompareReport {
        module_name: sketch.module_name,
        entrypoints_match,
        storage_slots_match,
        notes,
    })
}

/// Load package + lean observe from export dir (default file names).
pub fn dual_run_observe_dir(export_dir: impl AsRef<Path>) -> Result<ObserveCompareReport> {
    let dir = export_dir.as_ref();
    let pkg = ExportPackage::load(dir)?;
    let lean_path = dir.join("lean-evm-observe.v0.json");
    let lean = load_lean_observe(&lean_path)?;
    let report = compare_sketch_to_lean_observe(&pkg, &lean)?;
    if !report.ok() {
        bail!(
            "observe dual-run failed:\n{}",
            report.lines().join("\n")
        );
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn counter_fixture_needs_lean_observe_file() {
        // Unit test only checks schema loader on a minimal hand-made observe.
        let json = r#"{
          "schemaVersion": 0,
          "observeSchema": "lean-evm-observe.v0",
          "moduleName": "Counter",
          "targetId": "evm",
          "storage": [{"name": "count", "slot": 0, "span": 1, "kind": "scalar"}],
          "entrypoints": [
            {"name": "initialize", "mutability": "call", "selector": "aa", "paramCount": 0},
            {"name": "increment", "mutability": "call", "selector": "bb", "paramCount": 0},
            {"name": "get", "mutability": "view", "selector": "cc", "paramCount": 0}
          ]
        }"#;
        let lean: LeanEvmObserve = serde_json::from_str(json).unwrap();
        let pkg = crate::ExportPackage::load(
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/counter-evm"),
        )
        .unwrap();
        let report = compare_sketch_to_lean_observe(&pkg, &lean).unwrap();
        assert!(report.entrypoints_match, "{:?}", report.notes);
        assert!(report.storage_slots_match, "{:?}", report.notes);
        assert!(report.ok());
    }
}
