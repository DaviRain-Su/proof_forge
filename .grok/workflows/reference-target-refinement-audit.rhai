let meta = #{
    name: "reference-target-refinement-audit",
    description: "R1 audit: map Reference→target refinement real state, blockers, and actionable bounded slices across all twelve materializers. Read-only. Produces a frozen slice backlog + honesty baseline. Does not close formal TASK/TST, invent decisions, or expand accepted PRD.",
    phases: [
        #{ title: "Shard", detail: "one explorer per refinement surface (NEAR / Solana / EVM / shared-core)" },
        #{ title: "Synthesize", detail: "merge into one frozen slice backlog + honesty baseline" },
        #{ title: "Verify", detail: "one skeptic per claimed actionable slice" },
    ],
};

// ---- Schemas ----

let surface_schema = #{
    "type": "object",
    "required": ["surface", "current_state", "claim_level", "blockers", "actionable_slices"],
    "properties": #{
        "surface": #{ "type": "string" },
        "current_state": #{ "type": "string", "description": "What is actually in HEAD code/tests, not docs. Cite file:line." },
        "claim_level": #{ "type": "string", "enum": ["L0", "L1", "L2", "L3"], "description": "L0 Lean theorem checked / L1 Reference-certified / L2 engineering observed / L3 target-refined" },
        "blockers": #{ "type": "array", "items": #{ "type": "string" }, "description": "What blocks upgrading the claim level. Be specific: Boolean-gated premise, missing kernel discharge, product decision, qualification host." },
        "actionable_slices": #{ "type": "array", "maxItems": 10, "items": #{
            "type": "object",
            "required": ["id", "objective", "allowlist", "done_when", "not_claim"],
            "properties": #{
                "id": #{ "type": "string", "description": "UPPERCASE slice id, e.g. SOL-0048-D5-GET-UNCONDITIONAL" },
                "objective": #{ "type": "string" },
                "allowlist": #{ "type": "array", "items": #{ "type": "string" }, "description": "Exact files/suites the slice may touch" },
                "done_when": #{ "type": "string", "description": "Focused verification command + pass condition" },
                "not_claim": #{ "type": "string", "description": "What the slice must NOT claim (formal / hermetic / full target refinement)" },
            },
        }},
        "evidence": #{ "type": "array", "items": #{ "type": "string" }, "description": "file:line citations supporting each fact above" },
    },
};

let synthesis_schema = #{
    "type": "object",
    "required": ["frozen_slices", "honesty_baseline", "ordering", "out_of_scope"],
    "properties": #{
        "frozen_slices": #{ "type": "array", "items": #{
            "type": "object",
            "required": ["id", "objective", "allowlist", "done_when", "not_claim", "surface"],
            "properties": #{
                "id": #{ "type": "string" },
                "objective": #{ "type": "string" },
                "allowlist": #{ "type": "array", "items": #{ "type": "string" } },
                "done_when": #{ "type": "string" },
                "not_claim": #{ "type": "string" },
                "surface": #{ "type": "string" },
            },
        }},
        "honesty_baseline": #{ "type": "string", "description": "One paragraph: current per-target claim levels, what must NOT be written as done, formal status 0/27 unchanged." },
        "ordering": #{ "type": "array", "items": #{ "type": "string" }, "description": "Serial slice ids in recommended order; note which can parallelize (disjoint allowlists)" },
        "out_of_scope": #{ "type": "array", "items": #{ "type": "string" }, "description": "Slices/decisions explicitly excluded and why" },
    },
};

let verdict_schema = #{
    "type": "object",
    "required": ["real", "reason", "evidence"],
    "properties": #{
        "real": #{ "type": "boolean", "description": "true only if the slice is genuinely actionable (allowlist disjoint, no hidden product decision, focused verifiable, does not claim formal)" },
        "reason": #{ "type": "string" },
        "evidence": #{ "type": "string", "description": "file:line or doc citation proving the judgment" },
    },
};

