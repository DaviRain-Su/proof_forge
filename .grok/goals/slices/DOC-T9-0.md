# Goal slice — DOC-T9-0: Matrix long-table stale phrase sweep

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`DOC-T9-0`

## Phase
`docs` · milestone hint `D2` · shared_cutover `False`

## Objective
Sweep MIGRATION_MATRIX.md for outdated UInt64-only/single-block S1/CLI supervisor claims outside historical superseded sections; fix to engineering facts without claiming formal done.

## Dependencies (must be done or explicitly waived)
DOC-1

## Allowed path prefixes
```
MIGRATION_MATRIX.md
docs/engineering-backlog.md
docs/roadmap-t8.md
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
  "slice_id": "DOC-T9-0",
  "milestone": "D2",
  "objective": "Sweep MIGRATION_MATRIX.md for outdated UInt64-only/single-block S1/CLI supervisor claims outside historical superseded sections; fix to engineering facts without claiming formal done.",
  "dependencies": ["DOC-1"],
  "allowed_paths": ["MIGRATION_MATRIX.md", "docs/engineering-backlog.md", "docs/roadmap-t8.md"],
  "focused_checks": ["just docs-check"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "slice(DOC-T9-0): matrix-long-table-stale-phrase-sweep",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. Surgical edits; keep history rows."
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"DOC-T9-0","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
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
Surgical edits; keep history rows.
