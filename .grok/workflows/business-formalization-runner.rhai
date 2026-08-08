let meta = #{
    name: "business-formalization-runner",
    description: "Autonomous track-1 business formalization: next packaging/unpin/docs slice, review, verify, commit; no user continue",
    when_to_use: "Keep advancing ADR-0034 business-logic formalization after EvenCounter GREEN without per-slice user prompts",
    phases: [
        #{ title: "Select", detail: "read queue and claim next pending slice" },
        #{ title: "Implement", detail: "tests-first packaging or path hardening" },
        #{ title: "Review", detail: "parallel semantic / proof / boundary review" },
        #{ title: "Repair", detail: "fix real findings" },
        #{ title: "Verify", detail: "focused lake builds + product gate + docs if needed" },
        #{ title: "Commit", detail: "one local commit; never push; update queue" },
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
            "properties": #{ "command": #{ "type": "string" }, "result": #{ "type": "string" } },
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

let common = "ProofForge track-1 BUSINESS formalization (ADR-0034 D10). NOT tool-internal formal TASK/TST. ";
common += "Read AGENTS.md Current Checkpoint Active/Next, RECOVERY L1 note, docs/adr/0034-preservation-abi.md D9/D10, ";
common += ".grok/business-formalization-queue.md, ProofForgeV2/ProofInstances/EvenCounterPreservationV1.lean, ";
common += "ProofForgeV2/Semantic/PreservationABI.lean, ClosedSubjectPinV1, ReferenceMachineV1 packaging theorems. ";
common += "Sole L1 step authority: admitReferenceProgramSliceV1 + stepReferenceSliceV1. ";
common += "FORBIDDEN: second State/Effect/step; MiniAmm special helpers; supersede ADR-0027; formal overclaim; push; force; amend; reset --hard; checkout --; git add -A; network install; secrets. ";
common += "Pin is golden accelerator only. Second non-AMM instance is DEFERRED (not this runner). ";
common += "Commits allowed when green. Prefer leanest complete slice. ";

phase("Select");
let select_prompt = common;
select_prompt += "SELECT next work. Run git status --short and git rev-parse HEAD. Read .grok/business-formalization-queue.md. ";
select_prompt += "If worktree is dirty with unrelated WIP, set ready=false with blockers (do not destroy work). ";
select_prompt += "If all slices done, set program_complete=true, ready=false, slice_id=done, objective=complete. ";
select_prompt += "Else pick first pending (or stuck in_progress) row in order bf-pack-1, bf-pack-2, bf-unpin-1, bf-docs-1. ";
select_prompt += "Mark that row in_progress in the queue file only if worktree clean. ";
select_prompt += "Set allowed_paths tightly for the slice (Semantic/ + ProofInstances/ + Tests/Compiler for pack; ";
select_prompt += "Compiler/Language pin for unpin; docs/ AGENTS RECOVERY MIGRATION for docs). ";
select_prompt += "focused_checks must include lake build of touched modules and, if proof path touched, ";
select_prompt += "lake env lean --run Tests/Compiler/InlineProofCertifierV1.lean or lake build Tests.Compiler.InlineProofCertifierV1. ";
select_prompt += "verification_commands must include git diff --check; if product Lean changed also just sbom-package-files-refresh; if docs changed just docs-check; always a focused lake build preserving EvenCounter GREEN. ";
select_prompt += "Prefer just dev-check over full just ci unless docs/product surface requires it. ";
select_prompt += "commit_message imperative one-line. ready=true only if clean tree and a concrete slice is claimable.";
let selected = agent(select_prompt, #{
    label: "select-slice",
    phase: "Select",
    capability_mode: "all",
    output_schema: select_schema,
});
if selected == () || !selected.success {
    let report = "# business-formalization-runner\n\nSelect agent failed.\n\n" + json_encode(selected);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "select", report_path: path });
}
if selected.output.program_complete == true {
    let report = "# business-formalization-runner\n\n**Program complete.** All queue slices done.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "program_complete", report_path: path });
}
if selected.output.ready != true || selected.output.blockers.len() != 0 {
    let report = "# business-formalization-runner\n\nBlocked at select.\n\n" + json_encode(selected.output);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "select", report_path: path, blockers: selected.output.blockers });
}
let baseline_head = selected.output.head;
baseline_head.trim();
let slice_id = selected.output.slice_id;
log("Selected " + slice_id + " at " + baseline_head);

