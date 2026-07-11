# Canonical Core IR and Target-Plan Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current fail-open Core API spike with one checked Canonical Core boundary, migrate the three primary targets through their existing plan types, then prove the boundary with Queue/Set normalization and a typed NEAR HostOp.

**Architecture:** Frozen Legacy `ContractSpec` and the new independent `Frontend.Surface` both normalize to `CanonicalBundle`; only `CheckedCanonicalContract` and a resolved `CapabilityPlan` reach the existing EVM, Solana, and NEAR target plans. Target allocation stays in those plans, every pass returns `Except`, and public target IDs do not change.

**Tech Stack:** Lean 4, Lake, ProofForge compiler/CLI, `just`, solc/Foundry/Anvil, the repository sBPF assembler/encoder/executor, wabt `wat2wasm`, and the NEAR offline host.

## Global Constraints

- Public target IDs remain `evm`, `solana-sbpf-asm`, `wasm-near`, `wasm-cosmwasm`, `wasm-cloudflare-workers`, `wasm-stellar-soroban`, `move-aptos`, `move-sui`, `psy-dpn`, and `aleo-leo`; `quint` remains CLI-only.
- Never register `evm-core`, `solana-sbpf-asm-core`, or `wasm-near-core`.
- `ProofForge.IR.Contract` is frozen. New syntax cannot add a constructor or field there.
- Core storage uses logical `StateId` and `StateShape`; physical slots, offsets, account indices, and KV prefixes are target-plan data.
- Core is typed ANF/CFG. Every value-producing effect has explicit results and every CFG cycle preserves its loop-bound requirement.
- `CanonicalEvidence` is absent from capability and plan-builder signatures and cannot affect emitted code.
- Reuse `Evm.Plan.ModulePlan`, `Solana.Plan.SolanaModulePlan`, and `NearModulePlan.NearModulePlan`; do not add parallel target plan types.
- Normalize, validate, capability resolution, HostOp resolution, plan, lower, render, and artifact validation all fail closed.
- Queue and Set do not add Core or target-plan constructors.
- Run `just product` before backend-heavy gates whenever authoring or portable behavior changes.
- Live Surfpool/Pinocchio gates remain optional because their tools are not installed in the default environment.
- The worktree may contain unrelated user changes. Inspect `git status --short`, stage only paths listed by the current task, never run `git add -A`, and never revert unrelated changes.

---

## Delivery Map

| Wave | Deliverable | Promotion gate |
|---|---|---|
| 0 | Honest registry and internal-only migration lane | Public registry exact; no fail-open Core target |
| 1 | Stable Core schema, validator, semantics, Legacy inventory | Invalid programs reject; semantic anchors pass |
| 2 | Counter/ValueVault Legacy adapter parity | State/return/event/error/effect parity |
| 3 | Typed HostOp and existing target-plan builders | EVM, Solana, NEAR tool/runtime parity |
| 3B | Complete existing advertised fragment | Canonical product and coverage manifests pass |
| 4 | Independent Surface plus Queue/Set | No Core/backend diff for collection feature |
| 5 | NEAR Promise HostOp vertical slice | NEAR success; EVM/Solana typed rejection |
| 6 | Public-route cutover and spike removal | `just product`, `just check`, docs and diff gates |

## File Ownership

### Canonical Core

| File | Responsibility |
|---|---|
| `ProofForge/IR/Core/Id.lean` | Resolved canonical IDs and symbol table keys |
| `ProofForge/IR/Core/Type.lean` | Core types, literals, arithmetic/error policies |
| `ProofForge/IR/Core/Storage.lean` | Logical state shapes and typed paths |
| `ProofForge/IR/Core/HostOp.lean` | HostOp ID, version, signature, call, catalog |
| `ProofForge/IR/Core/Syntax.lean` | ANF instructions, CFG blocks, functions, module |
| `ProofForge/IR/Core/Validate.lean` | Type, dominance, CFG, storage, HostOp validation |
| `ProofForge/IR/Core/Semantics.lean` | Executable small-step Core semantics |
| `ProofForge/IR/Core/Semantics/Lemmas.lean` | Storage and arithmetic proof anchors |
| `ProofForge/IR/Core.lean` | Imports the focused Core modules only |
| `ProofForge/IR/Canonical.lean` | Canonical contract, materialization, evidence, checked wrapper |

### Inputs

| File | Responsibility |
|---|---|
| `ProofForge/IR/Legacy/Classification.lean` | Exhaustive Legacy constructor and field policy |
| `ProofForge/IR/Legacy/Adapter.lean` | `ContractSpec -> CanonicalBundle` |
| `ProofForge/IR/Legacy/Refinement.lean` | Observable relation and preservation lemmas |
| `ProofForge/Frontend/Surface/Type.lean` | Independent Surface types and IDs |
| `ProofForge/Frontend/Surface/Syntax.lean` | Independent Surface AST |
| `ProofForge/Frontend/Surface/Normalize.lean` | Surface typecheck and Core normalization |
| `ProofForge/Frontend/Surface/Semantics.lean` | Surface observable semantics for normalization checks |
| `ProofForge/Frontend/Surface.lean` | Surface exports |
| `ProofForge/Frontend.lean` | Frontend exports |

### Target Integration

| File | Responsibility |
|---|---|
| `ProofForge/Target/HostOpRegistry.lean` | Typed target-handler registry |
| `ProofForge/Compiler/CanonicalPipeline.lean` | Internal legacy/canonical dual-run API |
| `ProofForge/Backend/Evm/Plan/Core.lean` | Checked Core to existing EVM `ModulePlan` |
| `ProofForge/Backend/Solana/Plan/Core.lean` | Checked Core to existing `SolanaModulePlan` |
| `ProofForge/Backend/WasmHost/NearModulePlan/Core.lean` | Checked Core to existing `NearModulePlan` |
| `Tests/Canonical/Emit.lean` | Internal artifact emitter for parity scripts |
| `scripts/canonical/check-boundary.sh` | Mechanical dependency/public-ID checks |

---

## Wave 0: Restore an Honest Boundary

### Task 1: Remove Public Core Target Claims

**Files:**
- Create: `Tests/Canonical/RegistryBoundary.lean`
- Modify: `ProofForge/Target/Registry.lean`
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `justfile`
- Test: `Tests/TargetRegistry.lean`

**Interfaces:**
- Consumes: current target registry and CLI driver tables.
- Produces: exact public registry with no pipeline-variant target and no fail-open `core-product` recipe.

- [ ] **Step 1: Write the failing registry boundary test**

```lean
import ProofForge.Target.Registry

open ProofForge.Target

def expectedIds : Array String := #[
  "evm",
  "solana-sbpf-asm",
  "wasm-near",
  "wasm-cosmwasm",
  "wasm-cloudflare-workers",
  "wasm-stellar-soroban",
  "move-aptos",
  "move-sui",
  "psy-dpn",
  "aleo-leo"
]

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  require (knownIds == expectedIds) s!"unexpected public targets: {knownIds}"
  require (!knownIds.any (·.endsWith "-core")) "pipeline target leaked into registry"
  IO.println "canonical-registry-boundary: ok"
```

- [ ] **Step 2: Run the test and confirm the current spike fails**

Run:

```bash
lake env lean --run Tests/Canonical/RegistryBoundary.lean
```

Expected: FAIL because at least one public ID ends with `-core`.

- [ ] **Step 3: Remove the three Core profiles and dispatch entries**

Delete the Core profile values and their entries from `allIncludingDeprecated`,
`BackendRegistry`, and the CLI driver table. Remove the fail-open
`core-product` and `core-*-smoke` recipes. Keep the implementation files
temporarily compiled so later tasks can replace them without hiding work.

- [ ] **Step 4: Run registry and documentation truthfulness gates**

```bash
lake env lean --run Tests/Canonical/RegistryBoundary.lean
just target-registry
just target-backend
just target-support
just registry-command
git diff --check
```

Expected: all commands pass and generated backend status remains unchanged.

- [ ] **Step 5: Commit only the registry-boundary files**

```bash
git add Tests/Canonical/RegistryBoundary.lean ProofForge/Target/Registry.lean ProofForge/Target/BackendRegistry.lean ProofForge/Cli/TargetDriver.lean justfile
git commit -m "fix(target): keep canonical pipeline internal"
```

### Task 2: Freeze and Classify Legacy IR

**Files:**
- Create: `ProofForge/IR/Legacy/Classification.lean`
- Create: `Tests/Canonical/LegacyInventory.lean`
- Create: `scripts/canonical/check-legacy-freeze.sh`
- Modify: `ProofForge/IR.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `LegacyDisposition`, `LegacyDecision`, exhaustive
  `classifyExpr`, `classifyEffect`, `classifyStatement`, and
  `classifySpecFields`.
- Guarantees: every current Legacy constructor has an owner before the adapter
  can accept it.

- [ ] **Step 1: Add a failing inventory test**

```lean
import ProofForge.IR.Legacy.Classification

open ProofForge.IR.Legacy

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  require (allDecisions.all fun decision => decision.reason.trim != "")
    "legacy decision without reason"
  require (allDecisions.all fun decision => decision.owner.trim != "")
    "legacy decision without owner"
  require (allNodeTags.eraseDups.size == allNodeTags.size)
    "duplicate legacy node tag"
  require (contractSpecFieldDecisions.map (·.field) == expectedContractSpecFields)
    "ContractSpec field inventory drift"
  IO.println "canonical-legacy-inventory: ok"
```

Run:

```bash
lake env lean --run Tests/Canonical/LegacyInventory.lean
```

Expected: FAIL because the classification module does not exist.

- [ ] **Step 2: Define the classification contract**

```lean
inductive LegacyDisposition
  | preserve
  | normalize
  | materialization
  | evidence
  | reject
  deriving BEq, Repr

structure LegacyDecision where
  nodeTag : String
  disposition : LegacyDisposition
  owner : String
  reason : String
  deriving BEq, Repr
