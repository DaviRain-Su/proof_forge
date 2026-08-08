/-
  ALEO-IR-2: AleoPlan → Aleo Instructions program (Counter MVP).

  Lowers the single-field public-UInt64 Counter shape that locked Leo 4.0.2
  compiles to `testdata/golden/aleo-instructions-v1/counter.compiled.aleo`:

    * initialize: store param → Final with one-shot `initialized` guard
    * increment: store(checkedAdd(stateLoad, param)) + return stateLoad
      (resultDropped re-load after set)
    * bare views: off-chain only (not emitted into Instructions; match golden)
    * constructor: `assert.eq edition 0u16`

  Profile note (default vs compile):
    * Plan body is profile-insensitive (shared by
      `aleo-leo-4.0.2-u64-v1` and `aleo-leo-4.0.2-u64-compile-v1`).
    * Default source profile: product still emits Leo 4 source + query-contract
      (zero-tool); this lower is the engineering Instructions path for tests
      and the IR authority candidate — **not** product primary yet (IR-6).
    * Compile profile: product Leo source → locked `leo build` produces
      `*.compiled.aleo` extras; Counter Instructions from this lower must be
      structurally ≡ that golden (G1).

  Unsupported Plan shapes fail closed. Leo `EmitIRV1` path remains the
  transitional product printer.
-/
import ProofForgeV2.Targets.Aleo.LowerSemanticV1
import ProofForgeV2.Targets.Aleo.ValidatePlanV1
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.Aleo
open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

/-- Mapping key literal used by EmitIR and Leo 4.0.2 Counter golden. -/
def mappingKeyLiteralV1 : OperandV1 := .literal "0u8"

/-- One-shot init guard mapping (not a DSL state leaf). -/
def guardMappingNameV1 : String := "initialized"

/-- Physical mapping name for state leaf `fieldIndex` (matches EmitIR). -/
def mappingNameV1 (fieldIndex : Nat) : String :=
  s!"pf_state_{fieldIndex}"

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

/-- Leo program id spelling for Instructions header (`counter.aleo`). -/
def programNameFromPlanV1 (plan : Plan) : CompileResult String := do
  let id := asciiLower plan.programName
  unless !id.isEmpty do
    planError "ALEO-IR-2: program name is empty after lowercasing"
  pure s!"{id}.aleo"

private def isPublicUInt64Param (p : PlanParam) : Bool :=
  !p.isBool && !p.isInt && !p.isField &&
    (p.uintWidth == 0 || p.uintWidth == 64)

private def isPublicUInt64Leaf
    (plan : Plan) (fieldIndex : Nat) : Bool :=
  fieldIndex < plan.stateFieldNames.size &&
    !plan.stateFieldIsInt.getD fieldIndex false &&
    !plan.stateFieldIsField.getD fieldIndex false &&
    let w := plan.stateFieldUintWidth.getD fieldIndex 0
    w == 0 || w == 64

/-- Transition wrapper: `input` → `async name args into r` → `output future`.
    Matches Leo 4.0.2 compile of state-touching Final functions. -/
def lowerTransitionFunctionV1
    (programName : String) (fnName : String) (arity : Nat) :
    CompileResult FunctionDeclV1 := do
  unless arity == 1 do
    planError
      "ALEO-IR-2: Counter MVP only supports single public-UInt64 input transitions"
  pure {
    name := fnName
    body := #[
      .input ⟨0⟩ (.base .u64 .public_),
      .asyncCall fnName #[⟨0⟩] ⟨1⟩,
      .output ⟨1⟩ (.future programName fnName)
    ]
  }

/-- initialize finalize: init-guard + store param + mark initialized. -/
def lowerInitializeFinalizeV1 (fieldIndex : Nat) : Array InstructionV1 :=
  let m := mappingNameV1 fieldIndex
  #[
    .input ⟨0⟩ (.base .u64 .public_),
    .getOrUse guardMappingNameV1 mappingKeyLiteralV1 (.literal "false") ⟨1⟩,
    .unary "not" (.register ⟨1⟩) ⟨2⟩,
    .assertEq (.register ⟨2⟩) (.literal "true"),
    .set (.register ⟨0⟩) m mappingKeyLiteralV1,
    .set (.literal "true") guardMappingNameV1 mappingKeyLiteralV1
  ]

/-- increment finalize: get + add + set + re-get (dropped return eval). -/
def lowerCheckedAddStoreReturnFinalizeV1 (fieldIndex : Nat) :
    Array InstructionV1 :=
  let m := mappingNameV1 fieldIndex
  #[
    .input ⟨0⟩ (.base .u64 .public_),
    .getOrUse m mappingKeyLiteralV1 (.literal "0u64") ⟨1⟩,
    .binary "add" (.register ⟨1⟩) (.register ⟨0⟩) ⟨2⟩,
    .set (.register ⟨2⟩) m mappingKeyLiteralV1,
    .getOrUse m mappingKeyLiteralV1 (.literal "0u64") ⟨3⟩
  ]

