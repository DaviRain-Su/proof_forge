let meta = #{
    name: "proof-forge-one-slice",
    description: "Implement, independently review, verify, and locally commit exactly one Goal-selected ProofForge migration slice",
    phases: [
        #{ title: "Implement", detail: "write failing tests and implement the supplied bounded slice without committing" },
        #{ title: "Review", detail: "independently audit the uncommitted slice" },
        #{ title: "Verify", detail: "fix confirmed issues and run focused plus ordinary product gates" },
        #{ title: "Commit", detail: "guard the baseline and create exactly one local slice commit" },
    ],
    when_to_use: "Use from a long-running Goal after it selects one bounded ProofForge D1→D2→D3→D4 slice and records the clean baseline commit.",
};

let implementation_schema = #{
    "type": "object",
    "required": ["success", "summary", "files", "tests", "limitations"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "files": #{ "type": "array", "maxItems": 60, "items": #{ "type": "string" } },
        "tests": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "limitations": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
    },
};
let review_schema = #{
    "type": "object",
    "required": ["approved", "summary", "findings"],
    "properties": #{
        "approved": #{ "type": "boolean" },
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
let verification_schema = #{
    "type": "object",
    "required": ["success", "ready_to_commit", "summary", "verification", "remaining_limits", "next_hint", "files_to_commit"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "ready_to_commit": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "verification": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "remaining_limits": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "next_hint": #{ "type": "string" },
        "files_to_commit": #{ "type": "array", "minItems": 1, "maxItems": 70, "items": #{ "type": "string" } },
    },
};
let commit_schema = #{
    "type": "object",
    "required": ["success", "summary", "commit_hash", "commit_message"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "commit_hash": #{ "type": "string" },
        "commit_message": #{ "type": "string" },
    },
};

let slice = if args == () { () } else { args.slice };
let base_commit = if args == () { () } else { args.base_commit };
let task_prompt = if args == () { () } else { args.task_prompt };
if slice == () || slice == "" {
    pause("verification", "Goal must launch this workflow with args.slice for exactly one bounded migration slice.");
}
if base_commit == () || base_commit == "" {
    pause("verification", "Goal must launch this workflow with args.base_commit from a clean git rev-parse HEAD.");
}
if task_prompt == () || task_prompt == "" {
    pause("verification", "Goal must launch this workflow with a self-contained args.task_prompt.");
}

log("Starting one bounded ProofForge slice at baseline " + base_commit + ": " + slice);

