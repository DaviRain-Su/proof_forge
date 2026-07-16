# RFC 0004: EVM semantic plan and Yul AST boundary

Status: **Accepted**

Date: 2026-07-02

Implemented: 2026-07-04 (CS-6.3 / D-046)

## Summary

The EVM portable IR backend should not lower directly from ProofForge portable
IR into low-level Yul syntax nodes. ProofForge already has a Yul AST in
`ProofForge.Compiler.Yul.AST`, and the portable IR EVM backend renders that AST
through `Yul.Printer`. That AST is valuable, but it is a syntax AST: it models
Yul objects, blocks, statements, expressions, functions, and literals.

The missing layer is a target-semantic EVM plan between portable IR and that
syntax AST.

The product pipeline for the EVM target is:

```text
contract_source / ContractSpec
  -> ProofForge portable IR
  -> EVM semantic plan
  -> Yul AST
  -> reproducible Yul source
  -> solc --strict-assembly
  -> runtime bytecode + ProofForge metadata
```

The legacy `Lean.Compiler.LCNF` → `ProofForge.Compiler.LCNF.EmitYul` route,
`ProofForge.Evm`, and `.evm-methods` sidecars were removed from the product tree
in CS-0.2. They are not available for new work. New EVM examples, CI gates, and
documentation follow the portable-IR → EVM-plan → Yul pipeline above.

This RFC defines the boundary and migration path for that EVM semantic plan.
It keeps the existing Yul AST as the final syntax layer, but stops treating it
as the place where ABI dispatch, storage layout, helper discovery, event ABI,
cross-call ABI, and metadata construction are all interleaved.

## Motivation

The current EVM portable IR backend has grown successfully by adding validated
capability coverage: ABI entrypoints, scalar and aggregate expressions,
storage slots, mappings, arrays, structs, events, cross-contract calls,
artifact metadata, and diagnostics. That progress also exposed a structural
problem. Many distinct concerns now meet inside one lowering module:

- Type checking and unsupported-capability diagnostics.
- EVM storage layout allocation.
- ABI selector dispatch and calldata guards.
- Return-data encoding.
- Event signature and topic/data encoding.
- Helper function discovery and emission.
- Cross-contract call calldata/returndata packing.
- Artifact metadata and deploy-manifest inputs.
- Low-level Yul expression and statement construction.

This makes each new capability harder to add. It also makes review harder:
when a diff changes a storage path, reviewers must inspect Yul construction,
helper emission, diagnostics, metadata, and Foundry coverage at once.

The goal of this RFC is to make the EVM backend more inspectable and durable
without discarding the working Yul AST or the validated smoke suite.

## Current state

The current code already has a real Yul syntax AST:

- `ProofForge.Compiler.Yul.AST`
- `ProofForge.Compiler.Yul.Printer`

The portable IR EVM backend currently exposes:

- `ProofForge.Backend.Evm.IR.lowerModule : Module -> Except LowerError Yul.Object`
- `ProofForge.Backend.Evm.IR.renderModule : Module -> Except LowerError String`

So the backend is not doing raw string concatenation. The issue is that the
semantic EVM lowering and final Yul syntax construction happen in the same
pass. The next architecture step is to make the semantic pass explicit.

## Design goals

- Preserve all existing generated Yul, bytecode, metadata, diagnostics, and
  smoke tests while the migration is staged.
- Make ABI, storage, helpers, events, cross-calls, and metadata first-class
  planned artifacts before final Yul syntax generation.
- Keep the existing `Lean.Compiler.Yul.Object` as the final syntax AST passed
  to `Yul.Printer`.
- Make unsupported capabilities fail during validation or semantic planning,
  not during late syntax rendering.
- Allow future optimizer, audit, and metadata passes to inspect the EVM plan
  without parsing Yul text or reverse-engineering generic Yul statements.
- Keep the design target-specific. This is not a new global IR replacing the
  portable IR.

## Non-goals

- This RFC does not replace `ProofForge.Compiler.Yul.AST`.
- It does not introduce a second portable IR.
- It does not require changing the source-facing contract language.
- It does not require a one-shot rewrite of `ProofForge.Backend.Evm.IR`.
- It does not define Solana, Wasm, Move, or Psy backend plan structures. Those
  targets may choose different target-plan layers.

