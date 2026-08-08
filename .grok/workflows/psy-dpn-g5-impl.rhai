let meta = #{
    name: "psy-dpn-g5-impl",
    description: "Implement remaining Psy DPN residual allowlist families (narrow UInt, Int, pureFn, UInt64 shift, bitNot) then full hard-require; sequential commit, no push",
    when_to_use: "After G5-WIDE/AGG/MATRIX/HARD closed; residual allowlist still emits .psy-only for narrow/Int/pureFn/shl/bitNot.",
    phases: [
        #{ title: "Preflight", detail: "confirm G5-HARD allowlist and residual list" },
        #{ title: "R-NARROW", detail: "UInt8/16/32 checked arith + range in DPN" },
        #{ title: "R-INT", detail: "Int64/narrow Int signed ops in DPN" },
        #{ title: "R-SHIFT-BIT", detail: "UInt64 shl/shr + checkedBitNot in DPN" },
        #{ title: "R-PURE", detail: "pureFn/localCall inline or subgraph DPN" },
        #{ title: "R-HARD", detail: "shrink/delete residual allowlist; full hard-require" },
        #{ title: "Close", detail: "docs and residual honesty" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "allowlist_present", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "allowlist_present": #{ "type": "boolean" },
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

let stop_after = if args == () || args.stop_after == () { "R-HARD" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "R-NARROW" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "R-NARROW" { 0 }
    else if name == "R-INT" { 1 }
    else if name == "R-SHIFT-BIT" { 2 }
    else if name == "R-PURE" { 3 }
    else if name == "R-HARD" { 4 }
    else if name == "Close" { 5 }
    else { 0 }
}

let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Psy DPN residual implementation. Shared worktree. ";
common += "Authority: docs/targets/10-psy-dpn-lowering.md §3.2 residual rows + G5-HARD allowlist. ";
common += "Code: ProofForgeV2/Targets/Psy/Dpn/LowerPlanV1.lean EmitIRV1.lean (isPsyDpnG5HardResidualAllowlistV1). Tests/Materialization/PsyDpnV1.lean. ";
common += "After each residual family truly lowers to DPN, REMOVE it from residual allowlist so product dual-writes .dpn.json. ";
common += "Mirror EmitIR / Plan semantics; fail closed if no honest DPN encoding. ";
common += "Never formal/release/push/force/amend/reset --hard. Local commit only with exact message. ";
common += "sbom-package-files-refresh after product Lean; docs-check after docs; PsyDpnV1 focused tests. Counter golden green. ";
common += "implemented=true when slice met; residual future work only in blockers notes. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. git log -8 --oneline; git status; rev-parse HEAD. Confirm G5-HARD allowlist and residual FC diagnostics. ready if residual impl can proceed. start=" + start_from + " stop=" + stop_after + ".",
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# PSY-DPN G5 impl\n\nBlocked preflight.\n\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
log("Preflight " + pre.output.head);
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text;
    p += "IMPLEMENT " + slice_id + ". Objective: " + objective + " ";
    p += "Scope: ProofForgeV2/Targets/Psy/** Tests/Materialization/** docs/** AGENTS.md supply-chain/**. ";
    p += "Tests-first PsyDpnV1. Update docs matrix residual→done when true. ";
    if do_commit {
        p += "ONE commit exact message: " + commit_msg + " git add -- paths only. Never push. Already-done → verify + HEAD sha. ";
    } else {
        p += "Do not commit. ";
    }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " notes " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "R-NARROW", "R-NARROW",
        "DPN lower for narrow UInt8/16/32 state/param/literal/checked add/sub/mul/div/mod and compares with exact range asserts (mirror EmitIR). Product Plan→DPN where Psy admits. Remove narrow UInt from residual allowlist when green. Keep Counter UInt64 golden.",
        "feat(psy): DPN narrow UInt8/16/32 lowering (G5 residual)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# PSY-DPN G5 impl\n\nBlocked R-NARROW.\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "R-NARROW", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped after R-NARROW\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "R-INT", "R-INT",
        "DPN lower for Int64 and narrow Int signed add/sub/mul/div/mod/neg/compares as admitted by Psy Plan (two's complement in Felt or honest U32-backed encoding with overflow asserts). Remove Int residual from allowlist when green; else keep FC with evidence.",
        "feat(psy): DPN signed Int lowering (G5 residual)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked R-INT\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "R-INT", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped after R-INT\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "R-SHIFT-BIT", "R-SHIFT-BIT",
        "DPN lower for UInt64 shl/shr and checkedBitNot as Psy Plan emits. Prefer U32/Target ops + range/invalidShift asserts matching EmitIR. Remove from residual allowlist when green.",
        "feat(psy): DPN UInt64 shift and bitNot (G5 residual)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked R-SHIFT-BIT\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "R-SHIFT-BIT", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 2 {
    let report = "# stopped after R-SHIFT-BIT\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 3 && stop_rank >= 3 {
    let r = run_slice(common, "R-PURE", "R-PURE",
        "DPN lower pureFn + localCall: inline pure subgraph into caller definitions (preferred) or separate pure method defs if dargo/package shape requires. Match EmitIR pure helper emission honesty. Remove pureFn residual from allowlist when green. Fail closed on recursive/effectful pureFn.",
        "feat(psy): DPN pureFn/localCall lowering (G5 residual)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked R-PURE\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "R-PURE", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 3 {
    let report = "# stopped after R-PURE\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 4 && stop_rank >= 4 {
    let r = run_slice(common, "R-HARD", "R-HARD",
        "After residual families implemented: shrink or delete isPsyDpnG5HardResidualAllowlistV1 so materialize hard-requires DPN for all Plan-admitted shapes. Only leave allowlist empty or tiny with documented plan-FC exceptions. Update tests: former residual .psy-only cases must dual-write .dpn.json. deployable=false. Do not claim G6 .psy deletion unless done.",
        "feat(psy): DPN full hard-require after residual lowers (G5)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked R-HARD\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "R-HARD", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -15; status. Update docs §3.2 residual→done, backlog, AGENTS Next. just docs-check + PsyDpnV1. Docs-only commit if dirty: docs(psy): DPN G5 residual implementation closeout. passed if narrow or pure advanced. remaining=G6, method_id, etc. phases=" + json_encode(phase_results),
    #{ label: "closeout", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# PSY-DPN G5 impl\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n\n## Remaining\n" + json_encode(close.output.remaining) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