```

Use an explicit match arm for every current constructor. The initial accepted
runtime fragment is:

| Legacy group | Initial disposition |
|---|---|
| fixed-width literals, local, scalar arithmetic/comparison/boolean | preserve/normalize |
| scalar read/write/assign-op, context read, event emit | normalize |
| let/bind/assign/assert/revert/if/bounded loop/return | normalize |
| structs, maps, fixed/dynamic arrays, storage paths | reject until their Core validator and semantics tasks land |
| crosscalls and target-only receiver checks | reject until a typed portable primitive or HostOp handler exists |
| NEAR promise constructors | reject until Task 17 |
| selector/ABI/event words, allocator, constructor, upgrade/proxy, intents | materialization |
| Quint/Lean invariants, source provenance | evidence |

Do not use wildcard match arms. A new constructor must make this module fail to
compile until it receives a decision.

- [ ] **Step 3: Add the freeze script**

`scripts/canonical/check-legacy-freeze.sh` must fail when a diff adds a line
matching `^[[:space:]]*[|]` inside the `Expr`, `Effect`, or `Statement`
declarations without also changing `Legacy/Classification.lean`. It prints:

```text
legacy-freeze: IR.Contract changed without classification update
```

Add a `legacy-freeze` recipe, but do not add it to `just check` until the
current branch passes it.

- [ ] **Step 4: Run the inventory and freeze tests**

```bash
lake env lean --run Tests/Canonical/LegacyInventory.lean
just legacy-freeze
lake build
git diff --check
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/IR/Legacy/Classification.lean Tests/Canonical/LegacyInventory.lean scripts/canonical/check-legacy-freeze.sh ProofForge/IR.lean justfile
git commit -m "refactor(ir): freeze and classify legacy contract IR"
```

---

## Wave 1: Build the Canonical Core

### Task 3: Replace the Spike AST with Logical Typed Core

**Files:**
- Create: `ProofForge/IR/Core/Id.lean`
- Create: `ProofForge/IR/Core/Type.lean`
- Create: `ProofForge/IR/Core/Storage.lean`
- Create: `ProofForge/IR/Core/Syntax.lean`
- Rewrite: `ProofForge/IR/Core.lean`
- Create: `Tests/Canonical/CoreSchema.lean`
- Modify: `ProofForge/IR/Core/Error.lean`

**Interfaces:**
- Produces: `TypeId`, `StateId`, `FunctionId`, `EventId`, `BlockId`,
  `ValueId`, `ValueDef`, `ValueRef`, `CoreType`, `StateShape`,
  `StorageRef`, `Instruction`, `Terminator`, `Block`, `Function`,
  and `Module`.
- Removes: numeric storage slots, nested effectful expressions, string HostOp
  stubs, and statement-tree control flow from canonical Core.

- [ ] **Step 1: Write schema tests that the spike cannot satisfy**

The test constructs six distinct logical state declarations, verifies that two
`StateId` values cannot alias by layout number, and checks:

```lean
def checkedAdd : InstructionOp :=
  .pure (.arithmetic .add .checked
    { id := ⟨0⟩, type := .u64 }
    { id := ⟨1⟩, type := .u64 })

def wrappingAdd : InstructionOp :=
  .pure (.arithmetic .add .wrapping
    { id := ⟨0⟩, type := .u64 }
    { id := ⟨1⟩, type := .u64 })

#eval checkedAdd != wrappingAdd
```

It also constructs scalar, map, fixed-array, dynamic-array, and record
`StateShape` values and a storage path rooted at `StateId`, never at `Nat`.

Run:

```bash
lake env lean --run Tests/Canonical/CoreSchema.lean
```

Expected: FAIL because the required modules and types do not exist.

- [ ] **Step 2: Implement the ID, type, and storage modules**

Use separate `ValueDef` and `ValueRef`:

```lean
structure ValueDef where
  id : ValueId
  type : CoreType
  deriving BEq, Repr

structure ValueRef where
  id : ValueId
  type : CoreType
  deriving BEq, Repr
```

`StorageRef.root` is `StateId`; `StorageSegment` contains typed
`mapKey`, `index`, and resolved `FieldId`. No Core file may define
`slot : Nat`, `accountOffset`, or `keyPtr`.

- [ ] **Step 3: Implement ANF/CFG syntax**

`Instruction.results : Array ValueDef`. Effectful loads, context reads, and
HostOps use those results. `Block.params : Array ValueDef`. Every block has
one `Terminator`. `Terminator.jump` carries `Option LoopBound`; a cycle
without one is invalid.

- [ ] **Step 4: Run schema and build gates**

```bash
lake env lean --run Tests/Canonical/CoreSchema.lean
lake build
rg -n "slot : Nat|accountOffset|keyPtr" ProofForge/IR/Core
git diff --check
```

Expected: test/build pass and `rg` returns no matches.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/IR/Core.lean ProofForge/IR/Core/Id.lean ProofForge/IR/Core/Type.lean ProofForge/IR/Core/Storage.lean ProofForge/IR/Core/Syntax.lean ProofForge/IR/Core/Error.lean Tests/Canonical/CoreSchema.lean
git commit -m "refactor(core): define logical typed ANF and CFG"
```

### Task 4: Add Canonical Contract Ownership and Full Validation

**Files:**
- Create: `ProofForge/IR/Canonical.lean`
- Rewrite: `ProofForge/IR/Core/Validate.lean`
- Create: `Tests/Canonical/CoreValidate.lean`
- Create: `Tests/Canonical/EvidenceIsolation.lean`
- Modify: `ProofForge/IR.lean`

**Interfaces:**
- Produces: `CanonicalContract`, `CanonicalEvidence`,
  `CanonicalBundle`, `CheckedCanonicalContract`, and
  `validateCanonical : CanonicalContract -> Except ValidationError CheckedCanonicalContract`.
- Guarantees: plan builders receive a checked runtime/materialization contract
  and never receive evidence.

- [ ] **Step 1: Write the failing negative-validation matrix**

`Tests/Canonical/CoreValidate.lean` must use a helper
`expectError : ValidationErrorTag -> CanonicalContract -> IO Unit` and cover:

| Invalid input | Expected tag |
|---|---|
| duplicate state/value/block ID | `duplicateId` |
| unknown struct/state/function/event | `unknownReference` |
| literal outside fixed-width range | `literalOutOfRange` |
| use before definition or non-dominating definition | `invalidDominance` |
| wrong operand/result/block-argument type | `typeMismatch` |
| map key on scalar or wrong map key type | `invalidStoragePath` |
| array index with non-integer type | `invalidStoragePath` |
| CFG cycle without `LoopBound` | `missingLoopBound` |
| return arity/type mismatch | `invalidReturn` |
| interface references unknown function | `invalidInterface` |
| constructor binding references unknown state | `invalidMaterialization` |

Run and expect a missing API failure:

```bash
lake env lean --run Tests/Canonical/CoreValidate.lean
```

- [ ] **Step 2: Define canonical ownership**

`CanonicalContract` contains `Core.Module`, `InterfaceContract`,
`MaterializationContract`, and typed capability requirements.
`CanonicalEvidence` contains only source maps, verification annotations, and
Legacy classification evidence. Do not place selector, ABI, constructor,
upgrade, proxy, allocator, or capability data in evidence.

- [ ] **Step 3: Implement validation in fixed order**

Run passes in this order so diagnostics are deterministic:

1. symbol uniqueness and declaration tables;
2. state-shape and interface/materialization references;
3. CFG shape, reachability, and cycle bounds;
4. dominance and value environments;
5. instruction input/result typing;
6. terminator and return typing;
7. capability and HostOp references.

Each semantic error records function, block, instruction index, and reason.
`decorateValidationError` may add a source span from
`CanonicalEvidence.sourceMap`, but it cannot change the error tag or
validation result.

- [ ] **Step 4: Prove evidence isolation with deterministic output**

`Tests/Canonical/EvidenceIsolation.lean` creates two bundles with identical
`CheckedCanonicalContract` and different evidence, then verifies:

```lean
require (bundleA.contract == bundleB.contract) "contract changed"
require (capabilityRequirements bundleA.contract ==
  capabilityRequirements bundleB.contract) "evidence changed capabilities"
```

The target artifact equality check is added per backend in Tasks 8-10.

- [ ] **Step 5: Run and commit**

```bash
lake env lean --run Tests/Canonical/CoreValidate.lean
lake env lean --run Tests/Canonical/EvidenceIsolation.lean
lake build
git diff --check
git add ProofForge/IR/Canonical.lean ProofForge/IR/Core/Validate.lean Tests/Canonical/CoreValidate.lean Tests/Canonical/EvidenceIsolation.lean ProofForge/IR.lean
git commit -m "feat(core): validate canonical contract ownership"
```

### Task 5: Add Executable Core Semantics and Proof Anchors

**Files:**
- Create: `ProofForge/IR/Core/Semantics.lean`
- Create: `ProofForge/IR/Core/Semantics/Lemmas.lean`
- Create: `Tests/Canonical/CoreSemantics.lean`
- Create: `Tests/Canonical/CoreSemanticsProofs.lean`
- Modify: `ProofForge/IR/Core.lean`

**Interfaces:**
- Produces: `CoreValue`, `LogicalState`, `Machine`, `ObservableTrace`,
  `HostSemantics`, and fuel-bounded `execute`.
- Produces proof anchors: `write_read_same`, `write_read_other`,
  `map_key_separation`, `array_index_separation`.

- [ ] **Step 1: Write failing semantic scenarios**

Cover all of these in `Tests/Canonical/CoreSemantics.lean`:

- two logical scalar states remain isolated;
- wrapping `u8 255 + 1` returns zero;
- checked `u8 255 + 1` returns overflow error;
- divide by zero, failed assert, and explicit revert have distinct errors;
- map keys and array indices remain isolated;
- array out-of-bounds fails;
- branch and block arguments select the correct return;
- bounded loop consumes the declared number of iterations;
- a missing HostSemantics binding fails instead of returning a default.

Run:

```bash
lake env lean --run Tests/Canonical/CoreSemantics.lean
```

Expected: FAIL because Core semantics does not exist.

- [ ] **Step 2: Implement a total fuel-bounded machine**

`execute` validates first and returns:

```lean
def execute
    (host : HostSemantics)
    (fuel : Nat)
    (contract : CheckedCanonicalContract)
    (entrypoint : FunctionId)
    (args : Array CoreValue)
    (state : LogicalState) :
    Except RuntimeError ExecutionResult
```

