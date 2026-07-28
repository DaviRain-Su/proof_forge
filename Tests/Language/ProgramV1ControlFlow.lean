import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1ControlFlow

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ControlFlow where\n" ++
  "  state total : UInt64\n" ++
  "  entry run(a : UInt64) : UInt64 do\n" ++
  body ++
  "    return total\n"

private unsafe def decodeEntryStatements
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO (Array StmtV1) := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-control-flow-" ++ label ++ ">")
      "Tests.ProgramV1ControlFlow" none with
  | .ok value =>
      match value.program.items[1]? with
      | some (ProgramItemV1.entry declaration) => pure declaration.body.statements
      | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"
  | .error error => throw <| IO.userError error.render

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-control-flow-negative-" ++ label ++ ">")
      "Tests.ProgramV1ControlFlow" none with
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

private def expectPlaceNameExpr (expr : ExprV1) (expected : String) (label : String) : IO Unit :=
  match expr with
  | .place (.name name) => expect (name.raw == expected) label
  | other => throw <| IO.userError s!"{label}: {repr other}"

private def expectLiteralIntegerExpr (expr : ExprV1) (expected : Nat) (label : String) : IO Unit :=
  match expr with
  | .literal (.integer value) => expect (value == expected) label
  | other => throw <| IO.userError s!"{label}: {repr other}"

private def expectAssignNameValue (stmt : StmtV1) (targetName : String) (valueName : String)
    (label : String) : IO Unit := do
  match stmt with
  | .assign (.name target) value =>
      expect (target.raw == targetName) s!"{label}: assignment target changed"
      expectPlaceNameExpr value valueName s!"{label}: assignment value changed"
  | other => throw <| IO.userError s!"{label}: expected assignment, got {repr other}"

private def expectAssignNameLiteral (stmt : StmtV1) (targetName : String) (value : Nat)
    (label : String) : IO Unit := do
  match stmt with
  | .assign (.name target) expr =>
      expect (target.raw == targetName) s!"{label}: assignment target changed"
      expectLiteralIntegerExpr expr value s!"{label}: assignment literal changed"
  | other => throw <| IO.userError s!"{label}: expected assignment, got {repr other}"

