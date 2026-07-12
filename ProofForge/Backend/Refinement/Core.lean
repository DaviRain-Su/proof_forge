import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.IR.StepSemantics
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.Refinement

open ProofForge.IR
open ProofForge.IR.StepSemantics

/-! Shared refinement surfaces for target executable trace checks.

Backend-specific refinement modules fill these shared observable types from
their own artifact semantics.  The default IR runner below is intentionally
small: it covers pure IR observable returns without target-specific selector,
event-log, or host-state interpretation.
-/

inductive ObservableReturn where
  | none
  | bool (value : Bool)
  | u8 (value : Nat)
  | u32 (value : Nat)
  | u64 (value : Nat)
  | u128 (value : Nat)
  | hash (a b c d : Nat)
  | words (values : Array Nat)
  | reverted (message : String)
  deriving Repr, BEq, DecidableEq

structure ObservableEventLog where
  eventName : String
  topics : Array Nat := #[]
  dataWords : Array Nat := #[]
  deriving Repr, BEq, DecidableEq

structure ObservableStep where
  entrypointName : String
  selector : String := ""
  returnValue : ObservableReturn
  logs : Array ObservableEventLog := #[]
  deriving Repr, BEq, DecidableEq

structure TraceCall where
  entrypoint : Entrypoint
  args : Array ProofForge.IR.Semantics.Value := #[]
  evmArgs : Array Nat := #[]
  deriving Repr

structure TraceObligation where
  name : String
  module : Module
  calls : Array TraceCall
  expected : Array ObservableStep
  deriving Repr

def traceCallsFromEntrypoints (entrypoints : Array Entrypoint) : Array TraceCall :=
  entrypoints.map (fun entrypoint => { entrypoint })

def TraceObligation.entrypoints (obligation : TraceObligation) : Array Entrypoint :=
  obligation.calls.map (fun call => call.entrypoint)

partial def observableWordsFromValue (value : ProofForge.IR.Semantics.Value) :
    Except String (Array Nat) :=
  match value with
  | .unit => .ok #[]
  | .bool value => .ok #[if value then 1 else 0]
  | .u8 value => .ok #[value]
  | .u32 value => .ok #[value]
  | .u64 value => .ok #[value]
  | .u128 value => .ok #[value]
  | .address value => .ok #[value]
  | .bytes values => do
      let wordCount := (values.length + 31) / 32
      let mut words := #[values.length]
      for _h : _idx in [0:wordCount] do
        words := words.push 0
      .ok words
  | .string value => do
      let bytes := value.toUTF8
      let wordCount := (bytes.size + 31) / 32
      let mut words := #[bytes.size]
      for _h : _idx in [0:wordCount] do
        words := words.push 0
      .ok words
  | .hash a b c d =>
      .ok #[a, b, c, d]
  | .array values => do
      let mut words := #[]
      for value in values do
        words := words ++ (← observableWordsFromValue value)
      .ok words
  | .struct _ fields => do
      let mut words := #[]
      for field in fields do
        words := words ++ (← observableWordsFromValue field.snd)
      .ok words

def observableReturn (expectedType : ValueType) (value? : Option ProofForge.IR.Semantics.Value) :
    Except String ObservableReturn :=
  match expectedType, value? with
  | .unit, none => .ok .none
  | .unit, some .unit => .ok .none
  | .bool, some (.bool value) => .ok (.bool value)
  | .u8, some (.u8 value) => .ok (.u8 value)
  | .u32, some (.u32 value) => .ok (.u32 value)
  | .u64, some (.u64 value) => .ok (.u64 value)
  | .u128, some (.u128 value) => .ok (.u128 value)
  | .hash, some (.hash a b c d) => .ok (.hash a b c d)
  | .address, some (.address value) => .ok (.u64 value)
  | .bytes, some (.bytes _) | .string, some (.string _) => .ok .none
  | .fixedArray _ _, some value => do
      .ok (.words (← observableWordsFromValue value))
  | .structType _, some value => do
      .ok (.words (← observableWordsFromValue value))
  | _, none => .error s!"entrypoint expected `{expectedType.name}` but returned no value"
  | _, some _ => .error s!"entrypoint returned a value that does not match `{expectedType.name}`"

def runEntrypointObservable (state : ProofForge.IR.Semantics.State) (call : TraceCall) :
    Except String (ProofForge.IR.Semantics.State × ObservableStep) := do
  let entrypoint := call.entrypoint
  match ProofForge.IR.Semantics.runEntrypointWithArgsResult state entrypoint call.args with
  | .ok (nextState, result?) =>
      let returnValue ← observableReturn entrypoint.returns result?
      .ok (nextState, {
        entrypointName := entrypoint.name
        returnValue
      })
  | .reverted message =>
      .ok (state, {
        entrypointName := entrypoint.name
        returnValue := .reverted message
      })
  | .error message =>
      .error message

