import Lean
import ProofForgeV2.Core.Source
import ProofForgeV2.Language.ProgramExport

open Lean

namespace ProofForgeV2.Language.ProgramPayload

open ProofForgeV2
open ProofForgeV2.Language.ProgramExport

private def exportError (detail : String) : String :=
  s!"PF-EXPORT-004: {detail}"

private def unsupported {α : Type} : Except String α :=
  .error (exportError "unsupported quoted Source.Program form")

private def boundExceeded {α : Type} : Except String α :=
  .error (exportError "program payload structural bound exceeded")

private def unavailable {α : Type} : Except String α :=
  .error (exportError "declaration unavailable or unsafe")

private def identityError (detail : String) : String :=
  s!"PF-EXPORT-001: {detail}"

private def maxRawNodes : Nat := 100000
private def maxLogicalDepth : Nat := 256

private def isPolymorphicWrapper (name : Lean.Name) : Bool :=
  name == ``List.toArray || name == ``List.nil || name == ``List.cons ||
    name == ``Option.none || name == ``Option.some || name == ``OfNat.ofNat

private def hasExactLevels (name : Lean.Name) (levels : List Lean.Level) : Bool :=
  if isPolymorphicWrapper name then levels == [Lean.Level.zero] else levels.isEmpty

/-- Reject outer mdata on data positions; match const head + exact levels + full arity list. -/
private def appView (expr : Lean.Expr) : Option (Lean.Name × List Lean.Expr) :=
  match expr with
  | .mdata .. => none
  | _ =>
    match expr.getAppFn with
    | .const name levels =>
        if hasExactLevels name levels then some (name, expr.getAppArgs.toList) else none
    | _ => none

private def checkRawNodeBound (root : Lean.Expr) : Except String Unit := do
  let mut stack := #[root]
  let mut count := 0
  while !stack.isEmpty do
    let expr := stack.back!
    stack := stack.pop
    count := count + 1
    if count > maxRawNodes then
      return ← boundExceeded
    match expr with
    | .app fn arg => stack := stack.push fn |>.push arg
    | .lam _ type body _ | .forallE _ type body _ =>
        stack := stack.push type |>.push body
    | .letE _ type value body _ =>
        stack := stack.push type |>.push value |>.push body
    | .mdata _ body => stack := stack.push body
    | .proj _ _ struct => stack := stack.push struct
    | _ => pure ()

private def decodeString (expr : Lean.Expr) : Except String String :=
  match expr with
  | .lit (.strVal value) => pure value
  | _ => unsupported

private def decodeRawNat (expr : Lean.Expr) : Except String Nat :=
  match expr with
  | .lit (.natVal value) => pure value
  | _ => unsupported

private def decodeNat (expr : Lean.Expr) : Except String Nat := do
  match expr with
  | .lit (.natVal value) => pure value
  | _ =>
      match appView expr with
      | some (``OfNat.ofNat, [type, literal, instanceExpr]) =>
          unless type.consumeMData == mkConst ``Nat do
            return ← unsupported
          let value ← decodeRawNat literal
          match appView instanceExpr with
          | some (``instOfNatNat, [sameLiteral]) =>
              unless (← decodeRawNat sameLiteral) == value do
                return ← unsupported
              pure value
          | _ => unsupported
      | _ => unsupported

private def decodeUInt32 (expr : Lean.Expr) : Except String UInt32 := do
  match appView expr with
  | some (``UInt32.ofNat, [valueExpr]) =>
      let value ← decodeNat valueExpr
      if value < 2 ^ 32 then pure (UInt32.ofNat value) else unsupported
  | _ => unsupported

private def decodeUInt64 (expr : Lean.Expr) : Except String UInt64 := do
  match appView expr with
  | some (``UInt64.ofNat, [valueExpr]) =>
      let value ← decodeNat valueExpr
      if value < 2 ^ 64 then pure (UInt64.ofNat value) else unsupported
  | _ => unsupported

