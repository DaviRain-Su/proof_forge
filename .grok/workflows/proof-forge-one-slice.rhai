let meta = #{
    name: "proof-forge-one-slice",
    description: "Build and independently verify one ProofForge slice in isolated worktrees, returning one commit candidate for the Goal to apply",
    phases: [
        #{ title: "Implement", detail: "tests-first implementation and candidate commit in an isolated worktree" },
        #{ title: "Review", detail: "independent review of the candidate in a separate isolated worktree" },
        #{ title: "Verify", detail: "apply findings, run product gates, and create one final isolated commit" },
        #{ title: "Audit", detail: "independently inspect and test the final isolated commit" },
    ],
    when_to_use: "Use from a long-running Goal after it selects one bounded ProofForge slice and records a clean baseline; the Goal cherry-picks the returned final_commit only after checking main stayed unchanged.",
};

let implementation_schema = #{
    "type": "object",
    "required": ["success", "summary", "candidate_commit", "commit_message", "files", "tests", "limitations"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "candidate_commit": #{ "type": "string" },
        "commit_message": #{ "type": "string" },
        "files": #{ "type": "array", "maxItems": 70, "items": #{ "type": "string" } },
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
    "required": ["success", "summary", "final_commit", "commit_message", "verification", "remaining_limits", "next_hint"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "final_commit": #{ "type": "string" },
        "commit_message": #{ "type": "string" },
        "verification": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "remaining_limits": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "next_hint": #{ "type": "string" },
    },
};
let audit_schema = #{
    "type": "object",
    "required": ["approved", "summary", "findings"],
    "properties": #{
        "approved": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "findings": #{ "type": "array", "maxItems": 12, "items": #{
            "type": "object",
            "required": ["severity", "file", "issue"],
            "properties": #{
                "severity": #{ "type": "string" },
                "file": #{ "type": "string" },
                "issue": #{ "type": "string" },
            },
        }},
    },
};

let slice = if args == () { () } else { args.slice };
let base_commit = if args == () { () } else { args.base_commit };
let task_prompt = if args == () { () } else { args.task_prompt };
if slice == () || slice == "" { pause("verification", "Goal must pass args.slice for one bounded migration slice."); }
if base_commit == () || base_commit == "" { pause("verification", "Goal must pass args.base_commit from a clean main HEAD."); }
if task_prompt == () || task_prompt == "" { pause("verification", "Goal must pass a self-contained tests-first args.task_prompt."); }

log("Starting isolated ProofForge slice at baseline " + base_commit + ": " + slice);

