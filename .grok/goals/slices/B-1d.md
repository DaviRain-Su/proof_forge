# Goal slice — B-1d: Solana Map/Bytes/Option state pin

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`B-1d`

## Phase
`target` · milestone hint `D2` · shared_cutover `False`

## Objective
Either lower Solana Map/Bytes/Option state or pin FAIL-CLOSED with focused tests and matrix update.

## Dependencies (must be done or explicitly waived)
(none)

## Allowed path prefixes
```
ProofForgeV2/Targets/Solana/
Tests/
docs/research/12-target-coverage-matrix.md
docs/engineering-backlog.md
supply-chain/
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
  "slice_id": "B-1d",
  "milestone": "D2",
  "objective": "Either lower Solana Map/Bytes/Option state or pin FAIL-CLOSED with focused tests and matrix update.",
  "dependencies": [],
  "allowed_paths": ["ProofForgeV2/Targets/Solana/", "Tests/", "docs/research/12-target-coverage-matrix.md", "docs/engineering-backlog.md", "supply-chain/"],
  "focused_checks": ["just test-fast"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "slice(B-1d): solana-map/bytes/option-state-pin",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. Leaf lane OK."
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"B-1d","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
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
Leaf lane OK.
