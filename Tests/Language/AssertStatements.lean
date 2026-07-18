import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- AssertSurface pins bare `assert Expr` in every declaration body position: init,
-- entry, view, and fn. Covers literal, variable, Bool, binary, and grouped conditions.
namespace Tests.Language.AssertStatementsFixture

open ProofForgeV2.Language

program AssertSurface where
  init() do
    assert true
    return 0

  entry run(flag : UInt64) : UInt64 do
    assert flag
    return 0

  view peek() : UInt64 do
    assert (true)
    return 0

  fn helper() : UInt64 do
    assert 1 + 2
    return 0

end Tests.Language.AssertStatementsFixture

-- Positive control: escaped identifier `«assert»` remains a legal assignment target.
namespace Tests.Language.AssertStatementsFixture

open ProofForgeV2.Language

program AssertAssignmentControl where
  state «assert» : UInt64

  init() do
    «assert» := 1

  entry get() : UInt64 do
    return «assert»

end Tests.Language.AssertStatementsFixture

namespace Tests.Language.AssertStatements

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating assertStmt under one fixed identity. -/
private def twin (condition : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.AssertStatementsFixture.AssertTwin" "AssertTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.assertStmt condition]
    }
  ]

private def returnTwin (condition : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.AssertStatementsFixture.AssertTwin" "AssertTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue condition]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.AssertStatementsFixture\n\n" ++
  "program AssertSurface where\n" ++
  "  init() do\n" ++
  "    assert true\n" ++
  "    return 0\n\n" ++
  "  entry run(flag : UInt64) : UInt64 do\n" ++
  "    assert flag\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    assert (true)\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    assert 1 + 2\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.AssertStatementsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.AssertStatementsFixture\n\n" ++
  "program AssertAssignmentControl where\n" ++
  "  state «assert» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «assert» := 1\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «assert»\n\n" ++
  "end Tests.Language.AssertStatementsFixture\n"

