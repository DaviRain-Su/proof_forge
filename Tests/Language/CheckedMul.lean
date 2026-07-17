import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- CheckedMulSurface pins binary `*` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
namespace Tests.Language.CheckedMulFixture

open ProofForgeV2.Language

program CheckedMulSurface where
  init() do
    let seed : UInt64 := 2 * 3
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a * b

  view peek() : UInt64 do
    let value := 2 * 3 * 4
    return value

  fn helper() : UInt64 do
    return 2 + 3 * 4

end Tests.Language.CheckedMulFixture

namespace Tests.Language.CheckedMul

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedMulFixture.CheckedMulTwin" "CheckedMulTwin" #[
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
  "namespace Tests.Language.CheckedMulFixture\n\n" ++
  "program CheckedMulSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 2 * 3\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a * b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 2 * 3 * 4\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 2 + 3 * 4\n\n" ++
  "end Tests.Language.CheckedMulFixture\n"

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
  let elaborated := Tests.Language.CheckedMulFixture.CheckedMulSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.checkedMul (.literal 2) (.literal 3)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 2 * 3 and return seed"
  | none => throw <| IO.userError "CheckedMulSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.checkedMul (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a * b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.checkedMul (.checkedMul (.literal 2) (.literal 3)) (.literal 4)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain left-associative let value := 2 * 3 * 4"
  | _ => throw <| IO.userError "CheckedMulSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      -- 2 + 3 * 4 = 2 + (3 * 4)
      match helper.body with
      | #[.returnValue
            (.checkedAdd (.literal 2)
              (.checkedMul (.literal 3) (.literal 4)))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain precedence-correct return 2 + 3 * 4"
  | _ => throw <| IO.userError "CheckedMulSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<checked-mul>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same checkedMul Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same checkedMul sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact precedence / left-associativity AST pins (no parentheses surface).
  let mulChain ← select session
    (returnProgramSource "MulChain" "2 * 3 * 4") "<mul-left-chain>"
  expectReturnExpr "2 * 3 * 4"
    mulChain
    (.checkedMul (.checkedMul (.literal 2) (.literal 3)) (.literal 4))
  let addMul ← select session
    (returnProgramSource "AddMul" "2 + 3 * 4") "<mul-add-mul>"
  expectReturnExpr "2 + 3 * 4"
    addMul
    (.checkedAdd (.literal 2) (.checkedMul (.literal 3) (.literal 4)))
  let mulAdd ← select session
    (returnProgramSource "MulAdd" "2 * 3 + 4") "<mul-mul-add>"
  expectReturnExpr "2 * 3 + 4"
    mulAdd
    (.checkedAdd (.checkedMul (.literal 2) (.literal 3)) (.literal 4))
  let subMul ← select session
    (returnProgramSource "SubMul" "2 - 3 * 4") "<mul-sub-mul>"
  expectReturnExpr "2 - 3 * 4"
    subMul
    (.checkedSub (.literal 2) (.checkedMul (.literal 3) (.literal 4)))
  let mulSub ← select session
    (returnProgramSource "MulSub" "2 * 3 - 4") "<mul-mul-sub>"
  expectReturnExpr "2 * 3 - 4"
    mulSub
    (.checkedSub (.checkedMul (.literal 2) (.literal 3)) (.literal 4))

  -- Frozen prospective goldens for CheckedMulTwin (tag 6 recursive lhs/rhs).
  let mul23 := twin (.checkedMul (.literal 2) (.literal 3))
  let addMulPrec := twin
    (.checkedAdd (.literal 2) (.checkedMul (.literal 3) (.literal 4)))
  let mulAddPrec := twin
    (.checkedAdd (.checkedMul (.literal 2) (.literal 3)) (.literal 4))
  let leftNest := twin
    (.checkedMul (.checkedMul (.literal 2) (.literal 3)) (.literal 4))
  let rightNest := twin
    (.checkedMul (.literal 2) (.checkedMul (.literal 3) (.literal 4)))
  let add23 := twin (.checkedAdd (.literal 2) (.literal 3))
  let sub23 := twin (.checkedSub (.literal 2) (.literal 3))
  let mul32 := twin (.checkedMul (.literal 3) (.literal 2))

  expect (mul23.sourceHash ==
      "8128548ccbf651b56e4e7fff2cf57a098f69486eb06464f506e1caed2e7f581a")
    s!"checkedMul 2*3 CheckedMulTwin sourceHash golden must remain stable; got {mul23.sourceHash}"
  expect (mul23.canonicalBytes.size == 228)
    s!"checkedMul 2*3 CheckedMulTwin canonical size golden must remain stable; got {mul23.canonicalBytes.size}"
  expect (addMulPrec.sourceHash ==
      "a6eb82bd2a1f6402c8157065926ee0fc80f613126fdc822801b3b2b514635a08")
    s!"2+3*4 CheckedMulTwin sourceHash golden must remain stable; got {addMulPrec.sourceHash}"
  expect (addMulPrec.canonicalBytes.size == 238)
    s!"2+3*4 CheckedMulTwin canonical size golden must remain stable; got {addMulPrec.canonicalBytes.size}"
  expect (mulAddPrec.sourceHash ==
      "2596095b9f9ca52d373c0f1997746032240e26608ed37191b7e35a2e4f37b576")
    s!"2*3+4 CheckedMulTwin sourceHash golden must remain stable; got {mulAddPrec.sourceHash}"
  expect (mulAddPrec.canonicalBytes.size == 238)
    s!"2*3+4 CheckedMulTwin canonical size golden must remain stable; got {mulAddPrec.canonicalBytes.size}"
  expect (leftNest.sourceHash ==
      "625cdaa2d54c15d8da241c4d069f225374429a03076d30bf0be23638a00e0f88")
    s!"left nest 2*3*4 CheckedMulTwin sourceHash golden must remain stable; got {leftNest.sourceHash}"
  expect (leftNest.canonicalBytes.size == 238)
    s!"left nest 2*3*4 CheckedMulTwin canonical size golden must remain stable; got {leftNest.canonicalBytes.size}"
  expect (rightNest.sourceHash ==
      "f4b9a861619b742361e41f69342f07dc9c338daa9b9a520073b8aa2fa990c13c")
    s!"right nest 2*(3*4) CheckedMulTwin sourceHash golden must remain stable; got {rightNest.sourceHash}"
  expect (rightNest.canonicalBytes.size == 238)
    s!"right nest 2*(3*4) CheckedMulTwin canonical size golden must remain stable; got {rightNest.canonicalBytes.size}"

  -- Non-alias: operator tag, operand order, nesting, mixed-prec shapes.
  expect (mul23.sourceHash != add23.sourceHash)
    "checkedMul 2*3 must not alias checkedAdd 2+3 (operator tag)"
  expect (mul23.sourceHash != sub23.sourceHash)
    "checkedMul 2*3 must not alias checkedSub 2-3 (operator tag)"
  expect (mul23.canonicalBytes.size == add23.canonicalBytes.size)
    "checkedMul and checkedAdd of same operands must share size (tag-only distinction)"
  expect (mul23.canonicalBytes.size == sub23.canonicalBytes.size)
    "checkedMul and checkedSub of same operands must share size (tag-only distinction)"
  expect (mul23.sourceHash != mul32.sourceHash)
    "checkedMul 2*3 must not alias 3*2 (operand order)"
  expect (leftNest.sourceHash != rightNest.sourceHash)
    "left-nested and right-nested checkedMul must not alias"
  expect (leftNest.canonicalBytes.size == rightNest.canonicalBytes.size)
    "left/right nested checkedMul twins must share canonical size"
  expect (addMulPrec.sourceHash != mulAddPrec.sourceHash)
    "2+3*4 must not alias 2*3+4 (precedence shape)"
  expect (addMulPrec.sourceHash != leftNest.sourceHash)
    "2+3*4 must not alias left 2*3*4"

  -- Parser-boundary: missing operands, bare/repeated star, extra token, / and %.
  -- No parentheses tests in this slice.
  for (label, expr) in [
      ("missing lhs", "* 3"),
      ("missing rhs", "2 *"),
      ("bare star", "*"),
      ("repeated star spaced", "2 * * 3"),
      ("repeated star glued", "2 ** 3"),
      ("extra token", "2 * 3 4"),
      ("slash division", "2 / 3"),
      ("percent modulo", "2 % 3")
    ] do
    let source := returnProgramSource "RejectedMulShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<mul-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed for checkedMul; checkedAdd compiles; checkedSub keeps exact diagnostic.
  match Compiler.compile (twin (.checkedMul (.literal 2) (.literal 3))) with
  | .error (.invalidProgram
      "checked multiplication is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject checkedMul with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing checkedMul"

  match Compiler.compile (twin (.checkedAdd (.literal 2) (.literal 3))) with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

  match Compiler.compile (twin (.checkedSub (.literal 2) (.literal 3))) with
  | .error (.invalidProgram
      "checked subtraction is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedSub must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedSub twin must remain Typed fail-closed"

end Tests.Language.CheckedMul
