# Gap Analysis: Formal-Verification Boundaries

**Dimension:** formal-verification-boundaries — trust boundaries between the
Lean proof layer, the Portable IR semantics, each backend lowering, the
external toolchains that produce deployable artifacts, and the user-facing
product surface.

**Date:** 2026-07-10

## Executive summary

ProofForge has built an unusually rich FV *scaffold*: a shared total fuel-indexed
IR interpreter, structural capability-routing soundness theorems, a
`TraceObligation` / paired-step simulation framework, Yul-subset paired
simulation, and Quint MBT gates. However, the machine-checked guarantee is still
narrow: the only closed `∀ (m : Module)` refinement theorem is for the
Counter-shaped fragment; final-deployable artifacts (solc, wat2wasm, sbpf, leo)
remain outside the proof TCB; remote/crosscall semantics are axiomatised as a
stub; and the Quint/MBT lane is not exposed as a first-class product target.

**Overall maturity score for this dimension: 5 / 10.**

## What is healthy / complete

- **FV-1 capability routing soundness** is structural and universal.
  `ProofForge/Target/Formal.lean:26-53` proves `requireCapabilityPlan_sound`,
  and `ProofForge/Target/FormalBoundary.lean:31-57` checks the full
  `resolveSpec` boundary for Counter and ValueVault on EVM, Solana and NEAR.
- **FV-9.0 shared total IR interpreter** exists in
  `ProofForge/IR/SemanticsFuel.lean:36-191` (fuel-indexed, kernel-reducible, no
  contract names).
- **Paired-step simulation infrastructure** is in place:
  `ProofForge/Backend/Refinement/Core.lean:1036-1151`
  (`executableStepSimulationOk`, `executableSimulationTraceOk_sound`).
- **EVM Yul-subset host lane** has mathlib-free paired simulation for Counter
  and ValueVault (`ProofForge/Backend/Evm/YulHostRefinement.lean:96-99` and
  `:225-227`).
- **User-authored Lean invariants** work end-to-end for ValueVault and Counter
  (`ProofForge/Contract/Examples/ValueVaultInvariant.lean:134-146`,
  `Tests/LeanInvariantsSmoke.lean`).
- **CI coverage** is real: `just check` runs `semantics-fuel-smoke`,
  `constructor-coverage-smoke`, `counter-universal-refinement-smoke`,
  `evm-yul-host-refinement-smoke`, `lean-invariants-smoke`,
  `target-semantics-instances-smoke`, `quint-mbt-gate`, and
  `quint-ir-model-gate` (see `.github/workflows/ci.yml:170-214` and
  `justfile:1332`).

## Gaps

