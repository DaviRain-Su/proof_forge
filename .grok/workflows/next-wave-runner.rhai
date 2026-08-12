let meta = #{
    name: "next-wave-runner",
    description: "One next-wave engineering slice: select from the live queue, implement, review, verify, one local commit",
    when_to_use: "Advance ADR-0036 EVM lighthouse or ADR-0031 S4 after the previous queue row is done; one slice per fire.",
    phases: [
        #{ title: "Select", detail: "read next-wave queue and claim the first drainable pending row" },
        #{ title: "Implement", detail: "tests-first implementation in the shared worktree" },
        #{ title: "Review", detail: "parallel semantic, corpus/honesty, and boundary review" },
        #{ title: "Repair", detail: "fix real P0/P1 findings" },
        #{ title: "Verify", detail: "focused gates; formal IDs unchanged; no push" },
        #{ title: "Commit", detail: "one local commit; update the queue" },
    ],
};

let select_schema = #{
    "type": "object",
    "required": ["ready", "slice_id", "status", "objective", "head", "allowed_paths", "focused_checks", "verification_commands", "commit_message", "blockers", "program_complete"],
    "properties": #{
        "ready": #{ "type": "boolean" },
        "slice_id": #{ "type": "string" },
        "status": #{ "type": "string" },
        "objective": #{ "type": "string" },
        "head": #{ "type": "string" },
        "allowed_paths": #{ "type": "array", "maxItems": 40, "items": #{ "type": "string" } },
        "focused_checks": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "verification_commands": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "commit_message": #{ "type": "string" },
        "blockers": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "program_complete": #{ "type": "boolean" },
    },
};

let implementation_schema = #{
    "type": "object",
    "required": ["implemented", "summary", "head", "uncommitted", "files_changed", "tests_run", "blockers"],
    "properties": #{
        "implemented": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "head": #{ "type": "string" },
        "uncommitted": #{ "type": "boolean" },
        "files_changed": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "tests_run": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "blockers": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};

let findings_schema = #{
    "type": "object",
    "required": ["head", "summary", "findings"],
    "properties": #{
        "head": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "findings": #{ "type": "array", "maxItems": 10, "items": #{
            "type": "object",
            "required": ["severity", "file", "issue", "evidence", "required_fix"],
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
    "type": "object",
    "required": ["resolved", "summary", "head", "uncommitted", "files_changed", "tests_run", "remaining"],
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
    "type": "object",
    "required": ["passed", "summary", "head", "scope_ok", "tests_ok", "diff_clean", "formal_unchanged", "release_not_assessed", "changed_files", "commands", "unresolved"],
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
            "type": "object",
            "required": ["command", "result"],
            "properties": #{
                "command": #{ "type": "string" },
                "result": #{ "type": "string" },
            },
        }},
        "unresolved": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
    },
};

let commit_schema = #{
    "type": "object",
    "required": ["committed", "commit", "head_before", "head_after", "parent", "summary", "files", "worktree_clean", "queue_updated"],
    "properties": #{
        "committed": #{ "type": "boolean" },
        "commit": #{ "type": "string" },
        "head_before": #{ "type": "string" },
        "head_after": #{ "type": "string" },
        "parent": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "files": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
        "worktree_clean": #{ "type": "boolean" },
        "queue_updated": #{ "type": "boolean" },
    },
};

fn trimmed(s) {
    if type_of(s) == "string" {
        s.trim();
        s
    } else {
        ""
    }
}

let mode = "one";
if args != () && args.mode != () && type_of(args.mode) == "string" {
    mode = args.mode;
    mode.trim();
}

