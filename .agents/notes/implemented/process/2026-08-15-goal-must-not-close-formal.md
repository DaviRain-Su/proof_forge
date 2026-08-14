# Agent Note: Goal drain must not close formal IDs

Status: implemented

## Problem

Track A LH-1…28 and Track F packaging rows are engineering-done. Sem001 /
002 / 003 shape suites exist. OutcomeWire, the public `step` façade, and
the EVM adapter exist. The live AGENTS Next task still says “EVM-first
formal lighthouse.”

A drain that is told to keep going will treat that as permission to flip
`TASK-D2-06` / `TASK-D2-07` / `TST-SEM-001/002/003` to `done`, or to claim
C-3 / Anvil lossless. Engineering shape is not EV-bound formal evidence.

## Decision

[`.grok/next-wave-queue.md`](../../../../.grok/next-wave-queue.md) Track C
stays skipped. Goal and Amp sessions must **not** edit formal status in
`docs/04-task-breakdown.md` or `docs/05-test-spec.md`.

Still fail-closed / blocked:

- D1–D4 formal **0/27**
- `TASK-D1-01` qualification
- C-3 and Anvil ↛ OutcomeWire lossless
  ([`docs/specs/evm-outcome-adapter-v1.md`](../../../../docs/specs/evm-outcome-adapter-v1.md))
- EV binding of `.pfsem` / `.pfprov` / `pf.reference-outcome.v1`

When the executable queue is empty, stop or ask. Do not invent a formal
ceremony, a new `TASK-*`, or a silent accepted-PRD expansion.

## Alternatives considered

- **Count Sem00x + OutcomeWire as TST-SEM-002/003 done** — rejected:
  [`docs/plan/evm-formal-d2-07-gap.md`](../../../../docs/plan/evm-formal-d2-07-gap.md)
  lists the blockers (D2-06 dependency, no EV object, D1-01, SPEC still
  saying v1 external calls have no return).
- **Count the `.pfsem` path-vs-hash pin as TST-SEM-001 done** — rejected:
  [`docs/plan/evm-formal-d2-06-gap.md`](../../../../docs/plan/evm-formal-d2-06-gap.md)
  requires retained-artifact EV binding; production encoders are not that.
- **Let Goal keep draining TypeKey rank / SOR-1 / Merkle because “next
  task is lighthouse”** — rejected: those are product or formal decisions.
  See the sibling notes in this tree.
- **Write a new TASK-\* so drain has a formal-looking row** — rejected:
  recovery forbids inventing freeze / EV ceremony from engineering slices.

## Consequences

An empty next-wave table means the auto-drainable engineering surface is
exhausted, not that formal is finished. Further formal work is a human /
main-agent axis with evidence objects the current Goal is forbidden to
mint.
