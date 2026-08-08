let meta = #{
    name: "psy-dpn-residual",
    description: "Optional Psy DPN residual: official method_id SHA-256 pin, Tool Lock psy-node rev mirror, cleanup/docs honesty for package-only dargo and deferred full-byte goldens",
    when_to_use: "After G6 closeout when lane is idle; implement optional residual blockers only (no UPS/formal).",
    phases: [
        #{ title: "Preflight", detail: "baseline G6 + residual list" },
        #{ title: "RES-METHOD-ID", detail: "gen_dapen SHA-256 method_id in Lean" },
        #{ title: "RES-TOOL-LOCK", detail: "Tool Lock / docs pin psy-node rev" },
        #{ title: "RES-CLEAN", detail: "duplicate golden cleanup + residual tests" },
        #{ title: "Close", detail: "docs/backlog/AGENTS residual honesty" },
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

let stop_after = if args == () || args.stop_after == () { "RES-CLEAN" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "RES-METHOD-ID" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "RES-METHOD-ID" { 0 }
    else if name == "RES-TOOL-LOCK" { 1 }
    else if name == "RES-CLEAN" { 2 }
    else if name == "Close" { 3 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Psy DPN optional residual. Shared worktree. No UPS/formal/push/force/amend. ";
common += "Authority: docs/targets/10-psy-dpn-lowering.md §6/§10 residual. ";
common += "OFFICIAL method_id (verified against psy_crypto + Counter dargo golden): ";
common += "gen_dapen_contract_function_method_id(method_name, args) = first 4 LE bytes of SHA-256(UTF-8 of preimage) as u32, ";
common += "preimage = method_name + '(' + join(arg_name + '[' + size + ']', ',') + ')'. ";
common += "Felt/Bool/U32 size=1; EmitIR renames params to p0,p1,... in source order (Counter: get()→1459926901, increment(p0[1])→1990357658, initialize(p0[1])→202172507). ";
common += "Use ProofForgeV2.Crypto.sha256 / Common.sha256Bytes. Replace pinnedMethodIdV1 table with algorithm; keep Counter golden green. ";
common += "UInt128 params: size = limb count (4) if that is what EmitIR/dargo uses for multi-limb — verify against EmitIR param emission before claiming. ";
common += "package-only dargo execute still MISSING on locked dargo 0.1.0 — document only, do not invent CLI. ";
common += "Full multi-method dargo byte golden remains deferred unless cheap. Delete identical counter-package-full.v1.json if still untracked. ";
common += "Local commit exact message; sbom refresh; docs-check; PsyDpnV1. implemented=true when slice met; residual notes in blockers only. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. git log -8; status; HEAD. Confirm G6 done. Plan residual slices. start=" + start_from + " stop=" + stop_after,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# residual blocked preflight\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
log("Preflight " + pre.output.head);
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " Scope: ProofForgeV2/** Tests/** docs/** AGENTS.md supply-chain/** scripts/** .grok/workflows/**. ";
    if do_commit {
        p += "ONE commit message EXACTLY: " + commit_msg + " git add -- paths. Never push. ";
    }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "RES-METHOD-ID", "RES-METHOD-ID",
        "Implement official method_id in LowerPlanV1: genDapenContractFunctionMethodIdV1(name, args: Array (String × Nat)) using Crypto.sha256, LE u32 from first 4 bytes. Wire requireMethodIdV1 from Plan fn param Felt sizes (p0.. naming matching EmitIR). Unit tests: Counter get/increment/initialize exact ids; pureFn inlined methods still use caller's package method names. Prefer algorithm over hardcode table (table may remain as regression pin). Counter product package ≡ golden method_ids.",
        "feat(psy): official gen_dapen method_id SHA-256 (residual)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked RES-METHOD-ID\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "RES-METHOD-ID", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped RES-METHOD-ID\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "RES-TOOL-LOCK", "RES-TOOL-LOCK",
        "Pin psy-node rev 79e0b82422ebdd1173a7b4b3751eb3186aad83e5 as authority for DPN method_id/schema in Tool Lock docs and/or supply-chain annotation + 10-psy-dpn-lowering.md checkbox. Do not break dargo 0.1.0 runtime pins. Prefer additive documentation field or comments in ToolLockV4 / psy runtime scripts; fail closed if rev cannot be honestly bound.",
        "docs(psy): pin psy-node rev for DPN residual (Tool Lock)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked RES-TOOL-LOCK\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "RES-TOOL-LOCK", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped RES-TOOL-LOCK\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "RES-CLEAN", "RES-CLEAN",
        "Cleanup: remove untracked identical testdata/golden/psy-dpn-v1/counter-package-full.v1.json if still present (duplicate of counter-package.v1.json). Reaffirm deferred full multi-package dargo byte golden and package-only execute PARTIAL in docs/tests comments only. Add/adjust PsyDpnV1 residual note tests if useful. No false package-only claims.",
        "chore(psy): DPN residual cleanup and deferred honesty", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked RES-CLEAN\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "RES-CLEAN", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -12; status. Update §10 residual checkboxes (method_id done if landed). AGENTS Next residual. docs-check. Docs commit if needed: docs(psy): DPN residual closeout. remaining=package-only dargo, full byte golden, UPS. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# PSY-DPN residual\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n\n## Remaining\n" + json_encode(close.output.remaining) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