Do not use `partial def` for execution. Missing state defaults are derived
from the declared Core type; never hard-code `.u64 0`.

- [ ] **Step 3: Add the four storage lemmas and arithmetic examples**

`Tests/Canonical/CoreSemanticsProofs.lean` imports the lemma module and
contains `example` proofs for same-path read-after-write, different-state
isolation, map-key isolation, array-index isolation, and checked/wrapping
distinction.

- [ ] **Step 4: Run and commit**

```bash
lake env lean --run Tests/Canonical/CoreSemantics.lean
lake env lean Tests/Canonical/CoreSemanticsProofs.lean
lake build
git diff --check
git add ProofForge/IR/Core/Semantics.lean ProofForge/IR/Core/Semantics/Lemmas.lean Tests/Canonical/CoreSemantics.lean Tests/Canonical/CoreSemanticsProofs.lean ProofForge/IR/Core.lean
git commit -m "feat(core): define executable canonical semantics"
```

---

## Wave 2: Adapt Legacy Programs Without Losing Semantics

### Task 6: Implement the Fail-Closed Legacy Adapter

**Files:**
- Create: `ProofForge/IR/Legacy/Adapter/Env.lean`
- Create: `ProofForge/IR/Legacy/Adapter/Expr.lean`
- Create: `ProofForge/IR/Legacy/Adapter/Statement.lean`
- Create: `ProofForge/IR/Legacy/Adapter.lean`
- Rewrite: `ProofForge/IR/Elaborate.lean` as a deprecated facade
- Create: `Tests/Canonical/LegacyAdapter.lean`
- Modify: `ProofForge/IR/Legacy/Classification.lean`
- Modify: `ProofForge/IR.lean`

**Interfaces:**
- Produces:
  `adaptLegacy : ContractSpec -> Except CanonicalizeError CanonicalBundle`.
- Consumes: the exhaustive classification from Task 2 and Core builder types
  from Tasks 3-4.
- Initial accepted fragment: every construct used by the real Counter and
  ValueVault fixtures.

- [ ] **Step 1: Write failing adapter assertions against real fixtures**

`Tests/Canonical/LegacyAdapter.lean` must adapt:

```lean
def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

def vaultSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module
```

Assert the following facts, not only `.isOk`:

- Counter has one distinct state and three functions;
- ValueVault has six distinct `StateId` values and seven functions;
- every scalar load/store points to the declaration with the same source name;
- `checkpointId` becomes a value-producing context instruction;
- every event and return remains in its original effect order;
- wrapping and checked arithmetic remain distinct;
- entrypoint kind, mutability, parameters, return type, and dispatch hints
  survive in `InterfaceContract`;
- all `ContractSpec` fields are either materialization or evidence;
- `u8 256`, `u32 2^32`, `u64 2^64`, and `u128 2^128` reject before
  numeric narrowing;
- an unknown state name returns `unknownState`, never state zero.

Run:

```bash
lake env lean --run Tests/Canonical/LegacyAdapter.lean
```

Expected: FAIL because `adaptLegacy` is missing.

- [ ] **Step 2: Build resolved adapter environments**

`Adapter.Env` assigns deterministic IDs to types, states, functions, events,
blocks, and values. Every lookup returns `Except CanonicalizeError`. The state
environment stores source name, `StateId`, and `StateShape`; it never stores
a target slot.

- [ ] **Step 3: Normalize expressions to ordered ANF**

Use a state monad over a value/block name supply. Expression normalization
returns:

```lean
structure NormalizedValue where
  instructions : Array Core.Instruction
  value : Core.ValueRef
```

Evaluate operands left-to-right. Scalar storage and context reads append an
instruction and return its result. Arithmetic records the node's explicit
overflow flag. No dummy `Inhabited`, wildcard fallback, or `partial def` is
allowed.

- [ ] **Step 4: Normalize statements to CFG**

`ifElse` creates true, false, and continuation blocks. `boundedFor` creates
a backedge with `.atMost (stopExclusive - start)`. `whileLoop` is rejected
until it can carry `.requiresUnbounded` and capability resolution. Return and
revert terminate blocks; appending another statement to a terminated block is
an error.

- [ ] **Step 5: Preserve the complete `ContractSpec` envelope**

Map artifact-affecting fields into `InterfaceContract` or
`MaterializationContract`. Map invariant/source proof links into
`CanonicalEvidence`. If a source field has no canonical owner, return
`unclassifiedField`; do not ignore it.

- [ ] **Step 6: Run and commit**

```bash
lake env lean --run Tests/Canonical/LegacyAdapter.lean
lake build
git diff --check
git add ProofForge/IR/Legacy/Adapter/Env.lean ProofForge/IR/Legacy/Adapter/Expr.lean ProofForge/IR/Legacy/Adapter/Statement.lean ProofForge/IR/Legacy/Adapter.lean ProofForge/IR/Elaborate.lean Tests/Canonical/LegacyAdapter.lean ProofForge/IR/Legacy/Classification.lean ProofForge/IR.lean
git commit -m "feat(core): adapt legacy contracts without semantic loss"
```

### Task 7: Add Legacy-to-Core Observable Parity

**Files:**
- Create: `ProofForge/IR/Legacy/Refinement.lean`
- Create: `Tests/Canonical/LegacyParity.lean`
- Create: `Tests/Canonical/LegacyRefinement.lean`
- Modify: `ProofForge/IR/Legacy/Classification.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `LegacyScalarFragment`, `StateRelation`,
  `ObservableRelation`, and
  `adaptLegacy_preserves_scalar_fragment`.
- Produces the first `canonical-core` recipe.

- [ ] **Step 1: Write failing differential scenarios**

`Tests/Canonical/LegacyParity.lean` runs both existing
`ProofForge.IR.Semantics` and `Core.Semantics` for:

| Contract | Scenario |
|---|---|
| Counter | initialize; increment twice; get |
| ValueVault | initialize 100; deposit 25; charge fee; release; snapshot; getters |
| Counter error | checked overflow fixture |
| ValueVault error | release beyond balance fixture |

Compare logical state by source state name, returned values, event names and
arguments, structured errors, and ordered effect trace. Target layout and
internal value IDs are intentionally excluded.

Run:

```bash
lake env lean --run Tests/Canonical/LegacyParity.lean
```

Expected: FAIL until the relation and runner exist.

- [ ] **Step 2: Define the supported fragment and local lemmas**

`LegacyScalarFragment` accepts precisely the Legacy decisions marked
`preserve` or `normalize` for Task 6. Prove local preservation for literals,
locals, scalar load/store, context read, arithmetic, event, branch, return, and
revert. Combine those lemmas into:

```lean
theorem adaptLegacy_preserves_scalar_fragment
    (h : LegacyScalarFragment spec) :
    ObservableRelation
      (IR.Semantics.execute spec.module scenario)
      (Core.Semantics.execute host fuel
        (adaptLegacy spec).toChecked scenario)
```

- [ ] **Step 3: Register the canonical Core gate**

```make
canonical-core:
    lake env lean --run Tests/Canonical/CoreSchema.lean
    lake env lean --run Tests/Canonical/CoreValidate.lean
    lake env lean --run Tests/Canonical/CoreSemantics.lean
    lake env lean --run Tests/Canonical/LegacyAdapter.lean
    lake env lean --run Tests/Canonical/LegacyParity.lean
    lake env lean Tests/Canonical/LegacyRefinement.lean
```

Use the repository's `justfile` syntax, preserving the command order above.

- [ ] **Step 4: Run and commit**

```bash
just canonical-core
lake build
git diff --check
git add ProofForge/IR/Legacy/Refinement.lean Tests/Canonical/LegacyParity.lean Tests/Canonical/LegacyRefinement.lean ProofForge/IR/Legacy/Classification.lean justfile
git commit -m "proof(core): relate legacy and canonical observables"
```

---

## Wave 3: Typed HostOps and Existing Target Plans

### Task 8: Add the Typed HostOp and Capability Contract

**Files:**
- Create: `ProofForge/IR/Core/HostOp.lean`
- Create: `ProofForge/Target/HostOpRegistry.lean`
- Create: `Tests/Canonical/HostOpCatalog.lean`
- Create: `Tests/Canonical/HostOpFailClosed.lean`
- Modify: `ProofForge/IR/Core/Syntax.lean`
- Modify: `ProofForge/IR/Core/Validate.lean`
- Modify: `ProofForge/IR/Core/Semantics.lean`
- Modify: `ProofForge/Target/Plan.lean`
- Modify: `ProofForge/Contract/Intent.lean`
- Modify: `ProofForge/Contract/Builder.lean`
- Modify: `ProofForge/Target/Adapter.lean`
- Modify: `ProofForge/Backend/Solana/Extension/Parse.lean`
- Modify: `ProofForge/Cli/TargetJson.lean`
- Modify: `ProofForge/Cli/LearnArtifacts.lean`

**Interfaces:**
- Produces: `HostOpVersion`, `HostOpId`, `HostOpEffectClass`,
  `HostOpSig`, `HostOpCall`, `HostOpCatalog`,
  `HostOpHandler PlanOp`, and `HostOpRegistry PlanOp`.
- Changes: `CapabilityCall.operation : CapabilityOperation`, with
  `CapabilityOperation.builtin` and `.hostOp`.

- [ ] **Step 1: Write the failing HostOp matrix**

`HostOpCatalog.lean` defines two signatures with different exact versions and
checks deterministic lookup. `HostOpFailClosed.lean` must reject:

- unknown namespace or name;
- unknown major, minor, or patch version;
- duplicate catalog ID;
- wrong argument arity or type;
- wrong instruction result arity or type;
- pure operation used with effectful signature;
- missing required capability;
- target has capability but no handler;
- handler registered under a different target;
- handler output fails target-plan validation.

Run:

```bash
lake env lean --run Tests/Canonical/HostOpCatalog.lean
lake env lean --run Tests/Canonical/HostOpFailClosed.lean
```

Expected: FAIL because HostOp is still a string stub.

- [ ] **Step 2: Define exact IDs and signatures**

```lean
structure HostOpVersion where
  major : Nat
  minor : Nat
  patch : Nat
  deriving BEq, Ord, Repr

structure HostOpId where
  namespace : String
  name : String
  version : HostOpVersion
  deriving BEq, Ord, Repr

