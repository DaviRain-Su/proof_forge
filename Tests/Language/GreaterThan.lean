import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- GreaterThanSurface pins binary `>` in every declaration body position: init, entry,
-- view, and fn. Migration: exactly Equal.lean deferred `1 > 2` only.
namespace Tests.Language.GreaterThanFixture

open ProofForgeV2.Language

program GreaterThanSurface where
  init() do
    let seed : UInt64 := 1 > 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a > b

  view peek() : UInt64 do
    let value := 1 + 2 > 3
    return value

  fn helper() : UInt64 do
    return true > false

end Tests.Language.GreaterThanFixture

namespace Tests.Language.GreaterThan

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.GreaterThanFixture.GreaterThanTwin" "GreaterThanTwin" #[
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
  "namespace Tests.Language.GreaterThanFixture\n\n" ++
  "program GreaterThanSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 > 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a > b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 > 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true > false\n\n" ++
  "end Tests.Language.GreaterThanFixture\n"

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
  let elaborated := Tests.Language.GreaterThanFixture.GreaterThanSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.greaterThan (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 > 2"
  | none => throw <| IO.userError "GreaterThanSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.greaterThan (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a > b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.greaterThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 > 3 as (1+2)>3"
  | _ => throw <| IO.userError "GreaterThanSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.greaterThan (.boolLiteral true) (.boolLiteral false))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return true > false"
  | _ => throw <| IO.userError "GreaterThanSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<greater-than>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same greaterThan Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same greaterThan sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 50 non-assoc, both operand slots 51).
  let gt12 ← select session (returnProgramSource "Gt12" "1 > 2") "<gt-1-2>"
  expectReturnExpr "1 > 2" gt12 (.greaterThan (.literal 1) (.literal 2))

  let gt21 ← select session (returnProgramSource "Gt21" "2 > 1") "<gt-2-1>"
  expectReturnExpr "2 > 1" gt21 (.greaterThan (.literal 2) (.literal 1))

  let gtAB ← select session (varReturnProgramSource "GtAB" "a > b") "<gt-a-b>"
  expectReturnExpr "a > b" gtAB (.greaterThan (.variable "a") (.variable "b"))

  let gt00 ← select session (returnProgramSource "Gt00" "0 > 0") "<gt-0-0>"
  expectReturnExpr "0 > 0" gt00 (.greaterThan (.literal 0) (.literal 0))

  let gtTF ← select session (returnProgramSource "GtTF" "true > false") "<gt-t-f>"
  expectReturnExpr "true > false" gtTF
    (.greaterThan (.boolLiteral true) (.boolLiteral false))

  let gtFT ← select session (returnProgramSource "GtFT" "false > true") "<gt-f-t>"
  expectReturnExpr "false > true" gtFT
    (.greaterThan (.boolLiteral false) (.boolLiteral true))

  let addGt ← select session (returnProgramSource "AddGt" "1 + 2 > 3") "<add-gt>"
  expectReturnExpr "1 + 2 > 3" addGt
    (.greaterThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let gtAdd ← select session (returnProgramSource "GtAdd" "1 > 2 + 3") "<gt-add>"
  expectReturnExpr "1 > 2 + 3" gtAdd
    (.greaterThan (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulGt ← select session (returnProgramSource "MulGt" "1 * 2 > 3") "<mul-gt>"
  expectReturnExpr "1 * 2 > 3" mulGt
    (.greaterThan (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let gtMul ← select session (returnProgramSource "GtMul" "1 > 2 * 3") "<gt-mul>"
  expectReturnExpr "1 > 2 * 3" gtMul
    (.greaterThan (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shrGt ← select session (returnProgramSource "ShrGt" "1 >> 2 > 3") "<shr-gt>"
  expectReturnExpr "1 >> 2 > 3" shrGt
    (.greaterThan (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let gtShr ← select session (returnProgramSource "GtShr" "1 > 2 >> 3") "<gt-shr>"
  expectReturnExpr "1 > 2 >> 3" gtShr
    (.greaterThan (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let shlGt ← select session (returnProgramSource "ShlGt" "1 << 2 > 3") "<shl-gt>"
  expectReturnExpr "1 << 2 > 3" shlGt
    (.greaterThan (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let gtShl ← select session (returnProgramSource "GtShl" "1 > 2 << 3") "<gt-shl>"
  expectReturnExpr "1 > 2 << 3" gtShl
    (.greaterThan (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let groupGt ← select session
    (returnProgramSource "GroupGt" "(1 + 2) > 3") "<group-gt>"
  expectReturnExpr "(1 + 2) > 3" groupGt
    (.greaterThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negGt ← select session (returnProgramSource "NegGt" "-1 > 2") "<neg-gt>"
  expectReturnExpr "-1 > 2" negGt
    (.greaterThan (.checkedNeg (.literal 1)) (.literal 2))

  let gtNeg ← select session (returnProgramSource "GtNeg" "1 > -2") "<gt-neg>"
  expectReturnExpr "1 > -2" gtNeg
    (.greaterThan (.literal 1) (.checkedNeg (.literal 2)))

  -- Longest-token control: 1 >> 2 remains shiftRight.
  let stillShr ← select session (returnProgramSource "StillShr" "1 >> 2") "<still-shr>"
  expectReturnExpr "1 >> 2" stillShr (.shiftRight (.literal 1) (.literal 2))

  -- Same-identity desugar.
  let bareGt ← select session (returnProgramSource "GtSame" "1 > 2") "<gt-same-bare>"
  let groupSame ← select session
    (returnProgramSource "GtSame" "(1 > 2)") "<gt-same-group>"
  expect (bareGt == groupSame)
    "1 > 2 and (1 > 2) must share Source.Program under identical identity"
  expect (bareGt.canonicalBytes == groupSame.canonicalBytes)
    "1 > 2 and (1 > 2) must share canonical bytes under identical identity"
  expect (bareGt.sourceHash == groupSame.sourceHash)
    "1 > 2 and (1 > 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for GreaterThanTwin (Expr tag 18 + lhs/rhs).
  let twin12 := twin (.greaterThan (.literal 1) (.literal 2))
  let twin21 := twin (.greaterThan (.literal 2) (.literal 1))
  let twinAB := twin (.greaterThan (.variable "a") (.variable "b"))
  let twin00 := twin (.greaterThan (.literal 0) (.literal 0))
  let twinTF := twin (.greaterThan (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.greaterThan (.boolLiteral false) (.boolLiteral true))
  let twinAddGt := twin
    (.greaterThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinGtAdd := twin
    (.greaterThan (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.greaterThan (.literal 2) (.literal 3)))
  let twinMulGt := twin
    (.greaterThan (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinGtMul := twin
    (.greaterThan (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShrGt := twin
    (.greaterThan (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinGtShr := twin
    (.greaterThan (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinShlGt := twin
    (.greaterThan (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinGtShl := twin
    (.greaterThan (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinNegGt := twin
    (.greaterThan (.checkedNeg (.literal 1)) (.literal 2))
  let twinGtNeg := twin
    (.greaterThan (.literal 1) (.checkedNeg (.literal 2)))
  let twinLtCtrl := twin (.lessThan (.literal 1) (.literal 2))
  let twinLeCtrl := twin (.lessEqual (.literal 1) (.literal 2))
  let twinEqCtrl := twin (.equal (.literal 1) (.literal 2))
  let twinNeCtrl := twin (.notEqual (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinShr := twin (.shiftRight (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "1dd61183be0bfb0d0955232b2c1c751d049215f6fd262c9a81e35f59f8d0c137")
    s!"greaterThan 1>2 GreaterThanTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 231)
    s!"greaterThan 1>2 GreaterThanTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "dbce68b33070a56eecbcee77a46efb826c7cd4bc16b310868aa6cf9307dc6566")
    s!"greaterThan 2>1 GreaterThanTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 231)
    s!"greaterThan 2>1 GreaterThanTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "d40766c07df04716ddc45604213dd8edb5e6cb14534707e00794d84d1c2896c5")
    s!"a>b GreaterThanTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 233)
    s!"a>b GreaterThanTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "35ffbdfe9bbfa7a3875e7f8ce626de04945b72cb849a937063b4389421d5f984")
    s!"0>0 GreaterThanTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 231)
    s!"0>0 GreaterThanTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "d1b81799ca56ba7ced47d015f8ee13a8e48fcf53edd7a6e5655c9dfacec06e13")
    s!"true>false GreaterThanTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 217)
    s!"true>false GreaterThanTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "6f952cc5f3daba780e94dfe0445a48d9653f7a684c6e80386badaa5046c6ec67")
    s!"false>true GreaterThanTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 217)
    s!"false>true GreaterThanTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddGt.sourceHash ==
      "9b966897643d446292c4f15ed673fce28798b879cce2c9ec879a315b4974f2db")
    s!"1+2>3 GreaterThanTwin sourceHash golden must remain stable; got {twinAddGt.sourceHash}"
  expect (twinAddGt.canonicalBytes.size == 241)
    s!"1+2>3 GreaterThanTwin size golden must remain stable; got {twinAddGt.canonicalBytes.size}"
  expect (twinGtAdd.sourceHash ==
      "c34283559270f8d46e78b589edf5d53527076b18b24eabc1c5bcda2a21c63a95")
    s!"1>2+3 GreaterThanTwin sourceHash golden must remain stable; got {twinGtAdd.sourceHash}"
  expect (twinGtAdd.canonicalBytes.size == 241)
    s!"1>2+3 GreaterThanTwin size golden must remain stable; got {twinGtAdd.canonicalBytes.size}"
  expect (twinMulGt.sourceHash ==
      "c84e91bf70bcd3c61fec329d61c84084a9f41129755a9a20d31781fb6e293e2e")
    s!"1*2>3 GreaterThanTwin sourceHash golden must remain stable; got {twinMulGt.sourceHash}"
  expect (twinMulGt.canonicalBytes.size == 241)
    s!"1*2>3 GreaterThanTwin size golden must remain stable; got {twinMulGt.canonicalBytes.size}"
  expect (twinGtMul.sourceHash ==
      "f58ed77b6aaec39de997a1468b28cc80812b09bd3ba268ecc3307596560b34e7")
    s!"1>2*3 GreaterThanTwin sourceHash golden must remain stable; got {twinGtMul.sourceHash}"
  expect (twinGtMul.canonicalBytes.size == 241)
    s!"1>2*3 GreaterThanTwin size golden must remain stable; got {twinGtMul.canonicalBytes.size}"
  expect (twinShrGt.sourceHash ==
      "756aa4acb27e6a475d4732e56ed855f87f74ccd9ca45b372038331d53a0d9168")
    s!"1>>2>3 GreaterThanTwin sourceHash golden must remain stable; got {twinShrGt.sourceHash}"
  expect (twinShrGt.canonicalBytes.size == 241)
    s!"1>>2>3 GreaterThanTwin size golden must remain stable; got {twinShrGt.canonicalBytes.size}"
  expect (twinGtShr.sourceHash ==
      "6b1adb2c2d71e80c724ac050867bf87e8801a1f3c5ed9f053e64e9d533ccde4b")
    s!"1>2>>3 GreaterThanTwin sourceHash golden must remain stable; got {twinGtShr.sourceHash}"
  expect (twinGtShr.canonicalBytes.size == 241)
    s!"1>2>>3 GreaterThanTwin size golden must remain stable; got {twinGtShr.canonicalBytes.size}"
  expect (twinShlGt.sourceHash ==
      "b34ea34d0ca0946c19d63074653a245ff14b074c97f51b7dd7c40bf3ee1df486")
    s!"1<<2>3 GreaterThanTwin sourceHash golden must remain stable; got {twinShlGt.sourceHash}"
  expect (twinShlGt.canonicalBytes.size == 241)
    s!"1<<2>3 GreaterThanTwin size golden must remain stable; got {twinShlGt.canonicalBytes.size}"
  expect (twinGtShl.sourceHash ==
      "ff4523989d9688ec3a618693c3585505d6e0640d6f677e5424172423b9062f61")
    s!"1>2<<3 GreaterThanTwin sourceHash golden must remain stable; got {twinGtShl.sourceHash}"
  expect (twinGtShl.canonicalBytes.size == 241)
    s!"1>2<<3 GreaterThanTwin size golden must remain stable; got {twinGtShl.canonicalBytes.size}"
  expect (twinNegGt.sourceHash ==
      "d153215ff1a62d8d6b322da213b3bdc945f68d23083d4da82cb76a90e3777807")
    s!"-1>2 GreaterThanTwin sourceHash golden must remain stable; got {twinNegGt.sourceHash}"
  expect (twinNegGt.canonicalBytes.size == 232)
    s!"-1>2 GreaterThanTwin size golden must remain stable; got {twinNegGt.canonicalBytes.size}"
  expect (twinGtNeg.sourceHash ==
      "64ce58ac98b54b56e68de1e6c5c16976072984604bcdc119af9b0402506fd45c")
    s!"1>-2 GreaterThanTwin sourceHash golden must remain stable; got {twinGtNeg.sourceHash}"
  expect (twinGtNeg.canonicalBytes.size == 232)
    s!"1>-2 GreaterThanTwin size golden must remain stable; got {twinGtNeg.canonicalBytes.size}"
  expect (twinLtCtrl.sourceHash ==
      "b30b795c1e2ec35a310f3f660e0691ba4bbe8001b6468cdc373ad6d0a8556998")
    s!"lessThan 1<2 control sourceHash golden must remain stable; got {twinLtCtrl.sourceHash}"
  expect (twinLtCtrl.canonicalBytes.size == 231)
    s!"lessThan 1<2 control size golden must remain stable; got {twinLtCtrl.canonicalBytes.size}"
  expect (twinLeCtrl.sourceHash ==
      "3e9f9282a6d4f95705e4a2f46b826875843eecd535dc92a94b2d21f921aef4d7")
    s!"lessEqual 1<=2 control sourceHash golden must remain stable; got {twinLeCtrl.sourceHash}"
  expect (twinLeCtrl.canonicalBytes.size == 231)
    s!"lessEqual 1<=2 control size golden must remain stable; got {twinLeCtrl.canonicalBytes.size}"
  expect (twinEqCtrl.sourceHash ==
      "16458bf39f4a428a8cb8c4d8aac26e1c71bd90e91c937d8a452f707874bd09e0")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEqCtrl.sourceHash}"
  expect (twinEqCtrl.canonicalBytes.size == 231)
    s!"equal 1==2 control size golden must remain stable; got {twinEqCtrl.canonicalBytes.size}"
  expect (twinNeCtrl.sourceHash ==
      "1f17b03d844531810368030db342b93e0ffd2748b506b8b8bbb4645c9b16b6c3")
    s!"notEqual 1!=2 control sourceHash golden must remain stable; got {twinNeCtrl.sourceHash}"
  expect (twinNeCtrl.canonicalBytes.size == 231)
    s!"notEqual 1!=2 control size golden must remain stable; got {twinNeCtrl.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "bd1cfbdd9068bd2a7814ccd391144fccbeb42fef603ce58bc5d3db558a6423d3")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 231)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinShr.sourceHash ==
      "6dfb8c3c944dc5527125c1575935dbba5b66af7fe77a4f8feb02e19dbe4dd890")
    s!"shiftRight 1>>2 control sourceHash golden must remain stable; got {twinShr.sourceHash}"
  expect (twinShr.canonicalBytes.size == 231)
    s!"shiftRight 1>>2 control size golden must remain stable; got {twinShr.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "greaterThan 1>2 must not alias 2>1 (operand order)"
  expect (twin12.sourceHash != twinLtCtrl.sourceHash)
    "greaterThan 1>2 must not alias lessThan 1<2 (operator tag)"
  expect (twin12.sourceHash != twinLeCtrl.sourceHash)
    "greaterThan 1>2 must not alias lessEqual 1<=2 (operator tag)"
  expect (twin12.sourceHash != twinEqCtrl.sourceHash)
    "greaterThan 1>2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinNeCtrl.sourceHash)
    "greaterThan 1>2 must not alias notEqual 1!=2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "greaterThan 1>2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.sourceHash != twinShr.sourceHash)
    "greaterThan 1>2 must not alias shiftRight 1>>2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinLtCtrl.canonicalBytes.size)
    "greaterThan and lessThan of two small literals must share size (tag-only distinction)"
  expect (twinAddGt.sourceHash != twinWrong.sourceHash)
    "1+2>3 must not alias wrong C-style 1+(2>3)"
  expect (twinAddGt.sourceHash != twinGtAdd.sourceHash)
    "1+2>3 must not alias 1>2+3 (lhs/rhs add placement)"
  expect (twinMulGt.sourceHash != twinGtMul.sourceHash)
    "1*2>3 must not alias 1>2*3"
  expect (twinShrGt.sourceHash != twinGtShr.sourceHash)
    "1>>2>3 must not alias 1>2>>3"
  expect (twinShlGt.sourceHash != twinGtShl.sourceHash)
    "1<<2>3 must not alias 1>2<<3"
  expect (twinNegGt.sourceHash != twinGtNeg.sourceHash)
    "-1>2 must not alias 1>-2 (unary placement)"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true>false must not alias false>true (Bool operand order)"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0>0 must not alias 1>2"

  -- Parser-boundary: token integrity, same/mixed chains, malformed.
  for (label, expr) in [
      ("bare greater-than", ">"),
      ("missing lhs", "> 2"),
      ("missing rhs", "1 >"),
      ("extra token", "1 > 2 3"),
      ("spaced split", "1 > > 2"),
      ("triple greater", "1 >>> 2"),
      ("shift assign-like", "1 >>= 2"),
      ("spaced gt equals", "1 > = 2"),
      ("same chain", "1 > 2 > 3"),
      ("mixed gt then eq", "1 > 2 == 3"),
      ("mixed eq then gt", "1 == 2 > 3"),
      ("mixed gt then ne", "1 > 2 != 3"),
      ("mixed ne then gt", "1 != 2 > 3"),
      ("mixed gt then lt", "1 > 2 < 3"),
      ("mixed lt then gt", "1 < 2 > 3"),
      ("mixed gt then le", "1 > 2 <= 3"),
      ("mixed le then gt", "1 <= 2 > 3")
    ] do
    let source := returnProgramSource "RejectedGtShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<gt-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including Bool operands).
  match Compiler.compile (twin (.greaterThan (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "greater-than comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject greaterThan with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing greaterThan"

  match Compiler.compile
      (twin (.greaterThan (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "greater-than comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true>false with greater-than message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true>false programs"

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

end Tests.Language.GreaterThan
