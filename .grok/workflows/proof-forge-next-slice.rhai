let meta = #{
    name: "proof-forge-next-slice",
    description: "Continuously advance and locally commit bounded ProofForge recovery slices until blocked, capped, or out of agent budget",
    phases: [
        #{ title: "Plan", detail: "re-read the latest checkpoint and select the next bounded slice" },
        #{ title: "Implement", detail: "write failing tests, implement, and run focused checks" },
        #{ title: "Review", detail: "independently audit the new slice and accumulated boundaries" },
        #{ title: "Verify", detail: "fix issues, run product gates, create one local commit, then continue" },
    ],
    when_to_use: "Use to keep advancing ProofForge V2 recovery across successive bounded slices without formal qualification claims.",
};

let plan_schema = #{
    "type": "object",
    "required": ["proceed", "slice", "rationale", "implementation_prompt", "stop_reason"],
    "properties": #{
        "proceed": #{ "type": "boolean" },
        "slice": #{ "type": "string" },
        "rationale": #{ "type": "string" },
        "implementation_prompt": #{ "type": "string" },
        "stop_reason": #{ "type": "string" },
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
let final_schema = #{
    "type": "object",
    "required": ["success", "summary", "verification", "remaining_limits", "next_hint", "commit_hash", "commit_message"],
    "properties": #{
        "success": #{ "type": "boolean" },
        "summary": #{ "type": "string" },
        "verification": #{ "type": "array", "maxItems": 30, "items": #{ "type": "string" } },
        "remaining_limits": #{ "type": "array", "maxItems": 20, "items": #{ "type": "string" } },
        "next_hint": #{ "type": "string" },
        "commit_hash": #{ "type": "string", "minLength": 1 },
        "commit_message": #{ "type": "string", "minLength": 1 },
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
let report = "# ProofForge continuous recovery run\n\n";
report += "Objective: " + objective + "\n\n";

