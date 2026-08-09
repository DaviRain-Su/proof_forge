let meta = #{
    name: "external-program-v1",
    description: "External ProgramV1 project: template + --root build/sandbox + SDK/MCP + hello smoke. Not formal/network.",
    when_to_use: "Author path outside monorepo Examples: copy template, build/sandbox Aleo via CLI/SDK/MCP. Authority: docs/product/02-external-program-v1.md.",
    phases: [
        #{ title: "Preflight", detail: "CLI --root + sandbox + product docs baseline" },
        #{ title: "DOC", detail: "02-external-program-v1 + index pointer" },
        #{ title: "TEMPLATE", detail: "templates/external-aleo-hello minimal ProgramV1" },
        #{ title: "SANDBOX-ROOT", detail: "aleo_local_sandbox --root for external projects" },
        #{ title: "SDK-MCP-ROOT", detail: "local/pf_local pass --root" },
        #{ title: "SMOKE", detail: "external_hello_smoke + docs-check" },
        #{ title: "Close", detail: "honesty + residual (Lake SDK, network, formal)" },
    ],
};

let preflight_schema = #{
    "type": "object",
    "required": ["ready", "reason", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};

let phase_schema = #{
    "type": "object",
    "required": ["implemented", "summary", "files_changed", "tests_run", "blockers"],
    "properties": #{
        "implemented": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};

let close_schema = #{
    "type": "object",
    "required": ["passed", "summary", "remaining", "commands"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "remaining": #{ "type": "array", "maxItems": 24, "items": #{ "type": "string" } },
        "commands": #{ "type": "array", "maxItems": 20, "items": #{
            "type": "object", "required": ["command", "result"],
            "properties": #{
                "command": #{ "type": "string" },
                "result": #{ "type": "string" },
            },
        }},
    },
};

let stop_after = if args == () || args.stop_after == () { "Close" } else { args.stop_after };

fn rank(name) {
    if name == "DOC" { 0 }
    else if name == "TEMPLATE" { 1 }
    else if name == "SANDBOX-ROOT" { 2 }
    else if name == "SDK-MCP-ROOT" { 3 }
    else if name == "SMOKE" { 4 }
    else if name == "Close" { 5 }
    else { 99 }
}

let stop_rank = rank(stop_after);

phase("Preflight");
let pre_prompt = "";
pre_prompt += "Read-only preflight for external ProgramV1 author path on ProofForge V2.\n";
pre_prompt += "Use tools: git status --short; read docs/product/01-toolchain-install-surface.md; ";
pre_prompt += "docs/targets/09b-aleo-local-sandbox.md; scripts/aleo_local_sandbox.sh; ";
pre_prompt += "templates/ if present; tools/sdk/proof_forge_sdk.py; tools/mcp/proof_forge_mcp_server.py.\n";
pre_prompt += "Goal: authors build ProgramV1 outside monorepo Examples via --root + CLI/sandbox/SDK/MCP.\n";
pre_prompt += "ready=true if baseline product CLI exists and work can proceed. No edits.\n";
pre_prompt += "Do not claim formal/mainnet/deployable.\n";
let pre = agent(pre_prompt, #{
    label: "preflight",
    capability_mode: "read-only",
    output_schema: preflight_schema,
});
if pre == () || pre.success == false || pre.output == () {
    complete(#{ summary: "preflight failed", passed: false });
}
if pre.output.ready == false {
    complete(#{ summary: "not ready: " + pre.output.reason, blockers: pre.output.blockers, passed: false });
}

if stop_rank >= 0 {
    phase("DOC");
    let p = "";
    p += "Ensure docs/product/02-external-program-v1.md exists as authority for external ProgramV1 projects:\n";
    p += "source gate import ProofForgeV2; --source relative --root; build/sandbox/SDK/MCP ladder; ";
    p += "template pointer; non-goals (no Lake SDK required, no deployable, no formal).\n";
    p += "Add index.md pointer if missing. just docs-check after edits.\n";
    p += "Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r = agent(p, #{ label: "doc", capability_mode: "all", output_schema: phase_schema });
    if r == () || r.success == false || r.output == () || r.output.implemented == false {
        complete(#{ summary: "DOC incomplete", phase: r });
    }
}

if stop_rank >= 1 {
    phase("TEMPLATE");
    let p = "";
    p += "Ensure templates/external-aleo-hello/ exists with src/Hello.lean (import ProofForgeV2 + ";
    p += "program Hello UInt64 counter init/increment/get) and README with build/sandbox/SDK commands.\n";
    p += "No Lake package required. Not Counter-hardcoded engine — Hello is a template sample only.\n";
    p += "Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r = agent(p, #{ label: "template", capability_mode: "all", output_schema: phase_schema });
    if r == () || r.success == false || r.output == () || r.output.implemented == false {
        complete(#{ summary: "TEMPLATE incomplete", phase: r });
    }
}

if stop_rank >= 2 {
    phase("SANDBOX-ROOT");
    let p = "";
    p += "Ensure scripts/aleo_local_sandbox.sh accepts --root DIR, rewrites --source as project-relative, ";
    p += "passes --root to product build. In-repo Examples/Counter --skip-run still works. ";
    p += "External temp Hello with --root must LOCAL-SANDBOX-OK. Update 09b docs for --root.\n";
    p += "Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r = agent(p, #{ label: "sandbox-root", capability_mode: "all", output_schema: phase_schema });
    if r == () || r.success == false || r.output == () || r.output.implemented == false {
        complete(#{ summary: "SANDBOX-ROOT incomplete", phase: r });
    }
}

if stop_rank >= 3 {
    phase("SDK-MCP-ROOT");
    let p = "";
    p += "ProofForgeClient.local and MCP pf_local must pass --root when provided. Update READMEs.\n";
    p += "Reject broadcast/private-key still. self-check still ok.\n";
    p += "Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r = agent(p, #{ label: "sdk-mcp-root", capability_mode: "all", output_schema: phase_schema });
    if r == () || r.success == false || r.output == () || r.output.implemented == false {
        complete(#{ summary: "SDK-MCP-ROOT incomplete", phase: r });
    }
}

if stop_rank >= 4 {
    phase("SMOKE");
    let p = "";
    p += "Ensure scripts/external_hello_smoke.sh copies template → build --root → sandbox. ";
    p += "just external-hello-smoke recipe. Run: bash scripts/external_hello_smoke.sh (or --skip-run if no leo). ";
    p += "Also scripts/mcp_smoke.sh, scripts/sdk_smoke.sh, just docs-check as available.\n";
    p += "implemented=true only with real command evidence.\n";
    let r = agent(p, #{ label: "smoke", capability_mode: "all", output_schema: phase_schema });
    if r == () || r.success == false || r.output == () || r.output.implemented == false {
        complete(#{ summary: "SMOKE incomplete", phase: r });
    }
}

phase("Close");
let p5 = "";
p5 += "Closeout external ProgramV1 slice. Honesty: deployable=false; offline leo only; no network in MCP; ";
p5 += "formal last. Remaining: multi-chain frontend catalog, network demo, Lake syntax package optional.\n";
p5 += "Return passed, summary, remaining, commands with real results if you ran them.\n";
let close = agent(p5, #{
    label: "close",
    capability_mode: "read-only",
    output_schema: close_schema,
});
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
