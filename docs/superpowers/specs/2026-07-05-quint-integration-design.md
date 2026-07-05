# Quint Integration Design: From ProofForge IR to Executable Model

**Date:** 2026-07-05  
**Status:** Design spec (awaiting review)  
**Scope:** Document-only design for introducing Quint as a specification and model-checking layer for ProofForge contracts. This round produces the architectural contract and phase boundaries; implementation code is out of scope.  
**Related docs:**
- [Formal verification roadmap](../../../formal-verification.md)
- [Portable IR](../../../portable-ir.md)
- [Shared scenario: Counter / ValueVault](../../../shared-scenario.md)
- [Authoring model](../../../authoring-model.md)
- [Validation gates](../../../validation-gates.md)
- External: https://quint.sh/docs/why

---

## 1. Goal

Add Quint as a first-class specification layer in ProofForge so that a contract's portable IR can be automatically lifted into an executable Quint state-machine model. That model can then be simulated, model-checked, and used to generate model-based testing (MBT) traces that ProofForge replays against its own IR interpreter and target backends.

This spec defines:
1. The exact role Quint plays in the ProofForge toolchain (and what it does **not** do).
2. A three-phase rollout ending in "IR → Quint model" generation.
3. The subset of portable IR that maps into Quint.
4. The validation handshake between Quint and ProofForge.
5. File layout, capability surface, and artifact metadata extensions.

It explicitly does **not** write implementation code, add new CLI commands, or modify the IR AST.

---

## 2. Executive Summary

ProofForge is already a Lean-first, multi-chain compiler with a portable IR, executable IR semantics, and per-backend trace obligations. Its weakest upstream link is the gap between **design intent** and **verified implementation**: authors write `contract_source`, but there is no lightweight way to explore whether the intended state machine allows bad states before committing to backend code.

Quint is an executable specification language built on TLA. It is designed for exactly this problem: model state machines, express invariants, simulate them, and model-check them. It is **not** a production programming language and should not replace Lean as the contract authoring surface.

The recommended architecture is layered:

```text
Lean contract_source
  -> Portable IR
  -> Quint model generator (Phase 3)
  -> .qnt state-machine model
  -> quint run / quint verify / quint test
  -> ITF traces
  -> ProofForge testkit replay against IR + backends
```

The long-term product promise: every portable contract comes with an auto-generated Quint model that can be model-checked in CI, and every invariant violation produces a concrete trace that can be replayed against the generated EVM/Solana/NEAR artifact.

---

## 3. What Quint Is and Is Not in ProofForge

### 3.1 Quint is good for

| Use case | Why it fits |
|---|---|
| State-machine design validation | Contracts are state + entrypoints + transitions; Quint's `var`/`action` model maps directly. |
| Safety invariants | "Balance never negative", "total supply conserved", "vault cannot be drained". |
| Counter-example generation | `quint run` finds trace; trace becomes a regression test. |
| Bounded model checking | `quint verify` with Apalache checks invariants up to a step bound. |
| Model-based testing | `quint run --mbt` produces ITF traces that ProofForge can replay. |
| Protocol-level reasoning | Multi-step interactions, reentrancy, access-control races, ordering bugs. |

### 3.2 Quint is not good for

| Use case | Why it does not fit |
|---|---|
| Replacing Lean as the production language | Quint has no sound path to EVM bytecode / Solana ELF / NEAR Wasm. |
| Unbounded integer reasoning over `uint256` | Model checkers need finite, small domains; `uint256` must be abstracted. |
| Verifying backend lowering correctness | That stays inside Lean (FV-4 backend trace obligations). |
| Replacing existing Lean IR semantics | Lean's executable IR semantics is the ground truth for proofs; Quint is an upstream oracle. |
| On-chain execution | Quint models are off-chain reasoning artifacts only. |

### 3.3 Trust boundary

Quint does not become part of the trusted compilation chain. The truth chain remains:

```text
Lean contract_source  ->  Portable IR  ->  Backend artifact
        ^                      ^                ^
        |                      |                |
   user writes            Lean proofs     differential tests / trace obligations
```

