import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- EqualSurface pins binary `==` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
-- Zero migration: no existing == negatives; LogicalNot 1 != 2 retention stays untouched.
namespace Tests.Language.EqualFixture

open ProofForgeV2.Language

program EqualSurface where
  init() do
    let seed : UInt64 := 1 == 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a == b

  view peek() : UInt64 do
    let value := 1 + 2 == 3
    return value

  fn helper() : UInt64 do
    return true == false

end Tests.Language.EqualFixture

namespace Tests.Language.Equal

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.EqualFixture.EqualTwin" "EqualTwin" #[
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
  "namespace Tests.Language.EqualFixture\n\n" ++
  "program EqualSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 == 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a == b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 == 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true == false\n\n" ++
  "end Tests.Language.EqualFixture\n"

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
  let elaborated := Tests.Language.EqualFixture.EqualSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.equal (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 == 2"
  | none => throw <| IO.userError "EqualSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.equal (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a == b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.equal (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 == 3 as (1+2)==3"
  | _ => throw <| IO.userError "EqualSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.equal (.boolLiteral true) (.boolLiteral false))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return true == false"
  | _ => throw <| IO.userError "EqualSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<equal>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same equal Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same equal sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 50 non-assoc, both operand slots 51).
  let eq12 ← select session (returnProgramSource "Eq12" "1 == 2") "<eq-1-2>"
  expectReturnExpr "1 == 2" eq12 (.equal (.literal 1) (.literal 2))

  let eq21 ← select session (returnProgramSource "Eq21" "2 == 1") "<eq-2-1>"
  expectReturnExpr "2 == 1" eq21 (.equal (.literal 2) (.literal 1))

  let eqAB ← select session (varReturnProgramSource "EqAB" "a == b") "<eq-a-b>"
  expectReturnExpr "a == b" eqAB (.equal (.variable "a") (.variable "b"))

  let eqTF ← select session (returnProgramSource "EqTF" "true == false") "<eq-t-f>"
  expectReturnExpr "true == false" eqTF
    (.equal (.boolLiteral true) (.boolLiteral false))

  let eqFT ← select session (returnProgramSource "EqFT" "false == true") "<eq-f-t>"
  expectReturnExpr "false == true" eqFT
    (.equal (.boolLiteral false) (.boolLiteral true))

  let eq00 ← select session (returnProgramSource "Eq00" "0 == 0") "<eq-0-0>"
  expectReturnExpr "0 == 0" eq00 (.equal (.literal 0) (.literal 0))

  let addEq ← select session (returnProgramSource "AddEq" "1 + 2 == 3") "<add-eq>"
  expectReturnExpr "1 + 2 == 3" addEq
    (.equal (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let eqAdd ← select session (returnProgramSource "EqAdd" "1 == 2 + 3") "<eq-add>"
  expectReturnExpr "1 == 2 + 3" eqAdd
    (.equal (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulEq ← select session (returnProgramSource "MulEq" "1 * 2 == 3") "<mul-eq>"
  expectReturnExpr "1 * 2 == 3" mulEq
    (.equal (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let eqMul ← select session (returnProgramSource "EqMul" "1 == 2 * 3") "<eq-mul>"
  expectReturnExpr "1 == 2 * 3" eqMul
    (.equal (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlEq ← select session (returnProgramSource "ShlEq" "1 << 2 == 3") "<shl-eq>"
  expectReturnExpr "1 << 2 == 3" shlEq
    (.equal (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let eqShl ← select session (returnProgramSource "EqShl" "1 == 2 << 3") "<eq-shl>"
  expectReturnExpr "1 == 2 << 3" eqShl
    (.equal (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrEq ← select session (returnProgramSource "ShrEq" "1 >> 2 == 3") "<shr-eq>"
  expectReturnExpr "1 >> 2 == 3" shrEq
    (.equal (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let eqShr ← select session (returnProgramSource "EqShr" "1 == 2 >> 3") "<eq-shr>"
  expectReturnExpr "1 == 2 >> 3" eqShr
    (.equal (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let groupEq ← select session
    (returnProgramSource "GroupEq" "(1 + 2) == 3") "<group-eq>"
  expectReturnExpr "(1 + 2) == 3" groupEq
    (.equal (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negEq ← select session (returnProgramSource "NegEq" "-1 == 2") "<neg-eq>"
  expectReturnExpr "-1 == 2" negEq
    (.equal (.checkedNeg (.literal 1)) (.literal 2))

  let eqNeg ← select session (returnProgramSource "EqNeg" "1 == -2") "<eq-neg>"
  expectReturnExpr "1 == -2" eqNeg
    (.equal (.literal 1) (.checkedNeg (.literal 2)))

  let notEq ← select session
    (returnProgramSource "NotEq" "!true == false") "<not-eq>"
  expectReturnExpr "!true == false" notEq
    (.equal (.logicalNot (.boolLiteral true)) (.boolLiteral false))

  -- Same-identity desugar: (1 == 2) == 1 == 2 under identical program name.
  let bareEq ← select session (returnProgramSource "EqSame" "1 == 2") "<eq-same-bare>"
  let groupSame ← select session
    (returnProgramSource "EqSame" "(1 == 2)") "<eq-same-group>"
  expect (bareEq == groupSame)
    "1 == 2 and (1 == 2) must share Source.Program under identical identity"
  expect (bareEq.canonicalBytes == groupSame.canonicalBytes)
    "1 == 2 and (1 == 2) must share canonical bytes under identical identity"
  expect (bareEq.sourceHash == groupSame.sourceHash)
    "1 == 2 and (1 == 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for EqualTwin (Expr tag 14 + lhs/rhs).
  let twin12 := twin (.equal (.literal 1) (.literal 2))
  let twin21 := twin (.equal (.literal 2) (.literal 1))
  let twinAB := twin (.equal (.variable "a") (.variable "b"))
  let twinTF := twin (.equal (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.equal (.boolLiteral false) (.boolLiteral true))
  let twinTT := twin (.equal (.boolLiteral true) (.boolLiteral true))
  let twin00 := twin (.equal (.literal 0) (.literal 0))
  let twinAddEq := twin
    (.equal (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinEqAdd := twin
    (.equal (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.equal (.literal 2) (.literal 3)))
  let twinMulEq := twin
    (.equal (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinEqMul := twin
    (.equal (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlEq := twin
    (.equal (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinEqShl := twin
    (.equal (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrEq := twin
    (.equal (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinEqShr := twin
    (.equal (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinNegEq := twin
    (.equal (.checkedNeg (.literal 1)) (.literal 2))
  let twinEqNeg := twin
    (.equal (.literal 1) (.checkedNeg (.literal 2)))
  let twinNotEq := twin
    (.equal (.logicalNot (.boolLiteral true)) (.boolLiteral false))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinShl := twin (.shiftLeft (.literal 1) (.literal 2))
  let twinShr := twin (.shiftRight (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "dc5d71dc6b764fe1c3d17de4f59e60d669921ee6fb948e854a62bac9c65ead7a")
    s!"equal 1==2 EqualTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 213)
    s!"equal 1==2 EqualTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "29f5ee40692d2f0221b2b429770357e37455d5979072dfec717c4ef31c1e7abc")
    s!"equal 2==1 EqualTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 213)
    s!"equal 2==1 EqualTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "59673b07cb2dc86afa0e659b7ae8b5c0c664c6e898cd0c4e0360b783aca0f468")
    s!"a==b EqualTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 215)
    s!"a==b EqualTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "0f7470698cfe5876925ac2cc4de1b1514e90d703f936f875707c89a5b267e267")
    s!"true==false EqualTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 199)
    s!"true==false EqualTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "bc6b7fa14fc1b711f8cc2039223901ae9183188bedca14b7aa3e4682ab46844b")
    s!"false==true EqualTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 199)
    s!"false==true EqualTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinTT.sourceHash ==
      "126b084a6a9f680629e8720860e9b89cd2d2e90bd92c24168fadf3ec15025af8")
    s!"true==true EqualTwin sourceHash golden must remain stable; got {twinTT.sourceHash}"
  expect (twinTT.canonicalBytes.size == 199)
    s!"true==true EqualTwin size golden must remain stable; got {twinTT.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "c413794978701597d3f73a13e123ec34c1e02973e5061e2ac73f189a08a9ad99")
    s!"0==0 EqualTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 213)
    s!"0==0 EqualTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinAddEq.sourceHash ==
      "8d5658780fabd716f475bba30fe61ef7080c9b35f39258ade179720808bdbd50")
    s!"1+2==3 EqualTwin sourceHash golden must remain stable; got {twinAddEq.sourceHash}"
  expect (twinAddEq.canonicalBytes.size == 223)
    s!"1+2==3 EqualTwin size golden must remain stable; got {twinAddEq.canonicalBytes.size}"
  expect (twinEqAdd.sourceHash ==
      "3fa79078599a7ca90bf084ce0fcb86239b9df15d131a3aaa73486c0af9fb3995")
    s!"1==2+3 EqualTwin sourceHash golden must remain stable; got {twinEqAdd.sourceHash}"
  expect (twinEqAdd.canonicalBytes.size == 223)
    s!"1==2+3 EqualTwin size golden must remain stable; got {twinEqAdd.canonicalBytes.size}"
  expect (twinMulEq.sourceHash ==
      "3e8667331a9a9833e7490392d0b48f3a691d7233a9a4e8b8a3681c040fd53d69")
    s!"1*2==3 EqualTwin sourceHash golden must remain stable; got {twinMulEq.sourceHash}"
  expect (twinMulEq.canonicalBytes.size == 223)
    s!"1*2==3 EqualTwin size golden must remain stable; got {twinMulEq.canonicalBytes.size}"
  expect (twinEqMul.sourceHash ==
      "6554da9dfb3e49fb8f02d263536596dc5677054f123c233cf9ec78d56f10920b")
    s!"1==2*3 EqualTwin sourceHash golden must remain stable; got {twinEqMul.sourceHash}"
  expect (twinEqMul.canonicalBytes.size == 223)
    s!"1==2*3 EqualTwin size golden must remain stable; got {twinEqMul.canonicalBytes.size}"
  expect (twinShlEq.sourceHash ==
      "a25b46fe7fd84b260ee941f05bf37ac5d5238189e24b2dfc3b0cd9a04c137cd4")
    s!"1<<2==3 EqualTwin sourceHash golden must remain stable; got {twinShlEq.sourceHash}"
  expect (twinShlEq.canonicalBytes.size == 223)
    s!"1<<2==3 EqualTwin size golden must remain stable; got {twinShlEq.canonicalBytes.size}"
  expect (twinEqShl.sourceHash ==
      "f4d5c34af89f2563fc8a8f27a36c2f73798636a1841c143557e8cc5ac14b73e3")
    s!"1==2<<3 EqualTwin sourceHash golden must remain stable; got {twinEqShl.sourceHash}"
  expect (twinEqShl.canonicalBytes.size == 223)
    s!"1==2<<3 EqualTwin size golden must remain stable; got {twinEqShl.canonicalBytes.size}"
  expect (twinShrEq.sourceHash ==
      "0dee172b3debb3d885c4c5d7c2579ee34230d2a89e3e676825507a58465bd4c4")
    s!"1>>2==3 EqualTwin sourceHash golden must remain stable; got {twinShrEq.sourceHash}"
  expect (twinShrEq.canonicalBytes.size == 223)
    s!"1>>2==3 EqualTwin size golden must remain stable; got {twinShrEq.canonicalBytes.size}"
  expect (twinEqShr.sourceHash ==
      "19ca48da2d6fb72d4d005503f54c3be149c8fa92fed209bb8acacb813d408caf")
    s!"1==2>>3 EqualTwin sourceHash golden must remain stable; got {twinEqShr.sourceHash}"
  expect (twinEqShr.canonicalBytes.size == 223)
    s!"1==2>>3 EqualTwin size golden must remain stable; got {twinEqShr.canonicalBytes.size}"
  expect (twinNegEq.sourceHash ==
      "5320410409d44aea214e641cb8028e12bfc7a1bfc76d0d40535a66f02f7996b6")
    s!"-1==2 EqualTwin sourceHash golden must remain stable; got {twinNegEq.sourceHash}"
  expect (twinNegEq.canonicalBytes.size == 214)
    s!"-1==2 EqualTwin size golden must remain stable; got {twinNegEq.canonicalBytes.size}"
  expect (twinEqNeg.sourceHash ==
      "e1e4569967255e0f3728244d6fdd99015cb4e3a45cd3990eec50da5bb593566b")
    s!"1==-2 EqualTwin sourceHash golden must remain stable; got {twinEqNeg.sourceHash}"
  expect (twinEqNeg.canonicalBytes.size == 214)
    s!"1==-2 EqualTwin size golden must remain stable; got {twinEqNeg.canonicalBytes.size}"
  expect (twinNotEq.sourceHash ==
      "34c192b04f6e08c4c48c497db924822257d9da5fe6bc05396e1f296a9a0707e1")
    s!"!true==false EqualTwin sourceHash golden must remain stable; got {twinNotEq.sourceHash}"
  expect (twinNotEq.canonicalBytes.size == 200)
    s!"!true==false EqualTwin size golden must remain stable; got {twinNotEq.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "2d7b2c89a6a2c6aa748def6ee54f733dbca2760ec626148a6cecf3ebed247f5d")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 213)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinShl.sourceHash ==
      "a7bc17d63665001a66480ae62fe39fb32efb877a012b8cd40ac7ca907f3fcb3a")
    s!"shiftLeft 1<<2 control sourceHash golden must remain stable; got {twinShl.sourceHash}"
  expect (twinShl.canonicalBytes.size == 213)
    s!"shiftLeft 1<<2 control size golden must remain stable; got {twinShl.canonicalBytes.size}"
  expect (twinShr.sourceHash ==
      "4b9d4e8dbdd990e9c2a819a7dd1bdc545acdcd0fdd0e08223829b000907d87fd")
    s!"shiftRight 1>>2 control sourceHash golden must remain stable; got {twinShr.sourceHash}"
  expect (twinShr.canonicalBytes.size == 213)
    s!"shiftRight 1>>2 control size golden must remain stable; got {twinShr.canonicalBytes.size}"

  -- Non-alias / precedence / Bool-order discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "equal 1==2 must not alias 2==1 (operand order)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "equal 1==2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.sourceHash != twinShl.sourceHash)
    "equal 1==2 must not alias shiftLeft 1<<2 (operator tag)"
  expect (twin12.sourceHash != twinShr.sourceHash)
    "equal 1==2 must not alias shiftRight 1>>2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinAdd.canonicalBytes.size)
    "equal and checkedAdd of two small literals must share size (tag-only distinction)"
  expect (twinAddEq.sourceHash != twinWrong.sourceHash)
    "1+2==3 must not alias wrong C-style 1+(2==3)"
  expect (twinAddEq.sourceHash != twinEqAdd.sourceHash)
    "1+2==3 must not alias 1==2+3 (lhs/rhs add placement)"
  expect (twinMulEq.sourceHash != twinEqMul.sourceHash)
    "1*2==3 must not alias 1==2*3"
  expect (twinShlEq.sourceHash != twinEqShl.sourceHash)
    "1<<2==3 must not alias 1==2<<3"
  expect (twinShrEq.sourceHash != twinEqShr.sourceHash)
    "1>>2==3 must not alias 1==2>>3"
  expect (twinNegEq.sourceHash != twinEqNeg.sourceHash)
    "-1==2 must not alias 1==-2 (unary placement)"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true==false must not alias false==true (Bool operand order)"
  expect (twinTF.sourceHash != twinTT.sourceHash)
    "true==false must not alias true==true"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0==0 must not alias 1==2"

  -- Parser-boundary malformed / non-assoc / ordering-sibling retention.
  for (label, expr) in [
      ("bare equals", "=="),
      ("missing lhs", "== 2"),
      ("missing rhs", "1 =="),
      ("single equals", "1 = 2"),
      ("spaced split", "1 = = 2"),
      ("triple equals", "1 === 2"),
      ("chained equality", "1 == 2 == 3"),
      ("extra token", "1 == 2 3"),
      ("ordering gt deferred", "1 > 2"),
      ("ordering ge deferred", "1 >= 2")
    ] do
    let source := returnProgramSource "RejectedEqShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<eq-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including Bool operands).
  match Compiler.compile (twin (.equal (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "equality is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject equal with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing equal"

  match Compiler.compile
      (twin (.equal (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "equality is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true==false with equality message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true==false programs"

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

end Tests.Language.Equal