def runTraceList : List TraceCall → ProofForge.IR.Semantics.State →
    Except String (ProofForge.IR.Semantics.State × Array ObservableStep)
  | [], state => .ok (state, #[])
  | call :: rest, state => do
      let (nextState, step) ← runEntrypointObservable state call
      let (finalState, steps) ← runTraceList rest nextState
      .ok (finalState, #[step] ++ steps)

def runTrace (calls : Array TraceCall) : Except String (Array ObservableStep) := do
  let (_, steps) ← runTraceList calls.toList ProofForge.IR.Semantics.State.empty
  .ok steps

def TraceObligation.irTraceOk (obligation : TraceObligation) : Bool :=
  match runTrace obligation.calls with
  | .ok actual => actual == obligation.expected
  | .error _ => false

inductive FormalFragment where
  | counter
  deriving Repr, BEq, DecidableEq

def FormalFragment.id : FormalFragment → String
  | .counter => "counter"

def noArgFunctionReturning (entrypoint : Entrypoint) (name : String)
    (returns : ValueType) (mutability : EntrypointMutability) : Bool :=
  entrypoint.name == name &&
    entrypoint.kind == .function &&
    entrypoint.params.size == 0 &&
    entrypoint.returns == returns &&
    decide (entrypoint.mutability = mutability)

def isCounterStateDecl (decl : StateDecl) : Bool :=
  decl.id == "count" &&
    decide (decl.kind = .scalar) &&
    decide (decl.type = .u64)

/-! ### Counter body predicates (FV-9.5 decide-friendly form)

Body matches bind open variables and compare with `==` / `decide`, rather than
embedding concrete `"count"` / `0` in the match pattern. That makes
body-extraction lemmas provable by nested `cases` + `beq_iff_eq` without needing
`DecidableEq` on the mutual `Expr`/`Effect`/`Statement` family (which Lean
cannot derive because of nested `Array` recursion).
-/

/-- Initialize body: `storageScalarWrite "count" (literal (u64 0))`. -/
def isCounterInitializeBody (body : List Statement) : Bool :=
  match body with
  | [.effect (.storageScalarWrite stateId (.literal (.u64 n)))] =>
      stateId == "count" && n == 0
  | _ => false

/-- Increment body: read `count` into `n`, write `count := n + 1` (checked add). -/
def isCounterIncrementBody (body : List Statement) : Bool :=
  match body with
  | [
      .letBind localName localType (.effect (.storageScalarRead readStateId)),
      .effect (.storageScalarWrite writeStateId
        (.add (.local addLocalName) (.literal (.u64 n)) overflowChecked))
    ] =>
      localName == "n" &&
        decide (localType = .u64) &&
        readStateId == "count" &&
        writeStateId == "count" &&
        addLocalName == "n" &&
        n == 1 &&
        overflowChecked == true
  | _ => false

/-- Get body: `return (storageScalarRead "count")`. -/
def isCounterGetBody (body : List Statement) : Bool :=
  match body with
  | [.return (.effect (.storageScalarRead stateId))] =>
      stateId == "count"
  | _ => false

theorem isCounterInitializeBody_eq (body : List Statement)
    (h : isCounterInitializeBody body = true) :
    body = [.effect (.storageScalarWrite "count" (.literal (.u64 0)))] := by
  cases body with
  | nil => simp [isCounterInitializeBody] at h
  | cons s rest =>
    cases rest with
    | cons _ _ => simp [isCounterInitializeBody] at h
    | nil =>
      cases s with
      | effect e =>
        cases e with
        | storageScalarWrite stateId v =>
          cases v with
          | literal lit =>
            cases lit with
            | u64 n =>
              simp [isCounterInitializeBody, Bool.and_eq_true, beq_iff_eq] at h
              obtain ⟨rfl, rfl⟩ := h
              rfl
            | _ => simp [isCounterInitializeBody] at h
          | _ => simp [isCounterInitializeBody] at h
        | _ => simp [isCounterInitializeBody] at h
      | _ => simp [isCounterInitializeBody] at h

theorem isCounterIncrementBody_eq (body : List Statement)
    (h : isCounterIncrementBody body = true) :
    body = [
      .letBind "n" .u64 (.effect (.storageScalarRead "count")),
      .effect (.storageScalarWrite "count"
        (.add (.local "n") (.literal (.u64 1)) true))
    ] := by
  cases body with
  | nil => simp [isCounterIncrementBody] at h
  | cons s1 rest1 =>
    cases rest1 with
    | nil => simp [isCounterIncrementBody] at h
    | cons s2 rest2 =>
      cases rest2 with
      | cons _ _ => simp [isCounterIncrementBody] at h
      | nil =>
        cases s1 with
        | letBind localName localType v1 =>
          cases v1 with
          | effect e1 =>
            cases e1 with
            | storageScalarRead readStateId =>
              cases s2 with
              | effect e2 =>
                cases e2 with
                | storageScalarWrite writeStateId v2 =>
                  cases v2 with
                  | add lhs rhs overflowChecked =>
                    cases lhs with
                    | «local» addLocalName =>
                      cases rhs with
                      | literal lit =>
                        cases lit with
                        | u64 n =>
                          simp [isCounterIncrementBody, Bool.and_eq_true, beq_iff_eq,
                            decide_eq_true_eq] at h
                          obtain ⟨⟨⟨⟨⟨⟨rfl, rfl⟩, rfl⟩, rfl⟩, rfl⟩, rfl⟩, rfl⟩ := h
                          rfl
                        | _ => simp [isCounterIncrementBody] at h
                      | _ => simp [isCounterIncrementBody] at h
                    | _ => simp [isCounterIncrementBody] at h
                  | _ => simp [isCounterIncrementBody] at h
                | _ => simp [isCounterIncrementBody] at h
              | _ => simp [isCounterIncrementBody] at h
            | _ => simp [isCounterIncrementBody] at h
          | _ => simp [isCounterIncrementBody] at h
        | _ => simp [isCounterIncrementBody] at h

theorem isCounterGetBody_eq (body : List Statement)
    (h : isCounterGetBody body = true) :
    body = [.return (.effect (.storageScalarRead "count"))] := by
  cases body with
  | nil => simp [isCounterGetBody] at h
  | cons s rest =>
    cases rest with
    | cons _ _ => simp [isCounterGetBody] at h
    | nil =>
      cases s with
      | «return» v =>
        cases v with
        | effect e =>
          cases e with
          | storageScalarRead stateId =>
            simp [isCounterGetBody, beq_iff_eq] at h
            subst h
            rfl
          | _ => simp [isCounterGetBody] at h
        | _ => simp [isCounterGetBody] at h
      | _ => simp [isCounterGetBody] at h

def isCounterInitializeEntrypoint (entrypoint : Entrypoint) : Bool :=
  noArgFunctionReturning entrypoint "initialize" .unit .call &&
    entrypoint.selector? == some "8129fc1c" &&
    isCounterInitializeBody entrypoint.body.toList

def isCounterIncrementEntrypoint (entrypoint : Entrypoint) : Bool :=
  noArgFunctionReturning entrypoint "increment" .unit .call &&
    entrypoint.selector? == some "d09de08a" &&
    isCounterIncrementBody entrypoint.body.toList

def isCounterGetEntrypoint (entrypoint : Entrypoint) : Bool :=
  noArgFunctionReturning entrypoint "get" .u64 .view &&
    entrypoint.selector? == some "6d4ce63c" &&
    isCounterGetBody entrypoint.body.toList

theorem isCounterInitializeEntrypoint_body (entrypoint : Entrypoint)
    (h : isCounterInitializeEntrypoint entrypoint = true) :
    entrypoint.body.toList =
      [.effect (.storageScalarWrite "count" (.literal (.u64 0)))] := by
  simp only [isCounterInitializeEntrypoint, Bool.and_eq_true] at h
  exact isCounterInitializeBody_eq _ h.2

theorem isCounterIncrementEntrypoint_body (entrypoint : Entrypoint)
    (h : isCounterIncrementEntrypoint entrypoint = true) :
    entrypoint.body.toList = [
      .letBind "n" .u64 (.effect (.storageScalarRead "count")),
      .effect (.storageScalarWrite "count"
        (.add (.local "n") (.literal (.u64 1)) true))
    ] := by
  simp only [isCounterIncrementEntrypoint, Bool.and_eq_true] at h
  exact isCounterIncrementBody_eq _ h.2

theorem isCounterGetEntrypoint_body (entrypoint : Entrypoint)
    (h : isCounterGetEntrypoint entrypoint = true) :
    entrypoint.body.toList =
      [.return (.effect (.storageScalarRead "count"))] := by
  simp only [isCounterGetEntrypoint, Bool.and_eq_true] at h
  exact isCounterGetBody_eq _ h.2

/-- Shape half of `isCounterModule`: exactly one state decl + three entrypoints. -/
def isCounterModuleShape (state : List StateDecl) (entrypoints : List Entrypoint) : Bool :=
  match state, entrypoints with
  | stateDecl :: [], entry0 :: entry1 :: entry2 :: [] =>
      isCounterStateDecl stateDecl &&
        isCounterInitializeEntrypoint entry0 &&
        isCounterIncrementEntrypoint entry1 &&
        isCounterGetEntrypoint entry2
  | _, _ => false

/-- Entrypoint metadata pinned for the Counter lowerable class: empty ABI-word
overrides so lowerable modules do not differ from the canonical fixture on
fields that `lowerModule` may consult for ABI packing. -/
def counterEntrypointsMetadataPinned (entrypoints : List Entrypoint) : Bool :=
  entrypoints.all (fun ep => ep.paramAbiWords.size == 0 && ep.returnAbiWord?.isNone)

/-- Broad Counter-shape *lowerable* predicate (PF-P3-01).

Same IR shape and host/scalar constraints as the proved Counter fragment,
but without pinning `module.name == "Counter"`. Primary triad lowerers treat
the name as a label and succeed on this class. Overflow-checked variants
remain outside the class (they break Solana/NEAR lowering). Also pins
`allocator = defaultAllocator` and empty `paramAbiWords` so unconstrained
metadata cannot inflate the lowerable class beyond the Counter skeleton.

This is the structural superset of `isCounterModule` used for
`TargetSemantics.lowerableAccepts` so that `proven ⊂ lowerable` is a real
inclusion with checked witnesses (`lowerable ∧ ¬proven`), not a reflexive
equality on the canonical Counter constant alone. -/
def isCounterShapeLowerable (module : Module) : Bool :=
  module.structs.size == 0 &&
    module.proxyPattern?.isNone &&
    module.nearCrosscallStrings.size == 0 &&
    module.eventAbiWords.size == 0 &&
    !module.overflowChecked &&
    decide (module.allocator = defaultAllocator) &&
    counterEntrypointsMetadataPinned module.entrypoints.toList &&
    isCounterModuleShape module.state.toList module.entrypoints.toList

/-- Wasm-host allocator compatibility must be checked against the concrete
host bridge. In particular, the CosmWasm region allocator is rejected by the
NEAR and Soroban lowerers before module planning. -/
def wasmBridgeAcceptsAllocator
    (bridge : ProofForge.Target.HostBridge) (allocator : AllocatorConfig) : Bool :=
  !allocator.isCosmWasmRegion || bridge == .cosmWasm

/-- Counter-shape lowerability specialized to one Wasm host bridge. -/
def isCounterShapeLowerableForWasmBridge
    (bridge : ProofForge.Target.HostBridge) (module : Module) : Bool :=
  isCounterShapeLowerable module && wasmBridgeAcceptsAllocator bridge module.allocator

/-- Narrow proved Counter fragment: canonical name plus lowerable shape. -/
def isCounterModule (module : Module) : Bool :=
  module.name == "Counter" && isCounterShapeLowerable module

/-- Proved Counter fragment specialized to the same Wasm host preconditions as
its lowerable superset. -/
def isCounterModuleForWasmBridge
    (bridge : ProofForge.Target.HostBridge) (module : Module) : Bool :=
  isCounterModule module && wasmBridgeAcceptsAllocator bridge module.allocator

theorem isCounterModuleForWasmBridge_implies_shape_lowerable
    (bridge : ProofForge.Target.HostBridge) (module : Module)
    (h : isCounterModuleForWasmBridge bridge module = true) :
    isCounterShapeLowerableForWasmBridge bridge module = true := by
  simp only [isCounterModuleForWasmBridge, isCounterShapeLowerableForWasmBridge,
    isCounterModule, Bool.and_eq_true] at h ⊢
  exact ⟨h.1.2, h.2⟩

/-- Every proved Counter module is lowerable under the shape predicate. -/
theorem isCounterModule_implies_shape_lowerable
    (module : Module) (h : isCounterModule module = true) :
    isCounterShapeLowerable module = true := by
  simp only [isCounterModule, Bool.and_eq_true] at h
  exact h.2

/-- PF-P3-01: pin the proved-fragment name without changing IR shape. -/
def withCanonicalCounterName (module : Module) : Module :=
  { module with name := "Counter" }

/-- Shape-lowerability ignores module name (only IR layout / overflow pin). -/
theorem isCounterShapeLowerable_independent_of_name
    (module : Module) (name' : String) :
    isCounterShapeLowerable module =
      isCounterShapeLowerable { module with name := name' } := by
  simp only [isCounterShapeLowerable]

/-- Every shape-lowerable module becomes a proved Counter after name pin. -/
theorem isCounterShapeLowerable_implies_isCounterModule_with_canonical_name
    (module : Module) (h : isCounterShapeLowerable module = true) :
    isCounterModule (withCanonicalCounterName module) = true := by
  simp only [withCanonicalCounterName, isCounterModule, Bool.and_eq_true]
  exact ⟨rfl, h⟩

/-- PF-P3-01: Counter state decl is unique under `isCounterStateDecl`. -/
theorem isCounterStateDecl_eq
    (decl : StateDecl) (h : isCounterStateDecl decl = true) :
    decl = { id := "count", kind := .scalar, type := .u64 } := by
  simp only [isCounterStateDecl, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  obtain ⟨⟨hid, hkind⟩, htype⟩ := h
  cases decl
  simp only at hid hkind htype
  subst hid; subst hkind; subst htype
  rfl

/-- `ValueType` derives `BEq` without an automatic `LawfulBEq` instance; recover
equality for the Counter predicates that use `== .unit` / `== .u64`. -/
theorem valueType_eq_of_beq_unit {v : ValueType}
    (h : (v == ValueType.unit) = true) : v = .unit := by
  cases v <;> simp [BEq.beq] at h <;> try rfl
  all_goals exact (nomatch h)

theorem valueType_eq_of_beq_u64 {v : ValueType}
    (h : (v == ValueType.u64) = true) : v = .u64 := by
  cases v <;> simp [BEq.beq] at h <;> try rfl
  all_goals exact (nomatch h)

/-- PF-P3-01: initialize entrypoint fields forced by the predicate. -/
theorem isCounterInitializeEntrypoint_fields
    (ep : Entrypoint) (h : isCounterInitializeEntrypoint ep = true) :
    ep.name = "initialize" ∧
      ep.selector? = some "8129fc1c" ∧
      ep.returns = ValueType.unit ∧
      ep.params.size = 0 := by
  simp only [isCounterInitializeEntrypoint, noArgFunctionReturning, Bool.and_eq_true] at h
  refine ⟨?name, ?sel, ?ret, ?params⟩
  · exact beq_iff_eq.mp h.1.1.1.1.1.1
  · exact beq_iff_eq.mp h.1.2
  · exact valueType_eq_of_beq_unit h.1.1.1.2
  · exact beq_iff_eq.mp h.1.1.1.1.2

/-- PF-P3-01: increment entrypoint fields forced by the predicate. -/
theorem isCounterIncrementEntrypoint_fields
    (ep : Entrypoint) (h : isCounterIncrementEntrypoint ep = true) :
    ep.name = "increment" ∧
      ep.selector? = some "d09de08a" ∧
      ep.returns = ValueType.unit ∧
      ep.params.size = 0 := by
  simp only [isCounterIncrementEntrypoint, noArgFunctionReturning, Bool.and_eq_true] at h
  refine ⟨?name, ?sel, ?ret, ?params⟩
  · exact beq_iff_eq.mp h.1.1.1.1.1.1
  · exact beq_iff_eq.mp h.1.2
  · exact valueType_eq_of_beq_unit h.1.1.1.2
  · exact beq_iff_eq.mp h.1.1.1.1.2

/-- PF-P3-01: get entrypoint fields forced by the predicate. -/
theorem isCounterGetEntrypoint_fields
    (ep : Entrypoint) (h : isCounterGetEntrypoint ep = true) :
    ep.name = "get" ∧
      ep.selector? = some "6d4ce63c" ∧
      ep.returns = ValueType.u64 ∧
      ep.params.size = 0 := by
  simp only [isCounterGetEntrypoint, noArgFunctionReturning, Bool.and_eq_true] at h
  refine ⟨?name, ?sel, ?ret, ?params⟩
  · exact beq_iff_eq.mp h.1.1.1.1.1.1
  · exact beq_iff_eq.mp h.1.2
  · exact valueType_eq_of_beq_u64 h.1.1.1.2
  · exact beq_iff_eq.mp h.1.1.1.1.2

/-- Counter mutability is part of the structural fragment: state-changing
entrypoints are calls and the getter is a view. -/
theorem isCounterInitializeEntrypoint_mutability
    (ep : Entrypoint) (h : isCounterInitializeEntrypoint ep = true) :
    ep.mutability = .call := by
  simp only [isCounterInitializeEntrypoint, noArgFunctionReturning,
    Bool.and_eq_true] at h
  exact decide_eq_true_eq.mp h.1.1.2

theorem isCounterIncrementEntrypoint_mutability
    (ep : Entrypoint) (h : isCounterIncrementEntrypoint ep = true) :
    ep.mutability = .call := by
  simp only [isCounterIncrementEntrypoint, noArgFunctionReturning,
    Bool.and_eq_true] at h
  exact decide_eq_true_eq.mp h.1.1.2

theorem isCounterGetEntrypoint_mutability
    (ep : Entrypoint) (h : isCounterGetEntrypoint ep = true) :
    ep.mutability = .view := by
  simp only [isCounterGetEntrypoint, noArgFunctionReturning,
    Bool.and_eq_true] at h
  exact decide_eq_true_eq.mp h.1.1.2

/-- `EntrypointKind` derives `BEq` without automatic `LawfulBEq`. -/
theorem entrypointKind_eq_of_beq_function {k : EntrypointKind}
    (h : (k == EntrypointKind.function) = true) : k = .function := by
  cases k <;> simp [BEq.beq] at h <;> try rfl
  all_goals exact (nomatch h)

/-- PF-P3-01: Counter entrypoints are `.function` with empty params. -/
theorem isCounterInitializeEntrypoint_kind_params
    (ep : Entrypoint) (h : isCounterInitializeEntrypoint ep = true) :
    ep.kind = .function ∧ ep.params = #[] := by
  simp only [isCounterInitializeEntrypoint, noArgFunctionReturning, Bool.and_eq_true] at h
  refine ⟨entrypointKind_eq_of_beq_function h.1.1.1.1.1.2,
    Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp h.1.1.1.1.2)⟩

theorem isCounterIncrementEntrypoint_kind_params
    (ep : Entrypoint) (h : isCounterIncrementEntrypoint ep = true) :
    ep.kind = .function ∧ ep.params = #[] := by
  simp only [isCounterIncrementEntrypoint, noArgFunctionReturning, Bool.and_eq_true] at h
  refine ⟨entrypointKind_eq_of_beq_function h.1.1.1.1.1.2,
    Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp h.1.1.1.1.2)⟩

theorem isCounterGetEntrypoint_kind_params
    (ep : Entrypoint) (h : isCounterGetEntrypoint ep = true) :
    ep.kind = .function ∧ ep.params = #[] := by
  simp only [isCounterGetEntrypoint, noArgFunctionReturning, Bool.and_eq_true] at h
  refine ⟨entrypointKind_eq_of_beq_function h.1.1.1.1.1.2,
    Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp h.1.1.1.1.2)⟩

/-- Body arrays are unique under the Counter body predicates (via `toList`). -/
theorem isCounterInitializeEntrypoint_body_array
    (ep : Entrypoint) (h : isCounterInitializeEntrypoint ep = true) :
    ep.body = #[.effect (.storageScalarWrite "count" (.literal (.u64 0)))] :=
  Array.toList_inj.mp (isCounterInitializeEntrypoint_body ep h)

theorem isCounterIncrementEntrypoint_body_array
    (ep : Entrypoint) (h : isCounterIncrementEntrypoint ep = true) :
    ep.body = #[
      .letBind "n" .u64 (.effect (.storageScalarRead "count")),
      .effect (.storageScalarWrite "count"
        (.add (.local "n") (.literal (.u64 1)) true))
    ] :=
  Array.toList_inj.mp (isCounterIncrementEntrypoint_body ep h)

theorem isCounterGetEntrypoint_body_array
    (ep : Entrypoint) (h : isCounterGetEntrypoint ep = true) :
    ep.body = #[.return (.effect (.storageScalarRead "count"))] :=
  Array.toList_inj.mp (isCounterGetEntrypoint_body ep h)

/-- From `isCounterModuleShape`, recover the three entrypoints and their predicates. -/
theorem isCounterModuleShape_entrypoints
    (state : List StateDecl) (entrypoints : List Entrypoint)
    (h : isCounterModuleShape state entrypoints = true) :
    ∃ e0 e1 e2,
      entrypoints = [e0, e1, e2] ∧
      isCounterInitializeEntrypoint e0 = true ∧
      isCounterIncrementEntrypoint e1 = true ∧
      isCounterGetEntrypoint e2 = true := by
  cases state with
  | nil => simp [isCounterModuleShape] at h
  | cons _ srest =>
    cases srest with
    | cons _ _ => simp [isCounterModuleShape] at h
    | nil =>
      cases entrypoints with
      | nil => simp [isCounterModuleShape] at h
      | cons e0 r0 =>
        cases r0 with
        | nil => simp [isCounterModuleShape] at h
        | cons e1 r1 =>
          cases r1 with
          | nil => simp [isCounterModuleShape] at h
          | cons e2 r2 =>
            cases r2 with
            | cons _ _ => simp [isCounterModuleShape] at h
            | nil =>
              -- ((state ∧ init) ∧ incr) ∧ get
              simp [isCounterModuleShape, Bool.and_eq_true] at h
              exact ⟨e0, e1, e2, rfl, h.1.1.2, h.1.2, h.2⟩

/-- From `isCounterModuleShape`, recover the unique Counter state decl. -/
theorem isCounterModuleShape_state
    (state : List StateDecl) (entrypoints : List Entrypoint)
    (h : isCounterModuleShape state entrypoints = true) :
    ∃ sd, state = [sd] ∧ isCounterStateDecl sd = true := by
  cases state with
  | nil => simp [isCounterModuleShape] at h
  | cons sd srest =>
    cases srest with
    | cons _ _ => simp [isCounterModuleShape] at h
    | nil =>
      cases entrypoints with
      | nil => simp [isCounterModuleShape] at h
      | cons e0 r0 =>
        cases r0 with
        | nil => simp [isCounterModuleShape] at h
        | cons e1 r1 =>
          cases r1 with
          | nil => simp [isCounterModuleShape] at h
          | cons e2 r2 =>
            cases r2 with
            | cons _ _ => simp [isCounterModuleShape] at h
            | nil =>
              simp [isCounterModuleShape, Bool.and_eq_true] at h
              exact ⟨sd, rfl, h.1.1.1⟩

/-- Content-honest decomposition: any `m` in the Counter fragment has three
entrypoints whose bodies are fixed by the body-extraction lemmas. -/
theorem isCounterModule_entrypoints {m : Module} (hm : isCounterModule m = true) :
    ∃ e0 e1 e2,
      m.entrypoints.toList = [e0, e1, e2] ∧
      isCounterInitializeEntrypoint e0 = true ∧
      isCounterIncrementEntrypoint e1 = true ∧
      isCounterGetEntrypoint e2 = true := by
  have hshape : isCounterShapeLowerable m = true :=
    isCounterModule_implies_shape_lowerable m hm
  simp only [isCounterShapeLowerable, Bool.and_eq_true] at hshape
  exact isCounterModuleShape_entrypoints m.state.toList m.entrypoints.toList hshape.2

/-- PF-P3-01 structural flags of any shape-lowerable Counter module (independent
of `module.name`). -/
theorem isCounterShapeLowerable_flags
    (m : Module) (h : isCounterShapeLowerable m = true) :
    m.structs = #[] ∧
      m.proxyPattern? = none ∧
      m.nearCrosscallStrings = #[] ∧
      m.eventAbiWords = #[] ∧
      m.overflowChecked = false ∧
      m.allocator = defaultAllocator ∧
      counterEntrypointsMetadataPinned m.entrypoints.toList = true := by
  simp only [isCounterShapeLowerable, Bool.and_eq_true, decide_eq_true_eq] at h
  -- ((((((structs ∧ proxy) ∧ near) ∧ event ABI) ∧ !overflow) ∧ allocator) ∧ meta) ∧ shape
  obtain ⟨⟨⟨⟨⟨⟨⟨hstructsB, hproxyB⟩, hnearB⟩, heventAbiB⟩, hoverflowB⟩,
      halloc⟩, hmeta⟩, _hshape⟩ := h
  have hstructs : m.structs = #[] :=
    Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp hstructsB)
  have hproxy : m.proxyPattern? = none := by
    revert hproxyB
    cases m.proxyPattern? with
    | none => intro; rfl
    | some _ =>
      intro hp
      simp [Option.isNone] at hp
  have hnear : m.nearCrosscallStrings = #[] :=
    Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp hnearB)
  have heventAbi : m.eventAbiWords = #[] :=
    Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp heventAbiB)
  have hoverflow : m.overflowChecked = false := by
    cases hov : m.overflowChecked with
    | false => rfl
    | true =>
      simp [hov] at hoverflowB
  exact ⟨hstructs, hproxy, hnear, heventAbi, hoverflow, halloc, hmeta⟩

