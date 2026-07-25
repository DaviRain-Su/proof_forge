import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1FieldPlaces

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def sourceWithBody (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program FieldPlaces where\n" ++
  "  entry run(account : UInt64, owner : UInt64, id : UInt64, balance : UInt64, other : UInt64, amount : UInt64) : UInt64 do\n" ++
  body

private def returnSource (expr : String) : String :=
  sourceWithBody ("    return " ++ expr ++ "\n")

private def assignSource (target rhs : String) : String :=
  sourceWithBody ("    " ++ target ++ " := " ++ rhs ++ "\n" ++
    "    return 0\n")

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label src : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 src
      ("<program-v1-field-places-" ++ label ++ ">")
      "Tests.ProgramV1FieldPlaces" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeReturnExpr
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) : IO ExprV1 := do
  let value ← decodeSource session label (returnSource expr)
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.return_ (some value)] => pure value
      | other => throw <| IO.userError s!"'{label}' did not decode one return: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def decodeAssign
    (session : ProofForgeV2.Language.Loader.ParserSession) (label target rhs : String) :
    IO (PlaceV1 × ExprV1) := do
  let value ← decodeSource session label (assignSource target rhs)
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.assign target value, .return_ (some (.literal (.integer 0)))] => pure (target, value)
      | other => throw <| IO.userError s!"'{label}' did not decode assignment then return: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def expectRejectSource
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label src expected : String) : IO Unit := do
  match ← session.selectProgramV1 src
      ("<program-v1-field-places-negative-" ++ label ++ ">")
      "Tests.ProgramV1FieldPlaces" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private unsafe def expectRejectExpr
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label expr expected : String) : IO Unit :=
  expectRejectSource session label (returnSource expr) expected

private unsafe def expectRejectBody
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit :=
  expectRejectSource session label (sourceWithBody body) expected

