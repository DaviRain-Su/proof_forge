import ProofForge.IR.Semantics
import ProofForge.IR.Core.Semantics
import ProofForge.IR.Core.Id
import ProofForge.IR.Legacy.Classification
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec
import Std

namespace ProofForge.IR.Legacy.Refinement

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics
open ProofForge.IR.Legacy
open ProofForge.IR.Legacy.Adapter
open ProofForge.Contract

/-! Value-range constants for the fixed-width scalar types carried by Core. -/

def u8Max : Nat := 255
def u32Max : Nat := 4294967295
def u64Max : Nat := 18446744073709551615
def u128Max : Nat := 340282366920938463463374607431768211455

/-- A legacy scalar value is within the range of its declared type. Aggregates
and non-numeric scalars are treated as in-range. -/
def legacyValueInRange : ProofForge.IR.Semantics.Value → Bool
  | .u8 n => n ≤ u8Max
  | .u32 n => n ≤ u32Max
  | .u64 n => n ≤ u64Max
  | .u128 n => n ≤ u128Max
  | _ => true

/-- Convert a legacy runtime value to a Core value, failing only on unsupported
or out-of-range aggregates. This is the forward direction used for observable
comparison. -/
def legacyToCoreValue : ProofForge.IR.Semantics.Value → Option CoreValue
  | .unit => some .unit
  | .bool b => some (.bool b)
  | .u8 n => if n ≤ u8Max then some (.u8 (UInt8.ofNat n)) else none
  | .u32 n => if n ≤ u32Max then some (.u32 (UInt32.ofNat n)) else none
  | .u64 n => if n ≤ u64Max then some (.u64 (UInt64.ofNat n)) else none
  | .u128 n => if n ≤ u128Max then some (.u128 (BitVec.ofNat 128 n)) else none
  | .address n => some (.address (toString n))
  | .bytes bs =>
      some (.bytes (ByteArray.mk (Array.mk (bs.map (fun b => UInt8.ofNat b)))))
  | .string s => some (.string s)
  | .hash a b c d => some (.hash (s!"{a}:{b}:{c}:{d}"))
  | .array _ | .struct _ _ => none

/-- Convert a Core scalar value back to a legacy value. Only used for event
argument comparison. -/
def coreScalarToLegacyValue : CoreValue → Option ProofForge.IR.Semantics.Value
  | .unit => some .unit
  | .bool b => some (.bool b)
  | .u8 n => some (.u8 n.toNat)
  | .u32 n => some (.u32 n.toNat)
  | .u64 n => some (.u64 n.toNat)
  | .u128 n => some (.u128 n.toNat)
  | .string s => some (.string s)
  | _ => none

/-- Map a Core state id back to the source state name. The adapter assigns state
ids in declaration order, so the numeric id is exactly the source index. -/
def sourceStateName (spec : ContractSpec) (sid : StateId) : Option String :=
  spec.module.state[sid.value]?.map (·.id)

/-- Map a Core event id back to the source event name. Event ids are assigned in
first-occurrence order by `collectEventNames`. -/
def sourceEventName (spec : ContractSpec) (eid : EventId) : Option String :=
  (collectEventNames spec.module)[eid.value]?

/-- Decision acceptability for the scalar fragment. Delegates to the
canonical `isScalarAcceptable` from the classification module. -/
def allAcceptable (ds : Array LegacyDecision) : Bool :=
  ds.all isScalarAcceptable

def scalarFragmentValueType (ty : ValueType) : Bool :=
  allAcceptable #[classifyValueType ty]

def scalarFragmentLiteral (lit : Literal) : Bool :=
  allAcceptable #[classifyLiteral lit]

def scalarFragmentAssignOp (op : AssignOp) : Bool :=
  allAcceptable #[classifyAssignOp op]

def scalarFragmentContextField (f : ProofForge.IR.ContextField) : Bool :=
  allAcceptable #[classifyContextField f]

def scalarFragmentStoragePathSegment (s : StoragePathSegment) : Bool :=
  allAcceptable #[classifyStoragePathSegment s]

def scalarFragmentErrorRef (r : ErrorRef) : Bool :=
  allAcceptable (classifyErrorRefFields r)

