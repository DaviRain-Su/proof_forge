let meta = #{
    name: "proof-forge-engineering-slice",
    description: "Implement one bounded ProofForge D1/D2 engineering slice, independently review it, verify ordinary product gates, and create one local commit without push",
    when_to_use: "Use for one bounded D1 or D2 product-engineering slice after its dependencies are satisfied; formal/release work is excluded.",
    phases: [
        #{ title: "Preflight", detail: "verify authority, dependencies, clean baseline, scope, and checks" },
        #{ title: "Implement", detail: "tests-first implementation in the shared worktree" },
        #{ title: "Review", detail: "parallel semantic, test/security, and migration-boundary review" },
        #{ title: "Repair", detail: "repair concrete findings without changing history" },
        #{ title: "Verify", detail: "independently run focused, SBOM, development, and ordinary CI gates" },
        #{ title: "Commit", detail: "create exactly one local commit; never push" },
    ],
};

let preflight_schema = #{
    "type": "object", "required": ["ready", "reason", "head", "plan", "blockers"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "reason": #{ "type": "string" },
        "head": #{ "type": "string" },
        "plan": #{ "type": "string" },
        "blockers": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};
let implementation_schema = #{
    "type": "object", "required": ["implemented", "summary", "head", "uncommitted", "files_changed", "red_evidence", "tests_run", "blockers"],
    "properties": #{
        "implemented": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "uncommitted": #{ "type": "boolean" },
        "files_changed": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "red_evidence": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};
let findings_schema = #{
    "type": "object", "required": ["head", "summary", "findings"],
    "properties": #{
        "head": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "findings": #{ "type": "array", "maxItems": 10, "items": #{
            "type": "object", "required": ["severity", "file", "issue", "evidence", "required_fix"],
            "properties": #{
                "severity": #{ "type": "string", "enum": ["P0", "P1", "P2"] },
                "file": #{ "type": "string" },
                "issue": #{ "type": "string" },
                "evidence": #{ "type": "string" },
                "required_fix": #{ "type": "string" },
            },
        }},
    },
};
let repair_schema = #{
    "type": "object", "required": ["resolved", "summary", "head", "uncommitted", "files_changed", "tests_run", "remaining"],
    "properties": #{
        "resolved": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "uncommitted": #{ "type": "boolean" },
        "files_changed": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "remaining": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};
let verification_schema = #{
    "type": "object", "required": ["passed", "summary", "head", "scope_ok", "tests_ok", "diff_clean", "formal_unchanged", "release_not_assessed", "changed_files", "commands", "unresolved"],
    "properties": #{
        "passed": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "scope_ok": #{ "type": "boolean" },
        "tests_ok": #{ "type": "boolean" },
        "diff_clean": #{ "type": "boolean" },
        "formal_unchanged": #{ "type": "boolean" },
        "release_not_assessed": #{ "type": "boolean" },
        "changed_files": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "commands": #{ "type": "array", "maxItems": 40, "items": #{
            "type": "object", "required": ["command", "result"],
            "properties": #{ "command": #{ "type": "string" }, "result": #{ "type": "string" } },
        }},
        "unresolved": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};
let commit_schema = #{
    "type": "object", "required": ["committed", "commit", "head_before", "head_after", "parent", "summary", "files", "worktree_clean"],
    "properties": #{
        "committed": #{ "type": "boolean" },
        "commit": #{ "type": "string" },
        "head_before": #{ "type": "string" },
        "head_after": #{ "type": "string" },
        "parent": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "files": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "worktree_clean": #{ "type": "boolean" },
    },
};

let slice_id = if args == () { () } else { args.slice_id };
let milestone = if args == () { () } else { args.milestone };
let objective = if args == () { () } else { args.objective };
let dependencies = if args == () || args.dependencies == () { [] } else { args.dependencies };
let allowed_paths = if args == () { () } else { args.allowed_paths };
let focused_checks = if args == () { () } else { args.focused_checks };
let verification_commands = if args == () { () } else { args.verification_commands };
let deletion_zero_patterns = if args == () || args.deletion_zero_patterns == () { [] } else { args.deletion_zero_patterns };
let shared_cutover = if args == () || args.shared_cutover == () { false } else { args.shared_cutover };
let commit_message = if args == () { () } else { args.commit_message };
let constraints = if args == () || args.constraints == () { "" } else { args.constraints };

