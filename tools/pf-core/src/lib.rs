//! Read-only ProofForge Core export package (`core.v0`).
//!
//! This is the Rust side of Seam A (D-057): consume checked Canonical Core
//! packages produced by `proof-forge export-core --experimental`.
//!
//! **Not** a compile backend and **not** product ABI/SDK JSON.
//! Zero chain SDK dependencies by design.

mod lower;
mod observe;
mod walk;

pub use lower::{
    build_evm_storage_sketch, write_evm_storage_sketch, BuildFromCore, EntrypointSketch,
    EvmLowererPilot, EvmStorageSketch, LoweredArtifacts, StorageSlotSketch,
    EVM_STORAGE_SKETCH_SCHEMA,
};
pub use observe::{
    compare_sketch_to_lean_observe, dual_run_observe_dir, load_lean_observe, LeanEvmObserve,
    ObserveCompareReport, LEAN_EVM_OBSERVE_SCHEMA,
};
pub use walk::{
    host_calls_match_plan, walk_module, CoreWalkSummary, DualRunReadiness,
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

/// On-disk experimental export package directory.
#[derive(Debug, Clone)]
pub struct ExportPackage {
    pub dir: PathBuf,
    pub core: CoreDocument,
    pub plan: CapabilityPlanDocument,
    pub interface: Option<InterfaceDocument>,
    pub meta: Option<ExportMeta>,
    /// Raw core.v0.json bytes (for hashing / identity compares).
    pub core_bytes: Vec<u8>,
    /// Raw capability-plan.v0.json bytes.
    pub plan_bytes: Vec<u8>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreDocument {
    pub schema_version: SchemaVersion,
    pub core_schema: String,
    pub module: CoreModuleSummary,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreModuleSummary {
    pub name: String,
    #[serde(default)]
    pub structs: Vec<Value>,
    #[serde(default)]
    pub state: Vec<Value>,
    #[serde(default)]
    pub functions: Vec<CoreFunctionSummary>,
    #[serde(default)]
    pub events: Vec<Value>,
    #[serde(default)]
    pub errors: Vec<Value>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreFunctionSummary {
    pub id: u64,
    #[serde(default)]
    pub params: Vec<Value>,
    #[serde(rename = "retType")]
    pub ret_type: Value,
    pub entry: u64,
    #[serde(default)]
    pub blocks: Vec<Value>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityPlanDocument {
    pub schema_version: SchemaVersion,
    pub capability_plan_schema: String,
    pub target_id: String,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub requirements: Vec<CapabilityRequirement>,
    #[serde(default)]
    pub host_op_handlers: Vec<HostOpHandler>,
    #[serde(default)]
    pub target_host_op_catalog: Vec<HostOpHandler>,
    #[serde(default)]
    pub profile_notes: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityRequirement {
    pub capability: String,
    pub operation: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostOpHandler {
    pub id: HostOpId,
    pub available: bool,
    pub handler: String,
    #[serde(default)]
    pub required_capabilities: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostOpId {
    pub namespace: String,
    pub name: String,
    pub version: HostOpVersion,
    #[serde(default)]
    pub render: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostOpVersion {
    pub major: u64,
    pub minor: u64,
    pub patch: u64,
}

impl HostOpId {
    pub fn render(&self) -> String {
        self.render.clone().unwrap_or_else(|| {
            format!(
                "{}/{}@{}.{}.{}",
                self.namespace, self.name, self.version.major, self.version.minor, self.version.patch
            )
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InterfaceDocument {
    pub schema_version: SchemaVersion,
    pub interface_schema: String,
    pub contract_name: String,
    #[serde(default)]
    pub entrypoints: Vec<InterfaceEntrypoint>,
    #[serde(default)]
    pub events: Vec<String>,
    #[serde(default)]
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InterfaceEntrypoint {
    pub name: String,
    pub mutability: String,
    #[serde(default)]
    pub param_types: Vec<String>,
    pub ret_type: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportMeta {
    pub schema_version: SchemaVersion,
    #[serde(default)]
    pub core_schema: Option<String>,
    #[serde(default)]
    pub target_id: Option<String>,
    #[serde(default)]
    pub module_name: Option<String>,
    #[serde(default)]
    pub content_hash: Option<String>,
}

/// Accept integer 0 or string "0" for experimental schema versions.
#[derive(Debug, Clone)]
pub struct SchemaVersion(pub u64);

impl<'de> Deserialize<'de> for SchemaVersion {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;
        match value {
            Value::Number(n) => {
                let v = n
                    .as_u64()
                    .ok_or_else(|| serde::de::Error::custom("schemaVersion number out of range"))?;
                Ok(SchemaVersion(v))
            }
            Value::String(s) => {
                let v = s
                    .parse::<u64>()
                    .map_err(|_| serde::de::Error::custom("schemaVersion string not a u64"))?;
                Ok(SchemaVersion(v))
            }
            other => Err(serde::de::Error::custom(format!(
                "schemaVersion must be 0 or \"0\", got {other}"
            ))),
        }
    }
}

impl ExportPackage {
    /// Load and validate a package directory.
    pub fn load(dir: impl AsRef<Path>) -> Result<Self> {
        let dir = dir.as_ref().to_path_buf();
        let core_path = dir.join("core.v0.json");
        let plan_path = dir.join("capability-plan.v0.json");
        let core_bytes = fs::read(&core_path)
            .with_context(|| format!("missing `{}`", core_path.display()))?;
        let plan_bytes = fs::read(&plan_path)
            .with_context(|| format!("missing `{}`", plan_path.display()))?;

        let core: CoreDocument = serde_json::from_slice(&core_bytes)
            .with_context(|| format!("parse `{}`", core_path.display()))?;
        let plan: CapabilityPlanDocument = serde_json::from_slice(&plan_bytes)
            .with_context(|| format!("parse `{}`", plan_path.display()))?;

        if core.core_schema != "core.v0" {
            bail!("unexpected coreSchema `{}`", core.core_schema);
        }
        if core.schema_version.0 != 0 {
            bail!("unexpected core schemaVersion {}", core.schema_version.0);
        }
        if plan.capability_plan_schema != "capability-plan.v0" {
            bail!(
                "unexpected capabilityPlanSchema `{}`",
                plan.capability_plan_schema
            );
        }
        if plan.schema_version.0 != 0 {
            bail!("unexpected plan schemaVersion {}", plan.schema_version.0);
        }
        if plan.target_id.trim().is_empty() {
            bail!("capability-plan targetId is empty");
        }
        if core.module.name.trim().is_empty() {
            bail!("core module.name is empty");
        }

        for (i, h) in plan.host_op_handlers.iter().enumerate() {
            validate_handler(h, &format!("hostOpHandlers[{i}]"))?;
        }
        for (i, h) in plan.target_host_op_catalog.iter().enumerate() {
            validate_handler(h, &format!("targetHostOpCatalog[{i}]"))?;
        }
        // Used handlers must be covered by the target catalog (by render id).
        let catalog_ids: std::collections::HashSet<String> = plan
            .target_host_op_catalog
            .iter()
            .map(|h| h.id.render())
            .collect();
        for h in &plan.host_op_handlers {
            let rid = h.id.render();
            if !catalog_ids.is_empty() && !catalog_ids.contains(&rid) {
                bail!(
                    "used hostOp `{}` not present in targetHostOpCatalog (fail-closed)",
                    rid
                );
            }
        }

        let interface = {
            let path = dir.join("interface.v0.json");
            if path.exists() {
                let text = fs::read_to_string(&path)?;
                let doc: InterfaceDocument = serde_json::from_str(&text)
                    .with_context(|| format!("parse `{}`", path.display()))?;
                if doc.interface_schema != "interface.v0" {
                    bail!("unexpected interfaceSchema `{}`", doc.interface_schema);
                }
                Some(doc)
            } else {
                None
            }
        };

        let meta = {
            let path = dir.join("export-meta.json");
            if path.exists() {
                let text = fs::read_to_string(&path)?;
                let meta: ExportMeta = serde_json::from_str(&text)
                    .with_context(|| format!("parse `{}`", path.display()))?;
                if let Some(declared) = meta.content_hash.as_deref() {
                    if !declared.is_empty() && declared != "unset" {
                        let actual = content_hash_bytes(&core_bytes, &plan_bytes);
                        if declared != actual {
                            bail!(
                                "export-meta contentHash mismatch: declared={declared} actual={actual}"
                            );
                        }
                    }
                }
                Some(meta)
            } else {
                None
            }
        };

        Ok(Self {
            dir,
            core,
            plan,
            interface,
            meta,
            core_bytes,
            plan_bytes,
        })
    }

    pub fn module_name(&self) -> &str {
        &self.core.module.name
    }

    pub fn target_id(&self) -> &str {
        &self.plan.target_id
    }

    pub fn function_count(&self) -> usize {
        self.core.module.functions.len()
    }

    pub fn used_host_op_count(&self) -> usize {
        self.plan.host_op_handlers.len()
    }

    pub fn content_hash(&self) -> String {
        content_hash_bytes(&self.core_bytes, &self.plan_bytes)
    }

    /// Target-neutral Core identity: same semantic program.
    pub fn core_matches(&self, other: &Self) -> bool {
        self.core_bytes == other.core_bytes
    }
}

fn validate_handler(h: &HostOpHandler, label: &str) -> Result<()> {
    if !h.available {
        bail!("{label} is not available (fail-closed)");
    }
    if h.handler.trim().is_empty() {
        bail!("{label}.handler is empty");
    }
    if h.id.namespace.trim().is_empty() || h.id.name.trim().is_empty() {
        bail!("{label}.id namespace/name empty");
    }
    Ok(())
}

pub fn content_hash_bytes(core_bytes: &[u8], plan_bytes: &[u8]) -> String {
    let mut body = Vec::with_capacity(core_bytes.len() + plan_bytes.len());
    body.extend_from_slice(core_bytes);
    body.extend_from_slice(plan_bytes);
    format!("{:x}", Sha256::digest(&body))
}

/// Compare two packages: Core must match; plans may differ by target.
pub fn compare_packages(left: &ExportPackage, right: &ExportPackage) -> Result<CompareReport> {
    let core_same = left.core_matches(right);
    let report = CompareReport {
        left_dir: left.dir.clone(),
        right_dir: right.dir.clone(),
        left_target: left.target_id().to_string(),
        right_target: right.target_id().to_string(),
        left_used_host_ops: left.used_host_op_count(),
        right_used_host_ops: right.used_host_op_count(),
        left_catalog: left.plan.target_host_op_catalog.len(),
        right_catalog: right.plan.target_host_op_catalog.len(),
        left_content_hash: left.content_hash(),
        right_content_hash: right.content_hash(),
        core_identical: core_same,
        left_module: left.module_name().to_string(),
        right_module: right.module_name().to_string(),
    };
    if !core_same {
        bail!(
            "core.v0.json differs (Core must be target-neutral for the same module)\n{}",
            report.summary()
        );
    }
    if left.module_name() != right.module_name() {
        bail!(
            "module names differ: {} vs {}",
            left.module_name(),
            right.module_name()
        );
    }
    Ok(report)
}

#[derive(Debug, Clone)]
pub struct CompareReport {
    pub left_dir: PathBuf,
    pub right_dir: PathBuf,
    pub left_target: String,
    pub right_target: String,
    pub left_used_host_ops: usize,
    pub right_used_host_ops: usize,
    pub left_catalog: usize,
    pub right_catalog: usize,
    pub left_content_hash: String,
    pub right_content_hash: String,
    pub core_identical: bool,
    pub left_module: String,
    pub right_module: String,
}

impl CompareReport {
    pub fn summary(&self) -> String {
        format!(
            "left:  {} target={} usedHostOps={} catalog={} contentHash={}\n\
             right: {} target={} usedHostOps={} catalog={} contentHash={}\n\
             core.v0.json identical: {}",
            self.left_dir.display(),
            self.left_target,
            self.left_used_host_ops,
            self.left_catalog,
            self.left_content_hash,
            self.right_dir.display(),
            self.right_target,
            self.right_used_host_ops,
            self.right_catalog,
            self.right_content_hash,
            if self.core_identical { "yes" } else { "NO" }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name)
    }

    #[test]
    fn loads_counter_package() {
        let pkg = ExportPackage::load(fixture("counter-evm")).expect("load counter");
        assert_eq!(pkg.module_name(), "Counter");
        assert_eq!(pkg.target_id(), "evm");
        assert_eq!(pkg.function_count(), 3);
        assert_eq!(pkg.used_host_op_count(), 0);
        assert!(!pkg.plan.target_host_op_catalog.is_empty());
        assert!(pkg.interface.is_some());
        assert_eq!(
            pkg.content_hash(),
            pkg.meta
                .as_ref()
                .and_then(|m| m.content_hash.clone())
                .unwrap()
        );
    }

    #[test]
    fn loads_create_package_with_handlers() {
        let pkg = ExportPackage::load(fixture("create-evm")).expect("load create");
        assert_eq!(pkg.module_name(), "EvmCreateHostOp");
        assert_eq!(pkg.used_host_op_count(), 2);
        let renders: Vec<_> = pkg
            .plan
            .host_op_handlers
            .iter()
            .map(|h| h.id.render())
            .collect();
        assert!(renders.iter().any(|r| r.contains("create")));
        // used ⊆ catalog
        let catalog: std::collections::HashSet<_> = pkg
            .plan
            .target_host_op_catalog
            .iter()
            .map(|h| h.id.render())
            .collect();
        for r in &renders {
            assert!(catalog.contains(r), "missing {r} in catalog");
        }
    }

    #[test]
    fn walk_counter_storage_ops() {
        let pkg = ExportPackage::load(fixture("counter-evm")).expect("load counter");
        let walk = pkg.walk();
        assert_eq!(walk.function_count, 3);
        assert!(walk.instruction_count > 0);
        assert!(walk.storage_op_count >= 2);
        assert!(walk.host_calls_in_body.is_empty());
        assert!(walk.op_kind_counts.contains_key("storageLoad")
            || walk.op_kind_counts.contains_key("storageStore"));
        let ready = pkg.dual_run_readiness();
        assert!(ready.ready_for_dual_run_observe());
        assert!(!ready.ready_for_rust_lower_pilot());
        assert!(ready.host_body_matches_plan);
    }

    #[test]
    fn counter_fixture_content_hash_stable() {
        // Reloading the same fixture twice must yield identical contentHash
        // (core + capability-plan file bytes). Declared meta hash must match.
        let pkg1 = ExportPackage::load(fixture("counter-evm")).expect("load counter");
        let pkg2 = ExportPackage::load(fixture("counter-evm")).expect("reload counter");
        let h1 = pkg1.content_hash();
        let h2 = pkg2.content_hash();
        assert_eq!(h1, h2, "contentHash must be deterministic across loads");
        assert_eq!(h1.len(), 64, "sha256 hex");
        if let Some(meta) = &pkg1.meta {
            if let Some(declared) = meta.content_hash.as_deref() {
                if declared != "unset" && !declared.is_empty() {
                    assert_eq!(declared, h1, "export-meta contentHash must match recomputed");
                }
            }
        }
    }

    #[test]
    fn walk_create_host_calls_match_plan() {
        let pkg = ExportPackage::load(fixture("create-evm")).expect("load create");
        let walk = pkg.walk();
        assert_eq!(walk.host_calls_in_body.len(), 2);
        assert!(walk.op_kind_counts.get("hostCall").copied().unwrap_or(0) >= 2);
        assert!(host_calls_match_plan(&walk, &pkg.plan.host_op_handlers));
        let ready = pkg.dual_run_readiness();
        assert!(ready.host_body_matches_plan);
        assert!(ready.ready_for_dual_run_observe());
    }
}
