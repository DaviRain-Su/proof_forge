let meta = #{
    name: "aleo-product-ladder",
    description: "Aleo product ladder: generic local sandbox → CLI/SDK/MCP local → optional network residual. Not formal/release. No Counter lock-in.",
    when_to_use: "Advance Aleo author/agent path: any ProgramV1 → sandbox offline run → SDK/MCP; formal and mainnet last. Authority: docs/targets/09b-aleo-local-sandbox.md + docs/product/01-toolchain-install-surface.md.",
    phases: [
        #{ title: "Preflight", detail: "repo + sandbox script + CLI surface" },
        #{ title: "Sandbox-Generic", detail: "aleo_local_sandbox.sh requires source/module; discover program id" },
        #{ title: "CLI-Local", detail: "proof-forge-next local --target aleo forwards generic args" },
        #{ title: "SDK-MCP", detail: "ProofForgeClient.local + pf_local; reject broadcast" },
        #{ title: "Smoke", detail: "mcp_smoke/sdk_smoke/local_network_smoke + docs-check" },
        #{ title: "Close", detail: "honesty boundaries + residual backlog" },
    ],
};

let preflight_schema = #{
    "type": "object",
    "required": ["ready", "reason", "sandbox_generic", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "sandbox_generic": #{ "type": "boolean" },
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

// Args: stop_after (Sandbox-Generic | CLI-Local | SDK-MCP | Smoke | Close)
let stop_after = if args == () || args.stop_after == () { "Smoke" } else { args.stop_after };

fn rank(name) {
    if name == "Sandbox-Generic" { 0 }
    else if name == "CLI-Local" { 1 }
    else if name == "SDK-MCP" { 2 }
    else if name == "Smoke" { 3 }
    else if name == "Close" { 4 }
    else { 99 }
}

let stop_rank = rank(stop_after);

phase("Preflight");
let pre_prompt = "";
pre_prompt += "You are on ProofForge V2. Read-only preflight for Aleo product ladder.\n";
pre_prompt += "Use tools: git status --short, read docs/targets/09b-aleo-local-sandbox.md, ";
pre_prompt += "scripts/aleo_local_sandbox.sh, tools/sdk/proof_forge_sdk.py, tools/mcp/proof_forge_mcp_server.py, ";
pre_prompt += "docs/product/01-toolchain-install-surface.md.\n";
pre_prompt += "Confirm sandbox is GENERIC: requires --source and --module; no hardcoded Counter ";
pre_prompt += "entrypoints or golden unless --golden/--run supplied by caller.\n";
pre_prompt += "Set sandbox_generic=true only if script enforces that. List blockers only from code/docs.\n";
pre_prompt += "Do not edit files. Do not claim formal/mainnet/deployable.\n";
let pre = agent(pre_prompt, #{
    label: "preflight",
    capability_mode: "read-only",
    output_schema: preflight_schema,
});
if pre == () || pre.success == false || pre.output == () {
    complete(#{ summary: "preflight agent failed", passed: false });
}
if pre.output.ready == false {
    complete(#{
        summary: "preflight not ready: " + pre.output.reason,
        passed: false,
        blockers: pre.output.blockers,
    });
}
log("preflight ok; sandbox_generic=" + pre.output.sandbox_generic.to_string());

if stop_rank >= 0 {
    phase("Sandbox-Generic");
    let p1 = "";
    p1 += "Implement or verify GENERIC Aleo local sandbox (no Counter lock-in).\n";
    p1 += "Authority: docs/targets/09b-aleo-local-sandbox.md\n";
    p1 += "Script: scripts/aleo_local_sandbox.sh must require --source and --module; ";
    p1 += "discover primary {id}.aleo from OutputSet; stage Leo package from {id}.leo; ";
    p1 += "optional --golden pin; optional repeatable --run 'name args'; ";
    p1 += "no default initialize/increment. justfile: aleo-sandbox *ARGS forwards args.\n";
    p1 += "Update docs/targets/09b-aleo-local-sandbox.md and docs/index.md honesty.\n";
    p1 += "Run: bash -n scripts/aleo_local_sandbox.sh; script --help; script --skip-run must exit 2 usage.\n";
    p1 += "Do not add formal/release work. Do not set deployable=true.\n";
    p1 += "Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r1 = agent(p1, #{
        label: "sandbox-generic",
        capability_mode: "all",
        output_schema: phase_schema,
    });
    if r1 == () || r1.success == false || r1.output == () || r1.output.implemented == false {
        complete(#{ summary: "Sandbox-Generic incomplete", phase: r1 });
    }
}

