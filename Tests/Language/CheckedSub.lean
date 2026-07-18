import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- CheckedSubSurface pins binary `-` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
namespace Tests.Language.CheckedSubFixture

open ProofForgeV2.Language

program CheckedSubSurface where
  init() do
    let seed : UInt64 := 9 - 4
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a - b

  view peek() : UInt64 do
    let value := 7 - 3
    return value

  fn helper() : UInt64 do
    return 9 - 4 - 1

end Tests.Language.CheckedSubFixture

namespace Tests.Language.CheckedSub

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedSubFixture.CheckedSubTwin" "CheckedSubTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue expr]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.CheckedSubFixture\n\n" ++
  "program CheckedSubSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 9 - 4\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a - b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 7 - 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 9 - 4 - 1\n\n" ++
  "end Tests.Language.CheckedSubFixture\n"

private def returnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

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

/-- Assert entry body is exactly `return <expr>`. -/
private def expectReturnExpr (label : String) (sourceProgram : Source.Program)
    (expr : Source.Expr) : IO Unit := do
  match sourceProgram.entries with
  | #[runEntry] =>
      expect (runEntry.body == #[.returnValue expr])
        s!"{label}: entry body must be return of expected expression"
  | _ => throw <| IO.userError s!"{label}: expected a single entry"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.CheckedSubFixture.CheckedSubSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.checkedSub (.literal 9) (.literal 4)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 9 - 4 and return seed"
  | none => throw <| IO.userError "CheckedSubSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.checkedSub (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a - b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none (.checkedSub (.literal 7) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 7 - 3 and return value"
  | _ => throw <| IO.userError "CheckedSubSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      -- 9 - 4 - 1 = (9 - 4) - 1 left-associative
      match helper.body with
      | #[.returnValue
            (.checkedSub (.checkedSub (.literal 9) (.literal 4)) (.literal 1))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 9 - 4 - 1"
  | _ => throw <| IO.userError "CheckedSubSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<checked-sub>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same checkedSub Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same checkedSub sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact left-associativity AST pins (no parentheses surface).
  let leftChain ← select session
    (returnProgramSource "LeftChain" "9 - 4 - 1") "<sub-left-chain>"
  expectReturnExpr "9 - 4 - 1"
    leftChain
    (.checkedSub (.checkedSub (.literal 9) (.literal 4)) (.literal 1))
  let addThenSub ← select session
    (returnProgramSource "AddThenSub" "1 + 2 - 3") "<sub-add-then-sub>"
  expectReturnExpr "1 + 2 - 3"
    addThenSub
    (.checkedSub (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let subThenAdd ← select session
    (returnProgramSource "SubThenAdd" "1 - 2 + 3") "<sub-sub-then-add>"
  expectReturnExpr "1 - 2 + 3"
    subThenAdd
    (.checkedAdd (.checkedSub (.literal 1) (.literal 2)) (.literal 3))

  -- Frozen prospective goldens for CheckedSubTwin (tag 5 recursive lhs/rhs).
  let sub73 := twin (.checkedSub (.literal 7) (.literal 3))
  let add73 := twin (.checkedAdd (.literal 7) (.literal 3))
  let sub37 := twin (.checkedSub (.literal 3) (.literal 7))
  let leftNest := twin
    (.checkedSub (.checkedSub (.literal 7) (.literal 3)) (.literal 1))
  let rightNest := twin
    (.checkedSub (.literal 7) (.checkedSub (.literal 3) (.literal 1)))

  expect (sub73.sourceHash ==
      "bc13a1ffea38b78f4f86d7125ee5ebce869c38c4ecab322a0a0ac369f42e0369")
    s!"checkedSub 7-3 CheckedSubTwin sourceHash golden must remain stable; got {sub73.sourceHash}"
  expect (sub73.canonicalBytes.size == 228)
    s!"checkedSub 7-3 CheckedSubTwin canonical size golden must remain stable; got {sub73.canonicalBytes.size}"
  expect (add73.sourceHash ==
      "3beb6aeb92a9f8e556a9e4c97c2e383e102cc7b9bf2cc8b1966b17d358bad97f")
    s!"checkedAdd 7+3 CheckedSubTwin sourceHash golden must remain stable; got {add73.sourceHash}"
  expect (add73.canonicalBytes.size == 228)
    s!"checkedAdd 7+3 CheckedSubTwin canonical size golden must remain stable; got {add73.canonicalBytes.size}"
  expect (sub37.sourceHash ==
      "e1f474e6e23d73463d2ab2a4b16fddfd65737594cd4118bb80912453b42f5a15")
    s!"checkedSub 3-7 CheckedSubTwin sourceHash golden must remain stable; got {sub37.sourceHash}"
  expect (sub37.canonicalBytes.size == 228)
    s!"checkedSub 3-7 CheckedSubTwin canonical size golden must remain stable; got {sub37.canonicalBytes.size}"
  expect (leftNest.sourceHash ==
      "3e427798e7a530b6ea165e73e0a907e0f02246c49cacbac49f9ba292b4469966")
    s!"left nest (7-3)-1 CheckedSubTwin sourceHash golden must remain stable; got {leftNest.sourceHash}"
  expect (leftNest.canonicalBytes.size == 238)
    s!"left nest (7-3)-1 CheckedSubTwin canonical size golden must remain stable; got {leftNest.canonicalBytes.size}"
  expect (rightNest.sourceHash ==
      "7e6a2c24a6cad28e5984f2279dce0df9fdd863c6ea1062334cb32b69027e7e3a")
    s!"right nest 7-(3-1) CheckedSubTwin sourceHash golden must remain stable; got {rightNest.sourceHash}"
  expect (rightNest.canonicalBytes.size == 238)
    s!"right nest 7-(3-1) CheckedSubTwin canonical size golden must remain stable; got {rightNest.canonicalBytes.size}"

  -- Non-alias: operator tag, operand order, nesting shape.
  expect (sub73.sourceHash != add73.sourceHash)
    "checkedSub 7-3 must not alias checkedAdd 7+3 (operator tag)"
  expect (sub73.canonicalBytes.size == add73.canonicalBytes.size)
    "checkedSub and checkedAdd of same operands must share size (tag-only distinction)"
  expect (sub73.sourceHash != sub37.sourceHash)
    "checkedSub 7-3 must not alias 3-7 (operand order)"
  expect (leftNest.sourceHash != rightNest.sourceHash)
    "left-nested and right-nested checkedSub must not alias"
  expect (leftNest.canonicalBytes.size == rightNest.canonicalBytes.size)
    "left/right nested checkedSub twins must share canonical size"

  -- Parser-boundary: missing binary operand only.
  -- Unary shapes `- 3`/`-3`/`7 - - 3`/`1 + - 2` migrated to CheckedNeg positives (D1-PA-25).
  -- No parentheses tests in this slice.
  for (label, expr) in [
      ("missing rhs", "7 -")
    ] do
    let source := returnProgramSource "RejectedSubShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<sub-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed for checkedSub; existing checkedAdd twin must still compile.
  match Compiler.compile (twin (.checkedSub (.literal 7) (.literal 3))) with
  | .error (.invalidProgram
      "checked subtraction is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject checkedSub with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing checkedSub"

  match Compiler.compile (twin (.checkedAdd (.literal 7) (.literal 3))) with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

end Tests.Language.CheckedSub