let common = "ProofForge next-wave engineering (ADR-0036 EVM lighthouse + ADR-0031 S4). ";
common += "NOT formal TASK/TST/EV closeout. NOT C-3. NOT Anvil lossless OutcomeWire. ";
common += "Read AGENTS.md Current Checkpoint / Next task, RECOVERY.md, ";
common += "docs/engineering-backlog.md recommended kill order, ";
common += ".grok/next-wave-queue.md, .grok/goals/slices/<id>.md, ";
common += "docs/specs/reference-outcome-v1.md, docs/specs/evm-outcome-adapter-v1.md, ";
common += "docs/adr/0031-system-capability-unification.md when the slice is SYS-S4-*. ";
common += "Sole L1 step: admitReferenceProgramSliceV1 + stepReferenceSliceV1. ";
common += "FORBIDDEN: close TASK-D2-07/TST-SEM-002/003/C-3; mint OutcomeWire from observation; ";
common += "second step machine; new TASK-*; push; force; amend; reset --hard; checkout --; git add -A; secrets. ";
common += "Skip Track C decision/formal rows. Do not re-implement NEAR/CW blockHeight runtime harnesses. ";

phase("Select");
let select_prompt = common;
select_prompt += "SELECT next work. Run git status --short and git rev-parse HEAD. Read .grok/next-wave-queue.md. ";
select_prompt += "If worktree is dirty with unrelated WIP, set ready=false with blockers (do not destroy work). ";
select_prompt += "If Track A and Track B have no pending rows, set program_complete=true, ready=false, slice_id=done. ";
select_prompt += "Else pick the first pending row in Track A order (LH-4, LH-5, LH-6, LH-7) then Track B ";
select_prompt += "(SYS-S4-SHARED, SYS-S4-EVM, SYS-S4-NEAR, SYS-S4-CW). Never pick Track C. ";
select_prompt += "Read the matching .grok/goals/slices/<id>.md when it exists and copy its allowlist. ";
select_prompt += "Mark that row in_progress in .grok/next-wave-queue.md only if the tree is clean or dirty paths are inside the allowlist. ";
select_prompt += "focused_checks must include a real lake/lean or python command that would fail if the slice is missing. ";
select_prompt += "LH-4/5: Lean corpus/adapter suite plus scripts/evm_corpus_v1.py self-checks that keep observation mint FC. ";
select_prompt += "LH-6/7: Semantic/Reference focused suite; do not edit 04-task-breakdown or 05-test-spec status. ";
select_prompt += "SYS-S4-SHARED: CheckV1/Normalize/Reference focused; target Plans remain FC. ";
select_prompt += "verification_commands must include git diff --check; ProofForgeV2 changes require just sbom-package-files-refresh; docs require just docs-check. ";
select_prompt += "commit_message is one imperative line. ready=true only if a concrete slice is claimable.";
let selected = agent(select_prompt, #{
    label: "select-slice",
    phase: "Select",
    capability_mode: "all",
    output_schema: select_schema,
});
if selected == () || !selected.success {
    let report = "# next-wave-runner\n\nSelect agent failed.\n\n" + json_encode(selected);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "select", report_path: path });
}
if mode == "status" {
    let report = "# next-wave-runner\n\n**Mode:** status\n\n" + json_encode(selected.output);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "status", report_path: path, slice_id: selected.output.slice_id });
}
if selected.output.program_complete == true {
    let report = "# next-wave-runner\n\n**Program complete.** Track A+B pending empty.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "program_complete", report_path: path });
}
if selected.output.ready != true || selected.output.blockers.len() != 0 {
    let report = "# next-wave-runner\n\nBlocked at select.\n\n" + json_encode(selected.output);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "select", report_path: path, blockers: selected.output.blockers });
}

let baseline_head = trimmed(selected.output.head);
let slice_id = trimmed(selected.output.slice_id);
if baseline_head == "" || slice_id == "" {
    let report = "# next-wave-runner\n\nSelect returned empty head or slice_id.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "select", report_path: path });
}
log("Selected " + slice_id + " at " + baseline_head);

