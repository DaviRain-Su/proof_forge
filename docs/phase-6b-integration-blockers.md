# Phase 6b — `EVMYulLean` integration blockers

Status: **blocked — seam only.**
Date: 2026-07-07.
RFC: RFC 0014 Phase 6b (Path 5b — Tier C-proof).
Roadmap: `docs/tier-c-proof-feasibility.md` §5 Phase 6b.

## Goal (recap)

Bring in a conformance-tested EVM bytecode semantics as a `lake`
dependency, replacing/augmenting the in-tree pseudo-Yul `Evm.YulSemantics`
that `Evm.Refinement.lean` currently uses. The external dependency is
[`leonardoalt/EVMYulLean`](https://github.com/leonardoalt/EVMYulLean) — a
Lean 4 formal model of EVM + Yul passing 22,330/22,332 of the official
`ethereum/tests` Cancun suite. It exposes `EVM.State` and a `step` function
at opcode granularity, plus a Yul semantics reusing underlying EVM primops.
It is a STANDALONE semantics, not a refinement framework — the simulation
obligation is ProofForge's (that is Phase 6c).

## (a) Toolchain comparison

| | Lean toolchain | mathlib | Notes |
|---|---|---|---|
| **ProofForge** | `leanprover/lean4:v4.31.0` | none | Pinned by `lean-toolchain`. Existing 378-job build green. |
| **EVMYulLean** | `leanprover/lean4:v4.22.0` | `require mathlib from git "https://github.com/leanprover-community/mathlib4.git"@"v4.22.0"` | Pinned by its `lean-toolchain` and `lakefile.lean`. mathlib v4.22.0 is tightly coupled to the v4.22.0 toolchain. |

A lake workspace uses **one** `lean-toolchain`. The two pinned toolchains
differ by 9 minor versions (`v4.22.0` vs `v4.31.0`).

## (b) The exact `require` syntax that would be used

The `require` entry that would be added to ProofForge's `lakefile.lean`,
**if the toolchains aligned**, is (pinned to a commit for reproducibility;
`EVMYulLean` has no release tags, so a commit pin is the only option):

```lean
require evmyul from git
  "https://github.com/leonardoalt/EVMYulLean.git"@"<commit-sha>"
```

The `<commit-sha>` should be the tip of `main` at the time of unblocking,
captured into `lake-manifest.json` by `lake update`. (A `main`-branch pin
is explicitly avoided for reproducibility — `EVMYulLean` publishes no
tags, so a literal commit SHA is required.)

EVMYulLean's own `lakefile.lean` additionally:

- `require mathlib from git ... @"v4.22.0"` (transitive dep, toolchain-coupled).
- Builds a C FFI (`extern_lib libleanffi`) by cloning two external C repos
  (`amosnier/sha-2`, `brainhub/SHA3IUF`) and compiling `EvmYul/FFI/ffi.c`.
- Its `extern_lib` target opportunistically populates the `EthereumTests`
  git submodule via `git submodule update --init EthereumTests` from the
  package directory. This is the heavy submodule the task says NOT to pull
  in the default build (CI-only).

## (c) Integration outcome

**BLOCKED.** Not attempted as a live `lake update` because the blocker is
decisive from the pinned files alone and a failed/broken `lake update`
would risk leaving the 378-job build in a non-green state. Per the task
constraint ("Do NOT break `lake build` for the existing ProofForge build"),
the `require` entry was NOT added to `lakefile.lean`, so `lake build` is
unchanged and green.

## (d) The precise blocker + resolution path

### Blocker: Lean toolchain + mathlib version mismatch

- ProofForge: `leanprover/lean4:v4.31.0`, no mathlib.
- EVMYulLean: `leanprover/lean4:v4.22.0` + `mathlib4 @ v4.22.0`.

A single lake workspace cannot simultaneously satisfy both toolchain
pins. mathlib v4.22.0 will not compile under lean v4.31.0 (mathlib is
tightly coupled to a specific Lean toolchain version; the mathlib team
cuts a `v4.X.0` tag per Lean release). Downgrading ProofForge to v4.22.0
would break the existing 378-job build (and the task explicitly forbids
forcing a downgrade/upgrade).

### Secondary considerations (not the primary blocker)

- EVMYulLean builds C FFI by cloning two external C repos (`sha-2`,
  `SHA3IUF`) and compiling them; this needs a C compiler and network
  access at build time. Manageable in CI, but an extra moving part.
- EVMYulLean's `extern_lib` target populates the `EthereumTests` submodule
  (heavy; CI-only per the task). This is avoidable by not building the
  `conform` test driver, but the `extern_lib` still runs the submodule
  init in the default `lake build` of EVMYulLean — a downstream consumer
  building `EvmYul` would trigger it unless the target graph is trimmed.

### Resolution path (in order of preference)

1. **Wait for EVMYulLean to update its toolchain pin to a Lean version
   compatible with ProofForge's (≥ v4.31.0) and cut a matching mathlib
   tag.** This is the cleanest path: no ProofForge churn, no vendoring.
   Track upstream: https://github.com/leonardoalt/EVMYulLean. When the
   `lean-toolchain` there reads `leanprover/lean4:v4.31.0` (or later) and
   `lakefile.lean` requires `mathlib @ v4.31.0` (or later), add the
   `require` entry above and run `lake update` in an environment with
   network access.

2. **Align toolchains intentionally.** If ProofForge independently decides
   to downgrade/pin to v4.22.0 (unlikely — it would regress the 378-job
   build and the broader ecosystem), or if EVMYulLean lands on a
   ProofForge-compatible toolchain, the `require` entry in §(b) becomes
   droppable as-is. This is a coordinated upstream+downstream decision,
   not a Phase 6b unilateral change.

3. **Vendor an adapter against a frozen EVMYulLean commit, build it in a
   separate lake workspace pinned to v4.22.0, and surface a thin extracted
   interface (e.g. via an `irreducible` definition or a `cc`-free wrapper)
   that ProofForge imports.** This is the heaviest path and is only worth
   it if (1) and (2) are blocked long-term. It is research-grade; defer.

### Recommended next action

Re-evaluate at the next ProofForge toolchain bump. Each time ProofForge
updates `lean-toolchain`, check whether EVMYulLean has moved to a
compatible pin. The seam at `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean`
is ready to absorb the real `EvmYul.EVM.State` / `EVM.Semantics.step` the
moment the toolchains align — the adapter's public surface (`State`,
`step`, `runBytecode`, alignment with `Refinement.ObservableStep`) is
fixed by this stub, and no `Refinement.lean` theorem depends on the stub
body.