mutual
  /-- Helper: every expression in a list belongs to the scalar fragment. -/
  def scalarFragmentExprList (es : List Expr) : Bool :=
    match es with
    | [] => true
    | e :: es => scalarFragmentExpr e && scalarFragmentExprList es

  /-- Helper: every expression in a list of named fields belongs to the scalar
  fragment. -/
  def scalarFragmentExprPairList (es : List (String × Expr)) : Bool :=
    match es with
    | [] => true
    | (_, e) :: es => scalarFragmentExpr e && scalarFragmentExprPairList es

  /-- Helper: an optional expression belongs to the scalar fragment. -/
  def scalarFragmentExprOption : Option Expr → Bool
    | none => true
    | some e => scalarFragmentExpr e

  /-- Helper: every statement in a list belongs to the scalar fragment. -/
  def scalarFragmentStatementList (ss : List Statement) : Bool :=
    match ss with
    | [] => true
    | s :: ss => scalarFragmentStatement s && scalarFragmentStatementList ss

  /-- Recursively check that an expression belongs to the scalar fragment. -/
  def scalarFragmentExpr : Expr → Bool
    | .literal lit => allAcceptable #[classifyExpr (.literal lit)] && scalarFragmentLiteral lit
    | .local _ => allAcceptable #[classifyExpr (.local "")]
    | .arrayLit _ es =>
        match es with
        | ⟨es⟩ => allAcceptable #[classifyExpr (.arrayLit .u8 #[])] && scalarFragmentExprList es
    | .arrayGet a i => allAcceptable #[classifyExpr (.arrayGet (.local "") (.literal (.u64 0)))] && scalarFragmentExpr a && scalarFragmentExpr i
    | .memoryArrayNew _ len => allAcceptable #[classifyExpr (.memoryArrayNew .u8 (.literal (.u64 0)))] && scalarFragmentExpr len
    | .memoryArrayLength a => allAcceptable #[classifyExpr (.memoryArrayLength (.local ""))] && scalarFragmentExpr a
    | .memoryArrayGet a i => allAcceptable #[classifyExpr (.memoryArrayGet (.local "") (.literal (.u64 0)))] && scalarFragmentExpr a && scalarFragmentExpr i
    | .structLit _ fs =>
        match fs with
        | ⟨fs⟩ => allAcceptable #[classifyExpr (.structLit "" #[])] && scalarFragmentExprPairList fs
    | .field base _ => allAcceptable #[classifyExpr (.field (.local "") "")] && scalarFragmentExpr base
    | .add lhs rhs _ => allAcceptable #[classifyExpr (.add (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .sub lhs rhs _ => allAcceptable #[classifyExpr (.sub (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .mul lhs rhs _ => allAcceptable #[classifyExpr (.mul (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .div lhs rhs => allAcceptable #[classifyExpr (.div (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .mod lhs rhs => allAcceptable #[classifyExpr (.mod (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .pow lhs rhs => allAcceptable #[classifyExpr (.pow (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .bitAnd lhs rhs => allAcceptable #[classifyExpr (.bitAnd (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .bitOr lhs rhs => allAcceptable #[classifyExpr (.bitOr (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .bitXor lhs rhs => allAcceptable #[classifyExpr (.bitXor (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .shiftLeft lhs rhs => allAcceptable #[classifyExpr (.shiftLeft (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .shiftRight lhs rhs => allAcceptable #[classifyExpr (.shiftRight (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .cast v _ => allAcceptable #[classifyExpr (.cast (.local "") .u64)] && scalarFragmentExpr v
    | .eq lhs rhs => allAcceptable #[classifyExpr (.eq (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .ne lhs rhs => allAcceptable #[classifyExpr (.ne (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .lt lhs rhs => allAcceptable #[classifyExpr (.lt (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .le lhs rhs => allAcceptable #[classifyExpr (.le (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .gt lhs rhs => allAcceptable #[classifyExpr (.gt (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .ge lhs rhs => allAcceptable #[classifyExpr (.ge (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .boolAnd lhs rhs => allAcceptable #[classifyExpr (.boolAnd (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .boolOr lhs rhs => allAcceptable #[classifyExpr (.boolOr (.local "") (.local ""))] && scalarFragmentExpr lhs && scalarFragmentExpr rhs
    | .boolNot v => allAcceptable #[classifyExpr (.boolNot (.local ""))] && scalarFragmentExpr v
    | .hashValue a b c d => allAcceptable #[classifyExpr (.hashValue (.local "") (.local "") (.local "") (.local ""))] && scalarFragmentExpr a && scalarFragmentExpr b && scalarFragmentExpr c && scalarFragmentExpr d
    | .hash preimage => allAcceptable #[classifyExpr (.hash (.local ""))] && scalarFragmentExpr preimage
    | .hashTwoToOne a b => allAcceptable #[classifyExpr (.hashTwoToOne (.local "") (.local ""))] && scalarFragmentExpr a && scalarFragmentExpr b
    | .nativeValue => allAcceptable #[classifyExpr .nativeValue]
    | .hostCall _ _ _ _ => false
    | .crosscallInvoke t m args =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallInvoke (.local "") (.local "") #[])] && scalarFragmentExpr t && scalarFragmentExpr m && scalarFragmentExprList args
    | .crosscallInvokeTyped t m args _ =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallInvokeTyped (.local "") (.local "") #[] .unit)] && scalarFragmentExpr t && scalarFragmentExpr m && scalarFragmentExprList args
    | .crosscallInvokeValueTyped t m cv args _ =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallInvokeValueTyped (.local "") (.local "") (.local "") #[] .unit)] && scalarFragmentExpr t && scalarFragmentExpr m && scalarFragmentExpr cv && scalarFragmentExprList args
    | .crosscallInvokeStaticTyped t m args _ =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallInvokeStaticTyped (.local "") (.local "") #[] .unit)] && scalarFragmentExpr t && scalarFragmentExpr m && scalarFragmentExprList args
    | .crosscallInvokeDelegateTyped t m args _ =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallInvokeDelegateTyped (.local "") (.local "") #[] .unit)] && scalarFragmentExpr t && scalarFragmentExpr m && scalarFragmentExprList args
    | .crosscallCreate cv _ => allAcceptable #[classifyExpr (.crosscallCreate (.local "") "")] && scalarFragmentExpr cv
    | .crosscallCreate2 cv salt _ => allAcceptable #[classifyExpr (.crosscallCreate2 (.local "") (.local "") "")] && scalarFragmentExpr cv && scalarFragmentExpr salt
    | .crosscallNamed _ _ args _ =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallNamed "" "" #[] .unit)] && scalarFragmentExprList args
    | .crosscallInvokeNamedValue i m args d names =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallInvokeNamedValue (.local "") (.local "") #[] (.local "") names)] && scalarFragmentExpr i && scalarFragmentExpr m && scalarFragmentExprList args && scalarFragmentExpr d
    | .crosscallContinue p c args d names =>
        match args with
        | ⟨args⟩ => allAcceptable #[classifyExpr (.crosscallContinue (.local "") (.local "") #[] (.local "") names)] && scalarFragmentExpr p && scalarFragmentExpr c && scalarFragmentExprList args && scalarFragmentExpr d
    | .callValueU128 => allAcceptable #[classifyExpr .callValueU128]
    | .effect eff => allAcceptable #[classifyExpr (.effect (Effect.contextRead .userId))] && scalarFragmentEffect eff

  /-- Recursively check that an effect belongs to the scalar fragment. -/
  def scalarFragmentEffect : Effect → Bool
    | .hostCall _ _ _ => false
    | .storageScalarRead _ => allAcceptable #[classifyEffect (Effect.storageScalarRead "")]
    | .storageScalarWrite _ e => allAcceptable #[classifyEffect (Effect.storageScalarWrite "" (.local ""))] && scalarFragmentExpr e
    | .storageScalarAssignOp _ op e => allAcceptable #[classifyEffect (Effect.storageScalarAssignOp "" .add (.local ""))] && scalarFragmentAssignOp op && scalarFragmentExpr e
    | .storageMapContains _ k => allAcceptable #[classifyEffect (Effect.storageMapContains "" (.local ""))] && scalarFragmentExpr k
    | .storageMapGet _ k => allAcceptable #[classifyEffect (Effect.storageMapGet "" (.local ""))] && scalarFragmentExpr k
    | .storageMapInsert _ k v => allAcceptable #[classifyEffect (Effect.storageMapInsert "" (.local "") (.local ""))] && scalarFragmentExpr k && scalarFragmentExpr v
    | .storageMapSet _ k v => allAcceptable #[classifyEffect (Effect.storageMapSet "" (.local "") (.local ""))] && scalarFragmentExpr k && scalarFragmentExpr v
    | .storageMapDelete _ k => allAcceptable #[classifyEffect (Effect.storageMapDelete "" (.local ""))] && scalarFragmentExpr k
    | .storageArrayRead _ i => allAcceptable #[classifyEffect (Effect.storageArrayRead "" (.local ""))] && scalarFragmentExpr i
    | .storageArrayWrite _ i v => allAcceptable #[classifyEffect (Effect.storageArrayWrite "" (.local "") (.local ""))] && scalarFragmentExpr i && scalarFragmentExpr v
    | .storageArrayStructFieldRead _ i _ => allAcceptable #[classifyEffect (Effect.storageArrayStructFieldRead "" (.local "") "")] && scalarFragmentExpr i
    | .storageArrayStructFieldWrite _ i _ v => allAcceptable #[classifyEffect (Effect.storageArrayStructFieldWrite "" (.local "") "" (.local ""))] && scalarFragmentExpr i && scalarFragmentExpr v
    | .storageDynamicArrayPush _ e => allAcceptable #[classifyEffect (Effect.storageDynamicArrayPush "" (.local ""))] && scalarFragmentExpr e
    | .storageDynamicArrayPop _ => allAcceptable #[classifyEffect (Effect.storageDynamicArrayPop "")]
    | .memoryArraySet a i v => allAcceptable #[classifyEffect (Effect.memoryArraySet (.local "") (.local "") (.local ""))] && scalarFragmentExpr a && scalarFragmentExpr i && scalarFragmentExpr v
    | .storageStructFieldRead _ _ => allAcceptable #[classifyEffect (Effect.storageStructFieldRead "" "")]
    | .storageStructFieldWrite _ _ e => allAcceptable #[classifyEffect (Effect.storageStructFieldWrite "" "" (.local ""))] && scalarFragmentExpr e
    | .storagePathRead _ path => allAcceptable #[classifyEffect (Effect.storagePathRead "" #[])] && path.all scalarFragmentStoragePathSegment
    | .storagePathWrite _ path e => allAcceptable #[classifyEffect (Effect.storagePathWrite "" #[] (.local ""))] && path.all scalarFragmentStoragePathSegment && scalarFragmentExpr e
    | .storagePathAssignOp _ path op e => allAcceptable #[classifyEffect (Effect.storagePathAssignOp "" #[] .add (.local ""))] && path.all scalarFragmentStoragePathSegment && scalarFragmentAssignOp op && scalarFragmentExpr e
    | .contextRead f => allAcceptable #[classifyEffect (Effect.contextRead .userId)] && scalarFragmentContextField f
    | .eventEmit _ fs =>
        match fs with
        | ⟨fs⟩ => allAcceptable #[classifyEffect (Effect.eventEmit "" #[])] && scalarFragmentExprPairList fs
    | .eventEmitIndexed _ is ds =>
        match is, ds with
        | ⟨is⟩, ⟨ds⟩ => allAcceptable #[classifyEffect (Effect.eventEmitIndexed "" #[] #[])] && scalarFragmentExprPairList is && scalarFragmentExprPairList ds
  /-- Recursively check that a statement belongs to the scalar fragment. -/
  def scalarFragmentStatement : Statement → Bool
    | .letBind _ ty e => allAcceptable #[classifyStatement (.letBind "" .u64 (.local ""))] && scalarFragmentValueType ty && scalarFragmentExpr e
    | .letMutBind _ ty e => allAcceptable #[classifyStatement (.letMutBind "" .u64 (.local ""))] && scalarFragmentValueType ty && scalarFragmentExpr e
    | .assign (.local _) e => allAcceptable #[classifyStatement (.assign (.local "") (.local ""))] && scalarFragmentExpr e
    | .assign (.effect eff) e => allAcceptable #[classifyStatement (.assign (.effect (Effect.contextRead .userId)) (.local ""))] && scalarFragmentEffect eff && scalarFragmentExpr e
    | .assign other e => allAcceptable #[classifyStatement (.assign other e)]
    | .assignOp (.local _) op e => allAcceptable #[classifyStatement (.assignOp (.local "") .add (.local ""))] && scalarFragmentAssignOp op && scalarFragmentExpr e
    | .assignOp (.effect eff) op e => allAcceptable #[classifyStatement (.assignOp (.effect (Effect.contextRead .userId)) .add (.local ""))] && scalarFragmentEffect eff && scalarFragmentAssignOp op && scalarFragmentExpr e
    | .assignOp other _ _ => allAcceptable #[classifyStatement (.assignOp other .add (.local ""))]
    | .effect eff => allAcceptable #[classifyStatement (.effect (Effect.contextRead .userId))] && scalarFragmentEffect eff
    | .assert c _ r? => allAcceptable #[classifyStatement (.assert (.local "") "" none)] && scalarFragmentExpr c && r?.all scalarFragmentErrorRef
    | .assertEq l r _ r? => allAcceptable #[classifyStatement (.assertEq (.local "") (.local "") "" none)] && scalarFragmentExpr l && scalarFragmentExpr r && r?.all scalarFragmentErrorRef
    | .revert _ => allAcceptable #[classifyStatement (.revert "")]
    | .revertWithError r => allAcceptable #[classifyStatement (.revertWithError { assertionId := 0 })] && scalarFragmentErrorRef r
    | .release _ => allAcceptable #[classifyStatement (.release "")]
    | .ifElse c t e =>
        match t, e with
        | ⟨t⟩, ⟨e⟩ => allAcceptable #[classifyStatement (.ifElse (.local "") #[] #[])] && scalarFragmentExpr c && scalarFragmentStatementList t && scalarFragmentStatementList e
    | .boundedFor _ _ _ body =>
        match body with
        | ⟨body⟩ => allAcceptable #[classifyStatement (.boundedFor "" 0 0 #[])] && scalarFragmentStatementList body
    | .whileLoop c body =>
        match body with
        | ⟨body⟩ => allAcceptable #[classifyStatement (.whileLoop (.local "") #[])] && scalarFragmentExpr c && scalarFragmentStatementList body
    | .return e => allAcceptable #[classifyStatement (.return (.local ""))] && scalarFragmentExpr e
