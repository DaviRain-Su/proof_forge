let meta = #{
    name: "pypi-host-sdk",
    description: "REL-HOST-1: publish proof-forge-sdk to PyPI via Trusted Publishing on v* tags",
    when_to_use: "Wire Host SDK PyPI upload into engineering-dist release CI and document publisher setup.",
    phases: [
        #{ title: "Preflight", detail: "host sdk package + release workflow" },
        #{ title: "Publish-Script", detail: "publish_host_sdk_pypi + dry-run twine check" },
        #{ title: "CI", detail: "publish-pypi job OIDC on tag only" },
        #{ title: "Docs", detail: "06-pypi-host-sdk + index" },
        #{ title: "Smoke", detail: "package + twine check + docs-check" },
        #{ title: "Close", detail: "Trusted Publisher one-time setup remaining" },
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
    "Read-only: tools/sdk/pyproject.toml, package_host_sdk.sh, release-engineering-dist.yml. Note whether PyPI job exists. implemented=true if work can proceed.",
    #{ label: "preflight", capability_mode: "read-only", output_schema: phase_schema },
);
if pre == () || pre.success == false || pre.output == () || pre.output.implemented == false {
    complete(#{ summary: "preflight failed", phase: pre });
}

phase("Publish-Script");
let p = agent(
    "Implement/verify scripts/publish_host_sdk_pypi.sh and just publish-host-sdk-pypi. Support --dry-run twine check, --repository testpypi|pypi. Do not commit tokens. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "publish-script", capability_mode: "all", output_schema: phase_schema },
);
if p == () || p.success == false || p.output == () || p.output.implemented == false {
    complete(#{ summary: "Publish-Script incomplete", phase: p });
}

phase("CI");
let c = agent(
    "Add publish-pypi job to release-engineering-dist.yml: needs package-portable, only on tag push, environment pypi, id-token write, stage only Host SDK wheel+sdist, pypa/gh-action-pypi-publish with skip-existing. Pin action by commit SHA. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "ci", capability_mode: "all", output_schema: phase_schema },
);
if c == () || c.success == false || c.output == () || c.output.implemented == false {
    complete(#{ summary: "CI incomplete", phase: c });
}

phase("Docs");
let d = agent(
    "Write docs/product/06-pypi-host-sdk.md (Trusted Publisher setup table), update 05/index/SDK README. just docs-check. Return implemented, summary, files_changed, tests_run, blockers.",
    #{ label: "docs", capability_mode: "all", output_schema: phase_schema },
);
if d == () || d.success == false || d.output == () || d.output.implemented == false {
    complete(#{ summary: "Docs incomplete", phase: d });
}

phase("Smoke");
let s = agent(
    "Run just package-host-sdk && just publish-host-sdk-pypi --dry-run; just docs-check. implemented=true with evidence.",
    #{ label: "smoke", capability_mode: "all", output_schema: phase_schema },
);
if s == () || s.success == false || s.output == () || s.output.implemented == false {
    complete(#{ summary: "Smoke incomplete", phase: s });
}

phase("Close");
let close = agent(
    "Closeout: code ready for PyPI; remaining human Trusted Publisher config + optional re-tag/re-run for 0.1.0. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
