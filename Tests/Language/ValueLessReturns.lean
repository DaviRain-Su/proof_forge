import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- ValueLessReturnSurface pins bare `return` (prospective returnUnit) in init/entry/view/fn
-- with explicit Unit results. Zero migration: no existing suite edits.
namespace Tests.Language.ValueLessReturnsFixture

open ProofForgeV2.Language

program ValueLessReturnSurface where
  init() do
    return

  entry run() : Unit do
    return

  view peek() : Unit do
    return

  fn helper() : Unit do
    return

end Tests.Language.ValueLessReturnsFixture

-- Omitted Unit result materialization still accepts bare return at Source only.
namespace Tests.Language.ValueLessReturnsFixture

open ProofForgeV2.Language

program OmittedUnitBareReturn where
  entry run() do
    return

  view peek() do
    return

  fn helper() do
    return

end Tests.Language.ValueLessReturnsFixture

-- Non-Unit declaration: Source may still carry returnUnit; Typed must fail closed.
namespace Tests.Language.ValueLessReturnsFixture

open ProofForgeV2.Language

program NonUnitBareReturn where
  entry run() : UInt64 do
    return

end Tests.Language.ValueLessReturnsFixture

-- Escaped assignment identifier must remain assign, not return keyword.
namespace Tests.Language.ValueLessReturnsFixture

open ProofForgeV2.Language

program ReturnAssignmentControl where
  state «return» : UInt64

  init() do
    «return» := 1

  entry get() : UInt64 do
    return «return»

end Tests.Language.ValueLessReturnsFixture

namespace Tests.Language.ValueLessReturns

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Twin isolating a single statement then a valued return under fixed identity. -/
private def twin (stmt : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ValueLessReturnsFixture.ValueLessTwin" "ValueLessTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[stmt, .returnValue (.literal 0)]
    }
  ]

