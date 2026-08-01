# Goal slice — SKEPTIC-1: Gap recovery before further drain

> **Priority zero** for the next master-queue Goal session. Put skeptic-required work **inside Goal**, not as chat-side manual cleanup.

## ID
`SKEPTIC-1`

## Phase
`recovery` · milestone hint `D2` · shared_cutover `False`

## Objective
Close the three skeptic findings that blocked truthful drain progress, then resume normal QUEUE drain from the first real pending.

## Three required outcomes

### 1) DOC-T9-0 real matrix sweep
- Execute [`.grok/goals/slices/DOC-T9-0.md`](DOC-T9-0.md) acceptance **fully**.
- Commit **must** change `MIGRATION_MATRIX.md`.
- Reopen was caused by marking T9-0/DOC-T9-0 done without matrix edits.

### 2) Truthful PROGRESS / DONE_IDS
When writing `master-queue-report` (or Goal session report):

```text
DONE_IDS: ... must include every backlog-done engineering ID, at least:
  BUILD-1..9, DOC-1..5, DOC-DEDUP, N-A1, N-A2,
  B-1a, B-1b, B-1c, B-1d, B-1e, T9a–T9d, T9e, T9-0 (if still claimed),
  DOC-T9-0 (after matrix commit), ...
PROGRESS: done=D pending=P total=T (~pct%)
```

- Do **not** omit B-1d, B-1e, T9e when backlog says done.
- Recount D from `docs/engineering-backlog.md` truth, not from a stale seed list.

### 3) BUILD-5 clean serial evidence
- Re-run: `just run-deletion-gates` (or the serial path documented after BUILD-5).
- Capture log under Goal SCRATCH: `slice-BUILD-5-checks.log`.
- **Hard**: process exit **0**, **no** Python `AssertionError` / traceback in log.
- If serial already green on HEAD, re-run still and attach clean log; no product change required.
- If red, fix under BUILD-5 allowlist (`justfile`, `scripts/gate_helpers.sh`, backlog note) with a new local commit.

## Dependencies
None for recovery itself. DOC-T9-0 depends on DOC-1 (already done).

## Allowed path prefixes
```
MIGRATION_MATRIX.md
docs/engineering-backlog.md
docs/roadmap-t8.md
justfile
scripts/gate_helpers.sh
.grok/goals/
```

## Focused checks
```
just docs-check
just run-deletion-gates   # or equivalent serial gate entry; must exit 0
git diff --check
```

## Standard verification
```
just docs-check
# BUILD-5 path:
just run-deletion-gates
git diff --check
```

## Commit policy
- Prefer **one commit per logical ID**:
  1. `docs(DOC-T9-0): ...` (matrix + backlog DOC-T9-0)
  2. optional `build(BUILD-5): ...` only if gates needed a code fix
- SKEPTIC-1 itself may be a docs-only Goal meta commit updating backlog “recovery closed” note, or may have **no** separate commit if DOC-T9-0 + evidence log suffice.
- Never push.

## Engineering-slice args skeleton
```json
{
  "slice_id": "SKEPTIC-1",
  "milestone": "D2",
  "objective": "Skeptic recovery: real DOC-T9-0 matrix commit, truthful DONE_IDS (incl B-1d/B-1e/T9e), clean BUILD-5 exit-0 log.",
  "dependencies": [],
  "allowed_paths": [
    "MIGRATION_MATRIX.md",
    "docs/engineering-backlog.md",
    "docs/roadmap-t8.md",
    "justfile",
    "scripts/gate_helpers.sh",
    ".grok/goals/"
  ],
  "focused_checks": ["just docs-check", "just run-deletion-gates"],
  "verification_commands": ["just docs-check", "just run-deletion-gates", "git diff --check"],
  "deletion_zero_patterns": ["planFromAlpha", "alphaResidualOf"],
  "shared_cutover": false,
  "commit_message": "docs(SKEPTIC-1): close skeptic recovery gates",
  "constraints": "Never push. Never formal. Matrix commit required. No false DONE_IDS."
}
```

## After SKEPTIC-1
- Mark SKEPTIC-1 done in backlog (if listed) / report.
- Resume master drain: first real pending is typically `DOC-SPEC-AUDIT` then Normalize IDs — **from backlog truth**, not stale QUEUE seed.
- Continue drain until empty / BUDGET_STOP / hard block.

## Global forbidden
- Fixing these gaps only in chat without Goal commits
- Claiming DOC-T9-0 done without matrix file change
- Omitting known-done B-1d/B-1e/T9e from DONE_IDS
- Accepting BUILD-5 log with traceback as green
