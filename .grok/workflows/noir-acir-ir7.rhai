let meta = #{
    name: "noir-acir-ir7",
    description: "Noir ACIR IR-7 prove honesty: probe Tool Lock for prove backend; pin PARTIAL/MISSING via just noir-runtime or suite; sequential commit",
    when_to_use: "After NOIR-IR-6 opt-in ACIR dual-write; G6 prove honesty without inventing Barretenberg/CRS.",
    phases: [
        #{ title: "Preflight", detail: "IR-6 present; tool probe" },
        #{ title: "IR-7", detail: "prove honesty pin + script/recipe" },
        #{ title: "Close", detail: "lane idle or next residual" },
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
common += "ProofForge Noir ACIR IR-7 prove honesty. Shared worktree. Plan 07-noir-acir-lowering.md G6/IR-7. ";
common += "IR-0..IR-6 done: nargo-assisted ACIR dual-write opt-in profile; default zero-tool .nr; deployable=false. ";
common += "Probe Tool Lock / PROOF_FORGE_TOOL_ROOT for bb/barretenberg/prove backend. ";
common += "If MISSING: scripts/noir_runtime_test.sh or similar + just noir-runtime → PF-TOOLCHAIN-MISSING; suite honesty notes; do NOT invent prove CLI or CRS. ";
common += "If present: minimal host-heavy Counter prove pin, not ordinary ci. ";
common += "AGENTS Solana digests SBOM 244. Never push. ";

phase("Preflight");
let pre = agent(common + "READ-ONLY. Confirm IR-6 profile; probe prove tools. ready.",
    #{ label: "preflight", phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if pre == () || !pre.success || pre.output.ready != true {
    let report = "# blocked\n" + json_encode(pre);
    complete(#{ status: "blocked", stage: "preflight", report_path: write_scratch_file("report.md", report), report: report });
}

phase("IR-7");
let impl_prompt = common;
impl_prompt += "IMPLEMENT NOIR-IR-7. Prove honesty pin as above. Update plan G6 checkbox, backlog, AGENTS Next=lane idle if done. ";
if !skip_commit {
    impl_prompt += "ONE commit: feat(noir): ACIR prove honesty pin (NOIR-IR-7). Never push. ";
}
let impl = agent(impl_prompt, #{ label: "impl:IR-7", phase: "IR-7", capability_mode: "all", output_schema: phase_schema });
if impl == () || !impl.success || impl.output.implemented != true {
    let report = "# blocked IR-7\n" + json_encode(impl);
    complete(#{ status: "blocked", stage: "IR-7", report_path: write_scratch_file("report.md", report), report: report });
}

phase("Close");
let close = agent(common + "CLOSEOUT. git log -8; docs-check. remaining deferred. IR-7 result: " + json_encode(impl.output),
    #{ label: "close", phase: "Close", capability_mode: "all", output_schema: close_schema });
if close == () || !close.success {
    let report = "# close fail\n" + json_encode(impl);
    complete(#{ status: "blocked", stage: "close", report_path: write_scratch_file("report.md", report), report: report });
}
let st = if close.output.passed == true { "completed" } else { "completed-with-gaps" };
let report = "# Noir IR-7\n\n**Status:** " + st + "\n\n" + close.output.summary + "\n";
complete(#{ status: st, report_path: write_scratch_file("report.md", report), report: report, remaining: close.output.remaining, head: close.output.head, agent_calls: budget().spent });
