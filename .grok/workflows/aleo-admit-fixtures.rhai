let meta = #{
    name: "aleo-admit-fixtures",
    description: "Aleo admit-surface fixtures as suite-owned sources + OptionState/MapMini locked-leo compare; sequential commit",
    when_to_use: "After ALEO-MULTI-GOLDEN/CONST idle; expand admit-surface fixtures without changing cross-target Examples for reserved names/computed views.",
    phases: [
        #{ title: "Preflight", detail: "baseline multi-golden done" },
        #{ title: "ADMIT-FIXTURES", detail: "suite-owned sources for Accumulator/Option/MapMini admit" },
        #{ title: "OPTION-COMPARE", detail: "locked-leo golden for OptionState admit" },
        #{ title: "Close", detail: "docs honesty" },
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

let stop_after = if args == () || args.stop_after == () { "OPTION-COMPARE" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "ADMIT-FIXTURES" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "ADMIT-FIXTURES" { 0 }
    else if name == "OPTION-COMPARE" { 1 }
    else if name == "Close" { 2 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Aleo admit-surface fixtures. Shared worktree. Instructions primary. ";
common += "Plan: 09-aleo-instructions-lowering.md §10 ALEO-ADMIT-FIXTURES + ALEO-OPTION-COMPARE. ";
common += "Do NOT rename shared Examples/Accumulator.add if it breaks other targets; prefer suite-owned ProgramV1 source strings or Tests/Fixtures/*Aleo*.lean. ";
common += "Full Examples may stay Plan-FC (computed view / reserved Leo names) with honesty pins. ";
common += "Counter golden 870B must stay green. No snarkVM invent. deployable=false. ";
common += "AGENTS keep Solana #111-#125 digests SBOM 244 13/304 21/405. Never push. ";
common += "implemented=true when met; residual notes in blockers. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. git log -5; status; confirm multi-golden suite. ready. start=" + start_from,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# blocked\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " ";
    p += "Scope: ProofForgeV2/Targets/Aleo/** Tests/** testdata/golden/aleo-instructions-v1/** docs/** AGENTS.md supply-chain/** .grok/workflows/**. ";
    if do_commit { p += "ONE commit: " + commit_msg + " Never push. "; }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "ALEO-ADMIT-FIXTURES", "ADMIT-FIXTURES",
        "Promote admit-surface sources to durable suite fixtures (inline program text or Tests/Fixtures) for Accumulator-credit, OptionState entry-only, MapMini put-only. Each: product select→compile→capability→programFromCapabilityV1 / lower succeeds; structural IR asserts; G5-HARD. Document full Examples Plan-FC reasons (reserved add; computed views). Prefer not editing shared Examples. Update docs/backlog/AGENTS.",
        "feat(aleo): durable admit-surface Instructions fixtures", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked ADMIT\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "ADMIT-FIXTURES", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "ALEO-OPTION-COMPARE", "OPTION-COMPARE",
        "With locked Leo if available: capture optionstate-admit.compiled.aleo (and optional mapmini-admit) via compile profile; pin Plan→IR ≡ golden or structural equality. Tool MISSING → honest skip note in suite/docs. Counter golden unchanged.",
        "feat(aleo): OptionState admit locked-leo Instructions compare", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked COMPARE\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "OPTION-COMPARE", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -8; docs-check; AGENTS Next. remaining deferred. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Aleo admit fixtures\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