phase("Implement");
let implement_prompt = common;
implement_prompt += "IMPLEMENT slice " + slice_id + " only. Objective: " + json_encode(selected.output.objective) + ". ";
implement_prompt += "Allowed paths: " + json_encode(selected.output.allowed_paths) + ". ";
implement_prompt += "Baseline HEAD must remain " + baseline_head + ". Leave changes UNCOMMITTED (git add -N only for brand-new files). ";
implement_prompt += "Tests-first when adding lemmas: build must fail closed before wiring if you introduce new modules. ";
implement_prompt += "For bf-pack-1: create shared packaging module; move only truly generic lemmas; do not break EvenCounter. ";
implement_prompt += "For bf-pack-2: refactor instance to use packaging; delete safe duplicates. ";
implement_prompt += "For bf-unpin-1: non-pin path clarity + tests if product surface needs them; no forced pin growth. ";
implement_prompt += "For bf-docs-1: honest docs only after code facts exist. ";
implement_prompt += "Run focused_checks: " + json_encode(selected.output.focused_checks) + " and record results in tests_run.";
let implementation = agent(implement_prompt, #{
    label: "implement:" + slice_id,
    phase: "Implement",
    capability_mode: "all",
    output_schema: implementation_schema,
});
if implementation == () || !implementation.success || implementation.output.implemented != true
    || implementation.output.head != baseline_head || implementation.output.uncommitted != true {
    let report = "# business-formalization-runner\n\nImplement blocked.\n\n" + json_encode(implementation);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", slice_id: slice_id, report_path: path });
}
let review_diff = git_diff_since(baseline_head);
if review_diff == "" {
    let report = "# business-formalization-runner\n\nNo diff after implement.\n";
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "implement", slice_id: slice_id, report_path: path });
}
log("Implement diff " + fingerprint(review_diff));

phase("Review");
let review_jobs = [];
let dimensions = [
    #{ label: "semantic-proof", focus: "lemma generality, no second step, exact Reference packaging, defeq safety, no vacuous preservation" },
    #{ label: "product-green", focus: "EvenCounter product certifier still GREEN, pin not mandatory path, no formal overclaim in comments" },
    #{ label: "scope-boundary", focus: "allowed paths only, queue order, no MiniAmm, no ADR-0027 supersession, SBOM/docs accuracy if touched" },
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
            if findings.len() < 18 { findings.push(finding); } else { reviewers_ok = false; }
        }
    }
}
if !reviewers_ok {
    let report = "# business-formalization-runner\n\nReview infra failed.\n\n" + json_encode(reviews);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "review", slice_id: slice_id, report_path: path });
}
log(findings.len().to_string() + " findings");