## Proposed module shape

The EVM backend should be split toward this shape:

```text
ProofForge/Backend/Evm/
  IR.lean                 # compatibility facade during migration
  Plan.lean               # EVM semantic plan data structures
  Validate.lean           # EVM-specific validation and diagnostics
  Lower.lean              # portable IR -> EVM plan
  ToYul.lean              # EVM plan -> Lean.Compiler.Yul.Object
  Metadata.lean           # plan -> artifact/deploy metadata inputs
```

The current `IR.lean` can remain as the public entrypoint while these modules
are introduced. During migration, `IR.lowerModule` should eventually become:

```lean
def lowerModule (module : ProofForge.IR.Module) : Except LowerError Yul.Object := do
  let plan <- Lower.lowerModuleToPlan module
  ToYul.planToObject plan
```

`renderModule` can remain:

```lean
def renderModule (module : ProofForge.IR.Module) : Except LowerError String := do
  let object <- lowerModule module
  pure (Yul.Printer.render object)
```

## EVM plan model

The plan should describe the target contract in EVM terms, not generic Yul
terms. A sketch:

```lean
namespace ProofForge.Backend.Evm.Plan

structure ModulePlan where
  name : String
  storage : StorageLayout
  entrypoints : Array EntrypointPlan
  helpers : HelperSet
  events : Array EventPlan
  crosscalls : Array CrosscallPlan
  capabilities : CapabilitySet
  metadata : MetadataPlan

structure EntrypointPlan where
  name : String
  selector : String
  params : Array AbiParamPlan
  returns : ReturnPlan
  calldataGuards : Array GuardPlan
  body : BlockPlan

structure StorageLayout where
  states : Array StorageStatePlan

inductive StorageSlotPlan where
  | scalarSlot (slot : Nat)
  | structFieldSlot (baseSlot : Nat) (fieldOffset : Nat)
  | arrayElementSlot (baseSlot length : Nat) (index : ValuePlan)
  | structArrayFieldSlot
      (baseSlot length fieldCount fieldOffset : Nat)
      (index : ValuePlan)
  | mapValueSlot (rootSlot : Nat) (keys : Array ValuePlan)
  | mapPresenceSlot (rootSlot : Nat) (keys : Array ValuePlan)

inductive StmtPlan where
  | letValue (name : String) (type : EvmWordType) (value : ValuePlan)
  | assignValue (target : AssignTargetPlan) (value : ValuePlan)
  | storageLoad (target : String) (slot : StorageSlotPlan)
  | storageStore (slot : StorageSlotPlan) (value : ValuePlan)
  | assert (condition : ValuePlan) (message : String)
  | ifElse (condition : ValuePlan) (thenBlock elseBlock : BlockPlan)
  | boundedFor (index : String) (start stop : Nat) (body : BlockPlan)
  | emitEvent (event : EventPlan) (args : Array ValuePlan)
  | returnValue (value : ReturnValuePlan)

end ProofForge.Backend.Evm.Plan
```

This sketch is intentionally semantic. For example, `mapValueSlot` says "this
is an EVM mapping slot path"; it does not say "call
`__proof_forge_map_slot` twice." The `ToYul` pass decides which helper calls or
inline Yul forms produce that slot.

## Planned boundaries

### Validation

Validation should own:

- Type consistency.
- Target-specific supported/unsupported capability checks.
- Explicit diagnostics for unsupported shapes.
- ABI-facing type restrictions.
- Storage path validity.

The validation pass may annotate the module with type information that the
plan-lowering pass consumes. It should not construct final Yul.

### Semantic lowering

The `Lower` pass should own:

- Assigning storage layout.
- Turning portable effects into EVM plan statements.
- Resolving helper requirements.
- Building entrypoint plans with selectors, calldata guards, and return plans.
- Building event and crosscall plans.
- Recording capability ids and metadata inputs.

The output should be inspectable without rendering Yul.

### Yul generation

The `ToYul` pass should own:

- Turning plan statements into `Lean.Compiler.Yul.Statement`.
- Emitting helper functions requested by `HelperSet`.
- Emitting dispatcher `switch`.
- Emitting memory layout for calldata, returndata, events, hashes, and calls.
- Producing the final `Lean.Compiler.Yul.Object`.