if slice_id == () || type_of(slice_id) != "string" { pause("verification", "Pass args.slice_id."); }
slice_id.trim();
if slice_id == "" { pause("verification", "Pass a non-empty args.slice_id."); }
if milestone == () || (milestone != "D1" && milestone != "D2") { pause("verification", "args.milestone must be D1 or D2."); }
if objective == () || type_of(objective) != "string" { pause("verification", "Pass args.objective."); }
objective.trim();
if objective == "" { pause("verification", "Pass a non-empty args.objective."); }
if allowed_paths == () || type_of(allowed_paths) != "array" || allowed_paths.len() == 0 { pause("verification", "Pass non-empty args.allowed_paths."); }
if focused_checks == () || type_of(focused_checks) != "array" || focused_checks.len() == 0 { pause("verification", "Pass non-empty args.focused_checks."); }
if verification_commands == () || type_of(verification_commands) != "array" || verification_commands.len() == 0 { pause("verification", "Pass non-empty args.verification_commands."); }
if commit_message == () || type_of(commit_message) != "string" { pause("verification", "Pass args.commit_message."); }
commit_message.trim();
if commit_message == "" { pause("verification", "Pass a non-empty args.commit_message."); }

let touches_product = false;
let touches_docs = false;
for path in allowed_paths {
    if type_of(path) != "string" { pause("verification", "Every allowed path must be a string."); }
    let checked_path = path;
    checked_path.trim();
    if checked_path == "" || checked_path.starts_with("/") || checked_path.contains("..") { pause("verification", "allowed_paths must be repository-relative and must not contain '..'."); }
    if checked_path.starts_with("ProofForgeV2/") { touches_product = true; }
    if checked_path.starts_with("docs/") || checked_path == "AGENTS.md" || checked_path == "MIGRATION_MATRIX.md" || checked_path == "RECOVERY.md" { touches_docs = true; }
}
let has_ci = false;
let has_dev = false;
let has_diff = false;
let has_sbom = false;
let has_docs = false;
let has_target_negative = false;
for command in verification_commands {
    if type_of(command) != "string" { pause("verification", "Every verification command must be a string."); }
    if command == "just ci" { has_ci = true; }
    if command == "just dev-check" { has_dev = true; }
    if command == "git diff --check" { has_diff = true; }
    if command == "just sbom-package-files-refresh" { has_sbom = true; }
    if command == "just docs-check" { has_docs = true; }
    if command == "just target-negative" { has_target_negative = true; }
    if command.contains("governance-check") || command.contains("release-check") || command.contains("verify_host_stage0") || command.contains("TaskQualification") { pause("verification", "formal/release commands are forbidden."); }
}
if !has_ci || !has_dev || !has_diff { pause("verification", "Require just dev-check, just ci, and git diff --check."); }
if touches_product && !has_sbom { pause("verification", "ProofForgeV2 changes require just sbom-package-files-refresh."); }
if touches_docs && !has_docs { pause("verification", "Documentation changes require just docs-check."); }
if shared_cutover && !has_target_negative { pause("verification", "Shared cutover requires just target-negative."); }

let common = "ProofForge bounded engineering slice. Read AGENTS.md, RECOVERY.md, MIGRATION_MATRIX.md, and the directly relevant product specifications. Formal/release work is excluded: never create TASK/TST/EV/freeze/qualification objects and never run governance-check, release-check, or formal Stage-0. Never introduce fallback, adapter, dual reader, second ProgramV1 decoder, target-dependent source semantics, or target maturity expansion. Never read secrets, use the network, install dependencies, push, force, amend, reset --hard, or checkout --. ";

phase("Preflight");
let preflight_prompt = common;
preflight_prompt += "Work read-only. Run git status --short and git rev-parse HEAD. Inspect actual code, tests, consumers, and relevant specs. Set ready=true only if the worktree is clean, dependencies are satisfied, the objective is one bounded slice, every required edit fits the allowlist, and no unresolved product decision blocks implementation. Produce a minimal tests-first plan and exact blockers. ";
preflight_prompt += "Slice: " + slice_id + " (" + milestone + "). Objective: " + json_encode(objective) + ". Dependencies: " + json_encode(dependencies) + ". Allowed paths: " + json_encode(allowed_paths) + ". Focused checks: " + json_encode(focused_checks) + ". Verification: " + json_encode(verification_commands) + ". Shared cutover: " + shared_cutover.to_string() + ". Constraints: " + json_encode(constraints) + ".";
let preflight = agent(preflight_prompt, #{ label: "preflight:" + slice_id, phase: "Preflight", capability_mode: "execute", output_schema: preflight_schema });
if preflight == () || !preflight.success || preflight.output.ready != true || preflight.output.blockers.len() != 0 {
    let report = "# ProofForge engineering slice\n\nBlocked during preflight.\n\n" + json_encode(preflight);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "preflight", report_path: path, report: report });
}
let baseline_head = preflight.output.head;
baseline_head.trim();
if baseline_head == "" {
    let report = "# ProofForge engineering slice\n\nBlocked: empty baseline HEAD.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "preflight", report_path: path, report: report });
}
log("Preflight passed at " + baseline_head + ".");

