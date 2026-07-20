import Lean
import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Compiler

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- The target-neutral compiler boundary. Source requirements are deliberately
ignored: Typed checking resolves names and effects, then Semantic normalization
derives requirements from the checked operations. -/
def compile (source : Source.Program) : CompileResult Semantic.Program := do
  let typed ← Typed.check source
  return Semantic.fromTyped source.sourceHash typed

private def invalid (message : String) : CompileResult α :=
  .error (.invalidProgram message)

private def unsupported (tag : String) : CompileResult α :=
  invalid s!"validated ProgramV1 lowering does not support {tag}"

private def raw (name : SourceNameComponentV1) : String := name.raw

private def renderQualified (name : SourceQualifiedNameV1) : String :=
  (NonEmptyArray.toArray name.components).foldl
    (fun acc component => Lean.Name.str acc component.raw) .anonymous |>.toString

private def lowerVisibility : VisibilityV1 → Source.Visibility
  | .public_ => .verifierVisible
  | .private_ => .proverWitness
  | .commitment => .commitmentOnly

private partial def lowerType : TypeV1 → CompileResult Source.ValueType
  | .bool => pure .bool
  | .uint 8 => pure .u8
  | .uint 16 => pure .u16
  | .uint 32 => pure .u32
  | .uint 64 => pure .u64
  | .uint 128 => pure .u128
  | .uint 256 => pure .u256
  | .uint _ => unsupported "Type.UInt"
  | .int 8 => pure .i8
  | .int 16 => pure .i16
  | .int 32 => pure .i32
  | .int 64 => pure .i64
  | .int 128 => pure .i128
  | .int 256 => pure .i256
  | .int _ => unsupported "Type.Int"
  | .principal => pure .principal
  | .unit => pure .unit
  | .named _ => unsupported "Type.Named"
  | .array element length => do
      let element ← lowerType element
      if h : length.toNat < 4097 then
        pure (.array element ⟨length.toNat, h⟩)
      else
        unsupported "Type.Array"
  | .map _ _ => unsupported "Type.Map"
  | .option element => .option <$> lowerType element
  | .bytes length => pure (.bytes length)
  | .field id =>
      if id.raw == "bn254_fr" then pure .field else unsupported "Type.Field"

private def lowerParam (param : ProofForgeV2.Source.AstSupportV1.ParamV1) :
    CompileResult Source.Param := do
  pure {
    visibility := lowerVisibility param.visibility
    name := raw param.name
    type := ← lowerType param.type_
  }

private def lowerState (state : ProofForgeV2.Source.AstDeclV1.StateDeclV1) :
    CompileResult Source.StateDecl := do
  pure {
    visibility := lowerVisibility state.visibility
    name := raw state.name
    type := ← lowerType state.type_
  }

private def binaryTag : BinaryOpV1 → String
  | .add => "BinaryOp.Add"
  | .sub => "BinaryOp.Sub" | .mul => "BinaryOp.Mul" | .div => "BinaryOp.Div"
  | .mod => "BinaryOp.Mod" | .eq => "BinaryOp.Eq" | .ne => "BinaryOp.Ne"
  | .lt => "BinaryOp.Lt" | .le => "BinaryOp.Le" | .gt => "BinaryOp.Gt"
  | .ge => "BinaryOp.Ge" | .logicalAnd => "BinaryOp.And"
  | .logicalOr => "BinaryOp.Or" | .bitAnd => "BinaryOp.BitAnd"
  | .bitOr => "BinaryOp.BitOr" | .bitXor => "BinaryOp.BitXor"
  | .shl => "BinaryOp.Shl" | .shr => "BinaryOp.Shr"

private partial def lowerExpr : ExprV1 → CompileResult Source.Expr
  | .literal (.integer magnitude) =>
      if magnitude < UInt64.size then pure (.literal (UInt64.ofNat magnitude))
      else invalid "validated ProgramV1 lowering requires a UInt64 integer literal"
  | .literal (.bool _) => unsupported "Literal.Bool"
  | .literal (.string _) => unsupported "Literal.String"
  | .place (.name name) => pure (.variable (raw name))
  | .place (.field _ _) => unsupported "Place.Field"
  | .place (.index _ _) => unsupported "Place.Index"
  | .constructor _ _ => unsupported "Expr.Constructor"
  | .unary _ _ => unsupported "Expr.Unary"
  | .binary .add lhs rhs => do
      let lhs ← lowerExpr lhs
      let rhs ← lowerExpr rhs
      pure (.checkedAdd lhs rhs)
  | .binary op _ _ => unsupported (binaryTag op)
  | .localCall _ _ => unsupported "Expr.LocalCall"
  | .match_ _ _ => unsupported "Expr.Match"

