# Goal slice — LH-4: EventFlow Reference OutcomeWire

> Drain: `/goal @.grok/goals/prompt-next-wave.md starting at LH-4 --budget 8000000`  
> One slice: `/workflow next-wave-runner`

## ID
`LH-4`

## Phase
`lighthouse` · engineering only · shared corpus + Outcome mint

## Objective
Mint **Reference-only** `pf.reference-outcome.v1` sidecars for EventFlow
primitive case(s), add them to `OUTCOME_DIGEST_CASE_STEPS`, and make
`close-case` require digest+projection join. Keep Anvil ↛ OutcomeWire
lossless **fail closed**.

## Dependencies
LH-1, LH-2, LH-3 (already on `main`)

## Allowed path prefixes
```
ProofForgeV2/Semantic/OutcomeWireV1.lean
Tests/Materialization/EvmCorpusPrimitiveV1.lean
Tests/Materialization/EvmOutcomeAdapterV1.lean
Tests/Semantic/OutcomeWireV1.lean
scripts/evm_corpus_v1.py
scripts/evm_corpus_reference.sh
docs/specs/evm-outcome-adapter-v1.md
docs/specs/reference-outcome-v1.md
docs/engineering-backlog.md
.grok/next-wave-queue.md
supply-chain/
```

## Acceptance
1. EventFlow listed case has `reference-outcome-{step}.bin.hex` + `.digest` for every listed step.
2. Lean mint re-encode identity before write (same as ArithOps).
3. `validate-outcome-digests` / close-case fail closed if a listed sidecar is missing.
4. `try_mint_outcome_wire_from_observation` still returns `PF-CORPUS-OUTCOME`.
5. Docs say engineering only; TASK-D2-07 / C-3 / TST-SEM-* stay pending.
6. One local commit; never push.

## Out of scope
OwnableLike (LH-5). Formal step. Anvil lossless encoding. New TASK ids.
