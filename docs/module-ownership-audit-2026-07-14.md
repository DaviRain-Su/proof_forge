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

`ProofForgeFormal` is intentionally a sibling of `ProofForge`, not a backend
subdirectory. The directory boundary mirrors the Lake dependency boundary:
`ProofForge` is the default compiler/CLI library, while `ProofForgeFormalEvm`
and `ProofForgeFormalSolana` are opt-in proof libraries that may import powdr,
solanalib, and their transitive proof dependencies. Lightweight refinement
contracts used by normal compiler tests remain under
`ProofForge/Backend/Refinement` or `ProofForge/Backend/<Target>/Refinement`.

A-CUT1d completed the namespace ownership after the directory move. Optional
modules now declare names below `ProofForgeFormal.Evm` or
`ProofForgeFormal.Solana`; no compatibility declarations remain under the
default backend namespaces. The canonical boundary gate rejects reversed
imports, misleading namespaces, and restoration of the retired top-level
roots.

The Solana directory move is only the placement half of this decision. The
current public `Contract.Source.Solana` and `Contract.Source.Solana.Internal`
modules still forward into `Source.Solana.Legacy`, so the authoring dependency
has not yet been cut over. A-CUT1e owns that prerequisite before A-CUT2 resumes:
public macros stay under `Contract.Source.Solana`, stable operation identities
and signatures move to `Target.HostOps.Solana`, and target validation/planning
stays under `Backend.Solana.Extension`.

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

Before that full deletion, A-CUT1e must remove Legacy imports from the public
Solana Source and Internal modules. Remaining backend fixtures and Learn
compatibility callers must use explicit Legacy imports so they cannot be
mistaken for the current authoring route.