/-- Edition constructor (Leo 4.0.2 Counter golden). -/
def constructorEditionV1 : ConstructorDeclV1 :=
  { body := #[.assertEq (.identifier "edition") (.literal "0u16")] }

/-- Classify a single PlanFunction into Counter Instructions items
    (function + finalize pair). -/
def lowerFunctionCounterV1
    (programName : String) (plan : Plan) (fn : PlanFunction) :
    CompileResult (FunctionDeclV1 × FinalizeDeclV1) := do
  unless fn.touchesState do
    planError
      s!"ALEO-IR-2: function '{fn.name}' does not touch state (Counter MVP is Final-only)"
  unless !fn.isPureHelper do
    planError
      s!"ALEO-IR-2: pure helper '{fn.name}' is not admitted in Counter MVP"
  unless fn.params.size == 1 && isPublicUInt64Param fn.params[0]! do
    planError
      s!"ALEO-IR-2: function '{fn.name}' must have exactly one public UInt64 param"
  unless fn.resultAggregateLeaves.isNone do
    planError
      s!"ALEO-IR-2: function '{fn.name}' aggregate results are not admitted in Counter MVP"
  let transition ← lowerTransitionFunctionV1 programName fn.name 1
  match fn.kind, fn.body.toList with
  | .initialize, [.store f (.param 0), .returnNone]
  | .initialize, [.store f (.param 0)] => do
      unless isPublicUInt64Leaf plan f do
        planError
          s!"ALEO-IR-2: initialize store field {f} is not a public UInt64 leaf"
      unless !fn.resultDropped do
        planError "ALEO-IR-2: initialize must not set resultDropped"
      pure (transition, {
        name := fn.name
        body := lowerInitializeFinalizeV1 f
      })
  | .mutate,
      [.store f (.checkedAdd (.stateLoad fLoad) (.param 0)),
        .returnValue (.stateLoad fRet)] => do
      unless f == fLoad && f == fRet do
        planError
          s!"ALEO-IR-2: checkedAdd store/return field mismatch on '{fn.name}'"
      unless isPublicUInt64Leaf plan f do
        planError
          s!"ALEO-IR-2: mutate field {f} is not a public UInt64 leaf"
      unless fn.resultDropped do
        planError
          s!"ALEO-IR-2: Counter mutate '{fn.name}' must drop non-Unit result (Final model)"
      pure (transition, {
        name := fn.name
        body := lowerCheckedAddStoreReturnFinalizeV1 f
      })
  | _, _ =>
      planError
        s!"ALEO-IR-2: function '{fn.name}' body is not a Counter template (init store / checkedAdd store+return)"

/-- Lower an entire Plan to Instructions. Counter shape only (IR-2 MVP). -/
def lowerPlanToInstructionsV1 (plan : Plan) : CompileResult ProgramV1 := do
  validatePlan plan
  -- Single public UInt64 state leaf.
  unless plan.stateFieldNames.size == 1 do
    planError
      s!"ALEO-IR-2: expected exactly one state leaf, got {plan.stateFieldNames.size}"
  unless isPublicUInt64Leaf plan 0 do
    planError "ALEO-IR-2: sole state leaf must be public UInt64"
  -- Bare views only (off-chain; never emitted into Instructions text).
  for view in plan.views do
    unless view.stateFieldIndex < plan.stateFieldNames.size do
      planError s!"ALEO-IR-2: view '{view.name}' references missing state"
  unless plan.functions.size ≥ 1 do
    planError "ALEO-IR-2: expected at least one function (initialize)"
  let programName ← programNameFromPlanV1 plan
  -- Mappings: state leaves then init guard (golden order).
  let mut items : Array ItemV1 := #[]
  for i in [0:plan.stateFieldNames.size] do
    items := items.push (.mapping {
      name := mappingNameV1 i
      keyType := .base .u8 .public_
      valueType := .base .u64 .public_
    })
  items := items.push (.mapping {
    name := guardMappingNameV1
    keyType := .base .u8 .public_
    valueType := .base .boolean .public_
  })
  -- Functions: Plan source order; each emits function then finalize.
  let mut sawInitialize := false
  let mut sawMutate := false
  for fn in plan.functions do
    if fn.isPureHelper then
      planError
        s!"ALEO-IR-2: pure helper '{fn.name}' is not admitted in Counter MVP"
    let (fDecl, finDecl) ← lowerFunctionCounterV1 programName plan fn
    match fn.kind with
    | .initialize => sawInitialize := true
    | .mutate => sawMutate := true
    items := items.push (.function fDecl)
    items := items.push (.finalize finDecl)
  unless sawInitialize do
    planError "ALEO-IR-2: Counter MVP requires an initialize function"
  unless sawMutate do
    planError "ALEO-IR-2: Counter MVP requires a mutate (increment) function"
  items := items.push (.constructor constructorEditionV1)
  pure { name := programName, items }

/-- Capability path: materialize Plan then Instructions lower. -/
def programFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult ProgramV1 := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lowerPlanToInstructionsV1 plan

/-- Hand-built / test Plan → Instructions (same as product after validate). -/
def lowerPlanForTestV1 (plan : Plan) : CompileResult ProgramV1 :=
  lowerPlanToInstructionsV1 plan

end ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1