private def decodeFin4097 (expectedType : Lean.Name) (expr : Lean.Expr) :
    Except String (Fin 4097) := do
  match appView expr with
  | some (``OfNat.ofNat, [typeExpr, literal, instanceExpr]) =>
      unless typeExpr.consumeMData == mkConst expectedType do
        return ← unsupported
      let value ← decodeRawNat literal
      match appView instanceExpr with
      | some (``Fin.instOfNat, [instanceBound, _proof, instanceLiteral]) =>
          unless (← decodeNat instanceBound) == 4097 do
            return ← unsupported
          unless (← decodeRawNat instanceLiteral) == value do
            return ← unsupported
      | _ => return ← unsupported
      if h : value < 4097 then pure ⟨value, h⟩ else unsupported
  | _ => unsupported

private def decodeArray (decode : Lean.Expr → Except String α) (expr : Lean.Expr) :
    Except String (Array α) := do
  let rest0 ← match appView expr with
    | some (``List.toArray, [_type, list]) => pure list
    | _ => unsupported
  let mut rest := rest0
  let mut result := #[]
  let mut done := false
  while !done do
    match appView rest with
    | some (``List.nil, [_type]) => done := true
    | some (``List.cons, [_type, head, tail]) =>
        result := result.push (← decode head)
        rest := tail
    | _ => return ← unsupported
  pure result

private def decodeOption (decode : Lean.Expr → Except String α) (expr : Lean.Expr) :
    Except String (Option α) :=
  match appView expr with
  | some (``Option.none, [_type]) => pure none
  | some (``Option.some, [_type, value]) => some <$> decode value
  | _ => unsupported

private def decodeValueTypeAt (fuel : Nat) (expr : Lean.Expr) :
    Except String Source.ValueType :=
  match fuel with
  | 0 => boundExceeded
  | next + 1 => do
    match appView expr with
    | some (``Source.ValueType.u64, []) => pure .u64
    | some (``Source.ValueType.bool, []) => pure .bool
    | some (``Source.ValueType.field, []) => pure .field
    | some (``Source.ValueType.u8, []) => pure .u8
    | some (``Source.ValueType.u16, []) => pure .u16
    | some (``Source.ValueType.u32, []) => pure .u32
    | some (``Source.ValueType.u128, []) => pure .u128
    | some (``Source.ValueType.u256, []) => pure .u256
    | some (``Source.ValueType.i8, []) => pure .i8
    | some (``Source.ValueType.i16, []) => pure .i16
    | some (``Source.ValueType.i32, []) => pure .i32
    | some (``Source.ValueType.i64, []) => pure .i64
    | some (``Source.ValueType.i128, []) => pure .i128
    | some (``Source.ValueType.i256, []) => pure .i256
    | some (``Source.ValueType.unit, []) => pure .unit
    | some (``Source.ValueType.principal, []) => pure .principal
    | some (``Source.ValueType.option, [element]) =>
      .option <$> decodeValueTypeAt next element
    | some (``Source.ValueType.bytes, [length]) =>
      .bytes <$> decodeUInt32 length
    | some (``Source.ValueType.array, [element, length]) =>
      return .array (← decodeValueTypeAt next element)
        (← decodeFin4097 ``Source.ArrayLength length)
    | _ => unsupported

private def decodeValueType (expr : Lean.Expr) : Except String Source.ValueType :=
  decodeValueTypeAt maxLogicalDepth expr

private def decodeVisibility (expr : Lean.Expr) : Except String Source.Visibility :=
  match appView expr with
  | some (``Source.Visibility.verifierVisible, []) => pure .verifierVisible
  | some (``Source.Visibility.proverWitness, []) => pure .proverWitness
  | some (``Source.Visibility.commitmentOnly, []) => pure .commitmentOnly
  | _ => unsupported

private def decodeParam (expr : Lean.Expr) : Except String Source.Param := do
  match appView expr with
  | some (``Source.Param.mk, [name, type, visibility]) =>
      pure (.mk (← decodeString name) (← decodeValueType type) (← decodeVisibility visibility))
  | _ => unsupported

private def decodeStateDecl (expr : Lean.Expr) : Except String Source.StateDecl := do
  match appView expr with
  | some (``Source.StateDecl.mk, [name, type, visibility]) =>
      pure (.mk (← decodeString name) (← decodeValueType type) (← decodeVisibility visibility))
  | _ => unsupported

private def decodeFieldDecl (expr : Lean.Expr) : Except String Source.FieldDecl := do
  match appView expr with
  | some (``Source.FieldDecl.mk, [name, type]) =>
      pure (.mk (← decodeString name) (← decodeValueType type))
  | _ => unsupported

