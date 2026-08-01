# Goal slice — BUILD-6: just test-shard / test-targets recipes

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`BUILD-6`

## Phase
`build` · milestone hint `D2` · shared_cutover `False`

## Objective
Add ergonomic just recipes: test-shard NAME, test-targets, document in justfile comments or CONTRIBUTING snippet. Default daily path remains test-fast.

## Dependencies (must be done or explicitly waived)
BUILD-1

## Allowed path prefixes
```
justfile
docs/engineering-backlog.md
CONTRIBUTING.md
```

## Focused checks
```
just test-fast
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
  "slice_id": "BUILD-6",
  "milestone": "D2",
  "objective": "Add ergonomic just recipes: test-shard NAME, test-targets, document in justfile comments or CONTRIBUTING snippet. Default daily path remains test-fast.",
  "dependencies": ["BUILD-1"],
  "allowed_paths": ["justfile", "docs/engineering-backlog.md", "CONTRIBUTING.md"],
  "focused_checks": ["just test-fast"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "slice(BUILD-6): just-test-shard-/-test-targets-recipes",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. (none)"
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"BUILD-6","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
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
(none)