end

/-- The scalar fragment accepts contracts whose module uses only scalar storage
and runtime nodes classified as preserve or normalize. -/
def legacyScalarFragmentB (spec : ContractSpec) : Bool :=
  let m := spec.module
  m.state.all (fun s => s.kind == .scalar && scalarFragmentValueType s.type) &&
  m.entrypoints.all (fun ep =>
    ep.params.all (fun (_, ty) => scalarFragmentValueType ty) &&
    scalarFragmentValueType ep.returns &&
    ep.body.all scalarFragmentStatement)

def LegacyScalarFragment (spec : ContractSpec) : Prop :=
  legacyScalarFragmentB spec = true

/-- Run one legacy entrypoint, converting an out-of-range scalar result into a
revert so that it can be related to Core checked-arithmetic errors. -/
def executeLegacyEntrypoint (spec : ContractSpec) (entrypointName : String)
    (args : Array ProofForge.IR.Semantics.Value)
    (prevState : ProofForge.IR.Semantics.State) :
    ProofForge.IR.Semantics.ExecResult (ProofForge.IR.Semantics.State × Option ProofForge.IR.Semantics.Value) :=
  match spec.module.entrypoints.find? (·.name == entrypointName) with
  | none => .error s!"unknown entrypoint `{entrypointName}`"
  | some ep =>
      let r := ProofForge.IR.Semantics.runEntrypointWithArgsResult prevState ep args
      match r with
      | .ok (s, v) =>
          let allInRange :=
            s.storage.all (fun (_, val) => legacyValueInRange val) &&
            v.all legacyValueInRange
          if allInRange then .ok (s, v) else .reverted "revert: arithmetic overflow"
      | .reverted msg => .reverted msg
      | .error msg => .error msg

