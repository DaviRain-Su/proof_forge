# Canonical Core IR and Target-Plan Decoupling

## Status

Accepted architecture; implementation pending.

This document replaces the earlier API-spike design. The spike proved that a
Lean-defined intermediate layer can be wired into the repository, but its
public `*-core` targets, physical storage slots, untyped
`HostOpId := String`, parallel AST-bearing target plans, and structural-only
smokes are not part of this design and are not completion evidence.

The selected scope includes both reviewed boundaries:

1. **Portable syntax decoupling:** new SDK syntax and high-level collections
   normalize into a stable canonical Core without changing each backend.
2. **Typed host operations:** genuinely target-specific semantics use a
   namespaced, versioned, typed, capability-checked extension contract.

The first boundary is implemented before new collection syntax is enabled.
The second boundary is fully specified now and implemented after the Core
foundation, including one real end-to-end host-operation slice.

## Decision Summary

ProofForge will use Lean for typed compiler passes, validation, executable
semantics, and refinement statements. Lean itself is not the decoupling
mechanism. The decoupling comes from one stable semantic boundary and from
reusing the target-semantic plans that already exist.

```text
contract_source / SDK intents
              |
              v
ProofForge.Frontend.Surface
  independent syntax AST, Queue, Set, business operations
              |
              v
normalize + typecheck
              |
              v
CanonicalBundle
  + CheckedCanonicalContract
      - typed ANF/CFG Core.Module
      - logical StateId and StateShape
      - interface and materialization contract
      - capability requirements
  + CanonicalEvidence
      - source map, proof annotations, migration evidence
              |
              v
CapabilityPlan + typed/versioned HostOp catalog
              |
              v
existing Evm.Plan | Solana.Plan | NearModulePlan
              |
              v
Yul AST | sBPF AST | Wasm AST
              |
              v
printer + external toolchain + runtime parity gates
```

During migration, the current `ProofForge.IR.Contract` types are frozen and
treated as **Legacy IR**. Existing `contract_source` programs enter the new
pipeline through a fail-closed Legacy IR adapter. New Surface syntax does not
add constructors to Legacy IR.

## Current-State Clarification

`ProofForge.Contract.Surface` is currently a builder facade over
`ProofForge.IR.Contract`; it is not the independent Surface AST described in
this document. `ProofForge.IR.Contract` is already consumed directly by the
production backends and its `Expr`, `Effect`, and `Statement` types are
closed inductives. Calling either layer extensible would hide the coupling this
design is intended to remove.

The current Core spike is likewise not canonical:

- storage paths contain physical numbers rather than logical state identities;
- effectful reads may appear inside expression trees;
- state shape and metadata can be lost;
- unsupported semantics can become empty target bodies;
- the three new plan types duplicate existing target-plan ownership;
- public target profiles expose incomplete compiler routes.

Implementation starts by making those limitations explicit and fail-closed.

## Problem Classes

The design separates three problems that require different answers:

1. **Syntax diffusion:** Queue, Set, DSL sugar, and authoring conveniences.
   These belong in Surface normalization.
2. **Portable semantic growth:** a genuinely new chain-neutral operation.
   This requires an intentional Core version and all applicable target plans.
3. **Target-specific semantics:** PDA derivation, NEAR promises, EVM CREATE2,
   and similar host behavior. These use typed HostOps and target-owned handlers.

Target layout drift is a fourth concern, already partially addressed by the
existing EVM, Solana, and NEAR plan modules. This design extends those plans
rather than replacing them.

## Goals

1. New syntax sugar and collections change Surface normalization only when
   their meaning is expressible in existing Core primitives.
2. Core preserves state identity, state shape, types, effect order, control
   flow, loop bounds, arithmetic mode, errors, returns, events, and entrypoint
   semantics.
3. Every accepted Legacy IR constructor and field has an explicit policy:
   `preserve`, `normalize`, `materialization`, `evidence`, or `reject`.
