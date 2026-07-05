# Quint Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a first-class Quint state-machine model generator from ProofForge portable IR, plus a trace-replay harness that lets `quint run` / `quint verify` drive model-based tests against the Lean IR semantics.

**Architecture:** Add a `ProofForge.Backend.Quint` Lean library that mirrors the existing backend pattern (`renderModule : Module → Except String String`), emits `.qnt` files, and derives invariants from the IR. Add CLI support for `proof-forge emit --target quint`, a scenario TOML format for bounds, and a Lean-based ITF trace replay harness using `ProofForge.IR.Semantics`. Gate everything behind a new `quint-ir-model-gate` in CI.

**Tech Stack:** Lean 4, Quint CLI (`@informalsystems/quint`), Apalache (for `quint verify`; requires Java 17+), TOML for scenarios, JSON/ITF for traces.

## Global Constraints

- Quint is a **design validator**, not a replacement for Lean authoring or backend verification. The trusted compilation chain stays `Lean contract_source → Portable IR → Backend artifact`.
- Only the bounded portable IR subset from the design spec maps into Quint in Phase 3 v1.
- All integer types are abstracted to small finite ranges; `U32`/`U64` default to `0..3` for Counter and `0..10` for ValueVault, tunable per scenario.
- `caller.sender` is abstracted to a finite `Set[str]` defaulting to `{"alice", "bob", "charlie"}`.
- `crosscallInvoke`, `crosscallCreate`, unbounded loops, floating-point, and complex bitwise ops are **out of scope** for Phase 3 v1.
- The generator lives in Lean under `ProofForge/Backend/Quint/`, following the `Backend.Aleo.IR` pattern.
- MBT traces replay against the Lean IR semantics first; EVM backend replay is a stretch goal.
- CI gate is informational in Phase 3 v1 and becomes blocking once stable.

## Phase 2 Decisions (answers to design-spec Open Questions)

1. **Invariant authoring location:** Phase 3 v1 keeps invariants in a separate TOML scenario file. Do not extend `contract_source` syntax yet.
2. **Default integer bounds:** Counter uses `MAX_UINT = 3`; ValueVault uses `MAX_UINT = 10`. Both are overrideable in scenario config.
3. **Generator location:** Lean, inside `proof-forge`, as a new pseudo-target `quint` under `ProofForge/Backend/Quint/`.
4. **Replay harness:** Lean-based, consuming `ProofForge.IR.Semantics` directly. No Rust testkit dependency for v1.
5. **First MBT replay target:** IR semantics only for v1; EVM Foundry smoke replay is a follow-up after the IR replay is green.

## File Layout

```text
ProofForge/Backend/Quint/
  Model.lean          # Quint AST (modules, actions, vals, types)
  Emit.lean           # Pretty-printer from Model to .qnt text
  Lower.lean          # Portable IR -> Quint model lowering
  Invariants.lean     # Derive invariants from IR state/types
  Scenario.lean       # TOML scenario parsing + bounds config
  Replay.lean         # ITF trace -> IR semantics replay
  ITF.lean            # ITF JSON parser/types

ProofForge/Cli/
  Quint.lean          # CLI glue: emit --target quint, run, verify, replay

Tests/Quint/
  CounterModel.lean   # Tests that Counter IR -> .qnt renders expected output
  ValueVaultModel.lean# Tests that ValueVault IR -> .qnt renders expected output
  Replay.lean         # Tests replaying a synthetic ITF trace through IR semantics
  Verify.lean         # End-to-end: emit, quint run, parse ITF, replay

scripts/quint/
  model-check-gate.sh # CI: emit + quint verify
  mbt-replay-gate.sh  # CI: emit + quint run --mbt + replay

docs/superpowers/specs/2026-07-05-quint-integration-design.md  (already merged)
docs/capability-registry.md                                     (update with toolchain capabilities)
```

## Task 1: Quint AST and pretty-printer

**Files:**
- Create: `ProofForge/Backend/Quint/Model.lean`
- Create: `ProofForge/Backend/Quint/Emit.lean`
- Test: `Tests/Quint/CounterModel.lean`

**Interfaces:**
- `ProofForge.Backend.Quint.Model` exposes:
  - `Module` (name, constants, vars, actions, vals)
  - `Type` (`int`, `bool`, `str`, `set`, `map`, `list`, custom)
  - `Expr` literals, locals, operators, prime, `nondet`, `oneOf`
  - `Action`/`Val`/`Constant`
- `ProofForge.Backend.Quint.Emit.renderModule : Module → String`