/-- Relate a legacy return value (if any) to a Core return value. -/
def returnValueRelation (legacy : Option ProofForge.IR.Semantics.Value) (core : CoreValue) : Bool :=
  match legacy with
  | none => core == .unit
  | some lv =>
      match legacyToCoreValue lv with
      | some cv => cv == core
      | none => false

/-- Relate legacy and Core logical states by source state name. Only scalar
storage is considered, which matches the scalar fragment. -/
def StateRelation (spec : ContractSpec) (coreModule : Core.Module)
    (legacy : ProofForge.IR.Semantics.State) (core : LogicalState) : Bool :=
  Id.run do
    for i in [:spec.module.state.size] do
      let decl := spec.module.state[i]?.getD { id := "", kind := .scalar, type := .unit }
      let sid := StateId.mk i
      let legacyVal? := legacy.read decl.id
      match getStateCell coreModule core sid with
      | .error _ => return false
      | .ok (.scalar cv) =>
          match legacyVal? with
          | some lv =>
              match legacyToCoreValue lv with
              | some lv' => unless lv' == cv do return false
              | none => return false
          | none =>
              match coreModule.state.find? (·.id == sid) with
              | some { shape := .scalar ty, .. } =>
                  unless cv == typeDefaultForModule coreModule ty do return false
              | _ => return false
      | .ok _ => return false
    return true

