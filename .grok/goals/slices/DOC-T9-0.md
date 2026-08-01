# Goal slice — DOC-T9-0: Matrix long-table stale phrase sweep

> Paste into `/goal` or run via master queue. **Skeptic reopened this ID** — do not treat backlog `T9-0 done` as substitute.

## ID
`DOC-T9-0`

## Phase
`docs` · milestone hint `D2` · shared_cutover `False`

## Objective
**Real** sweep of `MIGRATION_MATRIX.md` non-historical presentation rows that still read as UInt64-only / single-block-only / supervised-frontend-current, and align them to engineering facts (multi-width T8/T9, multi-block CFG, in-process `Loader.selectProgramV1Product`). Do **not** claim formal D1–D4 done.

## Why reopened (skeptic)
Prior session marked `T9-0`/`DOC-T9-0` done with **zero** `MIGRATION_MATRIX.md` commits in the done set. That is invalid. This slice is only complete when matrix file content changes land in a dedicated local commit.

## Dependencies (must be done or explicitly waived)
DOC-1

## Allowed path prefixes
```
MIGRATION_MATRIX.md
docs/engineering-backlog.md
docs/roadmap-t8.md
.grok/goals/
```

## Must fix (non-exhaustive; rg-driven)

Search and fix **presentation** wording outside pure historical superseded archives:

| Pattern / claim | Fix direction |
|---|---|
| “**仅** narrow public-UInt64” as if whole D2 product surface stopped there | Acknowledge multi-width Normalize + T8 ABI/body; keep formal pending honest |
| “state/param/result **仍 UInt64-only**” as current fact | State/param UInt8/16/32 ABI on four targets; body multi-width; narrow results/UInt128-256 boundaries per roadmap |
| Present-tense **superviseFrontend** / B12 as product path | Product = process-in `Loader.selectProgramV1Product`; keep D1-08 **superseded** history intact |
| Solana **plan-only** as current registry/product fact | SBPF→ELF + Mollusk engineering path; plan-only only if clearly historical label |
| Single-block S1-only implication where multi-block if/match/for already shipped | Multi-block CFG + loopBounds facts |

**Keep** historical TASK rows, superseded B12 narrative blocks, and formal-pending honesty.

## Acceptance (hard — skeptic gates)

1. `git show --stat HEAD` (or the DOC-T9-0 commit) **includes** `MIGRATION_MATRIX.md`.
2. After commit, these greps on matrix **do not** leave unrepaired **present-tense false claims** (history rows OK if labeled superseded/history):
   - bare “UInt64-only” without multi-width caveat on current-product sentences
   - “superviseFrontend” as current product authority
3. `docs/engineering-backlog.md`: **DOC-T9-0** → `done` with commit SHA; if **T9-0** stays done, note that DOC-T9-0 matrix sweep is the matrix half.
4. `just docs-check` + `git diff --check` green.
5. **Forbidden**: mark done with only backlog/roadmap status flip and no matrix edit.

## Focused checks
```
just docs-check
git diff --check
# evidence: list of fixed line themes in commit body
rg -n 'UInt64-only|superviseFrontend|plan-only|narrow public-UInt64' MIGRATION_MATRIX.md | head -40
```

## Standard verification
```
just docs-check
git diff --check
```
Skip `just ci` for pure docs; still run docs-check.

## Engineering-slice args skeleton
```json
{
  "slice_id": "DOC-T9-0",
  "milestone": "D2",
  "objective": "Real MIGRATION_MATRIX stale UInt64-only/single-block/supervisor phrase sweep; commit must touch matrix; no formal claims.",
  "dependencies": ["DOC-1"],
  "allowed_paths": ["MIGRATION_MATRIX.md", "docs/engineering-backlog.md", "docs/roadmap-t8.md", ".grok/goals/"],
  "focused_checks": ["just docs-check"],
  "verification_commands": ["just docs-check", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "docs(DOC-T9-0): matrix stale UInt64-only and supervisor phrase sweep",
  "constraints": "Never push. Never formal. Surgical edits; keep history rows. Commit MUST include MIGRATION_MATRIX.md."
}
```

## Workflow hooks
1. `BASE=$(git rev-parse HEAD)` before edits.
2. Implement matrix + backlog status.
3. Optional: `proof-forge-one-slice` review.
4. One local commit; never push.

## Global forbidden
- No push, force, amend of published commits, secrets, network package install
- No new formal TASK-*/TST-*/EV-*/freeze objects
- No just governance-check / release-check / Stage-0
- No formal D1–D4 completion claims
- No “done” without matrix file in the commit

## Notes
Companion recovery work that may run in the same Goal session (see `SKEPTIC-1` / master prompt):
- Recount PROGRESS DONE_IDS to include B-1d, B-1e, T9e when backlog already marks them done
- Clean BUILD-5 serial `run-deletion-gates` exit-0 log if prior assert left traceback
