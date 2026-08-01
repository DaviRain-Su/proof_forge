# Goal slice — T9e: Solana/NEAR UInt128/256 multiprecision

> Paste into `/goal` or run via master queue. Detailed BUILD/N-A2 also in parent prompts.

## ID
`T9e`

## Phase
`width` · milestone hint `D2` · shared_cutover `False`

## Objective
Design then implement multiprecision UInt128/256 on Solana/NEAR (split T9e-Solana/T9e-NEAR). EVM T9b is reference. Fail-closed until correct.

## Dependencies (must be done or explicitly waived)
T9d

## Allowed path prefixes
```
ProofForgeV2/Targets/Solana/
ProofForgeV2/Targets/Near/
ProofForgeV2/Targets/EnvelopeV1.lean
Tests/
docs/roadmap-t8.md
docs/engineering-backlog.md
supply-chain/
```

## Focused checks
```
just test-fast
just dev-check
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
  "slice_id": "T9e",
  "milestone": "D2",
  "objective": "Design then implement multiprecision UInt128/256 on Solana/NEAR (split T9e-Solana/T9e-NEAR). EVM T9b is reference. Fail-closed until correct.",
  "dependencies": ["T9d"],
  "allowed_paths": ["ProofForgeV2/Targets/Solana/", "ProofForgeV2/Targets/Near/", "ProofForgeV2/Targets/EnvelopeV1.lean", "Tests/", "docs/roadmap-t8.md", "docs/engineering-backlog.md", "supply-chain/"],
  "focused_checks": ["just test-fast", "just dev-check"],
  "verification_commands": ["just docs-check", "just dev-check", "just ci", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "slice(T9e): solana/near-uint128/256-multiprecision",
  "constraints": "Serial shared-core if Normalize/Typed/Semantic. Never push. Never formal. Update engineering-backlog.md. DESIGN FIRST commit allowed."
}
```

## Workflow hooks
After implementation is green and still uncommitted (or use engineering-slice for full pipeline):

1. Record BASE=`git rev-parse HEAD` before edits if self-implementing.
2. Optional: workflow `proof-forge-one-slice` with args
   `{"slice":"T9e","base_commit":"<BASE>","task_prompt":"<one-line objective>","changed_files":[...]}`
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
DESIGN FIRST commit allowed.
