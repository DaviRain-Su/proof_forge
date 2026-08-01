# Goal — finish C-2 inside Goal, then continue drain

> **User intent:** C-2 (and further backlog) must run **in Goal**, not as chat-side
> “half-green research + backlog mark”. Chat may leave Goal-owned WIP under
> `docs/research/15-aleo-psy-compiler-vm.md`; only Goal commits C-2 and drains.
>
> ```text
> /goal @.grok/goals/prompt-c-2-finish.md --budget 4000000
> ```
>
> Or master drain from C-2:
>
> ```text
> /goal @.grok/goals/prompt-master-queue.md starting at C-2 --budget 8000000
> ```

---

## OBJECTIVE

1. **Close C-2 only via Goal**: own any uncommitted WIP on
   `docs/research/15-aleo-psy-compiler-vm.md` (or implement if missing), wire
   README/matrix/dossier/backlog, `just docs-check`, **one local commit**
   `docs(C-2): …` (never push). No fake Leo/Psy compiler/VM maturity.
2. If budget remains: **continue drain** from next pending using
   [prompt-master-queue.md](prompt-master-queue.md) rules (same session preferred).

## Authority (read in order)

1. This file
2. [prompt-master-queue.md](prompt-master-queue.md) ← drain loop after C-2
3. [QUEUE.md](QUEUE.md) / [docs/engineering-backlog.md](../../docs/engineering-backlog.md)
4. [slices/C-2.md](slices/C-2.md)
5. `AGENTS.md` / `docs/targets/09-aleo.md` / `docs/targets/10-psy.md`

## PHASE 1 — Close C-2

1. `git status --short` + `git log -5 --oneline`. HEAD after B-3 sole commit
   should be near `docs(B-3): sole-commit…` / `feat(T-3):…`.
2. **If** `docs/research/15-aleo-psy-compiler-vm.md` is untracked/modified and
   paths stay in C-2 allowlist → **Goal-owned C-2 WIP** — finish it; do **not**
   stop as “foreign WIP”.
3. Complete C-2 deliverable:
   - Research note: leo / psy-vm availability; **do not promote** acceptance gates
   - Register in `docs/research/README.md` if needed
   - Aleo/Psy dossier maturity stays source-only (no fake compiler/VM gates)
   - `docs/engineering-backlog.md` **C-2 → done** with SHA after commit
4. Allowlist only: `docs/research/`, `docs/targets/09-aleo.md`,
   `docs/targets/10-psy.md`, `docs/engineering-backlog.md` (+ README under research
   if registration requires it).
5. Checks: `just docs-check` + `git diff --check` (pure docs; skip full `just ci`
   unless product code touched).
6. One local commit; never push. C-2 stays **pending** in backlog until that commit.

## PHASE 2 — Drain (same Goal if budget allows)

1. Re-read backlog: first pending with deps met (expect **C-4** after C-2; **C-5**
   is ongoing fixture growth; **C-3** formal blocked — skip/exclude).
2. Enter [prompt-master-queue.md](prompt-master-queue.md) single-slice loop until
   hard stop (empty pending / BUDGET_STOP / BLOCKED).
3. Per-ID local commits; truthful `master-queue-report.md` under Goal SCRATCH:
   - `DONE_IDS` includes historical B-1d/B-1e/T9e + newly closed IDs
   - `NEXT=` first real pending (not a done ID)
   - `PUSHED=no`

## Hard stop / report template

```text
PROGRESS: done=D pending=P (~pct%)
NEXT: <id|EMPTY>
BUDGET_STOP: yes|no
PUSHED: no
DONE_THIS_SESSION: C-2, …
```

## Forbidden

- Chat-side “mark C-2 done” without Goal commit
- Promoting Aleo/Psy to compiler/VM acceptance without real toolchain evidence
- Queue skip (e.g. jump to T-1 while C-4 pending)
- Push / formal TASK-*/TST-*/EV claims