// ---- Guard args ----
// This workflow is read-only (no code edits, no commit, no push), so no mode
// gate is needed. args is accepted but not consumed.

// ---- Phase 1: Shard (parallel read-only exploration) ----

// Rhai arrays have no .contains; hand-roll membership check.
fn has(arr, x) {
    for a in arr { if a == x { return true; } }
    return false;
}

phase("Shard");

let surfaces = [
    #{
        prompt: "Audit the NEAR Reference→target refinement surface in ProofForge. Read the actual code and tests, not docs. " +
                "Focus: (1) VerifiedVaultPF status/init/deposit/withdraw MethodIR/typed-WAT slices — what is actually kernel-proven vs Boolean-gated; " +
                "(2) WasmCert-Coq provider (ADR-0043) — what is pinned, what runs, what is still assumed; " +
                "(3) canonical section envelope consumer; (4) the gap between 'engineering observed' and 'target-refined'. " +
                "Cite file:line for every fact. Read ProofForgeV2/Targets/Near/**, Tests/Materialization/Near*.lean, runtime-tests/near/**, " +
                "docs/adr/0042*.md, docs/adr/0043*.md, docs/plan/verified-contract-authoring.md Phase 7. " +
                "Do NOT claim formal TASK-D2-07 / TST-SEM-002/003 done. Report claim_level as the HONEST current level, not the aspirational one.",
        label: "near-refinement",
        capability_mode: "read-only",
        output_schema: surface_schema,
    },
    #{
        prompt: "Audit the Solana Reference→target refinement surface in ProofForge. Read the actual code and tests, not docs. " +
                "Focus: (1) StateCell get/initialize/increment/overflow — four sparse provider certificates (55/55/70/56 steps) — " +
                "are they Boolean-gated or kernel-discharged? What is the exact remaining blocker for SOL-0048-D5-GET-UNCONDITIONAL? " +
                "(2) ADR-0048 accepted provider boundary — what is pinned, what is assumed; (3) SbpfHandlerJoinV1 carrier; " +
                "(4) the gap between 'bounded Plan/HandlerIR refinement' and 'full .so target-refined'. " +
                "Cite file:line for every fact. Read ProofForgeV2/Targets/Solana/SbpfStateCell*.lean, SbpfHandlerJoinV1.lean, " +
                "Tests/Materialization/Solana*.lean, runtime-tests/solana/**, docs/adr/0048*.md, docs/plan/solana-adr-0048-next.md. " +
                "Do NOT claim formal TASK-D5 done. Report the HONEST current claim level.",
        label: "solana-refinement",
        capability_mode: "read-only",
        output_schema: surface_schema,
    },
    #{
        prompt: "Audit the EVM Reference→target refinement surface in ProofForge. Read the actual code and tests, not docs. " +
                "Focus: (1) Is there ANY EVM target refinement slice today, or only Reference lighthouse (LH-1..28) + Anvil engineering differential? " +
                "(2) OutcomeWireV1 / pf.reference-outcome.v1 — engineering-only, no formal EV binding; " +
                "(3) Anvil↛OutcomeWire lossless — still spec fail-closed (C-3)? Cite the spec line. " +
                "(4) What would a first bounded EVM refinement slice look like, and what product decision blocks it (B-CALL-SEM, SPEC-honesty ADR)? " +
                "Cite file:line for every fact. Read ProofForgeV2/Targets/Evm/**, Tests/Materialization/Evm*.lean, " +
                "docs/plan/evm-formal-d2-07-gap.md, docs/plan/evm-formal-d2-06-gap.md, docs/plan/evm-call-addr-gap.md, " +
                "docs/specs/evm-outcome-adapter-v1.md. Do NOT claim formal TASK-D2-06/07 done.",
        label: "evm-refinement",
        capability_mode: "read-only",
        output_schema: surface_schema,
    },
    #{
        prompt: "Audit the shared-core refinement prerequisites in ProofForge. Read the actual code, not docs. " +
                "Focus: (1) ReferenceMachineV1.stepReferenceSliceV1 — is it the sole executable semantics? Any second step anywhere? " +
                "(2) SemanticProgramV1 / CompiledSemanticV1 — sole carrier, no alpha residual? " +
                "(3) alpha-deletion-gate — does it still hold? (4) What shared-core work (TypeKey usage/rank, SPEC typeKey byte form, " +
                "ContextRead same-key TypeId) is pinned-but-not-a-structure-gate, and what product decision blocks promoting it? " +
                "(5) The L0-L3 claim-level matrix from verified-contract-authoring.md §6 — is it enforced anywhere in code/manifest? " +
                "Cite file:line for every fact. Read ProofForgeV2/Semantic/ReferenceMachineV1.lean, ProofForgeV2/Semantic/Wire/TypeKeyV1.lean, " +
                "ProofForgeV2/Core/TargetIdentityV1.lean, scripts/*deletion-gate*, docs/plan/evm-formal-d2-06-typekey-usage.md. " +
                "Do NOT claim formal done.",
        label: "shared-core",
        capability_mode: "read-only",
        output_schema: surface_schema,
    },
];

