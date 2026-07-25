let meta = #{
    name: "develop-review-commit",
    description: "Implement a bounded change, review it from three angles, repair findings, verify, and create a local commit",
    when_to_use: "Use for bounded repository changes that need independent review and required checks before a local commit; never pushes.",
    phases: [
        #{ title: "Plan", detail: "preflight the repository and produce a bounded plan" },
        #{ title: "Implement", detail: "make the requested change without committing" },
        #{ title: "Review", detail: "three read-only reviewers inspect the actual diff" },
        #{ title: "Repair", detail: "the implementer addresses concrete findings" },
        #{ title: "Verify", detail: "an independent verifier runs required checks" },
        #{ title: "Commit", detail: "stage exact files and create a local commit; never push" },
    ],
};

let preflight_schema = #{
    "type": "object",
    "required": ["ready", "reason", "head", "plan", "allowed_files", "recommended_checks"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "plan": #{ "type": "string" },
        "allowed_files": #{ "type": "array", "maxItems": 64, "items": #{ "type": "string" } },
        "recommended_checks": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};
let implementation_schema = #{
    "type": "object",
    "required": ["implemented", "summary", "files_changed", "tests_run", "blockers"],
    "properties": #{
        "implemented": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 64, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 24, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};
let findings_schema = #{
    "type": "object",
    "required": ["findings"],
    "properties": #{
        "findings": #{
            "type": "array",
            "maxItems": 8,
            "items": #{
                "type": "object",
                "required": ["severity", "file", "issue", "evidence", "fix"],
                "properties": #{
                    "severity": #{ "type": "string", "enum": ["blocker", "bug", "suggestion"] },
                    "file": #{ "type": "string" },
                    "issue": #{ "type": "string" },
                    "evidence": #{ "type": "string" },
                    "fix": #{ "type": "string" },
                },
            },
        },
    },
};
let remediation_schema = #{
    "type": "object",
    "required": ["resolved", "summary", "files_changed", "tests_run", "remaining"],
    "properties": #{
        "resolved": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "files_changed": #{ "type": "array", "maxItems": 64, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 24, "items": #{ "type": "string" } },
        "remaining": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};
let verification_schema = #{
    "type": "object",
    "required": ["passed", "summary", "scope_ok", "tests_ok", "diff_clean", "changed_files", "commands", "unresolved"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "scope_ok": #{ "type": "boolean" },
        "tests_ok": #{ "type": "boolean" },
        "diff_clean": #{ "type": "boolean" },
        "changed_files": #{ "type": "array", "maxItems": 64, "items": #{ "type": "string" } },
        "commands": #{
            "type": "array",
            "maxItems": 24,
            "items": #{
                "type": "object",
                "required": ["command", "result"],
                "properties": #{
                    "command": #{ "type": "string" },
                    "result": #{ "type": "string" },
                },
            },
        },
        "unresolved": #{ "type": "array", "maxItems": 16, "items": #{ "type": "string" } },
    },
};
let commit_schema = #{
    "type": "object",
    "required": ["committed", "commit", "summary", "files", "worktree_clean"],
    "properties": #{
        "committed": #{ "type": "boolean" },
        "commit": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "files": #{ "type": "array", "maxItems": 64, "items": #{ "type": "string" } },
        "worktree_clean": #{ "type": "boolean" },
    },
};

let objective = if args == () { () } else { args.objective };
let allowed_paths = if args == () { () } else { args.allowed_paths };
let verification_commands = if args == () { () } else { args.verification_commands };
let commit_message = if args == () { () } else { args.commit_message };
let constraints = if args == () { "" } else { args.constraints };