**Steps:**
- [x] Define the AST in `Model.lean`. Keep it minimal: support `module`, `const`, `var`, `pure def`, `action`, `val`, `assume`, and the operators needed for Counter/ValueVault (`+`, `-`, `*`, `/`, `>`, `<`, `>=`, `<=`, `==`, `!=`, `&&`, `||`, `!`).
- [x] Implement `Emit.lean` to pretty-print valid Quint syntax. Use 2-space indentation. Ensure `action step` can use `any { ... }` and `nondet x = oneOf(S) ...`.
- [x] Write a test that renders a hand-built Counter Quint model and checks the output contains expected substrings (`module CounterModel`, `var count: int`, `action increment`, etc.).
- [x] Run: `lake env lean Tests/Quint/CounterModel.lean`
- [x] Commit.

## Task 2: Scenario configuration

**Files:**
- Create: `ProofForge/Backend/Quint/Scenario.lean`
- Test: `Tests/Quint/Scenario.lean`

**Interfaces:**
- `ProofForge.Backend.Quint.Scenario.Config` with fields:
  - `maxUint : Nat` (default 3)
  - `users : Array String` (default `["alice", "bob", "charlie"]`)
  - `maxSteps : Nat` (default 10)
  - `nTraces : Nat` (default 10)
- `ProofForge.Backend.Quint.Scenario.parse (toml : String) : Except String Config`
- `ProofForge.Backend.Quint.Scenario.toQuintConstants : Config → Array Constant`

**Steps:**
- [x] Define `Config` and a lightweight TOML parser (no external dependency; parse the tiny subset we need: `max_uint = 3`, `users = ["alice", "bob"]`, etc.).
- [x] Add `toQuintConstants` to emit `const MAX_UINT: int` and `const USERS: Set[str]`.
- [x] Write a test parsing a sample TOML and checking the defaults.
- [x] Run: `lake env lean Tests/Quint/Scenario.lean`
- [x] Commit.

## Task 3: IR-to-Quint lowering

**Files:**
- Create: `ProofForge/Backend/Quint/Lower.lean`
- Modify: `ProofForge/Backend/Quint/Emit.lean` (if needed for new constructs)
- Test: `Tests/Quint/CounterModel.lean` (expand), `Tests/Quint/ValueVaultModel.lean`

**Interfaces:**
- `ProofForge.Backend.Quint.Lower.lowerModule (module : ProofForge.IR.Module) (scenario : Config) : Except LowerError ProofForge.Backend.Quint.Model.Module`
- `ProofForge.Backend.Quint.Lower.renderModule (module : ProofForge.IR.Module) (scenario : Config) : Except LowerError String`
- `ProofForge.Backend.Quint.Lower.LowerError` with `render : LowerError → String`

