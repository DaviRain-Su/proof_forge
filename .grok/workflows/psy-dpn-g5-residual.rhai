let meta = #{
    name: "psy-dpn-g5-residual",
    description: "Continue Psy DPN after DPN-1..7: G5 residual slices (wide mul/div/shift, aggregate goldens, admit matrix FC pins, optional hard-require DPN); sequential implement+commit, no push",
    when_to_use: "Use after PSY-DPN-1..7 dual-write is on main/local HEAD; advances G5 admit-surface residuals in docs/targets/10-psy-dpn-lowering.md §10.",
    phases: [
        #{ title: "Preflight", detail: "confirm DPN-1..7 baseline and residual list" },
        #{ title: "G5-WIDE", detail: "UInt128/256 bindWide mul/div/shift → DPN" },
        #{ title: "G5-AGG", detail: "Array/Principal/Bytes multi-leaf product goldens" },
        #{ title: "G5-MATRIX", detail: "§3.2 Y/P rows: DPN lower or explicit FC pin" },
        #{ title: "G5-HARD", detail: "hard-require DPN for Psy Plan admits (or document defer)" },
        #{ title: "Close", detail: "docs/backlog/AGENTS residual honesty" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "dpn7_present", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "dpn7_present": #{ "type": "boolean" },
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

let close_schema = #{
    "type": "object",
    "required": ["passed", "summary", "head", "phases_done", "remaining", "commands"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "phases_done": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "remaining": #{ "type": "array", "maxItems": 24, "items": #{ "type": "string" } },
        "commands": #{ "type": "array", "maxItems": 30, "items": #{
            "type": "object", "required": ["command", "result"],
            "properties": #{ "command": #{ "type": "string" }, "result": #{ "type": "string" } },
        }},
    },
};

let stop_after = if args == () || args.stop_after == () { "G5-HARD" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "G5-WIDE" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "G5-WIDE" { 0 }
    else if name == "G5-AGG" { 1 }
    else if name == "G5-MATRIX" { 2 }
    else if name == "G5-HARD" { 3 }
    else if name == "Close" { 4 }
    else { 0 }
}

let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "You implement ProofForge Psy DPN G5 residual work in the SHARED worktree. ";
common += "Authority: docs/targets/10-psy-dpn-lowering.md §3 admit matrix + §10 next steps. ";
common += "DPN-1..7 already landed (dual-write .dpn.json + transitional .psy). ";
common += "Code: ProofForgeV2/Targets/Psy/Dpn/{SchemaV1,JsonCodecV1,LowerPlanV1}.lean; EmitIRV1 dual-write; Tests/Materialization/PsyDpnV1.lean; Examples/WideCounter.lean WideCounter256.lean. ";
common += "Psy-only lane. Evidence fail-closed. Dual profiles: default psy-dargo-u64-v1 vs psy-dargo-0.1.0-vm-v1 for wide. ";
common += "Never: formal TASK/TST, release-check, Stage-0, push, force, amend, reset --hard, checkout --, secrets, network install, maturity inflation, UPS/deploy claims. ";
common += "Reuse EmitIRV1 schoolbook mul / restoring div / limb shift algorithms when lowering bindWide* to DPN defs (U32 ops + range asserts; inputs <2^32). ";
common += "Residual honesty notes go in blockers array WITHOUT setting implemented=false when the slice objective is met. ";
common += "When committing: one local commit, git add -- specific paths only, never git add -A, never push. ";
common += "After ProofForgeV2 edits: just sbom-package-files-refresh. Docs: just docs-check. ";
common += "Focused test: lake env lean --run Tests/Materialization/PsyDpnV1.lean. Keep Counter dargo golden green. ";

phase("Preflight");
let pre_prompt = common;
pre_prompt += "READ-ONLY PREFLIGHT with shell. Run git log --oneline -8, git status --short, git rev-parse HEAD. ";
pre_prompt += "Confirm DPN dual-write exists (emitFromIR .dpn.json) and LowerPlanV1 packageFromCapabilityV1. ";
pre_prompt += "dpn7_present=true if DPN-7 dual-write present. ready=true if G5 residual can proceed. ";
pre_prompt += "Short plan for G5-WIDE → AGG → MATRIX → HARD. start_from=" + start_from + " stop_after=" + stop_after + ".";
let preflight = agent(pre_prompt, #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if preflight == () || !preflight.success || preflight.output.ready != true {
    let report = "# PSY-DPN G5 residual\n\nBlocked at preflight.\n\n" + json_encode(preflight);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "preflight", report_path: path, report: report });
}
log("Preflight ok head=" + preflight.output.head);

