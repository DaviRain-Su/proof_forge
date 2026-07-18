import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- GreaterEqualSurface pins binary `>=` in every declaration body position: init, entry,
-- view, and fn. Migration: final Equal.lean deferred `1 >= 2` only.
namespace Tests.Language.GreaterEqualFixture

open ProofForgeV2.Language

program GreaterEqualSurface where
  init() do
    let seed : UInt64 := 1 >= 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a >= b

  view peek() : UInt64 do
    let value := 1 + 2 >= 3
    return value

  fn helper() : UInt64 do
    return true >= false

end Tests.Language.GreaterEqualFixture

namespace Tests.Language.GreaterEqual

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.GreaterEqualFixture.GreaterEqualTwin" "GreaterEqualTwin" #[
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
  "namespace Tests.Language.GreaterEqualFixture\n\n" ++
  "program GreaterEqualSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 >= 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a >= b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 >= 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true >= false\n\n" ++
  "end Tests.Language.GreaterEqualFixture\n"

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
  let elaborated := Tests.Language.GreaterEqualFixture.GreaterEqualSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.greaterEqual (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 >= 2"
  | none => throw <| IO.userError "GreaterEqualSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.greaterEqual (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a >= b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.greaterEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 >= 3 as (1+2)>=3"
  | _ => throw <| IO.userError "GreaterEqualSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.greaterEqual (.boolLiteral true) (.boolLiteral false))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return true >= false"
  | _ => throw <| IO.userError "GreaterEqualSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<greater-equal>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same greaterEqual Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same greaterEqual sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 50 non-assoc, both operand slots 51).
  let ge12 ← select session (returnProgramSource "Ge12" "1 >= 2") "<ge-1-2>"
  expectReturnExpr "1 >= 2" ge12 (.greaterEqual (.literal 1) (.literal 2))

  let ge21 ← select session (returnProgramSource "Ge21" "2 >= 1") "<ge-2-1>"
  expectReturnExpr "2 >= 1" ge21 (.greaterEqual (.literal 2) (.literal 1))

  let geAB ← select session (varReturnProgramSource "GeAB" "a >= b") "<ge-a-b>"
  expectReturnExpr "a >= b" geAB (.greaterEqual (.variable "a") (.variable "b"))

  let ge00 ← select session (returnProgramSource "Ge00" "0 >= 0") "<ge-0-0>"
  expectReturnExpr "0 >= 0" ge00 (.greaterEqual (.literal 0) (.literal 0))

  let geTF ← select session (returnProgramSource "GeTF" "true >= false") "<ge-t-f>"
  expectReturnExpr "true >= false" geTF
    (.greaterEqual (.boolLiteral true) (.boolLiteral false))

  let geFT ← select session (returnProgramSource "GeFT" "false >= true") "<ge-f-t>"
  expectReturnExpr "false >= true" geFT
    (.greaterEqual (.boolLiteral false) (.boolLiteral true))

  let addGe ← select session (returnProgramSource "AddGe" "1 + 2 >= 3") "<add-ge>"
  expectReturnExpr "1 + 2 >= 3" addGe
    (.greaterEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let geAdd ← select session (returnProgramSource "GeAdd" "1 >= 2 + 3") "<ge-add>"
  expectReturnExpr "1 >= 2 + 3" geAdd
    (.greaterEqual (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulGe ← select session (returnProgramSource "MulGe" "1 * 2 >= 3") "<mul-ge>"
  expectReturnExpr "1 * 2 >= 3" mulGe
    (.greaterEqual (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let geMul ← select session (returnProgramSource "GeMul" "1 >= 2 * 3") "<ge-mul>"
  expectReturnExpr "1 >= 2 * 3" geMul
    (.greaterEqual (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shrGe ← select session (returnProgramSource "ShrGe" "1 >> 2 >= 3") "<shr-ge>"
  expectReturnExpr "1 >> 2 >= 3" shrGe
    (.greaterEqual (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let geShr ← select session (returnProgramSource "GeShr" "1 >= 2 >> 3") "<ge-shr>"
  expectReturnExpr "1 >= 2 >> 3" geShr
    (.greaterEqual (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let shlGe ← select session (returnProgramSource "ShlGe" "1 << 2 >= 3") "<shl-ge>"
  expectReturnExpr "1 << 2 >= 3" shlGe
    (.greaterEqual (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let geShl ← select session (returnProgramSource "GeShl" "1 >= 2 << 3") "<ge-shl>"
  expectReturnExpr "1 >= 2 << 3" geShl
    (.greaterEqual (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let groupGe ← select session
    (returnProgramSource "GroupGe" "(1 + 2) >= 3") "<group-ge>"
  expectReturnExpr "(1 + 2) >= 3" groupGe
    (.greaterEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negGe ← select session (returnProgramSource "NegGe" "-1 >= 2") "<neg-ge>"
  expectReturnExpr "-1 >= 2" negGe
    (.greaterEqual (.checkedNeg (.literal 1)) (.literal 2))

  let geNeg ← select session (returnProgramSource "GeNeg" "1 >= -2") "<ge-neg>"
  expectReturnExpr "1 >= -2" geNeg
    (.greaterEqual (.literal 1) (.checkedNeg (.literal 2)))

  -- Controls: 1 > 2 remains greaterThan; 1 >> 2 remains shiftRight.
  let stillGt ← select session (returnProgramSource "StillGt" "1 > 2") "<still-gt>"
  expectReturnExpr "1 > 2" stillGt (.greaterThan (.literal 1) (.literal 2))

  let stillShr ← select session (returnProgramSource "StillShr" "1 >> 2") "<still-shr>"
  expectReturnExpr "1 >> 2" stillShr (.shiftRight (.literal 1) (.literal 2))

  -- Same-identity desugar.
  let bareGe ← select session (returnProgramSource "GeSame" "1 >= 2") "<ge-same-bare>"
  let groupSame ← select session
    (returnProgramSource "GeSame" "(1 >= 2)") "<ge-same-group>"
  expect (bareGe == groupSame)
    "1 >= 2 and (1 >= 2) must share Source.Program under identical identity"
  expect (bareGe.canonicalBytes == groupSame.canonicalBytes)
    "1 >= 2 and (1 >= 2) must share canonical bytes under identical identity"
  expect (bareGe.sourceHash == groupSame.sourceHash)
    "1 >= 2 and (1 >= 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for GreaterEqualTwin (Expr tag 19 + lhs/rhs).
  let twin12 := twin (.greaterEqual (.literal 1) (.literal 2))
  let twin21 := twin (.greaterEqual (.literal 2) (.literal 1))
  let twinAB := twin (.greaterEqual (.variable "a") (.variable "b"))
  let twin00 := twin (.greaterEqual (.literal 0) (.literal 0))
  let twinTF := twin (.greaterEqual (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.greaterEqual (.boolLiteral false) (.boolLiteral true))
  let twinAddGe := twin
    (.greaterEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinGeAdd := twin
    (.greaterEqual (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.greaterEqual (.literal 2) (.literal 3)))
  let twinMulGe := twin
    (.greaterEqual (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinGeMul := twin
    (.greaterEqual (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShrGe := twin
    (.greaterEqual (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinGeShr := twin
    (.greaterEqual (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinShlGe := twin
    (.greaterEqual (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinGeShl := twin
    (.greaterEqual (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinNegGe := twin
    (.greaterEqual (.checkedNeg (.literal 1)) (.literal 2))
  let twinGeNeg := twin
    (.greaterEqual (.literal 1) (.checkedNeg (.literal 2)))
  let twinGtCtrl := twin (.greaterThan (.literal 1) (.literal 2))
  let twinLtCtrl := twin (.lessThan (.literal 1) (.literal 2))
  let twinLeCtrl := twin (.lessEqual (.literal 1) (.literal 2))
  let twinEqCtrl := twin (.equal (.literal 1) (.literal 2))
  let twinNeCtrl := twin (.notEqual (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinShr := twin (.shiftRight (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "366618ab25d2688aacaec173c4ab38ae6b31c1d45deab21e01d058f79205c85a")
    s!"greaterEqual 1>=2 GreaterEqualTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 234)
    s!"greaterEqual 1>=2 GreaterEqualTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "cc252d273832175a831ea4f131b9d19b241fe4eb98a1cf8dd36d4ba03e6497fb")
    s!"greaterEqual 2>=1 GreaterEqualTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 234)
    s!"greaterEqual 2>=1 GreaterEqualTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "011be5b8751ff5b2c74b760a633eb3a4db3b5c1701c0ca50fe12837e8d054450")
    s!"a>=b GreaterEqualTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 236)
    s!"a>=b GreaterEqualTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "42656efa2ed8e4f3b3dbe7fda60c80f30dd70dcb60c91a8840e1fb410c7142e1")
    s!"0>=0 GreaterEqualTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 234)
    s!"0>=0 GreaterEqualTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "0eb6e86ada321ed7c40afc4f572f420c8a98f7ec80104c6fbfb6d45ebc6368cf")
    s!"true>=false GreaterEqualTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 220)
    s!"true>=false GreaterEqualTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "462f46219a4ce7b556c3bfa25dc68d3c8d84e5317684b168e0a32dac4173cb57")
    s!"false>=true GreaterEqualTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 220)
    s!"false>=true GreaterEqualTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddGe.sourceHash ==
      "5623ac1fcacc714e2d3de0d40075cca3945d58692c09fc28c4f4d8eb7b940603")
    s!"1+2>=3 GreaterEqualTwin sourceHash golden must remain stable; got {twinAddGe.sourceHash}"
  expect (twinAddGe.canonicalBytes.size == 244)
    s!"1+2>=3 GreaterEqualTwin size golden must remain stable; got {twinAddGe.canonicalBytes.size}"
  expect (twinGeAdd.sourceHash ==
      "40dcd2212b02095683f72ddfde487f374c9ceba20741bd8fe75d48545849a75a")
    s!"1>=2+3 GreaterEqualTwin sourceHash golden must remain stable; got {twinGeAdd.sourceHash}"
  expect (twinGeAdd.canonicalBytes.size == 244)
    s!"1>=2+3 GreaterEqualTwin size golden must remain stable; got {twinGeAdd.canonicalBytes.size}"
  expect (twinMulGe.sourceHash ==
      "dce0f5ecca0161b48a6aabd9f47815a2ab71691816fde13b1802bb2026f21dd5")
    s!"1*2>=3 GreaterEqualTwin sourceHash golden must remain stable; got {twinMulGe.sourceHash}"
  expect (twinMulGe.canonicalBytes.size == 244)
    s!"1*2>=3 GreaterEqualTwin size golden must remain stable; got {twinMulGe.canonicalBytes.size}"
  expect (twinGeMul.sourceHash ==
      "4e2fc3a96415d6b88f72a203e570b87edde3dfe4c122cded1a81767d7229f5ef")
    s!"1>=2*3 GreaterEqualTwin sourceHash golden must remain stable; got {twinGeMul.sourceHash}"
  expect (twinGeMul.canonicalBytes.size == 244)
    s!"1>=2*3 GreaterEqualTwin size golden must remain stable; got {twinGeMul.canonicalBytes.size}"
  expect (twinShrGe.sourceHash ==
      "5bdde75341b7b45cce2e17ad8f3b7e5932a302b916f7b74bc3faee406335f6ae")
    s!"1>>2>=3 GreaterEqualTwin sourceHash golden must remain stable; got {twinShrGe.sourceHash}"
  expect (twinShrGe.canonicalBytes.size == 244)
    s!"1>>2>=3 GreaterEqualTwin size golden must remain stable; got {twinShrGe.canonicalBytes.size}"
  expect (twinGeShr.sourceHash ==
      "879156eed4660d8a16c7f5bea1f61454ab55a836b0e7fecdf3901c7c1475d62c")
    s!"1>=2>>3 GreaterEqualTwin sourceHash golden must remain stable; got {twinGeShr.sourceHash}"
  expect (twinGeShr.canonicalBytes.size == 244)
    s!"1>=2>>3 GreaterEqualTwin size golden must remain stable; got {twinGeShr.canonicalBytes.size}"
  expect (twinShlGe.sourceHash ==
      "4baeccc174ad344ea48dd5dd542d1f2281760f7b0889384e4f32b4ddba8da0b6")
    s!"1<<2>=3 GreaterEqualTwin sourceHash golden must remain stable; got {twinShlGe.sourceHash}"
  expect (twinShlGe.canonicalBytes.size == 244)
    s!"1<<2>=3 GreaterEqualTwin size golden must remain stable; got {twinShlGe.canonicalBytes.size}"
  expect (twinGeShl.sourceHash ==
      "7f6fb364cb32d4e15cfd3963f1e8184ab2a5b31a4f9c240e35ce730bd3e6b3a4")
    s!"1>=2<<3 GreaterEqualTwin sourceHash golden must remain stable; got {twinGeShl.sourceHash}"
  expect (twinGeShl.canonicalBytes.size == 244)
    s!"1>=2<<3 GreaterEqualTwin size golden must remain stable; got {twinGeShl.canonicalBytes.size}"
  expect (twinNegGe.sourceHash ==
      "3fe7111454234791726fda5b756aae9fc6f9acac515c6100b6b3f83a1e2c678d")
    s!"-1>=2 GreaterEqualTwin sourceHash golden must remain stable; got {twinNegGe.sourceHash}"
  expect (twinNegGe.canonicalBytes.size == 235)
    s!"-1>=2 GreaterEqualTwin size golden must remain stable; got {twinNegGe.canonicalBytes.size}"
  expect (twinGeNeg.sourceHash ==
      "12aace24cca94c60af93bda960613a682a3381a676e3784c5fb369a2b33d97e0")
    s!"1>=-2 GreaterEqualTwin sourceHash golden must remain stable; got {twinGeNeg.sourceHash}"
  expect (twinGeNeg.canonicalBytes.size == 235)
    s!"1>=-2 GreaterEqualTwin size golden must remain stable; got {twinGeNeg.canonicalBytes.size}"
  expect (twinGtCtrl.sourceHash ==
      "1eec049d1b2c19c64cac903c272fd57328afb4f29c2a0d7a96a2791502bf0330")
    s!"greaterThan 1>2 control sourceHash golden must remain stable; got {twinGtCtrl.sourceHash}"
  expect (twinGtCtrl.canonicalBytes.size == 234)
    s!"greaterThan 1>2 control size golden must remain stable; got {twinGtCtrl.canonicalBytes.size}"
  expect (twinLtCtrl.sourceHash ==
      "3ffa66baa685dd43d3b7f900c76948383e8b0509d728038315430aca32bae8ac")
    s!"lessThan 1<2 control sourceHash golden must remain stable; got {twinLtCtrl.sourceHash}"
  expect (twinLtCtrl.canonicalBytes.size == 234)
    s!"lessThan 1<2 control size golden must remain stable; got {twinLtCtrl.canonicalBytes.size}"
  expect (twinLeCtrl.sourceHash ==
      "28d34d6824a7cde3f919c685cc61b62963d826562a797a58e78f0e75026c2d43")
    s!"lessEqual 1<=2 control sourceHash golden must remain stable; got {twinLeCtrl.sourceHash}"
  expect (twinLeCtrl.canonicalBytes.size == 234)
    s!"lessEqual 1<=2 control size golden must remain stable; got {twinLeCtrl.canonicalBytes.size}"
  expect (twinEqCtrl.sourceHash ==
      "4b1efc4488111a78bd98dd483e0ec664938b4967f42ffc8ebd57193048ec421e")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEqCtrl.sourceHash}"
  expect (twinEqCtrl.canonicalBytes.size == 234)
    s!"equal 1==2 control size golden must remain stable; got {twinEqCtrl.canonicalBytes.size}"
  expect (twinNeCtrl.sourceHash ==
      "c0b60b452a15666fdbe410012351b92abacf47a65084eaff2a640b333816cb62")
    s!"notEqual 1!=2 control sourceHash golden must remain stable; got {twinNeCtrl.sourceHash}"
  expect (twinNeCtrl.canonicalBytes.size == 234)
    s!"notEqual 1!=2 control size golden must remain stable; got {twinNeCtrl.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "ffe7b1973c2a281ce992a7a670d224465a24fdaa8410990c66ee8ac9b25a66a8")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 234)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinShr.sourceHash ==
      "3344b30e3980a1f193095b4833b451c89b2564b6cd3abb51fb39ff0751ff2e02")
    s!"shiftRight 1>>2 control sourceHash golden must remain stable; got {twinShr.sourceHash}"
  expect (twinShr.canonicalBytes.size == 234)
    s!"shiftRight 1>>2 control size golden must remain stable; got {twinShr.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "greaterEqual 1>=2 must not alias 2>=1 (operand order)"
  expect (twin12.sourceHash != twinGtCtrl.sourceHash)
    "greaterEqual 1>=2 must not alias greaterThan 1>2 (operator tag)"
  expect (twin12.sourceHash != twinLtCtrl.sourceHash)
    "greaterEqual 1>=2 must not alias lessThan 1<2 (operator tag)"
  expect (twin12.sourceHash != twinLeCtrl.sourceHash)
    "greaterEqual 1>=2 must not alias lessEqual 1<=2 (operator tag)"
  expect (twin12.sourceHash != twinEqCtrl.sourceHash)
    "greaterEqual 1>=2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinNeCtrl.sourceHash)
    "greaterEqual 1>=2 must not alias notEqual 1!=2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "greaterEqual 1>=2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.sourceHash != twinShr.sourceHash)
    "greaterEqual 1>=2 must not alias shiftRight 1>>2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinGtCtrl.canonicalBytes.size)
    "greaterEqual and greaterThan of two small literals must share size (tag-only distinction)"
  expect (twinAddGe.sourceHash != twinWrong.sourceHash)
    "1+2>=3 must not alias wrong C-style 1+(2>=3)"
  expect (twinAddGe.sourceHash != twinGeAdd.sourceHash)
    "1+2>=3 must not alias 1>=2+3 (lhs/rhs add placement)"
  expect (twinMulGe.sourceHash != twinGeMul.sourceHash)
    "1*2>=3 must not alias 1>=2*3"
  expect (twinShrGe.sourceHash != twinGeShr.sourceHash)
    "1>>2>=3 must not alias 1>=2>>3"
  expect (twinShlGe.sourceHash != twinGeShl.sourceHash)
    "1<<2>=3 must not alias 1>=2<<3"
  expect (twinNegGe.sourceHash != twinGeNeg.sourceHash)
    "-1>=2 must not alias 1>=-2 (unary placement)"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true>=false must not alias false>=true (Bool operand order)"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0>=0 must not alias 1>=2"

  -- Parser-boundary: token integrity, same chain, all ten mixed directions, malformed.
  for (label, expr) in [
      ("bare greater-equal", ">="),
      ("missing lhs", ">= 2"),
      ("missing rhs", "1 >="),
      ("extra token", "1 >= 2 3"),
      ("spaced gt equals", "1 > = 2"),
      ("shift assign-like", "1 >>= 2"),
      ("spaced ge equals", "1 >= = 2"),
      ("same chain", "1 >= 2 >= 3"),
      ("mixed ge then eq", "1 >= 2 == 3"),
      ("mixed eq then ge", "1 == 2 >= 3"),
      ("mixed ge then ne", "1 >= 2 != 3"),
      ("mixed ne then ge", "1 != 2 >= 3"),
      ("mixed ge then lt", "1 >= 2 < 3"),
      ("mixed lt then ge", "1 < 2 >= 3"),
      ("mixed ge then le", "1 >= 2 <= 3"),
      ("mixed le then ge", "1 <= 2 >= 3"),
      ("mixed ge then gt", "1 >= 2 > 3"),
      ("mixed gt then ge", "1 > 2 >= 3")
    ] do
    let source := returnProgramSource "RejectedGeShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<ge-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including Bool operands).
  match Compiler.compile (twin (.greaterEqual (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "greater-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject greaterEqual with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing greaterEqual"

  match Compiler.compile
      (twin (.greaterEqual (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "greater-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true>=false with greater-equal message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true>=false programs"

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

  match Compiler.compile (twin (.notEqual (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "not-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"notEqual must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "notEqual twin must remain Typed fail-closed"

  match Compiler.compile (twin (.lessThan (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "less-than comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"lessThan must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "lessThan twin must remain Typed fail-closed"

  match Compiler.compile (twin (.lessEqual (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "less-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"lessEqual must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "lessEqual twin must remain Typed fail-closed"

  match Compiler.compile (twin (.greaterThan (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "greater-than comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"greaterThan must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "greaterThan twin must remain Typed fail-closed"

end Tests.Language.GreaterEqual