private def decodeStructDecl (expr : Lean.Expr) : Except String Source.StructDecl := do
  match appView expr with
  | some (``Source.StructDecl.mk, [name, fields]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeFieldDecl fields))
  | _ => unsupported

private def decodeEnumVariant (expr : Lean.Expr) : Except String Source.EnumVariant := do
  match appView expr with
  | some (``Source.EnumVariant.mk, [name, payloadTypes]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeValueType payloadTypes))
  | _ => unsupported

private def decodeEnumDecl (expr : Lean.Expr) : Except String Source.EnumDecl := do
  match appView expr with
  | some (``Source.EnumDecl.mk, [name, variants]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeEnumVariant variants))
  | _ => unsupported

private def decodeEventDecl (expr : Lean.Expr) : Except String Source.EventDecl := do
  match appView expr with
  | some (``Source.EventDecl.mk, [name, params]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeParam params))
  | _ => unsupported

private def decodeErrorDecl (expr : Lean.Expr) : Except String Source.ErrorDecl := do
  match appView expr with
  | some (``Source.ErrorDecl.mk, [name, params]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeParam params))
  | _ => unsupported

private def binaryExprCtor? (name : Lean.Name) :
    Option (Source.Expr → Source.Expr → Source.Expr) :=
  if name == ``Source.Expr.checkedAdd then some Source.Expr.checkedAdd
  else if name == ``Source.Expr.checkedSub then some Source.Expr.checkedSub
  else if name == ``Source.Expr.checkedMul then some Source.Expr.checkedMul
  else if name == ``Source.Expr.checkedDiv then some Source.Expr.checkedDiv
  else if name == ``Source.Expr.checkedMod then some Source.Expr.checkedMod
  else if name == ``Source.Expr.shiftLeft then some Source.Expr.shiftLeft
  else if name == ``Source.Expr.shiftRight then some Source.Expr.shiftRight
  else if name == ``Source.Expr.equal then some Source.Expr.equal
  else if name == ``Source.Expr.notEqual then some Source.Expr.notEqual
  else if name == ``Source.Expr.lessThan then some Source.Expr.lessThan
  else if name == ``Source.Expr.lessEqual then some Source.Expr.lessEqual
  else if name == ``Source.Expr.greaterThan then some Source.Expr.greaterThan
  else if name == ``Source.Expr.greaterEqual then some Source.Expr.greaterEqual
  else if name == ``Source.Expr.bitwiseAnd then some Source.Expr.bitwiseAnd
  else if name == ``Source.Expr.bitwiseXor then some Source.Expr.bitwiseXor
  else if name == ``Source.Expr.bitwiseOr then some Source.Expr.bitwiseOr
  else if name == ``Source.Expr.logicalAnd then some Source.Expr.logicalAnd
  else if name == ``Source.Expr.logicalOr then some Source.Expr.logicalOr
  else none

private def decodeExprAt (fuel : Nat) (expr : Lean.Expr) : Except String Source.Expr :=
  match fuel with
  | 0 => boundExceeded
  | next + 1 => do
    match appView expr with
    | some (``Source.Expr.literal, [value]) => .literal <$> decodeUInt64 value
    | some (``Source.Expr.variable, [name]) => .variable <$> decodeString name
    | some (``Source.Expr.state, [name]) => .state <$> decodeString name
    | some (``Source.Expr.boolLiteral, [value]) =>
      match appView value with
      | some (``Bool.true, []) => pure (.boolLiteral true)
      | some (``Bool.false, []) => pure (.boolLiteral false)
      | _ => unsupported
    | some (``Source.Expr.stringLiteral, [value]) => .stringLiteral <$> decodeString value
    | some (``Source.Expr.localFnCall, [callee, args]) =>
      return .localFnCall (← decodeString callee) (← decodeArray (decodeExprAt next) args)
    | some (``Source.Expr.constructorExpr, [path, args]) =>
      return .constructorExpr (← decodeArray decodeString path)
        (← decodeArray (decodeExprAt next) args)
    | some (``Source.Expr.indexAccess, [base, index]) =>
      return .indexAccess (← decodeString base) (← decodeExprAt next index)
    | some (``Source.Expr.checkedNeg, [operand]) => .checkedNeg <$> decodeExprAt next operand
    | some (``Source.Expr.bitwiseNot, [operand]) => .bitwiseNot <$> decodeExprAt next operand
    | some (``Source.Expr.logicalNot, [operand]) => .logicalNot <$> decodeExprAt next operand
    | some (ctor, [lhsExpr, rhsExpr]) =>
      let some make := binaryExprCtor? ctor | return ← unsupported
      pure (make (← decodeExprAt next lhsExpr) (← decodeExprAt next rhsExpr))
    | _ => unsupported

