let meta = #{
    name: "aleo-instructions-ir",
    description: "Aleo Instructions IR lane: IR-1 schema+Counter compiled.aleo golden, IR-2 Plan lower MVP, then control-flow/multi-leaf/effects/product cutover; sequential implement+commit, no push",
    when_to_use: "After ALEO-IR-0 plan docs/targets/09-aleo-instructions-lowering.md exists; advances ProgramV1 admit surface toward Aleo Instructions authority (not sole Leo source).",
    phases: [
        #{ title: "Preflight", detail: "plan present, Leo pin, dirty planning commit if needed" },
        #{ title: "IR-1", detail: "Schema+TextCodec+Counter compiled.aleo golden" },
        #{ title: "IR-2", detail: "Plan→Instructions Counter MVP" },
        #{ title: "IR-3", detail: "if/match/bounded-for instruction sequences" },
        #{ title: "IR-4", detail: "multi-leaf Map/Option/narrow" },
        #{ title: "IR-5", detail: "effects honesty FC matrix" },
        #{ title: "IR-6", detail: "product primary Instructions; Leo debug-only" },
        #{ title: "Close", detail: "docs/backlog/AGENTS honesty" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "plan_present", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "plan_present": #{ "type": "boolean" },
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
let start_from = if args == () || args.start_from == () { "IR-1" } else { args.start_from };
let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

fn phase_rank(name) {
    if name == "IR-1" { 0 }
    else if name == "IR-2" { 1 }
    else if name == "IR-3" { 2 }
    else if name == "IR-4" { 3 }
    else if name == "IR-5" { 4 }
    else if name == "IR-6" { 5 }
    else if name == "Close" { 6 }
    else { 0 }
}
let start_rank = phase_rank(start_from);
let stop_rank = phase_rank(stop_after);

let common = "";
common += "ProofForge Aleo Instructions IR lane. Shared worktree. ";
common += "Authority plan: docs/targets/09-aleo-instructions-lowering.md (ALEO-IR-0 done). ";
common += "Target authority = official Aleo Instructions (register IR), NOT long-term sole Leo source. ";
common += "Official pipeline: Leo → Aleo Instructions → AVM. PF author language remains ProgramV1 only. ";
common += "Existing: ProofForgeV2/Targets/Aleo/{EmitIRV1,LowerSemanticV1,ValidatePlanV1,FinalizeV1,PlanSchemaV1}.lean — Leo printer path. ";
common += "New modules under ProofForgeV2/Targets/Aleo/Instructions/ per plan. ";
common += "Golden dir: testdata/golden/aleo-instructions-v1/. Prefer Counter via product build + locked leo 4.0.2 compile profile to capture compiled.aleo. ";
common += "Tool: PROOF_FORGE_TOOL_ROOT or Tool Lock Leo 4.0.2; never invent snarkVM/prove/deploy. deployable=false. ";
common += "Psy DPN lane idle — do not expand Psy. Never formal/release/push/force/amend/reset --hard. ";
common += "Local commit exact messages; just sbom-package-files-refresh after product Lean; just docs-check after docs. ";
common += "Tests: new Tests/Materialization/AleoInstructionsV1.lean (or similar) + wire into lakefile/Tests if required. ";
common += "implemented=true when slice met; residual notes only in blockers. ";
common += "Keep Solana #111-#125 digests/SBOM pins in AGENTS if editing Active row (docs-check). ";

phase("Preflight");
let pre = agent(common + "READ-ONLY/execute. git status; rev-parse HEAD; confirm 09-aleo-instructions-lowering.md exists. plan_present=true if plan file present. If uncommitted ALEO-IR-0 docs dirty, note in plan (IR-1 agent may commit them with IR-1 or separate docs commit). ready if IR-1 can start. start=" + start_from + " stop=" + stop_after,
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# Aleo IR blocked preflight\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}
log("Preflight " + pre.output.head);
let phase_results = [];

fn run_slice(common_text, slice_id, title, objective, commit_msg, do_commit, impl_schema) {
    phase(title);
    let p = common_text + "IMPLEMENT " + slice_id + ". " + objective + " ";
    p += "Scope: ProofForgeV2/Targets/Aleo/** Tests/Materialization/** testdata/golden/aleo-instructions-v1/** docs/** AGENTS.md supply-chain/** lakefile* Tests.lean Tests/Fast* .grok/workflows/**. ";
    p += "Update 09-aleo-instructions-lowering.md checkboxes, engineering-backlog ALEO-IR-*, AGENTS Active/Next accurately (preserve Solana checkpoint pins). ";
    if do_commit {
        p += "ONE local commit EXACT message: " + commit_msg + " git add -- paths only. Never push. If already on HEAD, verify tests + implemented=true. ";
    }
    let impl = agent(p, #{ label: "impl:" + slice_id, phase: title, capability_mode: "all", output_schema: impl_schema });
    if impl == () || !impl.success || impl.output.implemented != true {
        return #{ status: "blocked", slice: slice_id, detail: impl };
    }
    if impl.output.blockers.len() != 0 { log(slice_id + " residual " + json_encode(impl.output.blockers)); }
    return #{ status: "ok", slice: slice_id, impl: impl.output };
}

// IR-1
if start_rank <= 0 && stop_rank >= 0 {
    let r = run_slice(common, "ALEO-IR-1", "IR-1",
        "SchemaV1 + TextCodecV1 for Aleo Instructions subset (program header, function, input/output, core opcodes, mapping ops as needed). Capture Counter compiled.aleo golden via locked leo build on product Aleo Counter (compile profile aleo-leo-4.0.2-u64-compile-v1) into testdata/golden/aleo-instructions-v1/. Hand-built or decoded structure ≡ golden; encode round-trip. Wire facade import + tests. Commit any pending ALEO-IR-0 docs with this slice or first. NOT Plan→IR lower yet (that is IR-2).",
        "feat(aleo): Instructions Schema + Counter golden (ALEO-IR-1)", !skip_commit, phase_schema);
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

// IR-2
if start_rank <= 1 && stop_rank >= 1 {
    let r = run_slice(common, "ALEO-IR-2", "IR-2",
        "LowerPlanV1: AleoPlan Counter shape (init store, checkedAdd mutate, view load) → Instructions program structurally ≡ Counter golden. packageFromCapability or planFromCapability path for tests. Document default vs compile profile. Keep Leo EmitIR path working. Fail closed unsupported.",
        "feat(aleo): Plan→Instructions Counter MVP (ALEO-IR-2)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-2\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-2", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 1 {
    let report = "# stopped IR-2\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

// IR-3
if start_rank <= 2 && stop_rank >= 2 {
    let r = run_slice(common, "ALEO-IR-3", "IR-3",
        "Lower if/match and bounded for to instruction sequences matching existing Aleo Plan/Leo semantics (static unroll if needed). Tests structural. Fail closed unbounded.",
        "feat(aleo): Instructions if/match/for lowering (ALEO-IR-3)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-3\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-3", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 2 {
    let report = "# stopped IR-3\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

// IR-4
if start_rank <= 3 && stop_rank >= 3 {
    let r = run_slice(common, "ALEO-IR-4", "IR-4",
        "Multi-leaf flatten (Array/Option/Map cap-2/narrow widths) already admitted on Leo path → Instructions via same mapping layout. Structural product tests. Nested Map etc stay FC.",
        "feat(aleo): Instructions multi-leaf Map/Option (ALEO-IR-4)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-4\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-4", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 3 {
    let report = "# stopped IR-4\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

// IR-5
if start_rank <= 4 && stop_rank >= 4 {
    let r = run_slice(common, "ALEO-IR-5", "IR-5",
        "Effects honesty: emit/call/schedule/assets/context/record stay FC with stable diagnostics at Instructions lower (or document PARTIAL only with evidence). Tests pin FC. No maturity inflation.",
        "feat(aleo): Instructions effects honesty matrix (ALEO-IR-5)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-5\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-5", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}
if stop_rank <= 4 {
    let report = "# stopped IR-5\n" + json_encode(phase_results);
    complete(#{ status: "stopped", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}

// IR-6
if start_rank <= 5 && stop_rank >= 5 {
    let r = run_slice(common, "ALEO-IR-6", "IR-6",
        "Product cutover: materialize primary Aleo Instructions artifact when lower succeeds; Leo source debug-only via env/flag (document name). Finalize notes; deployable=false. Dual-write transition OK. Compile profile may still leo-build for compare.",
        "feat(aleo): Instructions product primary artifact (ALEO-IR-6)", !skip_commit, phase_schema);
    phase_results.push(r);
    if r.status != "ok" {
        let report = "# blocked IR-6\n" + json_encode(r);
        complete(#{ status: "blocked", stage: "IR-6", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
    }
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -15; status. Update plan checkboxes G-ladder, backlog, AGENTS Next. docs-check. Docs commit if needed: docs(aleo): Instructions IR closeout. remaining=IR-7 runtime, full opcode, record, prove. phases=" + json_encode(phase_results),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(phase_results);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report, phases: phase_results });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Aleo Instructions IR\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n\n## Phases\n" + json_encode(phase_results) + "\n\n## Remaining\n" + json_encode(close.output.remaining) + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, phases: phase_results, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
