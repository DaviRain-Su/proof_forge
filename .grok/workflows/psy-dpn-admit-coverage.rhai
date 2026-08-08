let meta = #{
    name: "psy-dpn-admit-coverage",
    description: "Sequential PSY-DPN remaining slices: baseline DPN-2 commit, then DPN-3 control-flow, DPN-4 multi-leaf/wide, DPN-5 Map, DPN-6 effects honesty, DPN-7 product cutover; implement-verify-commit each phase without push",
    when_to_use: "Use after PSY-DPN-1/2 schema+Counter lower exist and docs/targets/10-psy-dpn-lowering.md is the admit-surface plan; advances ProgramV1 Psy admit surface toward DPN authority.",
    phases: [
        #{ title: "Preflight", detail: "authority, existing DPN modules, dirty baseline awareness" },
        #{ title: "Baseline-DPN2", detail: "verify and local-commit DPN-1/2 if uncommitted" },
        #{ title: "DPN-3", detail: "if/match/bounded-for → DPN Select/unroll" },
        #{ title: "DPN-4", detail: "multi-leaf aggregates and UInt128 wide profile" },
        #{ title: "DPN-5", detail: "Map cap-8 without .psy return-in-if" },
        #{ title: "DPN-6", detail: "emit/call honesty matrix; FC for schedule/assets/context" },
        #{ title: "DPN-7", detail: "product dual-write or DPN primary artifact path" },
        #{ title: "Close", detail: "docs/backlog/AGENTS + final focused gates" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "dpn2_present", "uncommitted_dpn", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "dpn2_present": #{ "type": "boolean" },
        "uncommitted_dpn": #{ "type": "boolean" },
        "plan": #{ "type": "string" },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};

let phase_schema = #{
    "type": "object",
    "required": ["implemented", "summary", "head", "files_changed", "tests_run", "blockers", "commit", "worktree_clean_after"],
    "properties": #{
        "implemented": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
        "commit": #{ "type": "string" },
        "worktree_clean_after": #{ "type": "boolean" },
    },
};

// Keep findings items minimal — agents often omit optional "fix" and fail the whole phase.
let review_schema = #{
    "type": "object", "required": ["ok", "summary", "findings"],
    "properties": #{
        "ok": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "findings": #{ "type": "array", "maxItems": 12, "items": #{
            "type": "object", "required": ["severity", "file", "issue"],
            "properties": #{
                "severity": #{ "type": "string", "enum": ["P0", "P1", "P2"] },
                "file": #{ "type": "string" },
                "issue": #{ "type": "string" },
                "fix": #{ "type": "string" },
            },
        }},
    },
};

let close_schema = #{
    "type": "object",
    "required": ["passed", "summary", "head", "phases_done", "remaining", "commands"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "phases_done": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "remaining": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "commands": #{ "type": "array", "maxItems": 30, "items": #{
            "type": "object", "required": ["command", "result"],
            "properties": #{ "command": #{ "type": "string" }, "result": #{ "type": "string" } },
        }},
    },
};

// Optional: start_from / stop_after phase titles (Baseline-DPN2, DPN-3..DPN-7).
let stop_after = if args == () || args.stop_after == () { "DPN-7" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "Baseline-DPN2" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };
let skip_baseline_commit = if args == () || args.skip_baseline_commit == () { false } else { args.skip_baseline_commit };
// skip_review=true avoids brittle review schema blocks (impl+commit still run).
let skip_review = if args == () || args.skip_review == () { false } else { args.skip_review };

fn phase_rank(name) {
    if name == "Baseline-DPN2" { 0 }
    else if name == "DPN-3" { 1 }
    else if name == "DPN-4" { 2 }
    else if name == "DPN-5" { 3 }
    else if name == "DPN-6" { 4 }
    else if name == "DPN-7" { 5 }
    else if name == "Close" { 6 }
    else { 0 }
}

