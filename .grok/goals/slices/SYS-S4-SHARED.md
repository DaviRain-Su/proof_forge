# Goal slice — SYS-S4-SHARED: context.attachedValue

## ID
`SYS-S4-SHARED`

## Objective
ADR-0031 S4: source `context.attachedValue` → UInt64 `Op.ContextRead`
through CheckV1 + Normalize + Reference + S2 requirement freeze.
**All nine target Plans stay fail-closed** with tests until SYS-S4-EVM/NEAR/CW.

## Dependencies
Track A LH-4…LH-7 done or blocked (do not interleave shared-core with open LH).

## Allowed path prefixes
```
ProofForgeV2/Typed/
ProofForgeV2/Semantic/
ProofForgeV2/Source/
Tests/Typed/
Tests/Semantic/
docs/adr/0031-system-capability-unification.md
docs/engineering-backlog.md
.grok/next-wave-queue.md
supply-chain/
```

## Out of scope
Opening any target Plan. Native-asset economics. Solana (no direct attached value).