4. Target lowering starts from a checked canonical contract and a resolved
   `CapabilityPlan`; unsupported behavior fails before artifact publication.
5. EVM, Solana, and NEAR reuse their existing target plan types instead of
   growing parallel `CorePlan` architectures.
6. Target-specific capabilities use typed and versioned host operations with
   target-owned handlers and semantic hooks.
7. The public CLI continues to advertise only the existing primary target IDs:
   `evm`, `solana-sbpf-asm`, and `wasm-near`.
8. Counter and ValueVault establish the minimum semantic/runtime parity gate;
   public cutover additionally requires the full existing product matrix and
   every currently advertised primary-target fragment.

## Non-Goals

- Reimplement EVM, sBPF, or Wasm as a new universal VM.
- Add Queue, Set, or Map nodes to Yul, sBPF assembly, or Wasm ASTs.
- Guarantee that a genuinely new semantic primitive requires no target work.
- Dynamically load untrusted Lean plugins at runtime.
- Replace external validators, assemblers, or execution tests with proofs.
- Advertise a second family of blockchain target IDs for pipeline variants.
- Migrate the non-primary research targets in this project.
- Prove full target-code refinement for every supported constructor in the
  first delivery.

## Hard Invariants

| Invariant | Required consequence |
|---|---|
| One canonical semantic IR | Backends do not consume Surface nodes or add a second Core AST. |
| Legacy IR is frozen | Queue, Set, and future syntax do not add constructors or fields to `IR.Contract`. |
| Storage is logical in Core | Core paths start at `StateId`; slots, account offsets, and KV keys exist only in target plans. |
| Effects produce explicit results | Storage, context, crosscall, and host reads are ordered instructions with result IDs. |
| Loop intent is preserved | A backedge carries a validated bound or an explicit unbounded-loop requirement. |
| Plans are target-semantic | Existing plan types contain semantic operations, never `Yul.Statement`, `Asm.AstNode`, or `Wasm.Insn`. |
| All stages fail closed | Normalize, validate, capability, plan, lower, render, and artifact validation report unsupported semantics. |
| Host operations are typed | Unknown ID, version, arity, type, capability, effect class, or handler is a compile error. |
| Evidence is non-semantic | Removing `CanonicalEvidence` cannot change capabilities, target code, or observable runtime behavior. |
| Public targets describe platforms | Pipeline variants never appear in `Target.knownIds` or `--list-targets`. |
| Migration preserves the product path | Existing primary routes remain authoritative until canonical parity gates pass. |
| Skeleton output is failure | Empty bodies, placeholder instructions, invalid returns, and unvalidated artifacts cannot satisfy a gate. |

## Layer Ownership

### 1. Independent Surface AST

`contract_source` and SDK helpers remain the public authoring interface. A new
`ProofForge.Frontend.Surface` namespace owns an independent AST for syntax,
source spans, hygienic names, and high-level operations. The new namespace is
deliberately distinct from the historical `ProofForge.Contract.Surface`
builder facade.

Surface does not import Legacy IR, target plans, or target ASTs. It defines its
own types, expressions, lvalues, statements, declarations, and entrypoints.
The following excerpt shows the collection-bearing part of the schema:

