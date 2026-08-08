let meta = #{
    name: "noir-acir-g3",
    description: "Noir ACIR post-IR-2: IR-3 control/aggregate capture pins, IR-5 honesty matrix, IR-6 product primary ACIR optional; sequential commit",
    when_to_use: "After NOIR-IR-0/1/2 nargo-assisted Counter golden; expands G3 admit surface and optional product ACIR primary.",
    phases: [
        #{ title: "Preflight", detail: "IR-2 CaptureV1 + golden present" },
        #{ title: "IR-3", detail: "CF/aggregate nargo-assisted capture pins" },
        #{ title: "IR-5", detail: "admit honesty matrix pins" },
        #{ title: "IR-6", detail: "product primary ACIR or honest dual-write plan" },
        #{ title: "Close", detail: "docs/AGENTS" },
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

let stop_after = if args == () || args.stop_after == () { "IR-6" } else { args.stop_after };
let start_from = if args == () || args.start_from == () { "IR-3" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "IR-3" { 0 }
    else if name == "IR-5" { 1 }
    else if name == "IR-6" { 2 }
    else if name == "Close" { 3 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Noir ACIR G3+ lane. Shared worktree. Plan: docs/targets/07-noir-acir-lowering.md. ";
common += "Authority path = nargo-assisted CaptureV1 (NOT pure-Lean ACIR opcode encoder). ";
common += "IR-1 golden noir-acir-v1 Counter inventory; IR-2 product Plan source-join + capture ≡ golden. ";
common += "Expand admit-surface fixtures with capture success pins; nargo missing = honest skip for live paths. ";
common += "deployable=false; no prove/verify product claim; no invent backend. Aleo/Psy idle. ";
common += "AGENTS keep Solana #111-#125 digests SBOM 244 13/304 21/405. Never push. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. Confirm CaptureV1 + golden. ready. start=" + start_from,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# blocked\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " ";
    p += "Scope: ProofForgeV2/Targets/Noir/** Tests/Materialization/** testdata/golden/noir-acir-v1/** docs/** AGENTS.md supply-chain/** .grok/workflows/**. ";
    if do_commit { p += "ONE commit: " + commit_msg + " Never push. "; }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "NOIR-IR-3", "IR-3",
        "G3: nargo-assisted capture pins for Noir-admitted control-flow/aggregate fixtures (e.g. LoopSum if Plan admits, MapMini/OptionState as Noir admits, Branch/if products). Extend NoirAcirV1: product materialize packages + optional live capture circuit core stable (hash pin or structural). Counter golden regression. Document nargo skip. Update plan G3 checkbox.",
        "feat(noir): ACIR admit-surface CF/aggregate capture pins (NOIR-IR-3)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-3\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-3", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 0 {
    let report = "# stopped\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "NOIR-IR-5", "IR-5",
        "Honesty matrix for Noir ACIR path: pin call/schedule/Option-String/prove FC boundaries in NoirAcirV1 + plan §3.2 status column. No false Y. Counter green.",
        "feat(noir): ACIR honesty matrix pins (NOIR-IR-5)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-5\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-5", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "NOIR-IR-6", "IR-6",
        "Product primary ACIR path if honest: emit compile inventory/ACIR artifact as product OutputFile (or dual-write Finalize extra) when nargo-assisted capture succeeds for Counter; .nr remains transitional/debug. If product OutputFile ACIR is too heavy/host-dependent for ordinary build, implement optional profile or document dual-write deferred with suite pin of capture authority — do not break zero-tool Finalize default. deployable=false.",
        "feat(noir): product ACIR primary or dual-write path (NOIR-IR-6)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-6\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-6", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -10; docs-check; AGENTS Next. remaining IR-7 prove. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Noir ACIR G3\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
