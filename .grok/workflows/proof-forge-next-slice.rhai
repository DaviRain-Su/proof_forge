let meta = #{
    name: "proof-forge-next-slice",
    description: "Continuously advance bounded ProofForge slices with independent verification and one local commit per slice",
    phases: [
        #{ title: "Plan", detail: "read the latest committed checkpoint and select one bounded slice" },
        #{ title: "Implement", detail: "write failing tests and implement without committing" },
        #{ title: "Review", detail: "independently audit the uncommitted slice" },
        #{ title: "Verify", detail: "fix confirmed issues and run all product gates without committing" },
        #{ title: "Commit", detail: "guard the baseline and create exactly one local slice commit" },
    ],
    when_to_use: "Use to keep advancing ProofForge V2 recovery across committed bounded slices without pushing or claiming formal qualification.",
};

let plan_schema = #{
    "type": "object",
    "required": ["proceed", "slice", "rationale", "implementation_prompt", "stop_reason", "base_commit"],
    "properties": #{
        "proceed": #{ "type": "boolean" },
        "slice": #{ "type": "string" },
        "rationale": #{ "type": "string" },
        "implementation_prompt": #{ "type": "string" },
        "stop_reason": #{ "type": "string" },
        "base_commit": #{ "type": "string" },
    },
};
let implementation_schema = #{
    "type": "object",
    "required": ["success", "summary", "files", "tests", "limitations"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "files": #{ "type": "array", "maxItems": 50, "items": #{ "type": "string" } },
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
        "files_to_commit": #{ "type": "array", "minItems": 1, "maxItems": 60, "items": #{ "type": "string" } },
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

let objective = "Continue ProofForge V2 recovery across successive bounded migration slices.";
if args != () && args.objective != () { objective = args.objective; }
let max_slices = 20;
if args != () && args.max_slices != () {
    if args.max_slices > 0 && args.max_slices <= 20 { max_slices = args.max_slices; }
}

let round = 0;
let active = true;
let stop_reason = "maximum slice cap reached";
let completed_slices = [];
let round_results = [];
let report = "# ProofForge continuous committed recovery run\n\n";
report += "Objective: " + objective + "\n\n";

while active && round < max_slices {
    let budget_now = budget();
    if budget_now.remaining < 5 {
        active = false;
        stop_reason = "fewer than five agent calls remain; stopped before a partial slice";
    } else {
        round += 1;
        log("Starting committed recovery round " + round.to_string() + "; remaining agent budget " + budget_now.remaining.to_string());
        let completed_json = json_encode(completed_slices);

        phase("Plan");
        let planner_prompt = "Work read-only in the ProofForge repository. This is round " + round.to_string() + " of a continuous committed run. Read AGENTS.md completely, run git status --short and git rev-parse HEAD, then read RECOVERY.md, MIGRATION_MATRIX.md, docs/document-status.md, docs/index.md, docs/01-prd.md, docs/02-architecture.md, and docs/03-technical-spec.md in the mandated order. The working tree must be clean at round start. Inspect actual code, tests, and recent git history. Earlier rounds in this run are JSON: " + completed_json + ". Select exactly one smallest safe next slice in D1→D2→D3→D4 order; do not repeat a completed slice. If the tree is dirty, no safe task exists, or design authority is required, set proceed=false with a precise stop_reason. Return the exact current 40-hex HEAD as base_commit and a self-contained implementation prompt naming specs, files, failing tests, boundaries, and checks. Do not invent formal completion or expand qualification/governance. Objective: " + objective;
        let planned = agent(planner_prompt, #{ label: "planner-r" + round.to_string(), capability_mode: "read-only", output_schema: plan_schema });
        if planned == () || planned.success == false {
            complete(#{ status: "blocked", round: round, stop_reason: "planning agent failed", slices_completed: completed_slices });
        }

        let base_commit = planned.output.base_commit;
        if base_commit == () { base_commit = "validation-placeholder"; }

        if planned.output.proceed == false {
            active = false;
            stop_reason = planned.output.stop_reason;
            report += "## Round " + round.to_string() + " — stopped\n\n" + planned.output.rationale + "\n\n";
        } else {
            if base_commit == "" {
                complete(#{ status: "blocked", round: round, stop_reason: "planner returned an empty round baseline commit", slices_completed: completed_slices });
            }
            log("Round " + round.to_string() + " selected: " + planned.output.slice);

            phase("Implement");
            let implement_prompt = "Implement exactly one bounded ProofForge migration slice in the shared working tree for round " + round.to_string() + ". Re-read AGENTS.md; verify git rev-parse HEAD equals baseline " + base_commit + " and the tree is clean before editing. Add focused failing tests first, then minimum production implementation. Keep source/Typed/Semantic target-neutral. Do not commit, stage, push, amend, reset, or start another slice. No adapters, fallback, formal evidence, release/governance work, or maturity overclaims. Run focused tests. If ProofForgeV2/** changes, run just sbom-package-files-refresh. Update only directly relevant MIGRATION_MATRIX.md, AGENTS.md, and implementation facts. Leave all slice changes uncommitted for independent review. Planner task: " + planned.output.implementation_prompt;
            let implemented = agent(implement_prompt, #{ label: "implementer-r" + round.to_string(), capability_mode: "all", output_schema: implementation_schema });
            if implemented == () || implemented.success == false || implemented.output.success == false {
                complete(#{ status: "blocked", round: round, stop_reason: "implementation failed; inspect the uncommitted tree", slice: planned.output.slice, slices_completed: completed_slices });
            }

            phase("Review");
            let changed_json = json_encode(implemented.output.files);
            let review_prompt = "Independently review ProofForge round " + round.to_string() + " slice: " + planned.output.slice + ". Read AGENTS.md and relevant accepted specs. Verify HEAD still equals baseline " + base_commit + "; if HEAD moved, report a critical finding because only the final committer may commit. Inspect git diff, untracked files, and every implementer-listed file: " + changed_json + ". Check semantics, fail-closed behavior, diagnostics, negative tests, scope, pins, maturity claims, and D1→D2→D3→D4 boundaries. Do not edit, stage, commit, or push. Only evidence-backed findings count. Implementation summary: " + implemented.output.summary;
            let reviewed = agent(review_prompt, #{ label: "reviewer-r" + round.to_string(), capability_mode: "read-only", output_schema: review_schema });
            if reviewed == () || reviewed.success == false {
                complete(#{ status: "blocked", round: round, stop_reason: "independent review failed", slice: planned.output.slice, slices_completed: completed_slices });
            }

            phase("Verify");
            let findings_json = json_encode(reviewed.output.findings);
            let verify_prompt = "Own final repair and verification for ProofForge round " + round.to_string() + ". Verify HEAD still equals baseline " + base_commit + ". Read AGENTS.md and inspect the full uncommitted diff. Validate every reviewer finding and fix only confirmed issues without expanding this slice. Run focused tests, git diff --check, just sbom-package-files-refresh when ProofForgeV2/** changed, and ordinary just ci. Never run governance-check or release-check. Do not stage, commit, push, amend, reset, or start the next task. Leave a complete uncommitted slice for the dedicated committer. Return the exact explicit file list to commit and ready_to_commit=true only if all gates pass, HEAD is unchanged, and there are no unrelated files. Keep formal statuses honest. Slice: " + planned.output.slice + ". Findings JSON: " + findings_json;
            let verified = agent(verify_prompt, #{ label: "fixer-verifier-r" + round.to_string(), capability_mode: "all", output_schema: verification_schema });
            if verified == () || verified.success == false || verified.output.success == false || verified.output.ready_to_commit == false {
                complete(#{ status: "blocked", round: round, stop_reason: "repair or verification failed; inspect the uncommitted tree", slice: planned.output.slice, slices_completed: completed_slices });
            }

            phase("Commit");
            let files_json = json_encode(verified.output.files_to_commit);
            let commit_prompt = "Act only as the local committer for one already verified ProofForge slice. Do not edit source or tests and do not rerun or expand implementation. First verify git rev-parse HEAD exactly equals baseline " + base_commit + ". Inspect git status and ensure every dirty/untracked path belongs to this explicit verified list: " + files_json + ". If HEAD moved, the tree is clean, a dirty path is absent from the list, or a listed path is unrelated/missing, return success=false without changing git. Otherwise stage each explicit path individually with git add <path>; never use git add -A or git add . Check git diff --cached --check and inspect the staged diff. Create exactly one local commit with a concise imperative subject describing only slice " + planned.output.slice + ". Never amend and never push. After committing, require a clean working tree. Return actual git rev-parse HEAD and git log -1 --format=%s. Verification summary: " + verified.output.summary;
            let committed = agent(commit_prompt, #{ label: "committer-r" + round.to_string(), capability_mode: "all", output_schema: commit_schema });
            if committed == () || committed.success == false || committed.output.success == false || committed.output.commit_hash == () || committed.output.commit_hash == "" {
                complete(#{ status: "blocked", round: round, stop_reason: "dedicated local commit failed; inspect git status", slice: planned.output.slice, slices_completed: completed_slices });
            }

            completed_slices.push(#{ round: round, slice: planned.output.slice, summary: verified.output.summary, next_hint: verified.output.next_hint, commit_hash: committed.output.commit_hash, commit_message: committed.output.commit_message });
            round_results.push(#{ slice: planned.output.slice, verification: verified.output.verification, remaining_limits: verified.output.remaining_limits, commit_hash: committed.output.commit_hash });
            report += "## Round " + round.to_string() + " — " + planned.output.slice + "\n\n";
            report += "**Plan:** " + planned.output.rationale + "\n\n";
            report += "**Implementation:** " + implemented.output.summary + "\n\n";
            report += "**Review:** " + reviewed.output.summary + "\n\n";
            report += "**Verification:** " + verified.output.summary + "\n\n";
            report += "**Commit:** `" + committed.output.commit_hash + "` " + committed.output.commit_message + "\n\n";
            report += "**Next hint:** " + verified.output.next_hint + "\n\n";
            log("Round " + round.to_string() + " committed: " + committed.output.commit_hash);
        }
    }
}

if round >= max_slices && active { stop_reason = "maximum slice cap reached"; }
report += "## Stop condition\n\n" + stop_reason + "\n";
let report_path = write_scratch_file("proof-forge-continuous-recovery.md", report);
complete(#{ status: "completed", slices_completed: completed_slices, rounds_started: round, stop_reason: stop_reason, results: round_results, report_path: report_path });