```lean
namespace ProofForge.Frontend.Surface

structure SurfaceStateId where
  value : String

inductive StateDecl
  | scalar (id : SurfaceStateId) (type : SurfaceType)
  | map (id : SurfaceStateId) (key value : SurfaceType)
      (capacity : Option Nat)
  | fixedArray (id : SurfaceStateId) (element : SurfaceType)
      (length : Nat)
  | dynamicArray (id : SurfaceStateId) (element : SurfaceType)
  | queue (id : SurfaceStateId) (element : SurfaceType)
      (capacity : Nat)
  | set (id : SurfaceStateId) (element : SurfaceType)
      (capacity : Nat)

inductive Statement
  | bind (local : SurfaceLocalId) (type : SurfaceType) (value : Expr)
  | store (target : LValue) (value : Expr)
  | queueEnqueue (queueId : SurfaceStateId) (value : Expr)
  | queueDequeue (queueId : SurfaceStateId) (result : SurfaceLocalId)
  | setInsert (setId : SurfaceStateId) (value : Expr)
  | setRemove (setId : SurfaceStateId) (value : Expr)
  | branch (condition : Expr)
      (onTrue onFalse : Array Statement)
  | boundedLoop (index : SurfaceLocalId) (bound : Nat)
      (body : Array Statement)
  | return (value : Option Expr)

structure Module where
  name : String
  structs : Array StructDecl := #[]
  state : Array StateDecl := #[]
  entrypoints : Array Entrypoint := #[]
  events : Array EventDecl := #[]

end ProofForge.Frontend.Surface
```

Surface normalization is deterministic for a fixed Surface schema version.
Generated identifiers use one reserved namespace and are collision-checked.

### 2. Source Compatibility During Migration

Existing `contract_source-v1` modules continue to expose
`ProofForge.Contract.ContractSpec` and enter through `adaptLegacy`. When the
collection slice lands, the source elaborator may expose a
`ProofForge.Frontend.Surface.Contract` instead. `ContractLoader` recognizes
both source types and normalizes them to the same `CanonicalBundle`.

The public source syntax and target IDs remain stable. The machine-readable
source DSL version advances when a module begins emitting the independent
Surface type. No Surface-to-Legacy back-translation is allowed. Legacy-only
library consumers continue to work for v1 sources; new Surface features require
the canonical compiler API.

### 3. Frozen Legacy IR Adapter

`ProofForge.IR.Contract` remains supported as a compatibility input, not as an
extensible Surface AST. The adapter consumes the full `ContractSpec`, not only
`spec.module`, so metadata cannot disappear at the boundary:

```lean
def adaptLegacy
    (spec : ProofForge.Contract.ContractSpec) :
    Except CanonicalizeError CanonicalBundle
```

The adapter owns an exhaustive constructor and field inventory checked in CI.
Every case is classified as exactly one of:

- **preserve:** maps one-to-one to Core runtime semantics;
- **normalize:** expands to multiple Core instructions or blocks;
- **materialization:** preserved in the checked interface or materialization
  contract because it affects capabilities or generated artifacts;
- **evidence:** retained only for diagnostics, proofs, or migration tracking;
- **reject:** produces a diagnostic naming the unsupported case and source
  location.

There is no wildcard fallback and no fallback slot, zero value, empty body,
default type, ignored metadata, or unsupported-to-no-op conversion.

## Canonical Core

Core is typed administrative normal form with explicit control flow. It is not
a second source AST.

### Identity and Types

```lean
structure TypeId where value : Nat
structure StateId where value : Nat
structure FunctionId where value : Nat
structure EventId where value : Nat
structure BlockId where value : Nat
structure ValueId where value : Nat

structure ValueDef where
  id : ValueId
  type : CoreType

structure ValueRef where
  id : ValueId
  type : CoreType

inductive OverflowMode
  | wrapping
  | checked

inductive StateShape
  | scalar (value : CoreType)
  | map (key value : CoreType) (capacity : Option Nat)
  | fixedArray (element : CoreType) (length : Nat)
  | dynamicArray (element : CoreType)
  | record (type : TypeId)
```

Canonical references use resolved numeric identities, not user-visible strings.
A symbol table and source map retain display names. `StateId` is logical and
stable; a target plan allocates an EVM slot, Solana account offset, or NEAR
storage prefix only after capability resolution.

### Logical Storage Paths

```lean
inductive StorageSegment
  | mapKey (key : ValueRef)
  | index (index : ValueRef)
  | field (field : FieldId)

structure StorageRef where
  root : StateId
  path : Array StorageSegment := #[]
  resultType : CoreType
```