structure HostOpSig where
  id : HostOpId
  params : Array CoreType
  results : Array CoreType
  effectClass : HostOpEffectClass
  requiredCapabilities : Array Capability
  deriving BEq, Repr
```

Catalog lookup is exact. Duplicate registration is an error, not last-write
wins. `HostOpCall` contains only ID and typed argument references; result
definitions remain on the enclosing Core instruction.

- [ ] **Step 3: Replace the string capability operation**

```lean
inductive CapabilityOperation
  | builtin (name : String)
  | hostOp (id : HostOpId)
  deriving BEq, Repr

def CapabilityOperation.render : CapabilityOperation -> String
```

Update production callers listed under **Files** to construct `.builtin`.
Keep JSON and learn artifacts wire-compatible by rendering builtins to their
old strings and HostOps to
`namespace/name@major.minor.patch`. Update every compiler error from
`.operation` use; do not add an untyped compatibility field.

- [ ] **Step 4: Connect validation, capability resolution, and semantics**

Core validation checks catalog signature and instruction results. Capability
planning adds each HostOp signature's required capabilities. Target resolution
requires both the capability and handler. Core execution delegates to
`HostSemantics.eval`; absent semantics returns `unknownHostOp`.

- [ ] **Step 5: Run focused and regression tests**

```bash
lake env lean --run Tests/Canonical/HostOpCatalog.lean
lake env lean --run Tests/Canonical/HostOpFailClosed.lean
lake env lean --run Tests/SharedTokenIntent.lean
lake env lean --run Tests/TokenSpec.lean
lake build
git diff --check
```

Expected: all pass and existing builtin operation JSON strings remain stable.

- [ ] **Step 6: Commit**

```bash
git add ProofForge/IR/Core/HostOp.lean ProofForge/Target/HostOpRegistry.lean Tests/Canonical/HostOpCatalog.lean Tests/Canonical/HostOpFailClosed.lean ProofForge/IR/Core/Syntax.lean ProofForge/IR/Core/Validate.lean ProofForge/IR/Core/Semantics.lean ProofForge/Target/Plan.lean ProofForge/Contract/Intent.lean ProofForge/Contract/Builder.lean ProofForge/Target/Adapter.lean ProofForge/Backend/Solana/Extension/Parse.lean ProofForge/Cli/TargetJson.lean ProofForge/Cli/LearnArtifacts.lean
git commit -m "feat(core): add typed versioned host operations"
```

### Task 9: Add the Internal Dual-Run Compiler Harness

**Files:**
- Create: `ProofForge/Compiler/CanonicalPipeline.lean`
- Create: `Tests/Canonical/Emit.lean`
- Create: `Tests/Canonical/PipelineMode.lean`
- Modify: `ProofForge.lean`
- Modify: `justfile`

**Interfaces:**
- Produces: `CompilerPipeline.legacy`, `.canonical`, and internal
  `compileForTest`.
- Does not modify CLI usage, `Target.knownIds`, backend registry, or release
  packaging.

- [ ] **Step 1: Write a failing visibility test**

`PipelineMode.lean` checks that both modes are callable from Lean, while
`Target.knownIds` and rendered CLI help contain neither `canonical` nor
`-core` as a target.

- [ ] **Step 2: Implement the internal interface**

```lean
inductive CompilerPipeline
  | legacy
  | canonical

def compileForTest
    (mode : CompilerPipeline)
    (targetId : String)
    (spec : ContractSpec) :
    IO (Except CompileDiagnostic ArtifactBundle)
```

`.legacy` calls the frozen baseline functions directly. `.canonical` calls
`adaptLegacy`, `validateCanonical`, capability resolution, and the target's
`buildFromCore`. Never catch canonical failure and retry legacy.

`Tests/Canonical/Emit.lean` parses explicit
`--pipeline legacy|canonical --target <id> --fixture counter|value-vault --out <dir>`
arguments and writes test artifacts under `build/canonical/`.

- [ ] **Step 3: Run and commit**

```bash
lake env lean --run Tests/Canonical/PipelineMode.lean
lake build
git diff --check
git add ProofForge/Compiler/CanonicalPipeline.lean Tests/Canonical/Emit.lean Tests/Canonical/PipelineMode.lean ProofForge.lean justfile
git commit -m "test(core): add internal canonical dual-run harness"
```

### Task 10: Feed Canonical Core into the Existing EVM Plan

**Files:**
- Create: `ProofForge/Backend/Evm/Plan/Core.lean`
- Create: `Tests/Backend/Evm/CanonicalPlan.lean`
- Create: `scripts/canonical/evm-parity.sh`
- Modify: `ProofForge/Backend/Evm/Plan.lean`
- Modify: `ProofForge/Backend/Evm/Lower.lean`
- Modify: `ProofForge/Backend/Evm.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `Tests/Canonical/EvidenceIsolation.lean`
- Modify: `justfile`

**Interfaces:**
- Produces:
  `Evm.Plan.buildFromCore : CheckedCanonicalContract -> CapabilityPlan -> Except PlanError ModulePlan`.
- Produces a lowerer whose semantic input is the existing `ModulePlan`, not a
  Legacy module or final Yul AST.

- [ ] **Step 1: Write failing plan assertions**

`CanonicalPlan.lean` checks Counter and ValueVault:

- physical slot allocation is injective over logical `StateId`;
- selectors/ABI come from `InterfaceContract`, never zero fallback;
- each non-empty Core function has a non-empty `StmtPlan` body;
- checked/wrapping operations select different helpers;
- return plans exist for every non-unit function;
- evidence changes do not change `ModulePlan`;
- missing capability, unsupported Core op, and incomplete return fail.

- [ ] **Step 2: Build existing EVM semantic plans from Core**

Map Core pure/storage/context/event/control instructions into the existing
`ExprPlan`, `EffectPlan`, and `StmtPlan`. Resolve logical storage through
`StorageLayout` in this builder. Move shared scalar/ABI/error types out of
Legacy AST imports or map them explicitly to EVM plan types; the Core builder
must not consume `IR.Expr`, `IR.Effect`, `IR.Statement`, or `IR.Module`.

- [ ] **Step 3: Make lower/render fail closed**

The canonical lowerer consumes the complete existing `ModulePlan`. Remove
best-effort fallbacks for empty body, missing selector, unsupported expression,
and missing return. Validate the produced Yul AST before printing.

- [ ] **Step 4: Add toolchain and runtime parity**

`scripts/canonical/evm-parity.sh` runs:

```bash
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline legacy --target evm --fixture counter --out build/canonical/evm/legacy-counter
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target evm --fixture counter --out build/canonical/evm/core-counter
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline legacy --target evm --fixture value-vault --out build/canonical/evm/legacy-vault
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target evm --fixture value-vault --out build/canonical/evm/core-vault
solc --strict-assembly --bin --overwrite -o build/canonical/evm/solc build/canonical/evm/core-counter/contract.yul
solc --strict-assembly --bin --overwrite -o build/canonical/evm/solc build/canonical/evm/core-vault/contract.yul
```

Then reuse the repository Foundry/Anvil scenario helpers to compare state,
returns, events, and reverts between the two artifacts. Text equality is not
required.

- [ ] **Step 5: Run the EVM cutover gate**

```bash
lake env lean --run Tests/Backend/Evm/CanonicalPlan.lean
scripts/canonical/evm-parity.sh
just evm-all
git diff --check
```

Expected: all pass before `evm` routing changes.

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Backend/Evm/Plan/Core.lean Tests/Backend/Evm/CanonicalPlan.lean scripts/canonical/evm-parity.sh ProofForge/Backend/Evm/Plan.lean ProofForge/Backend/Evm/Lower.lean ProofForge/Backend/Evm.lean ProofForge/Compiler/CanonicalPipeline.lean Tests/Canonical/EvidenceIsolation.lean justfile
git commit -m "feat(evm): build existing plan from canonical core"
```

### Task 11: Feed Canonical Core into the Existing Solana Plan

**Files:**
- Create: `ProofForge/Backend/Solana/Plan/Core.lean`
- Create: `Tests/Backend/Solana/CanonicalPlan.lean`
- Create: `scripts/canonical/solana-parity.sh`
- Modify: `ProofForge/Backend/Solana/Plan.lean`
- Modify: `ProofForge/Backend/Solana/SbpfAsm.lean`
- Modify: `ProofForge/Backend/Solana.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `Tests/Canonical/EvidenceIsolation.lean`
- Modify: `justfile`

**Interfaces:**
- Produces:
  `Solana.Plan.buildFromCore : CheckedCanonicalContract -> CapabilityPlan -> Except PlanError SolanaModulePlan`.
- Extends the existing plan with target-semantic `SolanaOpPlan`; it does not
  store `AstNode` or Legacy declarations.

- [ ] **Step 1: Write failing Solana plan tests**

Check:

- six ValueVault states receive distinct account-data ranges;
- account/data/discriminator/parameter layout matches the legacy baseline;
- function bodies contain semantic load/store/arithmetic/branch/return ops;
- `SolanaLowerCtxSeed` contains resolved target layout, not
  `IR.StructDecl`, `IR.StateDecl`, or `IR.Module`;
- missing account capability, invalid alignment, unsupported Core operation,
  and missing return fail;
- different evidence produces identical plan and assembly.

- [ ] **Step 2: Extend the existing plan with semantic operations**

Define `SolanaOpPlan` for validated constants, locals, account-data
load/store, arithmetic, comparison, branch, log, assert/revert, and return.
Target HostOp handlers added later also return this type. Physical account
offsets are allocated here from logical state shapes.

Replace legacy-bearing `SolanaLowerCtxSeed` fields with resolved
`SolanaStateFieldPlan`, target struct layouts, input layout, manifest
accounts, and extensions. The assembler consumes only the complete plan.

- [ ] **Step 3: Make sBPF lowering fail closed**

Add `lowerFromPlan : SolanaModulePlan -> Except LowerError (Array AstNode)`.
Unknown plan op, invalid register assignment, missing epilogue, or verifier
failure returns an error. The legacy wrapper may still build its old plan for
dual-run, but canonical lowering cannot call `SbpfAsm.lowerModule` on a Legacy
module.

