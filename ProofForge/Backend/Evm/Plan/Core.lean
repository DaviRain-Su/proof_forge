import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Plan.Storage
import ProofForge.Target.Plan

/-! # Build Existing EVM Plan from Canonical Core

This module maps a `CheckedCanonicalContract` to the existing EVM `ModulePlan`.
It does not create a parallel plan type — it reuses `Evm.Plan.ModulePlan`,
`ExprPlan`, `EffectPlan`, and `StmtPlan` directly.

The Core builder must not consume `IR.Expr`, `IR.Effect`, `IR.Statement`, or
`IR.Module`. All input is typed Core ANF/CFG.
-/

namespace ProofForge.Backend.Evm.Plan.Core

open ProofForge.IR.Core
open ProofForge.IR
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Evm.Plan

/-- Map a Core type to an EVM ValueType. -/
def coreTypeToValueType : CoreType → ValueType
  | .unit => .unit
  | .bool => .bool
  | .u8 => .u8
  | .u32 => .u32
  | .u64 => .u64
  | .u128 => .u128
  | .address => .address
  | .bytes => .bytes
  | .string => .string
  | .hash => .hash
  | .fixedArray elem len => .fixedArray (coreTypeToValueType elem) len
  | .array elem => .array (coreTypeToValueType elem)
  | .memoryRef elem => .array (coreTypeToValueType elem)
  | .structType tid => .structType (toString tid.value)

/-- Infer the EVM ValueType from a Core literal. -/
def coreLiteralType : CoreLiteral → ValueType
  | .unitLit => .unit
  | .boolLit _ => .bool
  | .u8Lit _ => .u8
  | .u32Lit _ => .u32
  | .u64Lit _ => .u64
  | .u128Lit _ => .u128
  | .addressLit _ => .address
  | .bytesLit _ => .bytes
  | .stringLit _ => .string
  | .hashLit _ => .hash

/-- Map a Core literal to an EVM ExprPlan literal. -/
def coreLiteralToExprPlan : CoreLiteral → ExprPlan
  | .unitLit => .literalWord 0
  | .boolLit b => .literalWord (if b then 1 else 0)
  | .u8Lit n => .literalWord n
  | .u32Lit n => .literalWord n
  | .u64Lit n => .literalWord n
  | .u128Lit n => .literalWord n
  | .addressLit _ => .literalWord 0
  | .bytesLit _ => .literalWord 0
  | .stringLit _ => .literalWord 0
  | .hashLit _ => .literalWord 0

/-- Map a Core arithmetic op to the EVM assign op. -/
def coreArithToAssignOp : ArithmeticOp → AssignOp
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .and => .bitAnd
  | .or => .bitOr
  | .xor => .bitXor
  | .shl => .shiftLeft
  | .shr => .shiftRight

/-- Map a Core compare op to the EVM builtin name. -/
def coreCompareToBuiltin : CompareOp → String
  | .eq => "eq"
  | .ne => "ne"
  | .lt => "lt"
  | .le => "le"
  | .gt => "gt"
  | .ge => "ge"

/-- Map a Core context field to the EVM context expr plan.
`msg.value` maps to `ExprPlan.nativeValue`, not a context field — returned
as `none` so the caller can special-case it. -/
def coreContextToPlan? : Core.ContextField → Option ContextExprPlan
  | .sender => some .userId
  | .blockNumber => some .checkpointId
  | .blockTimestamp => some .timestamp
  | .gas => some .gasLeft
  | .contractAddress => some .contractId
  | .value => none  -- handled via ExprPlan.nativeValue, not a context field

/-- Derive the result name for an instruction from its result ValueDef array. -/
private def resultName (instr : Instruction) : String :=
  match instr.results[0]? with
  | some r => s!"v{r.id.value}"
  | none => "_"

/-- Compute the slot span for a Core state declaration.
Mirrors the existing `stateSlotSpan` logic: scalar/map/dynamicArray = 1,
fixedArray = length (× struct field count if element is a struct). -/
def coreStateSlotSpan (m : Core.Module) (decl : Core.StateDecl) : Nat :=
  match decl.shape with
  | .scalar _ => 1
  | .map _ _ _ => 1
  | .fixedArray elem len =>
      match elem with
      | .structType tid =>
          match m.structs.find? (fun s => s.id == tid) with
          | some s => len * s.fields.size
          | none => len
      | _ => len
  | .dynamicArray _ => 1
  | .record tid =>
      match m.structs.find? (fun s => s.id == tid) with
      | some s => s.fields.size
      | none => 1

