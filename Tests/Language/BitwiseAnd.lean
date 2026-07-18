import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- BitwiseAndSurface pins binary `&` in every declaration body position: init, entry,
-- view, and fn. Zero migration: no existing & negatives in the suite.
namespace Tests.Language.BitwiseAndFixture

open ProofForgeV2.Language

program BitwiseAndSurface where
  init() do
    let seed : UInt64 := 1 & 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a & b

  view peek() : UInt64 do
    let value := 1 + 2 & 3
    return value

  fn helper() : UInt64 do
    return 1 & 2 & 3

end Tests.Language.BitwiseAndFixture

namespace Tests.Language.BitwiseAnd

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.BitwiseAndFixture.BitwiseAndTwin" "BitwiseAndTwin" #[
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
  "namespace Tests.Language.BitwiseAndFixture\n\n" ++
  "program BitwiseAndSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 & 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a & b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 & 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 & 2 & 3\n\n" ++
  "end Tests.Language.BitwiseAndFixture\n"

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
  let elaborated := Tests.Language.BitwiseAndFixture.BitwiseAndSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.bitwiseAnd (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 & 2"
  | none => throw <| IO.userError "BitwiseAndSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.bitwiseAnd (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a & b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.bitwiseAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 & 3 as (1+2)&3"
  | _ => throw <| IO.userError "BitwiseAndSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.bitwiseAnd (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 & 2 & 3"
  | _ => throw <| IO.userError "BitwiseAndSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<bitwise-and>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same bitwiseAnd Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same bitwiseAnd sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins (precedence 45 left-assoc, looser than Compare 50).
  let and12 ← select session (returnProgramSource "And12" "1 & 2") "<and-1-2>"
  expectReturnExpr "1 & 2" and12 (.bitwiseAnd (.literal 1) (.literal 2))

  let and21 ← select session (returnProgramSource "And21" "2 & 1") "<and-2-1>"
  expectReturnExpr "2 & 1" and21 (.bitwiseAnd (.literal 2) (.literal 1))

  let andAB ← select session (varReturnProgramSource "AndAB" "a & b") "<and-a-b>"
  expectReturnExpr "a & b" andAB (.bitwiseAnd (.variable "a") (.variable "b"))

  let and00 ← select session (returnProgramSource "And00" "0 & 0") "<and-0-0>"
  expectReturnExpr "0 & 0" and00 (.bitwiseAnd (.literal 0) (.literal 0))

  let andTF ← select session (returnProgramSource "AndTF" "true & false") "<and-t-f>"
  expectReturnExpr "true & false" andTF
    (.bitwiseAnd (.boolLiteral true) (.boolLiteral false))

  let andFT ← select session (returnProgramSource "AndFT" "false & true") "<and-f-t>"
  expectReturnExpr "false & true" andFT
    (.bitwiseAnd (.boolLiteral false) (.boolLiteral true))

  let addAnd ← select session (returnProgramSource "AddAnd" "1 + 2 & 3") "<add-and>"
  expectReturnExpr "1 + 2 & 3" addAnd
    (.bitwiseAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let andAdd ← select session (returnProgramSource "AndAdd" "1 & 2 + 3") "<and-add>"
  expectReturnExpr "1 & 2 + 3" andAdd
    (.bitwiseAnd (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulAnd ← select session (returnProgramSource "MulAnd" "1 * 2 & 3") "<mul-and>"
  expectReturnExpr "1 * 2 & 3" mulAnd
    (.bitwiseAnd (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let andMul ← select session (returnProgramSource "AndMul" "1 & 2 * 3") "<and-mul>"
  expectReturnExpr "1 & 2 * 3" andMul
    (.bitwiseAnd (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlAnd ← select session (returnProgramSource "ShlAnd" "1 << 2 & 3") "<shl-and>"
  expectReturnExpr "1 << 2 & 3" shlAnd
    (.bitwiseAnd (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let andShl ← select session (returnProgramSource "AndShl" "1 & 2 << 3") "<and-shl>"
  expectReturnExpr "1 & 2 << 3" andShl
    (.bitwiseAnd (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrAnd ← select session (returnProgramSource "ShrAnd" "1 >> 2 & 3") "<shr-and>"
  expectReturnExpr "1 >> 2 & 3" shrAnd
    (.bitwiseAnd (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let andShr ← select session (returnProgramSource "AndShr" "1 & 2 >> 3") "<and-shr>"
  expectReturnExpr "1 & 2 >> 3" andShr
    (.bitwiseAnd (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let andEq ← select session (returnProgramSource "AndEq" "1 & 2 == 3") "<and-eq>"
  expectReturnExpr "1 & 2 == 3" andEq
    (.bitwiseAnd (.literal 1) (.equal (.literal 2) (.literal 3)))

  let eqAnd ← select session (returnProgramSource "EqAnd" "1 == 2 & 3") "<eq-and>"
  expectReturnExpr "1 == 2 & 3" eqAnd
    (.bitwiseAnd (.equal (.literal 1) (.literal 2)) (.literal 3))

  let andNe ← select session (returnProgramSource "AndNe" "1 & 2 != 3") "<and-ne>"
  expectReturnExpr "1 & 2 != 3" andNe
    (.bitwiseAnd (.literal 1) (.notEqual (.literal 2) (.literal 3)))

  let neAnd ← select session (returnProgramSource "NeAnd" "1 != 2 & 3") "<ne-and>"
  expectReturnExpr "1 != 2 & 3" neAnd
    (.bitwiseAnd (.notEqual (.literal 1) (.literal 2)) (.literal 3))

  let andLt ← select session (returnProgramSource "AndLt" "1 & 2 < 3") "<and-lt>"
  expectReturnExpr "1 & 2 < 3" andLt
    (.bitwiseAnd (.literal 1) (.lessThan (.literal 2) (.literal 3)))

  let ltAnd ← select session (returnProgramSource "LtAnd" "1 < 2 & 3") "<lt-and>"
  expectReturnExpr "1 < 2 & 3" ltAnd
    (.bitwiseAnd (.lessThan (.literal 1) (.literal 2)) (.literal 3))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 & 2 & 3") "<and-left>"
  expectReturnExpr "1 & 2 & 3" leftChain
    (.bitwiseAnd (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 & (2 & 3)") "<and-right>"
  expectReturnExpr "1 & (2 & 3)" rightNest
    (.bitwiseAnd (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))

  let groupAnd ← select session
    (returnProgramSource "GroupAnd" "(1 + 2) & 3") "<group-and>"
  expectReturnExpr "(1 + 2) & 3" groupAnd
    (.bitwiseAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negAnd ← select session (returnProgramSource "NegAnd" "-1 & 2") "<neg-and>"
  expectReturnExpr "-1 & 2" negAnd
    (.bitwiseAnd (.checkedNeg (.literal 1)) (.literal 2))

  let andNeg ← select session (returnProgramSource "AndNeg" "1 & -2") "<and-neg>"
  expectReturnExpr "1 & -2" andNeg
    (.bitwiseAnd (.literal 1) (.checkedNeg (.literal 2)))

  -- Same-identity desugar.
  let bareAnd ← select session (returnProgramSource "AndSame" "1 & 2") "<and-same-bare>"
  let groupSame ← select session
    (returnProgramSource "AndSame" "(1 & 2)") "<and-same-group>"
  expect (bareAnd == groupSame)
    "1 & 2 and (1 & 2) must share Source.Program under identical identity"
  expect (bareAnd.canonicalBytes == groupSame.canonicalBytes)
    "1 & 2 and (1 & 2) must share canonical bytes under identical identity"
  expect (bareAnd.sourceHash == groupSame.sourceHash)
    "1 & 2 and (1 & 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for BitwiseAndTwin (Expr tag 20 + lhs/rhs).
  let twin12 := twin (.bitwiseAnd (.literal 1) (.literal 2))
  let twin21 := twin (.bitwiseAnd (.literal 2) (.literal 1))
  let twinAB := twin (.bitwiseAnd (.variable "a") (.variable "b"))
  let twin00 := twin (.bitwiseAnd (.literal 0) (.literal 0))
  let twinTF := twin (.bitwiseAnd (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.bitwiseAnd (.boolLiteral false) (.boolLiteral true))
  let twinAddAnd := twin
    (.bitwiseAnd (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinAndAdd := twin
    (.bitwiseAnd (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))
  let twinMulAnd := twin
    (.bitwiseAnd (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinAndMul := twin
    (.bitwiseAnd (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlAnd := twin
    (.bitwiseAnd (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinAndShl := twin
    (.bitwiseAnd (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrAnd := twin
    (.bitwiseAnd (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinAndShr := twin
    (.bitwiseAnd (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinAndEq := twin
    (.bitwiseAnd (.literal 1) (.equal (.literal 2) (.literal 3)))
  let twinEqAnd := twin
    (.bitwiseAnd (.equal (.literal 1) (.literal 2)) (.literal 3))
  let twinAndNe := twin
    (.bitwiseAnd (.literal 1) (.notEqual (.literal 2) (.literal 3)))
  let twinNeAnd := twin
    (.bitwiseAnd (.notEqual (.literal 1) (.literal 2)) (.literal 3))
  let twinAndLt := twin
    (.bitwiseAnd (.literal 1) (.lessThan (.literal 2) (.literal 3)))
  let twinLtAnd := twin
    (.bitwiseAnd (.lessThan (.literal 1) (.literal 2)) (.literal 3))
  let twinLeft := twin
    (.bitwiseAnd (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.bitwiseAnd (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))
  let twinNegAnd := twin
    (.bitwiseAnd (.checkedNeg (.literal 1)) (.literal 2))
  let twinAndNeg := twin
    (.bitwiseAnd (.literal 1) (.checkedNeg (.literal 2)))
  let twinEq := twin (.equal (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "6fede90fbd307070fd4b86e60d48e595da4620e7d37bf8e368418754e2c55890")
    s!"bitwiseAnd 1&2 BitwiseAndTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 228)
    s!"bitwiseAnd 1&2 BitwiseAndTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "80220a38c8f73ac776ea1cc5cf0c2003265d5ef3c8054ba5a1cf34c51915af85")
    s!"bitwiseAnd 2&1 BitwiseAndTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 228)
    s!"bitwiseAnd 2&1 BitwiseAndTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "23ad86b9fc9316f0276213810809e177edca1c0aa3724cc47af4d9e39e2fd6a7")
    s!"a&b BitwiseAndTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 230)
    s!"a&b BitwiseAndTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "cf7b29b4794bcf92483993dbd30a0991523ca8b6fddedf171e9b6cb70a040b7a")
    s!"0&0 BitwiseAndTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 228)
    s!"0&0 BitwiseAndTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "58856d731cd9609d5e416ae0de68c22a7ea104938fae15224c52f514ed419ccc")
    s!"true&false BitwiseAndTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 214)
    s!"true&false BitwiseAndTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "b5a33459cae1e1f43c511ad7137337d5465ac311d5c491f3b560f557b6ef85b2")
    s!"false&true BitwiseAndTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 214)
    s!"false&true BitwiseAndTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddAnd.sourceHash ==
      "24bf1934c49f6f53360ba15e59d89f375ddda13d7eef449feb5917705ff49be2")
    s!"1+2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAddAnd.sourceHash}"
  expect (twinAddAnd.canonicalBytes.size == 238)
    s!"1+2&3 BitwiseAndTwin size golden must remain stable; got {twinAddAnd.canonicalBytes.size}"
  expect (twinAndAdd.sourceHash ==
      "cf794ce6b04eab9abfd753b4a5cacc8fbc1ba41383e0bf27d57d985bcfbe2525")
    s!"1&2+3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndAdd.sourceHash}"
  expect (twinAndAdd.canonicalBytes.size == 238)
    s!"1&2+3 BitwiseAndTwin size golden must remain stable; got {twinAndAdd.canonicalBytes.size}"
  expect (twinMulAnd.sourceHash ==
      "2c0deb3f41a7008e35298c1e8a89e7341aec0a5bed4ac75f1ba0004dec710c39")
    s!"1*2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinMulAnd.sourceHash}"
  expect (twinMulAnd.canonicalBytes.size == 238)
    s!"1*2&3 BitwiseAndTwin size golden must remain stable; got {twinMulAnd.canonicalBytes.size}"
  expect (twinAndMul.sourceHash ==
      "07fc9ffb4aefec980dc8e4e625f8247d1fa2b8f3a1c1f37713649f77fdf6eaee")
    s!"1&2*3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndMul.sourceHash}"
  expect (twinAndMul.canonicalBytes.size == 238)
    s!"1&2*3 BitwiseAndTwin size golden must remain stable; got {twinAndMul.canonicalBytes.size}"
  expect (twinShlAnd.sourceHash ==
      "3dbf5b748b85c6819760675ee5ca8b3ecef2eb2094e80a08f9dd28d73d43143b")
    s!"1<<2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinShlAnd.sourceHash}"
  expect (twinShlAnd.canonicalBytes.size == 238)
    s!"1<<2&3 BitwiseAndTwin size golden must remain stable; got {twinShlAnd.canonicalBytes.size}"
  expect (twinAndShl.sourceHash ==
      "52a25e79ae3820a1e247293f9d4236036c69bfded31346d07548b9cf5fae3bbd")
    s!"1&2<<3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndShl.sourceHash}"
  expect (twinAndShl.canonicalBytes.size == 238)
    s!"1&2<<3 BitwiseAndTwin size golden must remain stable; got {twinAndShl.canonicalBytes.size}"
  expect (twinShrAnd.sourceHash ==
      "b2a9dc35dd2c1b1ce33cf36aecda29e7080a52bf1ad59d69047604f3d74a563c")
    s!"1>>2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinShrAnd.sourceHash}"
  expect (twinShrAnd.canonicalBytes.size == 238)
    s!"1>>2&3 BitwiseAndTwin size golden must remain stable; got {twinShrAnd.canonicalBytes.size}"
  expect (twinAndShr.sourceHash ==
      "aa3cbbb85f1352bd9894b56696702c9eb32d5bccdb19200d29b3b836cae955ba")
    s!"1&2>>3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndShr.sourceHash}"
  expect (twinAndShr.canonicalBytes.size == 238)
    s!"1&2>>3 BitwiseAndTwin size golden must remain stable; got {twinAndShr.canonicalBytes.size}"
  expect (twinAndEq.sourceHash ==
      "2af6993f82817cf257c3de189f0210a2de374e4622ef6c63c362c6a07e487c9f")
    s!"1&2==3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndEq.sourceHash}"
  expect (twinAndEq.canonicalBytes.size == 238)
    s!"1&2==3 BitwiseAndTwin size golden must remain stable; got {twinAndEq.canonicalBytes.size}"
  expect (twinEqAnd.sourceHash ==
      "f0952fca126d7e655f2e368ac7e8b34494d5dff4f31f75fcc644c75b796a8aaf")
    s!"1==2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinEqAnd.sourceHash}"
  expect (twinEqAnd.canonicalBytes.size == 238)
    s!"1==2&3 BitwiseAndTwin size golden must remain stable; got {twinEqAnd.canonicalBytes.size}"
  expect (twinAndNe.sourceHash ==
      "0f19b791244f1f70d4a425b7e8b677086d8e8e8c3dae54b18296af46c59dcbd6")
    s!"1&2!=3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndNe.sourceHash}"
  expect (twinAndNe.canonicalBytes.size == 238)
    s!"1&2!=3 BitwiseAndTwin size golden must remain stable; got {twinAndNe.canonicalBytes.size}"
  expect (twinNeAnd.sourceHash ==
      "f39deed1b7a0e70e998299a84969df2c7fc0a1239b5fccd01f8fbb555e2462cd")
    s!"1!=2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinNeAnd.sourceHash}"
  expect (twinNeAnd.canonicalBytes.size == 238)
    s!"1!=2&3 BitwiseAndTwin size golden must remain stable; got {twinNeAnd.canonicalBytes.size}"
  expect (twinAndLt.sourceHash ==
      "11646eaf05124ae76f4b8d7108de487022eb91dad8c0354410f65698a1b1614a")
    s!"1&2<3 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndLt.sourceHash}"
  expect (twinAndLt.canonicalBytes.size == 238)
    s!"1&2<3 BitwiseAndTwin size golden must remain stable; got {twinAndLt.canonicalBytes.size}"
  expect (twinLtAnd.sourceHash ==
      "3f6f24bc348b2dca03baf9572fe74107d4b53d830ed457d969ee6d4c6dcebee4")
    s!"1<2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinLtAnd.sourceHash}"
  expect (twinLtAnd.canonicalBytes.size == 238)
    s!"1<2&3 BitwiseAndTwin size golden must remain stable; got {twinLtAnd.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "6de67f082d6270d14a91fc5cf8d72f2dcc3b06e22b6fee985ea05658252ec98c")
    s!"left 1&2&3 BitwiseAndTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 238)
    s!"left 1&2&3 BitwiseAndTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "262dbca58bcfd6d3028204c0b59e2c8e7d7589f1d4349d369ee6cb709b5748c2")
    s!"right 1&(2&3) BitwiseAndTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 238)
    s!"right 1&(2&3) BitwiseAndTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegAnd.sourceHash ==
      "2bfcd489bd349abf9d8e2a51cd64edf21c65f23c304f3b63fd5eb6e8a3b4e935")
    s!"-1&2 BitwiseAndTwin sourceHash golden must remain stable; got {twinNegAnd.sourceHash}"
  expect (twinNegAnd.canonicalBytes.size == 229)
    s!"-1&2 BitwiseAndTwin size golden must remain stable; got {twinNegAnd.canonicalBytes.size}"
  expect (twinAndNeg.sourceHash ==
      "c5849ce62d76eea9c0644598d410ce0d3bc9f4ed945d00f40537103d4959f279")
    s!"1&-2 BitwiseAndTwin sourceHash golden must remain stable; got {twinAndNeg.sourceHash}"
  expect (twinAndNeg.canonicalBytes.size == 229)
    s!"1&-2 BitwiseAndTwin size golden must remain stable; got {twinAndNeg.canonicalBytes.size}"
  expect (twinEq.sourceHash ==
      "daa6c09c9e91d5031d680ad58ba8a21ee11865c100c41f4d24066488c77734b0")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEq.sourceHash}"
  expect (twinEq.canonicalBytes.size == 228)
    s!"equal 1==2 control size golden must remain stable; got {twinEq.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "6fc33ccdd4209e92ef8d04c6de2bed2a257f3932e4b7f3a691a98305aceeb5b8")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 228)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "bitwiseAnd 1&2 must not alias 2&1 (operand order)"
  expect (twin12.sourceHash != twinEq.sourceHash)
    "bitwiseAnd 1&2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "bitwiseAnd 1&2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinEq.canonicalBytes.size)
    "bitwiseAnd and equal of two small literals must share size (tag-only distinction)"
  expect (twinAddAnd.sourceHash != twinWrong.sourceHash)
    "1+2&3 must not alias wrong C-style 1+(2&3)"
  expect (twinAddAnd.sourceHash != twinAndAdd.sourceHash)
    "1+2&3 must not alias 1&2+3"
  expect (twinMulAnd.sourceHash != twinAndMul.sourceHash)
    "1*2&3 must not alias 1&2*3"
  expect (twinShlAnd.sourceHash != twinAndShl.sourceHash)
    "1<<2&3 must not alias 1&2<<3"
  expect (twinShrAnd.sourceHash != twinAndShr.sourceHash)
    "1>>2&3 must not alias 1&2>>3"
  expect (twinAndEq.sourceHash != twinEqAnd.sourceHash)
    "1&2==3 must not alias 1==2&3"
  expect (twinAndNe.sourceHash != twinNeAnd.sourceHash)
    "1&2!=3 must not alias 1!=2&3"
  expect (twinAndLt.sourceHash != twinLtAnd.sourceHash)
    "1&2<3 must not alias 1<2&3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested bitwiseAnd must not alias"
  expect (twinNegAnd.sourceHash != twinAndNeg.sourceHash)
    "-1&2 must not alias 1&-2"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true&false must not alias false&true"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0&0 must not alias 1&2"

  -- Parser-boundary: malformed and deferred LogicAnd.
  for (label, expr) in [
      ("bare and", "&"),
      ("missing lhs", "& 2"),
      ("missing rhs", "1 &"),
      ("spaced split", "1 & & 2"),
      ("extra token", "1 & 2 3")
    ] do
    let source := returnProgramSource "RejectedAndShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<and-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.bitwiseAnd (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "bitwise and is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject bitwiseAnd with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing bitwiseAnd"

  match Compiler.compile
      (twin (.bitwiseAnd (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "bitwise and is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true&false with bitwise-and message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true&false programs"

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

end Tests.Language.BitwiseAnd