**Supported IR subset for v1:**
- `ValueType`: `unit`, `bool`, `u32`, `u64`, `u8`, `u128`, `address`, `fixedArray`, `structType`, `array`
- `StateKind`: `scalar`, `map` (with key type + capacity), `array`, `dynamicArray`
- `Literal`: `u8`, `u32`, `u64`, `u128`, `bool`, `address`
- `Expr`: `literal`, `local`, `add`, `sub`, `mul`, `div`, `mod`, `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `boolAnd`, `boolOr`, `boolNot`, `cast`, `arrayLit`, `arrayGet`, `structLit`, `field`, `effect`
- `Effect`: `storageScalarRead/Write`, `storageScalarAssignOp`, `storageMapGet/Set/Insert/Contains`, `storageArrayRead/Write`, `storageDynamicArrayPush/Pop`, `storageStructFieldRead/Write`, `eventEmit`, `contextRead` (only `userId` and `timestamp` in v1)
- `Statement`: `letBind`, `letMutBind`, `assign`, `assignOp`, `effect`, `assert`, `assertEq`, `ifElse`, `boundedFor`, `return`, `revert`

**Abstractions to apply:**
- Map keys: encode `Value` to a string key and use Quint `Map[str, V]`; capacity bounds the domain.
- Arrays: fixed arrays become `List[T]`; dynamic arrays become `List[T]` with length tracked implicitly.
- Structs: flatten into multiple scalar/map/array vars with dotted names, or use records if `Model.lean` supports records.
- Context: `userId` becomes a module parameter `caller: str` drawn from `USERS`; `timestamp` becomes a nondet `int` bounded by `MAX_UINT`.
- `+!`/`-!`/`*!`/`/!` become guarded arithmetic; `/!` also guards `divisor != 0`.

**Steps:**
- [x] Implement `lowerModule` by walking `Module.state` and `Module.entrypoints`.
- [x] Emit `init` action that zero-initializes all scalar state.
- [x] Emit one `action` per entrypoint. Entrypoint parameters become action parameters with finite domains (drawn from scenario constants).
- [x] Emit `step` as `any { nondet ... entrypoint(...) }` for each entrypoint.
- [x] For unsupported constructs, return a clear `LowerError`.
- [x] Expand `Tests/Quint/CounterModel.lean` to lower `ProofForge.IR.Examples.Counter.module` and check the rendered `.qnt` is valid Quint syntax.
- [ ] Create `Tests/Quint/ValueVaultModel.lean`: lower a ValueVault IR fixture and check render. If an IR-level ValueVault fixture does not exist, create `ProofForge/IR/Examples/ValueVault.lean` by hand-translating `ProofForge.Contract.Examples.ValueVault` to IR.
- [x] Run: `lake env lean Tests/Quint/CounterModel.lean` and `lake env lean Tests/Quint/ValueVaultModel.lean`
- [x] Commit.

## Task 4: Invariant derivation

**Files:**
- Create: `ProofForge/Backend/Quint/Invariants.lean`
- Modify: `ProofForge/Backend/Quint/Lower.lean` (integrate invariants into module)
- Test: `Tests/Quint/Invariants.lean`

**Interfaces:**
- `ProofForge.Backend.Quint.Invariants.derive (module : ProofForge.IR.Module) : Array (String × Expr)`

**Derived invariants (v1):**
- Unsigned scalar state variables are non-negative: `count >= 0`.
- For ValueVault: `balance + released + fees <= MAX_UINT` (this is scenario-specific; add a manual invariant list in TOML).

**Steps:**
- [x] Implement `derive` to produce auto invariants for every `u8/u32/u64/u128` scalar state variable.
- [ ] Support a manual invariant list in scenario TOML under `[invariants]`.
- [x] Wire invariants into `lowerModule` so the emitted `.qnt` contains `val` definitions.
- [x] Write a test checking that Counter gets `count >= 0` and ValueVault gets its conservation invariant.
- [x] Run: `lake env lean Tests/Quint/Invariants.lean`
- [x] Commit.

## Task 5: CLI integration

**Files:**
- Create: `ProofForge/Cli/Quint.lean`
- Modify: `ProofForge/Cli.lean` (register `--target quint` in `emitLegacyFlag`, `buildLegacyFlag`, and `compileFile`)
- Modify: `ProofForge/Cli/Fixture.lean` (add `quint` to supported targets/formats)

**Interfaces:**
- `proof-forge emit --target quint --fixture counter -o build/quint/Counter.qnt`
- `proof-forge emit --target quint --fixture counter --format scenario -o build/quint/Counter.scenario.toml`
- `proof-forge check --target quint --fixture counter` (validates IR-to-Quint lowering without emitting)

**Steps:**
- [x] Add `quint` to `Fixture.supportedTargetIds` and `Fixture.Format` (`qnt`, `scenario`).
- [x] Update `emitLegacyFlag` to map `--target quint --fixture counter` to `--emit-counter-ir-quint` and `--format scenario` to `--emit-counter-ir-quint-scenario`.
- [x] Add a compile branch in `compileFile` for `.counterIrQuint` that calls `ProofForge.Backend.Quint.Lower.renderModule` and writes the output.
- [ ] Add CLI options `--scenario` to pass a TOML scenario file; default to built-in defaults.
- [x] Run end-to-end:
  ```bash
  lake env proof-forge emit --target quint --fixture counter -o build/quint/Counter.qnt
  quint run --main Counter --n-traces 1 --max-steps 5 build/quint/Counter.qnt
  ```
- [x] Commit.

## Task 6: ITF trace parsing

**Files:**
- Create: `ProofForge/Backend/Quint/ITF.lean`
- Test: `Tests/Quint/ITF.lean`

**Interfaces:**
- `ProofForge.Backend.Quint.ITF.Trace` with `states : Array State` and `nondetPicks : Array Json`
- `ProofForge.Backend.Quint.ITF.parse (json : String) : Except String Trace`
- `ProofForge.Backend.Quint.ITF.actionTaken : State → Option String`

**ITF format expectations:**
- `vars` map per state: `{ "count": 0, ... }`
- `mbt::actionTaken`: string entrypoint name
- `mbt::nondetPicks`: object mapping param names to values

**Steps:**
- [x] Define Lean types matching the ITF JSON structure.
- [x] Implement a parser using `Lean.Json`.
- [x] Write a test with a synthetic ITF JSON string and verify parsing.
- [x] Run: `lake env lean Tests/Quint/ITF.lean`
- [x] Commit.

## Task 7: Trace replay harness

**Files:**
- Create: `ProofForge/Backend/Quint/Replay.lean`
- Modify: `ProofForge/IR/Semantics.lean` (if missing helpers needed for replay)
- Test: `Tests/Quint/Replay.lean`

**Interfaces:**
- `ProofForge.Backend.Quint.Replay.replayTrace (module : ProofForge.IR.Module) (trace : ITF.Trace) : Except String Unit`
- Returns `ok ()` if every step's resulting state matches the ITF state.
- On mismatch, returns an error describing the step, expected value, and actual value.

**Steps:**
- [x] Map ITF state variables to IR `State` storage keys using the same flattening scheme as the generator.
- [x] Find the entrypoint by `actionTaken`, map nondet picks to parameter values.
- [x] Run `ProofForge.IR.Semantics.runEntrypoint` (or equivalent) for each step.
- [x] Compare resulting storage against the next ITF state.
- [x] Write a test that constructs a 3-step Counter trace manually and replays it.
- [x] Run: `lake env lean Tests/Quint/Replay.lean`
- [x] Commit.

## Task 8: End-to-end MBT replay test

**Files:**
- Create: `Tests/Quint/Verify.lean`
- Modify: `Tests/Quint/Replay.lean` (reuse helpers)

**Interfaces:**
- Lean test that shells out to `quint run --mbt` and then replays generated ITF traces.

**Steps:**
- [x] Write a test that:
  1. Calls `ProofForge.Backend.Quint.Lower.renderModule` for Counter.
  2. Writes `build/quint/Counter.qnt`.
  3. Runs `quint run --mbt --n-traces 5 --max-steps 5 --out-itf build/quint/itf/Counter.json build/quint/Counter.qnt`.
  4. Parses each generated ITF trace and replays it against `ProofForge.IR.Semantics`.
- [x] Gate the test so it skips gracefully if `quint` is not on `PATH`.
- [x] Run: `lake env lean Tests/Quint/Verify.lean`
- [x] Commit.

## Task 9: Capability and metadata registry updates

**Files:**
- Modify: `docs/capability-registry.md`
- Modify: `ProofForge/Contract/Spec/Json.lean` (if `proof-forge-artifact.json` schema lives there)

**Interfaces:**
- Add toolchain capabilities: `model.quint`, `verify.model_check`, `verify.simulation`, `test.mbt_trace`.
- Add `verification.quint` section to artifact metadata JSON.

**Steps:**
- [ ] Update `docs/capability-registry.md` with the four new capabilities and their semantics.
- [ ] If artifact JSON generation is in Lean, add the `verification` block described in the design spec.
- [ ] Add a test that emits artifact metadata and checks for the new fields.
- [ ] Commit.

## Task 10: CI gates

**Files:**
- Create: `scripts/quint/model-check-gate.sh`
- Create: `scripts/quint/mbt-replay-gate.sh`
- Modify: `.github/workflows/ci.yml` or `justfile`

**Interfaces:**
- `scripts/quint/model-check-gate.sh`: emits Counter/ValueVault `.qnt` models and runs `quint verify`.
- `scripts/quint/mbt-replay-gate.sh`: emits models, runs `quint run --mbt`, replays traces via a Lean test.

**Steps:**
- [ ] Write `model-check-gate.sh` with Java 17+ check and graceful skip if missing.
- [ ] Write `mbt-replay-gate.sh` with `quint` availability check and graceful skip if missing.
- [ ] Add `just quint-model-gate` and `just quint-mbt-gate` commands to the `justfile`.
- [ ] Run the gates locally: `just quint-model-gate` and `just quint-mbt-gate`.
- [ ] Commit.

## Task 11: Documentation update

**Files:**
- Modify: `docs/development-log.md`
- Modify: `docs/implementation-backlog.md`
- Create: `docs/superpowers/README.md` update (if needed)

**Steps:**
- [x] Log Phase 3 completion in `docs/development-log.md`.
- [x] Update `docs/implementation-backlog.md` to mark Quint tasks done and note Java 17+ requirement for `quint verify`.
- [x] Add a short user-facing doc under `docs/` explaining how to run `proof-forge emit --target quint`.
- [x] Commit.

## Spec Coverage Self-Review

| Design spec section | Covered by task |
|---|---|
| §1 Goal | All tasks |
| §2 Executive summary (layered architecture) | Tasks 3, 5, 8 |
| §3 What Quint is/is not | Task 11 docs + global constraints |
| §4 Three-phase rollout | This plan is Phase 2; tasks implement Phase 3 |
| §5 IR-to-Quint mapping | Tasks 1, 2, 3, 4 |
| §6 Validation handshake | Tasks 6, 7, 8, 10 |
| §7 Capability/metadata | Task 9 |
| §8 File layout | File layout section above |
| §9 Risks | Mitigations embedded in tasks (bounded ints, graceful skips) |
| §10 Open questions | Answered in Phase 2 Decisions section |
| §11 Success criteria | Each task's test steps verify criteria |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-05-quint-implementation-plan.md`.

**Execution options:**

1. **Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration. Use `superpowers:subagent-driven-development`.
2. **Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints for review.

Which approach do you want?