- [ ] **Step 4: Add assembler/execution parity**

`solana-parity.sh` emits legacy and canonical Counter/ValueVault assembly,
runs the repository assembler/encoder/verifier, and executes existing
Counter/ValueVault sBPF scenarios. Compare return data, account bytes, logs,
and errors.

- [ ] **Step 5: Run the Solana cutover gate**

```bash
lake env lean --run Tests/Backend/Solana/CanonicalPlan.lean
scripts/canonical/solana-parity.sh
just solana-light
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Backend/Solana/Plan/Core.lean Tests/Backend/Solana/CanonicalPlan.lean scripts/canonical/solana-parity.sh ProofForge/Backend/Solana/Plan.lean ProofForge/Backend/Solana/SbpfAsm.lean ProofForge/Backend/Solana.lean ProofForge/Compiler/CanonicalPipeline.lean Tests/Canonical/EvidenceIsolation.lean justfile
git commit -m "feat(solana): build existing plan from canonical core"
```

### Task 12: Feed Canonical Core into the Existing NEAR Plan

**Files:**
- Create: `ProofForge/Backend/WasmHost/NearModulePlan/Core.lean`
- Create: `Tests/Backend/Wasm/CanonicalNearPlan.lean`
- Create: `scripts/canonical/near-parity.sh`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan.lean`
- Modify: `ProofForge/Backend/WasmHost/EmitWat.lean`
- Modify: `ProofForge/Backend/WasmHost.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `Tests/Canonical/EvidenceIsolation.lean`
- Modify: `justfile`

**Interfaces:**
- Produces:
  `NearModulePlan.buildFromCore : CheckedCanonicalContract -> CapabilityPlan -> Except PlanError NearModulePlan`.
- Extends the existing plan with target-semantic `NearOpPlan`; it contains no
  `Wasm.Insn` or Legacy declarations.

- [ ] **Step 1: Write failing NEAR plan tests**

Check:

- logical scalar/map/array states receive distinct deterministic key prefixes;
- interface, imports, memory, allocator, and scratch layout match legacy;
- each non-unit function has a planned return;
- `NearLowerCtxSeed` contains target layouts, not Legacy structs/module;
- missing host import, invalid key layout, unsupported Core operation, and
  missing return fail;
- evidence changes do not alter plan or WAT.

- [ ] **Step 2: Extend the existing plan with semantic function bodies**

`NearOpPlan` covers constants, locals, storage host calls, arithmetic,
comparison, branch, event/log, assert/revert, and return. Resolve logical state
to NEAR key pointers and prefixes only in `buildFromCore`. Replace legacy
`StructDecl` and `AllocatorConfig` seed values with explicit target layout
and allocator plan types.

- [ ] **Step 3: Lower only from the complete plan**

Add `lowerFromPlan : NearModulePlan -> Except EmitError Wasm.Module`.
Validate the Wasm AST before printing. An empty body for a non-unit function,
missing host import, unsupported plan op, or stack type mismatch is an error.

- [ ] **Step 4: Add WAT and offline-host parity**

`near-parity.sh` emits both modes for Counter and ValueVault, runs
`wat2wasm` on canonical WAT, and uses the existing offline host to compare
state, return values, logs, and errors.

- [ ] **Step 5: Run the NEAR cutover gate**

```bash
lake env lean --run Tests/Backend/Wasm/CanonicalNearPlan.lean
scripts/canonical/near-parity.sh
just emitwat-ci-smoke
just near-target-first
just wasm-near-host-smoke
just near-offline-host-transaction
git diff --check
```

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Backend/WasmHost/NearModulePlan/Core.lean Tests/Backend/Wasm/CanonicalNearPlan.lean scripts/canonical/near-parity.sh ProofForge/Backend/WasmHost/NearModulePlan.lean ProofForge/Backend/WasmHost/EmitWat.lean ProofForge/Backend/WasmHost.lean ProofForge/Compiler/CanonicalPipeline.lean Tests/Canonical/EvidenceIsolation.lean justfile
git commit -m "feat(near): build existing plan from canonical core"
```

---

## Wave 3B: Close the Existing Advertised Fragment

### Task 12.1: Close Portable Data, Storage, and Control Coverage

**Files:**
- Create: `Tests/Canonical/LegacyCoverage.tsv`
- Create: `Tests/Canonical/LegacyCoverage.lean`
- Create: `Tests/Canonical/ProductMatrix.lean`
- Create: `scripts/canonical/check-coverage.py`
- Modify: `ProofForge/IR/Core/Syntax.lean`
- Modify: `ProofForge/IR/Core/Validate.lean`
- Modify: `ProofForge/IR/Core/Semantics.lean`
- Modify: `ProofForge/IR/Legacy/Classification.lean`
- Modify: `ProofForge/IR/Legacy/Adapter/Expr.lean`
- Modify: `ProofForge/IR/Legacy/Adapter/Statement.lean`
- Modify: `ProofForge/Backend/Evm/Plan/Core.lean`
- Modify: `ProofForge/Backend/Solana/Plan/Core.lean`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan/Core.lean`
- Modify: `Tests/Canonical/Emit.lean`
- Modify: `justfile`

**Interfaces:**
- Extends the accepted canonical fragment to every portable constructor already
  used by the product matrix and the primary-target coverage manifests.
- Produces `canonical-product`, which runs the existing product matrix through
  `CompilerPipeline.canonical` while public routing is still Legacy.

- [ ] **Step 1: Build a failing coverage manifest**

`LegacyCoverage.tsv` has one row per Legacy constructor and these columns:

```text
node_kind	constructor	disposition	core_semantics	evm	solana	near	evidence
```

`check-coverage.py` compares it with
`Tests/Backend/Evm/EvmCoverage.tsv`,
`Tests/Backend/Wasm/EmitWatCoverage.tsv`, the Solana tests included by
`just solana-light`, and the sources included by `just product`. It fails
when an advertised Legacy case has no canonical decision or test evidence.

Run:

```bash
python3 scripts/canonical/check-coverage.py
```

Expected: FAIL with the first currently advertised constructor missing from the
new manifest.

- [ ] **Step 2: Implement the existing portable feature families**

Close these families in Core, validation, semantics, Legacy normalization, and
all applicable existing target plans:

| Family | Required canonical behavior |
|---|---|
| aggregates | struct values/fields, fixed arrays, dynamic arrays, bytes/string |
| persistent state | scalar, map presence/get/set, fixed/dynamic array, struct field, nested storage path |
| memory | allocate, length, read, write, release, ownership errors |
| scalar ops | mod, pow where supported, bitwise, shifts, cast, comparison, boolean |
| control/errors | assertEq, structured revert, branch, bounded loop, supported unbounded-loop requirement |
| events | ordinary and indexed event schemas with ordered arguments |

Any operation not supported by all three targets carries a capability
requirement and preserves the existing target-specific diagnostic. Do not
weaken an existing reject into a placeholder implementation.

- [ ] **Step 3: Run the complete product matrix in canonical shadow mode**

`ProductMatrix.lean` loads the same business sources as `just product`, uses
the same supported target matrix, and invokes
`compileForTest .canonical`. Compare success/rejection class, artifact
metadata, entrypoints, and diagnostics with the current public Legacy route.

```make
canonical-product:
    lake env lean --run Tests/Canonical/ProductMatrix.lean
    lake env lean --run Tests/Canonical/LegacyCoverage.lean
    python3 scripts/canonical/check-coverage.py
```

- [ ] **Step 4: Run and commit**

```bash
just product
just canonical-product
just canonical-core
lake build
git diff --check
git add Tests/Canonical/LegacyCoverage.tsv Tests/Canonical/LegacyCoverage.lean Tests/Canonical/ProductMatrix.lean scripts/canonical/check-coverage.py ProofForge/IR/Core/Syntax.lean ProofForge/IR/Core/Validate.lean ProofForge/IR/Core/Semantics.lean ProofForge/IR/Legacy/Classification.lean ProofForge/IR/Legacy/Adapter/Expr.lean ProofForge/IR/Legacy/Adapter/Statement.lean ProofForge/Backend/Evm/Plan/Core.lean ProofForge/Backend/Solana/Plan/Core.lean ProofForge/Backend/WasmHost/NearModulePlan/Core.lean Tests/Canonical/Emit.lean justfile
git commit -m "feat(core): close portable product fragment coverage"
```

### Task 12.2: Close Context, Crosscall, ABI, and Materialization Coverage

