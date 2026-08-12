# Goal slice — LH-6: engineering TST-SEM-002 shape pin

## ID
`LH-6`

## Objective
Pin a Counter-shaped **engineering** reference trace that matches the
*shape* of TST-SEM-002 (initializer vs default state, context key/type,
effect occurrence, normalized result) using retained OutcomeWire +
`step` façade. **Do not** edit `docs/04-task-breakdown.md` or
`docs/05-test-spec.md` to mark TST-SEM-002 / TASK-D2-07 done.

## Dependencies
`LH-4` (EventFlow path must not regress). `LH-5` may be `blocked`.

## Allowed path prefixes
```
ProofForgeV2/Semantic/
Tests/Semantic/
Tests/Materialization/EvmCorpus*.lean
docs/specs/reference-outcome-v1.md
docs/engineering-backlog.md
.grok/next-wave-queue.md
supply-chain/
```

## Out of scope
Formal evidence objects, EV catalog binding, Anvil lossless wire.