let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "You are implementing ProofForge Psy DPN lowering in the shared worktree. ";
common += "Authority: docs/targets/10-psy-dpn-lowering.md (admit surface = ProgramV1 constructs Psy admits, encoded as DPNFunctionCircuitDefinition; NOT full PSL handbook, NOT every DPN opcode). ";
common += "Existing code: ProofForgeV2/Targets/Psy/Dpn/{SchemaV1,JsonCodecV1,LowerPlanV1}.lean; Tests/Materialization/PsyDpnV1.lean; testdata/golden/psy-dpn-v1/*.json. ";
common += "Read AGENTS.md Recovery protocol. Psy-only lane. Evidence fail-closed. Dual profiles: default psy-dargo-u64-v1 vs explicit psy-dargo-0.1.0-vm-v1 for wide. ";
common += "Never: formal TASK/TST, release-check, Stage-0, push, force, amend, reset --hard, checkout --, secrets, network install, fallback adapters, dual ProgramV1 decoder, maturity inflation, UPS/deploy claims. ";
common += "When committing: one local commit only, git add -- specific paths, never git add -A, never push. ";
common += "After product Lean changes: just sbom-package-files-refresh. Docs: just docs-check. Prefer lake env lean --run Tests/Materialization/PsyDpnV1.lean or just test-targets focused; just ci when practical. ";

phase("Preflight");
let pre_prompt = common;
pre_prompt += "READ-ONLY PREFLIGHT. Run git status --short and git rev-parse HEAD. Confirm DPN modules exist (SchemaV1, JsonCodecV1, LowerPlanV1). ";
pre_prompt += "Set dpn2_present=true if packageFromCapabilityV1 / Counter lower exists. Set uncommitted_dpn=true if DPN files are dirty. ";
pre_prompt += "ready=true if DPN-1/2 foundation is present and work can proceed (dirty worktree is OK if it is DPN work). ";
pre_prompt += "List blockers if foundation missing. Short plan for remaining DPN-3..7 order. ";
pre_prompt += "start_from=" + start_from + " stop_after=" + stop_after + " skip_commit=" + skip_commit.to_string() + " skip_review=" + skip_review.to_string() + ".";
let preflight = agent(pre_prompt, #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if preflight == () || !preflight.success || preflight.output.ready != true {
    let report = "# PSY-DPN admit coverage\n\nBlocked at preflight.\n\n" + json_encode(preflight);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "preflight", report_path: path, report: report });
}
log("Preflight ok head=" + preflight.output.head + " uncommitted_dpn=" + preflight.output.uncommitted_dpn.to_string());

let phase_results = [];
let last_head = preflight.output.head;

// --- helper-style sequential phases encoded inline ---