while active && round < max_slices {
    let budget_now = budget();
    if budget_now.remaining < 4 {
        active = false;
        stop_reason = "fewer than four agent calls remain; stopped before starting a partial slice";
    } else {
        round += 1;
        log("Starting recovery round " + round.to_string() + "; remaining agent budget " + budget_now.remaining.to_string());
        let completed_json = json_encode(completed_slices);

        phase("Plan");
        let planner_prompt = "Work read-only in the ProofForge repository. This is round " + round.to_string() + " of a continuous run. Read AGENTS.md completely, run git status --short, then read RECOVERY.md, MIGRATION_MATRIX.md, docs/document-status.md, docs/index.md, docs/01-prd.md, docs/02-architecture.md, and docs/03-technical-spec.md in the mandated order. Inspect actual code, tests, git history, and working tree. Earlier successful rounds must already be local commits, so unfamiliar dirty files must set proceed=false. The earlier rounds in this same run are JSON: " + completed_json + ". Re-evaluate the latest checkpoint after those rounds and select exactly one smallest safe next slice, in D1→D2→D3→D4 order. Never select a slice already represented in that list merely to rename or restate it. A dirty working tree at round start is unexpected because the prior round must commit; unfamiliar or conflicting work, no safe next task, or a dependency requiring product/design authority must set proceed=false with a precise stop_reason. Do not invent formal TASK completion and do not expand qualification/governance. Return a self-contained implementation prompt naming specs, files, failing tests, boundaries, and required checks. Objective: " + objective;
        let planned = agent(planner_prompt, #{ label: "planner-r" + round.to_string(), capability_mode: "read-only", output_schema: plan_schema });
        if planned == () || planned.success == false { pause("infra", "Planning failed in round " + round.to_string() + "; inspect the workflow before resuming."); }

        if planned.output.proceed == false {
            active = false;
            stop_reason = planned.output.stop_reason;
            report += "## Round " + round.to_string() + " — stopped\n\n";
            report += planned.output.rationale + "\n\nReason: " + stop_reason + "\n\n";
        } else {
            log("Round " + round.to_string() + " selected: " + planned.output.slice);

            phase("Implement");
            let implement_prompt = "Implement exactly one bounded ProofForge migration slice in the shared working tree. This is continuous-run round " + round.to_string() + ". Re-read AGENTS.md and inspect current git status/diff; require a clean round-start tree and preserve all committed earlier rounds. Add focused failing tests first, then minimum production implementation. Keep source/Typed/Semantic target-neutral. No adapters, fallback, formal evidence, release/governance work, commits, pushes, destructive git commands, or maturity overclaims. Run focused tests. If ProofForgeV2/** changes, run just sbom-package-files-refresh. Update only directly relevant MIGRATION_MATRIX.md and AGENTS.md facts. Do not opportunistically start the following slice. Planner task: " + planned.output.implementation_prompt;
            let implemented = agent(implement_prompt, #{ label: "implementer-r" + round.to_string(), capability_mode: "all", output_schema: implementation_schema });
            if implemented == () || implemented.success == false || implemented.output.success == false { pause("blocked", "Implementation failed in round " + round.to_string() + ". Inspect the working tree before resuming."); }

            phase("Review");
            let changed_json = json_encode(implemented.output.files);
            let review_prompt = "Independently review continuous-run round " + round.to_string() + " for ProofForge slice: " + planned.output.slice + ". Read AGENTS.md and relevant accepted specs. Inspect actual git diff and every file listed by the implementer: " + changed_json + ". Focus on this round while checking interactions with accumulated prior-round changes. Look for semantic bugs, fail-open behavior, incorrect diagnostic phase/order, missing negative tests, accidental scope expansion, stale package pins, and violations of D1→D2→D3→D4 or target-neutral boundaries. Do not edit. Only concrete evidence-backed findings count; empty findings is valid only after actual inspection. Implementation summary: " + implemented.output.summary;
            let reviewed = agent(review_prompt, #{ label: "reviewer-r" + round.to_string(), capability_mode: "read-only", output_schema: review_schema });
            if reviewed == () || reviewed.success == false { pause("infra", "Independent review failed in round " + round.to_string() + "; verification cannot proceed."); }

            phase("Verify");
            let findings_json = json_encode(reviewed.output.findings);
            let verify_prompt = "Own final repair, verification, and local checkpoint commit for continuous-run round " + round.to_string() + " in the shared ProofForge tree. Read AGENTS.md and inspect the actual diff. Independently verify every reviewer finding and fix only confirmed issues without expanding scope. Run focused tests, git diff --check, just sbom-package-files-refresh when ProofForgeV2/** changed, and ordinary just ci. Never run governance-check or release-check and never push. After every check passes, inspect git status, stage only the explicit files belonging to this slice with git add <specific paths> (never git add -A or git add .), re-run git diff --cached --check, and create exactly one local commit with a concise imperative message. Include docs/tests/pins changed by this slice. Fail with success=false if there is nothing to commit, unrelated dirty state exists, staging is incomplete, or commit fails. Return the actual git rev-parse HEAD as commit_hash and actual commit subject as commit_message. Keep formal task statuses pending unless independent authority truly closes them. Report a next_hint for the next planner, but do not implement it. Slice: " + planned.output.slice + ". Findings JSON: " + findings_json;
            let finalized = agent(verify_prompt, #{ label: "fixer-verifier-r" + round.to_string(), capability_mode: "all", output_schema: final_schema });
            if finalized == () || finalized.success == false || finalized.output.success == false { pause("verification", "Final repair, ordinary CI, or local commit failed in round " + round.to_string() + ". Inspect logs before resuming."); }
            if finalized.output.commit_hash == () || finalized.output.commit_hash == "" || finalized.output.commit_message == () || finalized.output.commit_message == "" { pause("verification", "Round " + round.to_string() + " did not return a verified local commit identity."); }

            completed_slices.push(#{ round: round, slice: planned.output.slice, summary: finalized.output.summary, next_hint: finalized.output.next_hint, commit_hash: finalized.output.commit_hash, commit_message: finalized.output.commit_message });
            round_results.push(#{ slice: planned.output.slice, verification: finalized.output.verification, remaining_limits: finalized.output.remaining_limits, commit_hash: finalized.output.commit_hash });
            report += "## Round " + round.to_string() + " — " + planned.output.slice + "\n\n";
            report += "**Plan:** " + planned.output.rationale + "\n\n";
            report += "**Implementation:** " + implemented.output.summary + "\n\n";
            report += "**Review:** " + reviewed.output.summary + "\n\n";
            report += "**Verification:** " + finalized.output.summary + "\n\n";
            report += "**Commit:** `" + finalized.output.commit_hash + "` " + finalized.output.commit_message + "\n\n";
            report += "**Next hint:** " + finalized.output.next_hint + "\n\n";
            log("Round " + round.to_string() + " committed after ordinary CI: " + finalized.output.commit_hash);
        }
    }
}

if round >= max_slices && active { stop_reason = "maximum slice cap reached"; }
report += "## Stop condition\n\n" + stop_reason + "\n";
let report_path = write_scratch_file("proof-forge-continuous-recovery.md", report);
complete(#{
    status: "completed",
    slices_completed: completed_slices,
    rounds_started: round,
    stop_reason: stop_reason,
    results: round_results,
    report_path: report_path,
});