let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, allowed_hint, commit_msg, do_commit, impl_schema) {
    phase(title);
    let impl_prompt = common_text;
    impl_prompt += "IMPLEMENT " + slice_id + " in SHARED worktree. ";
    impl_prompt += "Objective: " + objective + " ";
    impl_prompt += "Scope: " + allowed_hint + " ";
    impl_prompt += "Tests-first in Tests/Materialization/PsyDpnV1.lean and/or testdata/golden/psy-dpn-v1/. ";
    impl_prompt += "Update docs/targets/10-psy-dpn-lowering.md, docs/engineering-backlog.md PSY-DPN* rows, AGENTS.md Active/Next accurately. ";
    impl_prompt += "Run lake env lean --run Tests/Materialization/PsyDpnV1.lean; sbom refresh if Lean product changed; just docs-check if docs changed. ";
    if do_commit {
        impl_prompt += "On green: ONE local commit message EXACTLY: " + commit_msg + " Use git add -- <paths>. Never push. ";
        impl_prompt += "If already implemented on HEAD (message/content match), verify tests and set implemented=true, commit=HEAD sha, summary=already-done. ";
    } else {
        impl_prompt += "Do NOT commit. commit empty string; worktree_clean_after=false. ";
    }
    impl_prompt += "implemented=true when slice acceptance is met; put future work in blockers as residual notes, not hard fail. ";
    impl_prompt += "implemented=false only if cannot deliver the slice at all (missing evidence for honest mapping). ";
    let impl = agent(impl_prompt, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success {
        return #{ status: "blocked", slice: slice_id, stage: "implement", detail: impl };
    }
    if impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, stage: "implement", detail: impl.output };
    }
    if impl.output.blockers.len() != 0 {
        log(slice_id + " residual: " + json_encode(impl.output.blockers));
    }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

// --- G5-WIDE ---
if start_rank <= 0 && stop_rank >= 0 {
    let p = run_slice(
        common,
        "PSY-DPN-G5-WIDE",
        "G5-WIDE",
        "Lower Plan bindWideUintMul / bindWideUintDivMod / bindWideUintShift to DPN for UInt128 (4×UInt32) on psy-dargo-0.1.0-vm-v1; port EmitIRV1 schoolbook 8×UInt16 mul, restoring binary div/mod, and limb shifts with u32 range asserts and overflow/zero-div assertions. Prefer structural product lower of Examples/WideCounter multiply/divide/remainder/shift entries (or hand-built Plan). Default profile must stay FC for UInt128. UInt256 optional if time permits; else residual note. Counter golden must remain green.",
        "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, testdata/golden/psy-dpn-v1/**, docs/**, AGENTS.md, supply-chain/**, Examples/WideCounter.lean",
        "feat(psy): DPN wide mul/div/shift lowering (G5-WIDE)",
        !skip_commit,
        phase_schema
    );
    phase_results.push(p);
    if p.status != "ok" {
        let report = "# PSY-DPN G5 residual\n\nBlocked at G5-WIDE.\n\n" + json_encode(p);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "G5-WIDE", report_path: path, report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# PSY-DPN G5 residual\n\nStopped after G5-WIDE.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// --- G5-AGG ---
if start_rank <= 1 && stop_rank >= 1 {
    let p = run_slice(
        common,
        "PSY-DPN-G5-AGG",
        "G5-AGG",
        "Admit Array / Principal / Bytes multi-leaf (and any missing Struct leaf shapes already in Psy Plan) into DPN via multi SlotSingle / storeAggregate / returnAggregate consistent with existing multi-leaf layout. Add PsyDpnV1 structural or product tests; golden optional. Nested Map/Map return stay FC. Do not invent unsupported ProgramV1 surface.",
        "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, testdata/golden/psy-dpn-v1/**, docs/**, AGENTS.md, supply-chain/**, Examples/**",
        "feat(psy): DPN Array/Principal/Bytes multi-leaf (G5-AGG)",
        !skip_commit,
        phase_schema
    );
    phase_results.push(p);
    if p.status != "ok" {
        let report = "# PSY-DPN G5 residual\n\nBlocked at G5-AGG.\n\n" + json_encode(p);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "G5-AGG", report_path: path, report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# PSY-DPN G5 residual\n\nStopped after G5-AGG.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// --- G5-MATRIX ---
if start_rank <= 2 && stop_rank >= 2 {
    let p = run_slice(
        common,
        "PSY-DPN-G5-MATRIX",
        "G5-MATRIX",
        "Scan docs/targets/10-psy-dpn-lowering.md §3.2 admit matrix. For each Y or P row: either prove DPN lower exists (test or known path) or add explicit stable FC diagnostic test. Update matrix status column honestly. Produce a short matrix coverage table in the planning doc. Prefer automated tests over prose-only claims. No false Y marks.",
        "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, docs/**, AGENTS.md, supply-chain/**",
        "feat(psy): DPN G5 admit matrix scan and FC pins",
        !skip_commit,
        phase_schema
    );
    phase_results.push(p);
    if p.status != "ok" {
        let report = "# PSY-DPN G5 residual\n\nBlocked at G5-MATRIX.\n\n" + json_encode(p);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "G5-MATRIX", report_path: path, report: report, phases: phase_results });
    }
}
if stop_rank <= 2 {
    let report = "# PSY-DPN G5 residual\n\nStopped after G5-MATRIX.\n\n" + json_encode(phase_results);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "stopped", stop_after: stop_after, report_path: path, report: report, phases: phase_results });
}

