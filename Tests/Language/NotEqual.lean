import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- NotEqualSurface pins binary `!=` in every declaration body position: init, entry,
-- view, and fn. Migration: exactly LogicalNot.lean deferred `1 != 2` only.
namespace Tests.Language.NotEqualFixture

open ProofForgeV2.Language

program NotEqualSurface where
  init() do
    let seed : UInt64 := 1 != 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a != b

  view peek() : UInt64 do
    let value := 1 + 2 != 3
    return value

  fn helper() : UInt64 do
    return true != false

end Tests.Language.NotEqualFixture

namespace Tests.Language.NotEqual

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.NotEqualFixture.NotEqualTwin" "NotEqualTwin" #[
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
  "namespace Tests.Language.NotEqualFixture\n\n" ++
  "program NotEqualSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 != 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a != b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 != 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true != false\n\n" ++
  "end Tests.Language.NotEqualFixture\n"

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
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
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
  let elaborated := Tests.Language.NotEqualFixture.NotEqualSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.notEqual (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 != 2"
  | none => throw <| IO.userError "NotEqualSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.notEqual (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a != b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.notEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 != 3 as (1+2)!=3"
  | _ => throw <| IO.userError "NotEqualSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.notEqual (.boolLiteral true) (.boolLiteral false))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return true != false"
  | _ => throw <| IO.userError "NotEqualSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<not-equal>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same notEqual Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same notEqual sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 50 non-assoc, both operand slots 51).
  let ne12 ← select session (returnProgramSource "Ne12" "1 != 2") "<ne-1-2>"
  expectReturnExpr "1 != 2" ne12 (.notEqual (.literal 1) (.literal 2))

  let ne21 ← select session (returnProgramSource "Ne21" "2 != 1") "<ne-2-1>"
  expectReturnExpr "2 != 1" ne21 (.notEqual (.literal 2) (.literal 1))

  let neAB ← select session (varReturnProgramSource "NeAB" "a != b") "<ne-a-b>"
  expectReturnExpr "a != b" neAB (.notEqual (.variable "a") (.variable "b"))

  let neTF ← select session (returnProgramSource "NeTF" "true != false") "<ne-t-f>"
  expectReturnExpr "true != false" neTF
    (.notEqual (.boolLiteral true) (.boolLiteral false))

  let neFT ← select session (returnProgramSource "NeFT" "false != true") "<ne-f-t>"
  expectReturnExpr "false != true" neFT
    (.notEqual (.boolLiteral false) (.boolLiteral true))

  let ne00 ← select session (returnProgramSource "Ne00" "0 != 0") "<ne-0-0>"
  expectReturnExpr "0 != 0" ne00 (.notEqual (.literal 0) (.literal 0))

  let addNe ← select session (returnProgramSource "AddNe" "1 + 2 != 3") "<add-ne>"
  expectReturnExpr "1 + 2 != 3" addNe
    (.notEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let neAdd ← select session (returnProgramSource "NeAdd" "1 != 2 + 3") "<ne-add>"
  expectReturnExpr "1 != 2 + 3" neAdd
    (.notEqual (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulNe ← select session (returnProgramSource "MulNe" "1 * 2 != 3") "<mul-ne>"
  expectReturnExpr "1 * 2 != 3" mulNe
    (.notEqual (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let neMul ← select session (returnProgramSource "NeMul" "1 != 2 * 3") "<ne-mul>"
  expectReturnExpr "1 != 2 * 3" neMul
    (.notEqual (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlNe ← select session (returnProgramSource "ShlNe" "1 << 2 != 3") "<shl-ne>"
  expectReturnExpr "1 << 2 != 3" shlNe
    (.notEqual (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let neShl ← select session (returnProgramSource "NeShl" "1 != 2 << 3") "<ne-shl>"
  expectReturnExpr "1 != 2 << 3" neShl
    (.notEqual (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrNe ← select session (returnProgramSource "ShrNe" "1 >> 2 != 3") "<shr-ne>"
  expectReturnExpr "1 >> 2 != 3" shrNe
    (.notEqual (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let neShr ← select session (returnProgramSource "NeShr" "1 != 2 >> 3") "<ne-shr>"
  expectReturnExpr "1 != 2 >> 3" neShr
    (.notEqual (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let groupNe ← select session
    (returnProgramSource "GroupNe" "(1 + 2) != 3") "<group-ne>"
  expectReturnExpr "(1 + 2) != 3" groupNe
    (.notEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negNe ← select session (returnProgramSource "NegNe" "-1 != 2") "<neg-ne>"
  expectReturnExpr "-1 != 2" negNe
    (.notEqual (.checkedNeg (.literal 1)) (.literal 2))

  let neNeg ← select session (returnProgramSource "NeNeg" "1 != -2") "<ne-neg>"
  expectReturnExpr "1 != -2" neNeg
    (.notEqual (.literal 1) (.checkedNeg (.literal 2)))

  let notNe ← select session
    (returnProgramSource "NotNe" "!true != false") "<not-ne>"
  expectReturnExpr "!true != false" notNe
    (.notEqual (.logicalNot (.boolLiteral true)) (.boolLiteral false))

  let neNot ← select session
    (returnProgramSource "NeNot" "1 != !false") "<ne-not>"
  expectReturnExpr "1 != !false" neNot
    (.notEqual (.literal 1) (.logicalNot (.boolLiteral false)))

  -- Same-identity desugar: (1 != 2) and 1 != 2 under identical program name.
  let bareNe ← select session (returnProgramSource "NeSame" "1 != 2") "<ne-same-bare>"
  let groupSame ← select session
    (returnProgramSource "NeSame" "(1 != 2)") "<ne-same-group>"
  expect (bareNe == groupSame)
    "1 != 2 and (1 != 2) must share Source.Program under identical identity"
  expect (bareNe.canonicalBytes == groupSame.canonicalBytes)
    "1 != 2 and (1 != 2) must share canonical bytes under identical identity"
  expect (bareNe.sourceHash == groupSame.sourceHash)
    "1 != 2 and (1 != 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for NotEqualTwin (Expr tag 15 + lhs/rhs).
  let twin12 := twin (.notEqual (.literal 1) (.literal 2))
  let twin21 := twin (.notEqual (.literal 2) (.literal 1))
  let twinAB := twin (.notEqual (.variable "a") (.variable "b"))
  let twinTF := twin (.notEqual (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.notEqual (.boolLiteral false) (.boolLiteral true))
  let twin00 := twin (.notEqual (.literal 0) (.literal 0))
  let twinAddNe := twin
    (.notEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinNeAdd := twin
    (.notEqual (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.notEqual (.literal 2) (.literal 3)))
  let twinMulNe := twin
    (.notEqual (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinNeMul := twin
    (.notEqual (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlNe := twin
    (.notEqual (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinNeShl := twin
    (.notEqual (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrNe := twin
    (.notEqual (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinNeShr := twin
    (.notEqual (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinNegNe := twin
    (.notEqual (.checkedNeg (.literal 1)) (.literal 2))
  let twinNeNeg := twin
    (.notEqual (.literal 1) (.checkedNeg (.literal 2)))
  let twinNotNe := twin
    (.notEqual (.logicalNot (.boolLiteral true)) (.boolLiteral false))
  let twinNeNot := twin
    (.notEqual (.literal 1) (.logicalNot (.boolLiteral false)))
  let twinEqCtrl := twin (.equal (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinShl := twin (.shiftLeft (.literal 1) (.literal 2))
  let twinShr := twin (.shiftRight (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "67d67880083a4d0dfb388b5ed143cb20bc38e06de011394e95f01dc689964aa3")
    s!"notEqual 1!=2 NotEqualTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 222)
    s!"notEqual 1!=2 NotEqualTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "cd2166f9ea79863591a5c0803dbe95881bd5e7032d1aa38cbdf31d1ad2622977")
    s!"notEqual 2!=1 NotEqualTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 222)
    s!"notEqual 2!=1 NotEqualTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "6a872c60e3b8abf027797c97a5e02442fedb1b87809df10565263fef5e95835a")
    s!"a!=b NotEqualTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 224)
    s!"a!=b NotEqualTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "be87f2a2407cfb141d39227db9e2f1ceebc1b174b16604c441e10c16056f3a7f")
    s!"true!=false NotEqualTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 208)
    s!"true!=false NotEqualTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "07225e9e291954153d652ced3ea5d6e28f2bc3bf58479e69e0dbe4cb2239b3bd")
    s!"false!=true NotEqualTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 208)
    s!"false!=true NotEqualTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "a8eaa6835cf48d1d0ee8a7d360a2ffe9872c98b3e4254a4fafcaab1617d9d5b3")
    s!"0!=0 NotEqualTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 222)
    s!"0!=0 NotEqualTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinAddNe.sourceHash ==
      "9baacaad68a3d6d47a5a6aad43432aed9a7ba6584a5f66b1d08e570a40048a4e")
    s!"1+2!=3 NotEqualTwin sourceHash golden must remain stable; got {twinAddNe.sourceHash}"
  expect (twinAddNe.canonicalBytes.size == 232)
    s!"1+2!=3 NotEqualTwin size golden must remain stable; got {twinAddNe.canonicalBytes.size}"
  expect (twinNeAdd.sourceHash ==
      "b265741fe134cbc17e168617e019e3d5a73d96f820c89421f876562675b8d045")
    s!"1!=2+3 NotEqualTwin sourceHash golden must remain stable; got {twinNeAdd.sourceHash}"
  expect (twinNeAdd.canonicalBytes.size == 232)
    s!"1!=2+3 NotEqualTwin size golden must remain stable; got {twinNeAdd.canonicalBytes.size}"
  expect (twinMulNe.sourceHash ==
      "75271482c7412d4ea963efe767d6dd85c57c58912862fc41388a9cf7527ec9bb")
    s!"1*2!=3 NotEqualTwin sourceHash golden must remain stable; got {twinMulNe.sourceHash}"
  expect (twinMulNe.canonicalBytes.size == 232)
    s!"1*2!=3 NotEqualTwin size golden must remain stable; got {twinMulNe.canonicalBytes.size}"
  expect (twinNeMul.sourceHash ==
      "d7703fd3b39f45d0b33cb916482c39d225c46dcc0daf37381ce08cff0aee6428")
    s!"1!=2*3 NotEqualTwin sourceHash golden must remain stable; got {twinNeMul.sourceHash}"
  expect (twinNeMul.canonicalBytes.size == 232)
    s!"1!=2*3 NotEqualTwin size golden must remain stable; got {twinNeMul.canonicalBytes.size}"
  expect (twinShlNe.sourceHash ==
      "82f701c0cccbee82a2b66eeb6b51b5e0950c95b24c4b5d074a15db4b03dd3e64")
    s!"1<<2!=3 NotEqualTwin sourceHash golden must remain stable; got {twinShlNe.sourceHash}"
  expect (twinShlNe.canonicalBytes.size == 232)
    s!"1<<2!=3 NotEqualTwin size golden must remain stable; got {twinShlNe.canonicalBytes.size}"
  expect (twinNeShl.sourceHash ==
      "5cb07ed7d26b10ffd18684eaa600e56599343a6a598a873745276a2a03db5782")
    s!"1!=2<<3 NotEqualTwin sourceHash golden must remain stable; got {twinNeShl.sourceHash}"
  expect (twinNeShl.canonicalBytes.size == 232)
    s!"1!=2<<3 NotEqualTwin size golden must remain stable; got {twinNeShl.canonicalBytes.size}"
  expect (twinShrNe.sourceHash ==
      "bf432615fe32a6a34f0c0833627e491f4a27d35142af73b73035aa3ccd5c0304")
    s!"1>>2!=3 NotEqualTwin sourceHash golden must remain stable; got {twinShrNe.sourceHash}"
  expect (twinShrNe.canonicalBytes.size == 232)
    s!"1>>2!=3 NotEqualTwin size golden must remain stable; got {twinShrNe.canonicalBytes.size}"
  expect (twinNeShr.sourceHash ==
      "ca59d57a19112d1b1cf306d72a28a882a68a3b96fd38004c69a978de49a62e13")
    s!"1!=2>>3 NotEqualTwin sourceHash golden must remain stable; got {twinNeShr.sourceHash}"
  expect (twinNeShr.canonicalBytes.size == 232)
    s!"1!=2>>3 NotEqualTwin size golden must remain stable; got {twinNeShr.canonicalBytes.size}"
  expect (twinNegNe.sourceHash ==
      "bc397b28f5d7df37342ccfa4ffd157b30564d6502376547c5c6d684e19c13980")
    s!"-1!=2 NotEqualTwin sourceHash golden must remain stable; got {twinNegNe.sourceHash}"
  expect (twinNegNe.canonicalBytes.size == 223)
    s!"-1!=2 NotEqualTwin size golden must remain stable; got {twinNegNe.canonicalBytes.size}"
  expect (twinNeNeg.sourceHash ==
      "d8fad4f861ed01f94787c39649d6992584ea7c721d6399275143beb49db7b32f")
    s!"1!=-2 NotEqualTwin sourceHash golden must remain stable; got {twinNeNeg.sourceHash}"
  expect (twinNeNeg.canonicalBytes.size == 223)
    s!"1!=-2 NotEqualTwin size golden must remain stable; got {twinNeNeg.canonicalBytes.size}"
  expect (twinNotNe.sourceHash ==
      "b53f41eda90f7cd68848008bb90b5edf9804ee53fdc63a44b383806859d85bb3")
    s!"!true!=false NotEqualTwin sourceHash golden must remain stable; got {twinNotNe.sourceHash}"
  expect (twinNotNe.canonicalBytes.size == 209)
    s!"!true!=false NotEqualTwin size golden must remain stable; got {twinNotNe.canonicalBytes.size}"
  expect (twinNeNot.sourceHash ==
      "a0a3f813a4e592bfee1f4e2effd4c96709c5bba1941c69cfd6ddfdf507f42108")
    s!"1!=!false NotEqualTwin sourceHash golden must remain stable; got {twinNeNot.sourceHash}"
  expect (twinNeNot.canonicalBytes.size == 216)
    s!"1!=!false NotEqualTwin size golden must remain stable; got {twinNeNot.canonicalBytes.size}"
  expect (twinEqCtrl.sourceHash ==
      "1198b0ff3c3267fa6f9f6947f7260ed0138fb345dc7fd5da38195b5f0602ff8a")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEqCtrl.sourceHash}"
  expect (twinEqCtrl.canonicalBytes.size == 222)
    s!"equal 1==2 control size golden must remain stable; got {twinEqCtrl.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "1e0c354851183a0756807e004a476f4f9b6dcfaa3319eacdb3d4a0f42c632f7f")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 222)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"

  -- Non-alias / precedence / Bool-order / equal-tag discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "notEqual 1!=2 must not alias 2!=1 (operand order)"
  expect (twin12.sourceHash != twinEqCtrl.sourceHash)
    "notEqual 1!=2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "notEqual 1!=2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinEqCtrl.canonicalBytes.size)
    "notEqual and equal of two small literals must share size (tag-only distinction)"
  expect (twin12.canonicalBytes.size == twinAdd.canonicalBytes.size)
    "notEqual and checkedAdd of two small literals must share size (tag-only distinction)"
  expect (twinAddNe.sourceHash != twinWrong.sourceHash)
    "1+2!=3 must not alias wrong C-style 1+(2!=3)"
  expect (twinAddNe.sourceHash != twinNeAdd.sourceHash)
    "1+2!=3 must not alias 1!=2+3 (lhs/rhs add placement)"
  expect (twinMulNe.sourceHash != twinNeMul.sourceHash)
    "1*2!=3 must not alias 1!=2*3"
  expect (twinShlNe.sourceHash != twinNeShl.sourceHash)
    "1<<2!=3 must not alias 1!=2<<3"
  expect (twinShrNe.sourceHash != twinNeShr.sourceHash)
    "1>>2!=3 must not alias 1!=2>>3"
  expect (twinNegNe.sourceHash != twinNeNeg.sourceHash)
    "-1!=2 must not alias 1!=-2 (unary placement)"
  expect (twinNotNe.sourceHash != twinNeNot.sourceHash)
    "!true!=false must not alias 1!=!false"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true!=false must not alias false!=true (Bool operand order)"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0!=0 must not alias 1!=2"
  -- silence unused controls that still pin identity under twin
  expect (twinShl.canonicalBytes.size == twinShr.canonicalBytes.size)
    "shiftLeft and shiftRight of two small literals share size under NotEqualTwin"

  -- Parser-boundary: token integrity, same/mixed chains, malformed.
  for (label, expr) in [
      ("bare not-equal", "!="),
      ("missing lhs", "!= 2"),
      ("missing rhs", "1 !="),
      ("spaced bang equals", "1 ! = 2"),
      ("triple not-equal", "1 !== 2"),
      ("bang equal equal", "1 ! == 2"),
      ("same chain", "1 != 2 != 3"),
      ("mixed eq then ne", "1 == 2 != 3"),
      ("mixed ne then eq", "1 != 2 == 3"),
      ("extra token", "1 != 2 3")
    ] do
    let source := returnProgramSource "RejectedNeShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<ne-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including Bool operands).
  match Compiler.compile (twin (.notEqual (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "not-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject notEqual with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing notEqual"

  match Compiler.compile
      (twin (.notEqual (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "not-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true!=false with not-equal message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true!=false programs"

  match Compiler.compile (twin (.checkedAdd (.literal 1) (.literal 2))) with
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

  match Compiler.compile (twin (.checkedSub (.literal 2) (.literal 1))) with
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

  match Compiler.compile (twin (.checkedDiv (.literal 6) (.literal 3))) with
  | .error (.invalidProgram
      "checked division is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedDiv must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedDiv twin must remain Typed fail-closed"

  match Compiler.compile (twin (.checkedMod (.literal 7) (.literal 3))) with
  | .error (.invalidProgram
      "checked modulo is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedMod must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedMod twin must remain Typed fail-closed"

  match Compiler.compile (twin (.checkedNeg (.literal 1))) with
  | .error (.invalidProgram
      "checked negation is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedNeg must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedNeg twin must remain Typed fail-closed"

  match Compiler.compile (twin (.bitwiseNot (.literal 1))) with
  | .error (.invalidProgram
      "bitwise not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bitwiseNot must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bitwiseNot twin must remain Typed fail-closed"

  match Compiler.compile (twin (.logicalNot (.literal 1))) with
  | .error (.invalidProgram
      "logical not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"logicalNot must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "logicalNot twin must remain Typed fail-closed"

  match Compiler.compile (twin (.shiftLeft (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "shift left is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"shiftLeft must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "shiftLeft twin must remain Typed fail-closed"

  match Compiler.compile (twin (.shiftRight (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "shift right is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"shiftRight must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "shiftRight twin must remain Typed fail-closed"

  match Compiler.compile (twin (.equal (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "equality is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"equal must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "equal twin must remain Typed fail-closed"

end Tests.Language.NotEqual
