import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- BitwiseXorSurface pins binary `^` in every declaration body position: init, entry,
-- view, and fn. Zero migration: no existing ^ negatives in the suite.
namespace Tests.Language.BitwiseXorFixture

open ProofForgeV2.Language

program BitwiseXorSurface where
  init() do
    let seed : UInt64 := 1 ^ 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a ^ b

  view peek() : UInt64 do
    let value := 1 + 2 ^ 3
    return value

  fn helper() : UInt64 do
    return 1 ^ 2 ^ 3

end Tests.Language.BitwiseXorFixture

namespace Tests.Language.BitwiseXor

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.BitwiseXorFixture.BitwiseXorTwin" "BitwiseXorTwin" #[
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
  "namespace Tests.Language.BitwiseXorFixture\n\n" ++
  "program BitwiseXorSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 ^ 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a ^ b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 ^ 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 ^ 2 ^ 3\n\n" ++
  "end Tests.Language.BitwiseXorFixture\n"

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
  let elaborated := Tests.Language.BitwiseXorFixture.BitwiseXorSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.bitwiseXor (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 ^ 2"
  | none => throw <| IO.userError "BitwiseXorSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.bitwiseXor (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a ^ b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.bitwiseXor (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 ^ 3 as (1+2)^3"
  | _ => throw <| IO.userError "BitwiseXorSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.bitwiseXor (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 ^ 2 ^ 3"
  | _ => throw <| IO.userError "BitwiseXorSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<bitwise-xor>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same bitwiseXor Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same bitwiseXor sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins (precedence 40 left-assoc, looser than BitAnd 45).
  let xor12 ← select session (returnProgramSource "Xor12" "1 ^ 2") "<xor-1-2>"
  expectReturnExpr "1 ^ 2" xor12 (.bitwiseXor (.literal 1) (.literal 2))

  let xor21 ← select session (returnProgramSource "Xor21" "2 ^ 1") "<xor-2-1>"
  expectReturnExpr "2 ^ 1" xor21 (.bitwiseXor (.literal 2) (.literal 1))

  let xorAB ← select session (varReturnProgramSource "XorAB" "a ^ b") "<xor-a-b>"
  expectReturnExpr "a ^ b" xorAB (.bitwiseXor (.variable "a") (.variable "b"))

  let xor00 ← select session (returnProgramSource "Xor00" "0 ^ 0") "<xor-0-0>"
  expectReturnExpr "0 ^ 0" xor00 (.bitwiseXor (.literal 0) (.literal 0))

  let xorTF ← select session (returnProgramSource "XorTF" "true ^ false") "<xor-t-f>"
  expectReturnExpr "true ^ false" xorTF
    (.bitwiseXor (.boolLiteral true) (.boolLiteral false))

  let xorFT ← select session (returnProgramSource "XorFT" "false ^ true") "<xor-f-t>"
  expectReturnExpr "false ^ true" xorFT
    (.bitwiseXor (.boolLiteral false) (.boolLiteral true))

  let addXor ← select session (returnProgramSource "AddXor" "1 + 2 ^ 3") "<add-xor>"
  expectReturnExpr "1 + 2 ^ 3" addXor
    (.bitwiseXor (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let xorAdd ← select session (returnProgramSource "XorAdd" "1 ^ 2 + 3") "<xor-add>"
  expectReturnExpr "1 ^ 2 + 3" xorAdd
    (.bitwiseXor (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulXor ← select session (returnProgramSource "MulXor" "1 * 2 ^ 3") "<mul-xor>"
  expectReturnExpr "1 * 2 ^ 3" mulXor
    (.bitwiseXor (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let xorMul ← select session (returnProgramSource "XorMul" "1 ^ 2 * 3") "<xor-mul>"
  expectReturnExpr "1 ^ 2 * 3" xorMul
    (.bitwiseXor (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlXor ← select session (returnProgramSource "ShlXor" "1 << 2 ^ 3") "<shl-xor>"
  expectReturnExpr "1 << 2 ^ 3" shlXor
    (.bitwiseXor (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let xorShl ← select session (returnProgramSource "XorShl" "1 ^ 2 << 3") "<xor-shl>"
  expectReturnExpr "1 ^ 2 << 3" xorShl
    (.bitwiseXor (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrXor ← select session (returnProgramSource "ShrXor" "1 >> 2 ^ 3") "<shr-xor>"
  expectReturnExpr "1 >> 2 ^ 3" shrXor
    (.bitwiseXor (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let xorShr ← select session (returnProgramSource "XorShr" "1 ^ 2 >> 3") "<xor-shr>"
  expectReturnExpr "1 ^ 2 >> 3" xorShr
    (.bitwiseXor (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let xorEq ← select session (returnProgramSource "XorEq" "1 ^ 2 == 3") "<xor-eq>"
  expectReturnExpr "1 ^ 2 == 3" xorEq
    (.bitwiseXor (.literal 1) (.equal (.literal 2) (.literal 3)))

  let eqXor ← select session (returnProgramSource "EqXor" "1 == 2 ^ 3") "<eq-xor>"
  expectReturnExpr "1 == 2 ^ 3" eqXor
    (.bitwiseXor (.equal (.literal 1) (.literal 2)) (.literal 3))

  let andXor ← select session (returnProgramSource "AndXor" "1 & 2 ^ 3") "<and-xor>"
  expectReturnExpr "1 & 2 ^ 3" andXor
    (.bitwiseXor (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))

  let xorAnd ← select session (returnProgramSource "XorAnd" "1 ^ 2 & 3") "<xor-and>"
  expectReturnExpr "1 ^ 2 & 3" xorAnd
    (.bitwiseXor (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 ^ 2 ^ 3") "<xor-left>"
  expectReturnExpr "1 ^ 2 ^ 3" leftChain
    (.bitwiseXor (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 ^ (2 ^ 3)") "<xor-right>"
  expectReturnExpr "1 ^ (2 ^ 3)" rightNest
    (.bitwiseXor (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))

  let groupXor ← select session
    (returnProgramSource "GroupXor" "(1 + 2) ^ 3") "<group-xor>"
  expectReturnExpr "(1 + 2) ^ 3" groupXor
    (.bitwiseXor (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negXor ← select session (returnProgramSource "NegXor" "-1 ^ 2") "<neg-xor>"
  expectReturnExpr "-1 ^ 2" negXor
    (.bitwiseXor (.checkedNeg (.literal 1)) (.literal 2))

  let xorNeg ← select session (returnProgramSource "XorNeg" "1 ^ -2") "<xor-neg>"
  expectReturnExpr "1 ^ -2" xorNeg
    (.bitwiseXor (.literal 1) (.checkedNeg (.literal 2)))

  -- Same-identity desugar.
  let bareXor ← select session (returnProgramSource "XorSame" "1 ^ 2") "<xor-same-bare>"
  let groupSame ← select session
    (returnProgramSource "XorSame" "(1 ^ 2)") "<xor-same-group>"
  expect (bareXor == groupSame)
    "1 ^ 2 and (1 ^ 2) must share Source.Program under identical identity"
  expect (bareXor.canonicalBytes == groupSame.canonicalBytes)
    "1 ^ 2 and (1 ^ 2) must share canonical bytes under identical identity"
  expect (bareXor.sourceHash == groupSame.sourceHash)
    "1 ^ 2 and (1 ^ 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for BitwiseXorTwin (Expr tag 21 + lhs/rhs).
  let twin12 := twin (.bitwiseXor (.literal 1) (.literal 2))
  let twin21 := twin (.bitwiseXor (.literal 2) (.literal 1))
  let twinAB := twin (.bitwiseXor (.variable "a") (.variable "b"))
  let twin00 := twin (.bitwiseXor (.literal 0) (.literal 0))
  let twinTF := twin (.bitwiseXor (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.bitwiseXor (.boolLiteral false) (.boolLiteral true))
  let twinAddXor := twin
    (.bitwiseXor (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinXorAdd := twin
    (.bitwiseXor (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))
  let twinMulXor := twin
    (.bitwiseXor (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinXorMul := twin
    (.bitwiseXor (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlXor := twin
    (.bitwiseXor (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinXorShl := twin
    (.bitwiseXor (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrXor := twin
    (.bitwiseXor (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinXorShr := twin
    (.bitwiseXor (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinXorEq := twin
    (.bitwiseXor (.literal 1) (.equal (.literal 2) (.literal 3)))
  let twinEqXor := twin
    (.bitwiseXor (.equal (.literal 1) (.literal 2)) (.literal 3))
  let twinAndXor := twin
    (.bitwiseXor (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinXorAnd := twin
    (.bitwiseXor (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))
  let twinLeft := twin
    (.bitwiseXor (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.bitwiseXor (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))
  let twinNegXor := twin
    (.bitwiseXor (.checkedNeg (.literal 1)) (.literal 2))
  let twinXorNeg := twin
    (.bitwiseXor (.literal 1) (.checkedNeg (.literal 2)))
  let twinAndCtrl := twin (.bitwiseAnd (.literal 1) (.literal 2))
  let twinEq := twin (.equal (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "d29a60c5f4ec26c1762023a2ca0edcbe168ac331533304d6d8780ccd8da67fe3")
    s!"bitwiseXor 1^2 BitwiseXorTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 228)
    s!"bitwiseXor 1^2 BitwiseXorTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "5e05fbbf55247f3585360d9759539cb75fdb0317e3d32407b7db4e7e2c9476cc")
    s!"bitwiseXor 2^1 BitwiseXorTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 228)
    s!"bitwiseXor 2^1 BitwiseXorTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "e64212a303b6b71dc209ed68e74f3464e0d7c4e131382c13e3245605ba9ccc73")
    s!"a^b BitwiseXorTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 230)
    s!"a^b BitwiseXorTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "e256d4ce891ab7b4da0281c84f068e545fa4c3308ab1b27bfd19652631551a16")
    s!"0^0 BitwiseXorTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 228)
    s!"0^0 BitwiseXorTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "1f0e7f0c3572b21a6aa0e5a71cbeb907dda87582141c5887ad5c38143bee67ad")
    s!"true^false BitwiseXorTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 214)
    s!"true^false BitwiseXorTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "a1da0eda4e1a15312aec14bfe8b3235f0881accbcedd0226bbe144d1a5ca640e")
    s!"false^true BitwiseXorTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 214)
    s!"false^true BitwiseXorTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddXor.sourceHash ==
      "fb45a7c499e1753b793ea4df7250f8b5abfc902d93f64864de8e4cc3c9aff553")
    s!"1+2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinAddXor.sourceHash}"
  expect (twinAddXor.canonicalBytes.size == 238)
    s!"1+2^3 BitwiseXorTwin size golden must remain stable; got {twinAddXor.canonicalBytes.size}"
  expect (twinXorAdd.sourceHash ==
      "579246d64fddb47c6e863f48cac7ab90cc49bda5d3eb6e05a55b68905bcd6ea8")
    s!"1^2+3 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorAdd.sourceHash}"
  expect (twinXorAdd.canonicalBytes.size == 238)
    s!"1^2+3 BitwiseXorTwin size golden must remain stable; got {twinXorAdd.canonicalBytes.size}"
  expect (twinMulXor.sourceHash ==
      "3bd2272873c5bc215d8af4db092981105bdcf9c2e69af5774549f98a235a58fc")
    s!"1*2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinMulXor.sourceHash}"
  expect (twinMulXor.canonicalBytes.size == 238)
    s!"1*2^3 BitwiseXorTwin size golden must remain stable; got {twinMulXor.canonicalBytes.size}"
  expect (twinXorMul.sourceHash ==
      "848ebdb3986a029d2a9b64c77f24a5d6aad3183a5472366ccb1bb301bcc62aa7")
    s!"1^2*3 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorMul.sourceHash}"
  expect (twinXorMul.canonicalBytes.size == 238)
    s!"1^2*3 BitwiseXorTwin size golden must remain stable; got {twinXorMul.canonicalBytes.size}"
  expect (twinShlXor.sourceHash ==
      "3bd872035dbb8ec1dca3226a31579805f7b0c5d0cc22bfa36ad315ccb6af3a3b")
    s!"1<<2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinShlXor.sourceHash}"
  expect (twinShlXor.canonicalBytes.size == 238)
    s!"1<<2^3 BitwiseXorTwin size golden must remain stable; got {twinShlXor.canonicalBytes.size}"
  expect (twinXorShl.sourceHash ==
      "0042aff8931d59a201551da0487d52c45f082157cc8183a0d5b503a7ae887200")
    s!"1^2<<3 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorShl.sourceHash}"
  expect (twinXorShl.canonicalBytes.size == 238)
    s!"1^2<<3 BitwiseXorTwin size golden must remain stable; got {twinXorShl.canonicalBytes.size}"
  expect (twinShrXor.sourceHash ==
      "068047f922eaff50b1a74ecb117b53546395eaf7f2614638dceaf7fc292bf188")
    s!"1>>2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinShrXor.sourceHash}"
  expect (twinShrXor.canonicalBytes.size == 238)
    s!"1>>2^3 BitwiseXorTwin size golden must remain stable; got {twinShrXor.canonicalBytes.size}"
  expect (twinXorShr.sourceHash ==
      "99fb1633337e1f3af086512025012daaf0595ec5c4af184b7bef983408373e0d")
    s!"1^2>>3 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorShr.sourceHash}"
  expect (twinXorShr.canonicalBytes.size == 238)
    s!"1^2>>3 BitwiseXorTwin size golden must remain stable; got {twinXorShr.canonicalBytes.size}"
  expect (twinXorEq.sourceHash ==
      "fa9ae34ecac7eb7581e8e7ca8db270fb5ef4ed5fbf10eb73ff580ea5bd0bb4bd")
    s!"1^2==3 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorEq.sourceHash}"
  expect (twinXorEq.canonicalBytes.size == 238)
    s!"1^2==3 BitwiseXorTwin size golden must remain stable; got {twinXorEq.canonicalBytes.size}"
  expect (twinEqXor.sourceHash ==
      "dd0d636ccb3d3f6d3a9fbceb5b21b160d9b5ac137cf0ad59524998ea57fb306b")
    s!"1==2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinEqXor.sourceHash}"
  expect (twinEqXor.canonicalBytes.size == 238)
    s!"1==2^3 BitwiseXorTwin size golden must remain stable; got {twinEqXor.canonicalBytes.size}"
  expect (twinAndXor.sourceHash ==
      "8f1601e1e52a447c295784f61dbac1d75ad62e6926adf310b202109ca25a5056")
    s!"1&2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinAndXor.sourceHash}"
  expect (twinAndXor.canonicalBytes.size == 238)
    s!"1&2^3 BitwiseXorTwin size golden must remain stable; got {twinAndXor.canonicalBytes.size}"
  expect (twinXorAnd.sourceHash ==
      "5ef0adb375daae990ea490535a66eb5dc716246de6ef3204cca8909131aa708d")
    s!"1^2&3 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorAnd.sourceHash}"
  expect (twinXorAnd.canonicalBytes.size == 238)
    s!"1^2&3 BitwiseXorTwin size golden must remain stable; got {twinXorAnd.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "3e2d516147ccf7503de9baa04960edc657aaacbf6ea27398bcde258ec4f9779a")
    s!"left 1^2^3 BitwiseXorTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 238)
    s!"left 1^2^3 BitwiseXorTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "16a7168f37deb94c2b6e25866cf45bd27d2049c42035b0e8087d39571976b64f")
    s!"right 1^(2^3) BitwiseXorTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 238)
    s!"right 1^(2^3) BitwiseXorTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegXor.sourceHash ==
      "a6a8fa6894b22eb8583e31c613e46d5c1061586a8891f32eab8adbdc59d13ada")
    s!"-1^2 BitwiseXorTwin sourceHash golden must remain stable; got {twinNegXor.sourceHash}"
  expect (twinNegXor.canonicalBytes.size == 229)
    s!"-1^2 BitwiseXorTwin size golden must remain stable; got {twinNegXor.canonicalBytes.size}"
  expect (twinXorNeg.sourceHash ==
      "13f5962e8396bac630c1bf1ef93c1938e7b19d5461e377e55efb5cc97ef7717f")
    s!"1^-2 BitwiseXorTwin sourceHash golden must remain stable; got {twinXorNeg.sourceHash}"
  expect (twinXorNeg.canonicalBytes.size == 229)
    s!"1^-2 BitwiseXorTwin size golden must remain stable; got {twinXorNeg.canonicalBytes.size}"
  expect (twinAndCtrl.sourceHash ==
      "008df6e4482fe15abdb4d5d2eb898a34869ac3a3452dc05c973d6c42226c57d1")
    s!"bitwiseAnd 1&2 control sourceHash golden must remain stable; got {twinAndCtrl.sourceHash}"
  expect (twinAndCtrl.canonicalBytes.size == 228)
    s!"bitwiseAnd 1&2 control size golden must remain stable; got {twinAndCtrl.canonicalBytes.size}"
  expect (twinEq.sourceHash ==
      "8622ad7b50d35dab4afe8d52441110f539e05e154ec626c762adbaf1370f3148")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEq.sourceHash}"
  expect (twinEq.canonicalBytes.size == 228)
    s!"equal 1==2 control size golden must remain stable; got {twinEq.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "1410da99303c5644e7e70ca29dfb13ed97402f947dc488dfdefa894d997d5d9d")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 228)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "bitwiseXor 1^2 must not alias 2^1 (operand order)"
  expect (twin12.sourceHash != twinAndCtrl.sourceHash)
    "bitwiseXor 1^2 must not alias bitwiseAnd 1&2 (operator tag)"
  expect (twin12.sourceHash != twinEq.sourceHash)
    "bitwiseXor 1^2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "bitwiseXor 1^2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinAndCtrl.canonicalBytes.size)
    "bitwiseXor and bitwiseAnd of two small literals must share size (tag-only distinction)"
  expect (twinAddXor.sourceHash != twinWrong.sourceHash)
    "1+2^3 must not alias wrong C-style 1+(2^3)"
  expect (twinAddXor.sourceHash != twinXorAdd.sourceHash)
    "1+2^3 must not alias 1^2+3"
  expect (twinMulXor.sourceHash != twinXorMul.sourceHash)
    "1*2^3 must not alias 1^2*3"
  expect (twinShlXor.sourceHash != twinXorShl.sourceHash)
    "1<<2^3 must not alias 1^2<<3"
  expect (twinShrXor.sourceHash != twinXorShr.sourceHash)
    "1>>2^3 must not alias 1^2>>3"
  expect (twinXorEq.sourceHash != twinEqXor.sourceHash)
    "1^2==3 must not alias 1==2^3"
  expect (twinAndXor.sourceHash != twinXorAnd.sourceHash)
    "1&2^3 must not alias 1^2&3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested bitwiseXor must not alias"
  expect (twinNegXor.sourceHash != twinXorNeg.sourceHash)
    "-1^2 must not alias 1^-2"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true^false must not alias false^true"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0^0 must not alias 1^2"

  -- Parser-boundary: malformed and deferred BitOr.
  for (label, expr) in [
      ("bare xor", "^"),
      ("missing lhs", "^ 2"),
      ("missing rhs", "1 ^"),
      ("spaced split", "1 ^ ^ 2"),
      ("double caret", "1 ^^ 2"),
      ("extra token", "1 ^ 2 3")
    ] do
    let source := returnProgramSource "RejectedXorShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<xor-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.bitwiseXor (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "bitwise xor is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject bitwiseXor with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing bitwiseXor"

  match Compiler.compile
      (twin (.bitwiseXor (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "bitwise xor is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true^false with bitwise-xor message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true^false programs"

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

end Tests.Language.BitwiseXor