/-- Relate the ordered event trace. Indexed fields are empty in the scalar
fragment because only `.eventEmit` is used. -/
def eventTraceRelation (spec : ContractSpec)
    (legacyLogs : Array ProofForge.IR.Semantics.EventLog)
    (coreTrace : ObservableTrace) : Bool :=
  let coreEvents := coreTrace.effects.filterMap (fun e =>
    match e with
    | .emit id args => some (id, args)
    | _ => none)
  if legacyLogs.size != coreEvents.size then false
  else
    legacyLogs.zip coreEvents |>.all (fun (log, (eid, args)) =>
      match sourceEventName spec eid with
      | none => false
      | some name =>
          name == log.name &&
          log.indexed.isEmpty &&
          match (args : Array CoreValue).mapM coreScalarToLegacyValue with
          | none => false
          | some legacyArgs => log.data == legacyArgs)

/-- Decidable observable relation between a legacy execution result and a Core
execution result. Target layout and internal value ids are intentionally
excluded. -/
def observableMatch (spec : ContractSpec)
    (legacy : ProofForge.IR.Semantics.ExecResult (ProofForge.IR.Semantics.State × Option ProofForge.IR.Semantics.Value))
    (core : Except RuntimeError ExecutionResult) : Bool :=
  match adaptLegacy spec with
  | .error _ => false
  | .ok bundle =>
      let coreModule := bundle.contract.contract.module
      match legacy, core with
      | .ok (legacyState, legacyReturn), .ok coreRes =>
          StateRelation spec coreModule legacyState coreRes.finalState &&
          returnValueRelation legacyReturn coreRes.returnValue &&
          eventTraceRelation spec legacyState.logs coreRes.trace
      | .reverted _, .error (.explicitRevert _) => true
      | .reverted msg, .error (.assertionFailure _) =>
          msg.startsWith "assertion failed:" || msg.startsWith "revert:"
      | .reverted "revert: arithmetic overflow", .error .arithmeticOverflow => true
      | .error _, .error _ => true
      | _, _ => false

def ObservableRelation (spec : ContractSpec)
    (legacy : ProofForge.IR.Semantics.ExecResult (ProofForge.IR.Semantics.State × Option ProofForge.IR.Semantics.Value))
    (core : Except RuntimeError ExecutionResult) : Prop :=
  observableMatch spec legacy core

/-- The executable matcher is a decision procedure for the observable
relation. This is intentionally weaker than a Legacy-to-Core simulation
theorem: such a theorem must quantify over related initial states and a host
contract, not arbitrary hosts, fuel, and an unrelated empty Core state. -/
theorem observableRelation_of_match
    (spec : ContractSpec)
    (legacy : ProofForge.IR.Semantics.ExecResult
      (ProofForge.IR.Semantics.State × Option ProofForge.IR.Semantics.Value))
    (core : Except RuntimeError ExecutionResult)
    (h : observableMatch spec legacy core = true) :
    ObservableRelation spec legacy core :=
  h

end ProofForge.IR.Legacy.Refinement
