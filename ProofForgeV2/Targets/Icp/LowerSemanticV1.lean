import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# ICP LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Narrow ICP-2 Counter/StateCell target leaf (ADR-0047). Envelope:

* public UInt64 state only (no Bool/Int/Field/Principal/aggregates/containers)
* `init` (initializer), `entry` (canister_update), `view` (canister_query)
* single-block callable bodies; checked `+`/`-` only (no mul/div/mod/compare/
  bitwise/bool); literal, param, stateLoad, stateStore, return
* zero pureFn, zero invariants, zero constants/events/errors
* zero `emit` / `call` (`Op.ExternalCall`) / `schedule` / `Op.ContextRead` /
  `Op.Commit`; the ICP-1 async advertise (`effect.asynchronous-workflow`)
  stays a resolver-level advertisement only — no ICP-2 Plan shape realizes it

Anything outside this envelope fails closed here (target-owned Plan; retains
no Semantic carrier). Not NEAR/CosmWasm Plan reuse (ADR-0007); not
sync-call/event/async materialization.
-/

namespace ProofForgeV2.Targets.Icp

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Engineering codegen profile spelling for the sole ICP-2 leaf. -/
def codegenProfileString : String := "icp-wasm-candid-u64-v1"

def codegenProfile : CodegenProfileId := CodegenProfileId.icpWasmCandidU64V1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .icp message

private def icpPlanErr (message : String) : CompileError :=
  .planInvariant .icp message

-- ---------------------------------------------------------------------------
-- Target-owned Plan surface
-- ---------------------------------------------------------------------------

/-- Untyped UInt64 expression nodes. Every value in this Plan is UInt64 — no
    Bool/comparisons are represented (the Counter/StateCell envelope has no
    conditional shape). -/