// Rhai fn cannot close over outer schema maps — pass schemas explicitly.
fn run_slice(common_text, slice_id, title, objective, allowed_hint, commit_msg, do_commit, do_review, impl_schema, rev_schema) {
    phase(title);
    let impl_prompt = common_text;
    impl_prompt += "IMPLEMENT SLICE " + slice_id + " in the SHARED worktree (not isolation). ";
    impl_prompt += "Objective: " + objective + " ";
    impl_prompt += "Scope hint: " + allowed_hint + " ";
    impl_prompt += "Tests-first: extend Tests/Materialization/PsyDpnV1.lean and/or golden JSON under testdata/golden/psy-dpn-v1/; keep existing Counter pins green. ";
    impl_prompt += "Expand LowerPlanV1 (and Schema/JsonCodec only if new op/statecmd needed). Prefer honest templates then general SSA; fail closed on unsupported. ";
    impl_prompt += "Update docs/targets/10-psy-dpn-lowering.md checkboxes, docs/engineering-backlog.md PSY-DPN-* row, AGENTS.md Active/Next if accurate. ";
    impl_prompt += "Run focused Lean tests for PsyDpnV1; on ProofForgeV2 edits run just sbom-package-files-refresh; on docs just docs-check. ";
    if do_commit {
        impl_prompt += "When green: create ONE local commit with message exactly: " + commit_msg + " Stage only intentional paths with git add -- <path>. Never push. ";
        impl_prompt += "Return commit=sha, worktree_clean_after=true if clean after commit. ";
    } else {
        impl_prompt += "Do NOT commit. Leave uncommitted; set commit=empty string, worktree_clean_after=false. ";
    }
    impl_prompt += "If blocked by missing upstream DPN evidence or impossible honest mapping, set implemented=false and list blockers (prefer evidence FC over fake lower). ";
    let impl = agent(impl_prompt, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success {
        return #{ status: "blocked", slice: slice_id, stage: "implement", detail: impl };
    }
    // Residual gaps may be listed in blockers as honesty notes; only hard-fail when
    // implemented=false. Soft residual gaps are carried in the phase result.
    if impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, stage: "implement", detail: impl.output };
    }
    if impl.output.blockers.len() != 0 {
        log(slice_id + " residual notes: " + json_encode(impl.output.blockers));
    }

    if do_review {
        let rev_prompt = common_text;
        rev_prompt += "READ-ONLY review of " + slice_id + ". git status; inspect diff vs HEAD~1 or uncommitted diff. ";
        rev_prompt += "Focus: DPN honesty (no invented op codes), default profile FC for wide, Counter golden still holds, no formal overclaim, no .psy as secret authority. ";
        rev_prompt += "ok=true only if no P0/P1; list findings with fixes. Objective was: " + objective;
        let rev = agent(rev_prompt, #{ label: "review:" + slice_id, phase: title, capability_mode: "read-only", output_schema: rev_schema });
        if rev == () || !rev.success {
            return #{ status: "blocked", slice: slice_id, stage: "review", detail: rev };
        }
        if rev.output.ok != true {
            let fix_prompt = common_text;
            fix_prompt += "REPAIR " + slice_id + " P0/P1 findings only. Findings: " + json_encode(rev.output.findings) + " ";
            fix_prompt += "Keep scope. Re-run focused tests. ";
            if do_commit {
                fix_prompt += "If already committed, create ONE follow-up fix commit message: fix(" + slice_id + "): address review findings. Never amend/push. ";
            }
            let fix = agent(fix_prompt, #{ label: "repair:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
            if fix == () || !fix.success || fix.output.implemented != true {
                return #{ status: "blocked", slice: slice_id, stage: "repair", detail: fix };
            }
            return #{ status: "ok", slice: slice_id, impl: fix.output, review: rev.output, repaired: true };
        }
        return #{ status: "ok", slice: slice_id, impl: impl.output, review: rev.output, repaired: false };
    }
    return #{ status: "ok", slice: slice_id, impl: impl.output, review: (), repaired: false };
}

// Baseline: commit DPN-2 foundation if dirty
if !skip_baseline_commit && start_rank <= 0 && stop_rank >= 0 {
    let b = run_slice(
        common,
        "PSY-DPN-2-baseline",
        "Baseline-DPN2",
        "Verify DPN-1/2 Counter packageFromCapability ≡ full golden; ensure tests green; if uncommitted DPN work exists, commit it as feat(psy): DPN Counter Plan lower (DPN-2). If already clean committed, no-op implemented=true with summary already-committed.",
        "ProofForgeV2/Targets/Psy/**, Tests/Materialization/PsyDpnV1.lean, testdata/golden/psy-dpn-v1/**, docs/**, AGENTS.md, supply-chain/**",
        "feat(psy): DPN Counter Plan→package lower (DPN-2)",
        !skip_commit,
        !skip_review,
        phase_schema,
        review_schema
    );
    phase_results.push(b);
    if b.status != "ok" {
        let report = "# PSY-DPN admit coverage\n\nBlocked at baseline DPN-2.\n\n" + json_encode(b);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "baseline", report_path: path, report: report, phases: phase_results });
    }
    log("Baseline done");
}

