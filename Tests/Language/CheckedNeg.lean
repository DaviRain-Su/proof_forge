import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- CheckedNegSurface pins prefix unary `-` in every declaration body position: init,
-- entry, view, and fn. Covers return-value and let-value reachability plus variable
-- and grouped operands for Source.Expr.checkedNeg.
namespace Tests.Language.CheckedNegFixture

open ProofForgeV2.Language

program CheckedNegSurface where
  init() do
    let seed : UInt64 := -2
    return seed

  entry run(x : UInt64) : UInt64 do
    return -x

  view peek() : UInt64 do
    let value := - 2
    return value

  fn helper() : UInt64 do
    return -(2 + 3)

end Tests.Language.CheckedNegFixture

namespace Tests.Language.CheckedNeg

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedNegFixture.CheckedNegTwin" "CheckedNegTwin" #[
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
  "namespace Tests.Language.CheckedNegFixture\n\n" ++
  "program CheckedNegSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := -2\n" ++
  "    return seed\n\n" ++
  "  entry run(x : UInt64) : UInt64 do\n" ++
  "    return -x\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := - 2\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return -(2 + 3)\n\n" ++
  "end Tests.Language.CheckedNegFixture\n"

private def returnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private def varReturnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run(x : UInt64) : UInt64 do\n" ++
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
  let elaborated := Tests.Language.CheckedNegFixture.CheckedNegSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64) (.checkedNeg (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := -2 as checkedNeg"
  | none => throw <| IO.userError "CheckedNegSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.checkedNeg (.variable "x"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return -x with variable operand"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none (.checkedNeg (.literal 2)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := - 2 as checkedNeg of literal"
  | _ => throw <| IO.userError "CheckedNegSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.checkedNeg (.checkedAdd (.literal 2) (.literal 3)))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return -(2 + 3) as checkedNeg of checkedAdd"
  | _ => throw <| IO.userError "CheckedNegSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<checked-neg>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same checkedNeg Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same checkedNeg sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins migrated from temporary parser-negatives and freeze positives.
  let neg2 ← select session (returnProgramSource "Neg2" "-2") "<neg-2>"
  expectReturnExpr "-2" neg2 (.checkedNeg (.literal 2))
  let neg2Spaced ← select session (returnProgramSource "Neg2" "- 2") "<neg-2-spaced>"
  expectReturnExpr "- 2" neg2Spaced (.checkedNeg (.literal 2))
  expect (neg2 == neg2Spaced)
    "-2 and - 2 must desugar to the same Source program"
  expect (neg2.sourceHash == neg2Spaced.sourceHash)
    "-2 and - 2 must share sourceHash (not signed literals)"

  let negX ← select session (varReturnProgramSource "NegX" "-x") "<neg-x>"
  expectReturnExpr "-x" negX (.checkedNeg (.variable "x"))

  let negMul ← select session (returnProgramSource "NegMul" "-2 * 3") "<neg-mul>"
  expectReturnExpr "-2 * 3" negMul
    (.checkedMul (.checkedNeg (.literal 2)) (.literal 3))

  let negGroup ← select session
    (returnProgramSource "NegGroup" "-(2 + 3)") "<neg-group>"
  expectReturnExpr "-(2 + 3)" negGroup
    (.checkedNeg (.checkedAdd (.literal 2) (.literal 3)))

  let subNeg ← select session (returnProgramSource "SubNeg" "1 - -2") "<sub-neg>"
  expectReturnExpr "1 - -2" subNeg
    (.checkedSub (.literal 1) (.checkedNeg (.literal 2)))

  let addNeg ← select session (returnProgramSource "AddNeg" "1 + -2") "<add-neg>"
  expectReturnExpr "1 + -2" addNeg
    (.checkedAdd (.literal 1) (.checkedNeg (.literal 2)))

  let mulNeg ← select session (returnProgramSource "MulNeg" "1 * -2") "<mul-neg>"
  expectReturnExpr "1 * -2" mulNeg
    (.checkedMul (.literal 1) (.checkedNeg (.literal 2)))

  let nested ← select session (returnProgramSource "NestedNeg" "- - 2") "<nested-neg>"
  expectReturnExpr "- - 2" nested
    (.checkedNeg (.checkedNeg (.literal 2)))

  -- Migrated Grouping positive: grouped unary desugars to the same AST as bare unary.
  let groupNeg3 ← select session
    (returnProgramSource "GroupNeg3" "(-3)") "<group-neg-3>"
  expectReturnExpr "(-3)" groupNeg3 (.checkedNeg (.literal 3))

  -- Exact spellings migrated from the PA22 temporary parser-negative matrix.
  let migratedNeg3Spaced ← select session
    (returnProgramSource "MigratedNeg3Spaced" "- 3") "<migrated-neg-3-spaced>"
  expectReturnExpr "- 3" migratedNeg3Spaced (.checkedNeg (.literal 3))
  let migratedNeg3 ← select session
    (returnProgramSource "MigratedNeg3" "-3") "<migrated-neg-3>"
  expectReturnExpr "-3" migratedNeg3 (.checkedNeg (.literal 3))
  let migratedSubNeg3 ← select session
    (returnProgramSource "MigratedSubNeg3" "7 - - 3") "<migrated-sub-neg-3>"
  expectReturnExpr "7 - - 3" migratedSubNeg3
    (.checkedSub (.literal 7) (.checkedNeg (.literal 3)))
  let migratedAddNeg2 ← select session
    (returnProgramSource "MigratedAddNeg2" "1 + - 2") "<migrated-add-neg-2>"
  expectReturnExpr "1 + - 2" migratedAddNeg2
    (.checkedAdd (.literal 1) (.checkedNeg (.literal 2)))

  -- Frozen prospective goldens for CheckedNegTwin (tag 7 + operand).
  let twinNeg2 := twin (.checkedNeg (.literal 2))
  let twinNegX := twin (.checkedNeg (.variable "x"))
  let twinNegMul := twin
    (.checkedMul (.checkedNeg (.literal 2)) (.literal 3))
  let twinWrongNegMul := twin
    (.checkedNeg (.checkedMul (.literal 2) (.literal 3)))
  let twinNegGroup := twin
    (.checkedNeg (.checkedAdd (.literal 2) (.literal 3)))
  let twinSubNeg := twin
    (.checkedSub (.literal 1) (.checkedNeg (.literal 2)))
  let twinAddNeg := twin
    (.checkedAdd (.literal 1) (.checkedNeg (.literal 2)))
  let twinMulNeg := twin
    (.checkedMul (.literal 1) (.checkedNeg (.literal 2)))
  let twinNested := twin
    (.checkedNeg (.checkedNeg (.literal 2)))
  let twinLit2 := twin (.literal 2)
  let twinNeg3 := twin (.checkedNeg (.literal 3))

  expect (twinNeg2.sourceHash ==
      "2d85f63df2d77d902f186712031114c9d66f9d169acc2672c1bccbb32dfc04ce")
    s!"checkedNeg -2 CheckedNegTwin sourceHash golden must remain stable; got {twinNeg2.sourceHash}"
  expect (twinNeg2.canonicalBytes.size == 219)
    s!"checkedNeg -2 CheckedNegTwin size golden must remain stable; got {twinNeg2.canonicalBytes.size}"
  expect (twinNegX.sourceHash ==
      "a24b2b26d9568962214245701db537cdab9ee18a427a5ae2d6ce3e6858023c29")
    s!"checkedNeg -x CheckedNegTwin sourceHash golden must remain stable; got {twinNegX.sourceHash}"
  expect (twinNegX.canonicalBytes.size == 220)
    s!"checkedNeg -x CheckedNegTwin size golden must remain stable; got {twinNegX.canonicalBytes.size}"
  expect (twinNegMul.sourceHash ==
      "ee810bab7d822bf4ea8dbdc5007096e40a7b34e1ab5cbacfccabb83153329978")
    s!"-2*3 CheckedNegTwin sourceHash golden must remain stable; got {twinNegMul.sourceHash}"
  expect (twinNegMul.canonicalBytes.size == 229)
    s!"-2*3 CheckedNegTwin size golden must remain stable; got {twinNegMul.canonicalBytes.size}"
  expect (twinNegGroup.sourceHash ==
      "bac0df381286a35efa955b2886bdc41932170b0c4759c72bf791ae922d863281")
    s!"-(2+3) CheckedNegTwin sourceHash golden must remain stable; got {twinNegGroup.sourceHash}"
  expect (twinNegGroup.canonicalBytes.size == 229)
    s!"-(2+3) CheckedNegTwin size golden must remain stable; got {twinNegGroup.canonicalBytes.size}"
  expect (twinSubNeg.sourceHash ==
      "697a13845b72899e4987ec417aed002516cb24a94dc2bf5b334c7150835f210f")
    s!"1 - -2 CheckedNegTwin sourceHash golden must remain stable; got {twinSubNeg.sourceHash}"
  expect (twinSubNeg.canonicalBytes.size == 229)
    s!"1 - -2 CheckedNegTwin size golden must remain stable; got {twinSubNeg.canonicalBytes.size}"
  expect (twinAddNeg.sourceHash ==
      "7022de10536032eb13e6298c968a05314e576326440c59aa31af4e282b05b81c")
    s!"1 + -2 CheckedNegTwin sourceHash golden must remain stable; got {twinAddNeg.sourceHash}"
  expect (twinAddNeg.canonicalBytes.size == 229)
    s!"1 + -2 CheckedNegTwin size golden must remain stable; got {twinAddNeg.canonicalBytes.size}"
  expect (twinMulNeg.sourceHash ==
      "5b8d1745cabe7832938278f507c83000d8e1fd80ca5bdd06bc2e426224074ca0")
    s!"1 * -2 CheckedNegTwin sourceHash golden must remain stable; got {twinMulNeg.sourceHash}"
  expect (twinMulNeg.canonicalBytes.size == 229)
    s!"1 * -2 CheckedNegTwin size golden must remain stable; got {twinMulNeg.canonicalBytes.size}"
  expect (twinNested.sourceHash ==
      "cddb76db9a7d522c1531d1058446c1ba75b6f0006eccfe6b2f274b515642127f")
    s!"- - 2 CheckedNegTwin sourceHash golden must remain stable; got {twinNested.sourceHash}"
  expect (twinNested.canonicalBytes.size == 220)
    s!"- - 2 CheckedNegTwin size golden must remain stable; got {twinNested.canonicalBytes.size}"
  expect (twinLit2.sourceHash ==
      "325f015ff4f50b4965af8a52add45a55853fa1f2a9767212f0f4a14f80bbacc5")
    s!"literal 2 control sourceHash golden must remain stable; got {twinLit2.sourceHash}"
  expect (twinLit2.canonicalBytes.size == 218)
    s!"literal 2 control size golden must remain stable; got {twinLit2.canonicalBytes.size}"
  expect (twinNeg3.sourceHash ==
      "6e23ac450bce520aae993273d98d7af32497d6267315e73b09bf12b416a19af8")
    s!"checkedNeg -3 order control sourceHash golden must remain stable; got {twinNeg3.sourceHash}"
  expect (twinNeg3.canonicalBytes.size == 219)
    s!"checkedNeg -3 order control size golden must remain stable; got {twinNeg3.canonicalBytes.size}"

  -- Non-alias: operand, nesting shape, and wrong grouping tree.
  expect (twinNeg2.sourceHash != twinLit2.sourceHash)
    "checkedNeg 2 must not alias literal 2"
  expect (twinNeg2.sourceHash != twinNeg3.sourceHash)
    "checkedNeg 2 must not alias checkedNeg 3 (operand order)"
  expect (twinNegMul.sourceHash != twinWrongNegMul.sourceHash)
    "-2*3 must not alias wrong neg(mul(2,3))"
  expect (twinNeg2.sourceHash != twinNested.sourceHash)
    "single checkedNeg must not alias nested checkedNeg"
  expect (twinSubNeg.sourceHash != twinAddNeg.sourceHash)
    "1 - -2 must not alias 1 + -2"
  expect (twinAddNeg.sourceHash != twinMulNeg.sourceHash)
    "1 + -2 must not alias 1 * -2"

  -- Lean line-comment boundary: glued `--` is not nested unary.
  -- `1--2` is literal 1 followed by a comment, not subtraction-of-negative.
  let commentBoundary ← select session
    (returnProgramSource "CommentBoundary" "1--2") "<comment-1--2>"
  expectReturnExpr "1--2 comment control" commentBoundary (.literal 1)

  -- Parser-boundary malformed shapes (not temporary unary rejections).
  for (label, expr) in [
      ("bare minus", "-"),
      ("empty group operand", "-()"),
      ("star after minus", "-*2"),
      ("plus after minus", "-+2"),
      ("extra token after neg", "-2 3"),
      ("trailing double minus", "1 - -")
    ] do
    let source := returnProgramSource "RejectedNegShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<neg-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed for checkedNeg; existing checkedAdd twin must still compile.
  match Compiler.compile (twin (.checkedNeg (.literal 2))) with
  | .error (.invalidProgram
      "checked negation is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject checkedNeg with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing checkedNeg"

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

  match Compiler.compile (twin (.checkedMul (.literal 2) (.literal 3))) with
  | .error (.invalidProgram
      "checked multiplication is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedMul must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedMul twin must remain Typed fail-closed"

end Tests.Language.CheckedNeg