Quint sits **above** the IR as a design validator:

```text
Quint model  --(model check)-->  invariants hold for the abstraction
      ^
      |
 auto-generated from IR subset
```

If Quint reports an invariant violation, either the design is wrong or the abstraction is wrong. If Quint reports success, the implementation may still be wrong; the abstraction must be validated separately by replaying traces against the IR/backends.

---

## 4. Three-Phase Rollout

### Phase 1: Documentation and planning (this document)

Deliverables:
- This design spec, reviewed and committed.
- A decision on the first IR-to-Quint subset (recommended: Counter + ValueVault scalar subset).
- A draft capability proposal for the capability registry.
- A trace-format contract between Quint ITF and ProofForge testkit.

Exit criteria:
- [ ] Design spec approved by maintainers.
- [ ] First target subset documented.
- [ ] No open architectural questions that block Phase 2.

### Phase 2: Implementation plan

Deliverables:
- Detailed implementation plan with per-task file paths, interfaces, tests, and commands.
- Plan covers: Quint AST/emitter library, IR-to-Quint lowering rules, testkit trace replay, CI integration.

Exit criteria:
- [ ] Implementation plan approved.
- [ ] Every spec requirement maps to at least one task.
- [ ] No placeholders.

### Phase 3: Implementation

Deliverables:
- A Quint model generator from portable IR.
- Generated `.qnt` models for Counter and ValueVault.
- `quint run` / `quint verify` integration in CI.
- ITF trace replay against IR interpreter and at least one backend (EVM recommended first).
- Artifact metadata records the Quint spec hash and verification command.

Exit criteria:
- [ ] `proof-forge` can emit a `.qnt` model from a portable IR fixture.
- [ ] `quint verify` passes on generated Counter/ValueVault models for documented invariants.
- [ ] At least one Quint-generated trace replays successfully through ProofForge testkit.
- [ ] CI gate exists and is documented.

---

## 5. IR-to-Quint Mapping Design

### 5.1 Supported portable IR subset (Phase 3 v1)

Only the following IR constructs lift cleanly into Quint without semantic drift:

| IR construct | Quint construct | Notes |
|---|---|---|
| Module name | `module Name { ... }` | Top-level namespace. |
| Scalar storage (`storage.scalar`) | `var name: Type` | Persistent contract state. |
| Entrypoint | `action` | Public transition. Private helpers become `pure def`. |
| Entrypoint parameters | Action parameters | Abstracted to small finite domains. |
| Return value | Pure result of action | Not all targets return values the same way; model returns a value expression. |
| `U32`, `U64`, `Bool` | `int`, `bool` | Integers are abstracted to a small bounded range (e.g. `0..MAX_INT`). |
| `if/else` | `if (p) ... else ...` | Standard expression form. |
| `boundedFor` | Fold or bounded iteration | Lower to `foldl` over a range; unbounded loops rejected. |
| Checked arithmetic (`+!`, `-!`, `*!`, `/!`) | Guarded arithmetic | Overflow/underflow/division-by-zero become action guards or error states. |
| `assert` / `assert_eq` | Action guards | Failed assertion blocks the transition. |
| Storage read/write | `var'` delayed assignment | Prime operator maps to next-state value. |
| Map storage (`storage.map`) | `Map[K, V]` | Finite map; keys bounded. |
| Fixed array storage | `List[T]` | Length fixed at model generation time. |
| Struct storage | Records | Flat structs only. |
| Event emission | Trace record / witness variable | Events become observable trace items, not state variables. |
| `env.block`, `caller.sender`, `value.native` | Constants or nondet choices | Block context abstracted per scenario; caller abstracted to a finite set. |

### 5.2 Abstraction rules

To keep model checking feasible, the generator must apply explicit abstractions:

