# Goal slice — APP-1: PrivateSum4 privacy acceptance vector

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`APP-1`

## Phase
`app` · milestone hint `D2` · shared_cutover `False`

## Objective
Ensure PrivateSum4 remains continuous privacy boundary acceptance (Phase-1 DoD); product tests fail if raw private leaks to manifest/ABI/logs.

## Dependencies (must be done or explicitly waived)
N-3

## Allowed path prefixes
```
Examples/
Tests/
docs/engineering-backlog.md
```

## Focused checks
```
just test-fast
just ci
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
  "slice_id": "APP-1",
  "milestone": "D2",
  "objective": "Ensure PrivateSum4 remains continuous privacy boundary acceptance (Phase-1 DoD); product tests fail if raw private leaks to manifest/ABI/logs.",
  "dependencies": ["N-3"],
  "allowed_paths": ["Examples/", "Tests/", "docs/engineering-backlog.md"],
  "focused_checks": ["just test-fast", "just ci"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "slice(APP-1): privatesum4-privacy-acceptance-vector",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. (none)"
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"APP-1","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
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
