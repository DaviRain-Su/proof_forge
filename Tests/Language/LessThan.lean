import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- LessThanSurface pins binary `<` in every declaration body position: init, entry,
-- view, and fn. Migration: exactly Equal.lean deferred `1 < 2` only.
namespace Tests.Language.LessThanFixture

open ProofForgeV2.Language

program LessThanSurface where
  init() do
    let seed : UInt64 := 1 < 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a < b

  view peek() : UInt64 do
    let value := 1 + 2 < 3
    return value

  fn helper() : UInt64 do
    return true < false

end Tests.Language.LessThanFixture

namespace Tests.Language.LessThan

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LessThanFixture.LessThanTwin" "LessThanTwin" #[
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
  "namespace Tests.Language.LessThanFixture\n\n" ++
  "program LessThanSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 < 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a < b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 < 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true < false\n\n" ++
  "end Tests.Language.LessThanFixture\n"

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
  let elaborated := Tests.Language.LessThanFixture.LessThanSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.lessThan (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 < 2"
  | none => throw <| IO.userError "LessThanSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.lessThan (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a < b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.lessThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 < 3 as (1+2)<3"
  | _ => throw <| IO.userError "LessThanSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.lessThan (.boolLiteral true) (.boolLiteral false))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return true < false"
  | _ => throw <| IO.userError "LessThanSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<less-than>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same lessThan Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same lessThan sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 50 non-assoc, both operand slots 51).
  let lt12 ← select session (returnProgramSource "Lt12" "1 < 2") "<lt-1-2>"
  expectReturnExpr "1 < 2" lt12 (.lessThan (.literal 1) (.literal 2))

  let lt21 ← select session (returnProgramSource "Lt21" "2 < 1") "<lt-2-1>"
  expectReturnExpr "2 < 1" lt21 (.lessThan (.literal 2) (.literal 1))

  let ltAB ← select session (varReturnProgramSource "LtAB" "a < b") "<lt-a-b>"
  expectReturnExpr "a < b" ltAB (.lessThan (.variable "a") (.variable "b"))

  let lt00 ← select session (returnProgramSource "Lt00" "0 < 0") "<lt-0-0>"
  expectReturnExpr "0 < 0" lt00 (.lessThan (.literal 0) (.literal 0))

  let ltTF ← select session (returnProgramSource "LtTF" "true < false") "<lt-t-f>"
  expectReturnExpr "true < false" ltTF
    (.lessThan (.boolLiteral true) (.boolLiteral false))

  let ltFT ← select session (returnProgramSource "LtFT" "false < true") "<lt-f-t>"
  expectReturnExpr "false < true" ltFT
    (.lessThan (.boolLiteral false) (.boolLiteral true))

  let addLt ← select session (returnProgramSource "AddLt" "1 + 2 < 3") "<add-lt>"
  expectReturnExpr "1 + 2 < 3" addLt
    (.lessThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let ltAdd ← select session (returnProgramSource "LtAdd" "1 < 2 + 3") "<lt-add>"
  expectReturnExpr "1 < 2 + 3" ltAdd
    (.lessThan (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulLt ← select session (returnProgramSource "MulLt" "1 * 2 < 3") "<mul-lt>"
  expectReturnExpr "1 * 2 < 3" mulLt
    (.lessThan (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let ltMul ← select session (returnProgramSource "LtMul" "1 < 2 * 3") "<lt-mul>"
  expectReturnExpr "1 < 2 * 3" ltMul
    (.lessThan (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlLt ← select session (returnProgramSource "ShlLt" "1 << 2 < 3") "<shl-lt>"
  expectReturnExpr "1 << 2 < 3" shlLt
    (.lessThan (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let ltShl ← select session (returnProgramSource "LtShl" "1 < 2 << 3") "<lt-shl>"
  expectReturnExpr "1 < 2 << 3" ltShl
    (.lessThan (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrLt ← select session (returnProgramSource "ShrLt" "1 >> 2 < 3") "<shr-lt>"
  expectReturnExpr "1 >> 2 < 3" shrLt
    (.lessThan (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let ltShr ← select session (returnProgramSource "LtShr" "1 < 2 >> 3") "<lt-shr>"
  expectReturnExpr "1 < 2 >> 3" ltShr
    (.lessThan (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let groupLt ← select session
    (returnProgramSource "GroupLt" "(1 + 2) < 3") "<group-lt>"
  expectReturnExpr "(1 + 2) < 3" groupLt
    (.lessThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negLt ← select session (returnProgramSource "NegLt" "-1 < 2") "<neg-lt>"
  expectReturnExpr "-1 < 2" negLt
    (.lessThan (.checkedNeg (.literal 1)) (.literal 2))

  let ltNeg ← select session (returnProgramSource "LtNeg" "1 < -2") "<lt-neg>"
  expectReturnExpr "1 < -2" ltNeg
    (.lessThan (.literal 1) (.checkedNeg (.literal 2)))

  -- Longest-token control: 1 << 2 remains shiftLeft (not nested lessThan).
  let stillShl ← select session (returnProgramSource "StillShl" "1 << 2") "<still-shl>"
  expectReturnExpr "1 << 2" stillShl (.shiftLeft (.literal 1) (.literal 2))

  -- Same-identity desugar.
  let bareLt ← select session (returnProgramSource "LtSame" "1 < 2") "<lt-same-bare>"
  let groupSame ← select session
    (returnProgramSource "LtSame" "(1 < 2)") "<lt-same-group>"
  expect (bareLt == groupSame)
    "1 < 2 and (1 < 2) must share Source.Program under identical identity"
  expect (bareLt.canonicalBytes == groupSame.canonicalBytes)
    "1 < 2 and (1 < 2) must share canonical bytes under identical identity"
  expect (bareLt.sourceHash == groupSame.sourceHash)
    "1 < 2 and (1 < 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for LessThanTwin (Expr tag 16 + lhs/rhs).
  let twin12 := twin (.lessThan (.literal 1) (.literal 2))
  let twin21 := twin (.lessThan (.literal 2) (.literal 1))
  let twinAB := twin (.lessThan (.variable "a") (.variable "b"))
  let twin00 := twin (.lessThan (.literal 0) (.literal 0))
  let twinTF := twin (.lessThan (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.lessThan (.boolLiteral false) (.boolLiteral true))
  let twinAddLt := twin
    (.lessThan (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinLtAdd := twin
    (.lessThan (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.lessThan (.literal 2) (.literal 3)))
  let twinMulLt := twin
    (.lessThan (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinLtMul := twin
    (.lessThan (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlLt := twin
    (.lessThan (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinLtShl := twin
    (.lessThan (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrLt := twin
    (.lessThan (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinLtShr := twin
    (.lessThan (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinNegLt := twin
    (.lessThan (.checkedNeg (.literal 1)) (.literal 2))
  let twinLtNeg := twin
    (.lessThan (.literal 1) (.checkedNeg (.literal 2)))
  let twinEqCtrl := twin (.equal (.literal 1) (.literal 2))
  let twinNeCtrl := twin (.notEqual (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinShl := twin (.shiftLeft (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "2603fd7611520e5ebf3fcab1e0cb228947acce84bc746f1201c894be08bceaca")
    s!"lessThan 1<2 LessThanTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 222)
    s!"lessThan 1<2 LessThanTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "8878e8fc1ec9415689c57508b19880a5ce7af6e3283f8e5f7d2bccfbae04cb0a")
    s!"lessThan 2<1 LessThanTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 222)
    s!"lessThan 2<1 LessThanTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "7fe2318bad2bfbcd5cd959dd6829f1ba343542e1955a99cf5d87cdf5c07ce241")
    s!"a<b LessThanTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 224)
    s!"a<b LessThanTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "e49045a23e7346886d79cecbe9075679e7fafc1d80a8b0023dd49bc996d50abf")
    s!"0<0 LessThanTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 222)
    s!"0<0 LessThanTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "dad6d5ebdb8578da84ab092abe733b83338859238ea1f5c81d9f643877733433")
    s!"true<false LessThanTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 208)
    s!"true<false LessThanTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "0ad9775af9e1e1a84fe8fe17b50abd177117407e8a300894df8d6a22d70e331d")
    s!"false<true LessThanTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 208)
    s!"false<true LessThanTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddLt.sourceHash ==
      "33328a0026056eaa295314e3d3707c53841b66401e4d3b62f248539be4f82874")
    s!"1+2<3 LessThanTwin sourceHash golden must remain stable; got {twinAddLt.sourceHash}"
  expect (twinAddLt.canonicalBytes.size == 232)
    s!"1+2<3 LessThanTwin size golden must remain stable; got {twinAddLt.canonicalBytes.size}"
  expect (twinLtAdd.sourceHash ==
      "dd5a017f15d81f60f32aab039bdfa411070622d8b75a8b327cd1dedeb53e3c06")
    s!"1<2+3 LessThanTwin sourceHash golden must remain stable; got {twinLtAdd.sourceHash}"
  expect (twinLtAdd.canonicalBytes.size == 232)
    s!"1<2+3 LessThanTwin size golden must remain stable; got {twinLtAdd.canonicalBytes.size}"
  expect (twinMulLt.sourceHash ==
      "3076bee2383d5afbffbc514e4f95abca01b54a16fbc84b3a43ccbdd9c83af118")
    s!"1*2<3 LessThanTwin sourceHash golden must remain stable; got {twinMulLt.sourceHash}"
  expect (twinMulLt.canonicalBytes.size == 232)
    s!"1*2<3 LessThanTwin size golden must remain stable; got {twinMulLt.canonicalBytes.size}"
  expect (twinLtMul.sourceHash ==
      "d1c24020e7916469a509d36d8a16764495a3cd511d66dfe27c73a110d3987b7a")
    s!"1<2*3 LessThanTwin sourceHash golden must remain stable; got {twinLtMul.sourceHash}"
  expect (twinLtMul.canonicalBytes.size == 232)
    s!"1<2*3 LessThanTwin size golden must remain stable; got {twinLtMul.canonicalBytes.size}"
  expect (twinShlLt.sourceHash ==
      "320ae2afb179c909eab24776406c085721fc78433fa5bdc39825f822d94e5920")
    s!"1<<2<3 LessThanTwin sourceHash golden must remain stable; got {twinShlLt.sourceHash}"
  expect (twinShlLt.canonicalBytes.size == 232)
    s!"1<<2<3 LessThanTwin size golden must remain stable; got {twinShlLt.canonicalBytes.size}"
  expect (twinLtShl.sourceHash ==
      "abc48121320bf8da57cac9b7f4ca5c744f5461e57d4b7a66ebb731d70bc40bfc")
    s!"1<2<<3 LessThanTwin sourceHash golden must remain stable; got {twinLtShl.sourceHash}"
  expect (twinLtShl.canonicalBytes.size == 232)
    s!"1<2<<3 LessThanTwin size golden must remain stable; got {twinLtShl.canonicalBytes.size}"
  expect (twinShrLt.sourceHash ==
      "300327093cc38ae18bb510c3338816e75b454e511265f3660034d95435728826")
    s!"1>>2<3 LessThanTwin sourceHash golden must remain stable; got {twinShrLt.sourceHash}"
  expect (twinShrLt.canonicalBytes.size == 232)
    s!"1>>2<3 LessThanTwin size golden must remain stable; got {twinShrLt.canonicalBytes.size}"
  expect (twinLtShr.sourceHash ==
      "fd724a763a62f3bc8c3ffcc1a55a53d97435c4e53092548bee1e45d0b5a422cb")
    s!"1<2>>3 LessThanTwin sourceHash golden must remain stable; got {twinLtShr.sourceHash}"
  expect (twinLtShr.canonicalBytes.size == 232)
    s!"1<2>>3 LessThanTwin size golden must remain stable; got {twinLtShr.canonicalBytes.size}"
  expect (twinNegLt.sourceHash ==
      "833663bd771f492225444eb1bfc1adeec84b6d7f344df19750e49c730f04f22d")
    s!"-1<2 LessThanTwin sourceHash golden must remain stable; got {twinNegLt.sourceHash}"
  expect (twinNegLt.canonicalBytes.size == 223)
    s!"-1<2 LessThanTwin size golden must remain stable; got {twinNegLt.canonicalBytes.size}"
  expect (twinLtNeg.sourceHash ==
      "4bfdf055eeefe42afdc41e614bdb5045871ff4bda2313ac0f1b2e73e33ccb55a")
    s!"1<-2 LessThanTwin sourceHash golden must remain stable; got {twinLtNeg.sourceHash}"
  expect (twinLtNeg.canonicalBytes.size == 223)
    s!"1<-2 LessThanTwin size golden must remain stable; got {twinLtNeg.canonicalBytes.size}"
  expect (twinEqCtrl.sourceHash ==
      "bef5b29f4bf9ab32a0473aa16767be7b4214c5393170c4543f8b3dd440b9360f")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEqCtrl.sourceHash}"
  expect (twinEqCtrl.canonicalBytes.size == 222)
    s!"equal 1==2 control size golden must remain stable; got {twinEqCtrl.canonicalBytes.size}"
  expect (twinNeCtrl.sourceHash ==
      "54ccf0d32c32be630c5d24eec1298e5a24e76d6fb2e5b56a38471c6c7b0dc912")
    s!"notEqual 1!=2 control sourceHash golden must remain stable; got {twinNeCtrl.sourceHash}"
  expect (twinNeCtrl.canonicalBytes.size == 222)
    s!"notEqual 1!=2 control size golden must remain stable; got {twinNeCtrl.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "972b818ce68b85f815171149b72261aae4a596d040cdab013bf1ce6aed4cce27")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 222)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinShl.sourceHash ==
      "5f1dc3d2df85c0d7e3ab9b4649f2581b9f2769e6064d53e7724231d4af932656")
    s!"shiftLeft 1<<2 control sourceHash golden must remain stable; got {twinShl.sourceHash}"
  expect (twinShl.canonicalBytes.size == 222)
    s!"shiftLeft 1<<2 control size golden must remain stable; got {twinShl.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "lessThan 1<2 must not alias 2<1 (operand order)"
  expect (twin12.sourceHash != twinEqCtrl.sourceHash)
    "lessThan 1<2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinNeCtrl.sourceHash)
    "lessThan 1<2 must not alias notEqual 1!=2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "lessThan 1<2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.sourceHash != twinShl.sourceHash)
    "lessThan 1<2 must not alias shiftLeft 1<<2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinEqCtrl.canonicalBytes.size)
    "lessThan and equal of two small literals must share size (tag-only distinction)"
  expect (twinAddLt.sourceHash != twinWrong.sourceHash)
    "1+2<3 must not alias wrong C-style 1+(2<3)"
  expect (twinAddLt.sourceHash != twinLtAdd.sourceHash)
    "1+2<3 must not alias 1<2+3 (lhs/rhs add placement)"
  expect (twinMulLt.sourceHash != twinLtMul.sourceHash)
    "1*2<3 must not alias 1<2*3"
  expect (twinShlLt.sourceHash != twinLtShl.sourceHash)
    "1<<2<3 must not alias 1<2<<3"
  expect (twinShrLt.sourceHash != twinLtShr.sourceHash)
    "1>>2<3 must not alias 1<2>>3"
  expect (twinNegLt.sourceHash != twinLtNeg.sourceHash)
    "-1<2 must not alias 1<-2 (unary placement)"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true<false must not alias false<true (Bool operand order)"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0<0 must not alias 1<2"

  -- Parser-boundary: same/mixed chains, token integrity, malformed.
  for (label, expr) in [
      ("bare less-than", "<"),
      ("missing lhs", "< 2"),
      ("missing rhs", "1 <"),
      ("extra token", "1 < 2 3"),
      ("same chain", "1 < 2 < 3"),
      ("mixed eq then lt", "1 == 2 < 3"),
      ("mixed lt then ne", "1 < 2 != 3"),
      ("mixed ne then lt", "1 != 2 < 3"),
      ("mixed lt then eq", "1 < 2 == 3")
    ] do
    let source := returnProgramSource "RejectedLtShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<lt-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including Bool operands).
  match Compiler.compile (twin (.lessThan (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "less-than comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject lessThan with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing lessThan"

  match Compiler.compile
      (twin (.lessThan (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "less-than comparison is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true<false with less-than message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true<false programs"

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

end Tests.Language.LessThan