/-- Build a StorageLayout from Core state declarations.
Logical StateId values are assigned slots in declaration order (0, 1, 2, ...).
The `StateKind` and slot span are preserved from the Core `StateShape` so
downstream helper discovery and Yul slot math work correctly. -/
def coreStorageLayout (module : Core.Module) : StorageLayout := {
  states := module.state.mapIdx fun idx decl =>
    let vt : ValueType := match decl.shape with
      | .scalar ty => coreTypeToValueType ty
      | .map _ vty _ => coreTypeToValueType vty
      | .fixedArray elem _ => coreTypeToValueType elem
      | .dynamicArray elem => coreTypeToValueType elem
      | .record tid =>
          match module.structs.find? (fun s => s.id == tid) with
          | some s =>
              match s.fields[0]? with
              | some f => coreTypeToValueType f.type
              | none => .u64
          | none => .u64
    let kind : StateKind := match decl.shape with
      | .scalar _ => StateKind.scalar
      | .map kty _ cap => StateKind.map (coreTypeToValueType kty) (cap.getD 0)
      | .fixedArray _ len => StateKind.array len
      | .dynamicArray _ => StateKind.dynamicArray
      | .record _ => StateKind.scalar
    { id := toString decl.id.value, slot := idx,
      span := coreStateSlotSpan module decl, kind, type := vt }
}

/-- Map a Core instruction op to EVM StmtPlan entries.
Scalar load/store, context read, arithmetic, event emit, assert, and return
are mapped. Unsupported ops fail closed. -/
def coreInstructionToStmtPlans (instr : Instruction) :
    Except PlanError (Array StmtPlan) :=
  match instr.op with
  | .pure (.literal lit) =>
      .ok #[StmtPlan.letBind (resultName instr) (coreLiteralType lit)
        (coreLiteralToExprPlan lit)]
  | .pure (.unary op arg) =>
      let argExpr := .local s!"v{arg.id.value}"
      match op with
      | .not => .ok #[StmtPlan.letBind (resultName instr) .bool
        (.builtin "not" #[argExpr])]
      | .neg => .ok #[StmtPlan.letBind (resultName instr) .u64
        (.builtin "sub" #[.literalWord 0, argExpr])]
  | .pure (.arithmetic op mode lhs rhs) =>
      let lhsExpr := .local s!"v{lhs.id.value}"
      let rhsExpr := .local s!"v{rhs.id.value}"
      let checked := mode == .checked
      /- Result type follows the operand type (both sides must agree in
      well-typed Core). -/
      let vt := coreTypeToValueType lhs.type
      .ok #[StmtPlan.letBind (resultName instr) vt
        (.checkedArith (coreArithToAssignOp op) lhsExpr rhsExpr checked none)]
  | .pure (.compare op lhs rhs) =>
      let lhsExpr := .local s!"v{lhs.id.value}"
      let rhsExpr := .local s!"v{rhs.id.value}"
      .ok #[StmtPlan.letBind (resultName instr) .bool
        (.builtin (coreCompareToBuiltin op) #[lhsExpr, rhsExpr])]
  | .pure (.cast toType arg) =>
      let vt := coreTypeToValueType toType
      .ok #[StmtPlan.letBind (resultName instr) vt
        (.cast (.local s!"v{arg.id.value}") vt)]
  | .pure (.hash arg) =>
      .ok #[StmtPlan.letBind (resultName instr) .hash
        (.hash (.local s!"v{arg.id.value}"))]
  | .storageLoad path =>
      if !path.path.isEmpty then
        .error { message := "storageLoad with non-scalar path not yet supported in EVM Core plan builder" }
      else
        let sid := path.root.value
        let vt := coreTypeToValueType path.resultType
        .ok #[StmtPlan.letBind (resultName instr) vt
          (.storageLoad (.scalarSlot sid))]
  | .storageStore path value =>
      if !path.path.isEmpty then
        .error { message := "storageStore with non-scalar path not yet supported in EVM Core plan builder" }
      else
        let sid := path.root.value
        .ok #[StmtPlan.effect (.storageScalarWrite (toString sid)
          (.local s!"v{value.id.value}"))]
  | .contextRead field =>
      match coreContextToPlan? field with
      | some ctxPlan =>
          .ok #[StmtPlan.letBind (resultName instr) .u64 (.context ctxPlan)]
      | none =>
          /- `.value` has no ContextExprPlan variant; it maps to
          `ExprPlan.nativeValue`. -/
          .ok #[StmtPlan.letBind (resultName instr) .u64 .nativeValue]
  | .emit event args =>
      let eventPlan := EventPlan.mk s!"event{event.value}" s!"Event{event.value}()" #[]
      let dataFields := args.map fun a => AbiValuePlan.expr (.local s!"v{a.id.value}")
      .ok #[StmtPlan.effect (.eventEmit eventPlan dataFields)]
  | .assert cond error =>
      /- Core's CoreErrorRef has `id : ErrorId` and `args : Array ValueRef`.
      The EVM StmtPlan.assert wants an `Option ProofForge.IR.ErrorRef`, which
      has `assertionId : UInt32` and `userCode? : Option String`. We map the
      Core error id (a Nat) to `assertionId` as a UInt32. -/
      let errRef : ProofForge.IR.ErrorRef := {
        assertionId := UInt32.ofNat error.id.value
        userCode? := none
      }
      .ok #[StmtPlan.assert (.local s!"v{cond.id.value}")
        s!"assertion failed" (some errRef)]
  | .hostCall _ =>
      .error { message := "hostCall not yet supported in EVM Core plan builder" }
  | .crosscall _ _ =>
      .error { message := "crosscall not yet supported in EVM Core plan builder" }
  | .storageContains _ =>
      .error { message := "storageContains not yet supported in EVM Core plan builder" }
  | .storageLength _ =>
      .error { message := "storageLength not yet supported in EVM Core plan builder" }
  | .storageResize _ _ =>
      .error { message := "storageResize not yet supported in EVM Core plan builder" }
  | .memoryAlloc _ _ =>
      .error { message := "memoryAlloc not yet supported in EVM Core plan builder" }
  | .memoryLoad _ _ =>
      .error { message := "memoryLoad not yet supported in EVM Core plan builder" }
  | .memoryStore _ _ _ =>
      .error { message := "memoryStore not yet supported in EVM Core plan builder" }
  | .memoryRelease _ =>
      .error { message := "memoryRelease not yet supported in EVM Core plan builder" }

