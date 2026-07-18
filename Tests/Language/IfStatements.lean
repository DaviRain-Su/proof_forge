import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- IfSurface pins the complete optional-else Source carrier, including recursive
-- blocks and offside/dangling-else ownership. Zero migration: no existing suite edits.
namespace Tests.Language.IfStatementsFixture

open ProofForgeV2.Language

program IfSurface where
  init() do
    if true then
      assert true
    return 0

  entry run(flag : UInt64) : UInt64 do
    if flag then
      assert true
      return 1
    else
      assert false
      return 2
    return 0

  view peek() : UInt64 do
    if (true) then
      return 1
    else
      return 2
    return 0

  fn helper() : UInt64 do
    if 1 + 2 then
      if false then
        return 1
      else
        return 2
    else
      return 3
    return 0

end Tests.Language.IfStatementsFixture

namespace Tests.Language.IfStatementsFixture

open ProofForgeV2.Language

program IfAssignmentControl where
  state «then» : UInt64
  state «else» : UInt64

  init() do
    «then» := 1
    «else» := 2

  entry get() : UInt64 do
    return «then» + «else»

end Tests.Language.IfStatementsFixture

namespace Tests.Language.IfStatements

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def twin (statement : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.IfStatementsFixture.IfTwin" "IfTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[statement]
    }
  ]

private def typedTwin (statement : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.IfStatementsFixture.IfTypedTwin" "IfTypedTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[statement, .returnValue (.literal 0)]
    }
  ]

private def returnTwin : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.IfStatementsFixture.IfTypedTwin" "IfTypedTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue (.literal 0)]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.IfStatementsFixture\n\n" ++
  "program IfSurface where\n" ++
  "  init() do\n" ++
  "    if true then\n" ++
  "      assert true\n" ++
  "    return 0\n\n" ++
  "  entry run(flag : UInt64) : UInt64 do\n" ++
  "    if flag then\n" ++
  "      assert true\n" ++
  "      return 1\n" ++
  "    else\n" ++
  "      assert false\n" ++
  "      return 2\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    if (true) then\n" ++
  "      return 1\n" ++
  "    else\n" ++
  "      return 2\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    if 1 + 2 then\n" ++
  "      if false then\n" ++
  "        return 1\n" ++
  "      else\n" ++
  "        return 2\n" ++
  "    else\n" ++
  "      return 3\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.IfStatementsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.IfStatementsFixture\n\n" ++
  "program IfAssignmentControl where\n" ++
  "  state «then» : UInt64\n" ++
  "  state «else» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «then» := 1\n" ++
  "    «else» := 2\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «then» + «else»\n\n" ++
  "end Tests.Language.IfStatementsFixture\n"

