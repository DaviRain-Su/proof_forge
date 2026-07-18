import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- LogicalAndSurface pins binary `&&` in every declaration body position: init, entry,
-- view, and fn. Migration: exactly BitwiseAnd.lean deferred `1 && 2`.
namespace Tests.Language.LogicalAndFixture

open ProofForgeV2.Language

program LogicalAndSurface where
  init() do
    let seed : UInt64 := 1 && 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a && b

  view peek() : UInt64 do
    let value := 1 | 2 && 3
    return value

  fn helper() : UInt64 do
    return 1 && 2 && 3

end Tests.Language.LogicalAndFixture

namespace Tests.Language.LogicalAnd

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LogicalAndFixture.LogicalAndTwin" "LogicalAndTwin" #[
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
  "namespace Tests.Language.LogicalAndFixture\n\n" ++
  "program LogicalAndSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 && 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a && b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 | 2 && 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 && 2 && 3\n\n" ++
  "end Tests.Language.LogicalAndFixture\n"

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

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.LogicalAndFixture.LogicalAndSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.logicalAnd (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 && 2"
  | none => throw <| IO.userError "LogicalAndSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.logicalAnd (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a && b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.logicalAnd (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 | 2 && 3 as (1|2)&&3"
  | _ => throw <| IO.userError "LogicalAndSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.logicalAnd (.logicalAnd (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 && 2 && 3"
  | _ => throw <| IO.userError "LogicalAndSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<logical-and>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same logicalAnd Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same logicalAnd sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins (precedence 30 left-assoc, looser than BitOr 35).
  let land12 ← select session (returnProgramSource "Land12" "1 && 2") "<land-1-2>"
  expectReturnExpr "1 && 2" land12 (.logicalAnd (.literal 1) (.literal 2))

  let land21 ← select session (returnProgramSource "Land21" "2 && 1") "<land-2-1>"
  expectReturnExpr "2 && 1" land21 (.logicalAnd (.literal 2) (.literal 1))

  let landAB ← select session (varReturnProgramSource "LandAB" "a && b") "<land-a-b>"
  expectReturnExpr "a && b" landAB (.logicalAnd (.variable "a") (.variable "b"))

  let land00 ← select session (returnProgramSource "Land00" "0 && 0") "<land-0-0>"
  expectReturnExpr "0 && 0" land00 (.logicalAnd (.literal 0) (.literal 0))

  let landTF ← select session (returnProgramSource "LandTF" "true && false") "<land-t-f>"
  expectReturnExpr "true && false" landTF
    (.logicalAnd (.boolLiteral true) (.boolLiteral false))

  let landFT ← select session (returnProgramSource "LandFT" "false && true") "<land-f-t>"
  expectReturnExpr "false && true" landFT
    (.logicalAnd (.boolLiteral false) (.boolLiteral true))

  let addLand ← select session (returnProgramSource "AddLand" "1 + 2 && 3") "<add-land>"
  expectReturnExpr "1 + 2 && 3" addLand
    (.logicalAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let landAdd ← select session (returnProgramSource "LandAdd" "1 && 2 + 3") "<land-add>"
  expectReturnExpr "1 && 2 + 3" landAdd
    (.logicalAnd (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulLand ← select session (returnProgramSource "MulLand" "1 * 2 && 3") "<mul-land>"
  expectReturnExpr "1 * 2 && 3" mulLand
    (.logicalAnd (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let landMul ← select session (returnProgramSource "LandMul" "1 && 2 * 3") "<land-mul>"
  expectReturnExpr "1 && 2 * 3" landMul
    (.logicalAnd (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlLand ← select session (returnProgramSource "ShlLand" "1 << 2 && 3") "<shl-land>"
  expectReturnExpr "1 << 2 && 3" shlLand
    (.logicalAnd (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let landShl ← select session (returnProgramSource "LandShl" "1 && 2 << 3") "<land-shl>"
  expectReturnExpr "1 && 2 << 3" landShl
    (.logicalAnd (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrLand ← select session (returnProgramSource "ShrLand" "1 >> 2 && 3") "<shr-land>"
  expectReturnExpr "1 >> 2 && 3" shrLand
    (.logicalAnd (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let landShr ← select session (returnProgramSource "LandShr" "1 && 2 >> 3") "<land-shr>"
  expectReturnExpr "1 && 2 >> 3" landShr
    (.logicalAnd (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let landEq ← select session (returnProgramSource "LandEq" "1 && 2 == 3") "<land-eq>"
  expectReturnExpr "1 && 2 == 3" landEq
    (.logicalAnd (.literal 1) (.equal (.literal 2) (.literal 3)))

  let eqLand ← select session (returnProgramSource "EqLand" "1 == 2 && 3") "<eq-land>"
  expectReturnExpr "1 == 2 && 3" eqLand
    (.logicalAnd (.equal (.literal 1) (.literal 2)) (.literal 3))

  let andLand ← select session (returnProgramSource "AndLand" "1 & 2 && 3") "<and-land>"
  expectReturnExpr "1 & 2 && 3" andLand
    (.logicalAnd (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))

  let landAnd ← select session (returnProgramSource "LandAnd" "1 && 2 & 3") "<land-and>"
  expectReturnExpr "1 && 2 & 3" landAnd
    (.logicalAnd (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))

  let xorLand ← select session (returnProgramSource "XorLand" "1 ^ 2 && 3") "<xor-land>"
  expectReturnExpr "1 ^ 2 && 3" xorLand
    (.logicalAnd (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))

  let landXor ← select session (returnProgramSource "LandXor" "1 && 2 ^ 3") "<land-xor>"
  expectReturnExpr "1 && 2 ^ 3" landXor
    (.logicalAnd (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))

  let orLand ← select session (returnProgramSource "OrLand" "1 | 2 && 3") "<or-land>"
  expectReturnExpr "1 | 2 && 3" orLand
    (.logicalAnd (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))

  let landOr ← select session (returnProgramSource "LandOr" "1 && 2 | 3") "<land-or>"
  expectReturnExpr "1 && 2 | 3" landOr
    (.logicalAnd (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 && 2 && 3") "<land-left>"
  expectReturnExpr "1 && 2 && 3" leftChain
    (.logicalAnd (.logicalAnd (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 && (2 && 3)") "<land-right>"
  expectReturnExpr "1 && (2 && 3)" rightNest
    (.logicalAnd (.literal 1) (.logicalAnd (.literal 2) (.literal 3)))

  let groupLand ← select session
    (returnProgramSource "GroupLand" "(1 + 2) && 3") "<group-land>"
  expectReturnExpr "(1 + 2) && 3" groupLand
    (.logicalAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negLand ← select session (returnProgramSource "NegLand" "-1 && 2") "<neg-land>"
  expectReturnExpr "-1 && 2" negLand
    (.logicalAnd (.checkedNeg (.literal 1)) (.literal 2))

  let landNeg ← select session (returnProgramSource "LandNeg" "1 && -2") "<land-neg>"
  expectReturnExpr "1 && -2" landNeg
    (.logicalAnd (.literal 1) (.checkedNeg (.literal 2)))

  -- Same-identity desugar.
  let bareLand ← select session (returnProgramSource "LandSame" "1 && 2") "<land-same-bare>"
  let groupSame ← select session
    (returnProgramSource "LandSame" "(1 && 2)") "<land-same-group>"
  expect (bareLand == groupSame)
    "1 && 2 and (1 && 2) must share Source.Program under identical identity"
  expect (bareLand.canonicalBytes == groupSame.canonicalBytes)
    "1 && 2 and (1 && 2) must share canonical bytes under identical identity"
  expect (bareLand.sourceHash == groupSame.sourceHash)
    "1 && 2 and (1 && 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for LogicalAndTwin (Expr tag 23 + lhs/rhs).
  let twin12 := twin (.logicalAnd (.literal 1) (.literal 2))
  let twin21 := twin (.logicalAnd (.literal 2) (.literal 1))
  let twinAB := twin (.logicalAnd (.variable "a") (.variable "b"))
  let twin00 := twin (.logicalAnd (.literal 0) (.literal 0))
  let twinTF := twin (.logicalAnd (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.logicalAnd (.boolLiteral false) (.boolLiteral true))
  let twinAddLand := twin
    (.logicalAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinLandAdd := twin
    (.logicalAnd (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.logicalAnd (.literal 2) (.literal 3)))
  let twinMulLand := twin
    (.logicalAnd (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinLandMul := twin
    (.logicalAnd (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlLand := twin
    (.logicalAnd (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinLandShl := twin
    (.logicalAnd (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrLand := twin
    (.logicalAnd (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinLandShr := twin
    (.logicalAnd (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinLandEq := twin
    (.logicalAnd (.literal 1) (.equal (.literal 2) (.literal 3)))
  let twinEqLand := twin
    (.logicalAnd (.equal (.literal 1) (.literal 2)) (.literal 3))
  let twinAndLand := twin
    (.logicalAnd (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinLandAnd := twin
    (.logicalAnd (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))
  let twinXorLand := twin
    (.logicalAnd (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))
  let twinLandXor := twin
    (.logicalAnd (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))
  let twinOrLand := twin
    (.logicalAnd (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))
  let twinLandOr := twin
    (.logicalAnd (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))
  let twinLeft := twin
    (.logicalAnd (.logicalAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.logicalAnd (.literal 1) (.logicalAnd (.literal 2) (.literal 3)))
  let twinNegLand := twin
    (.logicalAnd (.checkedNeg (.literal 1)) (.literal 2))
  let twinLandNeg := twin
    (.logicalAnd (.literal 1) (.checkedNeg (.literal 2)))
  let twinOrCtrl := twin (.bitwiseOr (.literal 1) (.literal 2))
  let twinXorCtrl := twin (.bitwiseXor (.literal 1) (.literal 2))
  let twinAndCtrl := twin (.bitwiseAnd (.literal 1) (.literal 2))
  let twinEq := twin (.equal (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "b89596d932de15ebbcea6c3f2694e2fbacaa89a83be4e05a60758b6c05158fe6")
    s!"logicalAnd 1&&2 LogicalAndTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 228)
    s!"logicalAnd 1&&2 LogicalAndTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "6679e8f4476a00519fd007b9d8efca64eebc0e45c29d9719100e881a1eafc635")
    s!"logicalAnd 2&&1 LogicalAndTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 228)
    s!"logicalAnd 2&&1 LogicalAndTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "74eeb2ab0bae7590229bd800ccd7fb80069bb3c9ff00b264fecab7b956b94d3b")
    s!"a&&b LogicalAndTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 230)
    s!"a&&b LogicalAndTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "e83516f914ec6b91ea1b40d2d4a43a76d506b9c8af1ccd83c0e09f51da5658af")
    s!"0&&0 LogicalAndTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 228)
    s!"0&&0 LogicalAndTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "ec66a3b5f8e1b590d105897f577a1d4f90510225238a2d3e14c3f5d44ffc3248")
    s!"true&&false LogicalAndTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 214)
    s!"true&&false LogicalAndTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "d09daae3fa2968290a14505c608d57988e6983d6f317ba3f8b36e87b9d833ae4")
    s!"false&&true LogicalAndTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 214)
    s!"false&&true LogicalAndTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddLand.sourceHash ==
      "d9d172aac240ba4f11e03bb1b565788ac2385a838b03c2a76591a453ffd63954")
    s!"1+2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinAddLand.sourceHash}"
  expect (twinAddLand.canonicalBytes.size == 238)
    s!"1+2&&3 LogicalAndTwin size golden must remain stable; got {twinAddLand.canonicalBytes.size}"
  expect (twinLandAdd.sourceHash ==
      "d8fba5d92ac2eba9c1a01bf061751a6ca843f767b235543d4d69003ceb9ab2eb")
    s!"1&&2+3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandAdd.sourceHash}"
  expect (twinLandAdd.canonicalBytes.size == 238)
    s!"1&&2+3 LogicalAndTwin size golden must remain stable; got {twinLandAdd.canonicalBytes.size}"
  expect (twinMulLand.sourceHash ==
      "b3e5c9c01c4105f507d00248eca98293cc75d19c2370cf45b2c95f9fe1f9d66e")
    s!"1*2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinMulLand.sourceHash}"
  expect (twinMulLand.canonicalBytes.size == 238)
    s!"1*2&&3 LogicalAndTwin size golden must remain stable; got {twinMulLand.canonicalBytes.size}"
  expect (twinLandMul.sourceHash ==
      "275bd246da4958c74130fa8da2d90868a6247dbc658403bcadae1e2e6a44fc8b")
    s!"1&&2*3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandMul.sourceHash}"
  expect (twinLandMul.canonicalBytes.size == 238)
    s!"1&&2*3 LogicalAndTwin size golden must remain stable; got {twinLandMul.canonicalBytes.size}"
  expect (twinShlLand.sourceHash ==
      "6ba490ffe6eea9d415a0ae2caa0c99f7f6dc9ba0db737f6343408f7e83992bd7")
    s!"1<<2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinShlLand.sourceHash}"
  expect (twinShlLand.canonicalBytes.size == 238)
    s!"1<<2&&3 LogicalAndTwin size golden must remain stable; got {twinShlLand.canonicalBytes.size}"
  expect (twinLandShl.sourceHash ==
      "16751195a6bbf1f034b4953c1ce245669423cf65bcddc5e5ea7daa0ac5b11fec")
    s!"1&&2<<3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandShl.sourceHash}"
  expect (twinLandShl.canonicalBytes.size == 238)
    s!"1&&2<<3 LogicalAndTwin size golden must remain stable; got {twinLandShl.canonicalBytes.size}"
  expect (twinShrLand.sourceHash ==
      "f4bfe89cf215e322ac768c903a1477c77c46569fe4bb0ff6988260b8a7ab4311")
    s!"1>>2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinShrLand.sourceHash}"
  expect (twinShrLand.canonicalBytes.size == 238)
    s!"1>>2&&3 LogicalAndTwin size golden must remain stable; got {twinShrLand.canonicalBytes.size}"
  expect (twinLandShr.sourceHash ==
      "f57a44aebfdbcd4fa7f7aec84b53cff265bd384ec8f25f4e4b39052473e6eba7")
    s!"1&&2>>3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandShr.sourceHash}"
  expect (twinLandShr.canonicalBytes.size == 238)
    s!"1&&2>>3 LogicalAndTwin size golden must remain stable; got {twinLandShr.canonicalBytes.size}"
  expect (twinLandEq.sourceHash ==
      "5c2401f1bf7257aa639739f38c118bf1c6410791324521ed8653d8a79697827c")
    s!"1&&2==3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandEq.sourceHash}"
  expect (twinLandEq.canonicalBytes.size == 238)
    s!"1&&2==3 LogicalAndTwin size golden must remain stable; got {twinLandEq.canonicalBytes.size}"
  expect (twinEqLand.sourceHash ==
      "0ec73e60a74793a6d901df1f41c029acd5bc833a181d8d5ae2d089f6c41bf5b9")
    s!"1==2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinEqLand.sourceHash}"
  expect (twinEqLand.canonicalBytes.size == 238)
    s!"1==2&&3 LogicalAndTwin size golden must remain stable; got {twinEqLand.canonicalBytes.size}"
  expect (twinAndLand.sourceHash ==
      "78917e44fe03d9116229ccaa8d0c921fe5ebd1e387e452b5ff91cc29f3bedd56")
    s!"1&2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinAndLand.sourceHash}"
  expect (twinAndLand.canonicalBytes.size == 238)
    s!"1&2&&3 LogicalAndTwin size golden must remain stable; got {twinAndLand.canonicalBytes.size}"
  expect (twinLandAnd.sourceHash ==
      "26c475cd7f656d6d7459970aa523f917663ddd664e60c8bc6a70e8601e63c9b3")
    s!"1&&2&3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandAnd.sourceHash}"
  expect (twinLandAnd.canonicalBytes.size == 238)
    s!"1&&2&3 LogicalAndTwin size golden must remain stable; got {twinLandAnd.canonicalBytes.size}"
  expect (twinXorLand.sourceHash ==
      "3ca35ae86490adce5214e6552ae0713d3e3454d2330922806eab696ccbb147cf")
    s!"1^2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinXorLand.sourceHash}"
  expect (twinXorLand.canonicalBytes.size == 238)
    s!"1^2&&3 LogicalAndTwin size golden must remain stable; got {twinXorLand.canonicalBytes.size}"
  expect (twinLandXor.sourceHash ==
      "87a8872c428578ab8c3f5fc0a3d65fa265160662f2d2262f3318c718c08a1896")
    s!"1&&2^3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandXor.sourceHash}"
  expect (twinLandXor.canonicalBytes.size == 238)
    s!"1&&2^3 LogicalAndTwin size golden must remain stable; got {twinLandXor.canonicalBytes.size}"
  expect (twinOrLand.sourceHash ==
      "fe0348ab3106ac875f4261f832844b10a56a3c7cbd364e72caec4bcc89597a98")
    s!"1|2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinOrLand.sourceHash}"
  expect (twinOrLand.canonicalBytes.size == 238)
    s!"1|2&&3 LogicalAndTwin size golden must remain stable; got {twinOrLand.canonicalBytes.size}"
  expect (twinLandOr.sourceHash ==
      "2f4a528015fdee46de9f7d646e4596fe82edb99a257c468e1eceff57776eb5f7")
    s!"1&&2|3 LogicalAndTwin sourceHash golden must remain stable; got {twinLandOr.sourceHash}"
  expect (twinLandOr.canonicalBytes.size == 238)
    s!"1&&2|3 LogicalAndTwin size golden must remain stable; got {twinLandOr.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "ae21d1bc4527e6e901988a410860d892f7ad49ab9fb581a079f8090bd1f48d72")
    s!"left 1&&2&&3 LogicalAndTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 238)
    s!"left 1&&2&&3 LogicalAndTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "c7551bc55592b2c5a2b3532cc8886c9c78b278ed23bb9630c2d538c4e9ed9dd9")
    s!"right 1&&(2&&3) LogicalAndTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 238)
    s!"right 1&&(2&&3) LogicalAndTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegLand.sourceHash ==
      "778ba6d6182b879e73299f1235f3d59cfcc00172fb5c0d8f818f078735459f3c")
    s!"-1&&2 LogicalAndTwin sourceHash golden must remain stable; got {twinNegLand.sourceHash}"
  expect (twinNegLand.canonicalBytes.size == 229)
    s!"-1&&2 LogicalAndTwin size golden must remain stable; got {twinNegLand.canonicalBytes.size}"
  expect (twinLandNeg.sourceHash ==
      "800e1658dd2a88fd8bacb51afd970234ffb14cbe19046a974ff40f6cf29bc43b")
    s!"1&&-2 LogicalAndTwin sourceHash golden must remain stable; got {twinLandNeg.sourceHash}"
  expect (twinLandNeg.canonicalBytes.size == 229)
    s!"1&&-2 LogicalAndTwin size golden must remain stable; got {twinLandNeg.canonicalBytes.size}"
  expect (twinOrCtrl.sourceHash ==
      "424eeffef120cc82b07d59333dfae83c66b0afeaae3a67252ef90466ad9f2880")
    s!"bitwiseOr 1|2 control LogicalAndTwin sourceHash golden must remain stable; got {twinOrCtrl.sourceHash}"
  expect (twinOrCtrl.canonicalBytes.size == 228)
    s!"bitwiseOr 1|2 control LogicalAndTwin size golden must remain stable; got {twinOrCtrl.canonicalBytes.size}"
  expect (twinXorCtrl.sourceHash ==
      "d9fe5d970055e47c831b2c1a608a0706bd0a3f297f03d82afca07970fe99e28f")
    s!"bitwiseXor 1^2 control LogicalAndTwin sourceHash golden must remain stable; got {twinXorCtrl.sourceHash}"
  expect (twinXorCtrl.canonicalBytes.size == 228)
    s!"bitwiseXor 1^2 control LogicalAndTwin size golden must remain stable; got {twinXorCtrl.canonicalBytes.size}"
  expect (twinAndCtrl.sourceHash ==
      "e988eca402bbe9c4d2927394665058595833377c80c0c26133c4264f185faf95")
    s!"bitwiseAnd 1&2 control LogicalAndTwin sourceHash golden must remain stable; got {twinAndCtrl.sourceHash}"
  expect (twinAndCtrl.canonicalBytes.size == 228)
    s!"bitwiseAnd 1&2 control LogicalAndTwin size golden must remain stable; got {twinAndCtrl.canonicalBytes.size}"
  expect (twinEq.sourceHash ==
      "7ab5e0b834902169cd4881f47230aa408eb4a58efef410b8168e5a3db71c401c")
    s!"equal 1==2 control LogicalAndTwin sourceHash golden must remain stable; got {twinEq.sourceHash}"
  expect (twinEq.canonicalBytes.size == 228)
    s!"equal 1==2 control LogicalAndTwin size golden must remain stable; got {twinEq.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "5aebfb4c2923ee90bd406e3a6fbf25928be17009e6fe43cf178ef6624bc606d3")
    s!"checkedAdd 1+2 control LogicalAndTwin sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 228)
    s!"checkedAdd 1+2 control LogicalAndTwin size golden must remain stable; got {twinAdd.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "logicalAnd 1&&2 must not alias 2&&1 (operand order)"
  expect (twin12.sourceHash != twinOrCtrl.sourceHash)
    "logicalAnd 1&&2 must not alias bitwiseOr 1|2 (operator tag)"
  expect (twin12.sourceHash != twinXorCtrl.sourceHash)
    "logicalAnd 1&&2 must not alias bitwiseXor 1^2 (operator tag)"
  expect (twin12.sourceHash != twinAndCtrl.sourceHash)
    "logicalAnd 1&&2 must not alias bitwiseAnd 1&2 (operator tag)"
  expect (twin12.sourceHash != twinEq.sourceHash)
    "logicalAnd 1&&2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "logicalAnd 1&&2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinOrCtrl.canonicalBytes.size)
    "logicalAnd and bitwiseOr of two small literals must share size (tag-only distinction)"
  expect (twinAddLand.sourceHash != twinWrong.sourceHash)
    "1+2&&3 must not alias wrong C-style 1+(2&&3)"
  expect (twinAddLand.sourceHash != twinLandAdd.sourceHash)
    "1+2&&3 must not alias 1&&2+3"
  expect (twinMulLand.sourceHash != twinLandMul.sourceHash)
    "1*2&&3 must not alias 1&&2*3"
  expect (twinShlLand.sourceHash != twinLandShl.sourceHash)
    "1<<2&&3 must not alias 1&&2<<3"
  expect (twinShrLand.sourceHash != twinLandShr.sourceHash)
    "1>>2&&3 must not alias 1&&2>>3"
  expect (twinLandEq.sourceHash != twinEqLand.sourceHash)
    "1&&2==3 must not alias 1==2&&3"
  expect (twinAndLand.sourceHash != twinLandAnd.sourceHash)
    "1&2&&3 must not alias 1&&2&3"
  expect (twinXorLand.sourceHash != twinLandXor.sourceHash)
    "1^2&&3 must not alias 1&&2^3"
  expect (twinOrLand.sourceHash != twinLandOr.sourceHash)
    "1|2&&3 must not alias 1&&2|3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested logicalAnd must not alias"
  expect (twinNegLand.sourceHash != twinLandNeg.sourceHash)
    "-1&&2 must not alias 1&&-2"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true&&false must not alias false&&true"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0&&0 must not alias 1&&2"

  -- Parser-boundary: malformed digraph shapes (BitwiseOr retains deferred 1 || 2).
  for (label, expr) in [
      ("bare land", "&&"),
      ("missing lhs", "&& 2"),
      ("missing rhs", "1 &&"),
      ("spaced split", "1 && && 2"),
      ("triple amp", "1 &&& 2"),
      ("mixed amp", "1 & && 2"),
      ("extra token", "1 && 2 3")
    ] do
    let source := returnProgramSource "RejectedLandShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<land-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.logicalAnd (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "logical and is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject logicalAnd with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing logicalAnd"

  match Compiler.compile
      (twin (.logicalAnd (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "logical and is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true&&false with logical-and message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true&&false programs"

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

  match Compiler.compile (twin (.greaterEqual (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "greater-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"greaterEqual must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "greaterEqual twin must remain Typed fail-closed"

  match Compiler.compile (twin (.bitwiseAnd (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "bitwise and is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bitwiseAnd must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bitwiseAnd twin must remain Typed fail-closed"

  match Compiler.compile (twin (.bitwiseXor (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "bitwise xor is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bitwiseXor must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bitwiseXor twin must remain Typed fail-closed"

  match Compiler.compile (twin (.bitwiseOr (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "bitwise or is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bitwiseOr must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bitwiseOr twin must remain Typed fail-closed"

end Tests.Language.LogicalAnd