Core validation walks the declared `StateShape` along every segment. Unknown
roots, wrong key/index types, invalid fields, incompatible result types, and
shape mismatches are errors. No target allocation value is representable here.

### ANF Instructions

```lean
inductive PureOp
  | literal (value : CoreLiteral)
  | unary (op : UnaryOp) (arg : ValueRef)
  | arithmetic (op : ArithmeticOp) (mode : OverflowMode)
      (lhs rhs : ValueRef)
  | compare (op : CompareOp) (lhs rhs : ValueRef)
  | cast (to : CoreType) (arg : ValueRef)
  | hash (arg : ValueRef)

inductive InstructionOp
  | pure (op : PureOp)
  | storageLoad (path : StorageRef)
  | storageContains (path : StorageRef)
  | storageStore (path : StorageRef) (value : ValueRef)
  | storageLength (root : StateId)
  | storageResize (root : StateId) (length : ValueRef)
  | memoryAlloc (type : CoreType) (length : ValueRef)
  | memoryLoad (base index : ValueRef)
  | memoryStore (base index value : ValueRef)
  | memoryRelease (base : ValueRef)
  | contextRead (field : ContextField)
  | emit (event : EventId) (args : Array ValueRef)
  | assert (condition : ValueRef) (error : CoreErrorRef)
  | crosscall (spec : CoreCrosscallSpec) (args : Array ValueRef)
  | hostCall (call : HostOpCall)

structure Instruction where
  results : Array ValueDef
  op : InstructionOp
```

Every value-producing effect binds explicit result IDs. Instruction order is
effect order. Nested expressions cannot contain storage, memory, context,
crosscall, or host effects. Portable crosscall and memory semantics are fixed
Core operations; platform-specific call forms remain typed HostOps.

### CFG and Loop Bounds

```lean
inductive LoopBound
  | atMost (iterations : Nat)
  | requiresUnbounded

inductive Terminator
  | jump (target : BlockId) (args : Array ValueRef)
      (backedgeBound : Option LoopBound := none)
  | branch (condition : ValueRef)
      (onTrue onFalse : BlockId)
  | return (values : Array ValueRef)
  | revert (error : CoreErrorRef)

structure Block where
  id : BlockId
  params : Array ValueDef := #[]
  instructions : Array Instruction
  terminator : Terminator
```

Branches and loops are CFG edges and block parameters carry merged values. Every
block has exactly one terminator. A cycle must have a validated `LoopBound`;
targets without the matching unbounded-loop capability reject
`requiresUnbounded`. There is no implicit fallthrough or missing return.

### Arithmetic and Error Semantics

Checked or wrapping behavior is attached to every arithmetic instruction.
Division by zero, narrowing casts, shifts, assertion failure, structured errors,
and revert observables have one Core definition. A module default may guide
normalization, but it is not the stored semantic truth.

Address, hash, and crosscall operations have normalized result types and error
behavior. A target that cannot implement those semantics must fail capability
or target-plan resolution.

### Module, Materialization, and Evidence

`Core.Module` contains portable runtime semantics: resolved symbols, structs,
logical state, functions, events, and stable context operations. Interface,
deployment, ABI, upgrade, allocator, and capability data can affect generated
artifacts and therefore belong to the checked canonical contract:

```lean
structure CanonicalContract where
  schemaVersion : Nat
  module : Core.Module
  interface : InterfaceContract
  materialization : MaterializationContract
  requirements : Array ProofForge.Target.CapabilityCall

structure CanonicalEvidence where
  sourceMap : SourceMap
  verification : VerificationAnnotations
  legacyClassification : Array LegacyClassificationEvidence

structure CanonicalBundle where
  contract : CheckedCanonicalContract
  evidence : CanonicalEvidence
```

`InterfaceContract` and `MaterializationContract` preserve entrypoint kind
and mutability, dispatch hints, ABI word overrides, constructor bindings,
upgrade/proxy policy, intents, allocator requirements, and other artifact-
affecting data. Every field is consumed by a named target stage or explicitly
rejected for that target.

