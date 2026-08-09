let meta = #{
    name: "release-engineering-0-1-1",
    description: "Bump engineering-dist to 0.1.1, tag v0.1.1, verify GitHub Release + PyPI publish",
    when_to_use: "Ship next engineering version after Trusted Publisher is configured.",
    phases: [
        #{ title: "Bump", detail: "VERSION + Lean + pyproject + tests" },
        #{ title: "Ship", detail: "commit push tag v0.1.1" },
        #{ title: "Verify", detail: "Actions success + PyPI install" },
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
        "remaining": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};

phase("Bump");
let b = agent(
    "Verify VERSION is 0.1.1 and matches ProductVersionV1 and tools/sdk/pyproject.toml and Tests/CLI/Emit. implemented=true if aligned.",
    #{ label: "bump", capability_mode: "read-only", output_schema: phase_schema },
);
if b == () || b.success == false || b.output == () || b.output.implemented == false {
    complete(#{ summary: "Bump incomplete", phase: b });
}

phase("Ship");
let s = agent(
    "Confirm tag v0.1.1 exists on origin and release-engineering-dist run is queued/succeeded. implemented=true with run URL if available.",
    #{ label: "ship", capability_mode: "read-only", output_schema: phase_schema },
);
if s == () || s.success == false || s.output == () || s.output.implemented == false {
    complete(#{ summary: "Ship incomplete", phase: s });
}

phase("Verify");
let v = agent(
    "Check GitHub Release v0.1.1 assets (linux+darwin CLI, author, wheel) and whether publish-pypi job succeeded. Note pip install proof-forge-sdk==0.1.1 if possible. implemented=true with evidence.",
    #{ label: "verify", capability_mode: "all", output_schema: phase_schema },
);
if v == () || v.success == false || v.output == () || v.output.implemented == false {
    complete(#{ summary: "Verify incomplete", phase: v });
}

phase("Close");
let close = agent(
    "Closeout engineering-dist 0.1.1. Not formal Stage-0. Return passed, summary, remaining.",
    #{ label: "close", capability_mode: "read-only", output_schema: close_schema },
);
if close == () || close.success == false || close.output == () {
    complete(#{ summary: "close failed", passed: false });
}
complete(close.output);