private def decodeExpr (expr : Lean.Expr) : Except String Source.Expr :=
  decodeExprAt maxLogicalDepth expr

private def decodeConstDecl (expr : Lean.Expr) : Except String Source.ConstDecl := do
  match appView expr with
  | some (``Source.ConstDecl.mk, [name, type, value]) =>
      pure (.mk (← decodeString name) (← decodeValueType type) (← decodeExpr value))
  | _ => unsupported

private def decodeStatementAt (fuel : Nat) (expr : Lean.Expr) :
    Except String Source.Statement :=
  match fuel with
  | 0 => boundExceeded
  | next + 1 => do
    let decodeNested := decodeArray (decodeStatementAt next)
    match appView expr with
    | some (``Source.Statement.assign, [name, value]) =>
      return .assign (← decodeString name) (← decodeExprAt next value)
    | some (``Source.Statement.returnValue, [value]) =>
      .returnValue <$> decodeExprAt next value
    | some (``Source.Statement.returnUnit, []) => pure .returnUnit
    | some (``Source.Statement.synchronousCall, [callee]) =>
      .synchronousCall <$> decodeString callee
    | some (``Source.Statement.letDecl, [name, typeAnn, value]) =>
      return .letDecl (← decodeString name) (← decodeOption (decodeValueTypeAt next) typeAnn)
        (← decodeExprAt next value)
    | some (``Source.Statement.assertStmt, [condition]) =>
      .assertStmt <$> decodeExprAt next condition
    | some (``Source.Statement.assertErrorStmt, [condition, errorName]) =>
      return .assertErrorStmt (← decodeExprAt next condition) (← decodeString errorName)
    | some (``Source.Statement.revertStmt, [errorName, args]) =>
      return .revertStmt (← decodeString errorName) (← decodeArray (decodeExprAt next) args)
    | some (``Source.Statement.emitStmt, [eventName, args]) =>
      return .emitStmt (← decodeString eventName) (← decodeArray (decodeExprAt next) args)
    | some (``Source.Statement.ifStmt, [condition, thenBody, elseBody]) =>
      return .ifStmt (← decodeExprAt next condition) (← decodeNested thenBody)
        (← decodeOption decodeNested elseBody)
    | some (``Source.Statement.forStmt,
        [iterator, start, stopExclusive, maxIterations, body]) =>
      return .forStmt (← decodeString iterator) (← decodeExprAt next start)
        (← decodeExprAt next stopExclusive)
        (← decodeFin4097 ``Source.IterationBound maxIterations) (← decodeNested body)
    | _ => unsupported

private def decodeStatements (expr : Lean.Expr) : Except String (Array Source.Statement) :=
  decodeArray (decodeStatementAt maxLogicalDepth) expr

private def decodeInitializer (expr : Lean.Expr) : Except String Source.Initializer := do
  match appView expr with
  | some (``Source.Initializer.mk, [params, body]) =>
      pure (.mk (← decodeArray decodeParam params) (← decodeStatements body))
  | _ => unsupported

private def decodeEntryMode (expr : Lean.Expr) : Except String Source.EntryMode :=
  match appView expr with
  | some (``Source.EntryMode.mutate, []) => pure .mutate
  | some (``Source.EntryMode.view, []) => pure .view
  | _ => unsupported

private def decodeEntry (expr : Lean.Expr) : Except String Source.Entry := do
  match appView expr with
  | some (``Source.Entry.mk, [name, params, result, mode, body]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeParam params)
        (← decodeValueType result) (← decodeEntryMode mode) (← decodeStatements body))
  | _ => unsupported

