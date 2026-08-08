let meta = #{
    name: "noir-acir-ir",
    description: "Noir ACIR IR lane: IR-0 docs commit if needed, IR-1 nargo Counter golden+pin, IR-2 Plan→ACIR MVP, sequential commit",
    when_to_use: "After Aleo Instructions lane idle residual; plan docs/targets/07-noir-acir-lowering.md exists.",
    phases: [
        #{ title: "Preflight", detail: "plan present; nargo tool probe" },
        #{ title: "IR-1", detail: "capture Counter nargo artifact golden + Lean pin" },
        #{ title: "IR-2", detail: "Plan→ACIR or nargo-assisted MVP" },
        #{ title: "Close", detail: "docs/AGENTS" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "plan_present", "nargo_available", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "plan_present": #{ "type": "boolean" },
        "nargo_available": #{ "type": "boolean" },
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

let stop_after = if args == () || args.stop_after == () { "IR-2" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "IR-1" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "IR-1" { 0 }
    else if name == "IR-2" { 1 }
    else if name == "Close" { 2 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Noir ACIR IR lane. Shared worktree. ";
common += "Authority plan: docs/targets/07-noir-acir-lowering.md. Target authority = ACIR/nargo circuit artifacts, NOT sole .nr. ";
common += "Existing: NoirPlan→relation→main.nr packages; locked nargo 1.0.0-beta.26 compile-only; Finalize non-deployable. ";
common += "Aleo/Psy lanes idle residual — do not expand them. ";
common += "IR-1 MUST open real nargo compile outputs before inventing schema. Prefer testdata/golden/noir-acir-v1/. ";
common += "If nargo missing: still implement inventory pin strategy + suite skip honesty; do not invent backend. ";
common += "deployable=false; no prove/verify product claim. AGENTS keep Solana #111-#125 digests SBOM 244 13/304 21/405. ";
common += "Commit exact messages; sbom; docs-check. Never push. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY/execute. Confirm 07-noir-acir-lowering.md; probe PROOF_FORGE_TOOL_ROOT/nargo or Tool Lock cache. nargo_available true/false. ready if IR-1 can start (tool optional with honest skip path). Commit pending NOIR-IR-0 docs if dirty. start=" + start_from,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# blocked preflight\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
log("Preflight nargo=" + pre.output.nargo_available.to_string());
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " ";
    p += "Scope: ProofForgeV2/Targets/Noir/** Tests/Materialization/** testdata/golden/noir-acir-v1/** docs/** AGENTS.md supply-chain/** .grok/workflows/** scripts/**. ";
    if do_commit { p += "ONE commit: " + commit_msg + " Never push. "; }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "NOIR-IR-1", "IR-1",
        "Capture Counter product Noir package + locked nargo compile outputs. Freeze golden under testdata/golden/noir-acir-v1/ (document exact files). Lean: minimal inventory/hash pin and/or Schema if format is parseable; Tests/Materialization/NoirAcirV1.lean. Include NOIR-IR-0 docs/AGENTS/backlog if still dirty. Honest if only multi-file hash pin is possible.",
        "feat(noir): ACIR golden pin + IR-1 inventory (NOIR-IR-1)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-1\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-1", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped IR-1\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "NOIR-IR-2", "IR-2",
        "MVP Plan→ACIR path: either pure encoder matching golden, or documented nargo-assisted capture from product Plan emit that is the sole authority pin. Counter ≡ golden. Keep .nr emission working as transition. Update plan checkboxes G0-G2.",
        "feat(noir): Plan→ACIR Counter MVP (NOIR-IR-2)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-2\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-2", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -10; docs-check; AGENTS Next. remaining IR-3.. prove. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Noir ACIR IR\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
