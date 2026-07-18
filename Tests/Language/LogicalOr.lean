import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- LogicalOrSurface pins binary `||` in every declaration body position: init, entry,
-- view, and fn. Migration: exactly BitwiseOr.lean deferred `1 || 2`.
namespace Tests.Language.LogicalOrFixture

open ProofForgeV2.Language

program LogicalOrSurface where
  init() do
    let seed : UInt64 := 1 || 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a || b

  view peek() : UInt64 do
    let value := 1 && 2 || 3
    return value

  fn helper() : UInt64 do
    return 1 || 2 || 3

end Tests.Language.LogicalOrFixture

namespace Tests.Language.LogicalOr

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LogicalOrFixture.LogicalOrTwin" "LogicalOrTwin" #[
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
  "namespace Tests.Language.LogicalOrFixture\n\n" ++
  "program LogicalOrSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 || 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a || b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 && 2 || 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 || 2 || 3\n\n" ++
  "end Tests.Language.LogicalOrFixture\n"

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
  let elaborated := Tests.Language.LogicalOrFixture.LogicalOrSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.logicalOr (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 || 2"
  | none => throw <| IO.userError "LogicalOrSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.logicalOr (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a || b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.logicalOr (.logicalAnd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 && 2 || 3 as (1&&2)||3"
  | _ => throw <| IO.userError "LogicalOrSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.logicalOr (.logicalOr (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 || 2 || 3"
  | _ => throw <| IO.userError "LogicalOrSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<logical-or>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same logicalOr Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same logicalOr sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins (precedence 25 left-assoc, looser than LogicAnd 30).
  let lor12 ← select session (returnProgramSource "Lor12" "1 || 2") "<lor-1-2>"
  expectReturnExpr "1 || 2" lor12 (.logicalOr (.literal 1) (.literal 2))

  let lor21 ← select session (returnProgramSource "Lor21" "2 || 1") "<lor-2-1>"
  expectReturnExpr "2 || 1" lor21 (.logicalOr (.literal 2) (.literal 1))

  let lorAB ← select session (varReturnProgramSource "LorAB" "a || b") "<lor-a-b>"
  expectReturnExpr "a || b" lorAB (.logicalOr (.variable "a") (.variable "b"))

  let lor00 ← select session (returnProgramSource "Lor00" "0 || 0") "<lor-0-0>"
  expectReturnExpr "0 || 0" lor00 (.logicalOr (.literal 0) (.literal 0))

  let lorTF ← select session (returnProgramSource "LorTF" "true || false") "<lor-t-f>"
  expectReturnExpr "true || false" lorTF
    (.logicalOr (.boolLiteral true) (.boolLiteral false))

  let lorFT ← select session (returnProgramSource "LorFT" "false || true") "<lor-f-t>"
  expectReturnExpr "false || true" lorFT
    (.logicalOr (.boolLiteral false) (.boolLiteral true))

  let addLor ← select session (returnProgramSource "AddLor" "1 + 2 || 3") "<add-lor>"
  expectReturnExpr "1 + 2 || 3" addLor
    (.logicalOr (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let lorAdd ← select session (returnProgramSource "LorAdd" "1 || 2 + 3") "<lor-add>"
  expectReturnExpr "1 || 2 + 3" lorAdd
    (.logicalOr (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulLor ← select session (returnProgramSource "MulLor" "1 * 2 || 3") "<mul-lor>"
  expectReturnExpr "1 * 2 || 3" mulLor
    (.logicalOr (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let lorMul ← select session (returnProgramSource "LorMul" "1 || 2 * 3") "<lor-mul>"
  expectReturnExpr "1 || 2 * 3" lorMul
    (.logicalOr (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlLor ← select session (returnProgramSource "ShlLor" "1 << 2 || 3") "<shl-lor>"
  expectReturnExpr "1 << 2 || 3" shlLor
    (.logicalOr (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let lorShl ← select session (returnProgramSource "LorShl" "1 || 2 << 3") "<lor-shl>"
  expectReturnExpr "1 || 2 << 3" lorShl
    (.logicalOr (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrLor ← select session (returnProgramSource "ShrLor" "1 >> 2 || 3") "<shr-lor>"
  expectReturnExpr "1 >> 2 || 3" shrLor
    (.logicalOr (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let lorShr ← select session (returnProgramSource "LorShr" "1 || 2 >> 3") "<lor-shr>"
  expectReturnExpr "1 || 2 >> 3" lorShr
    (.logicalOr (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let lorEq ← select session (returnProgramSource "LorEq" "1 || 2 == 3") "<lor-eq>"
  expectReturnExpr "1 || 2 == 3" lorEq
    (.logicalOr (.literal 1) (.equal (.literal 2) (.literal 3)))

  let eqLor ← select session (returnProgramSource "EqLor" "1 == 2 || 3") "<eq-lor>"
  expectReturnExpr "1 == 2 || 3" eqLor
    (.logicalOr (.equal (.literal 1) (.literal 2)) (.literal 3))

  let andLor ← select session (returnProgramSource "AndLor" "1 & 2 || 3") "<and-lor>"
  expectReturnExpr "1 & 2 || 3" andLor
    (.logicalOr (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))

  let lorAnd ← select session (returnProgramSource "LorAnd" "1 || 2 & 3") "<lor-and>"
  expectReturnExpr "1 || 2 & 3" lorAnd
    (.logicalOr (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))

  let xorLor ← select session (returnProgramSource "XorLor" "1 ^ 2 || 3") "<xor-lor>"
  expectReturnExpr "1 ^ 2 || 3" xorLor
    (.logicalOr (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))

  let lorXor ← select session (returnProgramSource "LorXor" "1 || 2 ^ 3") "<lor-xor>"
  expectReturnExpr "1 || 2 ^ 3" lorXor
    (.logicalOr (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))

  let orLor ← select session (returnProgramSource "OrLor" "1 | 2 || 3") "<or-lor>"
  expectReturnExpr "1 | 2 || 3" orLor
    (.logicalOr (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))

  let lorOr ← select session (returnProgramSource "LorOr" "1 || 2 | 3") "<lor-or>"
  expectReturnExpr "1 || 2 | 3" lorOr
    (.logicalOr (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))

  let landLor ← select session (returnProgramSource "LandLor" "1 && 2 || 3") "<land-lor>"
  expectReturnExpr "1 && 2 || 3" landLor
    (.logicalOr (.logicalAnd (.literal 1) (.literal 2)) (.literal 3))

  let lorLand ← select session (returnProgramSource "LorLand" "1 || 2 && 3") "<lor-land>"
  expectReturnExpr "1 || 2 && 3" lorLand
    (.logicalOr (.literal 1) (.logicalAnd (.literal 2) (.literal 3)))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 || 2 || 3") "<lor-left>"
  expectReturnExpr "1 || 2 || 3" leftChain
    (.logicalOr (.logicalOr (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 || (2 || 3)") "<lor-right>"
  expectReturnExpr "1 || (2 || 3)" rightNest
    (.logicalOr (.literal 1) (.logicalOr (.literal 2) (.literal 3)))

  let groupLor ← select session
    (returnProgramSource "GroupLor" "(1 + 2) || 3") "<group-lor>"
  expectReturnExpr "(1 + 2) || 3" groupLor
    (.logicalOr (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negLor ← select session (returnProgramSource "NegLor" "-1 || 2") "<neg-lor>"
  expectReturnExpr "-1 || 2" negLor
    (.logicalOr (.checkedNeg (.literal 1)) (.literal 2))

  let lorNeg ← select session (returnProgramSource "LorNeg" "1 || -2") "<lor-neg>"
  expectReturnExpr "1 || -2" lorNeg
    (.logicalOr (.literal 1) (.checkedNeg (.literal 2)))

  -- Same-identity desugar.
  let bareLor ← select session (returnProgramSource "LorSame" "1 || 2") "<lor-same-bare>"
  let groupSame ← select session
    (returnProgramSource "LorSame" "(1 || 2)") "<lor-same-group>"
  expect (bareLor == groupSame)
    "1 || 2 and (1 || 2) must share Source.Program under identical identity"
  expect (bareLor.canonicalBytes == groupSame.canonicalBytes)
    "1 || 2 and (1 || 2) must share canonical bytes under identical identity"
  expect (bareLor.sourceHash == groupSame.sourceHash)
    "1 || 2 and (1 || 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for LogicalOrTwin (Expr tag 24 + lhs/rhs).
  let twin12 := twin (.logicalOr (.literal 1) (.literal 2))
  let twin21 := twin (.logicalOr (.literal 2) (.literal 1))
  let twinAB := twin (.logicalOr (.variable "a") (.variable "b"))
  let twin00 := twin (.logicalOr (.literal 0) (.literal 0))
  let twinTF := twin (.logicalOr (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.logicalOr (.boolLiteral false) (.boolLiteral true))
  let twinAddLor := twin
    (.logicalOr (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinLorAdd := twin
    (.logicalOr (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.logicalOr (.literal 2) (.literal 3)))
  let twinMulLor := twin
    (.logicalOr (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinLorMul := twin
    (.logicalOr (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlLor := twin
    (.logicalOr (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinLorShl := twin
    (.logicalOr (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrLor := twin
    (.logicalOr (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinLorShr := twin
    (.logicalOr (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinLorEq := twin
    (.logicalOr (.literal 1) (.equal (.literal 2) (.literal 3)))
  let twinEqLor := twin
    (.logicalOr (.equal (.literal 1) (.literal 2)) (.literal 3))
  let twinAndLor := twin
    (.logicalOr (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinLorAnd := twin
    (.logicalOr (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))
  let twinXorLor := twin
    (.logicalOr (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))
  let twinLorXor := twin
    (.logicalOr (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))
  let twinOrLor := twin
    (.logicalOr (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))
  let twinLorOr := twin
    (.logicalOr (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))
  let twinLandLor := twin
    (.logicalOr (.logicalAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinLorLand := twin
    (.logicalOr (.literal 1) (.logicalAnd (.literal 2) (.literal 3)))
  let twinLeft := twin
    (.logicalOr (.logicalOr (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.logicalOr (.literal 1) (.logicalOr (.literal 2) (.literal 3)))
  let twinNegLor := twin
    (.logicalOr (.checkedNeg (.literal 1)) (.literal 2))
  let twinLorNeg := twin
    (.logicalOr (.literal 1) (.checkedNeg (.literal 2)))
  let twinLandCtrl := twin (.logicalAnd (.literal 1) (.literal 2))
  let twinOrCtrl := twin (.bitwiseOr (.literal 1) (.literal 2))
  let twinXorCtrl := twin (.bitwiseXor (.literal 1) (.literal 2))
  let twinAndCtrl := twin (.bitwiseAnd (.literal 1) (.literal 2))
  let twinEq := twin (.equal (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  expect (twin12.sourceHash ==
      "0d003490a306ffbf450ac6b6f14e52269b45ad323c5cbfb0c20bb185b28d19c8")
    s!"logicalOr 1||2 LogicalOrTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 225)
    s!"logicalOr 1||2 LogicalOrTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "b914f5d794a6d870f6340efe0cd0d5abef4456232c5a5845095a51b10d244a3b")
    s!"logicalOr 2||1 LogicalOrTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 225)
    s!"logicalOr 2||1 LogicalOrTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "cfbb00b7fa8f3c7e99579db13045bdb27ae826ec71e85d14416a01cdff858eaa")
    s!"a||b LogicalOrTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 227)
    s!"a||b LogicalOrTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "b526a49f787e2a5b000a1b9c6707f6624c40dbc93428bdc2844fcedbeed5d797")
    s!"0||0 LogicalOrTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 225)
    s!"0||0 LogicalOrTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "cd96205fda841af0c6721e03bb8a5be12fc3ea2228a85dfdce03b88a490f30b5")
    s!"true||false LogicalOrTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 211)
    s!"true||false LogicalOrTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "7c3bfc057ed03fc4ac1f00a4f8b95bbf1bc9621d85a98ac3bad600f217bac1a2")
    s!"false||true LogicalOrTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 211)
    s!"false||true LogicalOrTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddLor.sourceHash ==
      "5a4bc6b01e5cbdb6db1afcee7f0f37126fee8afa7066f2cd9b6df365a6cbef21")
    s!"1+2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinAddLor.sourceHash}"
  expect (twinAddLor.canonicalBytes.size == 235)
    s!"1+2||3 LogicalOrTwin size golden must remain stable; got {twinAddLor.canonicalBytes.size}"
  expect (twinLorAdd.sourceHash ==
      "8154f0bf446c52810a4191a7645f819a10baa88aad965dcab4c4e59599f65d17")
    s!"1||2+3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorAdd.sourceHash}"
  expect (twinLorAdd.canonicalBytes.size == 235)
    s!"1||2+3 LogicalOrTwin size golden must remain stable; got {twinLorAdd.canonicalBytes.size}"
  expect (twinMulLor.sourceHash ==
      "2a82cb74257cd01da8b1bd8c84d5808ad21af55ce022b0afd12491109691ae5e")
    s!"1*2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinMulLor.sourceHash}"
  expect (twinMulLor.canonicalBytes.size == 235)
    s!"1*2||3 LogicalOrTwin size golden must remain stable; got {twinMulLor.canonicalBytes.size}"
  expect (twinLorMul.sourceHash ==
      "68c03dfebadb66a68b8c1dec447f885c50032cd6c99ffbdbb800812318c742fa")
    s!"1||2*3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorMul.sourceHash}"
  expect (twinLorMul.canonicalBytes.size == 235)
    s!"1||2*3 LogicalOrTwin size golden must remain stable; got {twinLorMul.canonicalBytes.size}"
  expect (twinShlLor.sourceHash ==
      "c9d9473c5d4b0fb3e07fc1a079e0b5c80264ef76a744059d2dac775090e3f974")
    s!"1<<2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinShlLor.sourceHash}"
  expect (twinShlLor.canonicalBytes.size == 235)
    s!"1<<2||3 LogicalOrTwin size golden must remain stable; got {twinShlLor.canonicalBytes.size}"
  expect (twinLorShl.sourceHash ==
      "be95a109b3a89714b1cc76781fa76063ca750f4139b443e6203c07c7dd837a31")
    s!"1||2<<3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorShl.sourceHash}"
  expect (twinLorShl.canonicalBytes.size == 235)
    s!"1||2<<3 LogicalOrTwin size golden must remain stable; got {twinLorShl.canonicalBytes.size}"
  expect (twinShrLor.sourceHash ==
      "5b9cabd91b9c1d63b336cd851eb3f5d8b3cb9aea1cbcc8bc4e6d1c6e9900d0b3")
    s!"1>>2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinShrLor.sourceHash}"
  expect (twinShrLor.canonicalBytes.size == 235)
    s!"1>>2||3 LogicalOrTwin size golden must remain stable; got {twinShrLor.canonicalBytes.size}"
  expect (twinLorShr.sourceHash ==
      "dc171ca03d3cec83c21545bfe13c3bbf3e6b5c45f78dd3434a1a3a1bde414d2a")
    s!"1||2>>3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorShr.sourceHash}"
  expect (twinLorShr.canonicalBytes.size == 235)
    s!"1||2>>3 LogicalOrTwin size golden must remain stable; got {twinLorShr.canonicalBytes.size}"
  expect (twinLorEq.sourceHash ==
      "41ed43de76f6b039f2c13f1176cfef3c07fcbe92173a110bb309b0ebbf38aae1")
    s!"1||2==3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorEq.sourceHash}"
  expect (twinLorEq.canonicalBytes.size == 235)
    s!"1||2==3 LogicalOrTwin size golden must remain stable; got {twinLorEq.canonicalBytes.size}"
  expect (twinEqLor.sourceHash ==
      "f57275f76bff94db6bd725f46892c9a7f89f7ec8300d1e8f56a68b0fa7acdbac")
    s!"1==2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinEqLor.sourceHash}"
  expect (twinEqLor.canonicalBytes.size == 235)
    s!"1==2||3 LogicalOrTwin size golden must remain stable; got {twinEqLor.canonicalBytes.size}"
  expect (twinAndLor.sourceHash ==
      "e22365223d33e65519408937482b84629c486dbbdbb0f5f5b8565b74c8ee22ee")
    s!"1&2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinAndLor.sourceHash}"
  expect (twinAndLor.canonicalBytes.size == 235)
    s!"1&2||3 LogicalOrTwin size golden must remain stable; got {twinAndLor.canonicalBytes.size}"
  expect (twinLorAnd.sourceHash ==
      "fefa4bf21239d889dc5b73c00743ba2bd167434c0f03966c954df4a7fd96c359")
    s!"1||2&3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorAnd.sourceHash}"
  expect (twinLorAnd.canonicalBytes.size == 235)
    s!"1||2&3 LogicalOrTwin size golden must remain stable; got {twinLorAnd.canonicalBytes.size}"
  expect (twinXorLor.sourceHash ==
      "77fe3f28239dbc24f921e784f6ff2a031e2eecc9846e230b3ec6c0ff0069e4ab")
    s!"1^2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinXorLor.sourceHash}"
  expect (twinXorLor.canonicalBytes.size == 235)
    s!"1^2||3 LogicalOrTwin size golden must remain stable; got {twinXorLor.canonicalBytes.size}"
  expect (twinLorXor.sourceHash ==
      "aaf4a46714852c6506ab9fc3c605c6f75fbd0f2de7c1225e8d51471b7700033e")
    s!"1||2^3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorXor.sourceHash}"
  expect (twinLorXor.canonicalBytes.size == 235)
    s!"1||2^3 LogicalOrTwin size golden must remain stable; got {twinLorXor.canonicalBytes.size}"
  expect (twinOrLor.sourceHash ==
      "762ad77d757fc44481da7ab370668486ff4bf144172007a6ef8399406374dee3")
    s!"1|2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinOrLor.sourceHash}"
  expect (twinOrLor.canonicalBytes.size == 235)
    s!"1|2||3 LogicalOrTwin size golden must remain stable; got {twinOrLor.canonicalBytes.size}"
  expect (twinLorOr.sourceHash ==
      "d32ac4ebea8900920f516b177a9e0e9b015329d13ffd9247e7418d4f4f92a808")
    s!"1||2|3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorOr.sourceHash}"
  expect (twinLorOr.canonicalBytes.size == 235)
    s!"1||2|3 LogicalOrTwin size golden must remain stable; got {twinLorOr.canonicalBytes.size}"
  expect (twinLandLor.sourceHash ==
      "2c7f3000dacc59c3b2ebcdad7c248f376b020a19bd762f182adf6d687f161ff8")
    s!"1&&2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinLandLor.sourceHash}"
  expect (twinLandLor.canonicalBytes.size == 235)
    s!"1&&2||3 LogicalOrTwin size golden must remain stable; got {twinLandLor.canonicalBytes.size}"
  expect (twinLorLand.sourceHash ==
      "8035479203ad61e88f17bf09fba058a3d82084bc448ec24bb53329f4ea54ada4")
    s!"1||2&&3 LogicalOrTwin sourceHash golden must remain stable; got {twinLorLand.sourceHash}"
  expect (twinLorLand.canonicalBytes.size == 235)
    s!"1||2&&3 LogicalOrTwin size golden must remain stable; got {twinLorLand.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "137ad8122e776ceee9cd55c0ecda106f6c2264a83fdc2914740e569d32b67fb7")
    s!"left 1||2||3 LogicalOrTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 235)
    s!"left 1||2||3 LogicalOrTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "151b82c032acf39a9d3f02988b4cc25b4a28c47166fb288b19db8d334c3ee6fb")
    s!"right 1||(2||3) LogicalOrTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 235)
    s!"right 1||(2||3) LogicalOrTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegLor.sourceHash ==
      "741de850652c77bae52bda59c0ee9268ed3b048dea3c153b75f078432213f52f")
    s!"-1||2 LogicalOrTwin sourceHash golden must remain stable; got {twinNegLor.sourceHash}"
  expect (twinNegLor.canonicalBytes.size == 226)
    s!"-1||2 LogicalOrTwin size golden must remain stable; got {twinNegLor.canonicalBytes.size}"
  expect (twinLorNeg.sourceHash ==
      "6a7f09740a6753bb3c5b719ac09405d9d0d0b35f928fbe8b34b1318289362e40")
    s!"1||-2 LogicalOrTwin sourceHash golden must remain stable; got {twinLorNeg.sourceHash}"
  expect (twinLorNeg.canonicalBytes.size == 226)
    s!"1||-2 LogicalOrTwin size golden must remain stable; got {twinLorNeg.canonicalBytes.size}"
  expect (twinLandCtrl.sourceHash ==
      "0d5f65aae8ce105d5979373e3349f2d6c479bf55175631cc8b8733dfd839be3c")
    s!"logicalAnd 1&&2 control LogicalOrTwin sourceHash golden must remain stable; got {twinLandCtrl.sourceHash}"
  expect (twinLandCtrl.canonicalBytes.size == 225)
    s!"logicalAnd 1&&2 control LogicalOrTwin size golden must remain stable; got {twinLandCtrl.canonicalBytes.size}"
  expect (twinOrCtrl.sourceHash ==
      "95be5664e68834e48382ce70920f674073bb0a9219e91a7724f5acbc20e6a5fb")
    s!"bitwiseOr 1|2 control LogicalOrTwin sourceHash golden must remain stable; got {twinOrCtrl.sourceHash}"
  expect (twinOrCtrl.canonicalBytes.size == 225)
    s!"bitwiseOr 1|2 control LogicalOrTwin size golden must remain stable; got {twinOrCtrl.canonicalBytes.size}"
  expect (twinXorCtrl.sourceHash ==
      "90056c66be32ea73fd683e33f1ea5a3f15116c7789afd55fc6907eb7ee60f98b")
    s!"bitwiseXor 1^2 control LogicalOrTwin sourceHash golden must remain stable; got {twinXorCtrl.sourceHash}"
  expect (twinXorCtrl.canonicalBytes.size == 225)
    s!"bitwiseXor 1^2 control LogicalOrTwin size golden must remain stable; got {twinXorCtrl.canonicalBytes.size}"
  expect (twinAndCtrl.sourceHash ==
      "f8d6ae687d2b11824d7d578722119d12286451bd280a50c04e279180e378ca84")
    s!"bitwiseAnd 1&2 control LogicalOrTwin sourceHash golden must remain stable; got {twinAndCtrl.sourceHash}"
  expect (twinAndCtrl.canonicalBytes.size == 225)
    s!"bitwiseAnd 1&2 control LogicalOrTwin size golden must remain stable; got {twinAndCtrl.canonicalBytes.size}"
  expect (twinEq.sourceHash ==
      "3577dded407d303dc1c55ab02bc96ac096a6e23e1dfb12ff66a7835b520f35e4")
    s!"equal 1==2 control LogicalOrTwin sourceHash golden must remain stable; got {twinEq.sourceHash}"
  expect (twinEq.canonicalBytes.size == 225)
    s!"equal 1==2 control LogicalOrTwin size golden must remain stable; got {twinEq.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "6c0aaf070dbc3d03425050c068c1eede14043dd4acdc928de9b10d7b49ea389e")
    s!"checkedAdd 1+2 control LogicalOrTwin sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 225)
    s!"checkedAdd 1+2 control LogicalOrTwin size golden must remain stable; got {twinAdd.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "logicalOr 1||2 must not alias 2||1 (operand order)"
  expect (twin12.sourceHash != twinLandCtrl.sourceHash)
    "logicalOr 1||2 must not alias logicalAnd 1&&2 (operator tag)"
  expect (twin12.sourceHash != twinOrCtrl.sourceHash)
    "logicalOr 1||2 must not alias bitwiseOr 1|2 (operator tag)"
  expect (twin12.sourceHash != twinXorCtrl.sourceHash)
    "logicalOr 1||2 must not alias bitwiseXor 1^2 (operator tag)"
  expect (twin12.sourceHash != twinAndCtrl.sourceHash)
    "logicalOr 1||2 must not alias bitwiseAnd 1&2 (operator tag)"
  expect (twin12.sourceHash != twinEq.sourceHash)
    "logicalOr 1||2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "logicalOr 1||2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinLandCtrl.canonicalBytes.size)
    "logicalOr and logicalAnd of two small literals must share size (tag-only distinction)"
  expect (twinAddLor.sourceHash != twinWrong.sourceHash)
    "1+2||3 must not alias wrong C-style 1+(2||3)"
  expect (twinAddLor.sourceHash != twinLorAdd.sourceHash)
    "1+2||3 must not alias 1||2+3"
  expect (twinMulLor.sourceHash != twinLorMul.sourceHash)
    "1*2||3 must not alias 1||2*3"
  expect (twinShlLor.sourceHash != twinLorShl.sourceHash)
    "1<<2||3 must not alias 1||2<<3"
  expect (twinShrLor.sourceHash != twinLorShr.sourceHash)
    "1>>2||3 must not alias 1||2>>3"
  expect (twinLorEq.sourceHash != twinEqLor.sourceHash)
    "1||2==3 must not alias 1==2||3"
  expect (twinAndLor.sourceHash != twinLorAnd.sourceHash)
    "1&2||3 must not alias 1||2&3"
  expect (twinXorLor.sourceHash != twinLorXor.sourceHash)
    "1^2||3 must not alias 1||2^3"
  expect (twinOrLor.sourceHash != twinLorOr.sourceHash)
    "1|2||3 must not alias 1||2|3"
  expect (twinLandLor.sourceHash != twinLorLand.sourceHash)
    "1&&2||3 must not alias 1||2&&3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested logicalOr must not alias"
  expect (twinNegLor.sourceHash != twinLorNeg.sourceHash)
    "-1||2 must not alias 1||-2"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true||false must not alias false||true"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0||0 must not alias 1||2"

  -- Parser-boundary: malformed digraph shapes (BitwiseOr retains spaced 1 | | 2).
  for (label, expr) in [
      ("bare lor", "||"),
      ("missing lhs", "|| 2"),
      ("missing rhs", "1 ||"),
      ("spaced split", "1 || || 2"),
      ("triple pipe", "1 ||| 2"),
      ("mixed pipe", "1 | || 2"),
      ("extra token", "1 || 2 3")
    ] do
    let source := returnProgramSource "RejectedLorShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<lor-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.logicalOr (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "logical or is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject logicalOr with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing logicalOr"

  match Compiler.compile
      (twin (.logicalOr (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "logical or is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true||false with logical-or message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true||false programs"

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

  match Compiler.compile (twin (.logicalAnd (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "logical and is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"logicalAnd must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "logicalAnd twin must remain Typed fail-closed"

end Tests.Language.LogicalOr