phase("Implement");
let implement_prompt = common;
implement_prompt += "IMPLEMENT ONLY in the current shared clean worktree. Stay strictly inside allowed path prefixes; if a required edit falls outside, report a blocker instead of expanding scope. Write or update focused failing tests first and capture real RED evidence, then implement the minimum complete contract. Do not commit or stage contents; for newly created files only, git add -N on the specific file is allowed. Leave all changes uncommitted for review. ";
implement_prompt += "Slice: " + slice_id + ". Objective: " + json_encode(objective) + ". Allowed paths: " + json_encode(allowed_paths) + ". Approved plan: " + json_encode(preflight.output.plan) + ". Focused checks: " + json_encode(focused_checks) + ". Deletion zero patterns: " + json_encode(deletion_zero_patterns) + ". Constraints: " + json_encode(constraints) + ". Before returning, run git rev-parse HEAD; it must still equal " + baseline_head + ", and return uncommitted=true.";
let implementation = agent(implement_prompt, #{ label: "implement:" + slice_id, phase: "Implement", capability_mode: "all", output_schema: implementation_schema });
if implementation == () || !implementation.success || implementation.output.implemented != true || implementation.output.head != baseline_head || implementation.output.uncommitted != true {
    let report = "# ProofForge engineering slice\n\nBlocked during implementation.\n\n" + json_encode(implementation);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", report_path: path, report: report });
}
let review_diff = git_diff_since(baseline_head);
if review_diff == "" || fingerprint(review_diff) != fingerprint(git_diff_since("HEAD")) {
    let report = "# ProofForge engineering slice\n\nBlocked: no uncommitted baseline diff or HEAD moved.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", report_path: path, report: report });
}
log("Implementation diff fingerprint " + fingerprint(review_diff) + ".");

phase("Review");
let review_jobs = [];
let dimensions = [
    #{ label: "semantic", focus: "semantic correctness, totality, canonical ordering, error priority, and exact specification conformance" },
    #{ label: "tests-security", focus: "tests-first evidence, negative and boundary coverage, resource and security safety, and absence of test theater" },
    #{ label: "migration-boundary", focus: "bounded scope, D1 to D2 ordering, no fallback or formal overclaim, consumer completeness, documentation and SBOM accuracy" },
];
for dimension in dimensions {
    let prompt = common + "Work read-only. Run git status --short and git rev-parse HEAD; HEAD must equal " + baseline_head + ". Review the actual diff and surrounding code for " + dimension.focus + ". Objective: " + json_encode(objective) + ". Allowed paths: " + json_encode(allowed_paths) + ". Implementation: " + json_encode(implementation.output) + ". Diff: " + json_encode(review_diff) + ". Every finding needs concrete evidence and a required fix; an empty list is valid only after inspecting code and tests.";
    review_jobs.push(#{ prompt: prompt, label: "review:" + dimension.label, phase: "Review", capability_mode: "read-only", output_schema: findings_schema });
}
let reviews = parallel(review_jobs);
let reviewers_ok = true;
let findings = [];
for result in reviews {
    if result == () || !result.success || result.output.head != baseline_head {
        reviewers_ok = false;
    } else {
        for finding in result.output.findings {
            if findings.len() < 18 { findings.push(finding); }
            else { reviewers_ok = false; }
        }
    }
}
if !reviewers_ok {
    let report = "# ProofForge engineering slice\n\nBlocked: review infrastructure, history, or finding cap failed.\n\n" + json_encode(reviews);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "review", report_path: path, report: report });
}
log(findings.len().to_string() + " review findings collected.");

phase("Repair");
let repair = ();
if findings.len() > 0 {
    let repair_prompt = common;
    repair_prompt += "REPAIR ONLY in the current shared worktree. Verify and resolve every real P0/P1 finding; handle P2 only if in scope and risk-reducing. Stay inside allowed paths. Do not commit or stage contents; new-file git add -N only. Run focused checks and leave changes uncommitted. Baseline: " + baseline_head + ". Objective: " + json_encode(objective) + ". Allowed paths: " + json_encode(allowed_paths) + ". Findings: " + json_encode(findings) + ". Current diff: " + json_encode(git_diff_since(baseline_head)) + ". Return HEAD unchanged, uncommitted=true, and no remaining real finding.";
    repair = agent(repair_prompt, #{ label: "repair:" + slice_id, phase: "Repair", capability_mode: "all", output_schema: repair_schema });
    if repair == () || !repair.success || repair.output.resolved != true || repair.output.head != baseline_head || repair.output.uncommitted != true || repair.output.remaining.len() != 0 {
        let report = "# ProofForge engineering slice\n\nBlocked during repair.\n\n" + json_encode(repair);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "repair", report_path: path, report: report });
    }
} else {
    log("No repair required.");
}

