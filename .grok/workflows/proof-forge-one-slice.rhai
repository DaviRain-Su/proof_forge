let meta = #{
    name: "proof-forge-one-slice",
    description: "Independently review one Goal-implemented uncommitted ProofForge slice without write or execute access",
    phases: [
        #{ title: "Review", detail: "parallel semantic, test, and migration-boundary review of explicit changed files" },
    ],
    when_to_use: "Use after the Goal implements one bounded slice and targeted tests pass; pass the clean baseline, exact slice, task contract, and every changed file. The Goal fixes findings, runs full gates, and commits.",
};

let findings_schema = #{
    "type": "object",
    "required": ["summary", "findings"],
    "properties": #{
        "summary": #{ "type": "string" },
        "findings": #{ "type": "array", "maxItems": 12, "items": #{
            "type": "object",
            "required": ["severity", "file", "issue", "required_fix"],
            "properties": #{
                "severity": #{ "type": "string" },
                "file": #{ "type": "string" },
                "issue": #{ "type": "string" },
                "required_fix": #{ "type": "string" },
            },
        }},
    },
};

let slice = if args == () { () } else { args.slice };
let base_commit = if args == () { () } else { args.base_commit };
let task_prompt = if args == () { () } else { args.task_prompt };
let changed_files = if args == () { () } else { args.changed_files };
if slice == () || slice == "" { pause("verification", "Goal must pass args.slice."); }
if base_commit == () || base_commit == "" { pause("verification", "Goal must pass args.base_commit."); }
if task_prompt == () || task_prompt == "" { pause("verification", "Goal must pass args.task_prompt."); }
if changed_files == () || changed_files.len() == 0 { pause("verification", "Goal must pass every dirty path in args.changed_files."); }

let files_json = json_encode(changed_files);
let common = "Read-only review only. Never edit, write, execute shell commands, stage, commit, reset, push, or create planning files. Use targeted grep/read_file on only the relevant AGENTS/MIGRATION sections, directly relevant specification spans, and every explicit changed path: " + files_json + ". Do not read whole oversized status lines or unrelated specifications. Baseline before Goal implementation was " + base_commit + ". Slice: " + slice + ". Contract: " + task_prompt + ". Report only concrete evidence-backed findings; an empty list is valid after reading the shipped code and tests.";

phase("Review");
let jobs = [
    #{
        label: "semantic-review",
        agent_type: "general-purpose",
        capability_mode: "read-only",
        output_schema: findings_schema,
        prompt: common + " Focus on semantic correctness, totality, fail-closed behavior, error precedence, canonical ordering, and exact accepted-spec conformance."
    },
    #{
        label: "test-review",
        agent_type: "general-purpose",
        capability_mode: "read-only",
        output_schema: findings_schema,
        prompt: common + " Focus on whether tests drive the real shipped functions, isolate positive/negative/ordering cases, avoid test theater, and would fail if the implementation regressed."
    },
    #{
        label: "boundary-review",
        agent_type: "general-purpose",
        capability_mode: "read-only",
        output_schema: findings_schema,
        prompt: common + " Focus on bounded-slice scope, D1→D2→D3→D4 ordering, target-neutrality, no fallback or formal overclaim, accurate AGENTS/MIGRATION_MATRIX/implementation-log facts, and required SBOM pin coverage."
    }
];
let reviews = parallel(jobs);
let findings = [];
let summaries = [];
for r in reviews {
    if r == () || r.success == false {
        findings.push(#{ severity: "P1", file: "<review-infrastructure>", issue: "an independent review slot failed", required_fix: "rerun the read-only review before committing" });
    } else {
        summaries.push(r.output.summary);
        if r.output.findings != () {
            for f in r.output.findings { findings.push(f); }
        }
    }
}
let report = "# ProofForge one-slice read-only review\n\n";
report += "**Slice:** " + slice + "\n\n";
report += "**Baseline:** `" + base_commit + "`\n\n";
report += "**Changed files:** " + files_json + "\n\n";
report += "**Findings:** " + json_encode(findings) + "\n";
let report_path = write_scratch_file("proof-forge-one-slice-review.md", report);
complete(#{ status: if findings.len() == 0 { "approved" } else { "findings" }, slice: slice, findings: findings, summaries: summaries, report_path: report_path });
