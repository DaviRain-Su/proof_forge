import ProofForgeV2.Core.Typed
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ValidatedSourceV1
import Std.Data.HashMap
import Std.Data.HashSet

namespace ProofForgeV2.Typed

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def invalidV1 (message : String) : CompileResult α :=
  .error (.invalidProgram message)

private def unsupportedV1 (tag : String) : CompileResult α :=
  invalidV1 s!"validated ProgramV1 lowering does not support {tag}"

private def raw (name : SourceNameComponentV1) : String := name.raw

private def renderQualified (name : SourceQualifiedNameV1) : String :=
  (NonEmptyArray.toArray name.components).foldl
    (fun acc component => Lean.Name.str acc component.raw) .anonymous |>.toString

private def lowerVisibilityV1 : VisibilityV1 → Source.Visibility
  | .public_ => .verifierVisible
  | .private_ => .proverWitness
  | .commitment => .commitmentOnly

private partial def lowerTypeV1 : TypeV1 → CompileResult Source.ValueType
  | .bool => pure .bool
  | .uint 8 => pure .u8
  | .uint 16 => pure .u16
  | .uint 32 => pure .u32
  | .uint 64 => pure .u64
  | .uint 128 => pure .u128
  | .uint 256 => pure .u256
  | .uint _ => unsupportedV1 "Type.UInt"
  | .int 8 => pure .i8
  | .int 16 => pure .i16
  | .int 32 => pure .i32
  | .int 64 => pure .i64
  | .int 128 => pure .i128
  | .int 256 => pure .i256
  | .int _ => unsupportedV1 "Type.Int"
  | .principal => pure .principal
  | .unit => pure .unit
  | .named _ => unsupportedV1 "Type.Named"
  | .array element length => do
      let element ← lowerTypeV1 element
      if h : length.toNat < 4097 then
        pure (.array element ⟨length.toNat, h⟩)
      else
        unsupportedV1 "Type.Array"
  | .map _ _ => unsupportedV1 "Type.Map"
  | .option element => .option <$> lowerTypeV1 element
  | .bytes length => pure (.bytes length)
  | .field id =>
      if id.raw == "bn254_fr" then pure .field else unsupportedV1 "Type.Field"

private def binaryTagV1 : BinaryOpV1 → String
  | .add => "BinaryOp.Add"
  | .sub => "BinaryOp.Sub"
  | .mul => "BinaryOp.Mul"
  | .div => "BinaryOp.Div"
  | .mod => "BinaryOp.Mod"
  | .eq => "BinaryOp.Eq"
  | .ne => "BinaryOp.Ne"
  | .lt => "BinaryOp.Lt"
  | .le => "BinaryOp.Le"
  | .gt => "BinaryOp.Gt"
  | .ge => "BinaryOp.Ge"
  | .logicalAnd => "BinaryOp.And"
  | .logicalOr => "BinaryOp.Or"
  | .bitAnd => "BinaryOp.BitAnd"
  | .bitOr => "BinaryOp.BitOr"
  | .bitXor => "BinaryOp.BitXor"
  | .shl => "BinaryOp.Shl"
  | .shr => "BinaryOp.Shr"

/-- Validate every supported constructor before name/type checking. This keeps
source-order unsupported diagnostics ahead of all Typed diagnostics without
using a legacy source carrier. -/
private partial def validateExprShapeV1 : ExprV1 → CompileResult Unit
  | .literal (.integer magnitude) =>
      if magnitude < UInt64.size then pure ()
      else invalidV1 "validated ProgramV1 lowering requires a UInt64 integer literal"
  | .literal (.bool _) => unsupportedV1 "Literal.Bool"
  | .literal (.string _) => unsupportedV1 "Literal.String"
  | .place (.name _) => pure ()
  | .place (.field _ _) => unsupportedV1 "Place.Field"
  | .place (.index _ _) => unsupportedV1 "Place.Index"
  | .constructor _ _ => unsupportedV1 "Expr.Constructor"
  | .unary _ _ => unsupportedV1 "Expr.Unary"
  | .binary .add lhs rhs => do
      validateExprShapeV1 lhs
      validateExprShapeV1 rhs
  | .binary op _ _ => unsupportedV1 (binaryTagV1 op)
  | .localCall _ _ => unsupportedV1 "Expr.LocalCall"
  | .match_ _ _ => unsupportedV1 "Expr.Match"

private def validateParamShapeV1
    (param : ProofForgeV2.Source.AstSupportV1.ParamV1) : CompileResult Unit := do
  let _ ← lowerTypeV1 param.type_
  pure ()