`CanonicalEvidence` contains only source locations, verification annotations,
and migration evidence. Removing it may reduce diagnostics or proof links, but
cannot change capability resolution, target code, or observable execution.

## Validation

`validateCanonical` produces `CheckedCanonicalContract`. It runs before
capability resolution and after any pass that rewrites Core. It checks:

- unique type, state, function, event, block, and value identities;
- declaration and reference resolution;
- literal bounds before fixed-width conversion;
- operand, result, block argument, and return types;
- dominance and no use before definition;
- storage root and complete path shape;
- entry block, CFG reachability, and cycle bounds;
- terminator completeness and return arity;
- event and error schema agreement;
- arithmetic mode preservation;
- host-operation catalog, version, arity, type, and effect-class agreement;
- interface and materialization references to real canonical identities.

Validation returns a structured semantic diagnostic with pass name, function,
block, instruction index, and reason. The compiler may decorate that diagnostic
with a source location from `CanonicalEvidence.sourceMap`; decoration cannot
change the error tag, success/failure result, capabilities, or target output.

## Core Semantics and Preservation

`ProofForge.IR.Core.Semantics` defines executable small-step semantics over
logical state, value environments, control-flow blocks, events, errors, and host
traces. Target allocation is absent from these semantics.

The first formal migration boundary is:

```lean
def LegacyScalarFragment (spec : ContractSpec) : Prop

theorem adaptLegacy_preserves_scalar_fragment
    (h : LegacyScalarFragment spec) :
    Core.Semantics.observable
      (adaptLegacy spec)
      =
    IR.Semantics.observable spec.module
```

The theorem covers the constructor set exercised by Counter and ValueVault.
Other constructors cannot move from `reject` to `preserve` or `normalize`
without a proof lemma or a documented executable differential certificate.
Counter and ValueVault also run scenario-based differential tests for state,
return values, events, errors, and effect traces.

Surface normalization has the same obligation:

```lean
theorem normalizeSurface_preserves_observables
    (h : SupportedSurfaceFragment surface) :
    Surface.Semantics.observable surface
      =
    Core.Semantics.observable (normalizeSurface surface)
```

The Queue and Set slice extends `SupportedSurfaceFragment` only after its
normalization lemmas and executable scenarios pass.

## Typed Host Operations

Host operations are an extension contract for semantics that are genuinely
platform-specific. They are not an escape hatch for ordinary arithmetic,
storage, branching, collections, or target AST injection.

### Identity and Signature

```lean
structure HostOpVersion where
  major : Nat
  minor : Nat
  patch : Nat

structure HostOpId where
  namespace : String
  name : String
  version : HostOpVersion

inductive HostOpEffectClass
  | pure
  | readOnly
  | stateful
  | external

structure HostOpSig where
  id : HostOpId
  params : Array CoreType
  results : Array CoreType
  effectClass : HostOpEffectClass
  requiredCapabilities : Array ProofForge.Target.Capability

structure HostOpCall where
  id : HostOpId
  args : Array ValueRef
```

Calls use exact semantic versions in the first implementation. There is no
implicit version range. A catalog rejects duplicate IDs and signatures.

### Capability Integration

`CapabilityCall.operation` becomes a tagged operation reference rather than a
second ad hoc string channel:

```lean
inductive CapabilityOperation
  | builtin (name : String)
  | hostOp (id : HostOpId)
```

Canonicalization looks up each call in `HostOpCatalog`, verifies its signature,
and adds its declared capabilities to the existing `CapabilityPlan`. Target
resolution must satisfy both the capability and a concrete host-op handler.

### Target Handlers

Each backend owns a registry parameterized by its existing semantic plan
operation type:

```lean
structure HostOpHandler (PlanOp : Type) where
  signature : HostOpSig
  lower : HostOpCall ->
    Except HostOpLowerError (Array PlanOp)

structure HostOpRegistry (PlanOp : Type) where
  targetId : String
  handlers : Array (HostOpHandler PlanOp)
```