phase("Implement");
let implement_prompt = "Implement exactly one bounded ProofForge migration slice in the shared working tree. Re-read AGENTS.md and the directly relevant accepted specs. Before editing, run git status --short and git rev-parse HEAD; require a clean tree and exact baseline " + base_commit + ". Add focused failing tests first, then the minimum production implementation. Keep source/Typed/Semantic target-neutral. Do not stage, commit, push, amend, reset, create .plan.md or any planning artifact, start another slice, or touch qualification/governance. No adapters, fallback, destructive git commands, or maturity overclaims. Run focused tests. If ProofForgeV2/** changes, run just sbom-package-files-refresh. Update only directly relevant engineering facts. Leave the complete slice uncommitted. Slice: " + slice + ". Task: " + task_prompt;
let implemented = agent(implement_prompt, #{ label: "implementer", agent_type: "general-purpose", capability_mode: "all", output_schema: implementation_schema });
if implemented == () || implemented.success == false || implemented.output.success == false {
    complete(#{ status: "blocked", stage: "implement", slice: slice, reason: "implementation failed; inspect the uncommitted tree" });
}

phase("Review");
let files_json = json_encode(implemented.output.files);
let review_prompt = "Independently review one uncommitted ProofForge slice. Read AGENTS.md, the directly relevant accepted specs, and every implementer-listed path: " + files_json + ". Inspect actual files and tests; do not edit, stage, commit, push, or create planning files. Check semantic correctness, fail-closed behavior, diagnostic order, negative coverage, deterministic ordering, scope boundaries, SBOM pin facts, and maturity claims. Treat any evidence that HEAD moved away from baseline " + base_commit + " or any unrelated artifact as a critical finding. Only evidence-backed findings count; empty findings is valid after real inspection. Slice: " + slice + ". Implementation summary: " + implemented.output.summary;
let reviewed = agent(review_prompt, #{ label: "reviewer", agent_type: "oracle", capability_mode: "read-only", output_schema: review_schema });
if reviewed == () || reviewed.success == false {
    complete(#{ status: "blocked", stage: "review", slice: slice, reason: "independent review failed" });
}

phase("Verify");
let findings_json = json_encode(reviewed.output.findings);
let verify_prompt = "Own final repair and verification for exactly one ProofForge slice. Run git rev-parse HEAD and require baseline " + base_commit + ". Inspect git status and the full uncommitted diff, including untracked files. Independently validate every review finding and fix only confirmed issues without expanding scope. Delete no unfamiliar files. Run focused tests, git diff --check, just sbom-package-files-refresh when ProofForgeV2/** changed, and ordinary just ci. Never run governance-check or release-check. Do not stage, commit, push, amend, reset, create .plan.md, or begin another task. Return ready_to_commit=true only when HEAD is unchanged, every dirty path belongs to this slice, all gates pass, and files_to_commit exactly enumerates every dirty/untracked path. Keep formal statuses honest. Slice: " + slice + ". Findings JSON: " + findings_json;
let verified = agent(verify_prompt, #{ label: "fixer-verifier", agent_type: "general-purpose", capability_mode: "all", output_schema: verification_schema });
if verified == () || verified.success == false || verified.output.success == false || verified.output.ready_to_commit == false {
    complete(#{ status: "blocked", stage: "verify", slice: slice, reason: "repair or verification failed; inspect the uncommitted tree" });
}

phase("Commit");
let commit_files_json = json_encode(verified.output.files_to_commit);
let commit_prompt = "Act only as local committer for one already verified ProofForge slice. Do not edit files, rerun implementation, or expand scope. Require git rev-parse HEAD exactly equals baseline " + base_commit + ". Inspect git status and ensure every dirty/untracked path belongs to this exact verified list: " + commit_files_json + ". If HEAD moved, tree is clean, any dirty path is unlisted, or a listed path is unrelated/missing, return success=false without changing git. Otherwise stage each explicit path individually with git add <path>; never use git add -A or git add . Check git diff --cached --check and inspect the staged diff. Create exactly one local commit with a concise imperative subject describing only slice " + slice + ". Never amend or push. Require a clean working tree afterward. Return actual git rev-parse HEAD and git log -1 --format=%s. Verification summary: " + verified.output.summary;
let committed = agent(commit_prompt, #{ label: "committer", agent_type: "general-purpose", capability_mode: "all", output_schema: commit_schema });
if committed == () || committed.success == false || committed.output.success == false || committed.output.commit_hash == () || committed.output.commit_hash == "" {
    complete(#{ status: "blocked", stage: "commit", slice: slice, reason: "dedicated local commit failed; inspect git status" });
}

let report = "# ProofForge one-slice result\n\n";
report += "**Slice:** " + slice + "\n\n";
report += "**Baseline:** `" + base_commit + "`\n\n";
report += "**Implementation:** " + implemented.output.summary + "\n\n";
report += "**Review:** " + reviewed.output.summary + "\n\n";
report += "**Verification:** " + verified.output.summary + "\n\n";
report += "**Commit:** `" + committed.output.commit_hash + "` " + committed.output.commit_message + "\n\n";
report += "**Next hint:** " + verified.output.next_hint + "\n";
let report_path = write_scratch_file("proof-forge-one-slice.md", report);
complete(#{
    status: "completed",
    slice: slice,
    commit_hash: committed.output.commit_hash,
    commit_message: committed.output.commit_message,
    verification: verified.output.verification,
    remaining_limits: verified.output.remaining_limits,
    next_hint: verified.output.next_hint,
    report_path: report_path,
});