if stop_rank <= 0 {
    let report = "# PSY-DPN admit coverage\n\nStopped after baseline as requested.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// DPN-3
if start_rank <= 1 && stop_rank >= 1 {
let p3 = run_slice(
    common,
    "PSY-DPN-3",
    "DPN-3",
    "Lower Psy Plan if/match and bounded for to DPN: Select + conditional SetContractStateSlotSingle; bounded for as static unroll matching existing Psy Emit semantics (Examples/LoopSum or similar). Extend Schema OpType for Select if missing. Golden or structural tests; default profile still FC for unsupported. Keep Counter templates. Fail closed on while/unbounded. If DPN-3 already committed (HEAD message contains DPN-3), verify tests still green and no-op commit with implemented=true.",
    "ProofForgeV2/Targets/Psy/Dpn/**, ProofForgeV2/Targets/Psy.lean, Tests/Materialization/**, testdata/golden/psy-dpn-v1/**, docs/**, AGENTS.md, supply-chain/**",
    "feat(psy): DPN if/match/for lowering (DPN-3)",
    !skip_commit,
    !skip_review,
    phase_schema,
    review_schema
);
phase_results.push(p3);
if p3.status != "ok" {
    let report = "# PSY-DPN admit coverage\n\nBlocked at DPN-3.\n\n" + json_encode(p3);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "DPN-3", report_path: path, report: report, phases: phase_results });
}
}
if stop_rank <= 1 {
    let report = "# PSY-DPN admit coverage\n\nStopped after DPN-3.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// DPN-4
if start_rank <= 2 && stop_rank >= 2 {
let p4 = run_slice(
    common,
    "PSY-DPN-4",
    "DPN-4",
    "Multi-leaf and wide: Option/Array/Struct/Principal/Bytes multi-slot Get/Set Range or multi Single; UInt128 4×UInt32 only on psy-dargo-0.1.0-vm-v1 (default profile FC). Prefer OptionState + WideCounter fixtures. Extend Schema state cmds as needed. Structural/golden tests.",
    "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, testdata/golden/psy-dpn-v1/**, docs/**, AGENTS.md, supply-chain/**",
    "feat(psy): DPN multi-leaf and wide UInt128 (DPN-4)",
    !skip_commit,
    !skip_review,
    phase_schema,
    review_schema
);
phase_results.push(p4);
if p4.status != "ok" {
    let report = "# PSY-DPN admit coverage\n\nBlocked at DPN-4.\n\n" + json_encode(p4);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "DPN-4", report_path: path, report: report, phases: phase_results });
}
}
if stop_rank <= 2 {
    let report = "# PSY-DPN admit coverage\n\nStopped after DPN-4.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// DPN-5
if start_rank <= 3 && stop_rank >= 3 {
let p5 = run_slice(
    common,
    "PSY-DPN-5",
    "DPN-5",
    "Map cap-8 dense store fully expressible in DPN without relying on dargo .psy return-in-if. MapMini or Token-style fixture. Goldens/tests prove DPN path works where text .psy broke.",
    "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, testdata/golden/psy-dpn-v1/**, docs/**, AGENTS.md, supply-chain/**",
    "feat(psy): DPN Map cap-8 lowering (DPN-5)",
    !skip_commit,
    !skip_review,
    phase_schema,
    review_schema
);
phase_results.push(p5);
if p5.status != "ok" {
    let report = "# PSY-DPN admit coverage\n\nBlocked at DPN-5.\n\n" + json_encode(p5);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "DPN-5", report_path: path, report: report, phases: phase_results });
}
}
if stop_rank <= 3 {
    let report = "# PSY-DPN admit coverage\n\nStopped after DPN-5.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// DPN-6
if start_rank <= 4 && stop_rank >= 4 {
let p6 = run_slice(
    common,
    "PSY-DPN-6",
    "DPN-6",
    "Effects honesty matrix in DPN lower: emit/call only when product already admits PARTIAL with evidence (InvokeExternalContractFunctionSync only if justified); schedule/assets/context/invariant/nonempty stay fail-closed with stable diagnostics. Tests pin FC and any honest PARTIAL encode. No maturity expansion.",
    "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, docs/**, AGENTS.md, supply-chain/**",
    "feat(psy): DPN effects honesty matrix (DPN-6)",
    !skip_commit,
    !skip_review,
    phase_schema,
    review_schema
);
phase_results.push(p6);
if p6.status != "ok" {
    let report = "# PSY-DPN admit coverage\n\nBlocked at DPN-6.\n\n" + json_encode(p6);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "DPN-6", report_path: path, report: report, phases: phase_results });
}
}
if stop_rank <= 4 {
    let report = "# PSY-DPN admit coverage\n\nStopped after DPN-6.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// DPN-7
if start_rank <= 5 && stop_rank >= 5 {
let p7 = run_slice(
    common,
    "PSY-DPN-7",
    "DPN-7",
    "Product cutover: materialize DPN package JSON as primary or dual-write artifact alongside transitional .psy; wire filesFromIR/Finalize so build can emit *.dpn.json or package JSON; keep deployable=false; document .psy as debug/transition. Prefer dual-write compare if safer. Do not claim hermetic/UPS.",
    "ProofForgeV2/Targets/Psy/**, ProofForgeV2/Targets/**/Finalize*, Tests/Materialization/**, docs/**, AGENTS.md, supply-chain/**",
    "feat(psy): DPN product artifact cutover (DPN-7)",
    !skip_commit,
    !skip_review,
    phase_schema,
    review_schema
);
phase_results.push(p7);
if p7.status != "ok" {
    let report = "# PSY-DPN admit coverage\n\nBlocked at DPN-7.\n\n" + json_encode(p7);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "DPN-7", report_path: path, report: report, phases: phase_results });
}
}

