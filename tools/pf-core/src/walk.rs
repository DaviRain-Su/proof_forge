//! Structural walk over exported Core JSON (not a semantic interpreter).
//!
//! Used for dual-run readiness summaries and fail-closed consistency checks
//! between Core body hostCalls and capability-plan hostOpHandlers.

use crate::{CoreModuleSummary, ExportPackage, HostOpHandler};
use serde_json::Value;
use std::collections::BTreeMap;

/// Counts and host-call inventory from walking Core instructions/terminators.
#[derive(Debug, Clone, Default)]
pub struct CoreWalkSummary {
    pub function_count: usize,
    pub block_count: usize,
    pub instruction_count: usize,
    /// Top-level instruction op kinds (`pure`, `storageLoad`, `hostCall`, …).
    pub op_kind_counts: BTreeMap<String, usize>,
    /// Nested pure op kinds (`literal`, `arithmetic`, …).
    pub pure_kind_counts: BTreeMap<String, usize>,
    pub terminator_kind_counts: BTreeMap<String, usize>,
    /// HostOp render ids discovered in Core body (stable sorted unique).
    pub host_calls_in_body: Vec<String>,
    pub storage_op_count: usize,
    pub crosscall_count: usize,
    pub memory_op_count: usize,
    pub context_read_count: usize,
    pub assert_count: usize,
    pub emit_count: usize,
}

impl CoreWalkSummary {
    pub fn bump_op(&mut self, kind: &str) {
        *self.op_kind_counts.entry(kind.to_string()).or_insert(0) += 1;
        self.instruction_count += 1;
        match kind {
            "storageLoad" | "storageStore" | "storageContains" | "storageRemove"
            | "storageLength" | "storageResize" => self.storage_op_count += 1,
            "memoryAlloc" | "memoryLoad" | "memoryStore" | "memoryRelease" => {
                self.memory_op_count += 1
            }
            "crosscall" => self.crosscall_count += 1,
            "contextRead" => self.context_read_count += 1,
            "assert" => self.assert_count += 1,
            "emit" => self.emit_count += 1,
            _ => {}
        }
    }

    pub fn lines(&self) -> Vec<String> {
        let mut lines = vec![
            format!(
                "walk: functions={} blocks={} instructions={}",
                self.function_count, self.block_count, self.instruction_count
            ),
            format!(
                "walk: storage={} memory={} crosscall={} contextRead={} assert={} emit={}",
                self.storage_op_count,
                self.memory_op_count,
                self.crosscall_count,
                self.context_read_count,
                self.assert_count,
                self.emit_count
            ),
        ];
        if !self.op_kind_counts.is_empty() {
            let ops: Vec<_> = self
                .op_kind_counts
                .iter()
                .map(|(k, n)| format!("{k}={n}"))
                .collect();
            lines.push(format!("walk: opKinds {}", ops.join(" ")));
        }
        if !self.pure_kind_counts.is_empty() {
            let pure: Vec<_> = self
                .pure_kind_counts
                .iter()
                .map(|(k, n)| format!("{k}={n}"))
                .collect();
            lines.push(format!("walk: pureKinds {}", pure.join(" ")));
        }
        if !self.terminator_kind_counts.is_empty() {
            let terms: Vec<_> = self
                .terminator_kind_counts
                .iter()
                .map(|(k, n)| format!("{k}={n}"))
                .collect();
            lines.push(format!("walk: terminators {}", terms.join(" ")));
        }
        if self.host_calls_in_body.is_empty() {
            lines.push("walk: hostCallsInBody (none)".into());
        } else {
            lines.push(format!(
                "walk: hostCallsInBody [{}]",
                self.host_calls_in_body.join(", ")
            ));
        }
        lines
    }
}

/// Walk a deserialized Core module summary (blocks remain JSON values).
pub fn walk_module(module: &CoreModuleSummary) -> CoreWalkSummary {
    let mut summary = CoreWalkSummary {
        function_count: module.functions.len(),
        ..CoreWalkSummary::default()
    };
    let mut host_set = std::collections::BTreeSet::new();

    for function in &module.functions {
        for block in &function.blocks {
            summary.block_count += 1;
            if let Some(instructions) = block.get("instructions").and_then(Value::as_array) {
                for insn in instructions {
                    if let Some(op) = insn.get("op") {
                        walk_instruction_op(op, &mut summary, &mut host_set);
                    }
                }
            }
            if let Some(term) = block.get("terminator") {
                let kind = term
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown");
                *summary
                    .terminator_kind_counts
                    .entry(kind.to_string())
                    .or_insert(0) += 1;
            }
        }
    }
    summary.host_calls_in_body = host_set.into_iter().collect();
    summary
}

fn walk_instruction_op(
    op: &Value,
    summary: &mut CoreWalkSummary,
    host_set: &mut std::collections::BTreeSet<String>,
) {
    let kind = op.get("kind").and_then(Value::as_str).unwrap_or("unknown");
    summary.bump_op(kind);
    match kind {
        "pure" => {
            if let Some(inner) = op.get("op") {
                let pure_kind = inner
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown");
                *summary
                    .pure_kind_counts
                    .entry(pure_kind.to_string())
                    .or_insert(0) += 1;
            }
        }
        "hostCall" => {
            if let Some(call) = op.get("call") {
                if let Some(id) = call.get("id") {
                    let render = id
                        .get("render")
                        .and_then(Value::as_str)
                        .map(|s| s.to_string())
                        .unwrap_or_else(|| render_host_id(id));
                    host_set.insert(render);
                }
            }
        }
        _ => {}
    }
}