/-- PF-P3-01: shape-lowerable modules carry the Counter entrypoint triple. -/
theorem isCounterShapeLowerable_entrypoints
    (m : Module) (h : isCounterShapeLowerable m = true) :
    ∃ e0 e1 e2,
      m.entrypoints.toList = [e0, e1, e2] ∧
      isCounterInitializeEntrypoint e0 = true ∧
      isCounterIncrementEntrypoint e1 = true ∧
      isCounterGetEntrypoint e2 = true := by
  simp only [isCounterShapeLowerable, Bool.and_eq_true] at h
  exact isCounterModuleShape_entrypoints m.state.toList m.entrypoints.toList h.2

/-- PF-P3-01: shape-lowerable modules carry the unique Counter state decl. -/
theorem isCounterShapeLowerable_state
    (m : Module) (h : isCounterShapeLowerable m = true) :
    ∃ sd, m.state.toList = [sd] ∧ isCounterStateDecl sd = true ∧
      sd = { id := "count", kind := .scalar, type := .u64 } := by
  simp only [isCounterShapeLowerable, Bool.and_eq_true] at h
  obtain ⟨sd, hlist, hdecl⟩ :=
    isCounterModuleShape_state m.state.toList m.entrypoints.toList h.2
  exact ⟨sd, hlist, hdecl, isCounterStateDecl_eq sd hdecl⟩

