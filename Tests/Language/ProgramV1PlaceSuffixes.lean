import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1PlaceSuffixes

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
  "program PlaceSuffixes where\n" ++
  "  entry run(account : UInt64, value : UInt64, x : UInt64, f : UInt64) : UInt64 do\n" ++
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
      ("<program-v1-place-suffixes-" ++ label ++ ">")
      "Tests.ProgramV1PlaceSuffixes" none with
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
      ("<program-v1-place-suffixes-negative-" ++ label ++ ">")
      "Tests.ProgramV1PlaceSuffixes" none with
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

private def expectName (place : PlaceV1) (expected : String) (label : String) : IO Unit :=
  match place with
  | .name name => expect (name.raw == expected) s!"{label}: name raw changed"
  | other => throw <| IO.userError s!"{label}: expected name, got {repr other}"

private partial def renderPlaceShape : PlaceV1 → IO String
  | .name name => pure name.raw
  | .field base field => do
      pure s!"{← renderPlaceShape base}.{field.raw}"
  | .index base index => do
      let baseShape ← renderPlaceShape base
      match index with
      | .literal (.integer value) => pure s!"{baseShape}[{value}]"
      | .binary .add lhs rhs =>
          match lhs, rhs with
          | .literal (.integer left), .literal (.integer right) =>
              pure s!"{baseShape}[{left}+{right}]"
          | _, _ => pure s!"{baseShape}[binary]"
      | _ => pure s!"{baseShape}[expr]"

private def expectPlaceShape (place : PlaceV1) (expected label : String) : IO Unit := do
  let actual ← renderPlaceShape place
  expect (actual == expected) s!"{label}: expected {expected}, got {actual}"

private def expectPlaceExprShape (expr : ExprV1) (expected label : String) : IO Unit :=
  match expr with
  | .place place => expectPlaceShape place expected label
  | other => throw <| IO.userError s!"{label}: expected place expression, got {repr other}"

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

  expectPlaceExprShape (← decodeReturnExpr session "double-index" "x[0][1]")
    "x[0][1]" "x[0][1] rvalue"
  expectPlaceExprShape (← decodeReturnExpr session "qualified-double-index" "account.items[0][1]")
    "account.items[0][1]" "account.items[0][1] rvalue"
  expectPlaceExprShape (← decodeReturnExpr session "field-after-index" "x[0].field")
    "x[0].field" "x[0].field rvalue"
  expectPlaceExprShape (← decodeReturnExpr session "qualified-index-field" "account.items[0].owner")
    "account.items[0].owner" "account.items[0].owner rvalue"
  expectPlaceExprShape (← decodeReturnExpr session "mixed-field-index" "x[0].field[1]")
    "x[0].field[1]" "x[0].field[1] rvalue"
  expectPlaceExprShape (← decodeReturnExpr session "nested-index-expr" "account.items[1 + 2].owner[3]")
    "account.items[1+2].owner[3]" "nested index expression rvalue"

  match ← decodeReturnExpr session "dotted-suffix-after-index" "x[0].a.b" with
  | .place (.field (.field (.index (.name root) (.literal (.integer 0))) first) second) => do
      expect (root.raw == "x") "dotted suffix root raw changed"
      expect (first.raw == "a") "dotted suffix first component raw changed"
      expect (second.raw == "b") "dotted suffix second component raw changed"
  | other => throw <| IO.userError s!"dotted suffix after index must decompose like a dotted root: {repr other}"
  match ← decodeReturnExpr session "escaped-dotted-suffix" "x[0].«a.b»" with
  | .place (.field (.index (.name root) (.literal (.integer 0))) field) => do
      expect (root.raw == "x") "escaped dotted suffix root raw changed"
      expect (field.raw == "a.b") "whole-escaped dotted suffix must stay one raw component"
  | other => throw <| IO.userError s!"escaped dotted suffix shape changed: {repr other}"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "split-dotted-suffix" (returnSource "x[0].a.b"))
    (← decodeSource session "escaped-dotted-suffix-hash" (returnSource "x[0].«a.b»"))
    "split dotted suffix components must not alias one whole-escaped component"

  for (label, target, expected) in [
      ("assign-double-index", "x[0][1]", "x[0][1]"),
      ("assign-qualified-double-index", "account.items[0][1]", "account.items[0][1]"),
      ("assign-field-after-index", "x[0].field", "x[0].field"),
      ("assign-qualified-index-field", "account.items[0].owner", "account.items[0].owner"),
      ("assign-mixed-field-index", "x[0].field[1]", "x[0].field[1]")
    ] do
    let (place, rhs) ← decodeAssign session label target "value"
    expectPlaceShape place expected label
    match rhs with
    | .place valuePlace => expectName valuePlace "value" s!"{label}: rhs"
    | other => throw <| IO.userError s!"{label}: rhs shape changed: {repr other}"

  expectSameProgramBytesAndHash
    (← decodeSource session "escaped-field" (returnSource "account.«items»[0].owner"))
    (← decodeSource session "plain-field" (returnSource "account.items[0].owner"))
    "escaped ordinary field suffix must canonicalize with plain suffix"
  expectSameProgramBytesAndHash
    (← decodeSource session "grouping-a" (returnSource "x[0].field[1]"))
    (← decodeSource session "grouping-b" (returnSource "((((x[0].field[1]))))"))
    "redundant grouping must preserve chained place canonical identity"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "index-order-a" (returnSource "x[0][1]"))
    (← decodeSource session "index-order-b" (returnSource "x[1][0]"))
    "index suffix order must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "field-index-order-a" (returnSource "x[0].field"))
    (← decodeSource session "field-index-order-b" (returnSource "x.field[0]"))
    "field/index suffix order must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "depth-a" (returnSource "account.items[0].owner"))
    (← decodeSource session "depth-b" (returnSource "account.items[0].owner[1]"))
    "suffix depth must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "whole-escaped" (returnSource "«account.items»[0].owner"))
    (← decodeSource session "split-components" (returnSource "account.items[0].owner"))
    "whole escaped dotted root must not alias split components"

  for (label, expr) in [
      ("grouped-base", "(x)[0]"),
      ("call-base", "f()[0]"),
      ("missing-index", "x[]"),
      ("missing-field", "x[0]."),
      ("extra-payload", "x[0] 1")
    ] do
    expectRejectExpr session label expr "failed to parse file"

  expectRejectBody session "target-root-before-index-rhs"
    "    «if»[«return»] := «struct»\n    return 0\n"
    "reserved portable identifier 'if'"
  expectRejectBody session "earlier-suffix-before-later-suffix"
    "    x[«if»].«return» := «struct»\n    return 0\n"
    "reserved portable identifier 'if'"
  expectRejectBody session "field-before-later-index-rhs"
    "    x[0].«return»[«if»] := «struct»\n    return 0\n"
    "reserved portable identifier 'return'"
  expectRejectBody session "index-before-rhs"
    "    x[0].field[«if»] := «return»\n    return 0\n"
    "reserved portable identifier 'if'"
  expectRejectBody session "dotted-suffix-first-component-before-second"
    "    x[0].«if».«return» := «struct»\n    return 0\n"
    "reserved portable identifier 'if'"

end Tests.Language.ProgramV1PlaceSuffixes