1. **Integer bounding.** All `U32`/`U64` values are mapped to a configurable finite range, e.g. `0..MAX_UINT` where `MAX_UINT` defaults to 3 for Counter-style specs and is tunable per scenario. Checked arithmetic guards are preserved.
2. **Address/user sets.** `caller.sender` is abstracted to a finite `Set[Addr]` supplied as a module constant. The default is `Set("alice", "bob", "charlie")`.
3. **Map key bounding.** Map keys are drawn from a finite set of representative values, not the full type domain.
4. **No cross-contract calls in v1.** `crosscallInvoke` and `crosscallCreate` are out of scope for the first generator. They may be modeled as nondet external effects in a later phase.
5. **No unbounded loops.** `boundedFor` is allowed only when the bound is statically known or supplied as a constant.
6. **No floating-point or bitwise beyond word ops.** Bitwise ops that have clear integer semantics (`&`, `|`, `^`, shifts) may be added later; floating point is permanently out of scope.

### 5.3 Quint model shape

A generated model for a contract `C` has this shape:

```quint
module CModel {
  // 1. Constants (scenario parameters)
  const MAX_BALANCE: int
  const USERS: Set[str]

  // 2. State variables (one per scalar/map/array storage slot)
  var balance: int
  var released: int
  var fees: int

  // 3. Pure helpers (arithmetic, guards, derived values)
  pure def netValue(bal: int, fee: int): int = bal - fee

  // 4. Initial state
  action init = all {
    balance' = 0,
    released' = 0,
    fees' = 0,
  }

  // 5. Entrypoint actions
  action deposit(amount: int): bool = all {
    amount > 0,
    amount <= MAX_BALANCE - balance,
    balance' = balance + amount,
    released' = released,
    fees' = fees,
  }

  action release(amount: int): bool = all {
    amount > 0,
    amount <= balance,
    balance' = balance - amount,
    released' = released + amount,
    fees' = fees,
  }

  // 6. Step action (nondet choice among entrypoints)
  action step = any {
    nondet amount = oneOf(1.to(MAX_BALANCE))
    deposit(amount),
    nondet amount = oneOf(1.to(MAX_BALANCE))
    release(amount),
  }

  // 7. Invariants
  val noNegativeBalance = balance >= 0
  val conservation = balance + released + fees <= MAX_BALANCE
}
```

Invariants are generated from two sources:
- **Auto-derived:** storage type bounds, checked-arithmetic guards, non-negative balances for unsigned types.
- **User-supplied:** optional invariant annotations in `contract_source` (future work, out of Phase 3 v1).

For Phase 3 v1, invariants are declared in a separate `.qnt` file or in a Quint `assume`/`val` block that the generator emits alongside the model.

---

## 6. Validation Handshake: Quint ↔ ProofForge

### 6.1 Quint-to-ProofForge direction: MBT traces

```text
quint run CModel.qnt --mbt --n-traces N --out-itf build/quint/C/itf/
```

Each ITF trace is a sequence of states with:
- `mbt::actionTaken`: entrypoint name.
- `mbt::nondetPicks`: concrete values for nondet parameters.
- State snapshot: all `var` values.

ProofForge testkit consumes these traces and replays them:
1. Initialize the IR interpreter / EVM runtime / Solana Mollusk / NEAR offline-host to the trace's initial state.
2. For each step, invoke the named entrypoint with the concrete parameters.
3. Assert that the observable state (return values, storage, events) matches the trace.

This is the same trace-obligation pattern already used in FV-4, but the traces now come from Quint instead of hand-written scenarios.

### 6.2 ProofForge-to-Quint direction: IR model generation

```text
proof-forge emit --target quint --fixture value-vault -o build/quint/ValueVault.qnt
```

The generator reads the portable IR fixture and emits:
- `ValueVault.qnt`: the state-machine model.
- `ValueVault.invariants.qnt`: optional invariant module.
- `ValueVault.scenario.toml`: integer bounds, user sets, and max-step parameters per scenario.

### 6.3 CI gate design

A new validation gate, `quint-ir-model-gate`, runs:

```text
1. Emit .qnt model from portable IR fixture.
2. quint verify --invariants ... --max-steps K
3. quint run --mbt --n-traces N --out-itf ...
4. Replay N traces through ProofForge IR interpreter.
5. Replay a sampled subset through at least one backend (EVM Foundry smoke).
```

