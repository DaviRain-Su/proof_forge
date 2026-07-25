import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1IndexedPlaces

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def sourceWithBody (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program IndexedPlaces where\n" ++
  "  entry run(account : UInt64, value : UInt64, x : UInt64) : UInt64 do\n" ++
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
      ("<program-v1-indexed-places-" ++ label ++ ">")
      "Tests.ProgramV1IndexedPlaces" none with
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
      ("<program-v1-indexed-places-negative-" ++ label ++ ">")
      "Tests.ProgramV1IndexedPlaces" none with
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

private def rawParts (qualified : SourceQualifiedNameV1) : Array String :=
  qualified.components.toArray.map (·.raw)

private def expectPlaceParts (place : PlaceV1) (expected : Array String) (label : String) : IO Unit := do
  let rec collect : PlaceV1 → IO (Array String)
    | .name name => pure #[name.raw]
    | .field base field => do pure ((← collect base).push field.raw)
    | .index _ _ => throw <| IO.userError s!"{label}: unexpected nested index in base"
  expect ((← collect place) == expected) s!"{label}: base component source order changed"

private def expectIndexedPlace
    (expr : ExprV1) (expectedBase : Array String) (expectedIndex : Nat) (label : String) : IO Unit :=
  match expr with
  | .place (.index base index) => do
      expectPlaceParts base expectedBase label
      expectLiteral index expectedIndex s!"{label}: index changed"
  | other => throw <| IO.userError s!"{label}: expected indexed place, got {repr other}"

private def expectIndexedPlaceWithBinaryIndex
    (expr : ExprV1) (expectedBase : Array String) (label : String) : IO Unit :=
  match expr with
  | .place (.index base (.binary .add lhs rhs)) => do
      expectPlaceParts base expectedBase label
      expectLiteral lhs 1 s!"{label}: lhs index changed"
      expectLiteral rhs 2 s!"{label}: rhs index changed"
  | other => throw <| IO.userError s!"{label}: expected indexed place with add index, got {repr other}"

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

  expectIndexedPlace (← decodeReturnExpr session "field-index-literal" "account.items[0]")
    #["account", "items"] 0 "account.items[0]"
  expectIndexedPlaceWithBinaryIndex
    (← decodeReturnExpr session "uppercase-qualified-add-index" "A.B[1 + 2]")
    #["A", "B"] "A.B[1 + 2]"

  let (target, rhs) ← decodeAssign session "assign-field-index" "account.items[0]" "value"
  match target with
  | .index base index => do
      expectPlaceParts base #["account", "items"] "indexed assignment target"
      expectLiteral index 0 "indexed assignment index"
  | other => throw <| IO.userError s!"indexed assignment target shape changed: {repr other}"
  match rhs with
  | .place (.name name) => expect (name.raw == "value") "indexed assignment rhs raw changed"
  | other => throw <| IO.userError s!"indexed assignment rhs shape changed: {repr other}"

  expectSameProgramBytesAndHash
    (← decodeSource session "escaped-component" (returnSource "account.«items»[0]"))
    (← decodeSource session "plain-component" (returnSource "account.items[0]"))
    "escaped ordinary field component must canonicalize with plain indexed place"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "field-index" (returnSource "account.items[0]"))
    (← decodeSource session "whole-escaped-index" (returnSource "«account.items»[0]"))
    "whole escaped dotted base must not alias field-index base"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "index-zero" (returnSource "account.items[0]"))
    (← decodeSource session "index-one" (returnSource "account.items[1]"))
    "index value must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "field-order-a" (returnSource "account.items[0]"))
    (← decodeSource session "field-order-b" (returnSource "items.account[0]"))
    "field base component order must be hash-bound"

  expectIndexedPlace (← decodeReturnExpr session "bare-index-unchanged" "x[0]")
    #["x"] 0 "bare x[0] ProgramV1 place index"
  match ← decodeReturnExpr session "local-call-classification" "account(1)" with
  | .localCall callee args => do
      expect (callee.raw == "account") "local-call callee raw changed"
      expect (args.size == 1) "local-call argument count changed"
      expectLiteral (← exprAt args 0 "local-call argument") 1 "local-call argument changed"
  | other => throw <| IO.userError s!"local-call classification changed: {repr other}"
  match ← decodeReturnExpr session "constructor-classification" "account.items(1)" with
  | .constructor ctor args => do
      expect (rawParts ctor == #["account", "items"]) "constructor raw path changed"
      expect (args.size == 1) "constructor argument count changed"
      expectLiteral (← exprAt args 0 "constructor argument") 1 "constructor argument changed"
  | other => throw <| IO.userError s!"constructor classification changed: {repr other}"

  for (label, expr) in [
      ("grouped-base", "(x)[0]"),
      ("call-base", "f()[0]")
    ] do
    expectRejectExpr session label expr "failed to parse file"

  expectRejectBody session "target-before-rhs"
    "    account.«return»[0] := «if»\n    return 0\n"
    "reserved portable identifier 'return'"
  expectRejectExpr session "base-components-before-index" "account.«return»[«if»]"
    "reserved portable identifier 'return'"
  expectRejectBody session "index-before-rhs"
    "    account.items[«if»] := «return»\n    return 0\n"
    "reserved portable identifier 'if'"
  expectRejectExpr session "reserved-root" "«struct».items[0]"
    "reserved portable identifier 'struct'"
  let overlongRaw := String.ofList (List.replicate 241 'a')
  expectRejectExpr session "overlong-field-component" ("account.«" ++ overlongRaw ++ "»[0]")
    "source name component must contain 1..240 UTF-8 bytes"

end Tests.Language.ProgramV1IndexedPlaces
