import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1MatchStatements

open ProofForgeV2
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program MatchStatements where\n" ++
  "  entry run(flag : Bool) : UInt64 do\n" ++
  body

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-match-statements-" ++ label ++ ">")
      "Tests.ProgramV1MatchStatements" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeEntryStatements
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO (Array StmtV1) := do
  let value ← decodeSource session label body
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) => pure declaration.body.statements
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-match-statements-negative-" ++ label ++ ">")
      "Tests.ProgramV1MatchStatements" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private unsafe def expectLegacyReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgram (source body)
      ("<legacy-match-statements-negative-" ++ label ++ ">") none with
  | .ok value =>
      throw <| IO.userError s!"legacy negative '{label}' unexpectedly decoded: {repr value}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"legacy negative '{label}' expected '{expected}', got '{rendered}'"

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

private def expectPlaceNameExpr (expr : ExprV1) (expected label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) s!"{label}: place name changed"
  | other => throw <| IO.userError s!"{label}: expected place name, got {repr other}"

private def stmtAt (statements : Array StmtV1) (index : Nat) (label : String) : IO StmtV1 :=
  match statements[index]? with
  | some stmt => pure stmt
  | none => throw <| IO.userError s!"{label}: missing statement {index}"

private def armAt (arms : Array StmtMatchArmV1) (index : Nat) (label : String) : IO StmtMatchArmV1 :=
  match arms[index]? with
  | some arm => pure arm
  | none => throw <| IO.userError s!"{label}: missing arm {index}"

private def expectLiteralReturn (stmt : StmtV1) (expected : Nat) (label : String) : IO Unit :=
  match stmt with
  | .return_ (some (.literal (.integer value))) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: expected integer return, got {repr other}"

private def expectPattern (pattern expected : PatternV1) (label : String) : IO Unit :=
  expect (pattern == expected) s!"{label}: pattern changed to {repr pattern}"