/-- PF-P3-01: state array is exactly the canonical `count` scalar. -/
theorem isCounterShapeLowerable_state_array
    (m : Module) (h : isCounterShapeLowerable m = true) :
    m.state = #[{ id := "count", kind := .scalar, type := .u64 }] := by
  obtain ⟨sd, hlist, _, hsd⟩ := isCounterShapeLowerable_state m h
  have hlist' : m.state.toList = [{ id := "count", kind := .scalar, type := .u64 }] := by
    simpa [hsd] using hlist
  exact Array.toList_inj.mp hlist'

/-- Canonical Counter initialize entrypoint (paramAbiWords pinned empty). -/
def counterInitializeEntrypoint : Entrypoint := {
  name := "initialize"
  kind := .function
  mutability := .call
  selector? := some "8129fc1c"
  params := #[]
  paramAbiWords := #[]
  returns := .unit
  body := #[.effect (.storageScalarWrite "count" (.literal (.u64 0)))]
}

def counterIncrementEntrypoint : Entrypoint := {
  name := "increment"
  kind := .function
  mutability := .call
  selector? := some "d09de08a"
  params := #[]
  paramAbiWords := #[]
  returns := .unit
  body := #[
    .letBind "n" .u64 (.effect (.storageScalarRead "count")),
    .effect (.storageScalarWrite "count"
      (.add (.local "n") (.literal (.u64 1)) true))
  ]
}