/-- Twin whose sole body statement is bare returnUnit (Unit result). -/
private def unitTwin (stmt : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ValueLessReturnsFixture.ValueLessUnitTwin" "ValueLessUnitTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .unit
      mode := .mutate
      body := #[stmt]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ValueLessReturnsFixture\n\n" ++
  "program ValueLessReturnSurface where\n" ++
  "  init() do\n" ++
  "    return\n\n" ++
  "  entry run() : Unit do\n" ++
  "    return\n\n" ++
  "  view peek() : Unit do\n" ++
  "    return\n\n" ++
  "  fn helper() : Unit do\n" ++
  "    return\n\n" ++
  "end Tests.Language.ValueLessReturnsFixture\n"

private def omittedUnitSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ValueLessReturnsFixture\n\n" ++
  "program OmittedUnitBareReturn where\n" ++
  "  entry run() do\n" ++
  "    return\n\n" ++
  "  view peek() do\n" ++
  "    return\n\n" ++
  "  fn helper() do\n" ++
  "    return\n\n" ++
  "end Tests.Language.ValueLessReturnsFixture\n"

private def nonUnitSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ValueLessReturnsFixture\n\n" ++
  "program NonUnitBareReturn where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return\n\n" ++
  "end Tests.Language.ValueLessReturnsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ValueLessReturnsFixture\n\n" ++
  "program ReturnAssignmentControl where\n" ++
  "  state «return» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «return» := 1\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «return»\n\n" ++
  "end Tests.Language.ValueLessReturnsFixture\n"

private def bodyProgramSource (name body : String) (result : String := "UInt64") : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : " ++ result ++ " do\n" ++
  "    " ++ body ++ "\n"

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

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.ValueLessReturnsFixture.ValueLessReturnSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "init body must retain bare return as returnUnit"
  | none => throw <| IO.userError "ValueLessReturnSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      expect (runEntry.result == .unit) "run must have Unit result"
      match runEntry.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "entry body must retain bare return as returnUnit"
      expect (peekView.mode == .view && peekView.result == .unit)
        "peek must remain a Unit view"
      match peekView.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "view body must retain bare return as returnUnit"
  | _ => throw <| IO.userError "ValueLessReturnSurface must retain run entry and peek view"
  match elaborated.functions.back? with
  | some helper =>
      expect (helper.name == "helper" && helper.result == .unit)
        "helper must be Unit fn"
      match helper.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "fn helper body must retain bare return as returnUnit"
  | none => throw <| IO.userError "ValueLessReturnSurface must retain functions"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<value-less-returns>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same returnUnit Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same returnUnit sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Omitted Unit result + bare return (Source parity only).
  let omittedElab := Tests.Language.ValueLessReturnsFixture.OmittedUnitBareReturn
  match omittedElab.entries with
  | #[runEntry, peekView] =>
      expect (runEntry.result == .unit && peekView.result == .unit)
        "omitted results must materialize to Unit"
      match runEntry.body, peekView.body with
      | #[.returnUnit], #[.returnUnit] => pure ()
      | _, _ =>
          throw <| IO.userError
            "omitted-Unit entry/view must retain bare return as returnUnit"
  | _ => throw <| IO.userError "OmittedUnitBareReturn must retain entry and view"
  match omittedElab.functions.back? with
  | some helper =>
      expect (helper.result == .unit) "omitted fn result must materialize to Unit"
      match helper.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "omitted-Unit fn must retain bare return as returnUnit"
  | none => throw <| IO.userError "OmittedUnitBareReturn must retain functions"
  match ← session.selectProgram omittedUnitSource "<value-less-omitted-unit>" none with
  | .ok decoded =>
      expect (decoded == omittedElab)
        "Loader and Lean command must agree on omitted-Unit bare return"
  | .error error => throw <| IO.userError error.render

  -- Non-Unit declaration still carries returnUnit at Source.
  let nonUnitElab := Tests.Language.ValueLessReturnsFixture.NonUnitBareReturn
  match nonUnitElab.entries with
  | #[runEntry] =>
      expect (runEntry.result == .u64) "non-Unit entry must keep UInt64 result"
      match runEntry.body with
      | #[.returnUnit] => pure ()
      | _ =>
          throw <| IO.userError
            "non-Unit entry must still parse bare return as returnUnit at Source"
  | _ => throw <| IO.userError "NonUnitBareReturn must retain a single entry"
  match ← session.selectProgram nonUnitSource "<value-less-non-unit>" none with
  | .ok decoded =>
      expect (decoded == nonUnitElab)
        "Loader and Lean command must agree on non-Unit bare return Source"
  | .error error => throw <| IO.userError error.render

  -- Value-bearing priority: return 1 / return true / return add stay returnValue.
  let retOne ← select session
    (bodyProgramSource "RetOne" "return 1") "<vlr-return-1>"
  match retOne.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.returnValue (.literal 1)] => pure ()
      | _ => throw <| IO.userError "return 1 must remain returnValue (longest match)"
  | _ => throw <| IO.userError "return 1 program must have one entry"

  let retTrue ← select session
    (bodyProgramSource "RetTrue" "return true") "<vlr-return-true>"
  match retTrue.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.returnValue (.boolLiteral true)] => pure ()
      | _ => throw <| IO.userError "return true must remain returnValue (longest match)"
  | _ => throw <| IO.userError "return true program must have one entry"

  let retAdd ← select session
    (bodyProgramSource "RetAdd" "return 1 + 2") "<vlr-return-add>"
  match retAdd.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.returnValue (.checkedAdd (.literal 1) (.literal 2))] => pure ()
      | _ => throw <| IO.userError "return 1 + 2 must remain returnValue (longest match)"
  | _ => throw <| IO.userError "return add program must have one entry"

  -- Cross-line layout retention: return newline 1 stays returnValue (not bare+junk).
  let crossLineSource :=
    "import ProofForgeV2\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CrossLineReturn where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return\n" ++
    "      1\n"
  let crossLine ← select session crossLineSource "<vlr-cross-line>"
  match crossLine.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.returnValue (.literal 1)] => pure ()
      | _ =>
          throw <| IO.userError
            "cross-line return newline 1 must remain returnValue (layout retained)"
  | _ => throw <| IO.userError "cross-line return program must have one entry"

  -- Bare return then next-line assignment: returnUnit then assign (not value-bearing).
  let bareThenAssignSource :=
    "import ProofForgeV2\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BareThenAssign where\n" ++
    "  state x : UInt64\n\n" ++
    "  entry run() : Unit do\n" ++
    "    return\n" ++
    "    x := 1\n"
  let bareThenAssign ← select session bareThenAssignSource "<vlr-bare-then-assign>"
  match bareThenAssign.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.returnUnit, .assign "x" (.literal 1)] => pure ()
      | _ =>
          throw <| IO.userError
            "bare return then next-line x := 1 must be returnUnit then assign"
  | _ => throw <| IO.userError "bare-then-assign program must have one entry"

  -- Bare return via Loader under fixed program name.
  let bare ← select session
    (bodyProgramSource "BareReturn" "return" "Unit") "<vlr-bare>"
  match bare.entries with
  | #[runEntry] =>
      match runEntry.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "bare return must form returnUnit"
  | _ => throw <| IO.userError "bare return program must have one entry"

  -- Prospective goldens (UNBOUND until GREEN).
  let twinUnit := unitTwin .returnUnit
  let twinVal0 := unitTwin (.returnValue (.literal 0))
  let twinValTrue := twin (.returnValue (.boolLiteral true))
  let twinAssert := twin (.assertStmt (.boolLiteral true))
  let twinRevert := twin (.revertStmt "Err" #[])

  expect (twinUnit.sourceHash ==
      "UNBOUND_RETURN_UNIT_GOLDEN")
    s!"returnUnit ValueLessUnitTwin sourceHash golden must remain stable; got {twinUnit.sourceHash}"
  expect (toString twinUnit.canonicalBytes.size ==
      "UNBOUND_RETURN_UNIT_SIZE")
    s!"returnUnit ValueLessUnitTwin size golden must remain stable; got {twinUnit.canonicalBytes.size}"

  -- Non-alias: tag6 vs returnValue tag1 and other statements.
  expect (twinUnit.sourceHash != twinVal0.sourceHash)
    "returnUnit must not alias returnValue 0 (tag 6 vs tag 1)"
  expect (twinUnit.sourceHash != twinValTrue.sourceHash)
    "returnUnit must not alias returnValue true under different twin shape without collapsing kinds"
  expect (twinUnit.sourceHash != twinAssert.sourceHash)
    "returnUnit must not alias assertStmt"
  expect (twinUnit.sourceHash != twinRevert.sourceHash)
    "returnUnit must not alias revertStmt"

  -- Parser-boundary rejects.
  for (label, body) in [
      ("return empty paren", "return()"),
      ("bare then paren", "return ()"),
      ("bare then comma", "return ,"),
      ("extra payload", "return 1 2"),
      ("unescaped keyword assign", "return := 1")
    ] do
    let source := bodyProgramSource "RejectedVlr" body
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<vlr-{label}>")
    expectParserRejected label source result

  -- Escaped assignment identifier retention.
  let assignControl := Tests.Language.ValueLessReturnsFixture.ReturnAssignmentControl
  match assignControl.initializer with
  | some initializer =>
      expect (initializer.body == #[.assign "return" (.literal 1)])
        "«return» := 1 must remain Source.Statement.assign to identifier 'return'"
  | none => throw <| IO.userError "ReturnAssignmentControl must retain initializer"
  match ← session.selectProgram assignmentControlSource "<vlr-assignment-control>" none with
  | .ok decoded =>
      expect (decoded == assignControl)
        "Loader and Lean command must agree on return-assignment positive control"
  | .error error => throw <| IO.userError error.render

  -- Typed fail-before result/Unit/init/path analysis.
  match Compiler.compile (unitTwin .returnUnit) with
  | .error (.invalidProgram
      "value-less return is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject returnUnit with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing returnUnit"

  -- Source carries returnUnit for omitted-result fn, non-Unit entry, and initializer;
  -- Typed exact-fails identically on all three (not Unit auto-accept / type-mismatch first).
  let omittedFnElab := Tests.Language.ValueLessReturnsFixture.OmittedUnitBareReturn
  match omittedFnElab.functions.back? with
  | some helper =>
      match helper.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "omitted-result fn Source must carry returnUnit"
  | none => throw <| IO.userError "omitted-result fn missing"
  match Compiler.compile omittedFnElab with
  | .error (.invalidProgram
      "value-less return is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject omitted-result fn bare return with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept omitted-result fn bare return"

  match Compiler.compile nonUnitElab with
  | .error (.invalidProgram
      "value-less return is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject non-Unit bare return before type mismatch, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept non-Unit bare return"

  -- Initializer: surface dual-entry already carries returnUnit; Typed same diagnostic.
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.returnUnit] => pure ()
      | _ => throw <| IO.userError "initializer Source must carry returnUnit"
  | none => throw <| IO.userError "initializer missing"
  match Compiler.compile elaborated with
  | .error (.invalidProgram
      "value-less return is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject initializer bare return with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept surface with initializer bare return"

  -- Existing returnValue control still compiles.
  match Compiler.compile (twin (.returnValue (.literal 0))) with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"returnValue control under ValueLessTwin must still compile, got {error.render}"

end Tests.Language.ValueLessReturns
