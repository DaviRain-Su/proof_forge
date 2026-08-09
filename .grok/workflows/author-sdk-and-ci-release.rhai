let meta = #{
    name: "author-sdk-and-ci-release",
    description: "REL-AUTHOR-0 Lean Author SDK package + REL-CI-0 engineering-dist GitHub Release workflow",
    when_to_use: "Publish lean author package and wire CI to ship CLI+author tarballs on v* tags. Not formal Stage-0.",
    phases: [
        #{ title: "Preflight", detail: "VERSION + package scripts baseline" },
        #{ title: "Author-SDK", detail: "package_author_sdk + smoke lake build" },
        #{ title: "CI-Release", detail: "release-engineering-dist.yml on v* tags" },
        #{ title: "Docs", detail: "05-distribution update" },
        #{ title: "Smoke", detail: "package smokes + docs-check" },
        #{ title: "Close", detail: "engineering-dist honesty" },
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
    "Read-only: VERSION, docs/product/05-distribution-and-packages.md, scripts/package_cli_dist.sh, whether package_author_sdk and release-engineering-dist.yml exist. Return implemented=true if work can proceed.",
    #{ label: "preflight", capability_mode: "read-only", output_schema: phase_schema },
);
if pre == () || pre.success == false || pre.output == () || pre.output.implemented == false {
    complete(#{ summary: "preflight failed", phase: pre });
}

phase("Author-SDK");
let a = agent(
    "Implement or verify REL-AUTHOR-0: scripts/package_author_sdk.py builds Syntax import closure into dist/proof-forge-author-<ver> with thin ProofForgeV2.lean, lakefile, tarball+sha256; just package-author-sdk and package-author-sdk-smoke (lake build author + consumer path-require). No materializers. engineering-dist only. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "author-sdk", capability_mode: "all", output_schema: phase_schema },
);
if a == () || a.success == false || a.output == () || a.output.implemented == false {
    complete(#{ summary: "Author-SDK incomplete", phase: a });
}

phase("CI-Release");
let c = agent(
    "Implement or verify .github/workflows/release-engineering-dist.yml: on tag v* and workflow_dispatch, install lean, lake build proof_forge_next, package-cli + package-author-sdk, upload artifacts, softprops gh-release with prerelease body stating engineering-dist NOT formal Stage-0. Pin actions by commit SHA like ci.yml. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "ci-release", capability_mode: "all", output_schema: phase_schema },
);
if c == () || c.success == false || c.output == () || c.output.implemented == false {
    complete(#{ summary: "CI-Release incomplete", phase: c });
}

phase("Docs");
let d = agent(
    "Update docs/product/05-distribution-and-packages.md and 01-toolchain-install-surface + index if needed for Author SDK and CI release. just docs-check. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "docs", capability_mode: "all", output_schema: phase_schema },
);
if d == () || d.success == false || d.output == () || d.output.implemented == false {
    complete(#{ summary: "Docs incomplete", phase: d });
}

phase("Smoke");
let s = agent(
    "Run just package-author-sdk-smoke (and package-cli-smoke if binary present), just docs-check. implemented=true only with real evidence.",
    #{ label: "smoke", capability_mode: "all", output_schema: phase_schema },
);
if s == () || s.success == false || s.output == () || s.output.implemented == false {
    complete(#{ summary: "Smoke incomplete", phase: s });
}

phase("Close");
let close = agent(
    "Closeout: engineering-dist CLI+Author via CI tags; remaining CWD-free install, darwin matrix, pip, formal. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