Unknown operations, version mismatches, missing handlers, malformed arguments,
and handler-produced ill-typed plan operations fail closed. Handlers do not
emit final target AST.

### Semantic Hook and First Vertical Slice

Core semantics receives a `HostSemantics` implementation. Unknown operations
are runtime errors in the reference interpreter, never no-ops.

The first real slice is `near.promise.create@1.0.0`:

| Field | Value |
|---|---|
| Parameters | `string accountId`, `string methodName`, `bytes args`, `u128 deposit`, `u64 gas` |
| Results | `u64 promiseIndex` |
| Effect class | `external` |
| Capability | `nearPromise` |
| NEAR handler | Existing `promise_create` semantic plan/import path |
| EVM and Solana | Compile-time `missingHostOpHandler` error |

This proves the extension contract without pretending that all future host
operations are already modeled.

## Target-Plan Integration

The canonical path reuses these existing ownership boundaries:

- `ProofForge.Backend.Evm.Plan.ModulePlan`;
- `ProofForge.Backend.Solana.Plan.SolanaModulePlan`;
- `ProofForge.Backend.WasmHost.NearModulePlan.NearModulePlan`.

Core-specific **builders** may live beside those modules, but they produce the
existing plan types. They do not introduce `EvmCorePlan`,
`SolanaCorePlan`, or `WasmCorePlan` types.

Representative signatures are:

```lean
def Evm.Plan.buildFromCore
    (contract : CheckedCanonicalContract)
    (capabilities : CapabilityPlan) :
    Except Evm.PlanError Evm.Plan.ModulePlan

def Solana.Plan.buildFromCore
    (contract : CheckedCanonicalContract)
    (capabilities : CapabilityPlan) :
    Except Solana.PlanError Solana.Plan.SolanaModulePlan

def NearModulePlan.buildFromCore
    (contract : CheckedCanonicalContract)
    (capabilities : CapabilityPlan) :
    Except NearModulePlan.PlanError NearModulePlan
```

The corresponding lower and render functions also return `Except`. Plan
builders allocate physical storage and ABI layout. Lowerers translate semantic
plan operations to target AST. Printers render validated AST. External tools
validate rendered artifacts.

No shared `TargetPlan Plan Code` record is required in the first cut. The
three backends have meaningfully different plan contracts; forcing them through
a minimal generic record would hide target-specific validation.

## Internal Pipeline Selection

Canonical and legacy routes coexist only as compiler-internal modes:

```lean
inductive CompilerPipeline
  | legacy
  | canonical
```

Dual-run tests call the compiler API with both values. `--list-targets` and
`Target.knownIds` remain unchanged. `just canonical-*` recipes execute tests
or private compiler APIs; they do not register new blockchain targets.

After a target satisfies its cutover gate, its existing public target ID uses
the canonical route by default. The legacy builder remains callable by parity
tests for one release window and is removed after the rollback window.

## Surface Collection Normalization

Queue and Set are enabled only after all three target plans accept checked
Canonical Core and Counter/ValueVault parity passes.

### Queue

`Queue<T, capacity>` normalizes to three logical Core states:

- `$queue.<id>.items : fixedArray T capacity`;
- `$queue.<id>.head : scalar u64`;
- `$queue.<id>.length : scalar u64`.

Enqueue asserts `length < capacity`, writes at
`(head + length) mod capacity`, and increments length. Dequeue asserts
`length > 0`, reads at head, advances head modulo capacity, and decrements
length. Capacity zero is invalid. Generated identities live in a reserved
symbol namespace and collision is a normalization error.

### Set

`Set<T, capacity>` normalizes to one logical
`map T bool (some capacity)` plus a scalar cardinality. Insert changes
cardinality only when the key was absent and rejects capacity overflow. Remove
changes cardinality only when the key was present.

