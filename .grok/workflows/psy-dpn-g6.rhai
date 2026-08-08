let meta = #{
    name: "psy-dpn-g6",
    description: "PSY-DPN G6: .psy debug-only or deletion-gate path, psy-runtime DPN-first where honest, optional WideCounter256 product pin; no UPS/formal claims",
    when_to_use: "After R-HARD full hard-require (empty residual allowlist) and dual-write DPN primary is stable.",
    phases: [
        #{ title: "Preflight", detail: "confirm full hard-require and dual-write baseline" },
        #{ title: "G6-DEBUG", detail: ".psy optional debug-only / env or flag; DPN required primary" },
        #{ title: "G6-RUNTIME", detail: "psy-runtime / acceptance prefer DPN package when present" },
        #{ title: "G6-PIN", detail: "optional WideCounter256 or dargo structural pin" },
        #{ title: "Close", detail: "docs G6 honesty" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "hard_require", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "hard_require": #{ "type": "boolean" },
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

let stop_after = if args == () || args.stop_after == () { "G6-PIN" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "G6-DEBUG" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "G6-DEBUG" { 0 }
    else if name == "G6-RUNTIME" { 1 }
    else if name == "G6-PIN" { 2 }
    else if name == "Close" { 3 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Psy DPN G6. Shared worktree. Authority: docs/targets/10-psy-dpn-lowering.md G6 / §10. ";
common += "Baseline: R-HARD full hard-require; dual-write .dpn.json primary + transitional .psy. ";
common += "deployable=false forever in this slice. No UPS/network/formal. Never push/force/amend/reset --hard. ";
common += "Prefer evidence: keep .psy as opt-in debug if deletion breaks psy-runtime; document honesty. ";
common += "Local commit exact message; sbom refresh; docs-check; PsyDpnV1 tests. ";
common += "implemented=true when acceptance met; residual notes in blockers only. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. git log -8; status; HEAD. Confirm isPsyDpnG5HardResidualAllowlistV1 empty and dual-write. hard_require=true if empty allowlist. ready for G6. start=" + start_from + " stop=" + stop_after,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# G6 blocked preflight\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
log("Preflight " + pre.output.head);
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " Scope: ProofForgeV2/Targets/Psy/** scripts/** Tests/** docs/** AGENTS.md supply-chain/**. ";
    if do_commit {
        p += "ONE commit: " + commit_msg + " git add -- paths. Never push. ";
    }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "G6-DEBUG", "G6-DEBUG",
        "Make .psy emission debug-only: default product emits ONLY {name}.dpn.json as primary OutputFile; emit transitional .psy only when explicit opt-in (env PROOF_FORGE_PSY_EMIT_PSY=1 or IR/build flag documented). Update Finalize notes. Tests: Counter product default has .dpn.json and no .psy unless flag; with flag dual-write. Keep deployable=false. Do not delete EmitIR.psy lower code yet unless safe—prefer gated emission.",
        "feat(psy): DPN-primary emission; .psy debug-only (G6)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked G6-DEBUG\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "G6-DEBUG", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped G6-DEBUG\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "G6-RUNTIME", "G6-RUNTIME",
        "Point psy-runtime / psy_acceptance / scripts toward DPN-first when {name}.dpn.json exists (dargo package JSON path). If locked dargo still requires .psy source for compile, document PARTIAL: runtime can execute prebuilt package JSON from product .dpn.json without regenerating from .psy; do not invent unsupported dargo flags. Prefer minimal script changes + tests/docs. Host-heavy optional; do not break ordinary ci. deployable=false.",
        "feat(psy): psy-runtime DPN-first path (G6)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked G6-RUNTIME\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "G6-RUNTIME", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped G6-RUNTIME\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "G6-PIN", "G6-PIN",
        "Optional pins: WideCounter256 VM product Plan→DPN structural package test; and/or document why full dargo byte golden is deferred. If WideCounter256 already lowers, add PsyDpnV1 pin. No false completeness.",
        "feat(psy): DPN G6 optional product pins", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked G6-PIN\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "G6-PIN", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -12; status. Update docs G6 ladder, backlog, AGENTS Next. docs-check. Docs commit if needed: docs(psy): DPN G6 closeout. remaining=method_id hash, UPS etc. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# PSY-DPN G6\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n\n## Remaining\n" + json_encode(close.output.remaining) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