fn render_host_id(id: &Value) -> String {
    let ns = id.get("namespace").and_then(Value::as_str).unwrap_or("?");
    let name = id.get("name").and_then(Value::as_str).unwrap_or("?");
    let ver = id.get("version");
    let major = ver
        .and_then(|v| v.get("major"))
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let minor = ver
        .and_then(|v| v.get("minor"))
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let patch = ver
        .and_then(|v| v.get("patch"))
        .and_then(Value::as_u64)
        .unwrap_or(0);
    format!("{ns}/{name}@{major}.{minor}.{patch}")
}

/// Dual-run readiness checklist for a loaded package (no lowering yet).
#[derive(Debug, Clone)]
pub struct DualRunReadiness {
    pub core_ok: bool,
    pub plan_ok: bool,
    pub interface_present: bool,
    pub content_hash_ok: bool,
    pub host_body_matches_plan: bool,
    pub host_ops_available: bool,
    pub lowerer_implemented: bool,
    pub notes: Vec<String>,
}

impl DualRunReadiness {
    pub fn ready_for_dual_run_observe(&self) -> bool {
        self.core_ok
            && self.plan_ok
            && self.content_hash_ok
            && self.host_body_matches_plan
            && self.host_ops_available
        // lowerer not required for observe-only dual-run on Lean artifacts
    }

    pub fn ready_for_rust_lower_pilot(&self) -> bool {
        self.ready_for_dual_run_observe() && self.lowerer_implemented
    }

    pub fn lines(&self) -> Vec<String> {
        let mut lines = vec![
            format!(
                "dualRun: core={} plan={} interface={} contentHash={} hostBody↔plan={} hostAvailable={} lowerer={}",
                yn(self.core_ok),
                yn(self.plan_ok),
                yn(self.interface_present),
                yn(self.content_hash_ok),
                yn(self.host_body_matches_plan),
                yn(self.host_ops_available),
                yn(self.lowerer_implemented)
            ),
            format!(
                "dualRun: observeReady={} rustLowerPilot={}",
                yn(self.ready_for_dual_run_observe()),
                yn(self.ready_for_rust_lower_pilot())
            ),
        ];
        for n in &self.notes {
            lines.push(format!("dualRun: note: {n}"));
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

/// Compare Core body hostCalls with capability-plan hostOpHandlers (set equality).
pub fn host_calls_match_plan(walk: &CoreWalkSummary, handlers: &[HostOpHandler]) -> bool {
    let plan: std::collections::BTreeSet<_> =
        handlers.iter().map(|h| h.id.render()).collect();
    let body: std::collections::BTreeSet<_> =
        walk.host_calls_in_body.iter().cloned().collect();
    plan == body
}

impl ExportPackage {
    pub fn walk(&self) -> CoreWalkSummary {
        walk_module(&self.core.module)
    }

    pub fn dual_run_readiness(&self) -> DualRunReadiness {
        let walk = self.walk();
        let host_body_matches_plan =
            host_calls_match_plan(&walk, &self.plan.host_op_handlers);
        let host_ops_available = self.plan.host_op_handlers.iter().all(|h| h.available);
        let content_hash_ok = match self.meta.as_ref().and_then(|m| m.content_hash.as_deref()) {
            None | Some("") | Some("unset") => true,
            Some(declared) => declared == self.content_hash(),
        };
        let mut notes = Vec::new();
        if !host_body_matches_plan {
            notes.push(format!(
                "Core hostCalls {:?} vs plan handlers {:?}",
                walk.host_calls_in_body,
                self.plan
                    .host_op_handlers
                    .iter()
                    .map(|h| h.id.render())
                    .collect::<Vec<_>>()
            ));
        }
        let scalar_storage_sketch_eligible = walk.host_calls_in_body.is_empty()
            && walk.crosscall_count == 0
            && walk.memory_op_count == 0
            && walk.op_kind_counts.keys().all(|k| {
                matches!(
                    k.as_str(),
                    "pure"
                        | "storageLoad"
                        | "storageStore"
                        | "storageContains"
                        | "contextRead"
                        | "emit"
                        | "assert"
                )
            });
        if scalar_storage_sketch_eligible {
            notes.push(
                "EvmLowererPilot scalar storage sketch available (pure+storage±contextRead/emit/assert; not bytecode)"
                    .into(),
            );
        } else {
            notes.push(
                "EvmLowererPilot scalar storage sketch not eligible (unsupported ops/hostCalls)"
                    .into(),
            );
        }
        DualRunReadiness {
            core_ok: self.core.core_schema == "core.v0",
            plan_ok: self.plan.capability_plan_schema == "capability-plan.v0"
                && !self.plan.target_id.is_empty(),
            interface_present: self.interface.is_some(),
            content_hash_ok,
            host_body_matches_plan,
            host_ops_available,
            // Storage-only sketch is a pilot step, not full lower.
            lowerer_implemented: false,
            notes,
        }
    }
}