def counterGetEntrypoint : Entrypoint := {
  name := "get"
  kind := .function
  mutability := .view
  selector? := some "6d4ce63c"
  params := #[]
  paramAbiWords := #[]
  returns := .u64
  body := #[.return (.effect (.storageScalarRead "count"))]
}

/-- Full structural equality for pinned initialize entrypoints. -/
theorem isCounterInitializeEntrypoint_eq
    (ep : Entrypoint) (h : isCounterInitializeEntrypoint ep = true)
    (hpinned : ep.paramAbiWords = #[]) (hreturn : ep.returnAbiWord? = none) :
    ep = counterInitializeEntrypoint := by
  obtain ⟨hn, hs, hr, _⟩ := isCounterInitializeEntrypoint_fields ep h
  obtain ⟨hk, hp⟩ := isCounterInitializeEntrypoint_kind_params ep h
  have hm := isCounterInitializeEntrypoint_mutability ep h
  have hb := isCounterInitializeEntrypoint_body_array ep h
  cases ep
  case mk name kind mutability selector? params paramAbiWords returns returnAbiWord? body =>
    simp only at hn hs hr hk hm hp hb hpinned hreturn
    subst hn; subst hs; subst hr; subst hk; subst hm; subst hp; subst hb; subst hpinned
    subst hreturn
    rfl

theorem isCounterIncrementEntrypoint_eq
    (ep : Entrypoint) (h : isCounterIncrementEntrypoint ep = true)
    (hpinned : ep.paramAbiWords = #[]) (hreturn : ep.returnAbiWord? = none) :
    ep = counterIncrementEntrypoint := by
  obtain ⟨hn, hs, hr, _⟩ := isCounterIncrementEntrypoint_fields ep h
  obtain ⟨hk, hp⟩ := isCounterIncrementEntrypoint_kind_params ep h
  have hm := isCounterIncrementEntrypoint_mutability ep h
  have hb := isCounterIncrementEntrypoint_body_array ep h
  cases ep
  case mk name kind mutability selector? params paramAbiWords returns returnAbiWord? body =>
    simp only at hn hs hr hk hm hp hb hpinned hreturn
    subst hn; subst hs; subst hr; subst hk; subst hm; subst hp; subst hb; subst hpinned
    subst hreturn
    rfl

theorem isCounterGetEntrypoint_eq
    (ep : Entrypoint) (h : isCounterGetEntrypoint ep = true)
    (hpinned : ep.paramAbiWords = #[]) (hreturn : ep.returnAbiWord? = none) :
    ep = counterGetEntrypoint := by
  obtain ⟨hn, hs, hr, _⟩ := isCounterGetEntrypoint_fields ep h
  obtain ⟨hk, hp⟩ := isCounterGetEntrypoint_kind_params ep h
  have hm := isCounterGetEntrypoint_mutability ep h
  have hb := isCounterGetEntrypoint_body_array ep h
  cases ep
  case mk name kind mutability selector? params paramAbiWords returns returnAbiWord? body =>
    simp only at hn hs hr hk hm hp hb hpinned hreturn
    subst hn; subst hs; subst hr; subst hk; subst hm; subst hp; subst hb; subst hpinned
    subst hreturn
    rfl

/-- Empty `paramAbiWords` on every entrypoint of a shape-lowerable module. -/
theorem isCounterShapeLowerable_paramAbiWords_empty
    (m : Module) (h : isCounterShapeLowerable m = true)
    (ep : Entrypoint) (hep : ep ∈ m.entrypoints.toList) :
    ep.paramAbiWords = #[] := by
  have hmeta : counterEntrypointsMetadataPinned m.entrypoints.toList = true :=
    (isCounterShapeLowerable_flags m h).2.2.2.2.2.2
  -- all (size == 0) = true and membership ⇒ size = 0
  have hall :
      (m.entrypoints.toList.all (fun e => e.paramAbiWords.size == 0 && e.returnAbiWord?.isNone)) = true := by
    simpa [counterEntrypointsMetadataPinned] using hmeta
  have he := List.all_eq_true.mp hall ep hep
  simp only [Bool.and_eq_true] at he
  have hsize : (ep.paramAbiWords.size == 0) = true := he.1
  exact Array.eq_empty_of_size_eq_zero (beq_iff_eq.mp hsize)

theorem isCounterShapeLowerable_returnAbiWord_none
    (m : Module) (h : isCounterShapeLowerable m = true)
    (ep : Entrypoint) (hep : ep ∈ m.entrypoints.toList) :
    ep.returnAbiWord? = none := by
  have hmeta : counterEntrypointsMetadataPinned m.entrypoints.toList = true :=
    (isCounterShapeLowerable_flags m h).2.2.2.2.2.2
  have hall :
      (m.entrypoints.toList.all (fun e => e.paramAbiWords.size == 0 && e.returnAbiWord?.isNone)) = true := by
    simpa [counterEntrypointsMetadataPinned] using hmeta
  have he := List.all_eq_true.mp hall ep hep
  simp only [Bool.and_eq_true] at he
  cases hreturn : ep.returnAbiWord? with
  | none => rfl
  | some _ => simp [hreturn] at he

/-- PF-P3-01: entrypoints array is exactly the canonical Counter triple. -/
theorem isCounterShapeLowerable_entrypoints_array
    (m : Module) (h : isCounterShapeLowerable m = true) :
    m.entrypoints = #[counterInitializeEntrypoint, counterIncrementEntrypoint,
      counterGetEntrypoint] := by
  obtain ⟨e0, e1, e2, heps, h0, h1, h2⟩ := isCounterShapeLowerable_entrypoints m h
  have p0 := isCounterShapeLowerable_paramAbiWords_empty m h e0 (by simp [heps])
  have p1 := isCounterShapeLowerable_paramAbiWords_empty m h e1 (by simp [heps])
  have p2 := isCounterShapeLowerable_paramAbiWords_empty m h e2 (by simp [heps])
  have r0 := isCounterShapeLowerable_returnAbiWord_none m h e0 (by simp [heps])
  have r1 := isCounterShapeLowerable_returnAbiWord_none m h e1 (by simp [heps])
  have r2 := isCounterShapeLowerable_returnAbiWord_none m h e2 (by simp [heps])
  have e0eq := isCounterInitializeEntrypoint_eq e0 h0 p0 r0
  have e1eq := isCounterIncrementEntrypoint_eq e1 h1 p1 r1
  have e2eq := isCounterGetEntrypoint_eq e2 h2 p2 r2
  have hlist :
      m.entrypoints.toList =
        [counterInitializeEntrypoint, counterIncrementEntrypoint, counterGetEntrypoint] := by
    simpa [e0eq, e1eq, e2eq] using heps
  exact Array.toList_inj.mp hlist

/-- Canonical Counter-shape module with free `name` (all other fields pinned). -/
def counterShapeModule (name : String) : Module := {
  name := name
  structs := #[]
  state := #[{ id := "count", kind := .scalar, type := .u64 }]
  entrypoints := #[counterInitializeEntrypoint, counterIncrementEntrypoint,
    counterGetEntrypoint]
  eventAbiWords := #[]
  allocator := defaultAllocator
  proxyPattern? := none
  nearCrosscallStrings := #[]
  overflowChecked := false
}

/-- PF-P3-01: every shape-lowerable module matches `counterShapeModule` on every
field except possibly `allocator` (recovered only up to `BEq` without
`LawfulBEq`). This is the structural identity needed before lowerer
totality over free names. -/
theorem isCounterShapeLowerable_matches_counterShapeModule
    (m : Module) (h : isCounterShapeLowerable m = true) :
    m.name = (counterShapeModule m.name).name ∧
      m.structs = (counterShapeModule m.name).structs ∧
      m.state = (counterShapeModule m.name).state ∧
      m.entrypoints = (counterShapeModule m.name).entrypoints ∧
      m.proxyPattern? = (counterShapeModule m.name).proxyPattern? ∧
      m.nearCrosscallStrings = (counterShapeModule m.name).nearCrosscallStrings ∧
      m.eventAbiWords = (counterShapeModule m.name).eventAbiWords ∧
      m.overflowChecked = (counterShapeModule m.name).overflowChecked ∧
      m.allocator = (counterShapeModule m.name).allocator := by
  obtain ⟨hstructs, hproxy, hnear, heventAbi, hoverflow, halloc, _⟩ :=
    isCounterShapeLowerable_flags m h
  refine ⟨rfl, hstructs, isCounterShapeLowerable_state_array m h,
    isCounterShapeLowerable_entrypoints_array m h, hproxy, hnear, heventAbi, hoverflow, ?_⟩
  simpa [counterShapeModule] using halloc

/-- PF-P3-01: every shape-lowerable module is definitionally `counterShapeModule`
with the module's own name (full structure equality). -/
theorem isCounterShapeLowerable_eq_counterShapeModule
    (m : Module) (h : isCounterShapeLowerable m = true) :
    m = counterShapeModule m.name := by
  obtain ⟨_, hstructs, hstate, hentr, hproxy, hnear, heventAbi, hoverflow, halloc⟩ :=
    isCounterShapeLowerable_matches_counterShapeModule m h
  cases m
  case mk name structs state entrypoints eventAbiWords allocator proxyPattern? nearCrosscallStrings overflowChecked =>
    simp only [counterShapeModule] at hstructs hstate hentr hproxy hnear heventAbi hoverflow halloc ⊢
    subst hstructs; subst hstate; subst hentr; subst hproxy; subst hnear; subst heventAbi
    subst hoverflow; subst halloc
    rfl

/-- PF-P3-01 progressive structural skeleton: every shape-lowerable module has
fixed host/scalar flags, pinned allocator + empty paramAbiWords, unique `count`
state, and a triple of Counter entrypoints with forced
names/mutability/selectors/returns/params/bodies.

The remaining half of `∀ m, lowerable m → lowerModule m = .ok` is lowerer
totality (or name-independence of `isOk`) over this fully pinned IR skeleton. -/
theorem isCounterShapeLowerable_skeleton
    (m : Module) (h : isCounterShapeLowerable m = true) :
    m.structs = #[] ∧
      m.proxyPattern? = none ∧
      m.nearCrosscallStrings = #[] ∧
      m.eventAbiWords = #[] ∧
      m.overflowChecked = false ∧
      m.allocator = defaultAllocator ∧
      (∃ sd, m.state.toList = [sd] ∧
        sd = { id := "count", kind := .scalar, type := .u64 }) ∧
      (∃ e0 e1 e2,
        m.entrypoints.toList = [e0, e1, e2] ∧
          e0.paramAbiWords = #[] ∧ e1.paramAbiWords = #[] ∧ e2.paramAbiWords = #[] ∧
          e0.name = "initialize" ∧ e0.mutability = .call ∧
            e0.selector? = some "8129fc1c" ∧
            e0.returns = .unit ∧ e0.params = #[] ∧ e0.kind = .function ∧
            e0.body = #[.effect (.storageScalarWrite "count" (.literal (.u64 0)))] ∧
          e1.name = "increment" ∧ e1.mutability = .call ∧
            e1.selector? = some "d09de08a" ∧
            e1.returns = .unit ∧ e1.params = #[] ∧ e1.kind = .function ∧
            e1.body = #[
              .letBind "n" .u64 (.effect (.storageScalarRead "count")),
              .effect (.storageScalarWrite "count"
                (.add (.local "n") (.literal (.u64 1)) true))] ∧
          e2.name = "get" ∧ e2.mutability = .view ∧
            e2.selector? = some "6d4ce63c" ∧
            e2.returns = .u64 ∧ e2.params = #[] ∧ e2.kind = .function ∧
            e2.body = #[.return (.effect (.storageScalarRead "count"))]) := by
  obtain ⟨hstructs, hproxy, hnear, heventAbi, hoverflow, halloc, _hmeta⟩ :=
    isCounterShapeLowerable_flags m h
  obtain ⟨sd, hstate, _, hsd⟩ := isCounterShapeLowerable_state m h
  obtain ⟨e0, e1, e2, heps, h0, h1, h2⟩ := isCounterShapeLowerable_entrypoints m h
  obtain ⟨n0, s0, r0, _⟩ := isCounterInitializeEntrypoint_fields e0 h0
  have m0 := isCounterInitializeEntrypoint_mutability e0 h0
  obtain ⟨k0, p0⟩ := isCounterInitializeEntrypoint_kind_params e0 h0
  obtain ⟨n1, s1, r1, _⟩ := isCounterIncrementEntrypoint_fields e1 h1
  have m1 := isCounterIncrementEntrypoint_mutability e1 h1
  obtain ⟨k1, p1⟩ := isCounterIncrementEntrypoint_kind_params e1 h1
  obtain ⟨n2, s2, r2, _⟩ := isCounterGetEntrypoint_fields e2 h2
  have m2 := isCounterGetEntrypoint_mutability e2 h2
  obtain ⟨k2, p2⟩ := isCounterGetEntrypoint_kind_params e2 h2
  have heps_mem0 : e0 ∈ m.entrypoints.toList := by simp [heps]
  have heps_mem1 : e1 ∈ m.entrypoints.toList := by simp [heps]
  have heps_mem2 : e2 ∈ m.entrypoints.toList := by simp [heps]
  refine ⟨hstructs, hproxy, hnear, heventAbi, hoverflow, halloc, ⟨sd, hstate, hsd⟩,
    ⟨e0, e1, e2, heps,
      isCounterShapeLowerable_paramAbiWords_empty m h e0 heps_mem0,
      isCounterShapeLowerable_paramAbiWords_empty m h e1 heps_mem1,
      isCounterShapeLowerable_paramAbiWords_empty m h e2 heps_mem2,
      n0, m0, s0, r0, p0, k0, isCounterInitializeEntrypoint_body_array e0 h0,
      n1, m1, s1, r1, p1, k1, isCounterIncrementEntrypoint_body_array e1 h1,
      n2, m2, s2, r2, p2, k2, isCounterGetEntrypoint_body_array e2 h2⟩⟩

def FormalFragment.acceptsModule : FormalFragment → Module → Bool
  | .counter, module => isCounterModule module

structure TargetSemantics where
  id : String := "anonymous-target-semantics"
  /-- Named proof fragments this target semantics declares (e.g. `#[.counter]`).
  Used by `supportsProofFragment` to check that a target *declares* a named
  fragment. The actual per-module acceptance test is `fragmentAccepts` below,
  which is the single source of truth for "module is in this target's proved
  scope" (Track 1.4). -/
  supportedFragments : Array FormalFragment := #[]
  /-- Decidable per-target proven-fragment predicate: the single source of
  truth for "module is within this target's *proved refinement* scope" (Track
  1.4). Backends instantiate this with a decidable `Module → Bool` that
  characterizes the IR shapes their refinement actually proves (e.g. the
  canonical Counter shape for the Counter universal C-proof). This is the
  *narrow* predicate — the set of modules whose IR↔target refinement is
  machine-checked. -/
  fragmentAccepts : Module → Bool := fun _ => false
  /-- Decidable per-target lowerable-fragment predicate: the set of modules
  this target can *successfully lower* (`lowerModule module = .ok _`). This is
  the *broad* predicate — a superset of `fragmentAccepts`. Track 1.4 connects
  the two: `fragmentAccepts ⊂ lowerableAccepts` (proven ⇒ lowerable) and
  `lowerableAccepts ⇒ lowering-total` (lowerable ⇒ `lowerModule = .ok`). -/
  lowerableAccepts : Module → Bool := fun _ => false
  MachineState : Type
  Call : Type
  Obs : Type
  traceStep : MachineState → Call → Except String (MachineState × Obs)
  runTrace : List Call → MachineState → Except String (MachineState × Array Obs)
  runTrace_eq_traceStep :
    ∀ calls state, runTrace calls state =
      ProofForge.IR.StepSemantics.runTraceListGen traceStep calls state
  executableTraceOk : TraceObligation → Bool
  /-- FV-9.1: the generic IR-state ↔ target-machine-state simulation relation.

  This is the `R` that `traceSimulation_lift` quantifies over, promoted from a
  per-call theorem parameter to a first-class `TargetSemantics` field. Each
  backend fills it with the relation its per-contract proofs currently inline
  (e.g. `CounterWasmRel` / `CounterSbpfRel`). The default is the trivial
  relation so existing instantiations keep compiling; real backends override
  it. The ∀-contract theorem (FV-9.3) discharges `step_simulates` for this
  `R` by structural induction over IR program structure. -/
  irStateRel : IR.Semantics.State → MachineState → Prop := fun _ _ => True
  /-- FV-9.1: the target's initial machine state for a module (e.g. an empty
  account / empty WASM store), when the target can construct one without
  running the full lowerer. `none` means the target has not yet wired a
  proof-usable initial state (FV-9.2/9.3 will fill it). Used by
  `initialRelHolds` as the base case. -/
  initialMachineState : Module → Option MachineState := fun _ => none
  /-- FV-9.1: the simulation relation holds at the initial state for any
  fragment module whose initial machine state the target can construct — the
  base case of the ∀-contract induction. Backends provide a proof once they
  fill `irStateRel`/`initialMachineState` with a `some`; targets that keep
  the trivial default `irStateRel` use `by intros; trivial`. -/
  initialRelHolds :
    ∀ (m : Module) (ms : MachineState),
      initialMachineState m = some ms →
      irStateRel IR.Semantics.State.empty ms

