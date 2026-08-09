let meta = #{
    name: "business-formalization-drain",
    description: "Drain track-1 business formalization queue: up to 4 slices in one run, commit each, no user continue",
    when_to_use: "After EvenCounter GREEN: keep packaging/unpin/docs running until queue empty without asking the user to continue",
    phases: [
        #{ title: "Drain", detail: "repeat select→implement→review→verify→commit until done or max slices" },
    ],
};

let result_schema = #{
    "type": "object",
    "required": ["status", "summary", "slice_id", "commit", "program_complete", "blockers"],
    "properties": #{
        "status": #{ "type": "string" },
        "summary": #{ "type": "string" },
        "slice_id": #{ "type": "string" },
        "commit": #{ "type": "string" },
        "program_complete": #{ "type": "boolean" },
        "blockers": #{ "type": "array", "maxItems": 12, "items": #{ "type": "string" } },
        "files_changed": #{ "type": "array", "maxItems": 80, "items": #{ "type": "string" } },
    },
};

// Drain at most 4 slices per fire (queue length). No user pause.
let max_slices = 4;
let done_ids = [];
let last_status = "idle";
let i = 0;
while i < max_slices {
    let idx = i + 1;
    phase("Drain");
    log("Drain pass " + idx.to_string() + "/" + max_slices.to_string());

    let prompt = "";
    prompt += "You are the ProofForge track-1 BUSINESS formalization DRAIN agent. ";
    prompt += "Do ALL of the following in one shot for THE NEXT pending slice only; then stop. ";
    prompt += "Read .grok/business-formalization-queue.md, AGENTS.md, ADR-0034 D9/D10. ";
    prompt += "Queue order: bf-pack-1, bf-pack-2, bf-unpin-1, bf-docs-1. Skip done. ";
    prompt += "If worktree has uncommitted work that is clearly this queue (packaging/EvenCounter/pin/docs/queue file), ";
    prompt += "FIRST finish verify+local-commit that work and mark the matching row done. ";
    prompt += "Else claim first pending/in_progress, implement minimum complete contract, focused lake builds, ";
    prompt += "sbom refresh if ProofForgeV2/**, docs-check if docs, git diff --check, ONE local commit, mark done. ";
    prompt += "NEVER push. NEVER second State/Effect/step. NEVER MiniAmm special-case. NEVER supersede ADR-0027. ";
    prompt += "NEVER git add -A / reset --hard / amend. Pin is golden accelerator only. ";
    prompt += "If all rows done: status=program_complete, program_complete=true, slice_id=done. ";
    prompt += "If hard blocked (unrelated dirty tree): status=blocked, list blockers. ";
    prompt += "If one slice committed: status=committed, set commit sha, slice_id, files_changed. ";
    prompt += "EvenCounter product path must stay buildable GREEN when Lean proof modules change ";
    prompt += "(lake build Tests.Compiler.InlineProofCertifierV1). ";
    prompt += "Prefer leanest complete change. Update queue markdown status. ";

    let r = agent(prompt, #{
        label: "drain-slice-" + idx.to_string(),
        phase: "Drain",
        capability_mode: "all",
        output_schema: result_schema,
    });

    if r == () || !r.success {
        let report = "# business-formalization-drain\n\nAgent failed on pass " + idx.to_string()
            + "\n\n" + json_encode(r);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", pass: idx, done_ids: done_ids, report_path: path });
    }

    last_status = r.output.status;
    if r.output.program_complete == true || r.output.status == "program_complete" {
        let report = "# business-formalization-drain\n\n**Program complete.**\n\nDone this run: "
            + json_encode(done_ids) + "\n\n" + r.output.summary;
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "program_complete", done_ids: done_ids, report_path: path });
    }
    let blockers = r.output.blockers;
    let has_blockers = blockers != () && type_of(blockers) == "array" && blockers.len() > 0;
    if r.output.status == "blocked" || has_blockers {
        let report = "# business-formalization-drain\n\nBlocked on " + r.output.slice_id
            + "\n\n" + json_encode(r.output);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", slice_id: r.output.slice_id, done_ids: done_ids, report_path: path, blockers: blockers });
    }
    let commit = r.output.commit;
    let has_commit = commit != () && type_of(commit) == "string" && commit != "";
    if r.output.status == "committed" || has_commit {
        done_ids.push(r.output.slice_id);
        log("Committed " + r.output.slice_id + " @ " + commit);
    } else {
        let report = "# business-formalization-drain\n\nUnexpected status\n\n" + json_encode(r.output);
        let path = write_scratch_file("report.md", report);
        complete(#{ status: "blocked", done_ids: done_ids, report_path: path });
    }
    i += 1;
}

let report = "# business-formalization-drain\n\nMax slices reached this fire.\n\nDone: "
    + json_encode(done_ids) + "\n\nLast status: " + last_status
    + "\n\nRe-run `/workflow business-formalization-drain` or Goal prompt-business-formalization to continue.";
let path = write_scratch_file("report.md", report);
complete(#{ status: "max_slices", done_ids: done_ids, report_path: path, last_status: last_status });
