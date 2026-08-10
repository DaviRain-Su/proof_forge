# Psy P3: ContextRead / Commit — boundary note

Status: **Plan fail-closed** (not implemented).  
Related: `LowerSemanticV1` PSY-CONTEXT-COMMIT, `docs/targets/10-psy-dpn-lowering.md` FC matrix.

## Why FC today

Psy product materialization is **DPN package emission** + host-optional official
simulate. It is a ZK application-chain surface:

- no frozen **public-input / oracle binding** for `context.caller`,
  `blockHeight`, `unixTimeSeconds`;
- `Commit` cannot be lowered as Felt identity passthrough without claiming a
  cryptographic commitment that DPN package emission does not prove.

Opening these as ordinary state/Felt ops would over-claim.

## What would be required to open (checklist)

1. **ADR** fixing exact ContextRead keys admitted on Psy and their witness source
   (simulate context vs UPS public inputs vs coordinator).
2. **Wire requirement rows** already exist in Semantic; Psy Plan must bind them
   to DPN ops or explicit public-input slots — not silent drops.
3. **Commit**: define commitment algorithm + public-input layout; or keep FC and
   document “use Noir/other circuit target for Commit”.
4. **Fixtures**: official simulate/context injection tests; never session-only.
5. **Coverage** flip only after (1)–(4).

## Interim product guidance

| Need | Guidance |
|------|----------|
| Caller / height checks | Use another target (EVM/Solana/…) or wait for P3 ADR |
| Application counters, maps, events, void calls | Supported Psy subset (see probes) |
| Hash / IMT | See ADR-0037 / IMT official-only note |

## Probes already shipping (not P3)

- `Examples/StateCell.lean`, `MapMini.lean`, `OptionState.lean`, `WideCounter.lean`
- `Examples/LoopSum.lean` — bounded-for
- `Examples/EmitProbe.lean`, `CallProbe.lean` — PARTIAL effect leaves