if stop_rank >= 1 {
    phase("CLI-Local");
    let p2 = "";
    p2 += "Verify product CLI local --target aleo --mode sandbox forwards generic script args ";
    p2 += "after --. Update scripts/local_network_smoke.sh: missing-tool path must pass ";
    p2 += "--source and --module; add usage fail-closed smoke when they are omitted.\n";
    p2 += "Do not invent network broadcast. Keep deployable=false.\n";
    p2 += "Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r2 = agent(p2, #{
        label: "cli-local",
        capability_mode: "all",
        output_schema: phase_schema,
    });
    if r2 == () || r2.success == false || r2.output == () || r2.output.implemented == false {
        complete(#{ summary: "CLI-Local incomplete", phase: r2 });
    }
}

if stop_rank >= 2 {
    phase("SDK-MCP");
    let p3 = "";
    p3 += "Wire generic local into SDK and MCP:\n";
    p3 += "- tools/sdk/proof_forge_sdk.py: ProofForgeClient.local(... source, module, runs, skip_run, golden); ";
    p3 += "reject broadcast/private-key; self_check methods include local.\n";
    p3 += "- tools/mcp/proof_forge_mcp_server.py: pf_local tool; aleo sandbox requires source+module; ";
    p3 += "reject broadcast/secrets.\n";
    p3 += "Update tools/sdk/README.md, tools/mcp/README.md, docs/product/01-toolchain-install-surface.md.\n";
    p3 += "Update scripts/sdk_smoke.sh and scripts/mcp_smoke.sh for local/pf_local.\n";
    p3 += "No second compiler. No network tool. Return implemented, summary, files_changed, tests_run, blockers.\n";
    let r3 = agent(p3, #{
        label: "sdk-mcp",
        capability_mode: "all",
        output_schema: phase_schema,
    });
    if r3 == () || r3.success == false || r3.output == () || r3.output.implemented == false {
        complete(#{ summary: "SDK-MCP incomplete", phase: r3 });
    }
}

if stop_rank >= 3 {
    phase("Smoke");
    let p4 = "";
    p4 += "Run focused smokes from package root (not host-heavy full leo run unless tools present):\n";
    p4 += "1) /usr/bin/python3 -I tools/mcp/proof_forge_mcp_server.py --self-check\n";
    p4 += "2) /usr/bin/python3 -I tools/sdk/proof_forge_sdk.py --self-check\n";
    p4 += "3) scripts/mcp_smoke.sh (if proof-forge-next built)\n";
    p4 += "4) scripts/sdk_smoke.sh\n";
    p4 += "5) scripts/local_network_smoke.sh if CLI present\n";
    p4 += "6) just docs-check if available\n";
    p4 += "Report real command results. Do not claim ordinary ci full green without running it.\n";
    p4 += "Return implemented=true only if critical smokes you could run passed; else blockers.\n";
    let r4 = agent(p4, #{
        label: "smoke",
        capability_mode: "all",
        output_schema: phase_schema,
    });
    if r4 == () || r4.success == false || r4.output == () || r4.output.implemented == false {
        complete(#{ summary: "Smoke incomplete", phase: r4 });
    }
}

phase("Close");
let p5 = "";
p5 += "Write a short closeout for Aleo product ladder work done in this tree.\n";
p5 += "Honesty: deployable=false; LEO-OFFLINE-RUN is local interpret; IR-7 snarkVM still MISSING; ";
p5 += "network N1-E is separate; formal/release last; MCP has no broadcast.\n";
p5 += "Remaining should list concrete next items only (e.g. live leo run on a real program, ";
p5 += "Lean external project template, multi-chain frontend catalog) — not formal TASK invent.\n";
p5 += "Use tools to list changed files if helpful. Return passed, summary, remaining, commands.\n";
let close = agent(p5, #{
    label: "close",
    capability_mode: "read-only",
    output_schema: close_schema,
});
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close agent failed", passed: false });
}
complete(close.output);