let surface_results = parallel(surfaces);

// Collect non-empty surfaces
let surfaces_ok = [];
for r in surface_results {
    if r != () && r.success && r.output.surface != () { surfaces_ok.push(r.output); }
}
log(surfaces_ok.len().to_string() + "/4 surfaces returned data");

// ---- Phase 2: Synthesize ----

phase("Synthesize");

let all_slices = [];
for s in surfaces_ok {
    if s.actionable_slices != () {
        for sl in s.actionable_slices {
            if sl.id != () && sl.id != "" {
                all_slices.push(#{
                    id: sl.id,
                    objective: sl.objective,
                    allowlist: sl.allowlist,
                    done_when: sl.done_when,
                    not_claim: sl.not_claim,
                    surface: s.surface,
                });
            }
        }
    }
}

// Build honesty baseline from surface states
let baseline_parts = [];
for s in surfaces_ok {
    let line = s.surface + ": " + s.claim_level + " — " + s.current_state;
    baseline_parts.push(line);
}
let baseline = "";
for bl in baseline_parts {
    baseline += bl + "\n";
}

let ordering = [];
// Simple ordering: Solana unconditional first (ADR-0048 accepted, clearest blocker), then NEAR, then shared-core, EVM last (decision-blocked)
let priority = ["SOL-0048-D5-GET-UNCONDITIONAL", "SOL-0048-D5-INIT-UNCONDITIONAL", "SOL-0048-D5-INC-UNCONDITIONAL", "SOL-0048-D5-OVF-UNCONDITIONAL"];
let placed = [];
for p in priority {
    for sl in all_slices {
        if sl.id == p && !has(placed, p) {
            ordering.push(p);
            placed.push(p);
        }
    }
}
// Then any remaining slices
for sl in all_slices {
    if !has(placed, sl.id) {
        ordering.push(sl.id);
        placed.push(sl.id);
    }
}

let out_of_scope = [
    "C-3 / Anvil↛OutcomeWire lossless — formal-blocked, not a coding slice",
    "B-CALL-SEM — product decision (callee deployment address), not auto-codable",
    "SPEC-honesty ADR (void vs typed return) — product decision, not auto-codable",
    "TASK-D1-01 / TASK-D2-06 / TASK-D2-07 formal closeout — needs qualification host, single-maintainer cannot do",
    "New TargetId (cairo/risc0/sp1/aptos/sui/Bitcoin) — out of scope per ADR-0036",
    "Merkle / Bytes ABI / ed25519 auto-open — gated by EXT-CRYPTO design decision",
    "Soroban S1 Wasm / auth / TTL — product decision (SOR-1), not auto-codable",
    "Quint Q2 Tool Lock + ITF/MBT — product decision (QUINT-2)",
];

