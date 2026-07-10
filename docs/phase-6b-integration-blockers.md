# Phase 6b — EVM semantics target switch and integration blockers

Status: **preferred target switched to `powdr-labs/evm-semantics`; opt-in target and wrapper landed, default mathlib-free seam remains stubbed by design.**
Date: 2026-07-07.
RFC: RFC 0014 Phase 6b (Path 5b — Tier C-proof).
Roadmap: `docs/tier-c-proof-feasibility.md` §5 Phase 6b.

## Goal (recap)

Bring in a conformance-tested EVM bytecode semantics as an opt-in `lake`
dependency, replacing/augmenting the in-tree pseudo-Yul `Evm.YulSemantics`
that `Evm.Refinement.lean` currently uses. The preferred external dependency is
now [`powdr-labs/evm-semantics`](https://github.com/powdr-labs/evm-semantics):
a Lean 4 EVM semantics pinned to ProofForge's Lean toolchain (`v4.31.0`) and
structured around relational `Step` / `Eval` plus executable `stepF`.
It is a STANDALONE semantics, not a refinement framework — the simulation
obligation is ProofForge's (that is Phase 6c).

## (a) Toolchain comparison

| | Lean toolchain | mathlib | Notes |
|---|---|---|---|
| **ProofForge** | `leanprover/lean4:v4.31.0` | none | Pinned by `lean-toolchain`. Existing 378-job build green. |
| **powdr-labs/evm-semantics** | `leanprover/lean4:v4.31.0` | `mathlib4 @ v4.31.0` | Toolchain-compatible preferred target; pull behind an opt-in lake target so the default build stays mathlib-free. |
| **EVMYulLean** | `leanprover/lean4:v4.22.0` | `require mathlib from git "https://github.com/leanprover-community/mathlib4.git"@"v4.22.0"` | Pinned by its `lean-toolchain` and `lakefile.lean`. mathlib v4.22.0 is tightly coupled to the v4.22.0 toolchain. |

A lake workspace uses **one** `lean-toolchain`. The two pinned toolchains
differ by 9 minor versions (`v4.22.0` vs `v4.31.0`).

## (b) The exact `require` syntax now used

The opt-in EVM-refinement target now pins `powdr-labs/evm-semantics` to a
literal commit SHA for reproducibility:

```lean
require evm_semantics from git
  "https://github.com/powdr-labs/evm-semantics.git"@"ae13dbc506158f9d0c7e05634636b17e2bccf850"
```

`lake-manifest.json` records the transitive `mathlib` pin
`fabf563a7c95a166b8d7b6efca11c8b4dc9d911f` (`v4.31.0`). The new
`EvmRefinement` Lake target imports powdr; the default `proof-forge` target
does not.

The old `EVMYulLean` fallback syntax, **only if its toolchain aligns**, would be:

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

**TARGET SWITCHED, OPT-IN DEPENDENCY WIRED.** The `EVMYulLean` integration was
blocked by the pinned toolchain mismatch below. The preferred route is now
powdr, which removes the toolchain blocker but still pulls mathlib. The
dependency is present in `lakefile.lean` and `lake-manifest.json`, but it is
only imported by the separate opt-in `EvmRefinement` target. The default
`proof-forge` target remains free of powdr/mathlib imports.

## (d) The precise blocker + resolution path

### Historical blocker: `EVMYulLean` Lean toolchain + mathlib version mismatch

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

0. **Switch the refinement target to `powdr-labs/evm-semantics` (resolves the
   EVMYulLean blocker now).** As of 2026-07, [`powdr-labs/evm-semantics`](https://github.com/powdr-labs/evm-semantics)
   is a Lean 4 EVM semantics pinned to `leanprover/lean4:v4.31.0` + `mathlib @
   v4.31.0` — the **same toolchain as ProofForge** — so there is no version
   mismatch to wait on. It is relationally structured (Prop-valued `Step`/`Eval`
   plus an executable `stepF`), which fits the Phase 6c simulation proof better
   than EVMYulLean's executable `step`. Cost: it pulls `mathlib` (ProofForge has
   none today) — isolate it behind an **opt-in lake target** for the
   EVM-refinement modules so the core build stays mathlib-free. It is a draft
   ("not for production"), so pin a specific commit; its `Step` relation joins
   the TCB. This is now the **preferred** path; the EVMYulLean options below are
   fallbacks. The local seam now mirrors powdr's `State` / `Step` / `stepF`
   shape. See [tier-c-proof-feasibility.md §2](tier-c-proof-feasibility.md).

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

Use the opt-in powdr wrapper plus the landed Counter storage relation to prove
the Counter per-entrypoint simulation against powdr `Step`. The pinned powdr
tree exposes bytecode semantics but no Yul-level relation, so keep the
Yul→bytecode `solc` step as an explicit trust boundary.

## (e) Files changed (Phase 6b, blocked-seam deliverable)

- `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` (new/updated) — the
  default-build, mathlib-free adapter seam with the public surface (`State`,
  `Step`, `stepF`, `step`, `runBytecode`) aligned to the powdr target shape
  and `Refinement.ObservableStep`. Its stub body is intentional fallback
  surface; real powdr imports live in the opt-in `EvmRefinement` target.
- `docs/phase-6b-integration-blockers.md` (new/updated — this file).
- `docs/tier-c-proof-feasibility.md` (modified) — Phase 6b section marked
  as powdr-target wired, with the EVMYulLean blocker retained as historical
  context/fallback.
- `docs/rfcs/0014-unified-semantic-lowering-contract.md` (modified) —
  Path 5b Phase 6b status updated to powdr-target wired and Phase 6b
  unblocked.
- `docs/zh/rfcs/0014-unified-semantic-lowering-contract.zh.md` (modified)
  — Path 5b Phase 6b status updated by zh translation sync.
- `lakefile.lean` — modified to add the pinned `evm_semantics` dependency and
  an opt-in `EvmRefinement` target; the default `proof-forge` target does not
  import powdr/mathlib.
- `lake-manifest.json` — records the pinned powdr/mathlib dependency graph.
- `EvmRefinement/PowdrAdapter.lean` — opt-in adapter that imports powdr's
  `State`, `Step`, `StepF`, `BigStep`, and `Equiv` modules; exposes real
  powdr-backed `State`, `Step`, `stepF`, `step`, `isHalted`, and `runBytecode`
  wrappers; and proves the wrapper `stepF_sound` using
  `EvmSemantics.EVM.stepF_sound`, plus `runBytecode_steps` from successful
  fuel-bounded execution to powdr `Steps`.
- `EvmRefinement/CounterRefinement.lean` — opt-in Counter relation layer that
  maps IR `count` to the powdr account storage word at ProofForge's EVM scalar
  slot 0 using the generated Solidity-compatible packed U64 shape: low 64 bits
  carry `count`, high 192 bits are padding/other-packed-field space, and
  `count < 2^64`,
  embeds the current CLI-generated Counter runtime bytecode witness, proves its
  selector offsets, exposes the compiled-runtime powdr config, and specializes
  the initialize-prefixed trace theorem to that concrete runtime target. It also
  defines a high-gas top-level `counterBaseEvmState` and native executable
  smokes for the compiled runtime; those are C-diff witnesses, not the pending
  relational per-entrypoint proof. **Legacy storage-layout checkpoint:** the
  prepared-frame, safe-trace, and hand-expanded opcode names in the historical
  detail below live under `ProofForge.Backend.Evm.CounterRefinement.LegacyHighPacked`.
  They target the pre-migration high-64-bit layout and do not establish refinement
  for the current low-order runtime. Prepared calls now normalize a fresh
  top-level EVM frame while preserving storage, so stale halted frames or
  zero-gas defaults are not accidental counterexamples. The concrete compiled
  powdr target now wires `executableTraceOk` for Counter `TraceObligation`s and
  proves the initialize-get-increment-get trace. The relation layer also exposes
  `LegacyHighPacked.CounterStepSafe`,
  `LegacyHighPacked.CounterPowdrSafeEntrypointObligations`, and
  `LegacyHighPacked.counterPowdr_safe_step_simulates_from_obligations`, so the bounded
  `increment` precondition is now part of the per-entrypoint EVM proof surface.
  The safe trace theorem also lifts this predicate through the universal
  Counter trace induction and exposes a compiled-runtime specialization.
  `LegacyHighPacked.CounterTraceSafeAtState` exposes the same historical boundary.
  `LegacyHighPacked.CounterPowdrEvmPostconditions` and
  `LegacyHighPacked.counterPowdrSafeEntrypointObligationsOfPostconditions` isolate the historical
  proof to EVM-only storage postconditions for the legacy compiled runtime.
  Current padded-slot native smokes separately confirm low-64-bit reads and high-padding
  preservation; they do not discharge these legacy postconditions.
  `LegacyHighPacked.CounterPowdrPreparedEvmPostconditions` and
  `LegacyHighPacked.counterPowdrEvmPostconditionsOfPrepared` split the historical proof into
  prepared-frame bytecode facts plus the `prepareCounterCall` bridge. The
  initialize slice uses `LegacyHighPacked.counterInitializeStorageWord` as its high-packed storage model
  and `LegacyHighPacked.counterPreparedInitializePostconditionOfStorageModel` as the bridge from
  that model to the prepared-frame postcondition. `LegacyHighPacked.CounterPowdrPreparedStorageModels`
  names the exact remaining prepared-frame storage-model surface, and the
  compiled `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_*_prepared_storage_models`
  theorems connect that surface directly to the safe universal trace theorems.
  The SSTORE slice now has
  `LegacyHighPacked.counterInitializeStorageValue_of_sstore_stackMemFlow_ok`, proving that a
  successful powdr `SSTORE` helper step with the initialize model value on the
  stack writes that value into Counter slot 0. `LegacyHighPacked.counterStack_of_initialize_sload_and_or_ok`
  composes the powdr `SLOAD`, `AND`, and `OR` helper steps into the value
  shape that feeds that SSTORE. `counterInitializeSetValue_eq_zero`,
  `counterInitializeLowMask_eq`,
  `LegacyHighPacked.counterInitializeBodyWriteWord_eq_storageWord`, and
  `LegacyHighPacked.counterInitializeBodyWriteWord_rel_zero` prove that the historical mask and
  set value produced by the initialize body exactly match
  `counterInitializeStorageWord`; `counterStack_of_initialize_sload_and_or_storageWord_ok`
  specializes the SLOAD/AND/OR helper sequence to that storage model value.
  `counterStack_of_initialize_prefix_to_sload_ok` proves the initialize-body
  prefix constructs the exact stack consumed by the SLOAD helper.
  `counterStorageValue_of_initialize_sload_and_or_push_sstore_ok` stitches
  SLOAD/AND/OR through the final `PUSH0; SSTORE` and proves the resulting state
  writes the initialize storage model into Counter slot 0.
  `counterStorageValue_of_initialize_body_helpers_ok` composes the complete
  initialize-body helper sequence from the prefix through SSTORE.
  `counterCompiledRuntimeCode_decodes_initialize_first_push0`,
  `counterPreparedInitializeFirstPush0_decoded`, and
  `counterStack_of_stepFE_push0_ok` start the concrete opcode bridge by proving
  the first post-`JUMPDEST` initialize opcode decodes as `PUSH0` and that
  top-level `stepFE` matches the helper stack effect. The bridge also now has
  `stepFE` stack-effect lemmas for `PUSH1`, `DUP1`, `SHL`, `SUB`, and `NOT`,
  plus compiled-runtime decode facts for the initialize prefix through the
  mask-building `NOT`. `counterCompiledStateAt` and the
  `counterPreparedInitialize*_decoded` lemmas lift those bytecode decode facts
  to prepared-like states; `counterCompiledRuntimeCode_decodes_initialize_sload_slot_push0`
  covers the final slot `PUSH0`; and
  `counterStack_of_initialize_prefix_stepFE_to_sload_ok` composes the
  top-level `stepFE` prefix path to the stack shape consumed by `SLOAD`. The
  top-level bridge also now covers SLOAD/AND/OR/PUSH0/SSTORE:
  `counterStack_of_stepFE_stackMemFlow_sload_ok`,
  `counterStack_of_stepFE_compBit_and_ok`,
  `counterStack_of_stepFE_compBit_or_ok`,
  `counterStorageValue_of_stepFE_stackMemFlow_sstore_ok`,
  `counterStack_of_stepFE_stackMemFlow_sstore_ok`, tail decode facts through
  `SSTORE`, `counterStorageValue_of_initialize_tail_stepFE_ok`, and
  `counterStack_of_initialize_tail_stepFE_ok` prove the tail writes the
  initialize storage model value and leaves the return-address/selector stack
  tail ready for the final return path. The trampoline is bridged as well:
  `counterCompiledRuntimeCode_decodes_initialize_trampoline_*`,
  `counterPreparedInitializeTrampoline*_decoded`,
  `counterState_of_stepFE_stackMemFlow_jumpdest_ok`,
  `counterState_of_stepFE_stackMemFlow_jump_ok`,
  `counterState_of_initialize_trampoline_stepFE_to_body_ok`, and
  `counterState_of_initialize_body_jumpdest_stepFE_to_first_opcode_ok` prove
  the concrete top-level `stepFE` trampoline lands at the initialize body and
  advances to the first body opcode.
  `counterCompiledRuntimeCode_decodes_dispatcher_*` now pins the initialize
  selector dispatcher prefix through the taken-branch `JUMPI`, the
  `counterPreparedDispatcher*_decoded` lemmas lift those bytecode facts to
  `counterCompiledStateAt`, and
  `counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok` proves the
  first dispatcher `stepFE` advances from PC 0 to the `CALLDATALOAD` opcode
  with selector offset 0 on the stack. The dispatcher bridge now also has
  generic state lemmas for `CALLDATALOAD`, `SHR`, `EQ`, and taken `JUMPI`,
  plus concrete initialize selector facts and path theorems through
  `counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok`, proving the
  concrete initialize dispatcher reaches PC 5 (`DUP1`) with the extracted
  selector on top of the stack. The tail path through
  `counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok` now
  proves the dispatcher reaches the initialize trampoline `JUMPDEST` with the
  selector left on the stack.
  `counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok`
  composes that dispatcher path with the trampoline and body `JUMPDEST`, proving
  the runtime reaches the first initialize body opcode with the return address
  and selector stack shape preserved.
  `counterStorageValue_of_initialize_body_stepFE_from_first_opcode_ok` then
  composes the first body opcode through the prefix and SLOAD/AND/OR/PUSH0/SSTORE
  tail, proving the body writes `counterInitializeStorageWord` relative to the
  SLOAD-state storage word.
  `counterCompiledPreparedInitialize_entry_facts` records the compiled prepared
  initialize frame's PC0/code/fork, empty stack, initialize calldata, and
  contract address facts for instantiating the composed path from a real
  `CounterPreparedCall`.
  `counterCompiledRuntimeCode_decodes_initialize_body_return_jump`,
  `counterCompiledRuntimeCode_valid_initialize_return_jumpdest`,
  `counterCompiledRuntimeCode_decodes_initialize_return*`, and
  `counterPreparedInitializeReturn*_decoded` now pin the body final `JUMP` plus
  the `JUMPDEST; PUSH0; DUP1; RETURN` segment at the bytecode/prepared-state
  layer.
- `scripts/evm/powdr-counter-runtime-smoke.sh` + `just evm-powdr-counter-runtime`
  — opt-in drift gate that regenerates the Counter runtime and checks it still
  matches the embedded powdr witness.
- `ProofForge/Backend/Evm/Refinement.lean` — **NOT modified** (no theorem
  touched; wiring is Phase 6c).
- `ProofForge/IR/StepSemantics.lean` — **NOT modified** (Phase 6a
  invariant preserved).

## (f) Verification

- `lake build ProofForge.Backend.Evm.EvmBytecodeSemantics` — green (the
  default mathlib-free seam compiles with no external dependency).
- `lake build proof-forge` — green; default target does not build powdr/mathlib.
- `lake build EvmRefinement` — green; builds the opt-in powdr/mathlib adapter
  target.
- `just evm-powdr-counter-runtime` — green; generated Counter runtime matches
  the embedded powdr witness.
- `counterCompiledPowdr_initialize_executable_smoke`,
  `counterCompiledPowdr_get_zero_executable_smoke`, and
  `counterCompiledPowdr_initialize_increment_get_executable_smoke` — green
  under `lake build EvmRefinement`.
- `counterCompiledPowdr_get_packed_seven_executable_smoke` and
  `counterCompiledPowdr_increment_packed_seven_executable_smoke` — green;
  confirm the relation's packed U64 storage shape matches the compiled runtime.
- `counterCompiledPowdr_executable_trace_ok` — green; the compiled-runtime
  powdr `TargetSemantics.executableTraceOk` accepts the Counter trace obligation.
- `LegacyHighPacked.counterPowdr_safe_step_simulates_from_obligations` — historical high-packed theorem, green under
  `lake build EvmRefinement`; safe per-entrypoint obligations imply the
  one-step IR/powdr Counter simulation.
- `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_after_initialize_from_obligations`
  — green under `lake build EvmRefinement`; safe per-entrypoint obligations
  plus `counterTraceSafeAfterInitialize` imply the initialize-prefixed universal
  IR/powdr Counter trace simulation for the concrete compiled runtime.
- `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_from_state_safe_obligations` —
  historical high-packed theorem, green under `lake build EvmRefinement`;
  `LegacyHighPacked.CounterTraceSafeAtState` plus the
  storage relation imply the universal IR/powdr Counter trace simulation for
  the concrete compiled runtime.
- `LegacyHighPacked.counterPowdrSafeEntrypointObligationsOfPostconditions` — green under
  `lake build EvmRefinement`; EVM-only storage postconditions imply the safe
  per-entrypoint obligations.
- `LegacyHighPacked.counterPowdrEvmPostconditionsOfPrepared` — green under
  `lake build EvmRefinement`; prepared-frame postconditions imply the ordinary
  arbitrary-pre-state postconditions used by `counterPowdrTraceStep`.
- `LegacyHighPacked.counterPreparedInitializePostconditionOfStorageModel` — green under
  `lake build EvmRefinement`; a powdr proof that initialize writes
  `counterInitializeStorageWord` implies the prepared-frame initialize
  postcondition.
- `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_after_initialize_from_prepared_storage_models`
  and `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_from_state_safe_prepared_storage_models`
  — green under `lake build EvmRefinement`; compiled prepared-frame storage
  models imply the existing safe universal IR/powdr trace theorems.
- `counterInitializeStorageValue_of_sstore_stackMemFlow_ok` — green under
  `lake build EvmRefinement`; the final SSTORE helper branch writes the
  initialize storage model into Counter slot 0 when the dispatcher/body proof
  establishes the required stack shape.
- `counterStack_of_initialize_sload_and_or_ok` — green under
  `lake build EvmRefinement`; the SLOAD/AND/OR helper sequence forms the
  storage value that is later consumed by the SSTORE proof.
- `LegacyHighPacked.counterInitializeBodyWriteWord_eq_storageWord` and
  `counterStack_of_initialize_sload_and_or_storageWord_ok` — green under
  `lake build EvmRefinement`; the concrete initialize mask/set-value expression
  equals the storage model consumed by the SSTORE helper proof.
- `counterStack_of_initialize_prefix_to_sload_ok` — green under
  `lake build EvmRefinement`; the concrete initialize-body prefix constructs
  `counterCountSlot :: counterInitializeLowMask :: counterInitializeSetValue`
  before SLOAD.
- `counterStorageValue_of_initialize_sload_and_or_push_sstore_ok` — green under
  `lake build EvmRefinement`; the SLOAD/AND/OR result plus final PUSH0/SSTORE
  writes the initialize storage model into Counter slot 0.
- `counterStorageValue_of_initialize_body_helpers_ok` — green under
  `lake build EvmRefinement`; the complete initialize-body helper sequence
  writes `counterInitializeStorageWord`.
- `counterCompiledRuntimeCode_decodes_initialize_first_push0`,
  `counterPreparedInitializeFirstPush0_decoded`, and
  `counterStack_of_stepFE_push0_ok` — green under `lake build EvmRefinement`;
  the first concrete initialize opcode is bridged from compiled bytecode decode
  through top-level `stepFE` to the helper stack effect.
- `counterStack_of_stepFE_push1_ok`, `counterStack_of_stepFE_dup1_ok`,
  `counterStack_of_stepFE_compBit_shl_ok`,
  `counterStack_of_stepFE_stopArith_sub_ok`, and
  `counterStack_of_stepFE_compBit_not_ok` — green under
  `lake build EvmRefinement`; these cover the helper opcodes used by the
  initialize prefix.
- `counterCompiledRuntimeCode_decodes_initialize_*` facts — green under
  `lake build EvmRefinement`; the compiled runtime decodes through the
  tail `SSTORE`.
- `counterCompiledStateAt`, `counterPreparedInitialize*_decoded`, and
  `counterStack_of_initialize_prefix_stepFE_to_sload_ok` — green under
  `lake build EvmRefinement`; the prefix bridge now composes concrete
  top-level `stepFE` executions through the final slot `PUSH0` and proves the
  exact stack shape consumed by `SLOAD`.
- `counterStack_of_stepFE_stackMemFlow_sload_ok`,
  `counterStack_of_stepFE_compBit_and_ok`,
  `counterStack_of_stepFE_compBit_or_ok`,
  `counterStorageValue_of_stepFE_stackMemFlow_sstore_ok`,
  `counterStack_of_stepFE_stackMemFlow_sstore_ok`,
  `counterStorageValue_of_initialize_tail_stepFE_ok`, and
  `counterStack_of_initialize_tail_stepFE_ok` — green under
  `lake build EvmRefinement`; the tail bridge now composes concrete top-level
  `stepFE` executions through SLOAD/AND/OR/PUSH0/SSTORE, proves the initialize
  storage model is written, and preserves the stack tail for the final return path.
- `counterCompiledRuntimeCode_decodes_initialize_trampoline_*`,
  `counterPreparedInitializeTrampoline*_decoded`,
  `counterState_of_initialize_trampoline_stepFE_to_body_ok`, and
  `counterState_of_initialize_body_jumpdest_stepFE_to_first_opcode_ok` — green
  under `lake build EvmRefinement`; the top-level trampoline now reaches the
  initialize body and advances to the first body opcode with the return address
  preserved on the stack.
- `counterCompiledRuntimeCode_decodes_dispatcher_*`,
  `counterPreparedDispatcher*_decoded`, and
  `counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok` — green
  under `lake build EvmRefinement`; the initialize selector dispatcher is pinned
  through `JUMPI`, and its first top-level `stepFE` reaches the `CALLDATALOAD`
  opcode with selector offset 0 on the stack.
- `counterState_of_stepFE_env_calldataload_ok`,
  `counterState_of_stepFE_compBit_shr_ok`,
  `counterState_of_stepFE_compBit_eq_ok`,
  `counterState_of_stepFE_stackMemFlow_jumpi_taken_ok`, and the concrete path
  through `counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok` — green
  under `lake build EvmRefinement`; the initialize dispatcher now reaches the
  `DUP1` at PC 5 with the extracted initialize selector on the stack.
- `counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_ok`,
  `counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_ok`,
  `counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_ok`,
  `counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_ok`, and
  `counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok` —
  green under `lake build EvmRefinement`; the initialize dispatcher now reaches
  the trampoline `JUMPDEST`.
- `counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok`
  — green under `lake build EvmRefinement`; the dispatcher, trampoline, and body
  `JUMPDEST` now compose to the first initialize body opcode.
- `counterStorageValue_of_initialize_body_stepFE_from_first_opcode_ok` and
  `counterStack_of_initialize_body_stepFE_from_first_opcode_ok` — green under
  `lake build EvmRefinement`; the initialize body now composes from its first
  opcode through SSTORE, writes `counterInitializeStorageWord` relative to the
  SLOAD-state storage word, and preserves the stack tail for the final return path.
- `counterCompiledPreparedInitialize_entry_facts` — green under
  `lake build EvmRefinement`; the compiled prepared initialize frame has the
  PC0/code/fork, stack, calldata, and address facts needed by the composed path.
- `counterCompiledRuntimeCode_decodes_initialize_body_return_jump`,
  `counterCompiledRuntimeCode_valid_initialize_return_jumpdest`,
  `counterCompiledRuntimeCode_decodes_initialize_return*`, and
  `counterPreparedInitializeReturn*_decoded` — green under
  `lake build EvmRefinement`; the final return/jump segment is pinned through
  prepared decoding.
- `counterState_of_stepFE_system_return_empty_ok`,
  `counterState_of_initialize_return_stepFE_to_returned_empty_ok`, and
  `counterInitializeObservable_of_returned_empty` — green under
  `lake build EvmRefinement`; the final return path now executes through
  `JUMP; JUMPDEST; PUSH0; DUP1; RETURN`, halts with `Returned ByteArray.empty`,
  preserves Counter storage, and maps to the Counter `initialize` observable
  `.none`.
- `counterInitializeReturn_preserves_storage_model_stepFE_ok` — green under
  `lake build EvmRefinement`; once the body path has established the initialize
  storage model at the return jump, the final return path preserves it to the
  halted frame and produces the `.none` observable.
- `runBytecode_halted_succ`, `runBytecode_step_succ`,
  `runBytecode_stepFE_succ`, `StepFEPath`, and
  `stepFEPath_append`, `runBytecode_of_stepFEPath`, and
  `runBytecode_of_stepFEPath_done` — green under `lake build EvmRefinement`;
  the prepared-frame proof can now feed each successful `stepFE` opcode, or an
  already-packaged `stepFE` path segment, into the fuel-bounded powdr
  `runBytecode` driver. This is the first reusable path-composition layer for
  the deep opcode discharge.
- `counterStepFEPath_initialize_return_segment_ok`,
  `counterStepFEPath_initialize_body_and_return_ok`, and
  `counterStepFEPath_initialize_dispatcher_body_and_return_ok` — green under
  `lake build EvmRefinement`; the initialize deep path is now split into named
  segment facts before being turned into `runBytecode`, so later entrypoints can
  reuse the same segment-composition pattern.
- `counterRunBytecode_initialize_return_segment_ok` — green under
  `lake build EvmRefinement`; the final return segment now has a
  `runBytecode` proof from the body return jump to the halted frame using 5
  fuel steps.
- `counterRunBytecode_initialize_body_and_return_ok` — green under
  `lake build EvmRefinement`; the initialize body plus return segment now has a
  22-fuel `runBytecode` proof from the first body opcode to the halted `.none`
  result while preserving the initialize storage model. The theorem now derives
  the post-SSTORE body-return-jump `counterCompiledStateAt` fact internally and
  carries the final `halt = .Returned` fact out of the return segment.
- `counterCodePcFork_of_sstore_stackMemFlow_ok`,
  `counterCodePcFork_of_stepFE_stackMemFlow_sstore_ok`, and
  `counterCompiledStateAt_of_initialize_sstore_stepFE_ok` — green under
  `lake build EvmRefinement`; a successful powdr SSTORE step now preserves
  compiled code/fork and advances the initialize body PC to the return jump.
- `counterCallStack_of_stepFE_compBit_shl_ok`,
  `counterCallStack_of_stepFE_compBit_not_ok`,
  `counterCallStack_of_stepFE_stopArith_sub_ok`,
  `counterCallStack_of_stepFE_stackMemFlow_sload_ok`,
  `counterCallStack_of_stepFE_compBit_and_ok`,
  `counterCallStack_of_stepFE_compBit_or_ok`, and
  `counterCallStack_of_stepFE_stackMemFlow_sstore_ok` — green under
  `lake build EvmRefinement`; the initialize body now has reusable
  opcode-family call-stack preservation lemmas for the bit/arithmetic/storage
  opcodes needed to carry the prepared top-level `callStack` through the body
  prefix without duplicating a bespoke path proof per entrypoint.
- `counterCallStack_of_initialize_tail_stepFE_ok` — green under
  `lake build EvmRefinement`; the `SLOAD; AND; OR; PUSH0; SSTORE` tail now
  composes those opcode-family call-stack lemmas into a reusable segment proof,
  so the remaining body prefix only has to connect the first body opcode to the
  SLOAD state and then append this tail segment.
- `counterCallStack_of_initialize_prefix_stepFE_to_sload_ok` — green under
  `lake build EvmRefinement`; the first 12 initialize-body opcodes now compose
  into a reusable call-stack segment from the first body opcode to the SLOAD
  state, so the body proof can be assembled from prefix plus tail rather than
  replaying every opcode inside the final bridge.
- `counterStack_of_initialize_tail_stepFE_to_sstore_ok` and
  `counterStack_of_initialize_body_stepFE_to_sstore_ok` — green under
  `lake build EvmRefinement`; the composed tail/body path now exposes the
  pre-SSTORE stack shape needed by the SSTORE PC bridge, removing the explicit
  post-SSTORE `counterCompiledStateAt` premise from the 22-fuel bridge.
- `counterRunBytecode_initialize_dispatcher_body_and_return_ok` — green under
  `lake build EvmRefinement`; the initialize selector dispatcher and trampoline
  are now prepended to the body+return bridge through `StepFEPath`, giving a
  36-fuel `runBytecode` proof from PC0 to the halted `.none` result while
  preserving the initialize storage model. The return-path facts now also carry
  the returned-halt fact and call-stack preservation up through this 36-step
  theorem: the final frame's `callStack` is known equal to the
  body-return-jump frame's `callStack`.
- `runBytecode_halted`, `runBytecode_extend_halted`,
  `runBytecode_extend_to_fuel`,
  `runBytecode_extend_to_fuel_of_returned_top_level`, and
  `runBytecode_extend_of_stepFEPath_returned_top_level` — green under
  `lake build EvmRefinement`; any short fuel run, or any packaged
  `StepFEPath`, can now be lifted to a larger target fuel once the final frame
  is proven halted.
- `isHalted_of_returned_top_level`,
  `counterRunBytecode_extend_to_compiled_fuel`,
  `counterPowdrPreparedTraceStep_initialize_of_run36_returned_top_level_ok`,
  and the extended `counterCompiledPreparedInitialize_entry_facts` — green under
  `lake build EvmRefinement`; the `isDone` side condition is now reduced by
  adapter-level returned/top-level lemmas rather than a Counter-specific helper.
  Once the remaining prefix proof shows that the body-return-jump frame still
  has the prepared top-level empty `callStack`, the 36-step initialize run can
  discharge the condition without an external `hHalted` assumption; the
  returned-halt half is already carried by the 36-step bridge.
- `just evm-bytecode-semantics-smoke` — green; checks the local powdr-target
  seam without importing powdr or mathlib.

## (g) RFC/doc update summary

- `docs/tier-c-proof-feasibility.md` Phase 6b: marked as powdr-target seam,
  with the old EVMYulLean mismatch retained as historical blocker/fallback.
- RFC 0014 Path 5b Phase 6b: status updated to powdr-target wired and Phase
  6b unblocked, cross-referencing this file.

## (h) Current proof boundary and scaling guardrail

The canonical Counter relation now carries the generated low-64-bit packed
storage shape with high 192-bit padding allowed. The current solc 0.8.30 runtime
has native-decide fixed traces, including padding preservation. The all-call-list
shape `evmCompiledPowdr_fragment_refines_all` remains conditional on
`CounterCompiledPowdrEntrypointObligations`; those current-runtime obligations
are open. The former safe/prepared structures described above are available only
as `LegacyHighPacked` historical evidence.

The scaling risk is at the current per-entrypoint obligation boundary. The legacy
deep `runBytecode`/`stepFE` discharge covered an initialize path, but `increment`
and `get` should not copy that proof shape one entrypoint at a time. Before
widening the deep discharge,
extend the reusable segment machinery (`StepFEPath`,
`runBytecode_of_stepFEPath`, opcode-family call-stack preservation, and segment
lemmas for dispatcher, storage, arithmetic, and return paths) so later
entrypoints reuse common proof blocks instead of growing bespoke thousands-line
opcode traces.
