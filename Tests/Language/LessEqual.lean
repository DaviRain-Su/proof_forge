import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- LessEqualSurface pins binary `<=` in every declaration body position: init, entry,
-- view, and fn. Migration: exactly Equal.lean deferred `1 <= 2` only.
namespace Tests.Language.LessEqualFixture

open ProofForgeV2.Language

program LessEqualSurface where
  init() do
    let seed : UInt64 := 1 <= 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a <= b

  view peek() : UInt64 do
    let value := 1 + 2 <= 3
    return value

  fn helper() : UInt64 do
    return true <= false

end Tests.Language.LessEqualFixture

namespace Tests.Language.LessEqual

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LessEqualFixture.LessEqualTwin" "LessEqualTwin" #[
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
  "namespace Tests.Language.LessEqualFixture\n\n" ++
  "program LessEqualSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 <= 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a <= b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 <= 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true <= false\n\n" ++
  "end Tests.Language.LessEqualFixture\n"

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
  let elaborated := Tests.Language.LessEqualFixture.LessEqualSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.lessEqual (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 <= 2"
  | none => throw <| IO.userError "LessEqualSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.lessEqual (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a <= b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.lessEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 <= 3 as (1+2)<=3"
  | _ => throw <| IO.userError "LessEqualSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.lessEqual (.boolLiteral true) (.boolLiteral false))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return true <= false"
  | _ => throw <| IO.userError "LessEqualSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<less-equal>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same lessEqual Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same lessEqual sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 50 non-assoc, both operand slots 51).
  let le12 ← select session (returnProgramSource "Le12" "1 <= 2") "<le-1-2>"
  expectReturnExpr "1 <= 2" le12 (.lessEqual (.literal 1) (.literal 2))

  let le21 ← select session (returnProgramSource "Le21" "2 <= 1") "<le-2-1>"
  expectReturnExpr "2 <= 1" le21 (.lessEqual (.literal 2) (.literal 1))

  let leAB ← select session (varReturnProgramSource "LeAB" "a <= b") "<le-a-b>"
  expectReturnExpr "a <= b" leAB (.lessEqual (.variable "a") (.variable "b"))

  let le00 ← select session (returnProgramSource "Le00" "0 <= 0") "<le-0-0>"
  expectReturnExpr "0 <= 0" le00 (.lessEqual (.literal 0) (.literal 0))

  let leTF ← select session (returnProgramSource "LeTF" "true <= false") "<le-t-f>"
  expectReturnExpr "true <= false" leTF
    (.lessEqual (.boolLiteral true) (.boolLiteral false))

  let leFT ← select session (returnProgramSource "LeFT" "false <= true") "<le-f-t>"
  expectReturnExpr "false <= true" leFT
    (.lessEqual (.boolLiteral false) (.boolLiteral true))

  let addLe ← select session (returnProgramSource "AddLe" "1 + 2 <= 3") "<add-le>"
  expectReturnExpr "1 + 2 <= 3" addLe
    (.lessEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let leAdd ← select session (returnProgramSource "LeAdd" "1 <= 2 + 3") "<le-add>"
  expectReturnExpr "1 <= 2 + 3" leAdd
    (.lessEqual (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulLe ← select session (returnProgramSource "MulLe" "1 * 2 <= 3") "<mul-le>"
  expectReturnExpr "1 * 2 <= 3" mulLe
    (.lessEqual (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let leMul ← select session (returnProgramSource "LeMul" "1 <= 2 * 3") "<le-mul>"
  expectReturnExpr "1 <= 2 * 3" leMul
    (.lessEqual (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlLe ← select session (returnProgramSource "ShlLe" "1 << 2 <= 3") "<shl-le>"
  expectReturnExpr "1 << 2 <= 3" shlLe
    (.lessEqual (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let leShl ← select session (returnProgramSource "LeShl" "1 <= 2 << 3") "<le-shl>"
  expectReturnExpr "1 <= 2 << 3" leShl
    (.lessEqual (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrLe ← select session (returnProgramSource "ShrLe" "1 >> 2 <= 3") "<shr-le>"
  expectReturnExpr "1 >> 2 <= 3" shrLe
    (.lessEqual (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let leShr ← select session (returnProgramSource "LeShr" "1 <= 2 >> 3") "<le-shr>"
  expectReturnExpr "1 <= 2 >> 3" leShr
    (.lessEqual (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let groupLe ← select session
    (returnProgramSource "GroupLe" "(1 + 2) <= 3") "<group-le>"
  expectReturnExpr "(1 + 2) <= 3" groupLe
    (.lessEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negLe ← select session (returnProgramSource "NegLe" "-1 <= 2") "<neg-le>"
  expectReturnExpr "-1 <= 2" negLe
    (.lessEqual (.checkedNeg (.literal 1)) (.literal 2))

  let leNeg ← select session (returnProgramSource "LeNeg" "1 <= -2") "<le-neg>"
  expectReturnExpr "1 <= -2" leNeg
    (.lessEqual (.literal 1) (.checkedNeg (.literal 2)))

  -- Token coexistence: 1 < 2 remains lessThan; 1 << 2 remains shiftLeft.
  let stillLt ← select session (returnProgramSource "StillLt" "1 < 2") "<still-lt>"
  expectReturnExpr "1 < 2" stillLt (.lessThan (.literal 1) (.literal 2))

  let stillShl ← select session (returnProgramSource "StillShl" "1 << 2") "<still-shl>"
  expectReturnExpr "1 << 2" stillShl (.shiftLeft (.literal 1) (.literal 2))

  -- Same-identity desugar.
  let bareLe ← select session (returnProgramSource "LeSame" "1 <= 2") "<le-same-bare>"
  let groupSame ← select session
    (returnProgramSource "LeSame" "(1 <= 2)") "<le-same-group>"
  expect (bareLe == groupSame)
    "1 <= 2 and (1 <= 2) must share Source.Program under identical identity"
  expect (bareLe.canonicalBytes == groupSame.canonicalBytes)
    "1 <= 2 and (1 <= 2) must share canonical bytes under identical identity"
  expect (bareLe.sourceHash == groupSame.sourceHash)
    "1 <= 2 and (1 <= 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for LessEqualTwin (Expr tag 17 + lhs/rhs).
  let twin12 := twin (.lessEqual (.literal 1) (.literal 2))
  let twin21 := twin (.lessEqual (.literal 2) (.literal 1))
  let twinAB := twin (.lessEqual (.variable "a") (.variable "b"))
  let twin00 := twin (.lessEqual (.literal 0) (.literal 0))
  let twinTF := twin (.lessEqual (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.lessEqual (.boolLiteral false) (.boolLiteral true))
  let twinAddLe := twin
    (.lessEqual (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinLeAdd := twin
    (.lessEqual (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.lessEqual (.literal 2) (.literal 3)))
  let twinMulLe := twin
    (.lessEqual (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinLeMul := twin
    (.lessEqual (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlLe := twin
    (.lessEqual (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinLeShl := twin
    (.lessEqual (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrLe := twin
    (.lessEqual (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinLeShr := twin
    (.lessEqual (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinNegLe := twin
    (.lessEqual (.checkedNeg (.literal 1)) (.literal 2))
  let twinLeNeg := twin
    (.lessEqual (.literal 1) (.checkedNeg (.literal 2)))
  let twinLtCtrl := twin (.lessThan (.literal 1) (.literal 2))
  let twinEqCtrl := twin (.equal (.literal 1) (.literal 2))
  let twinNeCtrl := twin (.notEqual (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinShl := twin (.shiftLeft (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "dae46b177e848a37c45a1b83756828d709aced2f30ba6797084b36fa9af9c7ac")
    s!"lessEqual 1<=2 LessEqualTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 225)
    s!"lessEqual 1<=2 LessEqualTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "0b1ee5b31681f8c1eaa77386df60c1bb65c2285eeb63dad10a86b2538e60328f")
    s!"lessEqual 2<=1 LessEqualTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 225)
    s!"lessEqual 2<=1 LessEqualTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "55f1c8a8b93372c4f0cf20765cb0e7856cec6d518bc332e4147a846029f11461")
    s!"a<=b LessEqualTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 227)
    s!"a<=b LessEqualTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "3e2ab91b265582ca07f07f8de88e11f3ac06214c914baf4e2b9297907462d6c9")
    s!"0<=0 LessEqualTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 225)
    s!"0<=0 LessEqualTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "b99e171a3079f2497d1502c1d422dd761f86eadce84ce0280110ee22126dc7b6")
    s!"true<=false LessEqualTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 211)
    s!"true<=false LessEqualTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "4cb77dd476bd2a91a307c3cd62381f44e1cb919a845f177d9f7a74b0abba8264")
    s!"false<=true LessEqualTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 211)
    s!"false<=true LessEqualTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddLe.sourceHash ==
      "bc55b18f29500659734c183ec5c988430cbb5bdd01cc7f44d97d579ec0377368")
    s!"1+2<=3 LessEqualTwin sourceHash golden must remain stable; got {twinAddLe.sourceHash}"
  expect (twinAddLe.canonicalBytes.size == 235)
    s!"1+2<=3 LessEqualTwin size golden must remain stable; got {twinAddLe.canonicalBytes.size}"
  expect (twinLeAdd.sourceHash ==
      "63a6bae223eb77d85bdbdc108493e2d11ed571296c548b30ef1b90a28b44879e")
    s!"1<=2+3 LessEqualTwin sourceHash golden must remain stable; got {twinLeAdd.sourceHash}"
  expect (twinLeAdd.canonicalBytes.size == 235)
    s!"1<=2+3 LessEqualTwin size golden must remain stable; got {twinLeAdd.canonicalBytes.size}"
  expect (twinMulLe.sourceHash ==
      "d2726f509be1385d4413b571843b4fd6e1923c0f1147097156d3d210ebb219c3")
    s!"1*2<=3 LessEqualTwin sourceHash golden must remain stable; got {twinMulLe.sourceHash}"
  expect (twinMulLe.canonicalBytes.size == 235)
    s!"1*2<=3 LessEqualTwin size golden must remain stable; got {twinMulLe.canonicalBytes.size}"
  expect (twinLeMul.sourceHash ==
      "bdbf7659ff2e1d44a45636737ded4d8d110c4c3bcf40fd086c5773334161ea0c")
    s!"1<=2*3 LessEqualTwin sourceHash golden must remain stable; got {twinLeMul.sourceHash}"
  expect (twinLeMul.canonicalBytes.size == 235)
    s!"1<=2*3 LessEqualTwin size golden must remain stable; got {twinLeMul.canonicalBytes.size}"
  expect (twinShlLe.sourceHash ==
      "2a04f479b5738c51563644e97be58b3e93a64cef804daae0b2ba985d74c74880")
    s!"1<<2<=3 LessEqualTwin sourceHash golden must remain stable; got {twinShlLe.sourceHash}"
  expect (twinShlLe.canonicalBytes.size == 235)
    s!"1<<2<=3 LessEqualTwin size golden must remain stable; got {twinShlLe.canonicalBytes.size}"
  expect (twinLeShl.sourceHash ==
      "dc2233b671502479c6760adb0b984d3d880bd6d7d926120dadd182b2ec553544")
    s!"1<=2<<3 LessEqualTwin sourceHash golden must remain stable; got {twinLeShl.sourceHash}"
  expect (twinLeShl.canonicalBytes.size == 235)
    s!"1<=2<<3 LessEqualTwin size golden must remain stable; got {twinLeShl.canonicalBytes.size}"
  expect (twinShrLe.sourceHash ==
      "e59d394fe96252c34a3d61848ee8f0c315bc1e82b43347470c8685267b708e68")
    s!"1>>2<=3 LessEqualTwin sourceHash golden must remain stable; got {twinShrLe.sourceHash}"
  expect (twinShrLe.canonicalBytes.size == 235)
    s!"1>>2<=3 LessEqualTwin size golden must remain stable; got {twinShrLe.canonicalBytes.size}"
  expect (twinLeShr.sourceHash ==
      "86e352d72feeffcc00ccdaac897fe0e60f10a8d6fb57d09d488c12b6f05bfc35")
    s!"1<=2>>3 LessEqualTwin sourceHash golden must remain stable; got {twinLeShr.sourceHash}"
  expect (twinLeShr.canonicalBytes.size == 235)
    s!"1<=2>>3 LessEqualTwin size golden must remain stable; got {twinLeShr.canonicalBytes.size}"
  expect (twinNegLe.sourceHash ==
      "d32038c45a65cd42359b5244ce7b65680481710c2f7976e9f8cbf94fe605c6d2")
    s!"-1<=2 LessEqualTwin sourceHash golden must remain stable; got {twinNegLe.sourceHash}"
  expect (twinNegLe.canonicalBytes.size == 226)
    s!"-1<=2 LessEqualTwin size golden must remain stable; got {twinNegLe.canonicalBytes.size}"
  expect (twinLeNeg.sourceHash ==
      "de05b050e3995eee5345c8170dc7554e5b3549a5fad741884a27f77af8399b2f")
    s!"1<=-2 LessEqualTwin sourceHash golden must remain stable; got {twinLeNeg.sourceHash}"
  expect (twinLeNeg.canonicalBytes.size == 226)
    s!"1<=-2 LessEqualTwin size golden must remain stable; got {twinLeNeg.canonicalBytes.size}"
  expect (twinLtCtrl.sourceHash ==
      "dfffa99bf35ba4c05180a9ef8100501ed88bc0e0853cae42c1aec214775b44a0")
    s!"lessThan 1<2 control sourceHash golden must remain stable; got {twinLtCtrl.sourceHash}"
  expect (twinLtCtrl.canonicalBytes.size == 225)
    s!"lessThan 1<2 control size golden must remain stable; got {twinLtCtrl.canonicalBytes.size}"
  expect (twinEqCtrl.sourceHash ==
      "3c11c278c67a59f611f1f748365409f21f7eaf762ad30c2fd2a130a2a426da75")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEqCtrl.sourceHash}"
  expect (twinEqCtrl.canonicalBytes.size == 225)
    s!"equal 1==2 control size golden must remain stable; got {twinEqCtrl.canonicalBytes.size}"
  expect (twinNeCtrl.sourceHash ==
      "128acefc94ebb8a092b0c19e9c5ea88d9a440262cb926a23bb7f7296e62acd32")
    s!"notEqual 1!=2 control sourceHash golden must remain stable; got {twinNeCtrl.sourceHash}"
  expect (twinNeCtrl.canonicalBytes.size == 225)
    s!"notEqual 1!=2 control size golden must remain stable; got {twinNeCtrl.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "04c908caae60dca8fcbed5f22e1d3021a30a527d9e529255518c40e11b9c32c5")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 225)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinShl.sourceHash ==
      "669a58c95ce7312e338da9b36e0a1fa7357f3fa9a2025b216d516a73ba483d0b")
    s!"shiftLeft 1<<2 control sourceHash golden must remain stable; got {twinShl.sourceHash}"
  expect (twinShl.canonicalBytes.size == 225)
    s!"shiftLeft 1<<2 control size golden must remain stable; got {twinShl.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "lessEqual 1<=2 must not alias 2<=1 (operand order)"
  expect (twin12.sourceHash != twinLtCtrl.sourceHash)
    "lessEqual 1<=2 must not alias lessThan 1<2 (operator tag)"
  expect (twin12.sourceHash != twinEqCtrl.sourceHash)
    "lessEqual 1<=2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinNeCtrl.sourceHash)
    "lessEqual 1<=2 must not alias notEqual 1!=2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "lessEqual 1<=2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinLtCtrl.canonicalBytes.size)
    "lessEqual and lessThan of two small literals must share size (tag-only distinction)"
  expect (twinAddLe.sourceHash != twinWrong.sourceHash)
    "1+2<=3 must not alias wrong C-style 1+(2<=3)"
  expect (twinAddLe.sourceHash != twinLeAdd.sourceHash)
    "1+2<=3 must not alias 1<=2+3 (lhs/rhs add placement)"
  expect (twinMulLe.sourceHash != twinLeMul.sourceHash)
    "1*2<=3 must not alias 1<=2*3"
  expect (twinShlLe.sourceHash != twinLeShl.sourceHash)
    "1<<2<=3 must not alias 1<=2<<3"
  expect (twinShrLe.sourceHash != twinLeShr.sourceHash)
    "1>>2<=3 must not alias 1<=2>>3"
  expect (twinNegLe.sourceHash != twinLeNeg.sourceHash)
    "-1<=2 must not alias 1<=-2 (unary placement)"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true<=false must not alias false<=true (Bool operand order)"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0<=0 must not alias 1<=2"

  -- Parser-boundary: token integrity, same/mixed chains (both orientations), malformed.
  for (label, expr) in [
      ("bare less-equal", "<="),
      ("missing lhs", "<= 2"),
      ("missing rhs", "1 <="),
      ("extra token", "1 <= 2 3"),
      ("spaced lt equals", "1 < = 2"),
      ("shift assign-like", "1 <<= 2"),
      ("spaced le equals", "1 <= = 2"),
      ("same chain", "1 <= 2 <= 3"),
      ("mixed le then lt", "1 <= 2 < 3"),
      ("mixed lt then le", "1 < 2 <= 3"),
      ("mixed le then eq", "1 <= 2 == 3"),
      ("mixed eq then le", "1 == 2 <= 3"),
      ("mixed le then ne", "1 <= 2 != 3"),
      ("mixed ne then le", "1 != 2 <= 3")
    ] do
    let source := returnProgramSource "RejectedLeShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<le-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including Bool operands).
  match Compiler.compile (twin (.lessEqual (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "less-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject lessEqual with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing lessEqual"

  match Compiler.compile
      (twin (.lessEqual (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "less-equal comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true<=false with less-equal message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true<=false programs"

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

end Tests.Language.LessEqual