It should not make new target-support decisions. If a plan node reaches
`ToYul`, it is assumed to be valid for EVM.

### Metadata

The metadata pass should consume `ModulePlan`, not re-discover facts from
rendered Yul. This matters for:

- `abi.entrypoints`
- `abi.events`
- capability lists
- constructor metadata
- bytecode/Yul hashes
- deploy manifest fields

## Why this is better than direct portable IR to Yul AST

The existing low-level Yul AST is still necessary, but it is too low-level for
backend architecture. A semantic EVM plan gives ProofForge:

- A stable review surface for EVM semantics.
- A place to test storage layout and ABI plans before printing Yul.
- A clean point for artifact metadata generation.
- A clean point for helper discovery.
- A future optimizer surface that can reason about EVM concepts instead of
  raw Yul syntax.
- A clearer path to equivalence checks between the older SDK/LCNF EVM path and
  the portable IR EVM path.

## Migration plan

The migration should be staged and behavior-preserving.

### Stage 1: Introduce plan data structures

Add `ProofForge.Backend.Evm.Plan` with the semantic structures, plus
constructors for the first narrow surface:

- scalar values
- storage scalar read/write
- map value/presence slots
- entrypoint selector metadata
- helper requirements

No generated Yul should change in this stage.

### Stage 2: Move storage layout planning

Move slot assignment and storage-path planning out of `IR.lean` into
`Plan`/`Lower`. The first acceptance target should be map and scalar storage
because they already have strong golden Yul and raw Foundry slot validation.

### Stage 3: Move entrypoint and ABI planning

Represent dispatcher cases, calldata guards, return encoders, and structured
`abi.entrypoints` metadata from the plan. The existing ABI scalar and
aggregate smokes should stay byte-for-byte stable unless a deliberate printer
change is made.

### Stage 4: Move helper discovery

Replace scattered helper accumulation with `HelperSet` in the plan. `ToYul`
should emit helpers deterministically from this set.

### Stage 5: Move events and crosscalls

Represent event signatures, topic/data field layouts, and crosscall ABI
packing as plan nodes before lowering to Yul. These are the most complex
surfaces and should move only after storage and ABI entrypoints prove the
pattern.

### Stage 6: Add plan-level tests

Add tests that inspect `ModulePlan` directly for:

- storage slot formulas
- selected helpers
- entrypoint selector and ABI word counts
- event signatures and topic encodings
- unsupported diagnostics

Golden Yul and Foundry tests remain required. Plan tests are additional
evidence, not replacements.

## Acceptance criteria

A migration slice is accepted only when:

- Existing golden Yul remains reproducible or the diff is intentional and
  reviewed.
- `solc --strict-assembly` still accepts the generated Yul.
- The matching Foundry smoke still validates runtime behavior.
- `proof-forge-artifact.json` metadata still validates.
- Diagnostics remain explicit for unsupported nodes.
- The plan data can be inspected in a focused Lean test or smoke for the
  capability moved in that slice.

## Open questions

- Should plan tests use Lean equality on structures, or render a stable
  `.evm-plan.json` snapshot for review?
- Should `HelperSet` be an inductive set with deterministic ordering, or a
  computed summary from plan traversal?
- Should storage layout be computed before all type validation, or only after
  validation produces a typed module?
- ~~How much of the existing LCNF `EmitYul` path should share the same semantic
  EVM plan, if any?~~ **Resolved (D-046):** the LCNF route is removed; the EVM
  semantic plan is the sole lowering path for product builds.

## Initial implementation recommendation

Start with storage planning, not ABI or events.

The first concrete slice should be:

1. Add `ProofForge.Backend.Evm.Plan`.
2. Model `StorageLayout`, `StorageSlotPlan`, and `HelperSet`.
3. Lower scalar storage and map storage paths into plan nodes.
4. Convert those plan nodes to the existing Yul AST without changing generated
   Yul.
5. Add a focused plan test for nested map value and presence slots.
6. Keep `just evm-smoke map`, `just evm-smoke typed-map`, `just
   evm-diagnostics`, and `just evm-coverage` as the validation gate.

This is the smallest slice that proves the new architecture improves the
backend without destabilizing the already validated EVM surface.
