let meta = #{
    name: "noir-acir-ir4",
    description: "Noir ACIR IR-4 multi-fixture inventory expansion + residual close; optional EVM IR-0 plan seed",
    when_to_use: "After NOIR-IR-7 idle; expands multi-fixture nargo inventory pins without full prove.",
    phases: [
        #{ title: "Preflight", detail: "IR-7 done; residual list" },
        #{ title: "IR-4", detail: "multi-fixture inventory/capture pins" },
        #{ title: "Close", detail: "docs idle or next target" },
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

let skip_commit = if args == () || args.skip_commit == () { false } else { args.skip_commit };

let common = "";
common += "ProofForge Noir ACIR IR-4 residual expansion. Shared worktree. ";
common += "IR-0..IR-7 done; path = nargo-assisted CaptureV1; Counter inventory golden; opt-in ACIR dual-write profile. ";
common += "IR-4: extend path-normalized multi-fixture compile inventory and/or capture pins for admit fixtures that already nargo-ok (Branch/LoopSum/Option/Array). MapMini residual honesty keep. ";
common += "Do not invent barretenberg. deployable=false. AGENTS Solana digests. Never push. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. Confirm IR-7 closeout. ready for IR-4.",
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# blocked\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}

phase("IR-4");
let p = common + "IMPLEMENT NOIR-IR-4 multi-fixture inventory/capture expansion. Update 07-noir-acir-lowering.md IR-4 checkbox. ";
if !skip_commit { p += "ONE commit: feat(noir): ACIR multi-fixture inventory pins (NOIR-IR-4). Never push. "; }
let impl = agent(p, #{ label: "impl:IR-4", phase: "IR-4", capability_mode: "all", output_schema: phase_schema });
if impl == () || !impl.success || impl.output.implemented != true {
    let report = "# blocked IR-4\n" + json_encode(impl);
    complete(#{ status: "blocked", stage: "IR-4", report_path: write_scratch_file("report.md", report), report: report });
}

phase("Close");
let close = agent(common + "CLOSEOUT. Optionally seed docs/targets plan for next target lower-IR (EVM bytecode authority) if Noir queue empty. docs-check. AGENTS Next. IR-4: " + json_encode(impl.output),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(impl);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Noir IR-4\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