**Files:**
- Create: `Tests/Canonical/MaterializationParity.lean`
- Create: `Tests/Canonical/DiagnosticParity.lean`
- Modify: `Tests/Canonical/LegacyCoverage.tsv`
- Modify: `ProofForge/IR/Core/Syntax.lean`
- Modify: `ProofForge/IR/Core/HostOp.lean`
- Modify: `ProofForge/IR/Core/Validate.lean`
- Modify: `ProofForge/IR/Core/Semantics.lean`
- Modify: `ProofForge/IR/Canonical.lean`
- Modify: `ProofForge/IR/Legacy/Classification.lean`
- Modify: `ProofForge/IR/Legacy/Adapter.lean`
- Modify: `ProofForge/Backend/Evm/Plan/Core.lean`
- Modify: `ProofForge/Backend/Solana/Plan/Core.lean`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan/Core.lean`
- Modify: `ProofForge/Target/HostOpRegistry.lean`
- Modify: `justfile`

**Interfaces:**
- Closes every remaining case used by `just product`, `just evm-all`,
  `just solana-light`, and required NEAR/EmitWat gates.
- Preserves target-specific semantics through typed capabilities or typed
  HostOps, never untyped payloads.

- [ ] **Step 1: Write failing materialization and diagnostic parity tests**

Cover:

- every portable and chain-only context field currently advertised;
- hash/hash-two-to-one and target-gated crypto;
- portable crosscall invoke modes and return values;
- target-specific CREATE/CREATE2, receiver checks, PDA/CPI/syscall, and NEAR
  host forms that are currently required;
- fallback/receive, selector/discriminator, parameter/return ABI, indexed event
  ABI, constructor bindings, allocator, proxy/upgrade policy;
- missing capability, unsupported target, malformed metadata, and wrong ABI
  fail with the same or a stricter diagnostic than Legacy.

- [ ] **Step 2: Normalize portable calls and register target-only operations**

Portable call semantics use `InstructionOp.crosscall` and typed
`CoreCrosscallSpec`. Target-only operations receive exact versioned HostOp
signatures and handlers that return existing target-plan operations. A HostOp
handler is added only when its Legacy behavior is currently advertised and its
positive and negative tests are in this task.

- [ ] **Step 3: Preserve artifact-affecting fields outside evidence**

`MaterializationParity.lean` compares legacy and canonical ABI/artifact JSON
for every product source. Constructor, allocator, selector/discriminator,
event ABI, proxy, upgrade, and target extension data must be equal after
normalization. Changing `CanonicalEvidence` must not change the comparison.

- [ ] **Step 4: Run the full shadow gate**

```bash
just product
just canonical-product
just canonical-core
scripts/canonical/evm-parity.sh
scripts/canonical/solana-parity.sh
scripts/canonical/near-parity.sh
lake env lean --run Tests/Canonical/MaterializationParity.lean
lake env lean --run Tests/Canonical/DiagnosticParity.lean
git diff --check
```

Expected: every required current success remains a success and every current
target rejection remains fail-closed.

- [ ] **Step 5: Commit**

```bash
git add Tests/Canonical/MaterializationParity.lean Tests/Canonical/DiagnosticParity.lean Tests/Canonical/LegacyCoverage.tsv ProofForge/IR/Core/Syntax.lean ProofForge/IR/Core/HostOp.lean ProofForge/IR/Core/Validate.lean ProofForge/IR/Core/Semantics.lean ProofForge/IR/Canonical.lean ProofForge/IR/Legacy/Classification.lean ProofForge/IR/Legacy/Adapter.lean ProofForge/Backend/Evm/Plan/Core.lean ProofForge/Backend/Solana/Plan/Core.lean ProofForge/Backend/WasmHost/NearModulePlan/Core.lean ProofForge/Target/HostOpRegistry.lean justfile
git commit -m "feat(core): close primary target materialization coverage"
```

---

## Wave 4: Add the Independent Surface and Collections

### Task 13: Define and Normalize the Independent Surface AST

**Files:**
- Create: `ProofForge/Frontend/Surface/Type.lean`
- Create: `ProofForge/Frontend/Surface/Syntax.lean`
- Create: `ProofForge/Frontend/Surface/Validate.lean`
- Create: `ProofForge/Frontend/Surface/Normalize.lean`
- Create: `ProofForge/Frontend/Surface/Semantics.lean`
- Create: `ProofForge/Frontend/Surface.lean`
- Create: `ProofForge/Frontend.lean`
- Create: `Tests/Canonical/SurfaceNormalize.lean`
- Create: `Tests/Canonical/SurfaceParity.lean`
- Modify: `ProofForge.lean`

**Interfaces:**
- Produces:
  `normalizeSurface : Frontend.Surface.Contract -> Except SurfaceError CanonicalBundle`.
- Guarantees: Surface imports neither Legacy IR nor any backend/target AST.
- Initial supported Surface fragment matches Counter and ValueVault plus typed
  map/fixed-array primitives needed by collections.

- [ ] **Step 1: Write the failing import and normalization tests**

`SurfaceNormalize.lean` constructs independent Surface versions of Counter
and ValueVault and asserts their checked canonical contracts are equal to the
Legacy adapter outputs after removing source evidence. It also checks:

- duplicate source names fail before ID assignment;
- generated names use the reserved `$surface.` namespace;
- ordinary user names beginning with `$surface.` are rejected;
- effectful expressions normalize left-to-right to explicit instructions;
- bounded loops retain `LoopBound.atMost`;
- invalid source type, missing return, and unknown state fail.

Run:

```bash
lake env lean --run Tests/Canonical/SurfaceNormalize.lean
```

Expected: FAIL because `ProofForge.Frontend.Surface` does not exist.

- [ ] **Step 2: Define a complete independent Surface vocabulary**

Define Surface-owned types for literals, types, expressions, lvalues,
statements, structs, state, events, errors, entrypoints, interface hints,
materialization intents, and source spans. Do not alias `IR.Expr`,
`IR.Effect`, `IR.Statement`, or `IR.Module`.

The first fragment includes:

| Surface category | Constructors |
|---|---|
| expression | literal, local, state read, field/index, unary, arithmetic, comparison, boolean, cast, hash, context read |
| statement | bind, mutable bind, assign, state write, emit, assert, revert, branch, bounded loop, return |
| state | scalar, map, fixed array, dynamic array, record |
| entrypoint | name, kind, mutability, typed params/return, body, source span |

- [ ] **Step 3: Implement deterministic typecheck and normalization**

Assign canonical IDs by declaration order after duplicate-name validation.
Expression normalization uses the same `NormalizedValue` shape as the Legacy
adapter. Surface `InterfaceIntent` and `MaterializationIntent` map to the
checked canonical contract; spans map to evidence.

The normalizer must produce byte-for-byte equal canonical contract hashes for
equivalent Counter/ValueVault Surface and Legacy inputs.

- [ ] **Step 4: Add Surface semantic parity**

`SurfaceParity.lean` executes Surface reference semantics and Core semantics
for Counter initialize/increment/get and ValueVault initialize/deposit/release.
Compare state, returns, events, errors, and ordered effects.

- [ ] **Step 5: Enforce the dependency direction**

Run:

```bash
rg -n "ProofForge\.IR\.Contract|ProofForge\.Backend|ProofForge\.Compiler\.(Yul|Wasm)" ProofForge/Frontend
```

Expected: no matches.

- [ ] **Step 6: Run and commit**

```bash
lake env lean --run Tests/Canonical/SurfaceNormalize.lean
lake env lean --run Tests/Canonical/SurfaceParity.lean
lake build
git diff --check
git add ProofForge/Frontend/Surface/Type.lean ProofForge/Frontend/Surface/Syntax.lean ProofForge/Frontend/Surface/Validate.lean ProofForge/Frontend/Surface/Normalize.lean ProofForge/Frontend/Surface/Semantics.lean ProofForge/Frontend/Surface.lean ProofForge/Frontend.lean Tests/Canonical/SurfaceNormalize.lean Tests/Canonical/SurfaceParity.lean ProofForge.lean
git commit -m "feat(frontend): add independent canonical surface"
```

### Task 14: Teach Contract Loading About Versioned Surface Sources

**Files:**
- Create: `Examples/Product/Canonical/Counter.lean`
- Create: `Examples/Product/Canonical/ValueVault.lean`
- Create: `Tests/Canonical/SourceLoader.lean`
- Modify: `ProofForge/Contract/Source.lean`
- Modify: `ProofForge/Cli/ContractLoader.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `ProofForge/Contract/SdkSchema.lean`
- Modify: `justfile`

**Interfaces:**
- Produces source discovery for either `ContractSpec` v1 or
  `Frontend.Surface.Contract` v2.
- Keeps existing v1 source files and public CLI syntax working.

- [ ] **Step 1: Write loader failures first**

`SourceLoader.lean` requires:

- existing `Examples/Product/Counter.lean` loads as Legacy v1 and canonicalizes;
- the new canonical Counter loads as Surface v2 and canonicalizes;
- a module exporting both source types fails with `ambiguousContractSource`;
- a module exporting neither fails with `missingContractSource`;
- v2 input cannot request the Legacy pipeline;
- v1 and v2 Counter produce equal checked canonical hashes.

- [ ] **Step 2: Add a tagged compiler input**

```lean
inductive LoadedContractSource
  | legacyV1 (spec : ContractSpec)
  | surfaceV2 (contract : Frontend.Surface.Contract)

def LoadedContractSource.toCanonical :
    LoadedContractSource -> Except CompileDiagnostic CanonicalBundle
```

`ContractLoader` discovers exactly one supported constant. It does not
translate Surface back to Legacy. Update SDK schema to report
`contract_source-v1` or `contract_source-v2`.

- [ ] **Step 3: Add authoring fixtures without replacing product baselines**

The two canonical fixtures use the same business behavior and public names as
their product counterparts. They are test inputs under
`Examples/Product/Canonical/`; existing required product files remain the
public baseline until cutover.

- [ ] **Step 4: Run product-first validation and commit**

```bash
just product
lake env lean --run Tests/Canonical/SourceLoader.lean
lake build
git diff --check
git add Examples/Product/Canonical/Counter.lean Examples/Product/Canonical/ValueVault.lean Tests/Canonical/SourceLoader.lean ProofForge/Contract/Source.lean ProofForge/Cli/ContractLoader.lean ProofForge/Compiler/CanonicalPipeline.lean ProofForge/Contract/SdkSchema.lean justfile
git commit -m "feat(frontend): load versioned surface contracts"
```

### Task 15: Normalize Set Without Core or Backend Changes

**Files:**
- Create: `ProofForge/Frontend/Surface/Collections/Set.lean`
- Create: `Examples/Product/Canonical/SetRegistry.lean`
- Create: `Tests/Canonical/SetNormalize.lean`
- Create: `Tests/Canonical/SetParity.lean`
- Modify: `ProofForge/Frontend/Surface/Syntax.lean`
- Modify: `ProofForge/Frontend/Surface/Normalize.lean`
- Modify: `ProofForge/Frontend/Surface.lean`
- Modify: `ProofForge/Contract/Source.lean`
- Modify: `Tests/Canonical/Emit.lean`
- Modify: `justfile`

**Interfaces:**
- Produces Surface `Set<T, capacity>`, `insert`, `remove`, and
  `contains`.
- Normalizes to existing Core map-to-bool plus scalar cardinality.
- Must not modify `ProofForge/IR/Core*` or `ProofForge/Backend/*`.

- [ ] **Step 1: Record the no-Core/backend baseline**

```bash
git rev-parse HEAD > build/canonical/surface-boundary-base
```

- [ ] **Step 2: Write failing Set normalization and semantics tests**

Check:

- declaration creates `$surface.set.<id>.members : map T bool` and
  `$surface.set.<id>.cardinality : scalar u64`;
- capacity zero rejects;
- insert absent key writes true and increments cardinality;
- insert present key changes neither value nor cardinality;
- remove present key writes false and decrements cardinality;
- remove absent key is stable;
- keys remain isolated;
- generated-name collision rejects.