Neither feature adds a Core instruction or target-plan constructor. If a target
cannot materialize the required existing state shapes, capability resolution
rejects that target.

## Failure Model

The compiler pipeline is a chain of explicit errors:

```text
SurfaceError
  -> CanonicalizeError
  -> CoreValidationError
  -> CapabilityResolutionError
  -> HostOpResolutionError
  -> TargetPlanError
  -> TargetLowerError
  -> TargetRenderError
  -> ArtifactValidationError
```

Diagnostics include the pass and semantic node. No stage converts an error to
an empty body, zero selector, slot zero, placeholder instruction, or success
message. `check` reaches at least canonical, capability, plan, and target-AST
validation. `build` also reaches printing and external artifact validation
where the required project tool is available.

## Migration Sequence

### Wave 0: Truthful Experimental Boundary

- remove public `*-core` profiles and CLI routes;
- remove or rewrite fail-open package checks;
- retain the spike only as internal code subject to replacement;
- add exact registry and advertised-command invariant tests.

### Wave 1: Canonical Core Foundation

- introduce logical identities, state shapes, typed ANF/CFG, loop bounds,
  validation, and structured diagnostics;
- introduce checked interface/materialization ownership and non-semantic
  evidence;
- implement Core executable semantics;
- freeze Legacy IR and add the constructor/field classification inventory.

### Wave 2: Legacy Adapter and Semantic Parity

- adapt Counter and ValueVault without lost state, metadata, or effects;
- prove preservation for the shared scalar fragment;
- run executable state/return/event/error differential scenarios.

### Wave 3: Typed Host-Operation Contract

- add versioned IDs, signatures, catalog validation, capability operation
  tagging, target handler registries, and semantic hooks;
- do not enable a host call until one target handler and negative target tests
  exist.

### Wave 4: Existing Target-Plan Migration

- EVM Core builder to existing `Evm.Plan` and Yul path;
- Solana Core builder to existing `Solana.Plan` and sBPF path;
- NEAR Core builder to existing `NearModulePlan` and Wasm path;
- close the full existing product and coverage manifests, including
  aggregates, storage paths, context/hash/control/error behavior, crosscalls,
  ABI, and deployment materialization;
- keep each public route on Legacy until its complete cutover gate passes.

### Wave 5: Independent Surface and Vertical Slices

- add the independent Surface AST and versioned source-loader path;
- add Queue/Set normalization and validate them on all three primary targets;
- land `near.promise.create@1.0.0` with NEAR success and EVM/Solana rejection.

### Wave 6: Cutover and Cleanup

- switch the three existing public target IDs to canonical lowering;
- retain legacy dual-run tests during the rollback window;
- enforce the dependency boundary mechanically;
- remove superseded spike plan types and obsolete routes.

## Verification and Cutover Gates

### Core and Adapter

- constructor and field inventory has no unclassified case;
- invalid literal, unknown state, wrong state shape, use-before-definition,
  type mismatch, unbounded-loop mismatch, missing return, and unknown HostOp
  all fail;
- Counter and ValueVault preserve all state IDs, entrypoint semantics, and
  artifact-affecting metadata;
- Legacy and Core semantics produce identical state, returns, events, errors,
  and ordered effects for the approved scenario corpus;
- the scalar-fragment preservation theorem compiles.
- every constructor used by the existing product matrix and primary-target
  coverage manifests is canonicalized with parity or rejected with the same or
  a stricter public diagnostic.

### EVM

- canonical plan is inspectable and contains no Yul AST;
- rendered Yul passes `solc --strict-assembly`;
- Foundry/Anvil scenarios match the legacy artifact for Counter and ValueVault;
- existing `just evm-all` remains green.

### Solana

- canonical plan is inspectable and contains no `AstNode`;
- assembly passes the repository assembler/encoder/verifier route;
- Counter and ValueVault execution traces match the legacy route;
- existing `just solana-light` remains green;
- Surfpool/Pinocchio remains an optional tool-enabled gate.