| # | Area | Evidence | Severity | Remediation direction |
|---|------|----------|----------|----------------------|
| 1 | **Proved fragment is far smaller than the product surface** | The `ConstructorCoverage` table marks `arrayLit`, `structLit`, all `crosscallInvoke*` constructors, env-extensions, and unbounded loops as `gap` (`ProofForge/Backend/Refinement/ConstructorCoverage.lean:108-118`). The covered capability set is only `{storageScalar, storageMap, callerSender, eventsEmit, controlConditional, checkedArithmetic, assertions}` (`:776-780`). `Tests/ConstructorCoverageSmoke.lean:126-128` shows `Examples.Product.RemoteCall` is explicitly outside the fragment, and `docs/formal-verification.md:287-302` lists `Ownable`, `RemoteCall`, `StakingVault`, and richer `RoleGatedToken` constructs as outside both C-diff and C-proof. | **Blocker** | Extend `SemanticsFuel` + per-constructor preservation lemmas; either bring auth, crosscall, arrays/structs, and unbounded loops into the supported fragment or clearly scope the product to the fragment. |
| 2 | **No formal equivalence for external toolchain hops** | `docs/formal-verification.md:325-327` lists `solc`, `wat2wasm`, `sbpf`, `leo`, and chain runtimes as explicit non-goals. The EVM powdr bytecode lane is opt-in and Counter-only (`ProofForgeFormal/Evm/CounterRefinement.lean`; `justfile:305-314`). The default EVM lane only proves Yul-subset behaviour, not Yul→bytecode equivalence. | **High** | Extend external verification (e.g. `scripts/evm/yul-compiler-counter-smoke.sh`) beyond Counter; formalise assembler/Wasm parsers; or ship verifiable artifacts that record the exact proof boundary for each build. |
| 3 | **Crosscall / remote-call semantics boundary is unproven** | IR semantics treats `crosscall.*` as a deterministic sum stub (`docs/formal-verification.md:61-82`, `docs/portable-ir-semantics-anchor.md`). `ConstructorCoverage` marks every `crosscallInvoke*` constructor as `gap` (`Tests/ConstructorCoverageSmoke.lean:130-132`). Product remote correctness is validated only by `crosscall-materialize` + multi-target smokes, not by equating the IR stub to chain-native CALL/CPI/Promise behaviour. | **High** | Build an oracle-backed proof path (roadmap U2.4 / U5.3) that relates the IR stub to real peer-VM semantics for a supported crosscall fragment. |
| 4 | **Ownership checker lacks a universal soundness theorem** | The production ownership checker is now fuel-indexed and total (`ProofForge/IR/Ownership.lean:298-389`), but the only machine-checked facts are pointwise detection witnesses on five probe entrypoints (`:474-500`, all `native_decide`). There is no `∀ entrypoint, checkEntrypointOk ep = true → ¬(useAfterRelease ep)` style theorem. `docs/formal-verification.md:198-209` is also stale, still describing the checker as a `partial def`. | **High** | State and prove a universal soundness theorem over the accepted entrypoint set, or document the checker as a heuristic if a universal proof is infeasible. |
| 5 | **Quint / MBT is not a first-class product target** | `quint` is intentionally CLI-only and absent from `ProofForge.Target.Registry.knownIds` (`ProofForge/Target/Registry.lean:458-483`). The C-diff replay is end-to-end only for EVM (`scripts/quint/evm-backend-replay-gate.sh`; `Tests/Quint/CounterEvmReplay.lean`). NEAR and Solana replay shims are pure string-render smokes (`justfile:1223-1232`) and not wired into `just check`. | **Medium/High** | Either add `quint` to the registry with a clear support matrix, or complete and wire the NEAR/Solana C-diff gates so MBT replay covers the primary triad. |
| 6 | **Solana all-input host refinement remains research** | The Solana host bridge covers Counter + ValueVault pointwise scenarios but explicitly does *not* claim universal all-input refinement (`docs/solana-sbpf-solanalib-bridge.md:113-115`, `:141-144`). Broad syscalls, CPI, PDA, hash maps, nested paths, and dynamic arrays are outside the in-Lean interpreter (`docs/formal-verification.md:33-34`, `:221`). | **High** | Close per-entrypoint universal simulation on the full host for the supported fragment; expand syscall/account-model coverage or keep Solana in a research tier. |
| 7 | **Pointwise trace checks rely on `native_decide`** | Many trace-obligation and ownership checks use `native_decide`, trusting Lean's native evaluator rather than the kernel (e.g. `ProofForge/Backend/Evm/YulHostRefinement.lean:96-99`, `ProofForge/IR/Ownership.lean:474-500`, `ProofForge/IR/Semantics.lean:1036-1265`). The Track 1.6 audit acknowledges this (`docs/formal-verification.md:86-144`). | **Medium** | Push tractable checks to `decide` (kernel-only); document the `native_decide` TCB clearly for external communication. |
| 8 | **No emitted proof certificates / verifiable metadata** | Build outputs contain `.bin`, `.yul`, `.json` manifests, and SDK files (`build/evm/Counter.proof-forge-artifact.json`, `build/evm/Counter.proof-forge-deploy.json`) but no machine-checkable proof artifact or signed claim about which fragment/theorem was discharged. | **Medium** | Emit a proof-manifest or certificate per build that records the fragment predicate, theorem names, and evaluator trust assumptions. |
| 9 | **EVM bytecode semantics lane is opt-in, not default** | The powdr-backed bytecode refinement target `ProofForgeFormalEvm` is separate from the default build and requires mathlib + a pinned powdr tree (`docs/formal-verification.md:96-113`). CI builds `ProofForge.Backend.Evm.Refinement` but the default product path trusts `solc`/Foundry differentially. | **Medium** | Make the bytecode proof lane default for the supported fragment, or at least produce a per-contract bytecode equivalence witness automatically. |

## Top 5 gaps

1. **Proved fragment is far smaller than the product surface** — the `∀ (m : Module)` theorem is effectively Counter-only; auth, crosscall, arrays/structs, unbounded loops, and most Token/RoleGated/StakingVault constructs are outside the machine-checked fragment. **Blocker.**
2. **No formal equivalence for external toolchain hops** — `solc`, `wat2wasm`, `sbpf`, `leo`, and chain runtimes remain outside the proof TCB. The only bytecode equivalence evidence is an external Counter-only smoke. **High.**
3. **Crosscall / remote-call semantics boundary is unproven** — the IR stub is intentionally not related to real CALL/CPI/Promise semantics, so multi-chain remote correctness is not formally grounded. **High.**
4. **Ownership checker lacks universal soundness** — detection witnesses exist for five probes, but there is no `∀ entrypoint` theorem that accepted modules are free of use-after-release / double-release. **High.**
5. **Quint/MBT is not a first-class product target** — C-diff replay runs end-to-end only on EVM; the NEAR/Solana shims are string-render smokes not wired into CI, and `quint` is absent from `--list-targets`. **Medium/High.**

## Maturity score rationale

Score **5/10**: the project has crossed the threshold from “ad-hoc tests” to
“machine-checked scaffolding with CI gates,” but the boundary between what is
proved and what is only differentially tested is still too close to the
Counter/ValueVault demo pair. A production-grade compiler/CLI product needs the
proved fragment to cover its advertised contract surface, the external toolchains
to be inside a documented and ideally machine-checked trust boundary, and the
FV pipeline to be exposed to users through the CLI/registry rather than hidden
behind fixture-only scripts.