private def expectLiteral (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected integer literal, got {repr other}"

private def exprAt (exprs : Array ExprV1) (index : Nat) (label : String) : IO ExprV1 :=
  match exprs[index]? with
  | some expr => pure expr
  | none => throw <| IO.userError s!"{label}: missing expression {index}"

private def expectPlaceParts (place : PlaceV1) (expected : Array String) (label : String) : IO Unit := do
  let rec collect : PlaceV1 → IO (Array String)
    | .name name => pure #[name.raw]
    | .field base field => do pure ((← collect base).push field.raw)
    | .index _ _ => throw <| IO.userError s!"{label}: unexpected index place"
  expect ((← collect place) == expected) s!"{label}: field place source order changed"

private def expectPlaceExprParts (expr : ExprV1) (expected : Array String) (label : String) : IO Unit :=
  match expr with
  | .place place => expectPlaceParts place expected label
  | other => throw <| IO.userError s!"{label}: expected place expression, got {repr other}"

private def expectUnary (expr : ExprV1) (expected : UnaryOpV1) (label : String) : IO ExprV1 := do
  match expr with
  | .unary op operand =>
      expect (op == expected) s!"{label}: unary operator changed"
      pure operand
  | other => throw <| IO.userError s!"{label}: expected unary, got {repr other}"

private def expectBinary (expr : ExprV1) (expected : BinaryOpV1) (label : String) :
    IO (ExprV1 × ExprV1) := do
  match expr with
  | .binary op lhs rhs =>
      expect (op == expected) s!"{label}: binary operator changed"
      pure (lhs, rhs)
  | other => throw <| IO.userError s!"{label}: expected binary, got {repr other}"

private def canonicalBytes (source : ValidatedSourceV1) (label : String) : IO ByteArray :=
  match canonicalValidatedSourceAstBytesV1 source with
  | .ok bytes => pure bytes
  | .error error => throw <| IO.userError s!"{label}: canonical bytes failed: {error}"

private def sourceHash (source : ValidatedSourceV1) (label : String) : IO ProofForgeV2.Core.Common.Digest :=
  match sourceHashV1 source with
  | .ok digest => pure digest
  | .error error => throw <| IO.userError s!"{label}: sourceHashV1 failed: {error}"

private def expectSameProgramBytesAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program == right.program) s!"{label}: ProgramV1 AST changed"
  expect ((← canonicalBytes left (label ++ " left")) ==
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes changed"
  expect ((← sourceHash left (label ++ " left")) ==
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 changed"

private def expectDifferentProgramBytesAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program != right.program) s!"{label}: ProgramV1 AST unexpectedly aliased"
  expect ((← canonicalBytes left (label ++ " left")) !=
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes unexpectedly aliased"
  expect ((← sourceHash left (label ++ " left")) !=
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 unexpectedly aliased"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  expectPlaceExprParts (← decodeReturnExpr session "rvalue-two" "account.owner")
    #["account", "owner"] "two-component rvalue field place"
  expectPlaceExprParts (← decodeReturnExpr session "rvalue-three" "account.owner.id")
    #["account", "owner", "id"] "three-component rvalue field place"
  let (assignTarget, assignValue) ← decodeAssign session "assign-field" "account.balance" "1"
  expectPlaceParts assignTarget #["account", "balance"] "assignment field target"
  expectLiteral assignValue 1 "assignment rhs literal"
  let (deepAssignTarget, deepAssignValue) ← decodeAssign session "assign-deep-field" "account.owner.id" "2"
  expectPlaceParts deepAssignTarget #["account", "owner", "id"] "deep assignment source order"
  expectLiteral deepAssignValue 2 "deep assignment rhs literal"

  expectPlaceExprParts (← decodeReturnExpr session "escaped-component" "account.«owner».id")
    #["account", "owner", "id"] "escaped component raw identity"
  expectSameProgramBytesAndHash
    (← decodeSource session "canonical-plain" (returnSource "account.owner.id"))
    (← decodeSource session "canonical-escaped" (returnSource "account.«owner».id"))
    "ordinary and escaped components with identical raws must canonicalize equally"

  expectPlaceExprParts (← expectUnary (← decodeReturnExpr session "unary-field" "-account.balance")
    .neg "field place unary operand") #["account", "balance"] "unary field operand"
  let (binaryLhs, binaryRhs) ← expectBinary
    (← decodeReturnExpr session "binary-field" "account.balance + other.amount") .add
    "field place binary operand"
  expectPlaceExprParts binaryLhs #["account", "balance"] "binary lhs field place"
  expectPlaceExprParts binaryRhs #["other", "amount"] "binary rhs field place"

  expectSameProgramBytesAndHash
    (← decodeSource session "grouping-a" (returnSource "account.balance"))
    (← decodeSource session "grouping-b" (returnSource "((((account.balance))))"))
    "redundant grouping must preserve field-place canonical identity"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "whole-escaped" (returnSource "«account.balance»"))
    (← decodeSource session "field-chain" (returnSource "account.balance"))
    "whole escaped dotted identifier must not alias field chain"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "depth-two" (returnSource "account.balance"))
    (← decodeSource session "depth-three" (returnSource "account.balance.id"))
    "field depth must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "order-a" (returnSource "account.owner"))
    (← decodeSource session "order-b" (returnSource "owner.account"))
    "field component order must be hash-bound"

  expectPlaceExprParts (← decodeReturnExpr session "whole-escaped-name" "«account.balance»")
    #["account.balance"] "whole escaped dotted identifier must remain one name"

  let localArgs ← match ← decodeReturnExpr session "local-call-unchanged" "account(1)" with
    | .localCall callee args =>
        expect (callee.raw == "account") "local-call classification changed"
        pure args
    | other => throw <| IO.userError s!"local-call classification changed: {repr other}"
  expect (localArgs.size == 1) "local-call arg count changed"
  expectLiteral (← exprAt localArgs 0 "local-call arg") 1 "local-call arg value changed"
  match ← decodeReturnExpr session "constructor-unchanged" "account.owner(1)" with
  | .constructor ctor args =>
      let parts := ctor.components.toArray.map (·.raw)
      expect (parts == #["account", "owner"]) "constructor classification changed"
      expect (args.size == 1) "constructor arg count changed"
      expectLiteral (← exprAt args 0 "constructor arg") 1 "constructor arg value changed"
  | other => throw <| IO.userError s!"constructor classification changed: {repr other}"

  for (label, expr) in [
      ("double-dot", "account..owner"),
      ("leading-dot", ".account"),
      ("trailing-dot", "account.")
    ] do
    expectRejectExpr session label expr "failed to parse file"

  expectRejectExpr session "uppercase-qualified-rvalue" "A.x"
    "source name component must contain exactly one Lean Name component"
  expectRejectBody session "uppercase-qualified-assign"
    "    A.x := 1\n    return 0\n"
    "source name component must contain exactly one Lean Name component"
  expectRejectBody session "uppercase-qualified-assign-before-rhs"
    "    A.x := «if»\n    return 0\n"
    "source name component must contain exactly one Lean Name component"
  expectRejectExpr session "reserved-root-before-field" "«if».balance"
    "reserved portable identifier 'if'"
  expectRejectExpr session "reserved-field-component" "account.«return».id"
    "reserved portable identifier 'return'"
  let overlongRaw := String.ofList (List.replicate 241 'a')
  expectRejectExpr session "reserved-root-before-overlong-component"
    ("«if».«" ++ overlongRaw ++ "»")
    "reserved portable identifier 'if'"
  expectRejectBody session "assign-reserved-target-before-rhs"
    "    account.«return» := «if»\n    return 0\n"
    "reserved portable identifier 'return'"
  expectRejectBody session "assign-target-before-rhs"
    "    account.balance := «if»\n    return 0\n"
    "reserved portable identifier 'if'"
  expectRejectExpr session "qualified-index-base" "A.B[«if»]"
    "index access base must be unqualified"

end Tests.Language.ProgramV1FieldPlaces