/-- Map a Core function to EVM entrypoint plan entries (body statements).
Only the entry block is mapped for the initial fragment; control flow
mapping (branches, loops) will be added as needed. -/
def coreFunctionToStmtPlans (func : Function) : Except PlanError (Array StmtPlan) := do
  let mut stmts := #[]
  for block in func.blocks do
    if block.id == func.entry then
      for instr in block.instructions do
        let ss ← coreInstructionToStmtPlans instr
        stmts := stmts ++ ss
      /- Map the terminator: return produces a return stmt. -/
      match block.terminator with
      | .return vals =>
          if vals.isEmpty then
            stmts := stmts.push (StmtPlan.return (.literalWord 0))
          else
            stmts := stmts.push (StmtPlan.return (.local s!"v{vals[0]!.id.value}"))
      | _ => pure () -- other terminators handled in control-flow mapping
      break
  .ok stmts

/-- Map a Core InterfaceEntrypoint to an EVM EntrypointPlan. -/
def coreEntrypointToPlan (m : Core.Module) (ep : InterfaceEntrypoint) :
    Except PlanError EntrypointPlan := do
  /- Find the Core function by functionId. -/
  match m.functions.find? (fun f => f.id == ep.functionId) with
  | none => .error { message := s!"entrypoint {ep.name} references unknown function {ep.functionId.value}" }
  | some func =>
      let body ← coreFunctionToStmtPlans func
      let selector := ep.selector?.getD ""
      let params := ep.params.mapIdx fun idx p =>
        { name := p.name, type := coreTypeToValueType p.type,
          abiWord? := none, wordTypes := #[coreTypeToValueType p.type],
          headWordIndex := idx, localNames := #[p.name] : AbiParamPlan }
      let returnType := coreTypeToValueType ep.retType
      .ok {
        name := ep.name
        selector
        params
        returns := { returnType, wordTypes := #[returnType], localNames := #[] }
        body
      }

/-- Build an EVM ModulePlan from a checked canonical contract.
This reuses the existing ModulePlan structure — no parallel plan types. -/
def buildFromCore (checked : CheckedCanonicalContract)
    (capPlan : CapabilityPlan) :
    Except PlanError ModulePlan := do
  if capPlan.targetId != ProofForge.Target.evm.id then
    .error { message := s!"EVM buildFromCore requires target `{ProofForge.Target.evm.id}`, got `{capPlan.targetId}`" }
  let m := checked.contract.module
  let iface := checked.contract.interface
  /- Build storage layout from Core state declarations. -/
  let storage := coreStorageLayout m
  /- Build entrypoint plans from interface. -/
  let mut entrypoints := #[]
  for ep in iface.entrypoints do
    let epPlan ← coreEntrypointToPlan m ep
    entrypoints := entrypoints.push epPlan
  /- Build event plans from interface. -/
  let events := iface.events.map fun ev =>
    EventPlan.mk ev.name
      (s!"{ev.name}({String.intercalate "," (ev.fields.map (fun f => f.name)).toList})")
      (ev.fields.map fun f => EventFieldPlan.mk f.name (coreTypeToValueType f.type) f.indexed)
  /- Determine if any entrypoint uses checked arithmetic. -/
  let usesCheckedArithmetic := entrypoints.any fun ep =>
    ep.body.any fun s => match s with
      | .letBind _ _ (.checkedArith _ _ _ true _) => true
      | _ => false
  .ok {
    name := iface.contractName
    targetPlan := capPlan
    storage
    helpers := #[]
    mapAssignOps := #[]
    entrypoints
    dispatch := { entrypoints, default := .revert }
    events
    crosscalls := #[]
    creates := #[]
    localArrayGetLengths := #[]
    nestedLocalArrayGetShapes := #[]
    usesCheckedArithmetic
    overflowChecked := usesCheckedArithmetic
    metadata := {
      moduleName := iface.contractName
      entrypoints
      events
      capabilities := capPlan.capabilities
    }
    contextOps := #[]
  }

end ProofForge.Backend.Evm.Plan.Core