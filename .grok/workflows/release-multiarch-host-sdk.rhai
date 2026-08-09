let meta = #{
    name: "release-multiarch-host-sdk",
    description: "darwin-arm64 CLI matrix + Host SDK pip wheel + fix CI so engineering tags publish",
    when_to_use: "Ship multi-arch engineering-dist releases with CLI, Author, and Host SDK assets.",
    phases: [
        #{ title: "Preflight", detail: "release workflow + VERSION gates" },
        #{ title: "CI-Matrix", detail: "linux + darwin-arm64 package jobs + publish" },
        #{ title: "Host-SDK", detail: "pyproject + package_host_sdk + smoke" },
        #{ title: "Smoke", detail: "local package smokes + docs-check" },
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
    "Read-only: .github/workflows/release-engineering-dist.yml, VERSION, package_cli_dist.sh platform_id, tools/sdk. Report gaps for multi-arch + pip. implemented=true if work can proceed.",
    #{ label: "preflight", capability_mode: "read-only", output_schema: phase_schema },
);
if pre == () || pre.success == false || pre.output == () || pre.output.implemented == false {
    complete(#{ summary: "preflight failed", phase: pre });
}

phase("CI-Matrix");
let c = agent(
    "Implement/verify release-engineering-dist.yml: matrix ubuntu-latest=linux-x86_64 and macos-14=darwin-arm64 for CLI package; separate portable job for author+host sdk; publish job downloads all artifacts and softprops release with fail_on_unmatched_files; tag must match VERSION (v0.1.0). engineering-dist prerelease only. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "ci-matrix", capability_mode: "all", output_schema: phase_schema },
);
if c == () || c.success == false || c.output == () || c.output.implemented == false {
    complete(#{ summary: "CI-Matrix incomplete", phase: c });
}

phase("Host-SDK");
let h = agent(
    "Implement/verify tools/sdk/pyproject.toml, scripts/package_host_sdk.sh, package_host_sdk_smoke, just recipes, SDK README install from wheel. Version from repo VERSION. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "host-sdk", capability_mode: "all", output_schema: phase_schema },
);
if h == () || h.success == false || h.output == () || h.output.implemented == false {
    complete(#{ summary: "Host-SDK incomplete", phase: h });
}

phase("Smoke");
let s = agent(
    "Run just package-host-sdk-smoke, just package-cli-smoke if feasible, just docs-check. Update docs/product/05. implemented=true with real evidence.",
    #{ label: "smoke", capability_mode: "all", output_schema: phase_schema },
);
if s == () || s.success == false || s.output == () || s.output.implemented == false {
    complete(#{ summary: "Smoke incomplete", phase: s });
}

phase("Close");
let close = agent(
    "Closeout: multi-arch engineering Release + host wheel. Remaining PyPI/Reservoir/formal. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
