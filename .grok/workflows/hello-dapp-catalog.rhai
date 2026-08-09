let meta = #{
    name: "hello-dapp-catalog",
    description: "Hello dApp agent playbook + multi-chain client catalog (MCP/SDK). Not formal/network.",
    when_to_use: "After external ProgramV1 template: agent playbook and pf_chain_catalog metadata. Authority: docs/product/03-hello-dapp-agent-playbook.md + 04-chain-client-catalog.md.",
    phases: [
        #{ title: "Preflight", detail: "existing external template + MCP surface" },
        #{ title: "Playbook", detail: "03-hello-dapp-agent-playbook.md" },
        #{ title: "Catalog", detail: "JSON + 04 doc + pf_chain_catalog + SDK" },
        #{ title: "Smoke", detail: "sdk/mcp smoke + docs-check" },
        #{ title: "Close", detail: "honesty residual" },
    ],
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
    "required": ["passed", "summary", "remaining"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "remaining": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
    },
};

phase("Preflight");
let pre = agent(
    "Read-only: confirm templates/external-aleo-hello and pf_local exist. ready path for hello playbook + catalog. No edits. Return implemented=true if baseline ok, summary, files_changed=[], tests_run=[], blockers.",
    #{ label: "preflight", capability_mode: "read-only", output_schema: phase_schema },
);
if pre == () || pre.success == false || pre.output == () || pre.output.implemented == false {
    complete(#{ summary: "preflight failed", phase: pre });
}

phase("Playbook");
let p1 = agent(
    "Verify or create docs/product/03-hello-dapp-agent-playbook.md: MCP order doctor→install→build/local→artifacts; no broadcast; Aleo hello with --root; link template. Update docs/index.md pointer. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "playbook", capability_mode: "all", output_schema: phase_schema },
);
if p1 == () || p1.success == false || p1.output == () || p1.output.implemented == false {
    complete(#{ summary: "Playbook incomplete", phase: p1 });
}

phase("Catalog");
let p2 = agent(
    "Verify docs/product/chain-client-catalog.v1.json schema proof-forge.chain-client-catalog.v1, 04-chain-client-catalog.md, MCP pf_chain_catalog, SDK chain_catalog. No network tool. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "catalog", capability_mode: "all", output_schema: phase_schema },
);
if p2 == () || p2.success == false || p2.output == () || p2.output.implemented == false {
    complete(#{ summary: "Catalog incomplete", phase: p2 });
}

phase("Smoke");
let p3 = agent(
    "Run scripts/sdk_smoke.sh, scripts/mcp_smoke.sh, just docs-check. implemented=true only with real evidence. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "smoke", capability_mode: "all", output_schema: phase_schema },
);
if p3 == () || p3.success == false || p3.output == () || p3.output.implemented == false {
    complete(#{ summary: "Smoke incomplete", phase: p3 });
}

phase("Close");
let close = agent(
    "Closeout: deployable=false, no MCP broadcast, catalog is metadata only, formal last. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