phase("Repair");
let repair = ();
if findings.len() > 0 {
    let repair_prompt = common;
    repair_prompt += "REPAIR real P0/P1 findings for THIS slice only (" + slice_id + "). ";
    repair_prompt += "Stay in allowed_paths " + json_encode(selected.output.allowed_paths) + ". ";
    repair_prompt += "CRITICAL: do NOT commit, push, or mark the queue done here — leave work UNCOMMITTED ";
    repair_prompt += "(git add -N only for brand-new files). HEAD must remain " + baseline_head + ". ";
    repair_prompt += "remaining[] = only unresolved findings for this slice (empty when fixed); ";
    repair_prompt += "NEVER list future queue ids (bf-pack-2/bf-unpin/bf-docs) in remaining. ";
    repair_prompt += "Findings: " + json_encode(findings) + ". Diff: " + json_encode(git_diff_since(baseline_head));
    repair = agent(repair_prompt, #{
        label: "repair:" + slice_id,
        phase: "Repair",
        capability_mode: "all",
        output_schema: repair_schema,
    });
    // Prefer the strict uncommitted path. If a repair agent already committed a
    // green slice (legacy misbehavior), accept when tree is clean and HEAD moved.
    let repair_strict_ok = repair != () && repair.success && repair.output.resolved == true
        && repair.output.head == baseline_head && repair.output.uncommitted == true
        && repair.output.remaining.len() == 0;
    let repair_already_committed = repair != () && repair.success && repair.output.resolved == true
        && repair.output.uncommitted == false && repair.output.head != baseline_head
        && git_diff_since("HEAD") == "";
    if !repair_strict_ok && !repair_already_committed {
        let report = "# business-formalization-runner\n\nRepair blocked.\n\n" + json_encode(repair);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", stage: "repair", slice_id: slice_id, report_path: path });
    }
    if repair_already_committed {
        let report = "# business-formalization-runner\n\n**Status:** committed-via-repair\n\n**Slice:** "
            + slice_id + "\n\n**Commit:** `" + repair.output.head
            + "`\n\nRepair agent committed early; accepted because worktree clean. "
            + "Next fire continues queue.\n\n" + json_encode(repair.output);
        let path = write_scratch_file("report.md", report);
        complete(#{
            status: "committed",
            slice_id: slice_id,
            commit: repair.output.head,
            report_path: path,
            agent_calls: budget().spent,
            note: "repair-early-commit-accepted",
        });
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
verify_prompt += "EvenCounter preserving product must still be buildable GREEN if Lean proof modules touched. ";
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
    let report = "# business-formalization-runner\n\nVerify failed; no commit.\n\n" + json_encode(verification);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "verify", slice_id: slice_id, report_path: path });
}
log("Verify passed");

phase("Commit");
let commit_prompt = "ONE local commit for business formalization slice " + slice_id + "; NEVER push. ";
commit_prompt += "HEAD must be " + baseline_head + ". Stage only verified files one-by-one with git add -- <path>. ";
commit_prompt += "Never git add -A. Run git diff --cached --check. Commit message exactly: "
    + json_encode(selected.output.commit_message) + ". ";
commit_prompt += "Then update .grok/business-formalization-queue.md: mark " + slice_id
    + " as done (and clear in_progress). Stage that queue file too if changed. ";
commit_prompt += "No amend/reset/force. Return chain + queue_updated=true when the markdown status is done.";
let committed = agent(commit_prompt, #{
    label: "commit:" + slice_id,
    phase: "Commit",
    capability_mode: "all",
    output_schema: commit_schema,
});
if committed == () || !committed.success || committed.output.committed != true {
    let report = "# business-formalization-runner\n\nCommit failed.\n\n" + json_encode(committed);
    let path = write_scratch_file("report.md", report);
    complete(#{ status: "blocked", stage: "commit", slice_id: slice_id, report_path: path });
}
let chain_ok = committed.output.head_before == baseline_head
    && committed.output.head_after == committed.output.commit
    && committed.output.parent == baseline_head;
let worktree_ok = committed.output.worktree_clean == true && git_diff_since("HEAD") == "";
let final_status = if chain_ok && worktree_ok { "committed" } else { "committed-invalid" };
let report = "# business-formalization-runner\n\n**Status:** " + final_status
    + "\n\n**Slice:** " + slice_id
    + "\n\n**Commit:** `" + committed.output.commit + "`\n\n"
    + "Nothing pushed. Next durable scheduler fire should pick the following pending row.\n\n"
    + json_encode(committed.output);
let report_path = write_scratch_file("report.md", report);
complete(#{
    status: final_status,
    slice_id: slice_id,
    commit: committed.output.commit,
    report_path: report_path,
    agent_calls: budget().spent,
});