private def expectReturnName (stmt : StmtV1) (expected : String) (label : String) : IO Unit :=
  match stmt with
  | .return_ (some expr) => expectPlaceNameExpr expr expected label
  | other => throw <| IO.userError s!"{label}: expected return value, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  let ifStatements ← decodeEntryStatements session "if-else-order"
    ("    if a > total then\n" ++
     "      total := a\n" ++
     "      return total\n" ++
     "    else\n" ++
     "      total := total\n" ++
     "    total := a\n")
  expect (ifStatements.size == 3) "if/else source order changed"
  match ← stmtAt ifStatements 0 "if/else" with
  | .if_ condition thenBlock (some elseBlock) =>
      match condition with
      | .binary .gt lhs rhs =>
          expectPlaceNameExpr lhs "a" "if condition lhs order changed"
          expectPlaceNameExpr rhs "total" "if condition rhs order changed"
      | other => throw <| IO.userError s!"if condition shape changed: {repr other}"
      expect (thenBlock.statements.size == 2) "then block statement order changed"
      expectAssignNameValue (← stmtAt thenBlock.statements 0 "then assignment") "total" "a"
        "then assignment"
      expectReturnName (← stmtAt thenBlock.statements 1 "then return") "total" "then return"
      expect (elseBlock.statements.size == 1) "else block statement order changed"
      expectAssignNameValue (← stmtAt elseBlock.statements 0 "else assignment") "total" "total"
        "else assignment"
  | other => throw <| IO.userError s!"if/else decoded to wrong statement: {repr other}"
  expectAssignNameValue (← stmtAt ifStatements 1 "after if") "total" "a" "after if statement"

  let danglingStatements ← decodeEntryStatements session "dangling-else"
    ("    if a > total then\n" ++
     "      if total == a then\n" ++
     "        total := 1\n" ++
     "      else\n" ++
     "        total := 2\n" ++
     "    total := 3\n")
  match ← stmtAt danglingStatements 0 "outer if" with
  | .if_ _ outerThen none =>
      expect (outerThen.statements.size == 1) "dangling else changed outer then size"
      match ← stmtAt outerThen.statements 0 "inner if" with
      | .if_ _ innerThen (some innerElse) =>
          expectAssignNameLiteral (← stmtAt innerThen.statements 0 "inner then") "total" 1
            "inner then"
          expectAssignNameLiteral (← stmtAt innerElse.statements 0 "inner else") "total" 2
            "inner else"
      | other => throw <| IO.userError s!"inner dangling-if shape changed: {repr other}"
  | other => throw <| IO.userError s!"outer dangling-if shape changed: {repr other}"
  expectAssignNameLiteral (← stmtAt danglingStatements 1 "after dangling if") "total" 3
    "after dangling if"

  let forStatements ← decodeEntryStatements session "for-order"
    ("    for i in a ..< total bounded 4096 do\n" ++
     "      total := i\n" ++
     "      total := total + i\n" ++
     "    total := a\n")
  expect (forStatements.size == 3) "for source order changed"
  match ← stmtAt forStatements 0 "for" with
  | .for_ binder start stop bound body =>
      expect (binder.raw == "i") "for iterator raw identity changed"
      expectPlaceNameExpr start "a" "for start endpoint changed"
      expectPlaceNameExpr stop "total" "for end endpoint changed"
      expect (bound == UInt32.ofNat 4096) "for bound changed"
      expect (body.statements.size == 2) "for body statement order changed"
      expectAssignNameValue (← stmtAt body.statements 0 "for first body stmt") "total" "i"
        "for first body stmt"
      match ← stmtAt body.statements 1 "for second body stmt" with
      | .assign (.name target) (.binary .add lhs rhs) =>
          expect (target.raw == "total") "for second assignment target changed"
          expectPlaceNameExpr lhs "total" "for second assignment lhs changed"
          expectPlaceNameExpr rhs "i" "for second assignment rhs changed"
      | other => throw <| IO.userError s!"for second body statement changed: {repr other}"
  | other => throw <| IO.userError s!"for decoded to wrong statement: {repr other}"
  expectAssignNameValue (← stmtAt forStatements 1 "after for") "total" "a" "after for statement"

  let rawIteratorStatements ← decodeEntryStatements session "for-raw-iterator-zero-bound"
    ("    for «i.with.dot» in 0 ..< a bounded 0 do\n" ++
     "      total := «i.with.dot»\n")
  expect (rawIteratorStatements.size == 2) "zero-bound for source order changed"
  match ← stmtAt rawIteratorStatements 0 "raw iterator for" with
  | .for_ binder start stop bound body =>
      expect (binder.raw == "i.with.dot") "for escaped iterator raw identity changed"
      expectLiteralIntegerExpr start 0 "for zero-bound start endpoint changed"
      expectPlaceNameExpr stop "a" "for zero-bound end endpoint changed"
      expect (bound == UInt32.ofNat 0) "for zero bound changed"
      expect (body.statements.size == 1) "for zero-bound body size changed"
      expectAssignNameValue (← stmtAt body.statements 0 "raw iterator body") "total"
        "i.with.dot" "raw iterator body"
  | other => throw <| IO.userError s!"raw iterator for decoded incorrectly: {repr other}"

  expectReject session "malformed-if-missing-then"
    ("    if a > total\n" ++
     "      total := a\n")
    "failed to parse file"
  expectReject session "malformed-for-missing-do"
    ("    for i in a ..< total bounded 4\n" ++
     "      total := i\n")
    "failed to parse file"
  expectReject session "empty-if-then"
    "    if true then\n"
    "failed to parse file"
  expectReject session "empty-if-else"
    ("    if true then\n" ++
     "      total := a\n" ++
     "    else\n")
    "failed to parse file"
  expectReject session "empty-for-body"
    "    for i in a ..< total bounded 4 do\n"
    "failed to parse file"
  expectReject session "reserved-iterator"
    ("    for «for» in a ..< total bounded 4 do\n" ++
     "      total := a\n")
    "reserved portable identifier 'for'"
  expectReject session "qualified-iterator"
    ("    for A.i in a ..< total bounded 4 do\n" ++
     "      total := a\n")
    "unsupported portable statement"
  expectReject session "reserved-iterator-before-invalid-bound"
    ("    for «for» in a ..< total bounded 04 do\n" ++
     "      total := a\n")
    "reserved portable identifier 'for'"
  expectReject session "invalid-start-before-invalid-bound"
    ("    for i in «if» ..< total bounded 04 do\n" ++
     "      total := a\n")
    "reserved portable identifier 'if'"
  expectReject session "invalid-end-before-invalid-bound"
    ("    for i in a ..< «else» bounded 04 do\n" ++
     "      total := a\n")
    "reserved portable identifier 'else'"
  expectReject session "invalid-bound-leading-zero"
    ("    for i in a ..< total bounded 04 do\n" ++
     "      total := a\n")
    "unsupported portable statement"
  expectReject session "invalid-bound-hex"
    ("    for i in a ..< total bounded 0x10 do\n" ++
     "      total := a\n")
    "unsupported portable statement"
  expectReject session "invalid-bound-underscore"
    ("    for i in a ..< total bounded 1_0 do\n" ++
     "      total := a\n")
    "unsupported portable statement"
  expectReject session "over-bound"
    ("    for i in a ..< total bounded 4097 do\n" ++
     "      total := a\n")
    "unsupported portable statement"
  expectReject session "legacy-call-string-carrier"
    "    call \"legacy.effect\"\n"
    "failed to parse file"

end Tests.Language.ProgramV1ControlFlow