// Close
phase("Close");
let close_prompt = common;
close_prompt += "CLOSEOUT. Summarize which PSY-DPN phases landed (3-7 + baseline). Run git log --oneline -15 and git status --short. ";
close_prompt += "Update docs/targets/10-psy-dpn-lowering.md phase checkboxes accurately; docs/engineering-backlog.md; AGENTS Active/Next. ";
close_prompt += "Run just docs-check and focused PsyDpn tests if needed. ";
if !skip_commit {
    close_prompt += "If docs-only dirty, one commit: docs(psy): DPN admit coverage closeout. Never push. ";
}
close_prompt += "passed=true only if no critical unfinished P0 for claimed-done phases. remaining= honest leftover (e.g. G5 full matrix scan, G6 execute without .psy, method_id hash). ";
close_prompt += "Phase results JSON: " + json_encode(phase_results);
let close = agent(close_prompt, #{ label: "closeout", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# PSY-DPN admit coverage\n\nCloseout agent failed.\n\n" + json_encode(phase_results) + "\n\n" + json_encode(close);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "close", report_path: path, report: report, phases: phase_results });
}

let final_status = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# PSY-DPN admit coverage\n\n**Status:** " + final_status + "\n\n";
report += "**stop_after:** " + stop_after + "\n\n";
report += "**Close summary:** " + close.output.summary + "\n\n";
report += "## Phases\n" + json_encode(phase_results) + "\n\n";
report += "## Remaining\n" + json_encode(close.output.remaining) + "\n\n";
report += "## Commands\n" + json_encode(close.output.commands) + "\n\n";
report += "Engineering only: formal/release not assessed. Nothing pushed.\n";
let report_path = write_scratch_file("report.md", report);
complete(#{
    status: final_status,
    report_path: report_path,
    report: report,
    phases: phase_results,
    remaining: close.output.remaining,
    head: close.output.head,
    agent_calls: budget().spent,
});