### NEAR/Wasm

- canonical plan is inspectable and contains no `Wasm.Insn`;
- rendered WAT passes `wat2wasm`;
- offline host execution matches legacy state, returns, logs, and errors;
- existing EmitWat, target-first, and NEAR offline-host gates remain green.

### Product and Repository

Run in this order:

```bash
just product
just canonical-core
just canonical-parity
just canonical-product
just check
git diff --check
```

`just product` stays first because this changes the product-authoring path.

## Architecture Enforcement

A repository check rejects:

- backend imports of `ProofForge.Frontend.Surface`;
- canonical target builders that import or consume Legacy IR;
- final AST types in target plan declarations;
- public target IDs ending in `-core`;
- canonical compiler passes whose public result type cannot report failure;
- unclassified Legacy IR constructors or fields;
- Queue/Set changes that modify Core or backend files after the stable primitive
  boundary is locked.

The check enters `just check` after its corresponding migration wave can
satisfy it; it is not weakened to accommodate partial backends.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Core becomes another fast-changing Surface AST | ANF/CFG vocabulary is semantic; collections remain Surface expansions; constructor additions require architecture review. |
| Materialization data becomes an untyped metadata bag | Every field has a type, owner, target support rule, and validation test. |
| Evidence accidentally changes code | Evidence is absent from plan-builder signatures and checked by deterministic artifact tests. |
| HostOp becomes a stringly typed escape hatch | Exact version, signature, effect class, capabilities, handler lookup, and semantics are mandatory. |
| Two backend stacks persist indefinitely | Per-target cutover gates and a one-release rollback window; no public duplicate target IDs. |
| Formal work forks from current IR semantics | Legacy adapter preservation and a shared observable relation bridge old and new semantics. |
| External tools disagree with Lean models | External syntax, verifier, and runtime gates remain mandatory. |

## Rejected Alternatives

### Model Each Complete Target ISA in Lean First

Full EVM, sBPF, and Wasm models are valuable for verification, but they do not
stop Surface constructor diffusion and would delay the stable compiler
boundary. Target-semantic plans plus external tools deliver the required
decoupling sooner.

### Keep `IR.Contract` as the Extensible Surface AST

Its closed inductives are already consumed by all backends. Adding constructors
before backend cutover recreates the original problem.

### Reify Canonical Core Back into Legacy IR Permanently

A temporary differential-test adapter may render a supported Core fragment to
Legacy IR, but production target builders cannot depend on it. Permanent
Core-to-Legacy reification would preserve the old constructor bottleneck and
make Legacy IR a second semantic truth.

### Add Parallel Target Plan Types

`EvmCorePlan`, `SolanaCorePlan`, and `WasmCorePlan` duplicate plan,
diagnostic, proof, and test ownership that already exists.

### Use Public `*-core` Target IDs

They describe an internal compiler route, not a blockchain platform, and would
make incomplete behavior part of the product contract.

### Treat Successful Printing as Correctness

Printing proves neither target validity nor runtime equivalence.

## Completion Criteria

This design is complete only when all of the following are true:

1. The frozen Legacy adapter and independent Surface normalizer both produce
   the same validated `CanonicalBundle` boundary.
2. Counter and ValueVault pass Core semantic equivalence and all three target
   runtime parity gates.
3. The complete existing product matrix and primary-target coverage manifests
   pass through canonical lowering without support regression.
4. The existing EVM, Solana, and NEAR plans are the only target plan types used
   by canonical lowering.
5. Queue and Set compile through the three existing public target IDs without
   Core or target-plan constructor additions.
6. `near.promise.create@1.0.0` succeeds on NEAR and fails closed on EVM and
   Solana through the typed host-operation registry.
7. Public registry and CLI target lists remain unchanged.
8. `CanonicalEvidence` cannot affect capability resolution or target output.
9. `just product`, canonical gates, `just check`, and
   `git diff --check` pass.