phase("Verify");
let final_diff = git_diff_since(baseline_head);
let verify_prompt = common;
verify_prompt += "Independently verify the complete uncommitted change. Do not edit, stage, commit, or push. Require HEAD " + baseline_head + ". Inspect git status, the full diff, surrounding code, and findings. Run every focused check and every verification command exactly as supplied, serially. Confirm all changed paths are in the allowlist, no unrelated or generated path exists, no fallback or formal overclaim exists, SBOM and docs are accurate, and deletion zero patterns have no forbidden references. Set passed only if all commands pass, formal statuses are unchanged, release was not assessed, changed_files is non-empty, and unresolved is empty. Objective: " + json_encode(objective) + ". Allowed paths: " + json_encode(allowed_paths) + ". Focused: " + json_encode(focused_checks) + ". Verification: " + json_encode(verification_commands) + ". Zero patterns: " + json_encode(deletion_zero_patterns) + ". Findings: " + json_encode(findings) + ". Repair: " + json_encode(repair) + ". Diff: " + json_encode(final_diff) + ".";
let verification = agent(verify_prompt, #{ label: "verify:" + slice_id, phase: "Verify", capability_mode: "execute", output_schema: verification_schema });
let verified = verification != () && verification.success && verification.output.passed == true
    && verification.output.head == baseline_head && verification.output.scope_ok == true
    && verification.output.tests_ok == true && verification.output.diff_clean == true
    && verification.output.formal_unchanged == true && verification.output.release_not_assessed == true
    && verification.output.changed_files.len() > 0 && verification.output.unresolved.len() == 0;
if !verified {
    let report = "# ProofForge engineering slice\n\nVerification failed; no commit created.\n\n" + json_encode(verification);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "verify", report_path: path, report: report });
}
log("Independent engineering verification passed.");

phase("Commit");
let commit_prompt = "Create exactly one local commit for the verified ProofForge slice; never push. Require HEAD " + baseline_head + ". Inspect git status and diff. Every changed path must be in verified changed_files and allowed prefixes, with no unexpected, generated, or secret path. Stage exact files one by one with git add -- <specific-path>; never git add -A or git add .. Run git diff --cached --check, inspect the staged diff, then commit with exact message " + json_encode(commit_message) + ". Never amend, reset, checkout, force, bypass hooks, tag, or push. If hooks fail or alter source, stop. Return the exact chain and final status. Allowed paths: " + json_encode(allowed_paths) + ". Verified files: " + json_encode(verification.output.changed_files) + ".";
let committed = agent(commit_prompt, #{ label: "commit:" + slice_id, phase: "Commit", capability_mode: "all", output_schema: commit_schema });
if committed == () || !committed.success || committed.output.committed != true {
    let report = "# ProofForge engineering slice\n\nVerification passed, but local commit failed; nothing pushed.\n\n" + json_encode(committed);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "commit", report_path: path, report: report });
}
let chain_ok = committed.output.head_before == baseline_head && committed.output.head_after == committed.output.commit && committed.output.parent == baseline_head;
let content_ok = fingerprint(git_diff_since(baseline_head)) == fingerprint(final_diff);
let worktree_ok = committed.output.worktree_clean == true && git_diff_since("HEAD") == "" && git_diff_since(committed.output.commit) == "";
let final_status = if chain_ok && content_ok && worktree_ok { "committed" } else { "committed-invalid" };
let report = "# ProofForge engineering slice\n\n**Status:** " + final_status + "; nothing pushed.\n\n**Slice:** " + slice_id + "\n\n**Commit:** `" + committed.output.commit + "`\n\n**Engineering only:** formal task status unchanged; release not assessed.\n\n## Implementation\n" + json_encode(implementation.output) + "\n\n## Findings\n" + json_encode(findings) + "\n\n## Verification\n" + json_encode(verification.output) + "\n\n## Commit\n" + json_encode(committed.output);
let report_path = write_scratch_file("report.md", report);
complete(#{ status: final_status, slice_id: slice_id, commit: committed.output.commit, report_path: report_path, report: report, agent_calls: budget().spent });