if objective == () || type_of(objective) != "string" {
    pause("verification", "Pass args.objective as a non-empty string.");
}
objective.trim();
if objective == "" { pause("verification", "Pass a non-empty args.objective."); }
if allowed_paths == () || type_of(allowed_paths) != "array" || allowed_paths.len() == 0 {
    pause("verification", "Pass args.allowed_paths as a non-empty array of repository-relative path prefixes.");
}
for path in allowed_paths {
    if type_of(path) != "string" { pause("verification", "Every args.allowed_paths entry must be a string."); }
    let checked_path = path;
    checked_path.trim();
    if checked_path == "" { pause("verification", "args.allowed_paths must not contain an empty path."); }
}
if verification_commands == () || type_of(verification_commands) != "array" || verification_commands.len() == 0 {
    pause("verification", "Pass args.verification_commands as a non-empty array of required checks.");
}
for command in verification_commands {
    if type_of(command) != "string" { pause("verification", "Every verification command must be a string."); }
    let checked_command = command;
    checked_command.trim();
    if checked_command == "" { pause("verification", "verification_commands must not contain an empty command."); }
}
if commit_message == () || type_of(commit_message) != "string" {
    pause("verification", "Pass args.commit_message as a non-empty string.");
}
commit_message.trim();
if commit_message == "" { pause("verification", "Pass a non-empty args.commit_message."); }
if constraints == () { constraints = ""; }
if type_of(constraints) != "string" { pause("verification", "args.constraints must be a string when provided."); }

phase("Plan");
let preflight_prompt = "You are the preflight planner for a bounded repository change. Work read-only. ";
preflight_prompt += "Read the repository instruction files that govern the requested paths, inspect the actual code, ";
preflight_prompt += "run read-only git commands including `git status --short` and `git rev-parse HEAD`, and produce a minimal plan. ";
preflight_prompt += "Set ready=true only when the working tree is clean, the objective is bounded, and it can be completed entirely inside the user-approved path prefixes. ";
preflight_prompt += "Do not read .env files, credentials, keys, tokens, or secret stores. Do not modify files, install dependencies, use the network, commit, or push.\n";
preflight_prompt += "Objective (JSON): " + json_encode(objective) + "\n";
preflight_prompt += "Hard allowed path prefixes (JSON): " + json_encode(allowed_paths) + "\n";
preflight_prompt += "Required verification commands (JSON): " + json_encode(verification_commands) + "\n";
preflight_prompt += "Additional constraints (JSON): " + json_encode(constraints) + "\n";
preflight_prompt += "allowed_files must contain only repository-relative files under the hard prefixes. recommended_checks may add only safe, local, non-destructive project checks.";
let preflight = agent(preflight_prompt, #{
    label: "preflight-plan",
    phase: "Plan",
    capability_mode: "execute",
    output_schema: preflight_schema,
});
if preflight == () || !preflight.success {
    let report = "# Development workflow report\n\nBlocked during preflight: the planning agent failed.\n";
    let report_path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "plan", report_path: report_path, report: report });
}
if preflight.output.ready != true {
    let report = "# Development workflow report\n\nBlocked during preflight.\n\n";
    report += preflight.output.reason + "\n\nPlan:\n" + preflight.output.plan + "\n";
    let report_path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "plan", report_path: report_path, report: report });
}
log("Preflight passed at " + preflight.output.head + ".");

phase("Implement");
let implementation_prompt = "Implement the bounded repository objective below in the current working tree. ";
implementation_prompt += "First read all governing instruction files and inspect the actual code. Stay strictly inside the hard allowed path prefixes; ";
implementation_prompt += "if any required edit falls outside them, stop and report a blocker instead of expanding scope. ";
implementation_prompt += "Do not read secrets, use the network, install or downgrade dependencies, delete unrelated files, run destructive git commands, commit, amend, or push. ";
implementation_prompt += "Write focused tests before or with the fix, preserve unrelated work, run safe focused checks, and leave the changes uncommitted for review.\n";
implementation_prompt += "Objective (JSON): " + json_encode(objective) + "\n";
implementation_prompt += "Hard allowed path prefixes (JSON): " + json_encode(allowed_paths) + "\n";
implementation_prompt += "Required verification commands (JSON): " + json_encode(verification_commands) + "\n";
implementation_prompt += "Approved plan (JSON): " + json_encode(preflight.output) + "\n";
implementation_prompt += "Additional constraints (JSON): " + json_encode(constraints);
let implementation = agent(implementation_prompt, #{
    label: "implement",
    phase: "Implement",
    capability_mode: "all",
    output_schema: implementation_schema,
});
if implementation == () || !implementation.success || implementation.output.implemented != true {
    let report = "# Development workflow report\n\nBlocked during implementation.\n\n";
    if implementation != () && implementation.success {
        report += json_encode(implementation.output) + "\n";
    }
    let report_path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", report_path: report_path, report: report });
}
let review_diff = git_diff_since("HEAD");
log("Implementation completed; diff fingerprint " + fingerprint(review_diff) + ".");