private def bodyProgramSource (name bodyLine : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    " ++ bodyLine ++ "\n" ++
  "    return 0\n"

private def expectParserRejected (label source : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram message) =>
      expect (message.startsWith "Lean parser rejected source: failed to parse file")
        s!"{label}: expected parser-boundary rejection, got {message}"
  | .error other =>
      throw <| IO.userError s!"{label}: reached wrong failure for {source}: {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.AssertStatementsFixture.AssertSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.assertStmt (.boolLiteral true), .returnValue (.literal 0)] => pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain assert true and return 0"
  | none => throw <| IO.userError "AssertSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.assertStmt (.variable "flag"), .returnValue (.literal 0)] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain assert flag with variable condition"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.assertStmt (.boolLiteral true), .returnValue (.literal 0)] => pure ()
      | _ =>
          throw <| IO.userError
            "view body must desugar assert (true) to boolLiteral true"
  | _ => throw <| IO.userError "AssertSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.assertStmt (.checkedAdd (.literal 1) (.literal 2)),
          .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain assert 1 + 2 as checkedAdd condition"
  | _ => throw <| IO.userError "AssertSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<assert-statements>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same assert Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same assert sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Same AssertTwin identity: assert true and assert (true) are identical programs.
  let assertTrue := twin (.boolLiteral true)
  let assertGroupedTrue := twin (.boolLiteral true)
  expect (assertTrue == assertGroupedTrue)
    "assert true and assert (true) must share Source AST under AssertTwin"
  expect (assertTrue.canonicalBytes == assertGroupedTrue.canonicalBytes)
    "assert true and assert (true) must share canonical bytes under AssertTwin"
  expect (assertTrue.sourceHash == assertGroupedTrue.sourceHash)
    "assert true and assert (true) must share sourceHash under AssertTwin"

  -- Surface parse of grouped form desugars to the same program as bare true.
  let bareTrue ← select session
    (bodyProgramSource "AssertBareTrue" "assert true") "<assert-bare-true>"
  let groupTrue ← select session
    (bodyProgramSource "AssertBareTrue" "assert (true)") "<assert-group-true>"
  expect (bareTrue == groupTrue)
    "parsed assert true and assert (true) must share Source.Program identity"
  expect (bareTrue.sourceHash == groupTrue.sourceHash)
    "parsed assert true and assert (true) must share sourceHash"
  match bareTrue.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.assertStmt (.boolLiteral true), .returnValue (.literal 0)] => pure ()
      | _ => throw <| IO.userError "assert true body must be assertStmt boolLiteral true"
  | _ => throw <| IO.userError "assert true program must have one entry"

  let literalCondition ← select session
    (bodyProgramSource "AssertLiteral" "assert 1") "<assert-literal>"
  match literalCondition.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.assertStmt (.literal 1), .returnValue (.literal 0)] => pure ()
      | _ => throw <| IO.userError "assert 1 body must retain a literal condition"
  | _ => throw <| IO.userError "assert literal program must have one entry"

  -- Frozen prospective goldens for AssertTwin (Statement tag 4 + condition).
  let assertFalse := twin (.boolLiteral false)
  let returnTrue := returnTwin (.boolLiteral true)
  expect (assertTrue.sourceHash ==
      "175f8718f5c59c0d4284e70de39b6bf51fe3990ede6401df10046e141bd9e3b2")
    s!"assert true AssertTwin sourceHash golden must remain stable; got {assertTrue.sourceHash}"
  expect (assertTrue.canonicalBytes.size == 209)
    s!"assert true AssertTwin size golden must remain stable; got {assertTrue.canonicalBytes.size}"
  expect (assertFalse.sourceHash ==
      "d53075d45436f72d54370b5f3ef3d10b21d4f30d6ee9ab706b96cdb7b118f66e")
    s!"assert false AssertTwin sourceHash golden must remain stable; got {assertFalse.sourceHash}"
  expect (assertFalse.canonicalBytes.size == 209)
    s!"assert false AssertTwin size golden must remain stable; got {assertFalse.canonicalBytes.size}"
  expect (returnTrue.sourceHash ==
      "cbee441c2ccee971516b1ea4e428ae21890bacc55ec4cd68517551a41efad014")
    s!"return true AssertTwin control sourceHash golden must remain stable; got {returnTrue.sourceHash}"
  expect (returnTrue.canonicalBytes.size == 209)
    s!"return true AssertTwin control size golden must remain stable; got {returnTrue.canonicalBytes.size}"

  -- Non-alias: statement tag and condition payload.
  expect (assertTrue.canonicalBytes.size == returnTrue.canonicalBytes.size)
    "assert true and return true must share canonical size (tag-only distinction)"
  expect (assertTrue.sourceHash != returnTrue.sourceHash)
    "assert true must not alias return true (statement tag)"
  expect (assertTrue.sourceHash != assertFalse.sourceHash)
    "assert true must not alias assert false (condition)"

  -- Keyword controls.
  let (_, bareAssignResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms
      (bodyProgramSource "BareAssertAssign" "assert := 1")
      "<assert-bare-assign>")
  expectParserRejected "bare assert :=" (bodyProgramSource "BareAssertAssign" "assert := 1")
    bareAssignResult

  let assignControl := Tests.Language.AssertStatementsFixture.AssertAssignmentControl
  match assignControl.initializer with
  | some initializer =>
      expect (initializer.body == #[.assign "assert" (.literal 1)])
        "«assert» := 1 must remain Source.Statement.assign to identifier 'assert'"
  | none => throw <| IO.userError "AssertAssignmentControl must retain initializer"
  match ← session.selectProgram assignmentControlSource "<assert-assignment-control>" none with
  | .ok decoded =>
      expect (decoded == assignControl)
        "Loader and Lean command must agree on assert-assignment positive control"
  | .error error => throw <| IO.userError error.render

  let assertValue ← select session
    (bodyProgramSource "AssertValueAssign" "assertValue := 1") "<assert-value-assign>"
  match assertValue.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.assign "assertValue" (.literal 1), .returnValue (.literal 0)] => pure ()
      | _ =>
          throw <| IO.userError
            "assertValue := 1 must remain assignment, not assertStmt"
  | _ => throw <| IO.userError "assertValue program must have one entry"

  -- Parser-boundary negatives; optional else Ident is explicitly deferred.
  for (label, spelling) in [
      ("bare assert", "assert"),
      ("extra payload", "assert true false"),
      ("optional else deferred", "assert true else Failure"),
      ("missing condition", "assert"),
      ("block-like then", "assert true then"),
      ("block-like do", "assert true do")
    ] do
    let source := bodyProgramSource "RejectedAssertShape" spelling
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<assert-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before condition checking: assert true hits assert diagnostic,
  -- not the Bool-expression diagnostic.
  match Compiler.compile (twin (.boolLiteral true)) with
  | .error (.invalidProgram
      "assert statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject assert with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing assertStmt"

  -- Existing statement controls remain available under AssertTwin identity.
  match Compiler.compile (returnTwin (.literal 0)) with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"return control under AssertTwin must still compile, got {error.render}"

  let assignTwin :=
    Source.Program.buildQualified
      "Tests.Language.AssertStatementsFixture.AssertTwin" "AssertTwin" #[
      .stateDecl { name := "cell", type := .u64 },
      .entry {
        name := "run"
        params := #[]
        result := .u64
        mode := .mutate
        body := #[
          .assign "cell" (.literal 1),
          .returnValue (.literal 0)
        ]
      }
    ]
  match Compiler.compile assignTwin with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"assignment control must still compile, got {error.render}"

  let callTwin :=
    Source.Program.buildQualified
      "Tests.Language.AssertStatementsFixture.AssertTwin" "AssertTwin" #[
      .entry {
        name := "run"
        params := #[]
        result := .u64
        mode := .mutate
        body := #[
          .synchronousCall "peer",
          .returnValue (.literal 0)
        ]
      }
    ]
  match Compiler.compile callTwin with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"call control must still compile, got {error.render}"

  let letTwin :=
    Source.Program.buildQualified
      "Tests.Language.AssertStatementsFixture.AssertTwin" "AssertTwin" #[
      .entry {
        name := "run"
        params := #[]
        result := .u64
        mode := .mutate
        body := #[
          .letDecl "x" (some .u64) (.literal 1),
          .returnValue (.literal 0)
        ]
      }
    ]
  match Compiler.compile letTwin with
  | .error (.invalidProgram
      "let statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"let control must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "let control must remain Typed fail-closed"

end Tests.Language.AssertStatements
