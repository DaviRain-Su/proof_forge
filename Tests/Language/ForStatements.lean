import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- ForSurface pins the complete bounded-for Source carrier and strict offside
-- layout. Zero migration: no existing suite is edited.
namespace Tests.Language.ForStatementsFixture

open ProofForgeV2.Language

program ForSurface where
  init(limit : UInt64) do
    for i in 0 ..< limit bounded 4096 do
      assert true
    return 0

  entry run(limit : UInt64) : UInt64 do
    for i in 1..<limit + 1 bounded 4 do
      assert true
      return 1
    return 0

  view peek() : UInt64 do
    for j in (0) ..< (2 + 3) bounded 0 do
      return 1
    return 0

  fn helper() : UInt64 do
    for outer in 0 ..< 2 bounded 2 do
      for inner in 1 ..< 3 bounded 2 do
        return 1
    return 0

end Tests.Language.ForStatementsFixture

namespace Tests.Language.ForStatementsFixture

open ProofForgeV2.Language

program ForAssignmentControl where
  state «for» : UInt64
  state «in» : UInt64
  state «bounded» : UInt64

  init() do
    «for» := 1
    «in» := 2
    «bounded» := 3

  entry get() : UInt64 do
    return «for» + «in» + «bounded»

end Tests.Language.ForStatementsFixture