phase("Review");
let dimensions = [
    #{ label: "correctness", focus: "correctness, specification alignment, edge cases, error ordering, and semantic regressions" },
    #{ label: "tests-security", focus: "test adequacy, fail-closed behavior, resource safety, injection/security risks, and missing negative coverage" },
    #{ label: "scope-maintainability", focus: "scope discipline, allowed-path compliance, legacy/fallback leakage, unnecessary complexity, docs, and deletion readiness" },
];
let review_jobs = [];
for dimension in dimensions {
    let review_prompt = "Review the current uncommitted change for " + dimension.focus + ". Work read-only. ";
    review_prompt += "Run `git status --short` and inspect the actual diff and surrounding source files; do not trust the implementation summary alone. ";
    review_prompt += "Do not modify files, read secrets, use the network, commit, or push. Every finding must cite concrete file-level evidence and a specific fix. ";
    review_prompt += "An empty findings list is valid only after inspecting the shipped code and tests. Report at most 8 findings.\n";
    review_prompt += "Objective (JSON): " + json_encode(objective) + "\n";
    review_prompt += "Hard allowed path prefixes (JSON): " + json_encode(allowed_paths) + "\n";
    review_prompt += "Implementation report (JSON): " + json_encode(implementation.output) + "\n";
    review_prompt += "Unified diff (JSON): " + json_encode(review_diff);
    review_jobs.push(#{
        prompt: review_prompt,
        label: "review:" + dimension.label,
        phase: "Review",
        capability_mode: "read-only",
        output_schema: findings_schema,
    });
}
let review_results = parallel(review_jobs);
let reviewers_ok = true;
let findings = [];
let dropped_findings = 0;
for result in review_results {
    if result == () || !result.success {
        reviewers_ok = false;
    } else if result.output.findings != () {
        for finding in result.output.findings {
            if findings.len() < 12 {
                findings.push(finding);
            } else {
                dropped_findings += 1;
            }
        }
    }
}
if dropped_findings > 0 {
    reviewers_ok = false;
    log(dropped_findings.to_string() + " review findings were dropped by the 12-item repair cap; commit is fail-closed.");
}
log(findings.len().to_string() + " review findings collected.");

phase("Repair");
let remediation = ();
if findings.len() > 0 {
    let remediation_prompt = "Address the concrete review findings below in the same working tree. ";
    remediation_prompt += "Re-read the affected code and verify each claim before editing. Fix blocker/bug findings; apply suggestions only when they are in scope and reduce risk. ";
    remediation_prompt += "Stay inside the original hard allowed path prefixes, do not expand the objective, do not read secrets, use the network, run destructive git commands, commit, amend, or push. ";
    remediation_prompt += "Run focused checks and set resolved=false if any real finding remains.\n";
    remediation_prompt += "Objective (JSON): " + json_encode(objective) + "\n";
    remediation_prompt += "Hard allowed path prefixes (JSON): " + json_encode(allowed_paths) + "\n";
    remediation_prompt += "Findings (JSON): " + json_encode(findings);
    remediation = agent(remediation_prompt, #{
        label: "repair",
        phase: "Repair",
        capability_mode: "all",
        resume_from: implementation.agent_id,
        output_schema: remediation_schema,
    });
    if remediation == () || !remediation.success || remediation.output.resolved != true {
        let report = "# Development workflow report\n\nBlocked during remediation.\n\nFindings:\n";
        report += json_encode(findings) + "\n\nRemediation:\n";
        if remediation != () && remediation.success { report += json_encode(remediation.output); }
        let report_path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "repair", report_path: report_path, report: report });
    }
} else {
    log("No review findings required remediation.");
}

