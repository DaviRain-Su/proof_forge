# Agent Notes

Durable **why / why-not** records for engineering decisions that
[`docs/adr/`](../../docs/adr/), [`docs/engineering-backlog.md`](../../docs/engineering-backlog.md),
and [`.grok/next-wave-queue.md`](../../.grok/next-wave-queue.md) do not carry well.

This tree is **not** a second authority. Registry, capability, language, and
accepted-PRD changes still need an ADR. Formal `TASK-*` / `TST-*` status still
lives in `docs/04-task-breakdown.md` and `docs/05-test-spec.md`. These notes
record standing engineering choices so the next session does not re-litigate
them from chat.

## Layout

`{lifecycle}/{class}/yyyy-mm-dd-topic.md`

| Lifecycle | Meaning |
|---|---|
| `proposed/` | Considered, not shipped. |
| `implemented/` | Standing decision; present-tense facts only. |
| `rejected/` | Tempting next step that lost; keep only while it still blocks a mistake. |

| Class | Meaning |
|---|---|
| `architecture` | Shipped source / Plan / wire / target honesty. |
| `process` | How agents verify, drain queues, and talk to formal. |

No `INDEX.md`. No Chinese sidecar. No format CI in this wave. Do not copy
session logs, `lake` output, or Amp threads here.

## When to write one

Write or update a note when a maintainer would reasonably ask the same
question again: a fail-closed boundary, a deferred structure gate, a
verification ban, or a Goal/formal split.

Do **not** write one for a mechanical pin, a single test, or a changelog
line that already states the fact. Update the owning note instead of
duplicating it.

## Format

First three lines:

```markdown
# Agent Note: <title>

Status: implemented
```

`Status:` is `proposed`, `implemented`, or `rejected — <one-line why>`.
The folder and the status line must agree. Filename date is first-proposed.

Required sections:

- `proposed/`: `## Problem` · `## Proposal` · `## Alternatives considered` · `## Acceptance criteria` · `## Risks`
- `implemented/`: `## Problem` · `## Decision` · `## Alternatives considered` · `## Consequences`
- `rejected/`: `## Problem` · `## Proposal` · `## Alternatives considered`

`## Alternatives considered` is mandatory. Record real losers, do not invent
them.

## Authority

| Question | Where |
|---|---|
| What shipped / what is forbidden in product | ADR + code |
| What is next / what is skipped | backlog + next-wave queue |
| Why we stopped / why not that tempting next step | this tree |
| Formal done? | `04` / `05` only |

Archived history is out of scope until a later process note says otherwise.
`.orca/worker-reports` and Amp threads remain run logs, not decision records.
