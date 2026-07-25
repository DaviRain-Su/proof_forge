import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1CoreStatements

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program CoreStatements where\n" ++
  "  entry run() do\n" ++
  body

private unsafe def decodeEntryStatements
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO (Array StmtV1) := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-core-statements-" ++ label ++ ">")
      "Tests.ProgramV1CoreStatements" none with
  | .ok value =>
      match value.program.items[0]? with
      | some (ProgramItemV1.entry declaration) => pure declaration.body.statements
      | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"
  | .error error => throw <| IO.userError error.render

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-core-statements-negative-" ++ label ++ ">")
      "Tests.ProgramV1CoreStatements" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def stmtAt (statements : Array StmtV1) (index : Nat) (label : String) : IO StmtV1 :=
  match statements[index]? with
  | some stmt => pure stmt
  | none => throw <| IO.userError s!"{label}: missing statement {index}"

private def expectName (name : SourceNameComponentV1) (expected label : String) : IO Unit :=
  expect (name.raw == expected) s!"{label}: raw name identity changed to {name.raw}"

private def expectTypeUInt64 (type : TypeV1) (label : String) : IO Unit :=
  match type with
  | .uint width => expect (width == 64) s!"{label}: UInt width changed"
  | other => throw <| IO.userError s!"{label}: expected UInt64, got {repr other}"

private def expectLiteralInteger (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected integer literal, got {repr other}"

private def expectLiteralBool (expr : ExprV1) (expected : Bool) (label : String) : IO Unit :=
  match expr with
  | .literal (.bool value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected bool literal, got {repr other}"

private def expectPlaceName (expr : ExprV1) (expected : String) (label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expectName name expected label
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  let statements ← decodeEntryStatements session "positive-order"
    ("    let annotated : UInt64 := 1\n" ++
     "    let omitted := annotated\n" ++
     "    plain := 2\n" ++
     "    «slot.with.dot» := 3\n" ++
     "    return «slot.with.dot»\n" ++
     "    return\n" ++
     "    assert true\n" ++
     "    assert «condition.with.dot» else «error.with.dot»\n")
  expect (statements.size == 8) "core statement/source order changed"

  match ← stmtAt statements 0 "annotated let" with
  | .let_ binder (some type) value =>
      expectName binder "annotated" "annotated let binder"
      expectTypeUInt64 type "annotated let type"
      expectLiteralInteger value 1 "annotated let value"
  | other => throw <| IO.userError s!"annotated let shape changed: {repr other}"

  match ← stmtAt statements 1 "omitted let" with
  | .let_ binder none value =>
      expectName binder "omitted" "omitted let binder"
      expectPlaceName value "annotated" "omitted let value"
  | other => throw <| IO.userError s!"omitted let shape changed: {repr other}"

  match ← stmtAt statements 2 "plain assign" with
  | .assign (.name target) value =>
      expectName target "plain" "plain assignment target"
      expectLiteralInteger value 2 "plain assignment value"
  | other => throw <| IO.userError s!"plain assignment shape changed: {repr other}"

  match ← stmtAt statements 3 "escaped assign" with
  | .assign (.name target) value =>
      expectName target "slot.with.dot" "escaped assignment target"
      expectLiteralInteger value 3 "escaped assignment value"
  | other => throw <| IO.userError s!"escaped assignment shape changed: {repr other}"

  match ← stmtAt statements 4 "valued return" with
  | .return_ (some value) =>
      expectPlaceName value "slot.with.dot" "valued return expression"
  | other => throw <| IO.userError s!"valued return shape changed: {repr other}"

  match ← stmtAt statements 5 "valueless return" with
  | .return_ none => pure ()
  | other => throw <| IO.userError s!"valueless return shape changed: {repr other}"

  match ← stmtAt statements 6 "assert no error" with
  | .assert_ condition none =>
      expectLiteralBool condition true "assert condition"
  | other => throw <| IO.userError s!"assert shape changed: {repr other}"

  match ← stmtAt statements 7 "assert else" with
  | .assert_ condition (some errorName) =>
      expectPlaceName condition "condition.with.dot" "assert-else condition"
      expectName errorName "error.with.dot" "assert-else error"
  | other => throw <| IO.userError s!"assert-else shape changed: {repr other}"

  expectReject session "qualified-let-binder" "    let A.x := 1\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "qualified-assign-target" "    A.x := 1\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "bare-qualified-expression" "    return A.x\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "qualified-assert-error" "    assert true else A.Err\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "qualified-field-type-component" "    let field : Field A.bn254_fr := 1\n"
    "unsupported portable type"

  expectReject session "reserved-let-binder" "    let «let» := 1\n"
    "reserved portable identifier 'let'"
  expectReject session "reserved-assign-target" "    «return» := 1\n"
    "reserved portable identifier 'return'"
  expectReject session "reserved-return-place" "    return «if»\n"
    "reserved portable identifier 'if'"
  expectReject session "reserved-assert-error" "    assert true else «else»\n"
    "reserved portable identifier 'else'"

  expectReject session "malformed-let-missing-value" "    let x :=\n"
    "failed to parse file"
  expectReject session "malformed-let-missing-type" "    let x : := 1\n"
    "failed to parse file"
  expectReject session "malformed-assert-missing-condition" "    assert\n"
    "failed to parse file"
  expectReject session "malformed-return-extra-expression" "    return 1 2\n"
    "failed to parse file"

  expectReject session "let-binder-before-type-and-rhs"
    "    let A.x : Bad.Type := «if»\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "let-reserved-binder-before-type-and-rhs"
    "    let «if» : Bad.Type := A.x\n"
    "reserved portable identifier 'if'"
  expectReject session "assign-target-before-rhs"
    "    A.x := «if»\n"
    "source name component must contain exactly one Lean Name component"
  expectReject session "assign-reserved-target-before-rhs"
    "    «return» := A.x\n"
    "reserved portable identifier 'return'"
  expectReject session "assert-condition-before-error"
    "    assert «if» else A.Err\n"
    "reserved portable identifier 'if'"
  expectReject session "assert-qualified-condition-before-error"
    "    assert A.x else A.Err\n"
    "source name component must contain exactly one Lean Name component"

end Tests.Language.ProgramV1CoreStatements