private def expectBindPattern (pattern : PatternV1) (expected label : String) : IO Unit :=
  match pattern with
  | .bind name => expect (name.raw == expected) s!"{label}: bind raw identity changed"
  | other => throw <| IO.userError s!"{label}: expected bind pattern, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  let statements ← decodeEntryStatements session "pattern-source-order"
    ("    match flag with\n" ++
     "    | _ => do\n" ++
     "      return 0\n" ++
     "    | value => do\n" ++
     "      return 1\n" ++
     "    | true => do\n" ++
     "      return 2\n" ++
     "    | false => do\n" ++
     "      return 3\n" ++
     "    | 42 => do\n" ++
     "      return 4\n" ++
     "    | \"ok\" => do\n" ++
     "      return 5\n" ++
     "    | «whole.bind» => do\n" ++
     "      return 6\n" ++
     "    return 7\n")
  expect (statements.size == 2) "match statement source order changed"
  match statements[0]? with
  | some (StmtV1.match_ scrutinee arms) =>
      expectPlaceNameExpr scrutinee "flag" "match scrutinee"
      expect (arms.size == 7) "match arm count/source order changed"
      let wildcardArm ← armAt arms 0 "wildcard arm"
      let bindArm ← armAt arms 1 "bind arm"
      let trueArm ← armAt arms 2 "true arm"
      let falseArm ← armAt arms 3 "false arm"
      let integerArm ← armAt arms 4 "integer arm"
      let stringArm ← armAt arms 5 "string arm"
      let escapedBindArm ← armAt arms 6 "escaped bind arm"
      expectPattern wildcardArm.pattern .wildcard "wildcard arm"
      expectBindPattern bindArm.pattern "value" "bind arm"
      expectPattern trueArm.pattern (.literal (.bool true)) "true arm"
      expectPattern falseArm.pattern (.literal (.bool false)) "false arm"
      expectPattern integerArm.pattern (.literal (.integer 42)) "integer arm"
      expectPattern stringArm.pattern (.literal (.string "ok")) "string arm"
      expectBindPattern escapedBindArm.pattern "whole.bind" "whole-escaped dotted bind arm"
      expectLiteralReturn (← stmtAt wildcardArm.body.statements 0 "wildcard body") 0 "wildcard body"
      expectLiteralReturn (← stmtAt bindArm.body.statements 0 "bind arm body") 1 "bind arm body"
      expectLiteralReturn (← stmtAt escapedBindArm.body.statements 0 "escaped bind body") 6
        "escaped bind body"
  | other => throw <| IO.userError s!"match statement shape changed: {repr other}"
  expectLiteralReturn (← stmtAt statements 1 "statement after match") 7 "statement after match"

  let nested ← decodeEntryStatements session "nested-match"
    ("    match flag with\n" ++
     "    | first => do\n" ++
     "      match (flag) with\n" ++
     "      | first => do\n" ++
     "        return 1\n" ++
     "      | first => do\n" ++
     "        return 2\n")
  match nested[0]? with
  | some (StmtV1.match_ _ arms) =>
      expect (arms.size == 1) "outer nested match arm count changed"
      let outerArm ← armAt arms 0 "outer nested match arm"
      match outerArm.body.statements[0]? with
      | some (StmtV1.match_ innerScrutinee innerArms) =>
          expectPlaceNameExpr innerScrutinee "flag" "grouped nested scrutinee"
          expect (innerArms.size == 2) "duplicate bind arms should remain source-level accepted"
          expectBindPattern (← armAt innerArms 0 "first duplicate bind").pattern "first"
            "first duplicate bind"
          expectBindPattern (← armAt innerArms 1 "second duplicate bind").pattern "first"
            "second duplicate bind"
      | other => throw <| IO.userError s!"nested match shape changed: {repr other}"
  | other => throw <| IO.userError s!"outer nested match shape changed: {repr other}"

  expectSameProgramBytesAndHash
    (← decodeSource session "grouped-scrutinee-a"
      ("    match flag with\n" ++
       "    | _ => do\n" ++
       "      return 0\n"))
    (← decodeSource session "grouped-scrutinee-b"
      ("    match (flag) with\n" ++
       "    | _ => do\n" ++
       "      return 0\n"))
    "redundant scrutinee grouping must preserve identity"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-scrutinee-a"
      ("    match flag with\n" ++
       "    | _ => do\n" ++
       "      return 0\n"))
    (← decodeSource session "non-alias-scrutinee-b"
      ("    match true with\n" ++
       "    | _ => do\n" ++
       "      return 0\n"))
    "different scrutinees must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-pattern-a"
      ("    match flag with\n" ++
       "    | _ => do\n" ++
       "      return 0\n"))
    (← decodeSource session "non-alias-pattern-b"
      ("    match flag with\n" ++
       "    | true => do\n" ++
       "      return 0\n"))
    "different patterns must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-arm-order-a"
      ("    match flag with\n" ++
       "    | true => do\n" ++
       "      return 1\n" ++
       "    | false => do\n" ++
       "      return 2\n"))
    (← decodeSource session "non-alias-arm-order-b"
      ("    match flag with\n" ++
       "    | false => do\n" ++
       "      return 2\n" ++
       "    | true => do\n" ++
       "      return 1\n"))
    "arm order must be hash-bound"
  expectDifferentProgramBytesAndHash
    (← decodeSource session "non-alias-body-a"
      ("    match flag with\n" ++
       "    | _ => do\n" ++
       "      return 1\n"))
    (← decodeSource session "non-alias-body-b"
      ("    match flag with\n" ++
       "    | _ => do\n" ++
       "      return 2\n"))
    "arm body must be hash-bound"

  expectReject session "constructor-pattern" ("    match flag with\n" ++
    "    | Some(value) => do\n" ++
    "      return 0\n") "source qualified id must contain 2..256 components"
  expectReject session "qualified-bind" ("    match flag with\n" ++
    "    | A.x => do\n" ++
    "      return 0\n") "source name component must contain exactly one Lean Name component"
  expectReject session "reserved-bind" ("    match flag with\n" ++
    "    | «let» => do\n" ++
    "      return 0\n") "reserved portable identifier 'let'"
  expectReject session "match-expression" "    return match flag with\n" "failed to parse file"
  expectReject session "missing-with" ("    match flag\n" ++
    "    | _ => do\n" ++
    "      return 0\n") "failed to parse file"
  expectReject session "missing-bar" ("    match flag with\n" ++
    "      _ => do\n" ++
    "      return 0\n") "failed to parse file"
  expectReject session "missing-arrow" ("    match flag with\n" ++
    "    | _ do\n" ++
    "      return 0\n") "failed to parse file"
  expectReject session "missing-do" ("    match flag with\n" ++
    "    | _ =>\n" ++
    "      return 0\n") "failed to parse file"
  expectReject session "zero-arms" "    match flag with\n" "failed to parse file"
  expectReject session "empty-arm-block" ("    match flag with\n" ++
    "    | _ => do\n") "failed to parse file"
  expectReject session "trailing-payload" ("    match flag with extra\n" ++
    "    | _ => do\n" ++
    "      return 0\n") "failed to parse file"
  expectReject session "scrutinee-before-arm" ("    match «if» with\n" ++
    "    | «let» => do\n" ++
    "      return 0\n") "reserved portable identifier 'if'"
  expectReject session "earlier-pattern-before-block-and-later-arm" ("    match flag with\n" ++
    "    | «let» => do\n" ++
    "      return «if»\n" ++
    "    | «else» => do\n" ++
    "      return 0\n") "reserved portable identifier 'let'"
  expectReject session "earlier-block-before-later-arm" ("    match flag with\n" ++
    "    | _ => do\n" ++
    "      return «if»\n" ++
    "    | «let» => do\n" ++
    "      return 0\n") "reserved portable identifier 'if'"

  expectLegacyReject session "legacy-source-reader" ("    match flag with\n" ++
    "    | _ => do\n" ++
    "      return 0\n") "unsupported portable statement"

end Tests.Language.ProgramV1MatchStatements