- [ ] **Step 3: Implement Surface-only Set expansion**

Set nodes exist only in Surface. Expansion emits ordinary Core storage loads,
stores, branches, comparisons, assertions, and arithmetic through the existing
normalizer API. It adds no Core or target-plan operation.

- [ ] **Step 4: Run all three target artifacts**

```bash
just product
lake env lean --run Tests/Canonical/SetNormalize.lean
lake env lean --run Tests/Canonical/SetParity.lean
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target evm --fixture set-registry --out build/canonical/set/evm
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target solana-sbpf-asm --fixture set-registry --out build/canonical/set/solana
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target wasm-near --fixture set-registry --out build/canonical/set/near
```

Validate EVM Yul with solc, Solana output with the repository
assembler/verifier, and NEAR WAT with `wat2wasm`.

- [ ] **Step 5: Enforce the boundary and commit**

```bash
base=$(cat build/canonical/surface-boundary-base)
test -z "$(git diff --name-only "$base" -- ProofForge/IR/Core.lean ProofForge/IR/Core ProofForge/Backend)"
git diff --check
git add ProofForge/Frontend/Surface/Collections/Set.lean Examples/Product/Canonical/SetRegistry.lean Tests/Canonical/SetNormalize.lean Tests/Canonical/SetParity.lean ProofForge/Frontend/Surface/Syntax.lean ProofForge/Frontend/Surface/Normalize.lean ProofForge/Frontend/Surface.lean ProofForge/Contract/Source.lean Tests/Canonical/Emit.lean justfile
git commit -m "feat(frontend): normalize bounded sets to canonical storage"
```

### Task 16: Normalize Queue Without Core or Backend Changes

**Files:**
- Create: `ProofForge/Frontend/Surface/Collections/Queue.lean`
- Create: `Examples/Product/Canonical/BoundedQueue.lean`
- Create: `Tests/Canonical/QueueNormalize.lean`
- Create: `Tests/Canonical/QueueParity.lean`
- Modify: `ProofForge/Frontend/Surface/Syntax.lean`
- Modify: `ProofForge/Frontend/Surface/Normalize.lean`
- Modify: `ProofForge/Frontend/Surface.lean`
- Modify: `ProofForge/Contract/Source.lean`
- Modify: `Tests/Canonical/Emit.lean`
- Modify: `justfile`

**Interfaces:**
- Produces bounded FIFO `Queue<T, capacity>`, enqueue, dequeue, peek, length.
- Normalizes to existing fixed-array and scalar Core state shapes.
- Must not modify `ProofForge/IR/Core*` or `ProofForge/Backend/*`.

- [ ] **Step 1: Record the post-Set boundary baseline**

```bash
git rev-parse HEAD > build/canonical/queue-boundary-base
```

- [ ] **Step 2: Write failing layout and FIFO tests**

Check:

- one Queue creates items/head/length with reserved non-colliding IDs;
- capacity zero rejects;
- enqueue on full queue returns the declared structured error;
- dequeue/peek on empty queue return the declared structured error;
- enqueue 1,2 then dequeue returns 1,2;
- head wraps at capacity;
- length never exceeds capacity;
- two queues remain isolated.

- [ ] **Step 3: Implement the exact ring-buffer expansion**

Enqueue:

1. load head and length;
2. assert `length < capacity`;
3. compute `index = (head + length) mod capacity` using explicit wrapping
   arithmetic where overflow is semantically irrelevant after modulo;
4. store the value at items[index];
5. store `length + 1`.

Dequeue:

1. load head and length;
2. assert `length > 0`;
3. load items[head] into the result value;
4. store `(head + 1) mod capacity`;
5. store `length - 1`;
6. return the previously loaded value.

- [ ] **Step 4: Run product, semantic, and tri-target gates**

```bash
just product
lake env lean --run Tests/Canonical/QueueNormalize.lean
lake env lean --run Tests/Canonical/QueueParity.lean
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target evm --fixture bounded-queue --out build/canonical/queue/evm
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target solana-sbpf-asm --fixture bounded-queue --out build/canonical/queue/solana
lake env lean --run Tests/Canonical/Emit.lean -- --pipeline canonical --target wasm-near --fixture bounded-queue --out build/canonical/queue/near
```

Run the same target artifact validators used in Task 15.

- [ ] **Step 5: Enforce the boundary and commit**

```bash
base=$(cat build/canonical/queue-boundary-base)
test -z "$(git diff --name-only "$base" -- ProofForge/IR/Core.lean ProofForge/IR/Core ProofForge/Backend)"
git diff --check
git add ProofForge/Frontend/Surface/Collections/Queue.lean Examples/Product/Canonical/BoundedQueue.lean Tests/Canonical/QueueNormalize.lean Tests/Canonical/QueueParity.lean ProofForge/Frontend/Surface/Syntax.lean ProofForge/Frontend/Surface/Normalize.lean ProofForge/Frontend/Surface.lean ProofForge/Contract/Source.lean Tests/Canonical/Emit.lean justfile
git commit -m "feat(frontend): normalize bounded queues to canonical storage"
```

---

## Wave 5: Prove the HostOp Boundary

### Task 17: Implement `near.promise.create@1.0.0`

**Files:**
- Create: `ProofForge/Frontend/Surface/Host/Near.lean`
- Create: `ProofForge/Backend/WasmHost/NearModulePlan/HostOps.lean`
- Create: `Tests/Canonical/NearPromiseHostOp.lean`
- Create: `Tests/Backend/Wasm/CanonicalNearPromise.lean`
- Create: `scripts/canonical/near-promise-hostop.sh`
- Modify: `ProofForge/IR/Core/HostOp.lean`
- Modify: `ProofForge/IR/Core/Semantics.lean`
- Modify: `ProofForge/Frontend/Surface/Syntax.lean`
- Modify: `ProofForge/Frontend/Surface/Normalize.lean`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan/Core.lean`
- Modify: `ProofForge/Backend/WasmHost/NearModulePlan.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `Tests/Canonical/Emit.lean`
- Modify: `justfile`

**Interfaces:**
- Registers exact ID `near.promise.create@1.0.0`.
- Signature:
  `[string, string, bytes, u128, u64] -> [u64]`.
- Effect class: `external`; capability: `nearPromise`.
- NEAR handler returns `Array NearOpPlan`; EVM and Solana have no handler.

- [ ] **Step 1: Write the failing typed-call tests**

`NearPromiseHostOp.lean` checks the exact catalog signature and rejects:

- missing gas argument;
- `u64` deposit instead of `u128`;
- wrong result type;
- version `1.0.1`;
- call without `nearPromise`;
- call resolved for EVM;
- call resolved for Solana.

`CanonicalNearPromise.lean` initially fails because NEAR has no handler.

- [ ] **Step 2: Add Surface construction and normalization**

`Frontend.Surface.Host.Near.promiseCreate` accepts account ID, method name,
serialized args, deposit, gas, and a result local. Normalization emits one
`hostCall` instruction whose result is `u64`. It does not add a generic
string payload or target AST.

- [ ] **Step 3: Add reference semantics**

The Core host semantics for the test environment appends:

```lean
structure NearPromiseTrace where
  accountId : String
  methodName : String
  args : ByteArray
  deposit : BitVec 128
  gas : UInt64
  promiseIndex : UInt64
```

and returns the next promise index. Unknown versions remain errors.

- [ ] **Step 4: Add the NEAR plan handler**

Register one `HostOpHandler NearOpPlan` under target `wasm-near`. It lowers
to the existing `promise_create` import plan and result capture. The handler
must consume the exact signature and cannot emit `Wasm.Insn`.

- [ ] **Step 5: Run positive and negative target gates**

```bash
lake env lean --run Tests/Canonical/NearPromiseHostOp.lean
lake env lean --run Tests/Backend/Wasm/CanonicalNearPromise.lean
scripts/canonical/near-promise-hostop.sh
just wasm-near-plan
just near-plan-smoke
just wasm-near-ft-transfer-call-e2e
git diff --check
```

The script runs `wat2wasm` and the offline host. The EVM and Solana negative
tests must report `missingHostOpHandler`, not a generic unsupported node.

- [ ] **Step 6: Commit**

```bash
git add ProofForge/Frontend/Surface/Host/Near.lean ProofForge/Backend/WasmHost/NearModulePlan/HostOps.lean Tests/Canonical/NearPromiseHostOp.lean Tests/Backend/Wasm/CanonicalNearPromise.lean scripts/canonical/near-promise-hostop.sh ProofForge/IR/Core/HostOp.lean ProofForge/IR/Core/Semantics.lean ProofForge/Frontend/Surface/Syntax.lean ProofForge/Frontend/Surface/Normalize.lean ProofForge/Backend/WasmHost/NearModulePlan/Core.lean ProofForge/Backend/WasmHost/NearModulePlan.lean ProofForge/Compiler/CanonicalPipeline.lean Tests/Canonical/Emit.lean justfile
git commit -m "feat(near): lower typed promise create host operation"
```

---

## Wave 6: Promote Existing Targets and Remove the Spike

### Task 18: Cut Over `evm` Without Fallback

**Files:**
- Create: `Tests/Canonical/EvmPublicRoute.lean`
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `justfile`

**Interfaces:**
- Public `evm` build/check/emit uses canonical normalization and existing
  `Evm.Plan`.
- Legacy EVM remains callable only from dual-run tests.

- [ ] **Step 1: Write a route test**

Compile product Counter and ValueVault through the public target ID and compare
their artifact hashes with explicit canonical mode. Inject an unsupported Core
operation and assert the public route returns the same canonical diagnostic; it
must not retry the Legacy backend.

- [ ] **Step 2: Switch the route and run product-first gates**

```bash
just product
just canonical-product
lake env lean --run Tests/Canonical/EvmPublicRoute.lean
scripts/canonical/evm-parity.sh
just evm-all
just check
git diff --check
```

- [ ] **Step 3: Commit**

```bash
git add Tests/Canonical/EvmPublicRoute.lean ProofForge/Target/BackendRegistry.lean ProofForge/Cli/TargetDriver.lean ProofForge/Compiler/CanonicalPipeline.lean justfile
git commit -m "feat(evm): promote canonical pipeline on public target"
```

