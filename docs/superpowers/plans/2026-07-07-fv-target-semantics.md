# FV Target-Semantics Task Plan — Solana sBPF + WASM Executable Trace

> **For agentic workers.** Recommended sub-skill: `superpowers:subagent-driven-development`
> — dispatch one fresh subagent per task, review between tasks. Every task below is
> self-contained and states, in order:
> **① Read first** (orientation) · **② Context to load** (files the agent must open) ·
> **③ Do** (the work) · **Acceptance** (how to know it's done) · **Depends on**.
>
> Rationale and the wider portfolio live in
> [docs/zh/execution-plan-2026-07.md](../../zh/execution-plan-2026-07.md) §7.
> This file is the executable task queue only.

## Background (all agents read once)

Build **in-Lean executable semantics** for two target VMs and check them against the
portable IR reference semantics (`ProofForge/IR/Semantics.lean`). This moves
`solana-sbpf-asm` and `wasm-near` from weak/external checks to **in-Lean differential
trace checks (Tier C-diff)**, then toward **refinement theorems (Tier C-proof)**. Tiers:
[docs/formal-verification.md](../../formal-verification.md).

**Both targets are the SAME shape** — machine state → `step` → fuel-bounded `run` →
simulation relation `R : IR.State ↔ MachineState` → `observe` → differential obligation
(`native_decide`) → refinement lemma (`induction`). Build the shared interface once
(**Task P1**), then instantiate per target. Do NOT build two bespoke interpreters.

**Key scheduling fact:** the C-diff obligations use `native_decide` (pointwise
evaluation), so they need only Task P1 — **not** the IR induction (P2). Tasks S1–S3 and
W1–W5 are therefore doable now; the C-proof tasks (S6/W6) are a later layer on P2.

**Non-goals (stay in external differential gates, do NOT model in Lean):**
Solana CPI / PDA derivation / account-validation prologue → Mollusk/Surfpool.
NEAR Promise / async / cross-contract → `runtime/offline-host` + wasmtime.

**Import vs self-build — do NOT over-scope the self-built targets.** The EVM lane and the
Solana/WASM lanes differ in one fundamental way:

- **EVM = import (do not write EVM semantics).** A Lean 4 EVM semantics already exists —
  `powdr-labs/evm-semantics` (Lean `v4.31.0`, toolchain-compatible; relational `Step` plus
  an executable `stepF`). Add it as an **opt-in lake dependency** and refine the IR against
  its relational `Step`. See
  [tier-c-proof-feasibility.md §2](../../tier-c-proof-feasibility.md).
- **Solana / WASM = self-build, but ONLY the fragment.** No off-the-shelf Lean semantics
  exists, so you write the interpreter (S1 / W2) — but **self-build ≠ reimplement the whole
  VM**. Model ONLY the instruction + host subset the lowering emits (ALU, storage,
  control-flow). The full VM (Solana CPI/PDA/syscalls/account-model; NEAR Promise/async)
  stays OUT, in the external gate (Non-goals above). It is a small, auditable fragment
  interpreter, not a chain runtime.

**Two-hop trust for self-built targets — the external differential gate stays forever.**
- Import (EVM): powdr's `Step` is conformance-tested against `ethereum/tests`, so "Lean
  model ≈ real EVM" is powdr's job; you prove ONE hop: IR ⟷ powdr `Step`.
- Self-build (Solana/WASM): you prove IR ⟷ your interpreter (pure Lean, no mathlib). But
  "your interpreter ≈ the real VM" is a SECOND hop that is **not** proven in Lean — it is
  checked by the external differential gate (Mollusk/Surfpool for sBPF, wasmtime /
  offline-host for Wasm). **Never delete or weaken that gate for a self-built target**; it
  is the only thing that catches a hand-written interpreter diverging from the real runtime.

Whether import or self-build, both plug into the SAME `TargetSemantics` interface (P1):
a relational `Step` (for the C-proof induction) + an executable `step` / `stepF` (for the
C-diff `native_decide`). Adopt powdr's dual relational+executable shape for the self-built
interpreters too.

## Task graph

```text
P1 (shared interface, LANDED) ──→ E1 (LANDED) → E2 (LANDED) → E3   (EVM C-proof via powdr — REFERENCE, do first)
                               ├→ S1 → S2 → S3 → S4 → S5   (Solana C-diff)
                               └→ W1 → W2 → W3 → W4 → W5   (WASM C-diff)
P2 (trace induction, landed generically) ─┬─→ S6 (Solana C-proof, copies E3)
                                          └─→ W6 (WASM C-proof, copies E3)
```

**EVM is the reference lane — do E1–E3 first.** EVM *imports* an external Lean semantics
(`powdr-labs/evm-semantics`), so its C-proof lands fastest and gives Solana/WASM a worked
template: S6/W6 copy E3's shape, swapping powdr's `Step` for the self-built
`SbpfInterpreter` / `WasmInterpreter` `Step`. **Already LANDED** (commits `4c4ec279`…`2fd6e9f6`):
P1 shared interface, the generic trace induction, and the EVM seam switched to powdr's
`State`/`Step`/`stepF` shape (`173b9d4f`, builds mathlib-free), plus E1's opt-in
`EvmRefinement` target pinned to powdr/mathlib and E2's real powdr-backed wrapper
surface. Remaining EVM work is E3.
(For the self-built lanes, start with **S1** or **W1**.)

---

## Task P1 — Shared `TargetSemantics` interface

- **① Read first:** `docs/formal-verification.md` (the three tiers, so you don't
  over-claim); this file's Background.
- **② Context to load:** the three copied obligation types —
  `ProofForge/Backend/Solana/Refinement.lean:38-57`,
  `ProofForge/Backend/WasmHost/Refinement/Core.lean:23-40`,
  `ProofForge/Backend/Evm/Refinement.lean:30-61`.
- **③ Do:** create `ProofForge/Backend/Refinement/Core.lean` holding ONE shared
  `ObservableReturn` / `ObservableStep` / `TraceObligation`, plus a `TargetSemantics`
  abstraction (a structure/class with: a `MachineState` type, `step`, fuel-bounded
  `run`, `observe : MachineState → ObservableReturn`, and an `executableTraceOk`
  differential runner). Migrate EVM/Solana/NEAR Refinement to import the shared types.
  Keep every existing theorem's truth value unchanged.
- **Acceptance:** `lake build` green; existing Refinement theorems still `#check`;
  `just check` passes; the three local `ObservableReturn` copies are gone.
- **Depends on:** none.

---

## EVM lane (E1–E3) — REFERENCE, do first (import `powdr-labs/evm-semantics`)

> EVM does NOT self-build semantics — it **imports** `powdr-labs/evm-semantics` (Lean
> `v4.31.0`, toolchain-compatible; relational `Step` + executable `stepF`). Facts +
> rationale: [tier-c-proof-feasibility.md §2](../../tier-c-proof-feasibility.md),
> [phase-6b-integration-blockers.md](../../phase-6b-integration-blockers.md). The seam
> `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` already mirrors powdr's
> `State`/`Step`/`stepF` and builds mathlib-free (commit `173b9d4f`). E1–E3 wire the real
> dependency and prove the first IR↔EVM refinement — the template S6/W6 then copy.

## Task E1 — Opt-in lake target for `powdr-labs/evm-semantics` + mathlib (LANDED)

- **① Read first:** `docs/phase-6b-integration-blockers.md` §(b) `require` syntax + §(d)
  resolution path #0 + "Recommended next action"; `docs/tier-c-proof-feasibility.md` §2.
- **② Context to load:** `lakefile.lean` (currently mathlib-free — verified); the seam
  docstring in `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` (lists the required
  `EvmSemantics.EVM.*` imports).
- **③ Do:** add a **separate opt-in lake target** (a distinct `lean_lib`, e.g.
  `EvmRefinement`, **not** in the default target graph) that `require`s
  `powdr-labs/evm-semantics` pinned to a **literal commit SHA** (+ transitive
  `mathlib @ v4.31.0`). Run `lake update` in a **network** environment; capture the pinned
  commit into `lake-manifest.json`. The default `lake build` / `just check` MUST stay
  mathlib-free and green.
- **Landed:** `lakefile.lean` pins powdr
  `ae13dbc506158f9d0c7e05634636b17e2bccf850`; `lake-manifest.json` records
  mathlib `fabf563a7c95a166b8d7b6efca11c8b4dc9d911f`; `EvmRefinement/PowdrAdapter.lean`
  imports powdr's `State`, `Step`, `StepF`, `BigStep`, and `Equiv` modules and wraps
  `EvmSemantics.EVM.stepF_sound`.
- **Acceptance:** default `lake build` unchanged (mathlib-free, green); the opt-in
  `EvmRefinement` target resolves and builds powdr + mathlib in a network env; the pinned
  commit is recorded in `lake-manifest.json`.
- **Depends on:** none — **but needs network + a long mathlib build.** This is the one
  heavy, environment-dependent task; run it where network and build time exist.

## Task E2 — Replace the EVM seam stubs with real powdr imports (LANDED)

- **② Context to load:** `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` (stub
  `State`/`Step`/`stepF`/`runBytecode` + the docstring import list: `EvmSemantics.EVM.State`
  / `Step` / `BigStep` / `StepF`).
- **③ Do:** under the opt-in target only, replace the stub bodies with imports from
  `EvmSemantics.EVM.*`, keeping the public surface and all `Refinement.lean` callers
  unchanged. Keep the mathlib-free stub as the default-build fallback (gate the real import
  behind the opt-in target so the default build never pulls mathlib).
- **Landed:** `EvmRefinement/PowdrAdapter.lean` now exposes real powdr-backed
  `State`, `Step`, `stepF : State → Except String State`, `step`, `isHalted`, and
  `runBytecode`. The `stepF` wrapper turns done-state calls into adapter errors, so
  `stepF_sound` can recover powdr's `¬ state.isDone` precondition and prove the real
  `EvmSemantics.EVM.Step`.
- **Acceptance:** opt-in target type-checks against the real powdr `State`/`Step`/`stepF`;
  default build still mathlib-free + green; no `Refinement.lean` theorem statement changes.
- **Depends on:** E1.

## Task E3 — First real IR↔EVM refinement (Counter, against powdr's `Step`)

> ### COURSE CORRECTION (2026-07-08) — HARD STOP on EVM bytecode hand-derivation
>
> **Status correction (2026-07-10).** References below to an already-closed
> "universal EVM Counter refinement" were too strong. The current low-order lane has a
> fixed Counter trace checked with `native_decide`; `evmCompiledPowdr_fragment_refines_all`
> still requires `CounterCompiledPowdrEntrypointObligations`. The deep proof discussed here
> is retained under `LegacyHighPacked` and does not discharge those current-runtime obligations.
>
> **What went wrong.** A fixed EVM Counter trace was already green at ~1,100
> lines via `native_decide` on powdr's `stepF`, but it was misreported as universal.
> The follow-on path — hand-deriving powdr's
> `runBytecode` opcode-by-opcode, step-by-step ("first step → first four steps") for
> `initialize` and then the dispatcher/selector path — has continued to grow past
> **13k lines**. It still expands Counter-specific facts faster than reusable machinery, and
> the genericity signal is missing: no second contract discharges obligations through the
> same layer. This will not scale — `increment`/`get`/ValueVault would each need a fresh
> multi-thousand-line grind unless a real automation layer exists first.
>
> **Decision.** Stop treating deep powdr bytecode reduction as the EVM delivery blocker.
> The accepted EVM boundary is the fixed Counter trace that discharges concrete powdr
> `stepF` execution with `native_decide`. The universal trace-lift shape remains conditional
> on `CounterCompiledPowdrEntrypointObligations`. The explicit TCB statement is: ProofForge trusts
> powdr's conformance-tested `stepF` plus Lean's `native_decide` evaluator for the EVM
> bytecode execution witness; powdr's relational `Step` and the successful-run bridge remain
> the imported target semantics boundary.
>
> **Do this instead (replaces further EVM opcode grinding):**
>
> **1. Bank the EVM result.** Keep the opt-in powdr/mathlib target, the `PowdrAdapter`
> seam, the storage relation, the safe supported-input predicate, and the universal trace
> lift. Treat the `native_decide` powdr `stepF` discharge as the EVM deliverable for this
> milestone. Document the trust boundary instead of trying to remove it by hand.
>
> **2. Keep `PowdrExec` as optional automation substrate only.** It may stay as a reusable
> fuel/path adapter and future symbolic-execution layer, but it is not allowed to pull E3
> back into Counter-specific selector/body/return proofs. Manual per-entrypoint opcode
> chains are a non-goal unless a contract-agnostic tactic/library can discharge a second
> contract without bespoke segment facts.
>
> **3. Move the theorem-machine effort to breadth.** The shared shape is:
> `SupportedFragment` predicate + `TargetSemantics` instance + relation `R` +
> per-entrypoint obligation surface + `traceSimulation_lift`. Apply that shape next to
> self-owned Solana/WASM interpreters, where the step semantics can be designed to reduce
> cleanly. Do not block Solana/WASM on removing `native_decide` from the imported powdr EVM
> lane.
>
> **4. Genericity smoke is useful but non-blocking.** A second-contract check
> (ValueVault or a two-slot counter) is only acceptable if it reuses the existing
> `TargetSemantics` / obligation / `native_decide` machinery with a short proof. If it
> requires new bytecode segment hand-derivation, stop and record it as future automation
> work, not E3 completion work.
>
> **Revised acceptance (corrected 2026-07-10):** `lake build EvmRefinement` stays green; the
> EVM status is recorded as "canonical Counter fixed-trace evidence via powdr `stepF` +
> `native_decide`, with the universal theorem still obligation-explicit and Yul→bytecode
> plus powdr/`native_decide` called out as TCB boundaries"; no new manual
> `CounterRefinement.lean` dispatcher/body/return proof expansion is added; active proof
> work moves to Solana/WASM or to a genuinely contract-agnostic automation layer.

- **① Read first:** `ProofForge/Backend/Refinement/CounterUniversal.lean` (the proof shape:
  per-entrypoint simulation + generic trace induction, currently against a toy `targetStep`);
  `docs/tier-c-proof-feasibility.md` §3 (the target-obligation shape).
- **② Context to load:** `CounterUniversal.lean` (`targetStep` / `counterModelTargetSemantics`
  — the toy to replace for EVM); the real powdr `Step` (from E2); the EVM storage layout
  (`ProofForge/Backend/Evm/Plan/Storage.lean`, for the `R` relation);
  `ProofForge/Backend/Evm/Refinement.lean`.
- **③ Do now:** stop extending the Counter bytecode hand-derivation. Preserve the green
  opt-in EVM target, record the `native_decide`/powdr `stepF` TCB boundary, and move the
  active theorem-machine work to the shared `TargetSemantics` / `SupportedFragment` /
  `traceSimulation_lift` path for Solana and WASM. Only touch `PowdrExec` again if the next
  patch is contract-agnostic automation, not another Counter segment proof.
- **Historical progress (evidence, not a continuation recipe):**
  **Legacy storage-layout checkpoint:** the prepared-frame, safe-trace, and
  hand-expanded opcode theorem names in the historical paragraphs below live under
  `ProofForge.Backend.Evm.CounterRefinement.LegacyHighPacked`. They target the
  pre-migration runtime where `count` occupied the high 64 bits. They do not establish
  refinement for the current low-order runtime.
  `EvmRefinement/CounterRefinement.lean` now starts the E3 relation layer:
  it proves the ProofForge EVM layout maps Counter `count` to scalar slot 0, defines the
  IR `count` ↔ powdr `AccountMap`/`Storage` relation over the generated EVM
  packed U64 slot shape used at that checkpoint: `count` occupied the high 64
  bits and the low 192 bits were padding/other-packed-field space, with
  `count < 2^64`. The current canonical model has since migrated to
  Solidity-compatible low-64-bit packing with high 192-bit padding. This
  corrected the
  earlier raw-`UInt256.ofNat count` relation, and later corrected the too-strong
  canonical whole-word equality relation, neither of which matches the compiled
  runtime's `get`/write behavior. It also defines selector calldata plus
  `prepareCounterCall`, a runtime-bytecode-parameterized powdr frame setup for Counter
  calls, and proves that preparation preserves `CounterStorageRel`. It also embeds the
  current CLI-generated Counter runtime bytecode as `counterCompiledRuntimeCode`, proves
  its size and selector offsets, exposes `counterCompiledPowdrConfig`, and adds the
  opt-in `just evm-powdr-counter-runtime` drift gate. The compiled-runtime path also
  exposes `counterCompiledPowdrTargetSemantics` and
  `counterCompiledPowdr_trace_simulates_after_initialize_from_obligations`, which
  specialized the obligation surface to the real Counter runtime witness. The module also
  defines `counterBaseEvmState` and native executable smokes for `initialize`, `get`, and
  `initialize; increment; get`; together with the explicit TCB statement, those are the
  selected executable witness boundary over powdr's driver. The concrete compiled
  target's `executableTraceOk` now consumes Counter `TraceObligation`s through the
  compiled runtime and proves the initialize-get-increment-get trace with
  `counterCompiledPowdr_executable_trace_ok`. Prepared calls now normalize a fresh
  top-level EVM frame (gas/header/fork/caller/pc/stack/halt) while preserving storage, so
  the relation is not accidentally blocked by stale halted frames or zero-gas defaults.
  Current packed-storage smokes use low-bit count `7` with nonzero high padding;
  `initialize; get` returns `0` from that padded slot,
  and `increment; get` reaches `8`. It now exposes
  `counterPowdrTraceStep` / `counterPowdrTargetSemantics`, which run prepared Counter
  calls through powdr `runBytecode`, project EVM results to Counter observables, and prove
  successful trace steps are backed by powdr `Steps` with the stated observable projection;
  compiled-runtime C-diff is green. The relational per-entrypoint obligation surface is
  retained as the theorem-machine shape, but no longer drives manual bytecode reduction.
  It also defines explicit
  `CounterPowdrEntrypointObligations` for `initialize`/`increment`/`get` and proves
  `counterPowdr_trace_simulates_from_obligations`: those three powdr bytecode obligations
  are sufficient to obtain the universal Counter trace simulation through the shared
  induction. `initialize` is now modeled as the relation-establishing entrypoint, so
  `counterPowdr_trace_simulates_after_initialize_from_obligations` proves universal
  `initialize :: calls` traces from arbitrary IR/EVM starting states once the same three
  per-entrypoint obligations hold.
  The newly explicit `count < 2^64` side condition is the next proof boundary: an
  unbounded IR `u64` Nat increment at `2^64 - 1` will not match the compiled EVM runtime
  unless the supported fragment/input predicate excludes overflow or the IR Counter
  semantics is changed to the same checked/wrapping behavior. That boundary is now
  represented in Lean by `counterTraceSafeFromCount` /
  `counterTraceSafeAfterInitialize`, with native checks for the normal
  initialize-get-increment-get trace and for the unsafe max-u64 increment case.
  The per-entrypoint obligation surface now has a safe variant:
  `LegacyHighPacked.CounterStepSafe`,
  `LegacyHighPacked.CounterPowdrSafeEntrypointObligations`, and
  `counterPowdr_safe_step_simulates_from_obligations` thread the bounded
  `increment` precondition into the EVM step proof instead of leaving overflow
  as an implicit side condition. `counterPowdr_safe_trace_simulates_from_obligations`
  and `counterPowdr_safe_trace_simulates_after_initialize_from_obligations` then
  lift that safe side condition through the universal trace induction, with a
  compiled-runtime specialization exposed by
  `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_after_initialize_from_obligations`.
  `LegacyHighPacked.CounterTraceSafeAtState` and
  `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_from_state_safe_obligations` expose
  the same boundary as a state/input predicate, which is the shape needed for a
  later SupportedFragment gate. `CounterPowdrEvmPostconditions` and
  `counterPowdrSafeEntrypointObligationsOfPostconditions` historically isolated a
  deeper powdr route through compiled-runtime EVM-only storage postconditions for
  `initialize`/safe `increment`/`get`. That route is deferred until generic automation
  exists. The surface is split once more into
  prepared-frame obligations:
  `CounterPowdrPreparedEvmPostconditions` proves the bytecode facts on states
  already produced by `prepareCounterCall`, and
  `counterPowdrEvmPostconditionsOfPrepared` bridges those facts back to the
  arbitrary pre-state wrapper used by `counterPowdrTraceStep`. For initialize,
  the legacy `counterInitializeStorageWord` modeled the then-current compiled
  body as "clear the high 64-bit count field, preserve low 192-bit padding", and
  `LegacyHighPacked.counterPreparedInitializePostconditionOfStorageModel` turns that storage
  model into the prepared-frame initialize postcondition.
  `LegacyHighPacked.CounterPowdrPreparedStorageModels` names that historical prepared-frame
  storage-model surface and `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_*_prepared_storage_models`
  connect it directly to the compiled-runtime safe universal trace theorems.
  The SSTORE-side storage projection lemma
  `counterStorageValue_accountMap_set_storage_same` is also available for the
  eventual opcode case proof, and
  `counterInitializeStorageValue_of_sstore_stackMemFlow_ok` proves that a
  successful powdr `SSTORE` helper step with the initialize model value on top
  of the stack writes exactly that model into Counter slot 0.
  `counterStack_of_initialize_sload_and_or_ok` composes the powdr `SLOAD`,
  `AND`, and `OR` helper steps and proves the value presented to SSTORE is
  `lor (land oldWord mask) setValue`, matching the initialize-body shape.
  `counterInitializeSetValue_eq_zero`, `counterInitializeLowMask_eq`,
  `LegacyHighPacked.counterInitializeBodyWriteWord_eq_storageWord`, and
  `LegacyHighPacked.counterInitializeBodyWriteWord_rel_zero` prove the historical initialize
  body expression cleared the then-current high 64-bit count field while
  preserving low 192-bit padding. This is retained as legacy checkpoint
  evidence; the canonical runtime now clears the low 64-bit field and preserves
  high 192-bit padding.
  `counterStack_of_initialize_sload_and_or_storageWord_ok` specializes the
  SLOAD/AND/OR helper sequence to those concrete constants and returns the
  storage model value on top of the stack.
  `counterStack_of_initialize_prefix_to_sload_ok` now proves the initialize-body
  prefix (`PUSH0`, `PUSH1`, `DUP1`, `SHL`, `SUB`, `NOT`) constructs the exact
  `counterCountSlot :: counterInitializeLowMask :: counterInitializeSetValue`
  stack consumed by SLOAD.
  `counterStorageValue_of_initialize_sload_and_or_push_sstore_ok` stitches
  SLOAD/AND/OR through the final `PUSH0; SSTORE` and proves the resulting state
  writes the initialize storage model into Counter slot 0.
  `counterStorageValue_of_initialize_body_helpers_ok` now composes the complete
  initialize-body helper sequence from the prefix through SSTORE and proves it
  writes `counterInitializeStorageWord`.
  `counterCompiledRuntimeCode_decodes_initialize_first_push0`,
  `counterPreparedInitializeFirstPush0_decoded`, and
  `counterStack_of_stepFE_push0_ok` start the dispatcher-to-helper bridge by
  proving the compiled initialize body's first post-`JUMPDEST` opcode decodes
  as `PUSH0` and that top-level `stepFE` has the same stack effect as the
  helper. The bridge now also has `stepFE` stack-effect lemmas for `PUSH1`,
  `DUP1`, `SHL`, `SUB`, and `NOT`, plus compiled-runtime decode facts for the
  initialize prefix opcodes through the mask-building `NOT`.
  `counterCompiledStateAt`, the `counterPreparedInitialize*_decoded` lemmas,
  and `counterCompiledRuntimeCode_decodes_initialize_sload_slot_push0` extend
  those decode facts to prepared-like states through the final slot `PUSH0`;
  `counterStack_of_initialize_prefix_stepFE_to_sload_ok` now composes the
  top-level `stepFE` prefix path and proves it reaches the exact stack consumed
  by `SLOAD`. The bridge also now covers the initialize tail:
  `counterStack_of_stepFE_stackMemFlow_sload_ok`,
  `counterStack_of_stepFE_compBit_and_ok`,
  `counterStack_of_stepFE_compBit_or_ok`,
  `counterStorageValue_of_stepFE_stackMemFlow_sstore_ok`,
  `counterStack_of_stepFE_stackMemFlow_sstore_ok`, tail decode facts through
  `SSTORE`, `counterStorageValue_of_initialize_tail_stepFE_ok`, and
  `counterStack_of_initialize_tail_stepFE_ok` prove the top-level `stepFE`
  SLOAD/AND/OR/PUSH0/SSTORE sequence writes the initialize storage model value
  and preserves the return-address/selector stack tail needed by the final
  return path. The initialize trampoline is bridged too:
  `counterCompiledRuntimeCode_decodes_initialize_trampoline_*`,
  `counterPreparedInitializeTrampoline*_decoded`,
  `counterState_of_stepFE_stackMemFlow_jumpdest_ok`,
  `counterState_of_stepFE_stackMemFlow_jump_ok`,
  `counterState_of_initialize_trampoline_stepFE_to_body_ok`, and
  `counterState_of_initialize_body_jumpdest_stepFE_to_first_opcode_ok` prove the
  top-level `stepFE` trampoline lands at the initialize body and then advances
  to the first body opcode while preserving the return address stack shape.
  The initialize selector dispatcher is now pinned at the bytecode/prepared-state
  layer too: `counterCompiledRuntimeCode_decodes_dispatcher_*` facts cover
  offsets 0, 1, 2, 4, 5, 6, 11, 12, and 14 (`PUSH0; CALLDATALOAD; PUSH1 224;
  SHR; DUP1; PUSH4 initialize-selector; EQ; PUSH1 trampoline; JUMPI`),
  `counterPreparedDispatcher*_decoded` lifts those facts to
  `counterCompiledStateAt`, and
  `counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok` proves the
  first top-level dispatcher `stepFE` advances from PC 0 to the `CALLDATALOAD`
  opcode with selector offset 0 on the stack. The dispatcher bridge now also
  has `counterState_of_stepFE_env_calldataload_ok`,
  `counterState_of_stepFE_compBit_shr_ok`, and
  `counterState_of_stepFE_compBit_eq_ok` generic state lemmas, a taken-branch
  `counterState_of_stepFE_stackMemFlow_jumpi_taken_ok`, concrete initialize
  calldata selector facts, and the path theorems
  `counterState_of_dispatcher_calldataload_stepFE_to_shift_push_ok`,
  `counterState_of_dispatcher_selector_shift_push_stepFE_to_shr_ok`, and
  `counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok`. The tail is
  bridged too:
  `counterState_of_dispatcher_selector_dup_stepFE_to_selector_push_ok`,
  `counterState_of_dispatcher_initialize_selector_push_stepFE_to_eq_ok`,
  `counterState_of_dispatcher_initialize_eq_stepFE_to_trampoline_push_ok`,
  `counterState_of_dispatcher_trampoline_push_stepFE_to_jumpi_ok`, and
  `counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok` prove
  the concrete initialize dispatcher reaches the initialize trampoline
  `JUMPDEST` with the selector left on the stack.
  `counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok`
  now composes the dispatcher path, trampoline path, and initialize-body
  `JUMPDEST`, reaching the first initialize body opcode with the return address
  and selector stack shape preserved.
  `counterStorageValue_of_initialize_body_stepFE_from_first_opcode_ok` composes
  the first initialize body opcode through the prefix and SLOAD/AND/OR/PUSH0/SSTORE
  tail, proving the concrete `stepFE` body writes `counterInitializeStorageWord`
  relative to the SLOAD-state storage word. Its companion
  `counterStack_of_initialize_body_stepFE_from_first_opcode_ok` proves the same
  body path preserves the return-address/selector stack tail for the final
  return path.
  `counterCompiledPreparedInitialize_entry_facts` records the compiled prepared
  initialize frame's PC0/code/fork, empty stack, initialize calldata, and
  contract address facts needed to instantiate the composed path from a real
  `CounterPreparedCall`.
  The final return segment is now bridged at `stepFE` level:
  `counterCompiledRuntimeCode_decodes_initialize_body_return_jump`,
  `counterCompiledRuntimeCode_valid_initialize_return_jumpdest`, the
  `counterCompiledRuntimeCode_decodes_initialize_return*` facts,
  `counterPreparedInitializeReturn*_decoded`,
  `counterState_of_stepFE_system_return_empty_ok`, and
  `counterState_of_initialize_return_stepFE_to_returned_empty_ok` cover the body
  final `JUMP` plus `JUMPDEST; PUSH0; DUP1; RETURN` and prove the resulting
  frame halts with `Returned ByteArray.empty` while preserving Counter storage.
  `counterInitializeObservable_of_returned_empty` maps that result to the
  Counter `initialize` observable `.none`.
  `counterInitializeReturn_preserves_storage_model_stepFE_ok` packages those
  facts as the final return-path bridge: once the body has established the
  initialize storage model at the return jump, the halted frame keeps that model
  and exposes the `.none` observable.
  `EvmRefinement/PowdrAdapter.lean` also proves `runBytecode_steps`: every successful
  fuel-bounded executable run is backed by powdr's relational `Steps` closure.
  The adapter now has `runBytecode_halted_succ`, `runBytecode_step_succ`,
  `runBytecode_stepFE_succ`, `StepFEPath`, `stepFEPath_append`,
  `runBytecode_of_stepFEPath`, and `runBytecode_of_stepFEPath_done`, so the
  composed `stepFE` path can be fed into the prepared-frame `runBytecode` driver
  either one opcode at a time or as reusable path segments.
  `counterStepFEPath_initialize_return_segment_ok`,
  `counterStepFEPath_initialize_body_and_return_ok`, and
  `counterStepFEPath_initialize_dispatcher_body_and_return_ok` now name those
  reusable initialize segments before the `runBytecode` conversion.
  `counterRunBytecode_initialize_return_segment_ok` applies that bridge to the
  final return segment, proving 5 fuel steps from the body return jump reach the
  halted return frame. `counterRunBytecode_initialize_body_and_return_ok`
  composes the body path with that return segment: from the first initialize
  body opcode, 22 fuel steps reach the halted frame, preserve the initialize
  storage model, expose the `.none` observable, and carry out the final
  `halt = .Returned` fact.
  `counterStack_of_initialize_tail_stepFE_to_sstore_ok` and
  `counterStack_of_initialize_body_stepFE_to_sstore_ok` now expose the
  pre-SSTORE stack shape consumed by
  `counterCompiledStateAt_of_initialize_sstore_stepFE_ok`, so the 22-fuel body
  bridge derives the body-return-jump `counterCompiledStateAt` fact internally
  instead of carrying it as an explicit premise. The body opcode families also
  now have reusable call-stack preservation lemmas for `SHL`, `NOT`, `SUB`,
  `SLOAD`, `AND`, `OR`, and `SSTORE`, so the remaining prefix proof can compose
  local opcode facts instead of rebuilding each branch inside the entrypoint
  theorem. `counterCallStack_of_initialize_tail_stepFE_ok` already composes the
  `SLOAD; AND; OR; PUSH0; SSTORE` tail into a reusable call-stack segment, so
  the remaining body proof only has to connect the first body opcode to the
  SLOAD state and append that tail segment.
  `counterCallStack_of_initialize_prefix_stepFE_to_sload_ok` now supplies that
  first-body-opcode-to-SLOAD call-stack segment, leaving the body call-stack
  proof as a prefix-plus-tail composition.
  `counterRunBytecode_initialize_dispatcher_body_and_return_ok` now prepends
  the initialize selector dispatcher plus trampoline path to that body+return
  bridge through `StepFEPath`, proving a 36-fuel `runBytecode` path from PC0 to
  the halted `.none` result while preserving the initialize storage model. The
  return-path proof now also carries returned halt and call-stack preservation
  through that 36-step theorem, so the final frame's `callStack` is known equal
  to the body-return-jump frame's `callStack`.
  `runBytecode_halted`, `runBytecode_extend_halted`,
  `runBytecode_extend_to_fuel`,
  `runBytecode_extend_to_fuel_of_returned_top_level`, and
  `runBytecode_extend_of_stepFEPath_returned_top_level` now lift any short fuel
  run, or any packaged `StepFEPath`, to a larger target fuel once the final
  frame is known to be halted. The Counter compiled-fuel bridge is now only a
  wrapper around that adapter-level interface.
  `isHalted_of_returned_top_level` and
  `counterPowdrPreparedTraceStep_initialize_of_run36_returned_top_level_ok`
  reduce the `isDone` premise to returned halt plus an empty top-level
  `callStack`; `counterCompiledPreparedInitialize_entry_facts` now exposes the
  prepared frame's initial empty `callStack`. The returned-halt half is already
  available from the 36-step bridge, so the remaining prefix proof only has to
  carry the prepared empty `callStack` to the body-return-jump frame.
  The shared safe trace layer is green once
  `LegacyHighPacked.CounterCompiledPowdrPreparedStorageModels` is supplied. Do not continue the
  target-specific prepared-storage-model discharge by hand; the scaling boundary
  has been reached. The pinned
  powdr tree has no Yul-level semantics module, so ProofForge's Yul→bytecode `solc` hop
  remains an explicit trust boundary.
- **Acceptance:** the opt-in EVM target remains green; the EVM row in
  `docs/formal-verification.md` states the selected boundary clearly:
  the canonical fixed Counter trace is banked through powdr `stepF` and `native_decide`,
  while the universal theorem remains obligation-explicit and deep manual bytecode reduction
  is deferred until a genuinely
  contract-agnostic automation layer exists. No new Counter-specific dispatcher/body/return
  chain is added.
- **Depends on:** E1, E2, P1 (landed), generic trace induction (landed).

**Then Solana/WASM copy the theorem-machine shape, not the EVM rabbit hole.** S6/W6 mirror
the shared `TargetSemantics` + `SupportedFragment` + per-entrypoint obligation +
`traceSimulation_lift` structure, swapping powdr's imported `stepF` boundary for the
self-built `SbpfInterpreter` / `WasmInterpreter` step definitions. Because those
interpreters are in-tree, design them to reduce cleanly instead of accumulating manual
bytecode segment facts.

## Task S1 — sBPF interpreter (state + step)

- **① Read first:** `docs/solana-sbpf-executable-trace.md` — the FULL design (machine
  state, opcode subset, dispatch, observable projection, phasing). Follow it exactly.
- **② Context to load:** `ProofForge/Backend/Solana/Asm.lean`
  (`Reg`/`Imm`/`MemOff`/`Opcode`/`Inst`/`AstNode` + the `Opcode.isLoad/isStore/...`
  helpers); `ProofForge/Backend/Solana/SbpfAsm.lean` (`lowerModule : Module → Except _
  (Array AstNode)` — its output is what you interpret).
- **③ Do:** create `ProofForge/Backend/Solana/SbpfInterpreter.lean`. Define `SbpfState`
  (regs, stack, entryR0, pc). Build a label table + `equDecl` symbol table by a pre-pass
  over the `AstNode` array. Implement `step` for the Counter opcode subset
  (`mov64/add64/sub64/mul64/lsh64`, `lddw`, `ldxdw`, `stxdw`, `ja/jeq/exit`, and a
  storage read/write **syscall stub** only). Implement a **fuel-bounded** `run` (total;
  over-budget = interpreter error, not a hang). Uncovered syscalls/opcodes = error.
- **Acceptance:** a `#check`-only smoke that the interpreter runs the lowered Counter
  entrypoints to `exit` with no error.
- **Depends on:** P1 (for `ObservableReturn`).

## Task S2 — sBPF differential obligation

- **② Context to load:** the interpreter from S1;
  `ProofForge/Backend/Solana/Refinement.lean` (`counterTraceObligation`,
  `ObservableReturn`).
- **③ Do:** add `TraceObligation.sbpfExecutableTraceOk` (run interpreter over
  `lowerModule` output, project `observe`, compare to `expected`) and
  `theorem counter_sbpf_executable_trace_ok := by native_decide`. **Delete the
  bare-substring branch** in `hasEntrypointDispatch` (`Refinement.lean:119-123`) — the
  executable check supersedes it. Update the `solana-sbpf-asm` Tier C-diff row in
  `docs/formal-verification.md` from "artifact-surface only" to "executable-trace
  (Counter subset)".
- **Acceptance:** `just solana-light` runs the new theorem locally with no
  `sbpf`/`surfpool`; `just check` green.
- **Depends on:** S1, P1.

## Task S3 — sBPF simulation relation `R`

- **② Context to load:** `ProofForge/Backend/Solana/StateLayout.lean`
  (`computeInputLayout`, `AccountInputLayout`, account-data offsets);
  `ProofForge/IR/Semantics.lean` (`State`).
- **③ Do:** define `R : IR.State ↔ SbpfState` mapping the IR scalar binding to the U64
  at the account-data offset given by `StateLayout` (Slice A: one U64 scalar). State
  pointwise theorems that `R` holds on the Counter scenario after `initialize` and after
  `increment` (`native_decide` is fine — this is C-diff, not C-proof).
- **Acceptance:** `R`-holds theorems for the Counter scenario `#check` and pass.
- **Depends on:** S1.

---

## Solana C-proof lane (SOL-1–SOL-4) — the self-build twin of EVM E3

> **This is EVM E3 done self-build**, and it **bakes in the EVM COURSE CORRECTION from day
> one** (see Task E3): build ONE generic per-instruction layer first, then thin per-entrypoint
> proofs. Do NOT hand-derive `initialize` step-by-step (that was the 9,544-line EVM rabbit hole).
>
> **Where Solana stands now:** the executable interpreter is done — `SbpfInterpreter.lean`
> (`SbpfState` :48, `step` :215, fuel `run` :273), plugged into the shared `TargetSemantics`
> (`solanaSbpfTargetSemantics`), with C-diff `native_decide` obligations green (Counter /
> ValueVault / map / array). MISSING is the C-proof: per-instruction lemmas + universal (`∀`
> call list) IR↔sBPF refinement. Solana is exactly where EVM was *before* E3.
>
> **Differences from EVM (all in Solana's favour):**
> - **No E1/E2** — we do NOT import an external semantics; the interpreter is our own pure
>   Lean, already in the default build (no lake dep, no mathlib).
> - **We OWN `step`** — so we can shape it reduction-friendly and prove per-instruction lemmas
>   cleanly. EVM's pain came from reverse-engineering an external black box (powdr) with a
>   stack machine + gas/`OutOfGas` branch. sBPF is a **register machine, no stack, no gas
>   branch** → the generic layer is far smaller. Solana should avoid the EVM rabbit hole.
> - **Two-hop trust (keep forever)** — "our interpreter ≈ real sBPF VM" is NOT proven in Lean;
>   it stays checked by the external **Mollusk/Surfpool** differential gate. Never delete it.
>
> **Non-goals (stay in Mollusk/Surfpool):** CPI, PDA derivation, syscalls beyond the storage
> read/write stub, the account model. The Lean interpreter covers straight-line compute +
> scalar storage + U64/Unit returns (the Counter fragment).

## Task SOL-1 — Generic per-instruction sBPF step-lemma layer (`SbpfExec.lean`)

- **① Read first:** the ⚠️ COURSE CORRECTION under Task E3 (the "generic layer, not
  per-entrypoint hand-derivation" lesson); `docs/solana-sbpf-executable-trace.md`.
- **② Context to load:** `ProofForge/Backend/Solana/SbpfInterpreter.lean` (`SbpfState` :48,
  `step` :215, `run` :273); `ProofForge/Backend/Solana/Asm.lean` (`Opcode`/`Inst`).
- **③ Do:** create `ProofForge/Backend/Solana/SbpfExec.lean` — a **contract-agnostic** library
  of per-instruction step lemmas over `SbpfInterpreter.step`, each proven **once**,
  parameterized by the pre-state, **never by "Counter"**: `mov64`/`add64`/`sub64`/`mul64`/
  `lsh64`, `ldxdw`/`ldxw` (load), `stxdw`/`stxw` (store), `jeq`/`jne`/`ja` (branch), `exit`,
  and `call` (storage read/write syscall stub) — each: "if the instruction at `pc` is X,
  `step` yields this post-state (regs/mem/pc)". Add a `run` unfolding lemma (`run_succ`). If
  `step` is not reduction-friendly, refactor it (we own it — unlike powdr).
- **Acceptance:** `SbpfExec.lean` holds per-instruction step lemmas, contract-agnostic (no
  "Counter" in the statements); `lake build` green. Expect this MUCH smaller than EVM's
  PowdrExec (register machine, no stack, no gas).
- **Depends on:** none (interpreter already exists).

## Task SOL-2 — Per-entrypoint simulation via composition (thin proofs)

- **② Context to load:** `SbpfExec` (SOL-1); `ProofForge/Backend/Solana/SbpfAsm.lean`
  (`lowerModule` — the emitted instruction sequence per entrypoint);
  `ProofForge/Backend/Refinement/CounterUniversal.lean` (the IR-side per-entrypoint sim lemmas).
- **③ Do:** for `initialize`/`increment`/`get`, **compose** the `SbpfExec` lemmas over the
  emitted sBPF sequence to derive each entrypoint's post-state: `initialize` = dispatch ∘
  store-count-0 ∘ `exit`; `increment` = dispatch ∘ `ldxdw` ∘ `add64` ∘ `stxdw` ∘ `exit`;
  `get` = dispatch ∘ `ldxdw` ∘ set-return-data ∘ `exit`. Keep each proof SHORT (a composition),
  NOT a step-by-step hand-derivation.
- **Acceptance:** 3 per-entrypoint simulation theorems, short proofs, green.
- **Depends on:** SOL-1.

## Task SOL-3 — Universal IR↔sBPF refinement (the E3 payoff, self-build)

- **② Context to load:** `ProofForge/Backend/Solana/StateLayout.lean` (the `R` account-data
  offset); `solanaSbpfTargetSemantics` (`Solana/Refinement.lean`); the shared
  `ProofForge.Backend.Refinement.traceSimulation_lift` + `CounterUniversal` induction; the
  `counterTraceSafe` overflow predicate (from the EVM lane / CounterUniversal).
- **③ Do:** define/reuse `R : IR.State ↔ SbpfState` (IR `count` ↔ account-data U64 at the
  `StateLayout` offset); prove per-entrypoint IR↔sBPF simulation from SOL-2; lift to the
  **universal** theorem `∀ safe Counter calls, IR trace ⟷ sBPF interpreter trace` via the
  SHARED induction — **same shape as EVM E3, nearly free once the per-entrypoint sims exist.**
  Handle overflow via `counterTraceSafe` (sBPF `add64` wraps at 64 bits; the safe predicate
  bounds it — the FV-5 overflow boundary on the Solana side).
- **Acceptance:** a universal (`∀` safe calls, by `induction`, NOT `native_decide`) IR↔sBPF
  refinement theorem for Counter; `just solana-light` / `lake build` green; keep the existing
  `native_decide` obligations as regression smoke.
- **Depends on:** SOL-2; P1 (landed); the generic trace induction (landed).

## Task SOL-4 — Genericity test (proves `SbpfExec` actually scales)

> **A simple second contract does NOT prove genericity.** Counter (SOL-2/3) only proves
> `SbpfExec` *works*; a near-identical "two-slot counter" is a weak test — you could pass it
> with a layer that only covers Counter's opcodes. The validation contract must be
> **complex/different enough to exercise the layer in new combinations.**

- **③ Do (two parts):**
  - **(a) A genuinely different contract — use `ValueVault`, NOT a two-slot counter.** It has
    multiple storage fields, multi-step checked arithmetic (deposit/release/fees), events, and
    an accounting invariant, so it exercises `SbpfExec`'s storage/arith/event lemmas in new
    orderings. Discharge its per-entrypoint simulations by **reusing** `SbpfExec` with short
    proofs — no fresh per-instruction hand-derivation.
  - **(b) Full-opcode coverage.** `SbpfExec` must have a lemma for **every opcode the Solana
    lowering (`SbpfAsm.lowerModule`) can emit**, not just Counter's subset — so ANY contract
    in the supported fragment can reuse it. Cross-check the lemma set against `Asm.Opcode`.
- **Acceptance:** ValueVault's obligations discharged by reusing `SbpfExec` (short proofs);
  `SbpfExec` covers the full lowered-opcode set; green. If ValueVault needs fresh
  per-instruction derivation, `SbpfExec` isn't generic yet — go back to SOL-1.
- **Depends on:** SOL-3.

## Task W1 — WASM executable-trace design note (docs only)

- **① Read first:** `docs/solana-sbpf-executable-trace.md` (you are mirroring it);
  `ProofForge/Backend/WasmHost/Refinement/Core.lean` (existing `WasmTraceOp` extraction +
  offline-host obligations); `runtime/offline-host/src/main.rs` (the EXTERNAL semantics
  you will reproduce in-Lean).
- **② Context to load:** `ProofForge/Compiler/Wasm/AST.lean`;
  `ProofForge/Backend/WasmHost/Layout.lean`; `ProofForge/Target/HostBridge.lean`.
- **③ Do:** write `docs/wasm-executable-trace.md` mirroring the Solana note: scope the
  Wasm stack-machine subset (value stack, locals, linear memory), the abstract host model
  (HostBridge functions over an abstract host state), the `R` bridge via `Layout.lean`,
  the phasing (Counter → ValueVault → maps), and the non-goals (Promise/async →
  offline-host). Pure docs, no code.
- **Acceptance:** reviewed note; same section structure as the Solana note; registered in
  `docs/INDEX.md` and (if in the i18n manifest) a zh mirror plan noted.
- **Depends on:** none.

## Task W2 — Wasm interpreter (state + step)

- **① Read first:** `docs/wasm-executable-trace.md` (W1).
- **② Context to load:** `ProofForge/Compiler/Wasm/AST.lean` (`WasmInsn`/`WasmBlock`/
  `WasmFunc`); `ProofForge/Backend/WasmHost/Refinement/Core.lean` (`WasmTraceOp`,
  `wasmInsnTraceOps` — reuse as the instruction enumeration); `ProofForge/Backend/
  WasmNear/EmitWat.lean` (what is actually emitted for Counter).
- **③ Do:** create `ProofForge/Backend/WasmHost/WasmInterpreter.lean`. `WasmState` (value
  stack, locals, linear-memory bytes, abstract host state). `step`/`eval` over the emitted
  subset (`i64.const/add/sub/mul`, `local.get/set/tee`, `i64.load/store`,
  `block/loop/br/br_if/if/call/return`). Fuel-bounded.
- **Acceptance:** `#check` smoke that the interpreter runs the emitted Counter functions.
- **Depends on:** P1, W1.

## Task W3 — Wasm host model (HostBridge-parameterized)

- **② Context to load:** `ProofForge/Target/HostBridge.lean` (`requiredImports`,
  `hostFunctions`); `runtime/offline-host/src/main.rs` (reference behavior);
  `ProofForge/Backend/WasmHost/Layout.lean`.
- **③ Do:** model the HostBridge host functions (`storage_read`/`storage_write`,
  `value_return`, register ABI, `signer_account_id`, `attached_deposit`) as pure
  transitions over the abstract host state. **Parameterize by `HostBridge`** so
  CosmWasm/Soroban reuse it later (this is the FV counterpart of the W0 EmitWat
  unification in execution-plan §2.2).
- **Acceptance:** host calls in the Counter trace resolve against the model; a
  storage read-after-write returns the written value.
- **Depends on:** W2.

## Task W4 — WASM differential obligation

- **③ Do:** add `wasmExecutableTraceOk` + `native_decide` theorem, running the
  interpreter **in-Lean** (so this check no longer relies on the external Rust
  offline-host). Update the `wasm-near` Tier C-diff row in `docs/formal-verification.md`.
- **Acceptance:** the NEAR Lean gate runs the new theorem in-Lean; `just check` green.
- **Depends on:** W2, W3, P1.

## Task W5 — Wasm simulation relation `R`

- **② Context to load:** `ProofForge/Backend/WasmHost/Layout.lean` (Borsh key derivation).
- **③ Do:** define `R : IR.State ↔ Wasm host storage`; state pointwise theorems it holds
  on the Counter scenario after each entrypoint.
- **Acceptance:** `R`-holds theorems `#check` and pass.
- **Depends on:** W2, W3.

---

## WASM C-proof lane (WASM-1–WASM-5) — the chain-FAMILY twin of Solana

> ### ✅ PROGRESS + NEXT (2026-07-08) — WASM-1/2 landed; next is `CounterWasmRefinement` (copy Solana)
>
> **Landed & green:** `WasmExec.lean` (generic core, ~458 lines / 53 lemmas — WASM-1) +
> `NearHost.lean` (NEAR host model, ~480 lines — WASM-2), building green. **Not yet done:**
> `CounterWasmRefinement.lean` (WASM-3/4) — no `counterWasm_*_simulates` exists yet.
>
> **Solana is the finished template — copy it file-for-file.** Solana closed cleanly:
> `SbpfExec.lean` (generic) → `CounterSbpfRefinement.lean` (Counter universal C-proof, closed
> obligations `counterSbpfCoreSafeObligations`, green) → `ValueVaultSbpfExec.lean` (283
> theorems, genericity). WASM mirrors it exactly:
> - **NEXT (WASM-3/4): create `CounterWasmRefinement.lean` by copying `CounterSbpfRefinement.lean`.**
>   Per-entrypoint `counterWasm_{initialize,increment,get}_simulates` composing `WasmExec` +
>   `NearHost` lemmas → construct the **closed** `counterWasm…SafeObligations` term → lift to the
>   universal `counterWasm_safe_trace_simulates_*` via the SHARED `CounterUniversal` induction.
>   Expect it Solana-light (`simp`/`rfl` over our own interpreter), NOT EVM-heavy.
> - **Then (WASM-5): `ValueVaultWasmExec.lean`** (copy `ValueVaultSbpfExec.lean` — contract axis)
>   **+ `CosmWasmHost.lean`** (chain axis — Counter reusing the SAME `WasmExec`, swap host only).
> - **Discipline:** keep `WasmExec` at **0 "Counter"** (it has 1 now — clean it); no NEAR
>   specifics in the core. Same rule that kept `SbpfExec` generic.
>
> **Strategic point (answers "do I formalize all WASM chains?"): NO — one generic core, thin
> per-chain hosts.** Do NOT formalize NEAR/CosmWasm/ICP separately (that is N copies of the
> WASM stack machine — the CosmWasm-forks-EmitWat mistake, on the semantics side). Instead:
> **ONE generic WASM core (`WasmExec`, the stack machine — shared by ALL WASM chains) + a thin
> per-chain HOST model, parameterized by `HostBridge`.** Consider all chains at the
> ARCHITECTURE level (the core must serve all of them); IMPLEMENT the core once + one host at a
> time. This is the semantics-side of W0 (HostBridge-driven EmitWat, execution-plan §2.2).
>
> **Where WASM stands now (= Solana):** the executable interpreter is done
> (`WasmInterpreter.lean` 607 lines, already carries a `bridge : HostBridge` field), plugged
> into `wasmNearTargetSemantics`, C-diff green (Counter / ValueVault / array / map, 44
> `native_decide`). MISSING: the generic core is **not separated** (`runNearHostCall` is
> inlined at :226), no per-instruction lemmas, no C-proof.
>
> **WASM host-family map — you add a HOST, not a chain (one host serves many chains).**
> The WASM contract chains cluster into a few host families; formalize per host family,
> prioritized by reach. `WasmExec` (the core) is shared by ALL of them; each row is a thin
> `*Host.lean`.
>
> | Host family (`*Host.lean`) | Chains it serves | Fit / when |
> |---|---|---|
> | **NEAR** | NEAR | reference (WASM-2) — synchronous storage |
> | **CosmWasm** (`db_read`/`db_write`, JSON msg) | the **entire Cosmos WASM ecosystem** — Secret, Sei, Injective, Osmosis, Juno, Neutron, Archway, Nibiru, Terra… | **2nd host (WASM-5b)** — highest reach; the killer chain-genericity test |
> | **Soroban** (storage + TTL, XDR values) | Stellar Soroban | 3rd — clean sync host (simplest of the three per the SDK survey) |
> | **MultiversX** | MultiversX | sync host; later |
> | **Concordium** | Concordium | sync host; later |
> | **Casper** (Odra) | Casper | sync host; needs a target note first |
> | **ink!/Substrate** | Polkadot, Aleph Zero, Astar | sync host, BUT Polkadot is moving to PolkaVM/RISC-V — check before investing |
> | **EVM (Stylus)** — SPECIAL | Arbitrum Stylus | **its host IS the EVM**: Stylus WASM shares EVM storage slots + account model + Solidity ABI (MultiVM). So Stylus = `WasmExec` core **+ the EVM host we already formalize via powdr (E-lane)** — the WASM and EVM lanes MEET here. Advanced, high-value cross-over |
> | **Radix** (Scrypto) — different model | Radix | asset/resource-oriented, not a plain storage host; may not fit the generic pattern — research first |
> | **ICP / Vara-Gear** — DEFERRED (async) | ICP, Vara/Gear | async inter-canister / actor messaging does NOT fit the synchronous IR effect set; needs the **"IR async effect" design first** (execution-plan §2.4). Not a host-model swap |
>
> **Order:** NEAR (WASM-2) → CosmWasm (WASM-5b, dozens of chains) → Soroban → MultiversX /
> Concordium / Casper / ink! (each a thin host) → Stylus (EVM-host cross-over) → ICP / Vara
> (after the async-effect design). **One core, N hosts — that is the whole point.**
>
> **Two-hop trust (keep forever):** "our WASM interpreter ≈ real wasmtime" stays checked by the
> external offline-host / wasmtime differential gate. **Non-goals (external gate):** NEAR
> Promise / async / cross-contract.

## Task WASM-1 — Extract the generic WASM core `WasmExec.lean` (chain-agnostic)

- **① Read first:** the ⚠️ COURSE CORRECTION under Task E3; Solana Task SOL-1 (same shape).
- **② Context to load:** `ProofForge/Backend/WasmHost/WasmInterpreter.lean` (`WasmState` :115,
  `runHostCall` :309, `runNearHostCall` :226 — currently NEAR-inlined);
  `ProofForge/Compiler/Wasm/AST.lean`; `ProofForge/Target/HostBridge.lean`.
- **③ Do:** create `ProofForge/Backend/WasmHost/WasmExec.lean` — a **chain-agnostic** library
  of per-instruction step lemmas over the WASM stack machine, each proven **once**,
  parameterized by the pre-state, **never by NEAR or "Counter"**: `i64.const/add/sub/mul`,
  `local.get/set/tee`, `i64.load/store`, `block/loop/br/br_if/if/return`, and `call` where the
  **host call is a parameterized hook** (dispatch to a `HostBridge`-provided host model, NOT
  inlined). Add a `run` unfolding lemma. Move NEAR-specific host handling OUT of the core.
- **Acceptance:** `WasmExec.lean` holds chain-agnostic per-instruction lemmas (no NEAR/Counter
  in the statements); the host call is a hook; `lake build` green.
- **Depends on:** none (interpreter exists).

## Task WASM-2 — NEAR host model `NearHost.lean` (first chain instantiation)

- **② Context to load:** `WasmExec` (WASM-1); `runNearHostCall` (`WasmInterpreter.lean:226`);
  `ProofForge/Target/HostBridge.lean` (the NEAR imports); `runtime/offline-host/src/main.rs`.
- **③ Do:** the NEAR host model — `env.storage_read`/`storage_write`, `value_return`, register
  ABI, `signer_account_id`, `attached_deposit` — as transitions over the abstract host state,
  plugged into `WasmExec`'s host hook. Prove the host-op step lemmas (storage read-after-write,
  etc.). Reference host; CosmWasm/ICP hosts mirror it later.
- **Acceptance:** NEAR host lemmas prove; `WasmExec` + `NearHost` reproduce the Counter host
  boundary; green.
- **Depends on:** WASM-1.

## Task WASM-3 — Per-entrypoint simulation via composition (Counter, NEAR)

- **③ Do:** for `initialize`/`increment`/`get`, **compose** `WasmExec` + `NearHost` lemmas
  over the emitted WAT sequence to derive each entrypoint's post-state. Short proofs, NOT
  step-by-step hand-derivation.
- **Acceptance:** 3 per-entrypoint simulation theorems, short proofs, green.
- **Depends on:** WASM-2.

## Task WASM-4 — Universal IR↔WASM refinement (NEAR)

- **② Context to load:** `ProofForge/Backend/WasmHost/Layout.lean` (`R` via Borsh keys);
  `wasmNearTargetSemantics`; the shared `traceSimulation_lift` + `CounterUniversal` induction;
  `counterTraceSafe`.
- **③ Do:** define/reuse `R : IR.State ↔ WasmState host storage`; prove per-entrypoint IR↔WASM
  simulation from WASM-3; lift to the **universal** `∀ safe Counter calls, IR ⟷ WASM(NEAR)
  trace` via the SHARED induction (same as Solana SOL-3, nearly free). Overflow via
  `counterTraceSafe` (WASM `i64.add` wraps at 64 bits).
- **Acceptance:** a universal (`∀` safe calls, by `induction`) IR↔WASM refinement theorem for
  Counter on NEAR; green; keep `native_decide` obligations as regression smoke.
- **Depends on:** WASM-3; P1 (landed); generic induction (landed).

## Task WASM-5 — Double genericity test (contract axis AND chain axis)

> WASM needs **two** genericity tests, not one — because the whole point is a shared core
> across many chains.

- **③ Do:**
  - **(a) Second CONTRACT:** ValueVault reuses `WasmExec` + `NearHost` (like Solana SOL-4);
    full-opcode coverage of what the EmitWat lowering emits.
  - **(b) Second CHAIN — the killer test:** create `CosmWasmHost.lean` (`db_read`/`db_write`)
    and discharge Counter's obligations **reusing the SAME `WasmExec` core**, only swapping the
    host model. If the core needs changes to serve CosmWasm, it isn't chain-generic yet.
- **Acceptance:** ValueVault reuses `WasmExec`+`NearHost`; CosmWasm Counter reuses `WasmExec` +
  a new `CosmWasmHost`; both green. (ICP stays deferred — see the lane header.)
- **Depends on:** WASM-4.

---

## ZK targets — future lane (gated on codegen): group by the Lean-semantics axis, NOT a shared core

> **ZK does NOT have a shared core like WASM.** Cairo (Cairo VM/Sierra), Noir (ACIR), Aleo
> (Leo/AVM), and Psy (DPN) are different arithmetization/VM models with little common structure
> — so there is **no "one ZK core + thin adapters"**. They group instead by **whether a Lean
> semantics exists** (the execution-plan §6 axis), and they all share the FRAMEWORK
> (`TargetSemantics` + `CounterUniversal` induction), not a core.
>
> **Two groups:**
>
> | Group | Targets | Lean semantics | Structure |
> |---|---|---|---|
> | **ZK-import** (high FV value) | **Cairo/Starknet**, **Noir/Aztec** | ✓ exist — Cairo: `starkware-libs/formal-proofs` (Cairo VM/CPU in Lean 4); Noir: Reilabs `Lampe` + NAVe (ACIR) | **same as EVM E-lane**: opt-in lake dep on the external semantics, refine IR against its executable `Step`. Their Lean models ARE execution semantics, so trace-refinement works |
> | **ZK-sourcegen / C-diff** | **Aleo/Leo** (spike: `Backend/Aleo/IR.lean`), **Psy/DPN** (experimental: `Backend/Psy/*`) | ✗ none (snarkVM / DPN) | stay at **differential testing** (vs `leo` / `dargo` result vectors), like pre-interpreter C-diff. Self-building a Lean semantics is a research project — low priority |
>
> **ZK-specific boundary (non-goal, like `solc`):** the **proving system** (STARK for Cairo,
> Barretenberg/Groth16 for Noir, snarkVM for Aleo, Dargo for Psy) stays external. We prove
> **IR ⟷ the circuit's computed function** (functional correctness, via the imported execution
> semantics); "the circuit is sound / the proof verifies" is the ZK project's job (Cairo's AIR
> proofs, the ACIR formalization), not ours.
>
> **CRITICAL PREREQUISITE — codegen first.** Unlike EVM/Solana/WASM (mature codegen), the
> ZK-import targets are NOT code-ready:
> - **Cairo/Starknet** — docs-only research, NO code (no IR→Cairo codegen yet).
> - **Noir** — not in the repo at all; needs a target note + IR→Noir/ACIR codegen.
> - **Aleo/Psy** — have codegen spikes but no Lean semantics (C-diff only).
>
> So the ZK-import refinement is **gated on first building IR→Cairo and IR→Noir codegen** (a
> WS28 sourcegen effort). **Do EVM → Solana → WASM first** (mature codegen); schedule the ZK
> lane when a ZK sourcegen lane opens.
>
> **When the ZK-import lane opens, it copies the EVM E-lane exactly:** `ZK-E1` opt-in lake dep
> on `starkware-libs/formal-proofs` (Cairo) / `reilabs/lampe` (Noir) → `ZK-E2` adapter to its
> `Step` → `ZK-E3` IR↔Cairo / IR↔Noir refinement via the shared `CounterUniversal` induction.
> Aleo + Psy stay at C-diff differential gates until/unless a ZK-app Lean semantics is worth
> self-building.

