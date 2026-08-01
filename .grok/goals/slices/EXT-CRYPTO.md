# Goal slice — EXT-CRYPTO: extension.crypto design+MVP

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`EXT-CRYPTO`

## Phase
`northstar` · milestone hint `D2` · shared_cutover `True`

## Objective
Design capability matrix for SHA-256/Merkle/sign verify; MVP one target or research freeze. No insecure best-effort.

## Dependencies (must be done or explicitly waived)
NS-1

## Allowed path prefixes
```
docs/
ProofForgeV2/
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
  "slice_id": "EXT-CRYPTO",
  "milestone": "D2",
  "objective": "Design capability matrix for SHA-256/Merkle/sign verify; MVP one target or research freeze. No insecure best-effort.",
  "dependencies": ["NS-1"],
  "allowed_paths": ["docs/", "ProofForgeV2/", "docs/engineering-backlog.md"],
  "focused_checks": ["just docs-check"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": true,
  "commit_message": "slice(EXT-CRYPTO): extension.crypto-design+mvp",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. Design-first."
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"EXT-CRYPTO","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
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
Design-first.
