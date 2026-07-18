import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- LogicalNotSurface pins prefix unary `!` in every declaration body position: init,
-- entry, view, and fn. Covers return-value and let-value reachability plus variable
-- and grouped operands for Source.Expr.logicalNot. Zero migration of existing tests.
namespace Tests.Language.LogicalNotFixture

open ProofForgeV2.Language

program LogicalNotSurface where
  init() do
    let seed : UInt64 := !2
    return seed

  entry run(x : UInt64) : UInt64 do
    return !x

  view peek() : UInt64 do
    let value := !(2 + 3)
    return value

  fn helper() : UInt64 do
    return !true

end Tests.Language.LogicalNotFixture

namespace Tests.Language.LogicalNot

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LogicalNotFixture.LogicalNotTwin" "LogicalNotTwin" #[
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
  "namespace Tests.Language.LogicalNotFixture\n\n" ++
  "program LogicalNotSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := !2\n" ++
  "    return seed\n\n" ++
  "  entry run(x : UInt64) : UInt64 do\n" ++
  "    return !x\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := !(2 + 3)\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return !true\n\n" ++
  "end Tests.Language.LogicalNotFixture\n"

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
  let elaborated := Tests.Language.LogicalNotFixture.LogicalNotSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64) (.logicalNot (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := !2 as logicalNot"
  | none => throw <| IO.userError "LogicalNotSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.logicalNot (.variable "x"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return !x with variable operand"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.logicalNot (.checkedAdd (.literal 2) (.literal 3))),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := !(2 + 3)"
  | _ => throw <| IO.userError "LogicalNotSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue (.logicalNot (.boolLiteral true))] => pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return !true as logicalNot of boolLiteral true"
  | _ => throw <| IO.userError "LogicalNotSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<logical-not>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same logicalNot Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same logicalNot sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze.
  let not2 ← select session (returnProgramSource "Not2" "!2") "<not-2>"
  expectReturnExpr "!2" not2 (.logicalNot (.literal 2))

  let notTrue ← select session (returnProgramSource "NotTrue" "!true") "<not-true>"
  expectReturnExpr "!true" notTrue (.logicalNot (.boolLiteral true))

  let notFalse ← select session (returnProgramSource "NotFalse" "!false") "<not-false>"
  expectReturnExpr "!false" notFalse (.logicalNot (.boolLiteral false))

  let notX ← select session (varReturnProgramSource "NotX" "!x") "<not-x>"
  expectReturnExpr "!x" notX (.logicalNot (.variable "x"))

  let notMul ← select session (returnProgramSource "NotMul" "!2 * 3") "<not-mul>"
  expectReturnExpr "!2 * 3" notMul
    (.checkedMul (.logicalNot (.literal 2)) (.literal 3))

  let notGroup ← select session
    (returnProgramSource "NotGroup" "!(2 + 3)") "<not-group>"
  expectReturnExpr "!(2 + 3)" notGroup
    (.logicalNot (.checkedAdd (.literal 2) (.literal 3)))

  let subNot ← select session (returnProgramSource "SubNot" "1 - !2") "<sub-not>"
  expectReturnExpr "1 - !2" subNot
    (.checkedSub (.literal 1) (.logicalNot (.literal 2)))

  let mulNot ← select session (returnProgramSource "MulNot" "1 * !2") "<mul-not>"
  expectReturnExpr "1 * !2" mulNot
    (.checkedMul (.literal 1) (.logicalNot (.literal 2)))

  let nested ← select session (returnProgramSource "NestedNot" "! ! 2") "<nested-not>"
  expectReturnExpr "! ! 2" nested
    (.logicalNot (.logicalNot (.literal 2)))

  let grouped ← select session (returnProgramSource "GroupNot" "(!2)") "<group-not>"
  expectReturnExpr "(!2)" grouped (.logicalNot (.literal 2))
  let not2Same ← select session (returnProgramSource "NotEq" "!2") "<not-eq-bare>"
  let groupSame ← select session (returnProgramSource "NotEq" "(!2)") "<not-eq-group>"
  expect (not2Same == groupSame)
    "!2 and (!2) must share Source.Program under identical identity"
  expect (not2Same.sourceHash == groupSame.sourceHash)
    "!2 and (!2) must share sourceHash under identical identity"

  let negNot ← select session (returnProgramSource "NegNot" "- ! 2") "<neg-not>"
  expectReturnExpr "- ! 2" negNot
    (.checkedNeg (.logicalNot (.literal 2)))

  let notNeg ← select session (returnProgramSource "NotNeg" "! - 2") "<not-neg>"
  expectReturnExpr "! - 2" notNeg
    (.logicalNot (.checkedNeg (.literal 2)))

  let bitNot ← select session (returnProgramSource "BitNot" "~ ! 2") "<bit-not>"
  expectReturnExpr "~ ! 2" bitNot
    (.bitwiseNot (.logicalNot (.literal 2)))

  let notBit ← select session (returnProgramSource "NotBit" "! ~ 2") "<not-bit>"
  expectReturnExpr "! ~ 2" notBit
    (.logicalNot (.bitwiseNot (.literal 2)))

  -- Frozen prospective goldens for LogicalNotTwin (Expr tag 9 + operand).
  let twinNot2 := twin (.logicalNot (.literal 2))
  let twinNotTrue := twin (.logicalNot (.boolLiteral true))
  let twinNotFalse := twin (.logicalNot (.boolLiteral false))
  let twinNotX := twin (.logicalNot (.variable "x"))
  let twinNotMul := twin
    (.checkedMul (.logicalNot (.literal 2)) (.literal 3))
  let twinWrong := twin
    (.logicalNot (.checkedMul (.literal 2) (.literal 3)))
  let twinNotGroup := twin
    (.logicalNot (.checkedAdd (.literal 2) (.literal 3)))
  let twinSubNot := twin
    (.checkedSub (.literal 1) (.logicalNot (.literal 2)))
  let twinMulNot := twin
    (.checkedMul (.literal 1) (.logicalNot (.literal 2)))
  let twinNested := twin
    (.logicalNot (.logicalNot (.literal 2)))
  let twinLit2 := twin (.literal 2)
  let twinNeg2 := twin (.checkedNeg (.literal 2))
  let twinBit2 := twin (.bitwiseNot (.literal 2))
  let twinNegNot := twin
    (.checkedNeg (.logicalNot (.literal 2)))
  let twinNotNeg := twin
    (.logicalNot (.checkedNeg (.literal 2)))
  let twinBitNot := twin
    (.bitwiseNot (.logicalNot (.literal 2)))
  let twinNotBit := twin
    (.logicalNot (.bitwiseNot (.literal 2)))

  expect (twinNot2.sourceHash ==
      "5ac59fb7f95bb3aeac27441da9f5fc69990fc46ce903f6365ff9c6e3811d343d")
    s!"logicalNot !2 LogicalNotTwin sourceHash golden must remain stable; got {twinNot2.sourceHash}"
  expect (twinNot2.canonicalBytes.size == 219)
    s!"logicalNot !2 LogicalNotTwin size golden must remain stable; got {twinNot2.canonicalBytes.size}"
  expect (twinNotTrue.sourceHash ==
      "3ae83fbda053d685a95c6cd44c1d90f45cd9c197c90e85576c5d2ef34915450b")
    s!"logicalNot !true LogicalNotTwin sourceHash golden must remain stable; got {twinNotTrue.sourceHash}"
  expect (twinNotTrue.canonicalBytes.size == 212)
    s!"logicalNot !true LogicalNotTwin size golden must remain stable; got {twinNotTrue.canonicalBytes.size}"
  expect (twinNotFalse.sourceHash ==
      "1db5efc2710aceb37dd6dd0ccf48c8c879f0a821a9f885717d1229ca4ba989e1")
    s!"logicalNot !false LogicalNotTwin sourceHash golden must remain stable; got {twinNotFalse.sourceHash}"
  expect (twinNotFalse.canonicalBytes.size == 212)
    s!"logicalNot !false LogicalNotTwin size golden must remain stable; got {twinNotFalse.canonicalBytes.size}"
  expect (twinNotX.sourceHash ==
      "174d346ee92f3163df0e8af17d6f1929d400d40cd97ab56165f1fc16ec0a02ab")
    s!"logicalNot !x LogicalNotTwin sourceHash golden must remain stable; got {twinNotX.sourceHash}"
  expect (twinNotX.canonicalBytes.size == 220)
    s!"logicalNot !x LogicalNotTwin size golden must remain stable; got {twinNotX.canonicalBytes.size}"
  expect (twinNotMul.sourceHash ==
      "55941863fe708deb8307c2f3813f4064ecb917b583638d2ce50785ef8c775236")
    s!"!2*3 LogicalNotTwin sourceHash golden must remain stable; got {twinNotMul.sourceHash}"
  expect (twinNotMul.canonicalBytes.size == 229)
    s!"!2*3 LogicalNotTwin size golden must remain stable; got {twinNotMul.canonicalBytes.size}"
  expect (twinNotGroup.sourceHash ==
      "c7e2dc0cb6c33b654dcc4fc554cc73b8a362bc5613c2edd2fc3a3bcc82a504db")
    s!"!(2+3) LogicalNotTwin sourceHash golden must remain stable; got {twinNotGroup.sourceHash}"
  expect (twinNotGroup.canonicalBytes.size == 229)
    s!"!(2+3) LogicalNotTwin size golden must remain stable; got {twinNotGroup.canonicalBytes.size}"
  expect (twinSubNot.sourceHash ==
      "7e042a9d99dbcc07da8546a042f4f01b32e514b40395b0600db768668623650e")
    s!"1 - !2 LogicalNotTwin sourceHash golden must remain stable; got {twinSubNot.sourceHash}"
  expect (twinSubNot.canonicalBytes.size == 229)
    s!"1 - !2 LogicalNotTwin size golden must remain stable; got {twinSubNot.canonicalBytes.size}"
  expect (twinMulNot.sourceHash ==
      "9737d8eec16e35bd18d20903dfd56618347b3177c5cfddec3f700fa00fee1c8e")
    s!"1 * !2 LogicalNotTwin sourceHash golden must remain stable; got {twinMulNot.sourceHash}"
  expect (twinMulNot.canonicalBytes.size == 229)
    s!"1 * !2 LogicalNotTwin size golden must remain stable; got {twinMulNot.canonicalBytes.size}"
  expect (twinNested.sourceHash ==
      "614adf4f9adfc7a4c95ec0b164aeab30c118f7ea64f99b17b1041364930dba8f")
    s!"! ! 2 LogicalNotTwin sourceHash golden must remain stable; got {twinNested.sourceHash}"
  expect (twinNested.canonicalBytes.size == 220)
    s!"! ! 2 LogicalNotTwin size golden must remain stable; got {twinNested.canonicalBytes.size}"
  expect (twinLit2.sourceHash ==
      "798aeafc0c0e12aeb9e1d657145d1fd59b0e86cf7870e1eaffed30e0bef57e2b")
    s!"literal 2 control sourceHash golden must remain stable; got {twinLit2.sourceHash}"
  expect (twinLit2.canonicalBytes.size == 218)
    s!"literal 2 control size golden must remain stable; got {twinLit2.canonicalBytes.size}"
  expect (twinNeg2.sourceHash ==
      "c1c627dcaeec53f9b4a5b25545271cba413286107e003d612c7716c829c79f6a")
    s!"checkedNeg 2 control sourceHash golden must remain stable; got {twinNeg2.sourceHash}"
  expect (twinNeg2.canonicalBytes.size == 219)
    s!"checkedNeg 2 control size golden must remain stable; got {twinNeg2.canonicalBytes.size}"
  expect (twinBit2.sourceHash ==
      "60a947b303f0b333865b7f43b3c27b474a0d4e45d8f2083dc6924c9342d77806")
    s!"bitwiseNot 2 control sourceHash golden must remain stable; got {twinBit2.sourceHash}"
  expect (twinBit2.canonicalBytes.size == 219)
    s!"bitwiseNot 2 control size golden must remain stable; got {twinBit2.canonicalBytes.size}"
  expect (twinNegNot.sourceHash ==
      "86b57445571d5e2486afc39133d2196f9131155e76e6fccefec558422d2af29f")
    s!"- ! 2 LogicalNotTwin sourceHash golden must remain stable; got {twinNegNot.sourceHash}"
  expect (twinNegNot.canonicalBytes.size == 220)
    s!"- ! 2 LogicalNotTwin size golden must remain stable; got {twinNegNot.canonicalBytes.size}"
  expect (twinNotNeg.sourceHash ==
      "996c545bd6f4f3b935004bf43e0e4ec0a88dde025b4f5d574fd30981a67ca408")
    s!"! - 2 LogicalNotTwin sourceHash golden must remain stable; got {twinNotNeg.sourceHash}"
  expect (twinNotNeg.canonicalBytes.size == 220)
    s!"! - 2 LogicalNotTwin size golden must remain stable; got {twinNotNeg.canonicalBytes.size}"
  expect (twinBitNot.sourceHash ==
      "ff5d24c25dc5da0676e0ac1be20aa3593aea937a59fc1c3a69a4aa3aac5463cc")
    s!"~ ! 2 LogicalNotTwin sourceHash golden must remain stable; got {twinBitNot.sourceHash}"
  expect (twinBitNot.canonicalBytes.size == 220)
    s!"~ ! 2 LogicalNotTwin size golden must remain stable; got {twinBitNot.canonicalBytes.size}"
  expect (twinNotBit.sourceHash ==
      "4752db7095543e6a3b1fdf400c94d97bf14bfd0a38497f5db97689039c6c78af")
    s!"! ~ 2 LogicalNotTwin sourceHash golden must remain stable; got {twinNotBit.sourceHash}"
  expect (twinNotBit.canonicalBytes.size == 220)
    s!"! ~ 2 LogicalNotTwin size golden must remain stable; got {twinNotBit.canonicalBytes.size}"

  -- Non-alias controls.
  expect (twinNot2.sourceHash != twinLit2.sourceHash)
    "logicalNot 2 must not alias literal 2"
  expect (twinNot2.sourceHash != twinNeg2.sourceHash)
    "logicalNot 2 must not alias checkedNeg 2 (operator tag)"
  expect (twinNot2.sourceHash != twinBit2.sourceHash)
    "logicalNot 2 must not alias bitwiseNot 2 (operator tag)"
  expect (twinNot2.canonicalBytes.size == twinNeg2.canonicalBytes.size)
    "logicalNot and checkedNeg of same literal operand must share size"
  expect (twinNot2.canonicalBytes.size == twinBit2.canonicalBytes.size)
    "logicalNot and bitwiseNot of same literal operand must share size"
  expect (twinNotTrue.sourceHash != twinNotFalse.sourceHash)
    "logicalNot true must not alias logicalNot false"
  expect (twinNotMul.sourceHash != twinWrong.sourceHash)
    "!2*3 must not alias wrong logicalNot(mul(2,3))"
  expect (twinNot2.sourceHash != twinNested.sourceHash)
    "single logicalNot must not alias nested logicalNot"
  expect (twinNegNot.sourceHash != twinNotNeg.sourceHash)
    "- ! 2 must not alias ! - 2 (mixed unary order)"
  expect (twinBitNot.sourceHash != twinNotBit.sourceHash)
    "~ ! 2 must not alias ! ~ 2 (mixed unary order)"

  -- Parser-boundary malformed shapes (including deferred != and bare assignment-like).
  for (label, expr) in [
      ("bare bang", "!"),
      ("empty group operand", "!()"),
      ("star after bang", "!*2"),
      ("plus after bang", "!+2"),
      ("extra token after not", "!2 3"),
      ("trailing bang after binary", "1 - !"),
      ("comparison not-equal deferred", "1 != 2"),
      ("bang equals junk", "! = 2")
    ] do
    let source := returnProgramSource "RejectedNotShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<lnot-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed for logicalNot before operand Bool diagnostic.
  match Compiler.compile (twin (.logicalNot (.boolLiteral true))) with
  | .error (.invalidProgram
      "logical not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject !true with exact logical-not message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing logicalNot"

  match Compiler.compile (twin (.logicalNot (.literal 2))) with
  | .error (.invalidProgram
      "logical not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject logicalNot with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing logicalNot"

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

  match Compiler.compile (twin (.bitwiseNot (.literal 2))) with
  | .error (.invalidProgram
      "bitwise not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bitwiseNot must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bitwiseNot twin must remain Typed fail-closed"

end Tests.Language.LogicalNot
