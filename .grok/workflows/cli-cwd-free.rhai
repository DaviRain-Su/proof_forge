let meta = #{
    name: "cli-cwd-free",
    description: "REL-CWD-0: package-root resolution for doctor/install/local without monorepo CWD",
    when_to_use: "Make engineering CLI dist work from any working directory. Authority: docs/product/05-distribution-and-packages.md §9.4.",
    phases: [
        #{ title: "Preflight", detail: "current CWD script discovery" },
        #{ title: "Resolve", detail: "PackageRootV1 PROOF_FORGE_ROOT / bin parent / CWD" },
        #{ title: "Package", detail: "ship scripts+locks in package-cli dist" },
        #{ title: "Smoke", detail: "foreign CWD doctor + docs-check" },
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
        "remaining": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};

phase("Preflight");
let pre = agent(
    "Read-only: ProofForgeV2/CLI/Main.lean doctor/install/local CWD usage; package_cli_dist.sh; docs/product/05. Return implemented=true if CWD-free work can proceed.",
    #{ label: "preflight", capability_mode: "read-only", output_schema: phase_schema },
);
if pre == () || pre.success == false || pre.output == () || pre.output.implemented == false {
    complete(#{ summary: "preflight failed", phase: pre });
}

phase("Resolve");
let r = agent(
    "Implement or verify PackageRootV1: PROOF_FORGE_ROOT absolute → parent of IO.appDir when scripts/ present → CWD. Wire doctor/install/local/network to resolve package root and spawn with cwd=packageRoot; local sets PROOF_FORGE_CLI/PROOF_FORGE_ROOT for children. Update usage notes. lake build proof_forge_next. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "resolve", capability_mode: "all", output_schema: phase_schema },
);
if r == () || r.success == false || r.output == () || r.output.implemented == false {
    complete(#{ summary: "Resolve incomplete", phase: r });
}

phase("Package");
let p = agent(
    "package_cli_dist.sh must ship scripts (doctor/install/toolchain_assets/aleo_local_sandbox/…) and toolchains*.lock.json + host-profiles.lock.json. aleo_local_sandbox prefers PROOF_FORGE_CLI and <root>/bin/proof-forge-next. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "package", capability_mode: "all", output_schema: phase_schema },
);
if p == () || p.success == false || p.output == () || p.output.implemented == false {
    complete(#{ summary: "Package incomplete", phase: p });
}

phase("Smoke");
let s = agent(
    "Run just package-cli-cwd-free-smoke and just docs-check. implemented=true only with real evidence.",
    #{ label: "smoke", capability_mode: "all", output_schema: phase_schema },
);
if s == () || s.success == false || s.output == () || s.output.implemented == false {
    complete(#{ summary: "Smoke incomplete", phase: s });
}

phase("Close");
let close = agent(
    "Closeout CWD-free engineering-dist. Remaining: darwin matrix, pip, formal. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