private partial def lowerStatement : StmtV1 → CompileResult Source.Statement
  | .assign (.name name) value => .assign (raw name) <$> lowerExpr value
  | .assign _ _ => unsupported "Stmt.Assign"
  | .return_ (some value) => .returnValue <$> lowerExpr value
  | .return_ none => unsupported "Stmt.Return"
  | .call call =>
      if call.args.isEmpty then pure (.synchronousCall (renderQualified call.callee))
      else invalid "validated ProgramV1 lowering requires zero external call arguments"
  | .let_ .. => unsupported "Stmt.Let"
  | .if_ .. => unsupported "Stmt.If"
  | .match_ .. => unsupported "Stmt.Match"
  | .for_ .. => unsupported "Stmt.For"
  | .assert_ .. => unsupported "Stmt.Assert"
  | .revert .. => unsupported "Stmt.Revert"
  | .emit .. => unsupported "Stmt.Emit"
  | .schedule .. => unsupported "Stmt.Schedule"

private def lowerBlock (block : BlockV1) : CompileResult (Array Source.Statement) :=
  block.statements.mapM lowerStatement

private def lowerInit (init : ProofForgeV2.Source.AstSpineDeclV1.InitDeclV1) :
    CompileResult Source.Initializer := do
  pure { params := ← init.params.mapM lowerParam, body := ← lowerBlock init.body }

private def lowerEntry (mode : Source.EntryMode)
    (name : SourceNameComponentV1)
    (params : Array ProofForgeV2.Source.AstSupportV1.ParamV1)
    (result : TypeV1) (body : BlockV1) : CompileResult Source.Entry := do
  pure {
    name := raw name
    params := ← params.mapM lowerParam
    result := ← lowerType result
    mode
    body := ← lowerBlock body
  }

private structure LegacyParts where
  state : Array Source.StateDecl := #[]
  initializer : Option Source.Initializer := none
  entries : Array Source.Entry := #[]

private def lowerItem (parts : LegacyParts) : ProgramItemV1 → CompileResult LegacyParts
  | .state state => do
      pure { parts with state := parts.state.push (← lowerState state) }
  | .init init => do
      pure { parts with initializer := some (← lowerInit init) }
  | .entry entry => do
      let lowered ← lowerEntry .mutate entry.name entry.params entry.result entry.body
      pure { parts with entries := parts.entries.push lowered }
  | .view view => do
      let lowered ← lowerEntry .view view.name view.params view.result view.body
      pure { parts with entries := parts.entries.push lowered }
  | .struct _ => unsupported "StructDecl"
  | .enum _ => unsupported "EnumDecl"
  | .const _ => unsupported "ConstDecl"
  | .event _ => unsupported "EventDecl"
  | .error _ => unsupported "ErrorDecl"
  | .fn _ => unsupported "FnDecl"
  | .invariant _ => unsupported "InvariantDecl"
  | .extensionReq _ => unsupported "ExtensionReq"
  | .proof _ => unsupported "ProofDecl"

private def lowerValidatedSourceV1 (source : ValidatedSourceV1) :
    CompileResult Source.Program := do
  let parts ← source.program.items.foldlM lowerItem {}
  pure {
    qualifiedName := renderQualified source.programIdentity
    name := raw source.program.name
    state := parts.state
    initializer := parts.initializer
    entries := parts.entries
  }

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

private def semanticSourceHash (source : ValidatedSourceV1) : CompileResult String := do
  let digest ← match sourceHashV1 source with
    | .ok digest => pure digest
    | .error error => invalid error
  let rendered ← match renderDigest digest with
    | .ok rendered => pure rendered
    | .error error => invalid error
  unless rendered.startsWith "sha256:" do
    return ← invalid "validated ProgramV1 source hash must use sha256:"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 && suffix.all isLowerHex do
    return ← invalid "validated ProgramV1 source hash must contain 64 lowercase hex characters"
  pure suffix

/-- Transitional compiler entry: ProgramV1 owns source identity and hashing;
the legacy Source value remains a private input carrier for Typed checking. -/
def compileValidatedSourceV1 (source : ValidatedSourceV1) : CompileResult Semantic.Program := do
  let legacy ← lowerValidatedSourceV1 source
  let typed ← Typed.check legacy
  let sourceHash ← semanticSourceHash source
  pure (Semantic.fromTyped sourceHash typed)

end ProofForgeV2.Compiler
