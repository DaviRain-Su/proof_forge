import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- LetSurface pins same-line let in every declaration body position: init, entry,
-- view, and fn. Both annotated and omitted type forms are required.
namespace Tests.Language.LetStatementsFixture

open ProofForgeV2.Language

program LetSurface where
  init() do
    let seed : UInt64 := 0
    return seed

  entry run() : UInt64 do
    let value : UInt64 := 1
    return value

  view peek() : UInt64 do
    let value := 0
    return value

  fn helper() : UInt64 do
    let value : UInt64 := 2
    return value

end Tests.Language.LetStatementsFixture

-- Positive control: escaped identifier `«let»` remains a legal assignment
-- target. After GREEN this must stay Source.Statement.assign, never letDecl.
namespace Tests.Language.LetStatementsFixture

open ProofForgeV2.Language

program LetAssignmentControl where
  state «let» : UInt64

  init() do
    «let» := 1

  entry get() : UInt64 do
    return «let»

end Tests.Language.LetStatementsFixture

namespace Tests.Language.LetStatements

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry body twin isolating letDecl fields under one fixed identity. -/
private def twinWith (binder : String) (typeAnn : Option Source.ValueType)
    (value : UInt64) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LetStatementsFixture.LetTwin" "LetTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[
        .letDecl binder typeAnn (.literal value),
        .returnValue (.variable "x")
      ]
    }
  ]

private def twin (typeAnn : Option Source.ValueType) : Source.Program :=
  twinWith "x" typeAnn 42

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.LetStatementsFixture\n\n" ++
  "program LetSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 0\n" ++
  "    return seed\n\n" ++
  "  entry run() : UInt64 do\n" ++
  "    let value : UInt64 := 1\n" ++
  "    return value\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 0\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    let value : UInt64 := 2\n" ++
  "    return value\n\n" ++
  "end Tests.Language.LetStatementsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.LetStatementsFixture\n\n" ++
  "program LetAssignmentControl where\n" ++
  "  state «let» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «let» := 1\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «let»\n\n" ++
  "end Tests.Language.LetStatementsFixture\n"

private def bodyProgramSource (name bodyLine : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    " ++ bodyLine ++ "\n" ++
  "    return 0\n"

private def expectUnsupported (label expected : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}'"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def expectParserRejected (label source : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram message) =>
      expect (message.startsWith "Lean parser rejected source: failed to parse file")
        s!"{label}: expected parser-boundary rejection, got {message}"
  | .error other =>
      throw <| IO.userError s!"{label}: reached wrong failure for {source}: {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.LetStatementsFixture.LetSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64) (.literal 0), .returnValue (.variable "seed")] =>
          pure ()
      | _ => throw <| IO.userError "init body must retain annotated let seed : UInt64 := 0"
  | none => throw <| IO.userError "LetSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.letDecl "value" (some .u64) (.literal 1), .returnValue (.variable "value")] =>
          pure ()
      | _ => throw <| IO.userError "entry body must retain annotated let value : UInt64 := 1"
      expect (peekView.mode == .view)
        "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none (.literal 0), .returnValue (.variable "value")] =>
          pure ()
      | _ => throw <| IO.userError "view body must retain omitted-type let value := 0"
  | _ => throw <| IO.userError "LetSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.letDecl "value" (some .u64) (.literal 2), .returnValue (.variable "value")] =>
          pure ()
      | _ => throw <| IO.userError "fn body must retain annotated let value : UInt64 := 2"
  | _ => throw <| IO.userError "LetSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<let-statements>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same let Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same let sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Frozen prospective goldens for LetTwin annotated vs omitted typeAnn.
  expect ((twin (some .u64)).sourceHash ==
      "7675d0399e7a8e95451633fdf7484d69adefb238d04af00b78ae7280078167d0")
    "annotated LetTwin sourceHash golden must remain stable"
  expect ((twin (some .u64)).canonicalBytes.size == 230)
    "annotated LetTwin canonical size golden must remain stable"
  expect ((twin none).sourceHash ==
      "537570f28ba78b8719bb73dc34aca2a54fe09fdec487abdce6fe88ded4d4b49b")
    "omitted LetTwin sourceHash golden must remain stable"
  expect ((twin none).canonicalBytes.size == 229)
    "omitted LetTwin canonical size golden must remain stable"
  expect ((twin (some .u64)).sourceHash != (twin none).sourceHash)
    "typeAnn some/none must bind sourceHash distinctly"
  expect ((twin (some .u64)).sourceHash != (twin (some .unit)).sourceHash)
    "typeAnn payload must bind sourceHash distinctly"
  expect ((twin (some .u64)).sourceHash !=
      (twinWith "y" (some .u64) 42).sourceHash)
    "let binder must bind sourceHash distinctly"
  expect ((twin (some .u64)).sourceHash !=
      (twinWith "x" (some .u64) 43).sourceHash)
    "let value must bind sourceHash distinctly"

  -- Positive control: `«let» := 1` is assignment to identifier let, not letDecl.
  let assignControl := Tests.Language.LetStatementsFixture.LetAssignmentControl
  match assignControl.initializer with
  | some initializer =>
      expect (initializer.body == #[.assign "let" (.literal 1)])
        "«let» := 1 must remain Source.Statement.assign to identifier 'let'"
  | none => throw <| IO.userError "LetAssignmentControl must retain initializer"
  match ← session.selectProgram assignmentControlSource "<let-assignment-control>" none with
  | .ok decoded =>
      expect (decoded == assignControl)
        "Loader and Lean command must agree on let-assignment positive control"
  | .error error => throw <| IO.userError error.render

  -- Decoder negatives: unknown annotated type and reserved binder.
  expectUnsupported "unknown annotated type" "unsupported portable type"
    (← session.parsePrograms
      (bodyProgramSource "UnknownLetType" "let value : UInt7 := 1")
      "<let-unknown-type>")
  expectUnsupported "reserved binder" "reserved portable identifier 'const'"
    (← session.parsePrograms
      (bodyProgramSource "ReservedLetBinder" "let const : UInt64 := 1")
      "<let-reserved-binder>")

  -- Parser-boundary rejections (no generic fallback).
  for (label, spelling) in [
      ("escaped let", "«let» value := 1"),
      ("qualified let", "Std.let value := 1"),
      ("bare let without binder", "let := 1"),
      ("missing name", "let : UInt64 := 1"),
      ("missing type after colon", "let value : := 1"),
      ("missing value", "let value : UInt64 :="),
      ("missing assign", "let value : UInt64 1"),
      ("split-line let", "let value : UInt64 :=\n      1")
    ] do
    let source := bodyProgramSource "RejectedLetShape" spelling
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<let-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed: Source may retain letDecl, but Typed.check must reject.
  match Compiler.compile (twin (some .u64)) with
  | .error (.invalidProgram "let statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError s!"Typed must reject let with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing let statements"

end Tests.Language.LetStatements