private def decodeFnDecl (expr : Lean.Expr) : Except String Source.FnDecl := do
  match appView expr with
  | some (``Source.FnDecl.mk, [name, params, result, body]) =>
      pure (.mk (← decodeString name) (← decodeArray decodeParam params)
        (← decodeValueType result) (← decodeStatements body))
  | _ => unsupported

private def decodeInvariantDecl (expr : Lean.Expr) : Except String Source.InvariantDecl := do
  match appView expr with
  | some (``Source.InvariantDecl.mk, [name, predicate]) =>
      pure (.mk (← decodeString name) (← decodeExpr predicate))
  | _ => unsupported

private def decodeExtensionReq (expr : Lean.Expr) : Except String Source.ExtensionReq := do
  match appView expr with
  | some (``Source.ExtensionReq.mk, [id, version, digest]) =>
      pure (.mk (← decodeString id) (← decodeString version) (← decodeString digest))
  | _ => unsupported

private def decodeProofDecl (expr : Lean.Expr) : Except String Source.ProofDecl := do
  match appView expr with
  | some (``Source.ProofDecl.mk, [invariant, theoremExpr]) =>
      pure (.mk (← decodeString invariant) (← decodeArray decodeString theoremExpr))
  | _ => unsupported

private def decodeProgram (expr : Lean.Expr) : Except String Source.Program := do
  match appView expr with
  | some (``Source.Program.mk,
      [qualifiedName, name, stateExpr, structs, enums, consts, events, errors, initializer,
       entries, functions, invariants, extensionRequirements, proofReferences]) =>
      pure (.mk (← decodeString qualifiedName) (← decodeString name)
        (← decodeArray decodeStateDecl stateExpr) (← decodeArray decodeStructDecl structs)
        (← decodeArray decodeEnumDecl enums) (← decodeArray decodeConstDecl consts)
        (← decodeArray decodeEventDecl events) (← decodeArray decodeErrorDecl errors)
        (← decodeOption decodeInitializer initializer) (← decodeArray decodeEntry entries)
        (← decodeArray decodeFnDecl functions) (← decodeArray decodeInvariantDecl invariants)
        (← decodeArray decodeExtensionReq extensionRequirements)
        (← decodeArray decodeProofDecl proofReferences))
  | _ => unsupported

def decodeQuotedProgramV1 (expr : Lean.Expr) : Except String Source.Program := do
  checkRawNodeBound expr
  decodeProgram expr

private def decodeDeclaration (env : Lean.Environment) (name : Lean.Name) :
    Except String Source.Program := do
  match env.find? name with
  | some (.defnInfo info) =>
      unless info.type == mkConst ``Source.Program do
        return ← unavailable
      match info.safety with
      | .safe => pure ()
      | _ => return ← unavailable
      unless (Lean.Compiler.getImplementedBy? env name).isNone do
        return ← unavailable
      unless (Lean.getExternAttrData? env name).isNone do
        return ← unavailable
      checkRawNodeBound info.value
      if env.hasUnsafe info.value then
        return ← unavailable
      decodeProgram info.value
  | _ => unavailable

def programPayload (env : Lean.Environment) (name : Lean.Name) :
    Except String Source.Program := do
  let exports ← programExports env
  unless exports.any (fun row => row.declaration == name) do
    throw (exportError "not registered")
  decodeDeclaration env name

private def checkProgramIdentities
    (rows : Array (ProgramExportV1 × Source.Program)) : Except String Unit := do
  let mut seen := Std.HashMap.emptyWithCapacity rows.size
  for (_, program) in rows do
    let sourceHash := program.sourceHash
    let (previous, updated) :=
      seen.getThenInsertIfNew? program.qualifiedName sourceHash
    seen := updated
    match previous with
    | none => pure ()
    | some previousHash =>
        if previousHash == sourceHash then
          throw (identityError "duplicate exported program identity")
        else
          throw (identityError "conflicting exported program identity")

def programPayloads (env : Lean.Environment) :
    Except String (Array (ProgramExportV1 × Source.Program)) := do
  let exports ← programExports env
  let mut rows := #[]
  for row in exports do
    rows := rows.push (row, ← decodeDeclaration env row.declaration)
  checkProgramIdentities rows
  pure rows

end ProofForgeV2.Language.ProgramPayload