phase("Implement");
let implement_prompt = common;
implement_prompt += "IMPLEMENT slice " + slice_id + " only. Objective: " + json_encode(selected.output.objective) + ". ";
implement_prompt += "Allowed paths: " + json_encode(selected.output.allowed_paths) + ". ";
implement_prompt += "Baseline HEAD must remain " + baseline_head + ". Leave changes UNCOMMITTED (git add -N only for brand-new files). ";
implement_prompt += "Tests-first: add a failing check before wiring new mint/pin/key. ";
implement_prompt += "For LH-4: EventFlow Reference OutcomeWire sidecars + digest list; observation mint stays FC. ";
implement_prompt += "For LH-5: OwnableLike only if admit already yields Outcome; otherwise stop and set blockers, do not invent. ";
implement_prompt += "For LH-6/LH-7: engineering trace pins only; formal TASK/TST status files stay pending. ";
implement_prompt += "For SYS-S4-SHARED: attachedValue through typed/normalize/reference; Plans FC. ";
implement_prompt += "For SYS-S4-EVM/NEAR/CW: only that target Plan/IR/runtime gate. ";
implement_prompt += "Run focused_checks: " + json_encode(selected.output.focused_checks) + " and record results in tests_run.";
let implementation = agent(implement_prompt, #{
    label: "implement:" + slice_id,
    phase: "Implement",
    capability_mode: "all",
    output_schema: implementation_schema,
});
if implementation == () || !implementation.success || implementation.output.implemented != true
    || implementation.output.head != baseline_head || implementation.output.uncommitted != true {
    let report = "# next-wave-runner\n\nImplement blocked.\n\n" + json_encode(implementation);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", slice_id: slice_id, report_path: path });
}
let review_diff = git_diff_since(baseline_head);
if review_diff == "" {
    let report = "# next-wave-runner\n\nNo diff after implement.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", slice_id: slice_id, report_path: path });
}
log("Implement diff " + fingerprint(review_diff));

phase("Review");
let review_jobs = [];
let dimensions = [
    #{ label: "semantic-honesty", focus: "no second step, no Anvil lossless Outcome, exact OutcomeWire identity, fail-closed observation mint, no formal overclaim" },
    #{ label: "tests-corpus", focus: "tests hit shipped functions, digest/close-case would fail if sidecars vanish, no test theater" },
    #{ label: "scope-boundary", focus: "allowed paths only, queue order, no TASK/TST status close, SBOM/docs accuracy if touched" },
];
for dimension in dimensions {
    let prompt = common + "READ-ONLY review. HEAD must equal " + baseline_head + ". Slice " + slice_id + ". Focus: "
        + dimension.focus + ". Diff: " + json_encode(review_diff)
        + ". Implementation: " + json_encode(implementation.output)
        + ". Empty findings valid only after reading the real code.";
    review_jobs.push(#{
        prompt: prompt,
        label: "review:" + dimension.label,
        phase: "Review",
        capability_mode: "read-only",
        output_schema: findings_schema,
    });
}
let reviews = parallel(review_jobs);
let findings = [];
let reviewers_ok = true;
for result in reviews {
    if result == () || !result.success || result.output.head != baseline_head {
        reviewers_ok = false;
    } else {
        for finding in result.output.findings {
            if findings.len() < 18 {
                findings.push(finding);
            } else {
                reviewers_ok = false;
            }
        }
    }
}
if !reviewers_ok {
    let report = "# next-wave-runner\n\nReview infra failed.\n\n" + json_encode(reviews);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "review", slice_id: slice_id, report_path: path });
}
log(findings.len().to_string() + " findings");

phase("Repair");
if findings.len() > 0 {
    let repair_prompt = common;
    repair_prompt += "REPAIR real P0/P1 findings for THIS slice only (" + slice_id + "). ";
    repair_prompt += "Stay in allowed_paths " + json_encode(selected.output.allowed_paths) + ". ";
    repair_prompt += "CRITICAL: do NOT commit, push, or mark the queue done here — leave work UNCOMMITTED ";
    repair_prompt += "(git add -N only for brand-new files). HEAD must remain " + baseline_head + ". ";
    repair_prompt += "remaining[] = only unresolved findings for this slice (empty when fixed); ";
    repair_prompt += "NEVER list future queue ids in remaining. ";
    repair_prompt += "Findings: " + json_encode(findings) + ". Diff: " + json_encode(git_diff_since(baseline_head));
    let repair = agent(repair_prompt, #{
        label: "repair:" + slice_id,
        phase: "Repair",
        capability_mode: "all",
        output_schema: repair_schema,
    });
    let repair_strict_ok = repair != () && repair.success && repair.output.resolved == true
        && repair.output.head == baseline_head && repair.output.uncommitted == true
        && repair.output.remaining.len() == 0;
    if !repair_strict_ok {
        let report = "# next-wave-runner\n\nRepair blocked.\n\n" + json_encode(repair);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "repair", slice_id: slice_id, report_path: path });
    }
} else {
    log("No repair");
}

