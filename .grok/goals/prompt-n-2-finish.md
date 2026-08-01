# Goal — finish N-2 inside Goal, then continue drain

> **User intent:** N-2 (and further backlog) must run **in Goal**, not as chat-side
> implementer progress. This file is the resume entry when N-2 WIP is already on
> the worktree and backlog must not be falsely marked done.
>
> ```text
> /goal @.grok/goals/prompt-n-2-finish.md --budget 4000000
> ```
>
> Larger budget / full queue after N-2:
>
> ```text
> /goal @.grok/goals/prompt-master-queue.md starting at N-2 --budget 8000000
> ```

---

## OBJECTIVE

1. **Close N-2 only via Goal**: verify existing uncommitted WIP (or implement if
   clean), focused checks green, **one local commit**, then mark
   `docs/engineering-backlog.md` N-2 **done**.
2. If budget remains: **continue drain** from next pending using
   [prompt-master-queue.md](prompt-master-queue.md) rules (same session preferred).

Authority order:

1. [slices/N-2.md](slices/N-2.md) ← full acceptance + WIP inventory
2. [prompt-master-queue.md](prompt-master-queue.md) ← drain loop after N-2
3. [QUEUE.md](QUEUE.md) / [docs/engineering-backlog.md](../../docs/engineering-backlog.md)
4. `AGENTS.md`

---

## PHASE 0 — Tree ownership

1. `git status --short` + `git log -3 --oneline` + `git rev-parse HEAD`.
2. **If dirty paths match N-2 allowlist** (Semantic/Typed/Targets/ContextCommit/
   Tests + backlog): this is **Goal-owned N-2 WIP** — finish it; do **not** stop as
   “他人 WIP”.
3. **If unrelated dirty files** (other people / other slices): **BLOCKED** — report
   and stop; do not mix.
4. **If tree clean and N-2 still pending**: implement N-2 from [slices/N-2.md](slices/N-2.md)
   RED→GREEN under allowlist.
5. **If N-2 already committed and backlog done**: skip to drain from first pending
   (`starting at` next ID). Do not re-implement.

Skeptic triad (matrix commit / DONE_IDS / BUILD-5) should already be closed
(`SKEPTIC-1` / DOC-T9-0). If open, run [prompt-skeptic-recovery.md](prompt-skeptic-recovery.md)
first — still **inside Goal**.

---

## PHASE 1 — Finish N-2

Follow [slices/N-2.md](slices/N-2.md) exactly.

Minimum verify:

```bash
just test-shard typed
just docs-check
# if ProofForgeV2/** changed:
just sbom-package-files-refresh
git diff --check
```

Log under Goal SCRATCH when available: `slice-N-2-checks.log`.

**Do not** mark backlog done while tests red or while uncommitted.

Commit message suggestion:

```text
feat(N-2): context.caller Principal ContextRead + wire row
```

Stage only allowlisted paths. Never push.

---

## PHASE 2 — Drain (same Goal if budget allows)

After N-2 commit:

1. Update PROGRESS / DONE_IDS (must still include **B-1d, B-1e, T9e** when backlog-done).
2. Read backlog: first pending with deps met (often **N-3**).
3. Enter [prompt-master-queue.md](prompt-master-queue.md) single-slice loop until
   hard stop (empty pending / BUDGET_STOP / BLOCKED).

---

## Report template

```text
# N-2 finish + drain report
HEAD_START: ...
HEAD_END: ...
N2_STATUS: committed|blocked|still-wip
N2_COMMIT: <sha or none>
SKEPTIC_RECOVERY: closed|open
DONE_IDS: <truthful list including B-1d,B-1e,T9e if backlog-done>
COMPLETED:
  - N-2 @ sha
  - ...
NEXT: <id|EMPTY>
PUSHED: no
BACKLOG_UPDATED: yes|no
```

---

## Forbidden

- Chat-side “mark done / almost done” without Goal commit
- Backlog **done** without commit on product path
- Push / formal TASK-TST-EV / release-check
- Discarding valid N-2 WIP without cause