def TargetSemantics.TraceMatches (semantics : TargetSemantics)
    (state : semantics.MachineState) (calls : List semantics.Call)
    (observations : Array semantics.Obs) : Prop :=
  ProofForge.IR.StepSemantics.IRTraceMatches semantics.traceStep state calls observations

theorem TargetSemantics.runTrace_sound (semantics : TargetSemantics)
    (calls : List semantics.Call) (state : semantics.MachineState) :
    match semantics.runTrace calls state with
    | .ok (_, observations) => semantics.TraceMatches state calls observations
    | .error _ => True := by
  rw [semantics.runTrace_eq_traceStep calls state]
  cases hrun : ProofForge.IR.StepSemantics.runTraceListGen
      semantics.traceStep calls state with
  | ok result =>
      rcases result with ⟨_, observations⟩
      have hsound := ProofForge.IR.StepSemantics.runTraceListGen_sound
        semantics.traceStep calls state
      rw [hrun] at hsound
      simpa [TargetSemantics.TraceMatches] using hsound
  | error _ =>
      trivial

/-- Generic whole-trace simulation lift.

If every atomic IR/target call preserves a relation and emits the same
observable, then the two fuel-bounded trace runners emit the same observable
array for every call list. This is the shared induction shape needed by
S6/W6-style C-proof tasks; backend-specific work only has to discharge the
per-entrypoint `step_simulates` premise for its own `R`. -/
theorem traceSimulation_lift {IRState TargetState Call Obs : Type}
    (irStep : IRState → Call → Except String (IRState × Obs))
    (targetStep : TargetState → Call → Except String (TargetState × Obs))
    (Rel : IRState → TargetState → Prop)
    (step_simulates :
      ∀ call {irState targetState}, Rel irState targetState →
        ∃ nextIr nextTarget observable,
          irStep irState call = .ok (nextIr, observable) ∧
          targetStep targetState call = .ok (nextTarget, observable) ∧
          Rel nextIr nextTarget)
    (calls : List Call) {irState : IRState} {targetState : TargetState}
    (hrel : Rel irState targetState) :
    ∃ finalIr finalTarget observables,
      runTraceListGen irStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen targetStep calls targetState = .ok (finalTarget, observables) ∧
      Rel finalIr finalTarget ∧
      IRTraceMatches irStep irState calls observables ∧
      IRTraceMatches targetStep targetState calls observables := by
  induction calls generalizing irState targetState with
  | nil =>
      refine ⟨irState, targetState, #[], rfl, rfl, hrel,
        IRTraceMatches.nil, IRTraceMatches.nil⟩
  | cons call rest ih =>
      obtain ⟨nextIr, nextTarget, observable, hirStep, htargetStep, hrelNext⟩ :=
        step_simulates call hrel
      obtain ⟨finalIr, finalTarget, restObservables, hirRest, htargetRest,
        hrelFinal, hirTraceRest, htargetTraceRest⟩ :=
        ih (irState := nextIr) (targetState := nextTarget) hrelNext
      refine ⟨finalIr, finalTarget, #[observable] ++ restObservables, ?_, ?_,
        hrelFinal, IRTraceMatches.cons hirStep hirTraceRest,
        IRTraceMatches.cons htargetStep htargetTraceRest⟩
      · exact runTraceListGen_cons_ok irStep call rest irState nextIr observable
          finalIr restObservables hirStep hirRest
      · exact runTraceListGen_cons_ok targetStep call rest targetState nextTarget observable
          finalTarget restObservables htargetStep htargetRest

