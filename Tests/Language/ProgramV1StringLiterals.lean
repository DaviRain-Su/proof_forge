import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1StringLiterals

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
  "program StringLiterals where\n" ++
  "  entry run() : UInt64 do\n" ++
  body

private def returnSource (expr : String) : String :=
  sourceWithBody ("    return " ++ expr ++ "\n")

private def letSource (expr : String) : String :=
  sourceWithBody ("    let value := " ++ expr ++ "\n" ++
    "    return value\n")

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source
      ("<program-v1-string-literals-" ++ label ++ ">")
      "Tests.ProgramV1StringLiterals" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeReturnExpr
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ExprV1 := do
  let value ← decodeSource session label (returnSource expr)
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.return_ (some value)] => pure value
      | other => throw <| IO.userError s!"'{label}' did not decode one valued return: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def decodeLetValueExpr
    (session : ProofForgeV2.Language.Loader.ParserSession) (label expr : String) :
    IO ExprV1 := do
  let value ← decodeSource session label (letSource expr)
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) =>
      match declaration.body.statements with
      | #[.let_ _ none value, .return_ (some (.place (.name _)))] => pure value
      | other => throw <| IO.userError s!"'{label}' did not decode one let followed by return: {repr other}"
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label source expected : String) : IO Unit := do
  match ← session.selectProgramV1 source
      ("<program-v1-string-literals-negative-" ++ label ++ ">")
      "Tests.ProgramV1StringLiterals" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def expectStringLiteral (expr : ExprV1) (expected label : String) : IO Unit :=
  match expr with
  | .literal (.string value) =>
      expect (value == expected)
        s!"{label}: decoded String value changed to {repr value}"
  | other => throw <| IO.userError s!"{label}: expected string literal, got {repr other}"

private def expectPlaceName (expr : ExprV1) (expected label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) label
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

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

  for (label, expr, expected) in [
      ("empty", "\"\"", ""),
      ("ascii", "\"hello\"", "hello"),
      ("escaped-quote", "\"\\\"\"", "\""),
      ("escaped-backslash", "\"\\\\\"", "\\"),
      ("tab", "\"\\t\"", "\t"),
      ("newline", "\"\\n\"", "\n"),
      ("unicode-scalar", "\"α\"", "α")
    ] do
    expectStringLiteral (← decodeReturnExpr session (label ++ "-return") expr) expected
      s!"{label} return literal"
    expectStringLiteral (← decodeLetValueExpr session (label ++ "-let") expr) expected
      s!"{label} let value literal"

  expectSameProgramBytesAndHash
    (← decodeSource session "newline-escape-a" (returnSource "\"\\n\""))
    (← decodeSource session "newline-escape-b" (returnSource "\"\\x0a\""))
    "alternate newline escape spellings must share decoded ProgramV1 identity"
  expectSameProgramBytesAndHash
    (← decodeSource session "tab-escape-a" (letSource "\"\\t\""))
    (← decodeSource session "tab-escape-b" (letSource "\"\\x09\""))
    "alternate tab escape spellings must share decoded ProgramV1 identity"
  expectSameProgramBytesAndHash
    (← decodeSource session "unicode-escape-a" (returnSource "\"α\""))
    (← decodeSource session "unicode-escape-b" (returnSource "\"\\u03b1\""))
    "alternate Unicode scalar escape spellings must share decoded ProgramV1 identity"

  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-string-a" (returnSource "\"a\""))
    (← decodeSource session "non-alias-string-b" (returnSource "\"b\""))
    "different String payloads must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-string-tag" (returnSource "\"value\""))
    (← decodeSource session "non-alias-place-tag" (returnSource "value"))
    "string literal and place expression tags must not alias"
  expectStringLiteral (← decodeReturnExpr session "tag-string-shape" "\"value\"") "value"
    "string tag shape"
  expectPlaceName (← decodeReturnExpr session "tag-place-shape" "value") "value"
    "place tag shape"

  expectSameProgramBytesAndHash
    (← decodeSource session "redundant-grouping-a" (returnSource "\"grouped\""))
    (← decodeSource session "redundant-grouping-b" (returnSource "((((\"grouped\"))))"))
    "redundant grouping must preserve string literal canonical identity"
  expectSameProgramBytesAndHash
    (← decodeSource session "redundant-let-grouping-a" (letSource "\"grouped\""))
    (← decodeSource session "redundant-let-grouping-b" (letSource "(((\"grouped\")))"))
    "redundant grouping must preserve let-value string identity"

  expectReject session "adjacent-literals" (returnSource "\"a\" \"b\"")
    "failed to parse file"
  expectReject session "interpolated-syntax" (returnSource "s!\"hello {value}\"")
    "failed to parse file"
  expectReject session "unterminated-string" (returnSource "\"unterminated")
    "failed to parse file"
  expectReject session "extra-payload" (returnSource "\"ok\" value")
    "failed to parse file"

end Tests.Language.ProgramV1StringLiterals
