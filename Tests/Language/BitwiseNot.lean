import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- BitwiseNotSurface pins prefix unary `~` in every declaration body position: init,
-- entry, view, and fn. Covers return-value and let-value reachability plus variable
-- and grouped operands for Source.Expr.bitwiseNot. Zero migration of existing tests.
namespace Tests.Language.BitwiseNotFixture

open ProofForgeV2.Language

program BitwiseNotSurface where
  init() do
    let seed : UInt64 := ~2
    return seed

  entry run(x : UInt64) : UInt64 do
    return ~x

  view peek() : UInt64 do
    let value := ~(2 + 3)
    return value

  fn helper() : UInt64 do
    return ~2 * 3

end Tests.Language.BitwiseNotFixture

namespace Tests.Language.BitwiseNot

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.BitwiseNotFixture.BitwiseNotTwin" "BitwiseNotTwin" #[
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
  "namespace Tests.Language.BitwiseNotFixture\n\n" ++
  "program BitwiseNotSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := ~2\n" ++
  "    return seed\n\n" ++
  "  entry run(x : UInt64) : UInt64 do\n" ++
  "    return ~x\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := ~(2 + 3)\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return ~2 * 3\n\n" ++
  "end Tests.Language.BitwiseNotFixture\n"

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

private def expectReturnExpr (label : String) (sourceProgram : Source.Program)
    (expr : Source.Expr) : IO Unit := do
  match sourceProgram.entries with
  | #[runEntry] =>
      expect (runEntry.body == #[.returnValue expr])
        s!"{label}: entry body must be return of expected expression"
  | _ => throw <| IO.userError s!"{label}: expected a single entry"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.BitwiseNotFixture.BitwiseNotSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64) (.bitwiseNot (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := ~2 as bitwiseNot"
  | none => throw <| IO.userError "BitwiseNotSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.bitwiseNot (.variable "x"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return ~x with variable operand"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.bitwiseNot (.checkedAdd (.literal 2) (.literal 3))),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := ~(2 + 3)"
  | _ => throw <| IO.userError "BitwiseNotSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.checkedMul (.bitwiseNot (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return ~2 * 3 as mul(bitwiseNot 2, 3)"
  | _ => throw <| IO.userError "BitwiseNotSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<bitwise-not>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same bitwiseNot Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same bitwiseNot sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze.
  let not2 ← select session (returnProgramSource "Not2" "~2") "<not-2>"
  expectReturnExpr "~2" not2 (.bitwiseNot (.literal 2))

  let notX ← select session (varReturnProgramSource "NotX" "~x") "<not-x>"
  expectReturnExpr "~x" notX (.bitwiseNot (.variable "x"))

  let notMul ← select session (returnProgramSource "NotMul" "~2 * 3") "<not-mul>"
  expectReturnExpr "~2 * 3" notMul
    (.checkedMul (.bitwiseNot (.literal 2)) (.literal 3))

  let notGroup ← select session
    (returnProgramSource "NotGroup" "~(2 + 3)") "<not-group>"
  expectReturnExpr "~(2 + 3)" notGroup
    (.bitwiseNot (.checkedAdd (.literal 2) (.literal 3)))

  let subNot ← select session (returnProgramSource "SubNot" "1 - ~2") "<sub-not>"
  expectReturnExpr "1 - ~2" subNot
    (.checkedSub (.literal 1) (.bitwiseNot (.literal 2)))

  let mulNot ← select session (returnProgramSource "MulNot" "1 * ~2") "<mul-not>"
  expectReturnExpr "1 * ~2" mulNot
    (.checkedMul (.literal 1) (.bitwiseNot (.literal 2)))

  let nested ← select session (returnProgramSource "NestedNot" "~ ~ 2") "<nested-not>"
  expectReturnExpr "~ ~ 2" nested
    (.bitwiseNot (.bitwiseNot (.literal 2)))

  let grouped ← select session (returnProgramSource "GroupNot" "(~2)") "<group-not>"
  expectReturnExpr "(~2)" grouped (.bitwiseNot (.literal 2))
  -- Same program name for desugar equality of sourceHash under identical identity.
  let not2Same ← select session (returnProgramSource "NotEq" "~2") "<not-eq-bare>"
  let groupSame ← select session (returnProgramSource "NotEq" "(~2)") "<not-eq-group>"
  expect (not2Same == groupSame)
    "~2 and (~2) must share Source.Program under identical identity"
  expect (not2Same.sourceHash == groupSame.sourceHash)
    "~2 and (~2) must share sourceHash under identical identity"

  let negNot ← select session (returnProgramSource "NegNot" "- ~ 2") "<neg-not>"
  expectReturnExpr "- ~ 2" negNot
    (.checkedNeg (.bitwiseNot (.literal 2)))

  let notNeg ← select session (returnProgramSource "NotNeg" "~ - 2") "<not-neg>"
  expectReturnExpr "~ - 2" notNeg
    (.bitwiseNot (.checkedNeg (.literal 2)))

  -- Frozen prospective goldens for BitwiseNotTwin (Expr tag 8 + operand).
  let twinNot2 := twin (.bitwiseNot (.literal 2))
  let twinNotX := twin (.bitwiseNot (.variable "x"))
  let twinNotMul := twin
    (.checkedMul (.bitwiseNot (.literal 2)) (.literal 3))
  let twinWrong := twin
    (.bitwiseNot (.checkedMul (.literal 2) (.literal 3)))
  let twinNotGroup := twin
    (.bitwiseNot (.checkedAdd (.literal 2) (.literal 3)))
  let twinSubNot := twin
    (.checkedSub (.literal 1) (.bitwiseNot (.literal 2)))
  let twinMulNot := twin
    (.checkedMul (.literal 1) (.bitwiseNot (.literal 2)))
  let twinNested := twin
    (.bitwiseNot (.bitwiseNot (.literal 2)))
  let twinLit2 := twin (.literal 2)
  let twinNeg2 := twin (.checkedNeg (.literal 2))
  let twinNot3 := twin (.bitwiseNot (.literal 3))
  let twinNegNot := twin
    (.checkedNeg (.bitwiseNot (.literal 2)))
  let twinNotNeg := twin
    (.bitwiseNot (.checkedNeg (.literal 2)))

  expect (twinNot2.sourceHash ==
      "fc78bd762867552e854a95b0daa19fe2e40ca7aa2655a0c58d2efdb6053c0ca9")
    s!"bitwiseNot ~2 BitwiseNotTwin sourceHash golden must remain stable; got {twinNot2.sourceHash}"
  expect (twinNot2.canonicalBytes.size == 219)
    s!"bitwiseNot ~2 BitwiseNotTwin size golden must remain stable; got {twinNot2.canonicalBytes.size}"
  expect (twinNotX.sourceHash ==
      "7f3667734db603423590dd2bae1c43d3c8e086a437d49a9046fd09ff2d460404")
    s!"bitwiseNot ~x BitwiseNotTwin sourceHash golden must remain stable; got {twinNotX.sourceHash}"
  expect (twinNotX.canonicalBytes.size == 220)
    s!"bitwiseNot ~x BitwiseNotTwin size golden must remain stable; got {twinNotX.canonicalBytes.size}"
  expect (twinNotMul.sourceHash ==
      "284809b7678748bd97319471cf9a8ae3dbf23ff3b7e7b0e83c119e55d1e6a56a")
    s!"~2*3 BitwiseNotTwin sourceHash golden must remain stable; got {twinNotMul.sourceHash}"
  expect (twinNotMul.canonicalBytes.size == 229)
    s!"~2*3 BitwiseNotTwin size golden must remain stable; got {twinNotMul.canonicalBytes.size}"
  expect (twinNotGroup.sourceHash ==
      "9e8b962361148a534b9824e4d85034a03f137fba0a8f4cd9c23a761213b4446e")
    s!"~(2+3) BitwiseNotTwin sourceHash golden must remain stable; got {twinNotGroup.sourceHash}"
  expect (twinNotGroup.canonicalBytes.size == 229)
    s!"~(2+3) BitwiseNotTwin size golden must remain stable; got {twinNotGroup.canonicalBytes.size}"
  expect (twinSubNot.sourceHash ==
      "ed94b141a539c19bc9758f70a689c1cf6f44e870abc722bf83836704df7a267f")
    s!"1 - ~2 BitwiseNotTwin sourceHash golden must remain stable; got {twinSubNot.sourceHash}"
  expect (twinSubNot.canonicalBytes.size == 229)
    s!"1 - ~2 BitwiseNotTwin size golden must remain stable; got {twinSubNot.canonicalBytes.size}"
  expect (twinMulNot.sourceHash ==
      "52d11eb2cefea47d14dbcf6f65b15881929477419a575a1f2d020d1b62bb91dd")
    s!"1 * ~2 BitwiseNotTwin sourceHash golden must remain stable; got {twinMulNot.sourceHash}"
  expect (twinMulNot.canonicalBytes.size == 229)
    s!"1 * ~2 BitwiseNotTwin size golden must remain stable; got {twinMulNot.canonicalBytes.size}"
  expect (twinNested.sourceHash ==
      "89e68d7a47c7021abe58555e2997c4b25043a19c16d1190b3c184aea26add7b0")
    s!"~ ~ 2 BitwiseNotTwin sourceHash golden must remain stable; got {twinNested.sourceHash}"
  expect (twinNested.canonicalBytes.size == 220)
    s!"~ ~ 2 BitwiseNotTwin size golden must remain stable; got {twinNested.canonicalBytes.size}"
  expect (twinLit2.sourceHash ==
      "eaff01f9d5dae148a0669c4ddfdcaad0da02a4ef6c72c8b0028704b799db1aca")
    s!"literal 2 control sourceHash golden must remain stable; got {twinLit2.sourceHash}"
  expect (twinLit2.canonicalBytes.size == 218)
    s!"literal 2 control size golden must remain stable; got {twinLit2.canonicalBytes.size}"
  expect (twinNeg2.sourceHash ==
      "74204965b5d3937e842efca675daf1323879eb3882a4ff8ef9bd6a032af5c3e0")
    s!"checkedNeg 2 control sourceHash golden must remain stable; got {twinNeg2.sourceHash}"
  expect (twinNeg2.canonicalBytes.size == 219)
    s!"checkedNeg 2 control size golden must remain stable; got {twinNeg2.canonicalBytes.size}"
  expect (twinNot3.sourceHash ==
      "99482aba5cd94332f481b1cb470fc2c2ff7c729e381828fd8db12481bd75d1fa")
    s!"bitwiseNot ~3 operand-mutation control sourceHash golden must remain stable; got {twinNot3.sourceHash}"
  expect (twinNot3.canonicalBytes.size == 219)
    s!"bitwiseNot ~3 size golden must remain stable; got {twinNot3.canonicalBytes.size}"
  expect (twinNegNot.sourceHash ==
      "65a2e1bbdb5f426889e1bc8d512679124af44bc848bc947761fc119dd48220d3")
    s!"- ~ 2 BitwiseNotTwin sourceHash golden must remain stable; got {twinNegNot.sourceHash}"
  expect (twinNegNot.canonicalBytes.size == 220)
    s!"- ~ 2 BitwiseNotTwin size golden must remain stable; got {twinNegNot.canonicalBytes.size}"
  expect (twinNotNeg.sourceHash ==
      "550fefa2af4d9ab039932a03aab896b49e7c0fa39a375b3dc573c94d3fc4f392")
    s!"~ - 2 BitwiseNotTwin sourceHash golden must remain stable; got {twinNotNeg.sourceHash}"
  expect (twinNotNeg.canonicalBytes.size == 220)
    s!"~ - 2 BitwiseNotTwin size golden must remain stable; got {twinNotNeg.canonicalBytes.size}"

  -- Non-alias controls.
  expect (twinNot2.sourceHash != twinLit2.sourceHash)
    "bitwiseNot 2 must not alias literal 2"
  expect (twinNot2.sourceHash != twinNeg2.sourceHash)
    "bitwiseNot 2 must not alias checkedNeg 2 (operator tag)"
  expect (twinNot2.canonicalBytes.size == twinNeg2.canonicalBytes.size)
    "bitwiseNot and checkedNeg of same operand must share size (tag-only distinction)"
  expect (twinNot2.sourceHash != twinNot3.sourceHash)
    "bitwiseNot 2 must not alias bitwiseNot 3 (operand mutation)"
  expect (twinNotMul.sourceHash != twinWrong.sourceHash)
    "~2*3 must not alias wrong bitwiseNot(mul(2,3))"
  expect (twinNot2.sourceHash != twinNested.sourceHash)
    "single bitwiseNot must not alias nested bitwiseNot"
  expect (twinNegNot.sourceHash != twinNotNeg.sourceHash)
    "- ~ 2 must not alias ~ - 2 (mixed unary order)"

  -- Parser-boundary malformed shapes.
  for (label, expr) in [
      ("bare tilde", "~"),
      ("empty group operand", "~()"),
      ("star after tilde", "~*2"),
      ("plus after tilde", "~+2"),
      ("extra token after not", "~2 3"),
      ("trailing tilde after binary", "1 - ~")
    ] do
    let source := returnProgramSource "RejectedNotShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<not-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed for bitwiseNot; keep add positive and other exact controls.
  match Compiler.compile (twin (.bitwiseNot (.literal 2))) with
  | .error (.invalidProgram
      "bitwise not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject bitwiseNot with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing bitwiseNot"

  match Compiler.compile (twin (.checkedAdd (.literal 2) (.literal 3))) with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

  match Compiler.compile (twin (.boolLiteral true)) with
  | .error (.invalidProgram
      "boolean literals are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bool control must retain exact Typed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bool control must remain Typed fail-closed"

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

  match Compiler.compile (twin (.checkedNeg (.literal 2))) with
  | .error (.invalidProgram
      "checked negation is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedNeg must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedNeg twin must remain Typed fail-closed"

end Tests.Language.BitwiseNot