### Task 19: Cut Over `solana-sbpf-asm` Without Fallback

**Files:**
- Create: `Tests/Canonical/SolanaPublicRoute.lean`
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `justfile`

**Interfaces:**
- Public Solana build/check/emit uses canonical normalization and existing
  `SolanaModulePlan`.

- [ ] **Step 1: Write public-route parity and fail-closed tests**

Compare public and explicit canonical artifacts for Counter/ValueVault and
verify an unsupported operation does not invoke Legacy lowering.

- [ ] **Step 2: Switch and run gates**

```bash
just product
just canonical-product
lake env lean --run Tests/Canonical/SolanaPublicRoute.lean
scripts/canonical/solana-parity.sh
just solana-light
just check
git diff --check
```

- [ ] **Step 3: Commit**

```bash
git add Tests/Canonical/SolanaPublicRoute.lean ProofForge/Target/BackendRegistry.lean ProofForge/Cli/TargetDriver.lean ProofForge/Compiler/CanonicalPipeline.lean justfile
git commit -m "feat(solana): promote canonical pipeline on public target"
```

### Task 20: Cut Over `wasm-near` Without Fallback

**Files:**
- Create: `Tests/Canonical/NearPublicRoute.lean`
- Modify: `ProofForge/Target/BackendRegistry.lean`
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `justfile`

**Interfaces:**
- Public NEAR build/check/emit uses canonical normalization and the existing
  `NearModulePlan`.

- [ ] **Step 1: Write public-route parity and fail-closed tests**

Compare public and explicit canonical Counter/ValueVault artifacts, validate
Wasm, and verify unsupported operations do not invoke Legacy EmitWat.

- [ ] **Step 2: Switch and run gates**

```bash
just product
just canonical-product
lake env lean --run Tests/Canonical/NearPublicRoute.lean
scripts/canonical/near-parity.sh
just emitwat-ci-smoke
just near-target-first
just wasm-near-host-smoke
just near-offline-host-transaction
just check
git diff --check
```

- [ ] **Step 3: Commit**

```bash
git add Tests/Canonical/NearPublicRoute.lean ProofForge/Target/BackendRegistry.lean ProofForge/Cli/TargetDriver.lean ProofForge/Compiler/CanonicalPipeline.lean justfile
git commit -m "feat(near): promote canonical pipeline on public target"
```

### Task 21: Delete Parallel Spike Plans and Enforce the Boundary

**Files:**
- Create: `scripts/canonical/check-boundary.sh`
- Create: `Tests/Canonical/Boundary.lean`
- Delete: `ProofForge/Backend/Evm/CorePlan.lean`
- Delete: `ProofForge/Backend/Evm/CoreLower.lean`
- Delete: `ProofForge/Backend/Solana/CorePlan.lean`
- Delete: `ProofForge/Backend/Solana/CoreLower.lean`
- Delete: `ProofForge/Backend/WasmHost/CorePlan.lean`
- Delete: `ProofForge/Backend/WasmHost/CoreLower.lean`
- Delete: `ProofForge/Target/CoreBackend.lean`
- Delete: `ProofForge/Cli/CoreBackend.lean`
- Delete: `Tests/EvmCoreSmoke.lean`
- Delete: `Tests/SolanaCoreSmoke.lean`
- Delete: `Tests/WasmHostCoreSmoke.lean`
- Modify: `ProofForge/Backend/Evm.lean`
- Modify: `ProofForge/Backend/Solana.lean`
- Modify: `ProofForge/Backend/WasmHost.lean`
- Modify: `ProofForge/Target.lean`
- Modify: `ProofForge/Cli.lean`
- Modify: `lakefile.lean`
- Modify: `justfile`

**Interfaces:**
- Produces `canonical-boundary`, a required static architecture gate.
- Removes all duplicate target plan/lower types and structural-only smokes.

- [ ] **Step 1: Write the boundary script and see it fail**

The script fails on any of:

```text
public target id ending in -core
backend importing ProofForge.Frontend.Surface
canonical target builder importing ProofForge.IR.Contract
target plan declaration containing Yul.Statement, AstNode, or Wasm.Insn
legacy constructor change without classification change
remaining EvmCorePlan, SolanaCorePlan, or WasmCorePlan declaration
```

Run `scripts/canonical/check-boundary.sh`; expected failure names the current
parallel spike files.

- [ ] **Step 2: Delete the spike and update exports**

Delete only the files listed above. Preserve the canonical modules and legacy
dual-run baseline functions. Remove the `core-ir-smoke` Lake executable and
all obsolete just recipes.

- [ ] **Step 3: Add the architecture gate to `just check`**

```make
canonical-boundary:
    scripts/canonical/check-boundary.sh
```

Add `canonical-boundary`, `canonical-core`, and `canonical-parity` to the
backend-heavy section after required `product`.

- [ ] **Step 4: Run and commit**

```bash
just product
just canonical-boundary
just canonical-core
just canonical-parity
just canonical-product
lake build
git diff --check
git add scripts/canonical/check-boundary.sh Tests/Canonical/Boundary.lean ProofForge/Backend/Evm/CorePlan.lean ProofForge/Backend/Evm/CoreLower.lean ProofForge/Backend/Solana/CorePlan.lean ProofForge/Backend/Solana/CoreLower.lean ProofForge/Backend/WasmHost/CorePlan.lean ProofForge/Backend/WasmHost/CoreLower.lean ProofForge/Target/CoreBackend.lean ProofForge/Cli/CoreBackend.lean Tests/EvmCoreSmoke.lean Tests/SolanaCoreSmoke.lean Tests/WasmHostCoreSmoke.lean ProofForge/Backend/Evm.lean ProofForge/Backend/Solana.lean ProofForge/Backend/WasmHost.lean ProofForge/Target.lean ProofForge/Cli.lean lakefile.lean justfile
git commit -m "refactor(core): remove parallel target plan spike"
```

### Task 22: Final CI, Documentation, and Rollback Window

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.woodpecker.yml`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/backend-interface.md`
- Modify: `docs/validation-gates.md`
- Modify: `docs/zh/architecture.zh.md`
- Modify: `docs/zh/backend-interface.zh.md`
- Modify: `docs/zh/validation-gates.zh.md`
- Modify: `docs/generated/backend-status.md` only through its generator
- Modify: `docs/INDEX.md`
- Modify: `docs/zh/INDEX.zh.md`
- Modify: `justfile`

**Interfaces:**
- CI runs product first, then canonical semantic/parity/boundary gates, then
  the existing backend-heavy and repository checks.
- Documentation reports only validated public capabilities.
- Legacy dual-run functions remain test-only for one release window.

- [ ] **Step 1: Add CI in product-first order**

GitHub and Woodpecker must execute:

```text
just product
just canonical-core
just canonical-parity
just canonical-product
just canonical-boundary
just check
```

Do not add live Surfpool/Pinocchio to required default CI.

- [ ] **Step 2: Update architecture and validation documentation**

Document:

- Legacy v1 versus Surface v2 input;
- Canonical contract versus non-semantic evidence;
- logical state and target allocation ownership;
- exact HostOp failure rules;
- Queue/Set expansion;
- the three existing public target IDs and their canonical implementation;
- one-release test-only rollback window;
- external tool/runtime gates.

Do not describe the removed `*-core` targets or skeleton output as supported.

- [ ] **Step 3: Regenerate status and run i18n checks**

```bash
python3 scripts/docs/generate-backend-status.py
scripts/i18n/check-sync.sh
just docs-check
git diff --check
```

- [ ] **Step 4: Run the complete final gate**

```bash
just product
just canonical-core
just canonical-parity
just canonical-product
just canonical-boundary
just check
git diff --check
```

Expected: all required local gates pass. Optional live-network gates may report
their documented skip when tools are unavailable.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml .woodpecker.yml README.md docs/architecture.md docs/backend-interface.md docs/validation-gates.md docs/zh/architecture.zh.md docs/zh/backend-interface.zh.md docs/zh/validation-gates.zh.md docs/generated/backend-status.md docs/INDEX.md docs/zh/INDEX.zh.md justfile
git commit -m "ci(core): require canonical parity before backend suites"
```

---

## Per-Target Promotion Checklist

A public target is switched only when every item in its column is true:

| Gate | EVM | Solana | NEAR |
|---|---:|---:|---:|
| Counter plan semantic assertions | required | required | required |
| ValueVault multi-state assertions | required | required | required |
| unsupported Core op fail-closed | required | required | required |
| evidence-independent plan/artifact | required | required | required |
| external syntax/assembler validation | solc | encoder/verifier | wat2wasm |
| runtime state/return/event/error parity | Foundry/Anvil | sBPF executor | offline host |
| existing target aggregate | `just evm-all` | `just solana-light` | EmitWat/NEAR gates |
| public route has no Legacy fallback | required | required | required |

## Plan Self-Review

- **Spec coverage:** Legacy freeze, independent Surface, checked Core,
  logical storage, ANF/CFG, loop bounds, materialization ownership,
  evidence isolation, semantics, preservation, typed HostOps, existing plan
  reuse, complete current product/coverage closure, Queue/Set, per-target
  parity, public-ID stability, rollback, and CI all map to tasks above.
- **Placeholder scan:** the plan contains no deferred implementation marker;
  each task names its files, expected initial failure, implementation contract,
  validation commands, and commit boundary.
- **Type consistency:** `normalizeSurface` and `adaptLegacy` both return
  `CanonicalBundle`; validation produces `CheckedCanonicalContract`; all
  target `buildFromCore` functions consume that checked value plus
  `CapabilityPlan`; HostOp handlers return existing target-plan operations.
- **Boundary consistency:** only target plans allocate physical storage;
  Surface collections cannot modify Core/backends; evidence is excluded from
  capability and plan APIs; no public pipeline target is introduced.
- **Execution safety:** every commit stages explicit paths, product gates run
  first for authoring changes, and optional live Solana tools are not required.

## Execution Handoff

Execute strictly in task order. Wave 0 repairs public truthfulness; Waves 1-2
establish the semantic boundary; Wave 3 must reach all three runtime parity
gates before Wave 4 adds syntax that Legacy cannot express. Promote targets one
at a time and retain the frozen Legacy baseline only for the documented
one-release rollback window.
