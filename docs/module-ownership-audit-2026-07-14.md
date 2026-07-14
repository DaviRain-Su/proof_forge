# Module ownership audit (2026-07-14)

This audit fixes top-level module placement without changing the portable IR
boundary.

## Decisions

| Previous path | Current owner | Reason |
|---|---|---|
| `ProofForge/Solana.lean` and `ProofForge/Solana/{Types,Metadata,Programs,Builders}.lean` | `ProofForge/Contract/Source/Solana/Legacy*` | These modules implement the old target-specific `Contract.Builder` authoring route. They are compiler-owned compatibility code, not a peer of the compiler root. Public authors use only `ProofForge.Contract.Source.Solana`. |
| `ProofForge/Solana/Examples*` | `Examples/Backend/Solana/Contracts*` | The contracts are target fixtures for CPI, PDA, sysvar, and runtime behavior. They are not portable Product sources or public compiler modules. |
| `ProofForge/Psy.lean` | `ProofForge/Runtime/Psy.lean` | The module exposes `@[extern]` runtime intrinsics in `Lean.Psy`; it is neither portable authoring nor a compiler backend. |
| `EvmRefinement/*`, `SolanaRefinement/*` | `ProofForgeFormal/Evm/*`, `ProofForgeFormal/Solana/*` | These remain outside `ProofForge/**` because they are separate Lake libraries with heavyweight optional semantic dependencies. The shared project namespace makes ownership explicit without merging them into the default compiler library. |

## Enforced boundaries

- `ProofForge.Contract.Source.Solana` is the only public Solana contract
  authoring import.
- `Source.Solana.Legacy` may be imported only by compiler implementation,
  protocol compatibility, and backend fixtures. Product contracts must not
  import it.
- Target-specific examples live under `Examples/Backend`, while
  `Examples/Product` remains chain-neutral.
- The retired top-level Solana and Psy paths are rejected by the canonical
  boundary gate.

## Deletion point

`Source.Solana.Legacy` is not a permanent SDK layer. It is deleted after the
Solana direct-canonical materializer owns account declarations, PDA derivation,
CPI call plans, sysvars, memory/crypto operations, and protocol metadata without
constructing the old `Contract.Builder` module.