The gate is informational in Phase 3 v1 and becomes blocking once it is stable.

---

## 7. Capability and Metadata Extensions

### 7.1 Proposed capabilities

These capabilities are added to `docs/capability-registry.md`:

| Capability | Meaning |
|---|---|
| `model.quint` | Target emits a Quint state-machine model. |
| `verify.model_check` | Generated model can be checked with Apalache/TLC. |
| `verify.simulation` | Generated model can be simulated with `quint run`. |
| `test.mbt_trace` | Generated model can produce ITF traces for replay. |

They are not runtime capabilities of a chain; they are **toolchain capabilities** attached to the `quint` pseudo-target or to the verification stage of every real target.

### 7.2 Artifact metadata

`proof-forge-artifact.json` gains a `verification` section:

```json
{
  "verification": {
    "quint": {
      "modelHash": "sha256:...",
      "modelPath": "build/quint/ValueVault.qnt",
      "invariants": ["noNegativeBalance", "conservation"],
      "verifyCommand": "quint verify ValueVault.qnt --invariants noNegativeBalance,conservation --max-steps 10",
      "maxSteps": 10,
      "checker": "apalache"
    }
  }
}
```

---

## 8. File Layout

No files are created in Phase 1. The planned implementation layout is:

```text
ProofForge/Backend/Quint/           # Generator and emitter
  Model.lean                        # Quint AST
  Emit.lean                         # Pretty-printer to .qnt
  Lower.lean                        # Portable IR -> Quint model
  Invariants.lean                   # Invariant derivation
  Scenario.lean                     # Scenario/bounds configuration

Tests/Quint/                        # Generator tests
  CounterModel.lean                 # Generated Counter model fixtures
  ValueVaultModel.lean              # Generated ValueVault model fixtures
  Replay.lean                       # ITF trace replay harness

scripts/quint/                      # CI glue
  model-check-gate.sh
  mbt-replay-gate.sh

build/quint/                        # Generated artifacts (git-ignored)
  Counter.qnt
  ValueVault.qnt
  ValueVault.itf/
```

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Abstraction drift: model says OK but implementation is buggy | High | Always pair Quint success with trace replay against IR/backends. Never treat Quint as the sole verifier. |
| State space explosion | Medium | Use small bounded integers, small user sets, and bounded maps. Document tuning parameters per scenario. |
| Users confuse Quint with the authoring language | Medium | Clear naming: "Quint model", "Quint spec", not "Quint contract". Keep Lean as the only authoring surface. |
| Maintenance burden of two specifications | Medium | Generate the Quint model from IR, do not hand-write it. The only hand-written artifact is the invariant list. |
| Temporal properties not supported by Apalache | Low | Phase 3 v1 uses only invariants. Liveness properties are future work. |
| Toolchain dependency on `quint` CLI / Apalache / Java | Medium | Add `quint` and Java to documented prerequisites; gate skips gracefully if missing in Phase 3 v1. |

---

## 10. Open Questions

1. Should invariants be authored in Lean near `contract_source`, or in a separate `.qnt`/`.toml` file for Phase 3 v1?
2. What is the default integer bound for the Counter/ValueVault models? Is `0..3` enough to catch interesting bugs?
3. Should the generator live in Lean (as part of `proof-forge`) or as a standalone tool that consumes IR JSON?
4. Do we reuse the existing `testkit` Rust harness for ITF replay, or add a Lean-based replay harness?
5. Which backend is the first MBT replay target: EVM (most mature), NEAR offline-host (deterministic), or Solana Mollusk?

These questions are answered in Phase 2 before implementation begins.

---

## 11. Success Criteria for This Design Spec

- [ ] The role of Quint is clearly separated from Lean authoring and backend verification.
- [ ] The three-phase rollout is agreed upon.
- [ ] The supported IR-to-Quint subset is documented and bounded.
- [ ] The validation handshake (model generation + MBT trace replay) is defined.
- [ ] Capability and metadata extensions are proposed.
- [ ] File layout and risks are documented.
- [ ] All open questions are listed and assigned to Phase 2.
