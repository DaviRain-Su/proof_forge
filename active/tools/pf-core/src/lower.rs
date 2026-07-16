//! Experimental **surface sketch** only (D-057 Seam A; **D-058**).
//!
//! **EVM scalar storage sketch** for modules whose Core walk uses pure +
//! storage ops, plus optional `contextRead` / `emit` / `assert` (e.g. Counter,
//! ValueVault, Ownable). Emits a JSON sketch of provisional slots + entrypoints
//! — not bytecode, not Yul, and **not** a product compile path.
//!
//! Product lowering remains Lean (Yul → solc). This module must not grow into a
//! Rust re-implementation of EVM/Solana/Wasm machine-IR printers without a new
//! decision superseding D-058. HostCalls, memory, and crosscall still refuse.

use crate::{walk::CoreWalkSummary, ExportPackage};
use anyhow::{bail, Context, Result};
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

/// Schema id for the experimental storage sketch document.
pub const EVM_STORAGE_SKETCH_SCHEMA: &str = "evm-storage-sketch.v0";

/// Placeholder / sketch outputs from an experimental lowerer.
#[derive(Debug, Clone)]
pub struct LoweredArtifacts {
    pub target_id: String,
    pub notes: Vec<String>,
    /// Relative or absolute path to sketch JSON when produced.
    pub sketch_path: Option<String>,
    pub sketch: Option<EvmStorageSketch>,
}

/// Experimental **surface sketch** builder (name is historical).
///
/// Not a product `buildFromCore` lowerer (D-058). Implementors may only emit
/// inspect/observe sketches, never deployable bytecode or assembly.
pub trait BuildFromCore {
    fn target_id(&self) -> &str;
    fn build_from_core(&self, package: &ExportPackage) -> Result<LoweredArtifacts>;
}

/// One logical storage unit assigned a provisional EVM slot.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageSlotSketch {
    pub state_id: u64,
    pub shape: String,
    pub value_type: String,
    pub provisional_slot: u64,
}

/// Entrypoint surface for dual-run / ABI comparison.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EntrypointSketch {
    pub name: String,
    pub mutability: String,
    pub param_types: Vec<String>,
    pub ret_type: String,
    pub core_function_id: Option<u64>,
}

/// Experimental EVM storage-only lower sketch (not bytecode).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EvmStorageSketch {
    pub schema_version: u64,
    pub sketch_schema: String,
    pub module_name: String,
    pub target_id: String,
    pub content_hash: String,
    pub storage_slots: Vec<StorageSlotSketch>,
    pub entrypoints: Vec<EntrypointSketch>,
    pub walk: WalkSketch,
    pub status: String,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WalkSketch {
    pub instruction_count: usize,
    pub storage_op_count: usize,
    pub host_call_count: usize,
    pub op_kinds: Vec<String>,
}

/// Allowed instruction kinds for the scalar storage sketch pilot.
///
/// `contextRead`, `emit`, and `assert` are surface-level Core ops that do not
/// allocate storage slots or hostCalls; the sketch still only materializes
/// scalar slots + entrypoint names (no event ABI / context / assert codegen).
fn is_scalar_storage_sketch_walk(walk: &CoreWalkSummary) -> Result<(), String> {
    let allowed: BTreeSet<&str> = [
        "pure",
        "storageLoad",
        "storageStore",
        "storageContains",
        "contextRead",
        "emit",
        "assert",
    ]
    .into_iter()
    .collect();
    let mut bad = Vec::new();
    for kind in walk.op_kind_counts.keys() {
        if !allowed.contains(kind.as_str()) {
            bad.push(kind.clone());
        }
    }
    if !walk.host_calls_in_body.is_empty() {
        return Err(format!(
            "hostCalls not allowed in scalar storage sketch: {:?}",
            walk.host_calls_in_body
        ));
    }
    if walk.crosscall_count > 0 {
        return Err("crosscall not allowed in scalar storage sketch".into());
    }
    if walk.memory_op_count > 0 {
        return Err("memory ops not allowed in scalar storage sketch".into());
    }
    if !bad.is_empty() {
        return Err(format!(
            "unsupported op kinds for scalar storage sketch: {bad:?}"
        ));
    }
    // Terminators: only return for this pilot.
    for kind in walk.terminator_kind_counts.keys() {
        if kind != "return" {
            return Err(format!(
                "unsupported terminator `{kind}` in scalar storage sketch (only return)"
            ));
        }
    }
    Ok(())
}

fn shape_label(shape: &Value) -> (String, String) {
    let kind = shape
        .get("kind")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let value_type = shape
        .get("value")
        .and_then(|v| v.get("kind"))
        .and_then(Value::as_str)
        .unwrap_or("unknown")
        .to_string();
    (kind.to_string(), value_type)
}