namespace Tests.Language.ForStatements

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def twin (statement : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ForStatementsFixture.ForTwin" "ForTwin" #[
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
    "Tests.Language.ForStatementsFixture.ForTypedTwin" "ForTypedTwin" #[
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
    "Tests.Language.ForStatementsFixture.ForTypedTwin" "ForTypedTwin" #[
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
  "namespace Tests.Language.ForStatementsFixture\n\n" ++
  "program ForSurface where\n" ++
  "  init(limit : UInt64) do\n" ++
  "    for i in 0 ..< limit bounded 4096 do\n" ++
  "      assert true\n" ++
  "    return 0\n\n" ++
  "  entry run(limit : UInt64) : UInt64 do\n" ++
  "    for i in 1..<limit + 1 bounded 4 do\n" ++
  "      assert true\n" ++
  "      return 1\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    for j in (0) ..< (2 + 3) bounded 0 do\n" ++
  "      return 1\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    for outer in 0 ..< 2 bounded 2 do\n" ++
  "      for inner in 1 ..< 3 bounded 2 do\n" ++
  "        return 1\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.ForStatementsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ForStatementsFixture\n\n" ++
  "program ForAssignmentControl where\n" ++
  "  state «for» : UInt64\n" ++
  "  state «in» : UInt64\n" ++
  "  state «bounded» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «for» := 1\n" ++
  "    «in» := 2\n" ++
  "    «bounded» := 3\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «for» + «in» + «bounded»\n\n" ++
  "end Tests.Language.ForStatementsFixture\n"

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

private def expectUnsupportedStatement (label : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram "unsupported portable statement") => pure ()
  | .error other =>
      throw <| IO.userError s!"{label}: expected unsupported statement, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private unsafe def decodeFirst (session : Language.Loader.ParserSession)
    (name body : String) : IO Source.Statement := do
  let decoded ← select session (entryProgramSource name body) s!"<for-{name}>"
  match decoded.entries with
  | #[onlyEntry] =>
      match onlyEntry.body with
      | #[statement, .returnValue (.literal 0)] => pure statement
      | _ => throw <| IO.userError s!"{name}: expected for then return body"
  | _ => throw <| IO.userError s!"{name}: expected one entry"

private def expectGolden (label : String) (source : Source.Program)
    (expectedHash expectedSize : String) : IO Unit := do
  expect (source.sourceHash == expectedHash)
    s!"{label} sourceHash golden must remain stable; got {source.sourceHash}"
  expect (toString source.canonicalBytes.size == expectedSize)
    s!"{label} canonical size must remain stable; got {source.canonicalBytes.size}"

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.ForStatementsFixture.ForSurface
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.body == #[
          .forStmt "i" (.literal 0) (.variable "limit") 4096
            #[.assertStmt (.boolLiteral true)],
          .returnValue (.literal 0)])
        "initializer must retain bound 4096 and ordered for body"
  | none => throw <| IO.userError "ForSurface initializer missing"
  match elaborated.entries with
  | #[runEntry, peekEntry] =>
      expect (runEntry.body == #[
          .forStmt "i" (.literal 1) (.checkedAdd (.variable "limit") (.literal 1)) 4
            #[.assertStmt (.boolLiteral true), .returnValue (.literal 1)],
          .returnValue (.literal 0)])
        "entry must retain compact range, endpoints, bound and body order"
      expect (peekEntry.body == #[
          .forStmt "j" (.literal 0) (.checkedAdd (.literal 2) (.literal 3)) 0
            #[.returnValue (.literal 1)],
          .returnValue (.literal 0)])
        "view must desugar grouped endpoints and retain bound zero"
  | _ => throw <| IO.userError "ForSurface must retain entry and view"
  match elaborated.functions with
  | #[helper] =>
      expect (helper.body == #[
          .forStmt "outer" (.literal 0) (.literal 2) 2 #[
            .forStmt "inner" (.literal 1) (.literal 3) 2
              #[.returnValue (.literal 1)]],
          .returnValue (.literal 0)])
        "fn must retain nested bounded-for structure"
  | _ => throw <| IO.userError "ForSurface helper missing"

  let session ← Tests.Language.ParserSession.shared
  let decoded ← select session surfaceSource "<for-surface>"
  expect (decoded == elaborated)
    "Loader and Lean command must agree on complete bounded-for Source"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must agree on bounded-for source identity"

  let spaced ← decodeFirst session "Spaced"
    "    for i in 0 ..< 10 bounded 4 do\n      return 1\n"
  let compact ← decodeFirst session "Compact"
    "    for i in 0..<10 bounded 4 do\n      return 1\n"
  let expressionEndpoints ← decodeFirst session "ExpressionEndpoints"
    "    for i in (1 + 2) ..< limit * 2 bounded 4096 do\n      return 1\n"
  let nested ← decodeFirst session "Nested"
    "    for outer in 0 ..< 2 bounded 2 do\n      for inner in 1 ..< 3 bounded 2 do\n        return 1\n"
  expect (spaced == .forStmt "i" (.literal 0) (.literal 10) 4
      #[.returnValue (.literal 1)])
    "spaced bounded-for must retain all fields"
  expect (compact == spaced)
    "compact and spaced exact range tokens must form the same Source tree"
  expect (expressionEndpoints == .forStmt "i"
      (.checkedAdd (.literal 1) (.literal 2))
      (.checkedMul (.variable "limit") (.literal 2)) 4096
      #[.returnValue (.literal 1)])
    "full expression endpoints and maximum bound must survive decode"
  expect (nested == .forStmt "outer" (.literal 0) (.literal 2) 2 #[
      .forStmt "inner" (.literal 1) (.literal 3) 2
        #[.returnValue (.literal 1)]])
    "nested for body must survive recursive decode"

  let twinBase := twin <| .forStmt "i" (.literal 0) (.literal 10) 4
    #[.assertStmt (.boolLiteral true)]
  let twinIterator := twin <| .forStmt "j" (.literal 0) (.literal 10) 4
    #[.assertStmt (.boolLiteral true)]
  let twinStart := twin <| .forStmt "i" (.literal 1) (.literal 10) 4
    #[.assertStmt (.boolLiteral true)]
  let twinStop := twin <| .forStmt "i" (.literal 0) (.literal 11) 4
    #[.assertStmt (.boolLiteral true)]
  let twinBound := twin <| .forStmt "i" (.literal 0) (.literal 10) 5
    #[.assertStmt (.boolLiteral true)]
  let twinBody := twin <| .forStmt "i" (.literal 0) (.literal 10) 4
    #[.returnValue (.literal 1)]
  let twinBodyOrder := twin <| .forStmt "i" (.literal 0) (.literal 10) 4
    #[.assertStmt (.boolLiteral true), .returnValue (.literal 1)]
  let twinBodyReverse := twin <| .forStmt "i" (.literal 0) (.literal 10) 4
    #[.returnValue (.literal 1), .assertStmt (.boolLiteral true)]
  let twinNested := twin <| .forStmt "i" (.literal 0) (.literal 10) 4 #[
    .forStmt "j" (.literal 1) (.literal 2) 1 #[.returnValue (.literal 1)]]

  -- Bound independently after the tests-only RED commit.
  expectGolden "for base" twinBase
    "99b116672a93b719e2fe3bf8416b7fcadd990fd9270932fcc8e5f838689d44ef" "244"
  expectGolden "for iterator" twinIterator
    "b1a145ce2fea8c986ef423c3bfde8f45800804f5f5925728a0e4e20e13bfa2dc" "244"
  expectGolden "for start" twinStart
    "4cd2f6a0b5860205f28db60c5dfe36fc978af9a94b1cdca3fa42df0d7b3e15f9" "244"
  expectGolden "for stop" twinStop
    "3e419a96934adae8d4834741f28bbbd724911f36b2c5cc1358d8e8a9090cb71a" "244"
  expectGolden "for bound" twinBound
    "1c8d8d6c8610739095bf59d30b1758a50b907954f4557b10fd99b0f20d2dadb9" "244"
  expectGolden "for nested" twinNested
    "01c8e020e61ef5fc43f020e5e90d17cda14ffd77634d9e293ba5ee6e43f9dc3d" "295"

  expect (twinBase.sourceHash != twinIterator.sourceHash)
    "for iterator must bind source identity"
  expect (twinBase.sourceHash != twinStart.sourceHash)
    "for start endpoint must bind source identity"
  expect (twinBase.sourceHash != twinStop.sourceHash)
    "for stop-exclusive endpoint must bind source identity"
  expect (twinBase.sourceHash != twinBound.sourceHash)
    "for max-iteration bound must bind source identity"
  expect (twinBase.sourceHash != twinBody.sourceHash)
    "for body content must bind source identity"
  expect (twinBase.sourceHash != twinBodyOrder.sourceHash)
    "for body statement count must bind source identity"
  expect (twinBodyOrder.sourceHash != twinBodyReverse.sourceHash)
    "for body statement order must bind source identity"
  expect (twinBase.sourceHash != twinNested.sourceHash)
    "nested for kind must bind source identity"
  expect (twinBase.sourceHash != (twin (.ifStmt (.boolLiteral true)
      #[.returnValue (.literal 1)] none)).sourceHash)
    "for tag 10 must not alias if tag 9"
  expect (twinBase.sourceHash != (twin (.returnValue (.literal 1))).sourceHash)
    "for tag 10 must not alias return"
  expect (twinBase.sourceHash != (twin (.revertStmt "Err" #[])).sourceHash)
    "for tag 10 must not alias revert"
  expect (twinBase.sourceHash != (twin (.emitStmt "Tick" #[])).sourceHash)
    "for tag 10 must not alias emit"

  let parserRejected : Array (String × String) := #[
    ("missing iterator", entryProgramSource "MissingIterator"
      "    for in 0 ..< 10 bounded 4 do\n      return 1\n"),
    ("missing in", entryProgramSource "MissingIn"
      "    for i 0 ..< 10 bounded 4 do\n      return 1\n"),
    ("missing range", entryProgramSource "MissingRange"
      "    for i in 0 10 bounded 4 do\n      return 1\n"),
    ("missing stop", entryProgramSource "MissingStop"
      "    for i in 0 ..< bounded 4 do\n      return 1\n"),
    ("missing bounded", entryProgramSource "MissingBounded"
      "    for i in 0 ..< 10 4 do\n      return 1\n"),
    ("missing bound", entryProgramSource "MissingBound"
      "    for i in 0 ..< 10 bounded do\n      return 1\n"),
    ("missing do", entryProgramSource "MissingDo"
      "    for i in 0 ..< 10 bounded 4\n      return 1\n"),
    ("split before in", entryProgramSource "SplitIn"
      "    for i\n      in 0 ..< 10 bounded 4 do\n      return 1\n"),
    ("split before range", entryProgramSource "SplitRange"
      "    for i in 0\n      ..< 10 bounded 4 do\n      return 1\n"),
    ("split before bounded", entryProgramSource "SplitBounded"
      "    for i in 0 ..< 10\n      bounded 4 do\n      return 1\n"),
    ("split before do", entryProgramSource "SplitDo"
      "    for i in 0 ..< 10 bounded 4\n      do\n      return 1\n"),
    ("same-line body", entryProgramSource "SameLineBody"
      "    for i in 0 ..< 10 bounded 4 do return 1\n"),
    ("same-column body", entryProgramSource "SameColumnBody"
      "    for i in 0 ..< 10 bounded 4 do\n    return 1\n"),
    ("empty body", entryProgramSource "EmptyBody"
      "    for i in 0 ..< 10 bounded 4 do\n"),
    ("internally split range", entryProgramSource "SplitRangeToken"
      "    for i in 0 .. < 10 bounded 4 do\n      return 1\n"),
    ("negative bound", entryProgramSource "NegativeBound"
      "    for i in 0 ..< 10 bounded -1 do\n      return 1\n"),
    ("extra payload", entryProgramSource "ExtraPayload"
      "    for i in 0 ..< 10 bounded 4 do\n      return 1\n    2\n"),
    ("unescaped for assign", entryProgramSource "ForAssign" "    for := 1\n"),
    ("unescaped in assign", entryProgramSource "InAssign" "    in := 1\n"),
    ("unescaped bounded assign", entryProgramSource "BoundedAssign" "    bounded := 1\n")
  ]
  for (label, source) in parserRejected do
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<for-reject-{label}>")
    expectParserRejected label source result

  for (label, spelling) in [
      ("over-bound", "4097"),
      ("leading-zero bound", "01"),
      ("hex bound", "0x10"),
      ("underscore bound", "1_0")
    ] do
    expectUnsupportedStatement label
      (← session.parsePrograms
        (entryProgramSource "RejectedForBound"
          s!"    for i in 0 ..< 10 bounded {spelling} do\n      return 1\n")
        s!"<for-bound-{label}>")

  let assignmentControl := Tests.Language.ForStatementsFixture.ForAssignmentControl
  match assignmentControl.initializer with
  | some initializer =>
      expect (initializer.body == #[
          .assign "for" (.literal 1),
          .assign "in" (.literal 2),
          .assign "bounded" (.literal 3)])
        "escaped for/in/bounded assignments must remain Source assigns"
  | none => throw <| IO.userError "ForAssignmentControl initializer missing"
  let assignmentDecoded ← select session assignmentControlSource "<for-assignment-control>"
  expect (assignmentDecoded == assignmentControl)
    "Loader and Lean command must agree on escaped for/in/bounded assignments"

  for (label, statement) in [
      ("unknown iterator and string endpoints", Source.Statement.forStmt "missing"
        (.stringLiteral "start") (.stringLiteral "stop") 4
        #[.assign "missing" (.boolLiteral true)]),
      ("zero bound and invalid body", Source.Statement.forStmt "i"
        (.literal 0) (.literal 1) 0 #[.returnUnit]),
      ("maximum bound and nested invalid body", Source.Statement.forStmt "i"
        (.literal 0) (.literal 1) 4096 #[
          .ifStmt (.stringLiteral "condition") #[.returnUnit] none])
    ] do
    match Compiler.compile (typedTwin statement) with
    | .error (.invalidProgram
        "for statements are not yet supported by typed checking") => pure ()
    | .error other =>
        throw <| IO.userError s!"{label}: Typed for priority mismatch: {other.render}"
    | .ok _ => throw <| IO.userError s!"{label}: Typed unexpectedly accepted for"

  match Compiler.compile returnTwin with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"return control failed: {error.render}"
  match Compiler.compile (typedTwin (.ifStmt (.boolLiteral true)
      #[.returnValue (.literal 1)] none)) with
  | .error (.invalidProgram
      "if statements are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"if control changed: {other.render}"
  | .ok _ => throw <| IO.userError "if control unexpectedly compiled"
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

end Tests.Language.ForStatements
