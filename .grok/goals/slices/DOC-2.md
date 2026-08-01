# Goal slice — DOC-2: Rescan NEAR op coverage matrix

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`DOC-2`

## Phase
`docs` · milestone hint `D2` · shared_cutover `False`

## Objective
Code-scan Targets/Near against docs/research/12-target-coverage-matrix.md: convert GAP to LOWERED or FAIL-CLOSED+tests. Update matrix only with evidence.

## Dependencies (must be done or explicitly waived)
(none)

## Allowed path prefixes
```
docs/research/12-target-coverage-matrix.md
ProofForgeV2/Targets/Near/
docs/engineering-backlog.md
```

## Focused checks
```
just docs-check
```

## Standard verification
```
just docs-check
just dev-check   # when product/docs touched
just ci          # before treating slice complete if product code changed
git diff --check
```
Skip ci only for pure docs research slices; still run docs-check.

## Engineering-slice args skeleton
```json
{
  "slice_id": "DOC-2",
  "milestone": "D2",
  "objective": "Code-scan Targets/Near against docs/research/12-target-coverage-matrix.md: convert GAP to LOWERED or FAIL-CLOSED+tests. Update matrix only with evidence.",
  "dependencies": [],
  "allowed_paths": ["docs/research/12-target-coverage-matrix.md", "ProofForgeV2/Targets/Near/", "docs/engineering-backlog.md"],
  "focused_checks": ["just docs-check"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "slice(DOC-2): rescan-near-op-coverage-matrix",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. Read-only product code preferred; tests only if marking FAIL-CLOSED needs them."
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"DOC-2","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
3. Or full: workflow `proof-forge-engineering-slice` with milestone/objective/allowed_paths from this file.
4. One local commit; never push.

## Global forbidden
- No push, force, amend of published commits, secrets, network package install
- No new formal TASK-*/TST-*/EV-*/freeze objects
- No just governance-check / release-check / Stage-0
- No fallback/dual-reader/second ProgramV1 decoder
- No formal D1–D4 completion claims
- ProofForgeV2 changes ⇒ just sbom-package-files-refresh
- Update docs/engineering-backlog.md status for this ID when done


## Notes
Read-only product code preferred; tests only if marking FAIL-CLOSED needs them.