phase("Verify");
let final_diff = git_diff_since("HEAD");
let verification_prompt = "Independently verify the current uncommitted change. Do not modify source files and do not commit or push. ";
verification_prompt += "Inspect `git status --short`, the full diff, and surrounding code. Confirm every changed file is inside the hard allowed prefixes, no pre-existing or unrelated change is present, ";
verification_prompt += "no legacy fallback or security regression was introduced, and review findings are resolved. Run every user-required verification command and `git diff --check`; ";
verification_prompt += "you may add only safe, local, non-destructive project checks. Never read secrets, use the network, install dependencies, delete source, or alter git history. ";
verification_prompt += "Set passed=true only when reviewer coverage is complete, scope_ok/tests_ok/diff_clean are all true, and unresolved is empty.\n";
verification_prompt += "Objective (JSON): " + json_encode(objective) + "\n";
verification_prompt += "Hard allowed path prefixes (JSON): " + json_encode(allowed_paths) + "\n";
verification_prompt += "Required verification commands (JSON): " + json_encode(verification_commands) + "\n";
verification_prompt += "Reviewer panel complete: " + reviewers_ok.to_string() + "\n";
verification_prompt += "Findings (JSON): " + json_encode(findings) + "\n";
verification_prompt += "Remediation result (JSON): " + json_encode(remediation) + "\n";
verification_prompt += "Final unified diff (JSON): " + json_encode(final_diff);
let verification = agent(verification_prompt, #{
    label: "verify",
    phase: "Verify",
    capability_mode: "execute",
    output_schema: verification_schema,
});
let verified = reviewers_ok;
if verification == () || !verification.success {
    verified = false;
} else if verification.output.passed != true || verification.output.scope_ok != true || verification.output.tests_ok != true || verification.output.diff_clean != true {
    verified = false;
} else if verification.output.unresolved.len() != 0 {
    verified = false;
}
if !verified {
    let report = "# Development workflow report\n\nVerification failed; no commit was created.\n\n";
    report += "Reviewers complete: " + reviewers_ok.to_string() + "\n\nFindings:\n" + json_encode(findings) + "\n\nVerification:\n";
    if verification != () && verification.success { report += json_encode(verification.output); }
    let report_path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "verify", report_path: report_path, report: report });
}
log("Independent verification passed.");

phase("Commit");
let commit_prompt = "Create one local git commit for the independently verified change. Never push. ";
commit_prompt += "First inspect `git status --short` and the staged/unstaged diff. Require every changed path to be listed by verification and under the hard allowed prefixes; ";
commit_prompt += "if there is any unexpected, pre-existing, generated, secret-bearing, or out-of-scope path, do not commit and report failure. ";
commit_prompt += "Stage exact files one at a time with `git add -- <specific-path>`; never use `git add -A` or `git add .`. Run `git diff --cached --check`, inspect the staged diff, then commit with the exact provided message. ";
commit_prompt += "Never use reset --hard, checkout --, amend, force, hook bypass, or any push command. If hooks fail or modify source, stop without amending. Return the commit hash and final `git status --short`.\n";
commit_prompt += "Hard allowed path prefixes (JSON): " + json_encode(allowed_paths) + "\n";
commit_prompt += "Verified changed files (JSON): " + json_encode(verification.output.changed_files) + "\n";
commit_prompt += "Commit message, treated as literal text (JSON): " + json_encode(commit_message) + "\n";
commit_prompt += "Verification (JSON): " + json_encode(verification.output);
let commit_result = agent(commit_prompt, #{
    label: "local-commit",
    phase: "Commit",
    capability_mode: "all",
    output_schema: commit_schema,
});
if commit_result == () || !commit_result.success || commit_result.output.committed != true {
    let report = "# Development workflow report\n\nVerification passed, but the local commit was not created.\n\n";
    if commit_result != () && commit_result.success { report += json_encode(commit_result.output); }
    let report_path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "commit", report_path: report_path, report: report });
}

let post_commit_diff = git_diff_since("HEAD");
let final_status = "committed";
if commit_result.output.worktree_clean != true || post_commit_diff != "" {
    final_status = "committed-with-residual-changes";
}
let report = "# Development workflow report\n\n";
report += "**Status:** " + final_status + "; nothing was pushed.\n\n";
report += "**Objective:** " + objective + "\n\n";
report += "**Commit:** `" + commit_result.output.commit + "`\n\n";
report += "## Implementation\n\n" + json_encode(implementation.output) + "\n\n";
report += "## Review findings\n\n" + json_encode(findings) + "\n\n";
report += "## Verification\n\n" + json_encode(verification.output) + "\n\n";
report += "## Commit\n\n" + json_encode(commit_result.output) + "\n\n";
report += "Tracked diff remaining after commit: " + fingerprint(post_commit_diff) + "\n";
let report_path = write_scratch_file("report.md", report);
complete(#{
    status: final_status,
    commit: commit_result.output.commit,
    report_path: report_path,
    report: report,
    agent_calls: budget().spent,
});