## Later tasks — C-proof layer (after P2) and deeper slices

These are lower-priority; they build on the C-diff tasks above.

- **P2 — trace induction:** landed in `ProofForge/IR/StepSemantics.lean`
  (`IRTraceMatches`, `runTraceListGen_sound`, proven by induction) and generalized over
  arbitrary target machine states. `ProofForge/Backend/Refinement/Core.lean` now also
  provides `traceSimulation_lift`, the reusable S6/W6 induction lemma: if every atomic
  IR/target call preserves `R` and emits the same observable, then the whole call list
  emits the same observable array. `CounterUniversal.lean` instantiates this as
  `counter_trace_simulates_all_related_via_framework`. The same core module now also
  provides `executableStepSimulationOk_sound` and `executableSimulationTraceOk_sound`,
  which convert concrete paired-step executable checks into Lean evidence for one
  entrypoint or a concrete call list.
- **S6 / W6 — refinement lemmas:** per-entrypoint simulation
  `R s s' → R (stepIR …) (runTarget …)`, then apply `traceSimulation_lift` to get
  whole-trace equality by induction over the call list. The shared lift is landed, and
  both real target runners now have Counter entrypoint-level paired-step soundness checks
  for the concrete `initialize`/`get`/`increment` prefixes, plus whole-trace checks:
  `counter_sbpf_trace_simulation_sound_checked` and
  `counter_wasm_trace_simulation_sound_checked`. The remaining target-specific work is
  to replace these pointwise entrypoint checks with universally quantified
  per-entrypoint simulation lemmas for the sBPF and Wasm interpreters.
  Depends on P1 + P2 + (S3 / W5).
- **S4 / S5 — Solana deeper slices:** ValueVault multiple scalar slots (S4), then
  maps/arrays by porting the IR storage-slot model to sBPF scratch memory (S5).
- **WASM deeper slices:** ValueVault, then maps — mirror S4/S5 using `Layout.lean`.

---

## How to hand a task to a subagent (answers "①去看什么 / ②给它看什么 / ③让它做什么")

For each task, give the subagent exactly its three fields:
1. **① Read first** → the orientation docs (so it understands the tier framing and the
   design note before touching code).
2. **② Context to load** → the concrete files (with line ranges) it must open.
3. **③ Do + Acceptance** → the imperative work and the pass condition (a `just` recipe or
   a `lake env lean --run Tests/…` line).

Dispatch one subagent per task via `superpowers:subagent-driven-development`; review the
diff between tasks. **First moves:** `P1` (unblocks both C-diff lanes) or `W1` (pure docs).