// --- G5-HARD ---
if start_rank <= 3 && stop_rank >= 3 {
    let p = run_slice(
        common,
        "PSY-DPN-G5-HARD",
        "G5-HARD",
        "Product honesty cut: when Psy Plan validates, prefer requiring DPN lower success for dual-write primary path OR document deferred hard-require with evidence. Preferred engineering: if packageFromCapability/lowerPlanToPackage fails on a shape that Plan admitted, fail materialize with stable PSY-DPN diagnostic instead of silent .psy-only (except optional debug flag). Keep deployable=false. If hard-require would break too many residual shapes, implement a gated profile or explicit residual allowlist + tests, and list remaining in blockers. Do not claim G6 deletion of .psy complete unless fully done.",
        "ProofForgeV2/Targets/Psy/**, Tests/Materialization/**, docs/**, AGENTS.md, supply-chain/**",
        "feat(psy): DPN hard-require or gated residual policy (G5-HARD)",
        !skip_commit,
        phase_schema
    );
    phase_results.push(p);
    if p.status != "ok" {
        let report = "# PSY-DPN G5 residual\n\nBlocked at G5-HARD.\n\n" + json_encode(p);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "G5-HARD", report_path: path, report: report, phases: phase_results });
    }
}

phase("Close");
let close_prompt = common;
close_prompt += "CLOSEOUT. git log --oneline -20; git status --short. Summarize which G5 slices landed. ";
close_prompt += "Update docs/targets/10-psy-dpn-lowering.md §10 and G-ladder; docs/engineering-backlog.md PSY-DPN residual; AGENTS Active/Next. ";
close_prompt += "Run just docs-check and PsyDpnV1 if needed. ";
if !skip_commit {
    close_prompt += "If docs dirty, one commit: docs(psy): DPN G5 residual closeout. Never push. ";
}
close_prompt += "passed=true if at least G5-WIDE or MATRIX advanced honestly; remaining= G6, method_id hash, Tool Lock, UInt256 if skipped, etc. ";
close_prompt += "Phase results: " + json_encode(phase_results);
let close = agent(close_prompt, #{ label: "closeout", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# PSY-DPN G5 residual\n\nCloseout failed.\n\n" + json_encode(phase_results) + "\n" + json_encode(close);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "close", report_path: path, report: report, phases: phase_results });
}

let final_status = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# PSY-DPN G5 residual\n\n**Status:** " + final_status + "\n\n";
report += "**Close:** " + close.output.summary + "\n\n";
report += "## Phases\n" + json_encode(phase_results) + "\n\n";
report += "## Remaining\n" + json_encode(close.output.remaining) + "\n\n";
report += "Engineering only; nothing pushed.\n";
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