private def validateBlockShapeV1 (block : BlockV1) : CompileResult Unit := do
  for statement in block.statements do
    match statement with
    | .assign (.name _) value => validateExprShapeV1 value
    | .assign _ _ => unsupportedV1 "Stmt.Assign"
    | .return_ (some value) => validateExprShapeV1 value
    | .return_ none => unsupportedV1 "Stmt.Return"
    | .call call =>
        if call.args.isEmpty then pure ()
        else invalidV1 "validated ProgramV1 lowering requires zero external call arguments"
    | .let_ .. => unsupportedV1 "Stmt.Let"
    | .if_ .. => unsupportedV1 "Stmt.If"
    | .match_ .. => unsupportedV1 "Stmt.Match"
    | .for_ .. => unsupportedV1 "Stmt.For"
    | .assert_ .. => unsupportedV1 "Stmt.Assert"
    | .revert .. => unsupportedV1 "Stmt.Revert"
    | .emit .. => unsupportedV1 "Stmt.Emit"
    | .schedule .. => unsupportedV1 "Stmt.Schedule"

private def validateSupportedShapeV1 (source : ValidatedSourceV1) : CompileResult Unit := do
  for item in source.program.items do
    match item with
    | .state state =>
        let _ ← lowerTypeV1 state.type_
        pure ()
    | .init init =>
        for param in init.params do validateParamShapeV1 param
        validateBlockShapeV1 init.body
    | .entry entry =>
        for param in entry.params do validateParamShapeV1 param
        let _ ← lowerTypeV1 entry.result
        validateBlockShapeV1 entry.body
    | .view view =>
        for param in view.params do validateParamShapeV1 param
        let _ ← lowerTypeV1 view.result
        validateBlockShapeV1 view.body
    | .struct _ => unsupportedV1 "StructDecl"
    | .enum _ => unsupportedV1 "EnumDecl"
    | .const _ => unsupportedV1 "ConstDecl"
    | .event _ => unsupportedV1 "EventDecl"
    | .error _ => unsupportedV1 "ErrorDecl"
    | .fn _ => unsupportedV1 "FnDecl"
    | .invariant _ => unsupportedV1 "InvariantDecl"
    | .extensionReq _ => unsupportedV1 "ExtensionReq"
    | .proof _ => unsupportedV1 "ProofDecl"

private structure StateEnvV1 where
  ordered : Array StateDecl
  byName : Std.HashMap String StateDecl

private structure ParamEnvV1 where
  ordered : Array Param
  byName : Std.HashMap String Param

private def resolveStatesV1 (owner : String) (items : Array ProgramItemV1) :
    CompileResult StateEnvV1 := do
  let mut ordered : Array StateDecl := #[]
  let mut byName := Std.HashMap.emptyWithCapacity items.size
  for item in items do
    match item with
    | .state declaration =>
        let name := raw declaration.name
        let state : StateDecl := {
          id := ⟨ordered.size⟩
          name
          type := ← lowerTypeV1 declaration.type_
          visibility := lowerVisibilityV1 declaration.visibility
        }
        let (existing, updated) := byName.getThenInsertIfNew? name state
        if existing.isSome then
          throw <| .invalidProgram s!"duplicate state declaration '{name}' in {owner}"
        byName := updated
        ordered := ordered.push state
    | _ => pure ()
  pure { ordered, byName }

private def resolveParamsV1 (owner : String)
    (params : Array ProofForgeV2.Source.AstSupportV1.ParamV1) :
    CompileResult ParamEnvV1 := do
  let mut ordered : Array Param := #[]
  let mut byName := Std.HashMap.emptyWithCapacity params.size
  for sourceParam in params do
    let name := raw sourceParam.name
    let param : Param := {
      id := ⟨ordered.size⟩
      name
      type := ← lowerTypeV1 sourceParam.type_
      visibility := lowerVisibilityV1 sourceParam.visibility
    }
    let (existing, updated) := byName.getThenInsertIfNew? name param
    if existing.isSome then
      throw <| .invalidProgram s!"duplicate parameter '{name}' in {owner}"
    byName := updated
    ordered := ordered.push param
  pure { ordered, byName }

private structure ScopeV1 where
  owner : String
  stateByName : Std.HashMap String StateDecl
  paramByName : Std.HashMap String Param

private partial def checkExprV1 (scope : ScopeV1) : ExprV1 → CompileResult Expr
  | .literal (.integer magnitude) => pure (.literal (UInt64.ofNat magnitude))
  | .place (.name sourceName) =>
      let name := raw sourceName
      match scope.paramByName.get? name with
      | some param => pure (.ref (.param param.id param.type))
      | none =>
          match scope.stateByName.get? name with
          | some state => pure (.ref (.state state.id state.type))
          | none => invalidV1 s!"unknown value '{name}' in {scope.owner}"
  | .binary .add lhs rhs => do
      let lhs ← checkExprV1 scope lhs
      let rhs ← checkExprV1 scope rhs
      unless lhs.type == .u64 && rhs.type == .u64 do
        throw <| .invalidProgram
          s!"checked addition in {scope.owner} requires two UInt64 operands"
      pure (.checkedAdd lhs rhs)
  | expression =>
      -- `validateSupportedShapeV1` owns reachable unsupported diagnostics.
      invalidV1 s!"PF-INTERNAL: unsupported ProgramV1 expression reached Typed: {repr expression}"