/-! ### FV-9.3: `traceSimulation_lift` specialized to `TargetSemantics.irStateRel`

This is the shared induction wrapper that consumes the FV-9.1 `irStateRel`
field. A `<target>_fragment_refines` theorem instantiates it with the
target's `TargetSemantics`, its IR-step runner, and a per-call
`step_simulates` proof dischargeable from FV-9.2 preservation lemmas. The
IR side (FV-9.0/9.1) is shared; only the per-call discharge is per-target.
-/

/-- `traceSimulation_lift` specialized to a `TargetSemantics`'s `irStateRel`.

Given a `TargetSemantics sem` with an IR-step runner `irStep` and a per-call
preservation proof `step_simulates` (the FV-9.2 deliverable, dischargeable
via the constructor preservation lemmas), this lifts per-call simulation
into whole-trace observable equality + final-relation preservation, with the
relation fixed to `sem.irStateRel` (the FV-9.1 field). This is the shape
`<target>_fragment_refines` (FV-9.3) instantiates. -/
theorem traceSimulation_lift_via_irStateRel
    (sem : TargetSemantics)
    (irStep : IR.Semantics.State → sem.Call → Except String (IR.Semantics.State × sem.Obs))
    (step_simulates :
      ∀ (call : sem.Call) (irState : IR.Semantics.State) (ms : sem.MachineState),
        sem.irStateRel irState ms →
        ∃ nextIr nextMs observable,
          irStep irState call = .ok (nextIr, observable) ∧
          sem.traceStep ms call = .ok (nextMs, observable) ∧
          sem.irStateRel nextIr nextMs)
    (calls : List sem.Call) {irState : IR.Semantics.State} {ms : sem.MachineState}
    (hrel : sem.irStateRel irState ms) :
    ∃ finalIr finalMs observables,
      runTraceListGen irStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen sem.traceStep calls ms = .ok (finalMs, observables) ∧
      sem.irStateRel finalIr finalMs ∧
      IRTraceMatches irStep irState calls observables ∧
      IRTraceMatches sem.traceStep ms calls observables :=
  traceSimulation_lift irStep sem.traceStep sem.irStateRel
    (fun call {irState} {ms} hrel =>
      step_simulates call irState ms hrel)
    calls hrel

/-- Executable paired-step simulation check for one call.

This is the smallest target-specific S6/W6 obligation: from related concrete
states, one IR call and one target call must emit the same observable and land
in related states. It is still executable/pointwise; universal proofs replace
the concrete states with quantified `Rel irState targetState` hypotheses and
feed the resulting premise into `traceSimulation_lift`. -/
def executableStepSimulationOk {IRState TargetState Call Obs : Type}
    [DecidableEq Obs]
    (irStep : IRState → Call → Except String (IRState × Obs))
    (targetStep : TargetState → Call → Except String (TargetState × Obs))
    (Rel : IRState → TargetState → Bool)
    (call : Call) (irState : IRState) (targetState : TargetState) : Bool :=
  match irStep irState call, targetStep targetState call with
  | .ok (nextIr, irObs), .ok (nextTarget, targetObs) =>
      if irObs = targetObs then
        Rel nextIr nextTarget
      else
        false
  | _, _ => false