private def entryProgramSource (name body : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  body ++
  "    return 0\n"

private def expectParserRejected (label source : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram message) =>
      expect (message.startsWith "Lean parser rejected source: failed to parse file")
        s!"{label}: expected parser-boundary rejection, got {message}"
  | .error other =>
      throw <| IO.userError s!"{label}: reached wrong failure: {other.render} for {source}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private unsafe def decodeFirst (session : Language.Loader.ParserSession)
    (name body : String) : IO Source.Statement := do
  let decoded ← select session (entryProgramSource name body) s!"<if-{name}>"
  match decoded.entries with
  | #[onlyEntry] =>
      match onlyEntry.body with
      | #[statement, .returnValue (.literal 0)] => pure statement
      | _ => throw <| IO.userError s!"{name}: expected if then return body"
  | _ => throw <| IO.userError s!"{name}: expected one entry"

private def expectGolden (label : String) (source : Source.Program)
    (expectedHash expectedSize : String) : IO Unit := do
  expect (source.sourceHash == expectedHash)
    s!"{label} sourceHash golden must remain stable; got {source.sourceHash}"
  expect (toString source.canonicalBytes.size == expectedSize)
    s!"{label} canonical size must remain stable; got {source.canonicalBytes.size}"

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.IfStatementsFixture.IfSurface
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.body == #[
          .ifStmt (.boolLiteral true) #[.assertStmt (.boolLiteral true)] none,
          .returnValue (.literal 0)])
        "initializer must retain an else-less if block"
  | none => throw <| IO.userError "IfSurface initializer missing"
  match elaborated.entries with
  | #[runEntry, peekEntry] =>
      expect (runEntry.body == #[
          .ifStmt (.variable "flag")
            #[.assertStmt (.boolLiteral true), .returnValue (.literal 1)]
            (some #[.assertStmt (.boolLiteral false), .returnValue (.literal 2)]),
          .returnValue (.literal 0)])
        "entry must retain condition and ordered then/else blocks"
      expect (peekEntry.body == #[
          .ifStmt (.boolLiteral true) #[.returnValue (.literal 1)]
            (some #[.returnValue (.literal 2)]),
          .returnValue (.literal 0)])
        "view must desugar grouped condition while retaining both blocks"
  | _ => throw <| IO.userError "IfSurface must retain entry and view"
  match elaborated.functions with
  | #[helper] =>
      expect (helper.body == #[
          .ifStmt (.checkedAdd (.literal 1) (.literal 2)) #[
            .ifStmt (.boolLiteral false) #[.returnValue (.literal 1)]
              (some #[.returnValue (.literal 2)])]
            (some #[.returnValue (.literal 3)]),
          .returnValue (.literal 0)])
        "fn must retain nested if ownership and expression tree"
  | _ => throw <| IO.userError "IfSurface helper missing"

  let session ← Tests.Language.ParserSession.shared
  let decoded ← select session surfaceSource "<if-surface>"
  expect (decoded == elaborated)
    "Loader and Lean command must agree on complete conditional Source"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must agree on conditional source identity"

  let noElse ← decodeFirst session "NoElse"
    "    if true then\n      assert true\n"
  let withElse ← decodeFirst session "WithElse"
    "    if flag then\n      return 1\n    else\n      return 2\n"
  let grouped ← decodeFirst session "Grouped"
    "    if (true) then\n      return 1\n"
  let nested ← decodeFirst session "Nested"
    "    if true then\n      if false then\n        return 1\n      else\n        return 2\n    else\n      return 3\n"
  expect (noElse == .ifStmt (.boolLiteral true) #[.assertStmt (.boolLiteral true)] none)
    "if-then must retain an absent else"
  expect (withElse == .ifStmt (.variable "flag") #[.returnValue (.literal 1)]
      (some #[.returnValue (.literal 2)]))
    "if-then-else must retain condition and branch content"
  expect (grouped == .ifStmt (.boolLiteral true) #[.returnValue (.literal 1)] none)
    "grouping must desugar inside an if condition"
  expect (nested == .ifStmt (.boolLiteral true) #[
      .ifStmt (.boolLiteral false) #[.returnValue (.literal 1)]
        (some #[.returnValue (.literal 2)])]
      (some #[.returnValue (.literal 3)]))
    "nested else must bind structurally to the nearest owning if"

  let twinNoElse := twin <| .ifStmt (.boolLiteral true)
    #[.assertStmt (.boolLiteral true)] none
  let twinCondition := twin <| .ifStmt (.boolLiteral false)
    #[.assertStmt (.boolLiteral true)] none
  let twinThenOrder := twin <| .ifStmt (.boolLiteral true)
    #[.assertStmt (.boolLiteral true), .returnValue (.literal 1)] none
  let twinThenReverse := twin <| .ifStmt (.boolLiteral true)
    #[.returnValue (.literal 1), .assertStmt (.boolLiteral true)] none
  let twinElse := twin <| .ifStmt (.boolLiteral true)
    #[.assertStmt (.boolLiteral true)] (some #[.returnValue (.literal 1)])
  let twinElseContent := twin <| .ifStmt (.boolLiteral true)
    #[.assertStmt (.boolLiteral true)] (some #[.returnValue (.literal 2)])
  let twinNested := twin <| .ifStmt (.boolLiteral true) #[
    .ifStmt (.boolLiteral false) #[.returnValue (.literal 1)]
      (some #[.returnValue (.literal 2)])] none

  -- Prospective goldens: deliberately UNBOUND in the tests-only RED.
  expectGolden "if no else" twinNoElse "UNBOUND" "UNBOUND"
  expectGolden "if condition" twinCondition "UNBOUND" "UNBOUND"
  expectGolden "if then order" twinThenOrder "UNBOUND" "UNBOUND"
  expectGolden "if else" twinElse "UNBOUND" "UNBOUND"
  expectGolden "if else content" twinElseContent "UNBOUND" "UNBOUND"
  expectGolden "if nested" twinNested "UNBOUND" "UNBOUND"

  expect (twinNoElse.sourceHash != twinCondition.sourceHash)
    "if condition value must bind source identity"
  expect (twinThenOrder.sourceHash != twinThenReverse.sourceHash)
    "then statement order must bind source identity"
  expect (twinNoElse.sourceHash != twinElse.sourceHash)
    "else marker must bind source identity"
  expect (twinElse.sourceHash != twinElseContent.sourceHash)
    "else statement content must bind source identity"
  expect (twinNoElse.sourceHash != twinNested.sourceHash)
    "nested statement kind must bind source identity"
  expect (twinNoElse.sourceHash != (twin (.assertStmt (.boolLiteral true))).sourceHash)
    "if tag 9 must not alias assert tag 4"
  expect (twinNoElse.sourceHash != (twin (.assertErrorStmt (.boolLiteral true) "Err")).sourceHash)
    "if tag 9 must not alias assert-error tag 8"
  expect (twinElse.sourceHash != (twin (.revertStmt "Err" #[])).sourceHash)
    "if must not alias revert"
  expect (twinElse.sourceHash != (twin (.emitStmt "Tick" #[])).sourceHash)
    "if must not alias emit"

  let rejected : Array (String × String) := #[
    ("missing condition", entryProgramSource "MissingCondition"
      "    if then\n      return 1\n"),
    ("missing then", entryProgramSource "MissingThen"
      "    if true\n      return 1\n"),
    ("same-line then body", entryProgramSource "SameLineThen"
      "    if true then return 1\n"),
    ("empty then body", entryProgramSource "EmptyThen"
      "    if true then\n"),
    ("same-column then body", entryProgramSource "SameColumnThen"
      "    if true then\n    return 1\n"),
    ("dangling else", entryProgramSource "DanglingElse"
      "    else\n      return 1\n"),
    ("deeper else", entryProgramSource "DeeperElse"
      "    if true then\n      return 1\n      else\n        return 2\n"),
    ("shallower else", entryProgramSource "ShallowerElse"
      "    if true then\n      return 1\n  else\n    return 2\n"),
    ("empty else body", entryProgramSource "EmptyElse"
      "    if true then\n      return 1\n    else\n"),
    ("duplicate else", entryProgramSource "DuplicateElse"
      "    if true then\n      return 1\n    else\n      return 2\n    else\n      return 3\n"),
    ("extra payload", entryProgramSource "ExtraIfPayload"
      "    if true then\n      return 1\n    2\n"),
    ("unescaped then assign", entryProgramSource "ThenAssign" "    then := 1\n"),
    ("unescaped else assign", entryProgramSource "ElseAssign" "    else := 1\n")
  ]
  for (label, source) in rejected do
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<if-reject-{label}>")
    expectParserRejected label source result

  let assignmentControl := Tests.Language.IfStatementsFixture.IfAssignmentControl
  match assignmentControl.initializer with
  | some initializer =>
      expect (initializer.body == #[.assign "then" (.literal 1), .assign "else" (.literal 2)])
        "escaped then/else assignments must remain Source assigns"
  | none => throw <| IO.userError "IfAssignmentControl initializer missing"
  let assignmentDecoded ← select session assignmentControlSource "<if-assignment-control>"
  expect (assignmentDecoded == assignmentControl)
    "Loader and Lean command must agree on escaped then/else assignments"

  for (label, statement) in [
      ("literal condition", Source.Statement.ifStmt (.literal 1)
        #[.returnValue (.literal 1)] none),
      ("string condition and invalid then", Source.Statement.ifStmt (.stringLiteral "x")
        #[.assign "missing" (.boolLiteral true)] none),
      ("bool condition and invalid else", Source.Statement.ifStmt (.boolLiteral true)
        #[.returnValue (.literal 1)] (some #[.returnUnit]))
    ] do
    match Compiler.compile (typedTwin statement) with
    | .error (.invalidProgram
        "if statements are not yet supported by typed checking") => pure ()
    | .error other =>
        throw <| IO.userError s!"{label}: Typed if priority mismatch: {other.render}"
    | .ok _ => throw <| IO.userError s!"{label}: Typed unexpectedly accepted if"

  match Compiler.compile returnTwin with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"return control failed: {error.render}"
  match Compiler.compile (typedTwin (.assertStmt (.boolLiteral true))) with
  | .error (.invalidProgram
      "assert statements are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"assert control changed: {other.render}"
  | .ok _ => throw <| IO.userError "assert control unexpectedly compiled"
  match Compiler.compile (typedTwin (.revertStmt "Err" #[])) with
  | .error (.invalidProgram
      "revert statements are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"revert control changed: {other.render}"
  | .ok _ => throw <| IO.userError "revert control unexpectedly compiled"
  match Compiler.compile (typedTwin (.emitStmt "Tick" #[])) with
  | .error (.invalidProgram
      "emit statements are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"emit control changed: {other.render}"
  | .ok _ => throw <| IO.userError "emit control unexpectedly compiled"

end Tests.Language.IfStatements