/// Build a storage-only EVM sketch from a loaded package (no files written).
pub fn build_evm_storage_sketch(package: &ExportPackage) -> Result<EvmStorageSketch> {
    let ready = package.dual_run_readiness();
    if !ready.ready_for_dual_run_observe() {
        bail!(
            "package not dual-run observe ready:\n{}",
            ready.lines().join("\n")
        );
    }
    if package.target_id() != "evm" {
        // Sketch is EVM-shaped; Core is target-neutral but this pilot assigns EVM slots.
        // Allow any package target_id so long as Core is storage-only — still label sketch as evm.
    }

    let walk = package.walk();
    if let Err(msg) = is_scalar_storage_sketch_walk(&walk) {
        bail!("EVM scalar storage sketch refused: {msg}");
    }

    let mut slots = Vec::new();
    for (i, state) in package.core.module.state.iter().enumerate() {
        let state_id = state.get("id").and_then(Value::as_u64).unwrap_or(i as u64);
        let shape = state.get("shape").cloned().unwrap_or(Value::Null);
        let (shape_kind, value_type) = shape_label(&shape);
        if shape_kind != "scalar" {
            bail!(
                "EVM scalar storage sketch only supports scalar state (state_id={state_id} shape={shape_kind})"
            );
        }
        slots.push(StorageSlotSketch {
            state_id,
            shape: shape_kind,
            value_type,
            provisional_slot: i as u64,
        });
    }

    let mut entrypoints = Vec::new();
    if let Some(iface) = &package.interface {
        for (i, ep) in iface.entrypoints.iter().enumerate() {
            let core_function_id = package
                .core
                .module
                .functions
                .get(i)
                .map(|f| f.id);
            entrypoints.push(EntrypointSketch {
                name: ep.name.clone(),
                mutability: ep.mutability.clone(),
                param_types: ep.param_types.clone(),
                ret_type: ep.ret_type.clone(),
                core_function_id,
            });
        }
    } else {
        bail!("EVM scalar storage sketch requires interface.v0.json");
    }

    let op_kinds: Vec<String> = walk
        .op_kind_counts
        .iter()
        .map(|(k, n)| format!("{k}={n}"))
        .collect();

    let mut notes = vec![
        "provisional slots are sequential scalars only".into(),
        "not bytecode; not a product compile path".into(),
        "product CLI default remains Lean".into(),
    ];
    if walk.context_read_count > 0 || walk.emit_count > 0 || walk.assert_count > 0 {
        notes.push(format!(
            "contextRead={} emit={} assert={} counted in walk but not materialized in sketch surface",
            walk.context_read_count, walk.emit_count, walk.assert_count
        ));
    }

    Ok(EvmStorageSketch {
        schema_version: 0,
        sketch_schema: EVM_STORAGE_SKETCH_SCHEMA.to_string(),
        module_name: package.module_name().to_string(),
        target_id: "evm".to_string(),
        content_hash: package.content_hash(),
        storage_slots: slots,
        entrypoints,
        walk: WalkSketch {
            instruction_count: walk.instruction_count,
            storage_op_count: walk.storage_op_count,
            host_call_count: walk.host_calls_in_body.len(),
            op_kinds,
        },
        status: "experimental-storage-sketch".into(),
        notes,
    })
}

/// Write `evm-storage-sketch.v0.json` next to the package (or to `out_dir`).
pub fn write_evm_storage_sketch(
    package: &ExportPackage,
    out_dir: Option<&Path>,
) -> Result<LoweredArtifacts> {
    let sketch = build_evm_storage_sketch(package)?;
    let dir = out_dir.unwrap_or(package.dir.as_path());
    fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    let path = dir.join("evm-storage-sketch.v0.json");
    let json = serde_json::to_string_pretty(&sketch)? + "\n";
    fs::write(&path, json).with_context(|| format!("write {}", path.display()))?;
    Ok(LoweredArtifacts {
        target_id: "evm".into(),
        notes: sketch.notes.clone(),
        sketch_path: Some(path.display().to_string()),
        sketch: Some(sketch),
    })
}

/// EVM **storage surface sketch** pilot (not a product lowerer; D-058).
#[derive(Debug, Default, Clone, Copy)]
pub struct EvmStorageSketchPilot;

/// Historical alias — prefer [`EvmStorageSketchPilot`].
pub type EvmLowererPilot = EvmStorageSketchPilot;

impl BuildFromCore for EvmStorageSketchPilot {
    fn target_id(&self) -> &str {
        "evm"
    }

    fn build_from_core(&self, package: &ExportPackage) -> Result<LoweredArtifacts> {
        // Prefer writing beside the loaded package for pilot workflows.
        write_evm_storage_sketch(package, None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    #[test]
    fn counter_storage_sketch_ok() {
        let pkg = crate::ExportPackage::load(fixture("counter-evm")).unwrap();
        let sketch = build_evm_storage_sketch(&pkg).expect("counter sketch");
        assert_eq!(sketch.module_name, "Counter");
        assert_eq!(sketch.storage_slots.len(), 1);
        assert_eq!(sketch.storage_slots[0].provisional_slot, 0);
        assert_eq!(sketch.storage_slots[0].value_type, "u64");
        assert_eq!(sketch.entrypoints.len(), 3);
        assert!(sketch.entrypoints.iter().any(|e| e.name == "increment"));
        assert_eq!(sketch.walk.host_call_count, 0);
        assert_eq!(sketch.sketch_schema, EVM_STORAGE_SKETCH_SCHEMA);
    }

    #[test]
    fn create_module_refused_by_storage_pilot() {
        let pkg = crate::ExportPackage::load(fixture("create-evm")).unwrap();
        let err = build_evm_storage_sketch(&pkg).unwrap_err().to_string();
        assert!(
            err.contains("hostCalls") || err.contains("refused"),
            "{err}"
        );
    }

    #[test]
    fn build_from_core_writes_sketch_file() {
        let pkg = crate::ExportPackage::load(fixture("counter-evm")).unwrap();
        let out = std::env::temp_dir().join(format!(
            "pf-core-sketch-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&out);
        let arts = write_evm_storage_sketch(&pkg, Some(&out)).unwrap();
        let path = arts.sketch_path.unwrap();
        assert!(Path::new(&path).exists());
        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains("evm-storage-sketch.v0"));
        assert!(text.contains("Counter"));
        let _ = fs::remove_dir_all(&out);
    }
}