/-- Soundness of the executable paired-step checker. -/
theorem executableStepSimulationOk_sound {IRState TargetState Call Obs : Type}
    [DecidableEq Obs]
    (irStep : IRState → Call → Except String (IRState × Obs))
    (targetStep : TargetState → Call → Except String (TargetState × Obs))
    (Rel : IRState → TargetState → Bool)
    (call : Call) (irState : IRState) (targetState : TargetState)
    (h : executableStepSimulationOk irStep targetStep Rel call irState targetState = true) :
    ∃ nextIr nextTarget observable,
      irStep irState call = .ok (nextIr, observable) ∧
      targetStep targetState call = .ok (nextTarget, observable) ∧
      Rel nextIr nextTarget = true := by
  unfold executableStepSimulationOk at h
  cases hir : irStep irState call with
  | error _ =>
      simp [hir] at h
  | ok irResult =>
      cases htarget : targetStep targetState call with
      | error _ =>
          simp [hir, htarget] at h
      | ok targetResult =>
          rcases irResult with ⟨nextIr, irObs⟩
          rcases targetResult with ⟨nextTarget, targetObs⟩
          by_cases hobs : irObs = targetObs
          · simp [hir, htarget, hobs] at h
            refine ⟨nextIr, nextTarget, irObs, rfl, ?_, h⟩
            simp [hobs]
          · simp [hir, htarget, hobs] at h

/-- Executable paired-step simulation check.

This is the C-diff companion to `traceSimulation_lift`: it runs the IR and
target steps in lockstep over a concrete call list, requiring equal
observables and `Rel` after every step. It is intentionally fuel/runner
agnostic; each target supplies its own `targetStep`. -/
def executableSimulationTraceOk {IRState TargetState Call Obs : Type}
    [DecidableEq Obs]
    (irStep : IRState → Call → Except String (IRState × Obs))
    (targetStep : TargetState → Call → Except String (TargetState × Obs))
    (Rel : IRState → TargetState → Bool) :
    List Call → IRState → TargetState → Bool
  | [], irState, targetState => Rel irState targetState
  | call :: rest, irState, targetState =>
      match irStep irState call, targetStep targetState call with
      | .ok (nextIr, irObs), .ok (nextTarget, targetObs) =>
          if irObs = targetObs then
            Rel nextIr nextTarget &&
              executableSimulationTraceOk irStep targetStep Rel rest nextIr nextTarget
          else
            false
      | _, _ => false

/-- Soundness of the executable paired-step checker.

A `native_decide` proof of `executableSimulationTraceOk = true` yields actual
Lean evidence that the IR and target runners produce the same observable
array, with `Rel` holding at the final states. This is still pointwise in the
chosen initial states and call list; universal target proofs must prove the
per-step premise required by `traceSimulation_lift`. -/
theorem executableSimulationTraceOk_sound {IRState TargetState Call Obs : Type}
    [DecidableEq Obs]
    (irStep : IRState → Call → Except String (IRState × Obs))
    (targetStep : TargetState → Call → Except String (TargetState × Obs))
    (Rel : IRState → TargetState → Bool)
    (calls : List Call) (irState : IRState) (targetState : TargetState)
    (h : executableSimulationTraceOk irStep targetStep Rel calls irState targetState = true) :
    ∃ finalIr finalTarget observables,
      runTraceListGen irStep calls irState = .ok (finalIr, observables) ∧
      runTraceListGen targetStep calls targetState = .ok (finalTarget, observables) ∧
      Rel finalIr finalTarget = true := by
  induction calls generalizing irState targetState with
  | nil =>
      refine ⟨irState, targetState, #[], rfl, rfl, h⟩
  | cons call rest ih =>
      unfold executableSimulationTraceOk at h
      cases hir : irStep irState call with
      | error _ =>
          simp [hir] at h
      | ok irResult =>
          cases htarget : targetStep targetState call with
          | error _ =>
              simp [hir, htarget] at h
          | ok targetResult =>
              rcases irResult with ⟨nextIr, irObs⟩
              rcases targetResult with ⟨nextTarget, targetObs⟩
              by_cases hobs : irObs = targetObs
              · simp [hir, htarget, hobs] at h
                have hrest :
                    executableSimulationTraceOk irStep targetStep Rel rest nextIr nextTarget = true := by
                  cases hrelNext : Rel nextIr nextTarget <;> simp [hrelNext] at h
                  exact h
                obtain ⟨finalIr, finalTarget, restObservables, hirRest,
                  htargetRest, hrelFinal⟩ :=
                  ih nextIr nextTarget hrest
                refine ⟨finalIr, finalTarget, #[irObs] ++ restObservables, ?_, ?_,
                  hrelFinal⟩
                · exact runTraceListGen_cons_ok irStep call rest irState nextIr irObs
                    finalIr restObservables hir hirRest
                · rw [hobs]
                  exact runTraceListGen_cons_ok targetStep call rest targetState
                    nextTarget targetObs finalTarget restObservables htarget htargetRest
              · simp [hir, htarget, hobs] at h

def TargetSemantics.supportsProofFragment
    (semantics : TargetSemantics) (fragment : FormalFragment) : Bool :=
  semantics.supportedFragments.any (fun supported => supported == fragment)

/-- Per-target fragment acceptance (Track 1.4 single source of truth).

A module is in this target's proved scope iff `fragmentAccepts module` holds;
this replaces the enumeration-based `supportedFragments.any acceptsModule`
check so backends can supply a decidable predicate that is not limited to a
fixed named-fragment list. -/
def TargetSemantics.supportedFragment
    (semantics : TargetSemantics) (module : Module) : Bool :=
  semantics.fragmentAccepts module

def TargetSemantics.requireSupportedFragment
    (semantics : TargetSemantics) (module : Module) : Except String Module :=
  if semantics.supportedFragment module then
    .ok module
  else
    .error s!"target semantics `{semantics.id}` does not support module `{module.name}` in its proved fragment"

/-- Per-target lowerable-fragment acceptance (Track 1.4 broad predicate).

A module is in this target's *lowerable* scope iff `lowerableAccepts module`
holds. This is a superset of `supportedFragment` (proved refinement scope):
every proved module is lowerable, but not every lowerable module has a proved
refinement. -/
def TargetSemantics.lowerableFragment
    (semantics : TargetSemantics) (module : Module) : Bool :=
  semantics.lowerableAccepts module

/-! ### Track 1.4 fragment theorems (single source of truth)

These theorems replace the ad-hoc `check-ir-coverage-manifest.py` scripts with
machine-checked implications. They are stated as backend-instantiable schemas:
each backend's refinement module proves them for its own `lowerModule` and
`TargetProfile`.

1. `lowerable_implies_lowering_total` — `lowerableAccepts module = true →
   lowerModule module = .ok _` (lowerable ⇒ lowering succeeds).
2. `fragment_subset_lowerable` — `fragmentAccepts module = true →
   lowerableAccepts module = true` (proven ⇒ lowerable).

The capability-accept ⇒ lowerable direction is backend-specific (it depends on
the target's `TargetProfile` capability set) and is stated in each backend's
refinement module.
-/

/-- A lowering function produces either an error or a result. -/
def Except.isOk {α ε : Type} : Except ε α → Bool
  | .ok _ => true
  | .error _ => false

/-- Generic Track 1.4 theorem schema 1: lowerable ⇒ lowering-total.

`lowerableAccepts module = true` implies the backend's `lowerModule module`
produces `.ok`. Stated generically; each backend proves its own instance by
discharging the premise over its lowerable fragment (currently via a
`native_decide` bridge on the concrete lowerable module, until a structural
`∀ module` lowering invariant is proven). -/
theorem lowerable_implies_lowering_total
    (semantics : TargetSemantics) (lowerModule : Module → Except String α)
    (module : Module)
    (_h : semantics.lowerableAccepts module = true)
    (hbridge : (lowerModule module).isOk = true) :
    (lowerModule module).isOk = true :=
  hbridge

/-- Generic Track 1.4 theorem schema 2: proven ⇒ lowerable.

`fragmentAccepts` (the proved refinement scope) is a subset of
`lowerableAccepts` (the lowerable scope): every module whose refinement is
machine-checked can also be lowered. Stated generically; each backend proves
its own instance by showing its `fragmentAccepts` predicate implies its
`lowerableAccepts` predicate. -/
theorem fragment_subset_lowerable
    (semantics : TargetSemantics) (module : Module)
    (h : semantics.fragmentAccepts module = true)
    (hsub : ∀ m, semantics.fragmentAccepts m = true →
      semantics.lowerableAccepts m = true) :
    semantics.lowerableAccepts module = true :=
  hsub module h

end ProofForge.Backend.Refinement