private def checkStatementV1 (scope : ScopeV1) (mode : EntryMode) :
    StmtV1 → CompileResult Statement
  | .assign (.name sourceName) value => do
      let name := raw sourceName
      if mode == .view then
        throw <| .invalidProgram s!"view '{scope.owner}' cannot write state '{name}'"
      let state ← match scope.stateByName.get? name with
        | some state => pure state
        | none => invalidV1 (
            s!"assignment target '{name}' in {scope.owner} is not declared state")
      let value ← checkExprV1 scope value
      unless value.type == state.type do
        throw <| .invalidProgram
          s!"assignment to state '{name}' in {scope.owner} has a type mismatch"
      pure (.assign state.id value)
  | .return_ (some value) => .returnValue <$> checkExprV1 scope value
  | .call call =>
      let callee := renderQualified call.callee
      if mode == .view then
        invalidV1 s!"view '{scope.owner}' cannot perform synchronous call '{callee}'"
      else if callee.isEmpty then
        invalidV1 s!"synchronous call target in {scope.owner} cannot be empty"
      else
        pure (.synchronousCall callee)
  | statement =>
      invalidV1 s!"PF-INTERNAL: unsupported ProgramV1 statement reached Typed: {repr statement}"

private def checkInitializerV1 (state : StateEnvV1)
    (initializer : ProofForgeV2.Source.AstSpineDeclV1.InitDeclV1) :
    CompileResult Initializer := do
  let params ← resolveParamsV1 "initializer" initializer.params
  let scope : ScopeV1 := {
    owner := "initializer"
    stateByName := state.byName
    paramByName := params.byName
  }
  let mut body : Array Statement := #[]
  for statement in initializer.body.statements do
    match statement with
    | .return_ (some _) =>
        throw <| .invalidProgram "initializer cannot return a value"
    | _ => body := body.push (← checkStatementV1 scope .mutate statement)
  pure { params := params.ordered, body }

private def checkEntryV1 (state : StateEnvV1) (mode : EntryMode)
    (name : SourceNameComponentV1)
    (paramsSource : Array ProofForgeV2.Source.AstSupportV1.ParamV1)
    (resultSource : TypeV1) (block : BlockV1) : CompileResult Entry := do
  let name := raw name
  let owner := s!"entry '{name}'"
  let params ← resolveParamsV1 owner paramsSource
  let scope : ScopeV1 := {
    owner := name
    stateByName := state.byName
    paramByName := params.byName
  }
  let result ← lowerTypeV1 resultSource
  let mut body : Array Statement := #[]
  let mut returned := false
  for statement in block.statements do
    if returned then
      throw <| .invalidProgram s!"{owner} contains a statement after return"
    let checked ← checkStatementV1 scope mode statement
    match checked with
    | .returnValue value =>
        unless value.type == result do
          throw <| .invalidProgram s!"{owner} return type does not match its declaration"
        returned := true
    | _ => pure ()
    body := body.push checked
  unless returned do
    throw <| .invalidProgram s!"{owner} is missing a return value"
  pure { name, params := params.ordered, result, mode, body }

/-- Direct ProgramV1 → Typed boundary. It never constructs or validates a
legacy `Source.Program`; source identity and hashing remain owned by
`ValidatedSourceV1`. -/
def checkV1 (source : ValidatedSourceV1) : CompileResult Program := do
  validateSupportedShapeV1 source
  let qualifiedName := renderQualified source.programIdentity
  let owner := s!"program '{qualifiedName}'"
  let state ← resolveStatesV1 owner source.program.items

  let mut entryNames := Std.HashSet.emptyWithCapacity source.program.items.size
  let mut initializer : Option Initializer := none
  let mut entries : Array Entry := #[]
  for item in source.program.items do
    match item with
    | .init declaration =>
        initializer := some (← checkInitializerV1 state declaration)
    | .entry declaration =>
        let name := raw declaration.name
        let (duplicate, updated) := entryNames.containsThenInsert name
        if duplicate then
          throw <| .invalidProgram s!"duplicate entry declaration '{name}' in {owner}"
        entryNames := updated
        entries := entries.push (← checkEntryV1 state .mutate declaration.name
          declaration.params declaration.result declaration.body)
    | .view declaration =>
        let name := raw declaration.name
        let (duplicate, updated) := entryNames.containsThenInsert name
        if duplicate then
          throw <| .invalidProgram s!"duplicate entry declaration '{name}' in {owner}"
        entryNames := updated
        entries := entries.push (← checkEntryV1 state .view declaration.name
          declaration.params declaration.result declaration.body)
    | _ => pure ()

  if entries.isEmpty then
    throw <| .invalidProgram s!"program '{qualifiedName}' must declare at least one entry or view"
  pure {
    qualifiedName
    name := raw source.program.name
    state := state.ordered
    initializer
    entries
  }

end ProofForgeV2.Typed