phase("Verify");
let final_diff = git_diff_since(baseline_head);
let verify_prompt = common;
verify_prompt += "INDEPENDENT verify uncommitted " + slice_id + ". No edit/commit/push. HEAD " + baseline_head + ". ";
verify_prompt += "Run serially every focused check and verification_commands. ";
verify_prompt += "focused: " + json_encode(selected.output.focused_checks) + ". ";
verify_prompt += "verify: " + json_encode(selected.output.verification_commands) + ". ";
verify_prompt += "allowed: " + json_encode(selected.output.allowed_paths) + ". ";
verify_prompt += "diff: " + json_encode(final_diff) + ". ";
verify_prompt += "formal_unchanged=true only if 04-task-breakdown / 05-test-spec TASK/TST status rows were not marked done. ";
verify_prompt += "passed=true only if all commands green, scope_ok, formal_unchanged, release_not_assessed, unresolved empty.";
let verification = agent(verify_prompt, #{
    label: "verify:" + slice_id,
    phase: "Verify",
    capability_mode: "execute",
    output_schema: verification_schema,
});
let verified = verification != () && verification.success && verification.output.passed == true
    && verification.output.head == baseline_head && verification.output.scope_ok == true
    && verification.output.tests_ok == true && verification.output.diff_clean == true
    && verification.output.formal_unchanged == true && verification.output.release_not_assessed == true
    && verification.output.changed_files.len() > 0 && verification.output.unresolved.len() == 0;
if !verified {
    let report = "# next-wave-runner\n\nVerify failed; no commit.\n\n" + json_encode(verification);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "verify", slice_id: slice_id, report_path: path });
}
log("Verify passed");

phase("Commit");
let commit_prompt = "ONE local commit for next-wave slice " + slice_id + "; NEVER push. ";
commit_prompt += "HEAD must be " + baseline_head + ". Stage only verified files one-by-one with git add -- <path>. ";
commit_prompt += "Never git add -A. Run git diff --cached --check. Commit message exactly: "
    + json_encode(selected.output.commit_message) + ". ";
commit_prompt += "Then update .grok/next-wave-queue.md: mark " + slice_id
    + " as done (and clear in_progress). Stage that queue file too if changed. ";
commit_prompt += "If docs/engineering-backlog.md was part of the verified set, keep its one-line fact. ";
commit_prompt += "No amend/reset/force. Return chain + queue_updated=true when the markdown status is done.";
let committed = agent(commit_prompt, #{
    label: "commit:" + slice_id,
    phase: "Commit",
    capability_mode: "all",
    output_schema: commit_schema,
});
if committed == () || !committed.success || committed.output.committed != true {
    let report = "# next-wave-runner\n\nCommit failed.\n\n" + json_encode(committed);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "commit", slice_id: slice_id, report_path: path });
}
let chain_ok = committed.output.head_before == baseline_head
    && committed.output.head_after == committed.output.commit
    && committed.output.parent == baseline_head;
let worktree_ok = committed.output.worktree_clean == true && git_diff_since("HEAD") == "";
let final_status = if chain_ok && worktree_ok { "committed" } else { "committed-invalid" };
let report = "# next-wave-runner\n\n**Status:** " + final_status
    + "\n\n**Slice:** " + slice_id
    + "\n\n**Commit:** `" + committed.output.commit + "`\n\n"
    + "Nothing pushed. Goal drain or the next `/workflow next-wave-runner` picks the following pending row.\n\n"
    + json_encode(committed.output);
let report_path = write_scratch_file("report.md", report);
complete(#{
    status: final_status,
    slice_id: slice_id,
    commit: committed.output.commit,
    report_path: report_path,
    agent_calls: budget().spent,
});