## (e) Files changed (Phase 6b, blocked-seam deliverable)

- `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` (new) — stub adapter
  with the public surface (`State`, `step`, `runBytecode`) aligned to
  `Refinement.ObservableStep`, `sorry`-free stub theorems (`step_noop`,
  `runBytecode_empty`), and a module docstring recording the blocker.
  Compiles with NO external dependency (imports only
  `ProofForge.Backend.Evm.Refinement`).
- `docs/phase-6b-integration-blockers.md` (new — this file).
- `docs/tier-c-proof-feasibility.md` (modified) — Phase 6b section marked
  "blocked — seam only (2026-07-07)" with a one-paragraph note.
- `docs/rfcs/0014-unified-semantic-lowering-contract.md` (modified) —
  Path 5b Phase 6b status updated to "blocked — seam only".
- `docs/zh/rfcs/0014-unified-semantic-lowering-contract.zh.md` (modified)
  — Path 5b Phase 6b status updated (zh translation sync).
- `lakefile.lean` — **NOT modified** (no `require` entry added; build
  stays green).
- `ProofForge/Backend/Evm/Refinement.lean` — **NOT modified** (no theorem
  touched; wiring is Phase 6c).
- `ProofForge/IR/StepSemantics.lean` — **NOT modified** (Phase 6a
  invariant preserved).

## (f) Verification

- `lake build ProofForge.Backend.Evm.EvmBytecodeSemantics` — green (the
  stub module compiles with no external dependency; only imports
  `ProofForge.Backend.Evm.Refinement` which already builds).
- `lake build` — green (the default target is unchanged; the stub module
  is not transitively imported by the `proof-forge` exe, and the lib root
  `ProofForge.Backend` compiles the new module cleanly).
- No smoke gate added (per the task: the smoke is added only if
  integration succeeded). The stub theorems `step_noop`/`runBytecode_empty`
  discharge by `rfl` and type-check, confirming the seam is well-formed.

## (g) RFC/doc update summary

- `docs/tier-c-proof-feasibility.md` Phase 6b: marked
  "blocked — seam only (2026-07-07)" with the blocker (toolchain +
  mathlib version mismatch) and the resolution path (wait for EVMYulLean
  to pin a ProofForge-compatible Lean toolchain, then add the `require`
  entry from §(b)).
- RFC 0014 (en + zh) Path 5b Phase 6b: status updated to
  "blocked — seam only (2026-07-07)" with the same one-paragraph note,
  cross-referencing this file.