let synthesis = #{
    frozen_slices: all_slices,
    honesty_baseline: baseline,
    ordering: ordering,
    out_of_scope: out_of_scope,
};

// ---- Phase 3: Verify (one skeptic per actionable slice) ----

phase("Verify");

let vjobs = [];
for sl in all_slices {
    let p = "Adversarially verify this proposed Reference→target refinement slice is genuinely actionable: " +
            "id=" + sl.id + " objective=" + sl.objective + " allowlist=" + json_encode(sl.allowlist) + " " +
            "done_when=" + sl.done_when + " not_claim=" + sl.not_claim + ". " +
            "Set real=true ONLY if ALL hold: (1) allowlist files exist and are disjoint from other slices; " +
            "(2) no hidden product/formal decision is required (read AGENTS.md Non-Negotiable Product Boundaries + Recovery Execution Protocol); " +
            "(3) done_when is a focused lake env lean / just command, not a shard or full ci; " +
            "(4) not_claim explicitly forbids formal/hermetic/full-target-refinement; " +
            "(5) the slice does not invent a second executable semantics (verified-contract-authoring.md §3.3). " +
            "Read the actual files before answering. Default real=false if any doubt.";
    vjobs.push(#{
        prompt: p,
        label: "verify:" + sl.id,
        capability_mode: "read-only",
        output_schema: verdict_schema,
    });
}

let verdicts = parallel(vjobs);

let confirmed = [];
let i = 0;
for sl in all_slices {
    let v = verdicts[i];
    if v != () && v.success && v.output.real == true && v.output.evidence != () && v.output.evidence != "" {
        confirmed.push(#{
            id: sl.id,
            objective: sl.objective,
            allowlist: sl.allowlist,
            done_when: sl.done_when,
            not_claim: sl.not_claim,
            surface: sl.surface,
            verify_reason: v.output.reason,
            verify_evidence: v.output.evidence,
        });
    }
    i += 1;
}
log(confirmed.len().to_string() + "/" + all_slices.len().to_string() + " slices survived adversarial verification");

// ---- Report ----

let report = "# R1: Reference→target refinement audit (frozen)\n\n";
report += "## Honesty baseline (per surface, current claim level)\n\n";
report += synthesis.honesty_baseline + "\n\n";
report += "## Frozen actionable slices (" + confirmed.len().to_string() + " verified / " + all_slices.len().to_string() + " proposed)\n\n";
for s in confirmed {
    report += "### " + s.id + " [" + s.surface + "]\n";
    report += "- objective: " + s.objective + "\n";
    report += "- allowlist: " + json_encode(s.allowlist) + "\n";
    report += "- done_when: " + s.done_when + "\n";
    report += "- not_claim: " + s.not_claim + "\n";
    report += "- verify: " + s.verify_reason + " — " + s.verify_evidence + "\n\n";
}
report += "## Recommended ordering\n\n";
report += json_encode(synthesis.ordering) + "\n\n";
report += "## Out of scope (do not auto-code)\n\n";
for o in synthesis.out_of_scope { report += "- " + o + "\n"; }
report += "\n## Non-claims\n\n";
report += "- Formal D1-D4 stays 0/27. This audit does not close TASK/TST/EV.\n";
report += "- No second executable semantics. All refinement must reuse stepReferenceSliceV1.\n";
report += "- No accepted-PRD expansion. No new TargetId.\n";
report += "- Read-only workflow: no code edited, no commit, no push.\n";

let path = write_scratch_file("r1-refinement-audit.md", report);
complete(#{
    summary: confirmed.len().to_string() + " verified actionable slices across " + surfaces_ok.len().to_string() + " surfaces",
    report_path: path,
    confirmed_count: confirmed.len(),
    proposed_count: all_slices.len(),
    surfaces_audited: surfaces_ok.len(),
});