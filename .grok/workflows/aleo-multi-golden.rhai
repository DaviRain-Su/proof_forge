let meta = #{
    name: "aleo-multi-golden",
    description: "Aleo Instructions multi-fixture expansion: product Plan→IR structural pins for OptionState/Accumulator/MapMini/LoopSum; optional locked-leo compare; const probe; sequential commit",
    when_to_use: "After Aleo IR-0..G5/IR-7 idle; expands multi-fixture coverage without claiming full multi-program leo byte goldens or snarkVM execute.",
    phases: [
        #{ title: "Preflight", detail: "IR primary + suite baseline" },
        #{ title: "MULTI-GOLDEN", detail: "product structural Plan→IR for multiple Examples" },
        #{ title: "COMPILE-COMPARE", detail: "optional locked-leo golden for 1-2 fixtures" },
        #{ title: "CONST", detail: "Constant lower or plan-FC pin" },
        #{ title: "Close", detail: "docs/AGENTS residual honesty" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
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

let stop_after = if args == () || args.stop_after == () { "CONST" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "MULTI-GOLDEN" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "MULTI-GOLDEN" { 0 }
    else if name == "COMPILE-COMPARE" { 1 }
    else if name == "CONST" { 2 }
    else if name == "Close" { 3 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Aleo Instructions multi-fixture expansion. Shared worktree. ";
common += "Authority remains Aleo Instructions (not sole Leo). Plan §10 ALEO-MULTI-GOLDEN / COMPILE-COMPARE / CONST. ";
common += "Do NOT claim full multi-program leo byte-equality matrix; structural/product pins are the deliverable. ";
common += "Do NOT invent snarkVM. deployable=false. Counter golden must stay green. ";
common += "Code: Targets/Aleo/Instructions/*; EmitIRV1; Tests/Materialization/AleoInstructionsV1.lean; Examples/*.lean. ";
common += "AGENTS Solana #111–#125 + digests + SBOM 244 + 13/304 + 21/405 if editing Active. ";
common += "Never push/force/amend. Commit exact messages. sbom + docs-check. ";
common += "implemented=true when met; residual notes in blockers only. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. git status; HEAD; confirm IR primary + AleoInstructionsV1. ready if multi-golden can start. start=" + start_from + " stop=" + stop_after,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# blocked preflight\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
log("Preflight " + pre.output.head);
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " ";
    p += "Scope: ProofForgeV2/Targets/Aleo/** Tests/Materialization/** testdata/golden/aleo-instructions-v1/** docs/** AGENTS.md supply-chain/** .grok/workflows/** Examples/**. ";
    if do_commit {
        p += "ONE commit exact: " + commit_msg + " Never push. ";
    }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "ALEO-MULTI-GOLDEN", "MULTI-GOLDEN",
        "Expand AleoInstructionsV1 (and LowerPlan if needed) with product capability Plan→Instructions structural pins for admit-surface Examples: OptionState, Accumulator, MapMini (if Plan admits on Aleo), LoopSum. Assert method/mapping counts, key ops present, encode nonempty, no crash; hard-require still holds. Fix lower gaps if product Plan fails IR with ALEO-IR-G5-HARD for shapes that should lower. Counter golden byte pin must remain. Document which fixtures are structural-only vs byte-golden. Update plan §10 + backlog.",
        "feat(aleo): multi-fixture Instructions structural product pins", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked MULTI-GOLDEN\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "MULTI-GOLDEN", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped MULTI-GOLDEN\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "ALEO-COMPILE-COMPARE", "COMPILE-COMPARE",
        "If locked Leo 4.0.2 tool root available: for one small extra fixture (e.g. Accumulator or OptionState), product compile profile + capture compiled.aleo under testdata/golden/aleo-instructions-v1/ and pin structural or byte equality with Plan→IR where feasible. If tool MISSING: document skip + suite honesty note (no invent). Counter golden unchanged.",
        "feat(aleo): optional multi-fixture locked-leo Instructions compare", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked COMPILE-COMPARE\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "COMPILE-COMPARE", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped COMPILE-COMPARE\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "ALEO-CONST", "CONST",
        "Probe Op.Constant on Aleo Plan path: if can honestly lower to Instructions (literal-backed constants), implement + tests; else keep plan-FC with stable pin in AleoInstructionsV1 and matrix note. No false Y.",
        "feat(aleo): Instructions const lower or plan-FC pin", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked CONST\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "CONST", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -10; status. Update plan/backlog/AGENTS. docs-check. remaining deferred list. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Aleo multi-golden\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n\n## Remaining\n" + json_encode(close.output.remaining) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