inductive Expr where
  | literal (value : UInt64)
  | param (index : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

/-- Method body statement. `returnNone` is the explicit Unit terminator
    marker (initializer and Unit-result entries). -/
inductive Statement where
  | store (fieldIndex : Nat) (value : Expr)
  | returnValue (value : Expr)
  | returnNone
  deriving BEq, Inhabited, Repr

/-- IC method dispatch mode: initializer runs once at canister install;
    mutate is a `canister_update`; query is a `canister_query`. -/
inductive MethodMode where
  | initialize
  | mutate
  | query
  deriving BEq, Inhabited, Repr

inductive ResultKind where
  | unit
  | uint64
  deriving BEq, Inhabited, Repr

structure StateField where
  name : String
  deriving BEq, Inhabited, Repr

structure Method where
  name : String
  params : Array String
  mode : MethodMode
  resultKind : ResultKind
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Target-owned ICP Plan. Digests + artifact name only; no Semantic carrier. -/
structure Plan where
  programName : String
  sourceHash : String
  semanticHash : String
  states : Array StateField
  initializer : Method
  entries : Array Method
  views : Array Method
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Type closure (anonymous unique UInt64 only; Unit for init/Unit results)
-- ---------------------------------------------------------------------------

private def icpTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "ICP"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64 width is supported"
  unsupportedShapeDetail :=
    "only anonymous UInt64, Bool, and Unit are supported (Int/Field/Principal/aggregates/containers/String fail closed on the ICP-2 Counter/StateCell envelope)"

private def pilotUintWidthPolicyU64Only : PilotUintWidthPolicy where
  admittedWidths := #[64]

private abbrev IcpTypeClosureV1 := PilotTypeClosureV1

private def validateIcpTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult IcpTypeClosureV1 :=
  validatePilotTypeClosure icpPlanErr icpTypeClosureWording types
    pilotUintWidthPolicyU64Only
    (intPolicy := pilotIntWidthPolicyNone)
    (fieldPolicy := pilotFieldPolicyNone)
    (principalPolicy := pilotPrincipalPolicyNone)

private def maxIdentifierBytes : Nat := 200
private def maxStateFields : Nat := 64
private def maxParams : Nat := 32
private def maxBodyStatements : Nat := 256
/-- Maximum fully expanded nodes in any target Plan expression. -/
private def maxExpandedExprNodes : Nat := 4096

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

private def isUInt64Type (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  typeId == types.uint64TypeId

private def isUnitType (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.unitTypeId == some typeId

-- ---------------------------------------------------------------------------
-- Lowering helpers
-- ---------------------------------------------------------------------------

private structure ValueEnv where
  entries : Array (ValueIdV1 × Expr)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option Expr :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (v : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

/-- Overlay for StateStore → subsequent StateLoad within the single block.
    Last write wins on `overlayFinalStores` projection. -/
private structure StateOverlay where
  entries : Array (StateIdV1 × Expr)
  deriving Inhabited

private def overlayLookup (ov : StateOverlay) (sid : StateIdV1) : Option Expr :=
  ov.entries.findSome? (fun (id, e) => if id == sid then some e else none)

private def overlayInsert
    (ov : StateOverlay) (sid : StateIdV1) (e : Expr) : StateOverlay :=
  let withoutOld := ov.entries.filter (fun item => item.1 != sid)
  { ov with entries := withoutOld.push (sid, e) }

/-- Emit final stores in ascending field-index order (dense Statement.store
    list; store order does not need to match source order for Plan purposes,
    only the final value per field matters for a single-block body). -/
private def overlayFinalStores (ov : StateOverlay) : Array Statement := Id.run do
  let mut last : Array (Option Expr) := #[]
  for (sid, e) in ov.entries do
    let i := sid.toNat
    while last.size ≤ i do
      last := last.push none
    last := last.set! i (some e)
  let mut out : Array Statement := #[]
  for i in [0:last.size] do
    match last[i]? with
    | some (some e) => out := out.push (.store i e)
    | _ => pure ()
  pure out

/-- After overlay stores are projected, a return that still names the pre-store
    Expr tree would re-evaluate that tree in Emit (classic store-then-read
    hazard: `count := count + delta; return count` became add-twice). Map any
    return Expr that is exactly an overlay value back to `.stateLoad` of the
    field that now holds it. -/
private def rewriteReturnThroughOverlay (ov : StateOverlay) (e : Expr) : Expr :=
  match ov.entries.findSome? (fun (sid, v) => if v == e then some sid else none) with
  | some sid => .stateLoad sid.toNat
  | none => e

private structure BodyAccum where
  env : ValueEnv
  overlay : StateOverlay
  opCount : Nat
  deriving Inhabited

private def emptyBodyAccum (env : ValueEnv) (overlay : StateOverlay) : BodyAccum :=
  { env, overlay, opCount := 0 }

private def bumpOp (acc : BodyAccum) : CompileResult BodyAccum := do
  if acc.opCount + 1 > maxBodyStatements then
    planError "unsupported ICP semantic shape: body operation count exceeds limit"
  pure { acc with opCount := acc.opCount + 1 }

private partial def exprNodes : Expr → Nat
  | .literal _ | .param _ | .stateLoad _ => 1
  | .checkedAdd lhs rhs | .checkedSub lhs rhs => 1 + exprNodes lhs + exprNodes rhs

private def checkedExprNodes (what : String) (e : Expr) : CompileResult Expr := do
  unless exprNodes e ≤ maxExpandedExprNodes do
    planError
      s!"unsupported ICP semantic shape: {what} expanded expression exceeds {maxExpandedExprNodes} nodes"
  pure e

private def lowerLiteral
    (types : IcpTypeClosureV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult Expr := do
  unless isUInt64Type types typeId do
    planError "unsupported ICP semantic shape: literal type is outside UInt64"
  let v ← decodeUInt64LiteralLe icpPlanErr "ICP" valueBytes
  pure (.literal v)

private def lowerBinary (op : BinaryOpV1) (lhs rhs : Expr) : CompileResult Expr := do
  match op with
  | .add => checkedExprNodes "add" (.checkedAdd lhs rhs)
  | .sub => checkedExprNodes "sub" (.checkedSub lhs rhs)
  | .mul | .div | .mod | .eq | .ne | .lt | .le | .gt | .ge | .and | .or
  | .bitAnd | .bitOr | .bitXor | .shl | .shr =>
      planError
        "unsupported ICP semantic shape: only checked add/sub are admitted on the ICP-2 Counter/StateCell envelope"

/-- Single-block instruction walk (ICP-2 has no pureFn/invariant closures, no
    branching, no async continuations — StateCell shape only). -/
private partial def lowerInstructions
    (data : SemanticProgramDataV1) (types : IcpTypeClosureV1)
    (allowStateWrite : Bool) (callable : CallableV1) (acc0 : BodyAccum) :
    CompileResult (BodyAccum × Option Expr) := do
  unless callable.blocks.size == 1 do
    planError
      "unsupported ICP semantic shape: each callable must have exactly one block (Counter/StateCell envelope has no control flow)"
  unless callable.loopBounds.isEmpty do
    planError "unsupported ICP semantic shape: loopBounds are outside ICP-2"
  unless callable.entryBlock.toNat == 0 do
    planError "unsupported ICP semantic shape: entryBlock must be 0"
  let some block := callable.blocks[0]? |
    planError "unsupported ICP semantic shape: missing entry block"
  unless block.params.isEmpty do
    planError "unsupported ICP semantic shape: block parameters are outside ICP-2"
  let mut acc := acc0
  for instr in block.instructions do
    acc ← bumpOp acc
    match instr.op with
    | .literal typeId valueBytes => do
        let v ← lowerLiteral types typeId valueBytes
        match instr.result with
        | none => planError "unsupported ICP semantic shape: literal must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId v }
    | .stateLoad stateId => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: stateLoad must produce a value"
        | some vd =>
            unless stateId.toNat < data.logicalState.size do
              planError "unsupported ICP semantic shape: stateLoad references unknown state"
            let value : Expr :=
              match overlayLookup acc.overlay stateId with
              | some ov => ov
              | none => .stateLoad stateId.toNat
            acc := { acc with env := envInsert acc.env vd.valueId value }
    | .stateStore stateId value => do
        unless allowStateWrite do
          planError "unsupported ICP semantic shape: view methods cannot write state"
        let v ← match envLookup acc.env value with
          | some tv => pure tv
          | none => planError "unsupported ICP semantic shape: stateStore value undefined"
        unless stateId.toNat < data.logicalState.size do
          planError "unsupported ICP semantic shape: stateStore references unknown state"
        acc := { acc with overlay := overlayInsert acc.overlay stateId v }
    | .binary op lhs rhs => do
        let lv ← match envLookup acc.env lhs with
          | some v => pure v
          | none => planError "unsupported ICP semantic shape: binary lhs undefined"
        let rv ← match envLookup acc.env rhs with
          | some v => pure v
          | none => planError "unsupported ICP semantic shape: binary rhs undefined"
        let e ← lowerBinary op lv rv
        match instr.result with
        | none => planError "unsupported ICP semantic shape: binary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId e }
    | .constant .. =>
        planError "unsupported ICP semantic shape: constants table must be empty (ICP-2 has no const lowering)"
    | .contextRead .. =>
        planError "unsupported ICP semantic shape: Op.ContextRead is outside the ICP-2 envelope"
    | .commit .. =>
        planError "unsupported ICP semantic shape: Op.Commit is outside the ICP-2 envelope"
    | .emit .. =>
        planError "unsupported ICP semantic shape: emit is outside the ICP-2 envelope (no portable event bus)"
    | .externalCall .. =>
        planError "unsupported ICP semantic shape: call is outside the ICP-2 envelope (ICP has no sync inter-canister call)"
    | .schedule .. =>
        planError "unsupported ICP semantic shape: schedule (async workflow) is advertised at the resolver only — ICP-2 Plan has no realized async shape"
    | .construct .. | .fieldGet .. | .fieldSet ..
    | .variantTag .. | .variantPayload .. | .indexGet .. | .indexSet ..
    | .checkedCast .. | .unary .. | .pureCall .. | .envRead .. | .assert_ .. =>
        planError "unsupported ICP semantic shape: op is outside the ICP-2 Counter/StateCell envelope"
  match block.terminator with
  | .return_ value => do
      match value with
      | none => pure (acc, none)
      | some vid =>
          match envLookup acc.env vid with
          | some e => pure (acc, some e)
          | none => planError "unsupported ICP semantic shape: return value undefined"
  | .revert .. =>
      planError "unsupported ICP semantic shape: revert is outside the ICP-2 envelope (errors table must be empty)"
  | .jump .. | .branch .. | .switch .. | .trap .. =>
      planError "unsupported ICP semantic shape: multi-block/branch/switch/trap terminators are outside ICP-2 (no control flow)"

private def seedParamEnv (types : IcpTypeClosureV1) (owner : String)
    (callable : CallableV1) : CompileResult (ValueEnv × Array String) := do
  let mut env : ValueEnv := { entries := #[] }
  let mut names : Array String := #[]
  let mut i : Nat := 0
  for p in callable.params do
    requirePublicUInt64Param icpPlanErr types.uint64TypeId owner p
    unless isIdentifier p.name do
      planError s!"parameter '{p.name}' in {owner} is not a safe identifier"
    env := envInsert env p.valueId (.param i)
    names := names.push p.name
    i := i + 1
  unless names.size ≤ maxParams do
    planError s!"{owner} parameter count exceeds limit"
  if hasDuplicates names then
    planError s!"{owner} parameter names must be unique"
  pure (env, names)

private def lowerCallableBody
    (data : SemanticProgramDataV1) (types : IcpTypeClosureV1)
    (allowStateWrite seedZeroState : Bool) (owner : String)
    (callable : CallableV1) :
    CompileResult (Array String × Array Statement × Option Expr) := do
  let (env0, paramNames) ← seedParamEnv types owner callable
  let mut overlay0 : StateOverlay := { entries := #[] }
  if seedZeroState then
    for st in data.logicalState do
      overlay0 := overlayInsert overlay0 st.id (.literal 0)
  let acc0 := emptyBodyAccum env0 overlay0
  let (acc, ret?) ← lowerInstructions data types allowStateWrite callable acc0
  let stores := overlayFinalStores acc.overlay
  let ret? := ret?.map (rewriteReturnThroughOverlay acc.overlay)
  pure (paramNames, stores, ret?)

private def resultKindOf
    (types : IcpTypeClosureV1) (typeId : TypeIdV1) (owner : String) :
    CompileResult ResultKind := do
  if isUnitType types typeId then pure .unit
  else if isUInt64Type types typeId then pure .uint64
  else planError s!"{owner} result must be public Unit or UInt64"

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  unless isIdentifier programName do
    planError s!"program name '{programName}' is not a safe identifier"
  unless data.constants.isEmpty do
    planError "unsupported ICP semantic shape: constants table must be empty (ICP-2 admits zero constants)"
  unless data.events.isEmpty do
    planError "unsupported ICP semantic shape: events table must be empty (emit is outside ICP-2)"
  unless data.errors.isEmpty do
    planError "unsupported ICP semantic shape: errors table must be empty (revert is outside ICP-2)"
  unless data.invariants.isEmpty do
    planError "unsupported ICP semantic shape: invariants must be empty (nonempty invariants fail closed on ICP-2)"
  let types ← validateIcpTypeClosureV1 data.types
  let mut states : Array StateField := #[]
  for st in data.logicalState do
    requirePublicUInt64State icpPlanErr types.uint64TypeId st
    unless isIdentifier st.name do
      planError s!"state name '{st.name}' is not a safe identifier"
    unless st.id.toNat == states.size do
      planError "unsupported ICP semantic shape: state ids must match declaration order"
    states := states.push { name := st.name }
  unless states.size ≤ maxStateFields do
    planError "unsupported ICP semantic shape: state field count exceeds limit"
  let mut initializer? : Option Method := none
  let mut entries : Array Method := #[]
  let mut views : Array Method := #[]
  for callable in data.callables do
    match callable.kind with
    | .pureFn =>
        planError "unsupported ICP semantic shape: pureFn is outside the ICP-2 Counter/StateCell envelope"
    | .invariant =>
        planError "unsupported ICP semantic shape: invariant callables are outside the ICP-2 envelope"
    | .initializer => do
        unless initializer?.isNone do
          planError "unsupported ICP semantic shape: at most one initializer"
        unless isUnitType types callable.result.typeId do
          planError "unsupported ICP semantic shape: initializer result must be Unit"
        unless callable.result.visibility == .public_ do
          planError "unsupported ICP semantic shape: initializer result must be public"
        let (params, stores, ret?) ←
          lowerCallableBody data types (allowStateWrite := true) (seedZeroState := true)
            "initializer" callable
        unless ret?.isNone do
          planError "unsupported ICP semantic shape: initializer must return Unit"
        initializer? := some {
          name := "init", params, mode := .initialize, resultKind := .unit
          body := stores
        }
    | .entry => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported ICP semantic shape: entry requires a name"
        unless isIdentifier name do
          planError s!"entry '{name}' is not a safe identifier"
        let rk ← resultKindOf types callable.result.typeId s!"entry '{name}'"
        unless callable.result.visibility == .public_ do
          planError s!"entry '{name}' result must be public"
        let (params, stores, ret?) ←
          lowerCallableBody data types (allowStateWrite := true) (seedZeroState := false)
            s!"entry '{name}'" callable
        let body ← match rk, ret? with
          | .unit, none => pure stores
          | .unit, some _ =>
              planError s!"entry '{name}' Unit result must not return a value"
          | .uint64, some e => pure (stores.push (.returnValue e))
          | .uint64, none =>
              planError s!"entry '{name}' non-Unit result is missing"
        entries := entries.push {
          name, params, mode := .mutate, resultKind := rk, body
        }
    | .view => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported ICP semantic shape: view requires a name"
        unless isIdentifier name do
          planError s!"view '{name}' is not a safe identifier"
        let rk ← resultKindOf types callable.result.typeId s!"view '{name}'"
        unless rk == .uint64 do
          planError s!"view '{name}' result must be UInt64 (query methods must return a value)"
        unless callable.result.visibility == .public_ do
          planError s!"view '{name}' result must be public"
        let (params, stores, ret?) ←
          lowerCallableBody data types (allowStateWrite := false) (seedZeroState := false)
            s!"view '{name}'" callable
        unless stores.isEmpty do
          planError s!"view '{name}' cannot write state"
        let e ← match ret? with
          | some e => pure e
          | none => planError s!"view '{name}' must return a value"
        views := views.push {
          name, params, mode := .query, resultKind := rk, body := #[.returnValue e]
        }
  let initializer ← match initializer? with
    | some m => pure m
    | none => planError "unsupported ICP semantic shape: ICP-2 requires exactly one initializer"
  unless entries.size > 0 do
    planError "unsupported ICP semantic shape: at least one entry is required"
  pure {
    programName
    sourceHash
    semanticHash
    states
    initializer
    entries
    views
  }

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "ICP received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

/-- Internal capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .icp do
    throw <| .planInvariant .icp "engineering capability kind is not ICP"
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  unless selection.codegenProfile == codegenProfile do
    planError s!"unsupported ICP codegen profile (expected {codegenProfileString})"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "ICP source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "ICP semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

/-- Unit-test Plan entry over retained SemanticProgramV1 (no registry required). -/
def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "ICP source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "ICP semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Icp
