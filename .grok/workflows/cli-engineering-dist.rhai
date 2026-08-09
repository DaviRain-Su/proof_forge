let meta = #{
    name: "cli-engineering-dist",
    description: "REL-CLI-0/1: product version identity + engineering CLI tarball. Not formal Stage-0.",
    when_to_use: "Package proof-forge-next for external authors. Authority: docs/product/05-distribution-and-packages.md.",
    phases: [
        #{ title: "Preflight", detail: "VERSION + CLI surface" },
        #{ title: "REL-CLI-0", detail: "version / --version + ProductVersionV1" },
        #{ title: "REL-CLI-1", detail: "package_cli_dist.sh + just package-cli" },
        #{ title: "Smoke", detail: "package-cli-smoke + focused CLI tests" },
        #{ title: "Close", detail: "honesty: engineering-dist only" },
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
    "Read-only preflight for CLI engineering dist. Check VERSION, docs/product/05-distribution-and-packages.md, ProofForgeV2/CLI for version command, scripts/package_cli_dist.sh. Return implemented=true if work can proceed, summary, files_changed=[], tests_run=[], blockers. No formal Stage-0 claims.",
    #{ label: "preflight", capability_mode: "read-only", output_schema: phase_schema },
);
if pre == () || pre.success == false || pre.output == () || pre.output.implemented == false {
    complete(#{ summary: "preflight failed", phase: pre });
}

phase("REL-CLI-0");
let r0 = agent(
    "Implement or verify REL-CLI-0: repo VERSION file; ProofForgeV2/CLI/ProductVersionV1.lean with productVersionV1 matching VERSION; parseCliCommandV1 accepts version and --version with optional --json; schema proof-forge.cli.version.v1; channel engineering-dist; CLI.run prints human/json; usage mentions version; Tests/CLI/Emit parse pins. lake build proof_forge_next. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "rel-cli-0", capability_mode: "all", output_schema: phase_schema },
);
if r0 == () || r0.success == false || r0.output == () || r0.output.implemented == false {
    complete(#{ summary: "REL-CLI-0 incomplete", phase: r0 });
}

phase("REL-CLI-1");
let r1 = agent(
    "Implement or verify REL-CLI-1: scripts/package_cli_dist.sh produces dist tarball+sha256; gates VERSION==CLI version; just package-cli and package-cli-smoke; docs/product/05 §9 install path; does NOT claim formal Stage-0; does not bundle Tool Lock tools. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "rel-cli-1", capability_mode: "all", output_schema: phase_schema },
);
if r1 == () || r1.success == false || r1.output == () || r1.output.implemented == false {
    complete(#{ summary: "REL-CLI-1 incomplete", phase: r1 });
}

phase("Smoke");
let r2 = agent(
    "Run: lake build proof_forge_next (if needed); proof-forge-next version --json; just package-cli-smoke; just docs-check; focused CLI Emit tests if available. implemented=true only with real evidence. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "smoke", capability_mode: "all", output_schema: phase_schema },
);
if r2 == () || r2.success == false || r2.output == () || r2.output.implemented == false {
    complete(#{ summary: "Smoke incomplete", phase: r2 });
}

phase("Close");
let close = agent(
    "Closeout: engineering-dist only; not formal Stage-0; remaining Author SDK, pip, CWD-free install. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