phase("Implement");
let implement_prompt = "Work only in your isolated git worktree. Confirm its starting HEAD equals baseline " + base_commit + ". Read AGENTS.md and directly relevant accepted specs. Implement exactly one bounded ProofForge slice tests-first. Do not touch the parent/main worktree, push, amend, create .plan.md, run governance/release, or start another slice. Run focused tests; refresh SBOM pin if ProofForgeV2/** changes; update only accurate engineering facts. Then stage explicit slice paths, run git diff --cached --check, and create exactly one candidate commit in this isolated worktree. Return its actual hash and subject. Slice: " + slice + ". Task: " + task_prompt;
let implemented = agent(implement_prompt, #{ label: "isolated-implementer", agent_type: "general-purpose", capability_mode: "all", isolation_worktree: true, output_schema: implementation_schema });
if implemented == () || implemented.success == false || implemented.output.success == false || implemented.output.candidate_commit == () || implemented.output.candidate_commit == "" {
    complete(#{ status: "blocked", stage: "implement", slice: slice, reason: "isolated implementation failed" });
}

phase("Review");
let files_json = json_encode(implemented.output.files);
let review_prompt = "Work only in your isolated git worktree; never touch parent/main. Confirm starting HEAD equals baseline " + base_commit + ". Inspect candidate commit " + implemented.output.candidate_commit + " with git show and apply it in this isolated worktree with git cherry-pick -n only if needed for focused inspection. Read AGENTS.md, relevant specs, and listed files: " + files_json + ". Independently check semantic correctness, fail-closed behavior, diagnostic order, deterministic ordering, shipped tests, SBOM facts, scope, and maturity claims. Do not push or create planning files. Return only evidence-backed findings. Slice: " + slice + ". Summary: " + implemented.output.summary;
let reviewed = agent(review_prompt, #{ label: "isolated-reviewer", agent_type: "general-purpose", capability_mode: "all", isolation_worktree: true, output_schema: review_schema });
if reviewed == () || reviewed.success == false {
    complete(#{ status: "blocked", stage: "review", slice: slice, reason: "independent isolated review failed" });
}

phase("Verify");
let findings_json = json_encode(reviewed.output.findings);
let verify_prompt = "Work only in your isolated git worktree; never touch parent/main. Require starting HEAD equals baseline " + base_commit + ". Apply candidate " + implemented.output.candidate_commit + " without committing via git cherry-pick -n. Validate each review finding and fix only confirmed issues within this slice. Run focused tests, git diff --check, applicable just sbom-package-files-refresh, and ordinary just ci. Never run governance/release, push, amend, reset parent/main, create .plan.md, or start another task. After all gates pass, stage every explicit slice path, run git diff --cached --check, and create exactly one final commit from the baseline containing candidate plus fixes. Return actual final commit hash, subject, evidence, limits, and next hint. Slice: " + slice + ". Findings JSON: " + findings_json;
let verified = agent(verify_prompt, #{ label: "isolated-fixer-verifier", agent_type: "general-purpose", capability_mode: "all", isolation_worktree: true, output_schema: verification_schema });
if verified == () || verified.success == false || verified.output.success == false || verified.output.final_commit == () || verified.output.final_commit == "" {
    complete(#{ status: "blocked", stage: "verify", slice: slice, reason: "isolated repair or verification failed" });
}

phase("Audit");
let audit_prompt = "Work only in your isolated git worktree; never touch parent/main. Require starting HEAD equals baseline " + base_commit + ". Inspect final commit " + verified.output.final_commit + " with git show; apply it with git cherry-pick -n in this isolated worktree for checks. Independently verify it is exactly one bounded slice, contains real shipped tests, respects AGENTS/spec boundaries, has accurate docs/pins, and passes a focused build plus git diff --check. Do not edit, commit, push, or create planning files. approved=true only with concrete evidence and no findings. Slice: " + slice + ". Verification summary: " + verified.output.summary;
let audited = agent(audit_prompt, #{ label: "isolated-final-auditor", agent_type: "general-purpose", capability_mode: "all", isolation_worktree: true, output_schema: audit_schema });
if audited == () || audited.success == false || audited.output.approved == false || audited.output.findings.len() > 0 {
    complete(#{ status: "blocked", stage: "audit", slice: slice, reason: "final isolated audit rejected candidate", final_commit: verified.output.final_commit, findings: audited.output.findings });
}

let report = "# ProofForge isolated one-slice candidate\n\n";
report += "**Slice:** " + slice + "\n\n";
report += "**Baseline:** `" + base_commit + "`\n\n";
report += "**Implementation:** " + implemented.output.summary + "\n\n";
report += "**Review:** " + reviewed.output.summary + "\n\n";
report += "**Verification:** " + verified.output.summary + "\n\n";
report += "**Audit:** " + audited.output.summary + "\n\n";
report += "**Final isolated commit:** `" + verified.output.final_commit + "` " + verified.output.commit_message + "\n\n";
report += "**Next hint:** " + verified.output.next_hint + "\n";
let report_path = write_scratch_file("proof-forge-one-slice.md", report);
complete(#{ status: "candidate_ready", slice: slice, base_commit: base_commit, final_commit: verified.output.final_commit, commit_message: verified.output.commit_message, verification: verified.output.verification, remaining_limits: verified.output.remaining_limits, next_hint: verified.output.next_hint, audit_summary: audited.output.summary, report_path: report_path });
