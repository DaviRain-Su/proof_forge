let meta = #{
    name: "aleo-instructions-g5",
    description: "Aleo Instructions post-IR-6 residual: G5 admit matrix scan, residual true lower + hard-require, IR-7 runtime honesty, cleanup; sequential commit no push",
    when_to_use: "After ALEO-IR-0..IR-6 product primary Instructions; plan §10 queue G5-MATRIX → G5-HARD → IR-7 → RES-CLEAN.",
    phases: [
        #{ title: "Preflight", detail: "IR-6 primary present; residual Leo path inventory" },
        #{ title: "G5-MATRIX", detail: "§3.2 scan + FC/IR pins + coverage table" },
        #{ title: "G5-HARD", detail: "true lower residual + hard-require no silent Leo-only" },
        #{ title: "IR-7", detail: "runtime honesty: tool probe or evidence MISSING" },
        #{ title: "RES-CLEAN", detail: "docs/backlog closeout deferred list" },
        #{ title: "Close", detail: "AGENTS Next honesty" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "ir6_primary", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "ir6_primary": #{ "type": "boolean" },
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

let stop_after = if args == () || args.stop_after == () { "RES-CLEAN" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "G5-MATRIX" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "G5-MATRIX" { 0 }
    else if name == "G5-HARD" { 1 }
    else if name == "IR-7" { 2 }
    else if name == "RES-CLEAN" { 3 }
    else if name == "Close" { 4 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Aleo Instructions G5 residual queue. Shared worktree. ";
common += "Plan: docs/targets/09-aleo-instructions-lowering.md §5 G5-MATRIX/G5-HARD/IR-7/RES-CLEAN + §10 queue. ";
common += "Baseline: IR-0..IR-6 done — product primary {id}.aleo = Instructions when lower succeeds; Leo debug PROOF_FORGE_ALEO_EMIT_LEO=1; residual Leo-primary still possible until G5-HARD. ";
common += "Code: ProofForgeV2/Targets/Aleo/Instructions/{SchemaV1,TextCodecV1,LowerPlanV1}.lean; EmitIRV1; Tests/Materialization/AleoInstructionsV1.lean; golden counter.compiled.aleo. ";
common += "Align Psy discipline: matrix honesty no false Y; hard-require no silent Leo-only for Plan-admitted shapes; residual true lower preferred before empty allowlist. ";
common += "Never invent snarkVM CLI; deployable=false; no prove/deploy/formal; no Psy expansion; no push/force/amend. ";
common += "AGENTS Active row must keep Solana #111–#125 + digests b0f3f5bc… e2c2ebac… + SBOM 244 + 13/304 + 21/405 if edited. ";
common += "Commit exact messages; sbom refresh; docs-check. implemented=true when met; residual notes only in blockers. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. git log -8; status; HEAD. Confirm Instructions primary path in EmitIRV1 and LowerPlanV1. List residual Leo-primary candidates (Int64/Field/pureFn). ready if G5 can start. start=" + start_from + " stop=" + stop_after,
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
    p += "Scope: ProofForgeV2/Targets/Aleo/** Tests/Materialization/** testdata/golden/aleo-instructions-v1/** docs/** AGENTS.md supply-chain/** .grok/workflows/**. ";
    p += "Update plan checkboxes, backlog ALEO-G5-*/ALEO-IR-7/ALEO-RES-CLEAN, AGENTS. ";
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
    let r = run_slice(common, "ALEO-G5-MATRIX", "G5-MATRIX",
        "Scan plan §3.2 admit matrix. For each Y/P/F row set Instructions status: done (IR test), residual (stable ALEO-IR FC + test), plan-FC (Plan/resolve FC). Add §3.2.1 coverage table. Extend AleoInstructionsV1 with pins for missing Y rows (const/Bool/assert, Int64 residual FC, pureFn residual FC, Field residual FC, nested Map plan-FC). No false Y. Update G5 ladder status to in-progress/done as accurate.",
        "feat(aleo): Instructions G5 admit matrix scan and FC pins", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked G5-MATRIX\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "G5-MATRIX", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped G5-MATRIX\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "ALEO-G5-HARD", "G5-HARD",
        "Residual true lower then hard-require: (1) lower residual Plan-admitted families to Instructions where honest (Int64 signed ops, Field BLS12-377 if Plan admits, pureFn/localCall inline — mirror existing Leo EmitIR semantics). (2) After lowers: remove silent Leo-only primary for Plan-admitted shapes — materialize must Instructions succeed or fail with stable ALEO-IR-G5-HARD (optional tiny evidence allowlist only if documented). (3) Tests: former residual dual-write paths; Counter golden green. deployable=false.",
        "feat(aleo): Instructions residual lower + G5 hard-require", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked G5-HARD\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "G5-HARD", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped G5-HARD\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "ALEO-IR-7", "IR-7",
        "Runtime honesty only: probe for locked snarkVM / honest package-only execute. If MISSING: document PARTIAL + suite note + optional just recipe that fail-closed PF-TOOLCHAIN-MISSING without inventing CLI. If tool exists under PROOF_FORGE_TOOL_ROOT or Tool Lock: minimal host-heavy Counter execute pin, not ordinary ci. Never claim deploy/prove formal.",
        "feat(aleo): Instructions runtime honesty pin (ALEO-IR-7)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-7\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-7", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 2 {
    let report = "# stopped IR-7\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 3 && stop_rank >= 3 {
    let r = run_slice(common, "ALEO-RES-CLEAN", "RES-CLEAN",
        "Closeout docs: mark G5/IR-7 status honestly; list deferred (full multi-program leo byte goldens, record custody, prove/deploy, full opcode). AGENTS Next = lane idle if G5+HARD done, else accurate remaining. just docs-check. Commit docs if needed.",
        "docs(aleo): Instructions G5 residual closeout", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked RES-CLEAN\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "RES-CLEAN", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT summary. git log -12; status. remaining=record/prove/full opcode if any. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Aleo G5 residual\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n\n## Remaining\n" + json_encode(close.output.remaining) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
