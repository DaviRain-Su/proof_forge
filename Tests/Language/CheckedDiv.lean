import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- CheckedDivSurface pins binary `/` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
-- Migrated positives: `2 / 3` (from CheckedMul) and `(2 / 3)` (from Grouping).
namespace Tests.Language.CheckedDivFixture

open ProofForgeV2.Language

program CheckedDivSurface where
  init() do
    let seed : UInt64 := 6 / 3
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a / b

  view peek() : UInt64 do
    let value := (1 + 2) / 3
    return value

  fn helper() : UInt64 do
    return 2 * 6 / 3

end Tests.Language.CheckedDivFixture

namespace Tests.Language.CheckedDiv

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedDivFixture.CheckedDivTwin" "CheckedDivTwin" #[
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
  "namespace Tests.Language.CheckedDivFixture\n\n" ++
  "program CheckedDivSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 6 / 3\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a / b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := (1 + 2) / 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 2 * 6 / 3\n\n" ++
  "end Tests.Language.CheckedDivFixture\n"

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
  let elaborated := Tests.Language.CheckedDivFixture.CheckedDivSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.checkedDiv (.literal 6) (.literal 3)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 6 / 3"
  | none => throw <| IO.userError "CheckedDivSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.checkedDiv (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a / b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.checkedDiv (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := (1 + 2) / 3"
  | _ => throw <| IO.userError "CheckedDivSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.checkedDiv (.checkedMul (.literal 2) (.literal 6)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 2 * 6 / 3"
  | _ => throw <| IO.userError "CheckedDivSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<checked-div>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same checkedDiv Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same checkedDiv sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (including migrated 2/3 and (2/3)).
  let div63 ← select session (returnProgramSource "Div63" "6 / 3") "<div-6-3>"
  expectReturnExpr "6 / 3" div63 (.checkedDiv (.literal 6) (.literal 3))

  let div36 ← select session (returnProgramSource "Div36" "3 / 6") "<div-3-6>"
  expectReturnExpr "3 / 6" div36 (.checkedDiv (.literal 3) (.literal 6))

  let divAB ← select session (varReturnProgramSource "DivAB" "a / b") "<div-a-b>"
  expectReturnExpr "a / b" divAB (.checkedDiv (.variable "a") (.variable "b"))

  let addDiv ← select session (returnProgramSource "AddDiv" "1 + 6 / 3") "<add-div>"
  expectReturnExpr "1 + 6 / 3" addDiv
    (.checkedAdd (.literal 1) (.checkedDiv (.literal 6) (.literal 3)))

  let divAdd ← select session (returnProgramSource "DivAdd" "6 / 3 + 1") "<div-add>"
  expectReturnExpr "6 / 3 + 1" divAdd
    (.checkedAdd (.checkedDiv (.literal 6) (.literal 3)) (.literal 1))

  let leftChain ← select session (returnProgramSource "LeftChain" "6 / 3 / 2") "<div-left>"
  expectReturnExpr "6 / 3 / 2" leftChain
    (.checkedDiv (.checkedDiv (.literal 6) (.literal 3)) (.literal 2))

  let rightNest ← select session
    (returnProgramSource "RightNest" "6 / (3 / 2)") "<div-right>"
  expectReturnExpr "6 / (3 / 2)" rightNest
    (.checkedDiv (.literal 6) (.checkedDiv (.literal 3) (.literal 2)))

  let mulDiv ← select session (returnProgramSource "MulDiv" "2 * 6 / 3") "<mul-div>"
  expectReturnExpr "2 * 6 / 3" mulDiv
    (.checkedDiv (.checkedMul (.literal 2) (.literal 6)) (.literal 3))

  let mulOfDiv ← select session
    (returnProgramSource "MulOfDiv" "2 * (6 / 3)") "<mul-of-div>"
  expectReturnExpr "2 * (6 / 3)" mulOfDiv
    (.checkedMul (.literal 2) (.checkedDiv (.literal 6) (.literal 3)))

  let groupDiv ← select session
    (returnProgramSource "GroupDiv" "(1 + 2) / 3") "<group-div>"
  expectReturnExpr "(1 + 2) / 3" groupDiv
    (.checkedDiv (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let divMul ← select session (returnProgramSource "DivMul" "8 / 4 * 2") "<div-mul>"
  expectReturnExpr "8 / 4 * 2" divMul
    (.checkedMul (.checkedDiv (.literal 8) (.literal 4)) (.literal 2))

  let divSub ← select session (returnProgramSource "DivSub" "8 / 4 - 2") "<div-sub>"
  expectReturnExpr "8 / 4 - 2" divSub
    (.checkedSub (.checkedDiv (.literal 8) (.literal 4)) (.literal 2))

  let negDiv ← select session (returnProgramSource "NegDiv" "-8 / 4") "<neg-div>"
  expectReturnExpr "-8 / 4" negDiv
    (.checkedDiv (.checkedNeg (.literal 8)) (.literal 4))

  let divNeg ← select session (returnProgramSource "DivNeg" "8 / -4") "<div-neg>"
  expectReturnExpr "8 / -4" divNeg
    (.checkedDiv (.literal 8) (.checkedNeg (.literal 4)))

  let divZero ← select session (returnProgramSource "DivZero" "8 / 0") "<div-zero>"
  expectReturnExpr "8 / 0" divZero
    (.checkedDiv (.literal 8) (.literal 0))

  -- Migrated positives from temporary slash negatives.
  let migrated23 ← select session (returnProgramSource "Migrated23" "2 / 3") "<migrated-2-3>"
  expectReturnExpr "2 / 3" migrated23 (.checkedDiv (.literal 2) (.literal 3))
  let migratedGroup ← select session
    (returnProgramSource "MigratedGroup" "(2 / 3)") "<migrated-group-2-3>"
  expectReturnExpr "(2 / 3)" migratedGroup (.checkedDiv (.literal 2) (.literal 3))

  -- Same-identity desugar: (6 / 3) == 6 / 3.
  let bareEq ← select session (returnProgramSource "DivEq" "6 / 3") "<div-eq-bare>"
  let groupEq ← select session (returnProgramSource "DivEq" "(6 / 3)") "<div-eq-group>"
  expect (bareEq == groupEq)
    "6 / 3 and (6 / 3) must share Source.Program under identical identity"
  expect (bareEq.canonicalBytes == groupEq.canonicalBytes)
    "6 / 3 and (6 / 3) must share canonical bytes under identical identity"
  expect (bareEq.sourceHash == groupEq.sourceHash)
    "6 / 3 and (6 / 3) must share sourceHash under identical identity"

  -- Frozen prospective goldens for CheckedDivTwin (Expr tag 10 + lhs/rhs).
  let twin63 := twin (.checkedDiv (.literal 6) (.literal 3))
  let twin36 := twin (.checkedDiv (.literal 3) (.literal 6))
  let twinMul63 := twin (.checkedMul (.literal 6) (.literal 3))
  let twinSub63 := twin (.checkedSub (.literal 6) (.literal 3))
  let twinAddDiv := twin
    (.checkedAdd (.literal 1) (.checkedDiv (.literal 6) (.literal 3)))
  let twinDivAdd := twin
    (.checkedAdd (.checkedDiv (.literal 6) (.literal 3)) (.literal 1))
  let twinLeft := twin
    (.checkedDiv (.checkedDiv (.literal 6) (.literal 3)) (.literal 2))
  let twinRight := twin
    (.checkedDiv (.literal 6) (.checkedDiv (.literal 3) (.literal 2)))
  let twinMulDiv := twin
    (.checkedDiv (.checkedMul (.literal 2) (.literal 6)) (.literal 3))
  let twinMulOfDiv := twin
    (.checkedMul (.literal 2) (.checkedDiv (.literal 6) (.literal 3)))
  let twinGroup := twin
    (.checkedDiv (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinDivMul := twin
    (.checkedMul (.checkedDiv (.literal 8) (.literal 4)) (.literal 2))
  let twinWrongMulDiv := twin
    (.checkedDiv (.checkedMul (.literal 8) (.literal 4)) (.literal 2))
  let twinDivSub := twin
    (.checkedSub (.checkedDiv (.literal 8) (.literal 4)) (.literal 2))
  let twinNegDiv := twin
    (.checkedDiv (.checkedNeg (.literal 8)) (.literal 4))
  let twinDivNeg := twin
    (.checkedDiv (.literal 8) (.checkedNeg (.literal 4)))
  let twinDivZero := twin (.checkedDiv (.literal 8) (.literal 0))
  let twin23 := twin (.checkedDiv (.literal 2) (.literal 3))

  expect (twin63.sourceHash ==
      "c7b5abc6f7a665e821646195c1c191bd5c79970f56f774824e21d52dbcf0e07c")
    s!"checkedDiv 6/3 CheckedDivTwin sourceHash golden must remain stable; got {twin63.sourceHash}"
  expect (twin63.canonicalBytes.size == 228)
    s!"checkedDiv 6/3 CheckedDivTwin size golden must remain stable; got {twin63.canonicalBytes.size}"
  expect (twin36.sourceHash ==
      "f779a87b512fe81c41e242a971ffae9913f78bf8f6f5add0fca9fb74284a554c")
    s!"checkedDiv 3/6 CheckedDivTwin sourceHash golden must remain stable; got {twin36.sourceHash}"
  expect (twin36.canonicalBytes.size == 228)
    s!"checkedDiv 3/6 CheckedDivTwin size golden must remain stable; got {twin36.canonicalBytes.size}"
  expect (twinMul63.sourceHash ==
      "f790e3b6072afbb7a9a296b2a565639495120054074ec4852913da388c1576c9")
    s!"checkedMul 6*3 control sourceHash golden must remain stable; got {twinMul63.sourceHash}"
  expect (twinMul63.canonicalBytes.size == 228)
    s!"checkedMul 6*3 control size golden must remain stable; got {twinMul63.canonicalBytes.size}"
  expect (twinSub63.sourceHash ==
      "45f398d39cd3fff2183c310c553fe82eb43f2dfdc85eb65e8d163393cffa590f")
    s!"checkedSub 6-3 control sourceHash golden must remain stable; got {twinSub63.sourceHash}"
  expect (twinSub63.canonicalBytes.size == 228)
    s!"checkedSub 6-3 control size golden must remain stable; got {twinSub63.canonicalBytes.size}"
  expect (twinAddDiv.sourceHash ==
      "c353b7542c739eebf05e956620f38332709da58ae0f718ccf93e90837479eb05")
    s!"1+6/3 CheckedDivTwin sourceHash golden must remain stable; got {twinAddDiv.sourceHash}"
  expect (twinAddDiv.canonicalBytes.size == 238)
    s!"1+6/3 CheckedDivTwin size golden must remain stable; got {twinAddDiv.canonicalBytes.size}"
  expect (twinDivAdd.sourceHash ==
      "d710114445d4e9fc581684c211ea33e4c42eba8455c4cae51957e864d30a0745")
    s!"6/3+1 CheckedDivTwin sourceHash golden must remain stable; got {twinDivAdd.sourceHash}"
  expect (twinDivAdd.canonicalBytes.size == 238)
    s!"6/3+1 CheckedDivTwin size golden must remain stable; got {twinDivAdd.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "d5a1c2cbeb3f767be6042af2d401602faabe086f2b41178e5642ea6eeaa1366b")
    s!"left 6/3/2 CheckedDivTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 238)
    s!"left 6/3/2 CheckedDivTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "c3e7034c2330d88024977a8f96f2c961af55c5962add61d39bb0586d8b2cbd9f")
    s!"right 6/(3/2) CheckedDivTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 238)
    s!"right 6/(3/2) CheckedDivTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinMulDiv.sourceHash ==
      "d3122b7fa90528c2fa316ada367b3ff6a6183617e486dbb8c4c2b1fc484a1a65")
    s!"2*6/3 CheckedDivTwin sourceHash golden must remain stable; got {twinMulDiv.sourceHash}"
  expect (twinMulDiv.canonicalBytes.size == 238)
    s!"2*6/3 CheckedDivTwin size golden must remain stable; got {twinMulDiv.canonicalBytes.size}"
  expect (twinMulOfDiv.sourceHash ==
      "8dbed2ebe25abc8c3d324100be331619321e0b4bfa987c263537c7816cdc5b6f")
    s!"2*(6/3) CheckedDivTwin sourceHash golden must remain stable; got {twinMulOfDiv.sourceHash}"
  expect (twinMulOfDiv.canonicalBytes.size == 238)
    s!"2*(6/3) CheckedDivTwin size golden must remain stable; got {twinMulOfDiv.canonicalBytes.size}"
  expect (twinGroup.sourceHash ==
      "adaaaab1ce8a76c3d53545c7ee356be572e49480afc5514de1ecabe8f1a1aabb")
    s!"(1+2)/3 CheckedDivTwin sourceHash golden must remain stable; got {twinGroup.sourceHash}"
  expect (twinGroup.canonicalBytes.size == 238)
    s!"(1+2)/3 CheckedDivTwin size golden must remain stable; got {twinGroup.canonicalBytes.size}"
  expect (twinDivMul.sourceHash ==
      "b8aa2e8fd0664751291b9fcf2f5c8c9738d126daaecd23ace326c88409599f4f")
    s!"8/4*2 CheckedDivTwin sourceHash golden must remain stable; got {twinDivMul.sourceHash}"
  expect (twinDivMul.canonicalBytes.size == 238)
    s!"8/4*2 CheckedDivTwin size golden must remain stable; got {twinDivMul.canonicalBytes.size}"
  expect (twinDivSub.sourceHash ==
      "1184b49536e2dc85fa4ff44c9b7949671ded7c3a641cc7041cd982e3245ce998")
    s!"8/4-2 CheckedDivTwin sourceHash golden must remain stable; got {twinDivSub.sourceHash}"
  expect (twinDivSub.canonicalBytes.size == 238)
    s!"8/4-2 CheckedDivTwin size golden must remain stable; got {twinDivSub.canonicalBytes.size}"
  expect (twinNegDiv.sourceHash ==
      "ca1ac95f05572c042efeab1a5a30e4d77a7c26c451c7c41b2637b32fa4d3c55d")
    s!"-8/4 CheckedDivTwin sourceHash golden must remain stable; got {twinNegDiv.sourceHash}"
  expect (twinNegDiv.canonicalBytes.size == 229)
    s!"-8/4 CheckedDivTwin size golden must remain stable; got {twinNegDiv.canonicalBytes.size}"
  expect (twinDivNeg.sourceHash ==
      "8e9ff4cd467933212011fd4953b5d2ac560f0cab306ac65aa09a5226f595693b")
    s!"8/-4 CheckedDivTwin sourceHash golden must remain stable; got {twinDivNeg.sourceHash}"
  expect (twinDivNeg.canonicalBytes.size == 229)
    s!"8/-4 CheckedDivTwin size golden must remain stable; got {twinDivNeg.canonicalBytes.size}"
  expect (twinDivZero.sourceHash ==
      "cde97577aecae8a24075bab611c3bbe6053149149fc4a9147c2eb68352a0a12b")
    s!"8/0 CheckedDivTwin sourceHash golden must remain stable; got {twinDivZero.sourceHash}"
  expect (twinDivZero.canonicalBytes.size == 228)
    s!"8/0 CheckedDivTwin size golden must remain stable; got {twinDivZero.canonicalBytes.size}"
  expect (twin23.sourceHash ==
      "0d38cb17ac24ed48bfa9139af1a7af1629439a8d53c9ed824e77f185b8806c68")
    s!"migrated 2/3 CheckedDivTwin sourceHash golden must remain stable; got {twin23.sourceHash}"
  expect (twin23.canonicalBytes.size == 228)
    s!"migrated 2/3 CheckedDivTwin size golden must remain stable; got {twin23.canonicalBytes.size}"

  -- Non-alias controls.
  expect (twin63.sourceHash != twinMul63.sourceHash)
    "checkedDiv 6/3 must not alias checkedMul 6*3 (operator tag)"
  expect (twin63.sourceHash != twinSub63.sourceHash)
    "checkedDiv 6/3 must not alias checkedSub 6-3 (operator tag)"
  expect (twin63.canonicalBytes.size == twinMul63.canonicalBytes.size)
    "checkedDiv and checkedMul of same operands must share size (tag-only distinction)"
  expect (twin63.sourceHash != twin36.sourceHash)
    "checkedDiv 6/3 must not alias 3/6 (operand order)"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested checkedDiv must not alias"
  expect (twinMulDiv.sourceHash != twinMulOfDiv.sourceHash)
    "2*6/3 must not alias 2*(6/3)"
  expect (twinAddDiv.sourceHash != twinDivAdd.sourceHash)
    "1+6/3 must not alias 6/3+1"
  expect (twinDivMul.sourceHash != twinWrongMulDiv.sourceHash)
    "8/4*2 must not alias wrong div(mul(8,4),2)"
  expect (twinNegDiv.sourceHash != twinDivNeg.sourceHash)
    "-8/4 must not alias 8/-4 (unary placement)"
  expect (twin63.sourceHash != twinDivZero.sourceHash)
    "6/3 must not alias 8/0 (literal-zero denominator accepted as distinct AST)"

  -- Parser-boundary malformed shapes; percent remains rejected.
  for (label, expr) in [
      ("bare slash", "/"),
      ("missing lhs", "/ 3"),
      ("missing rhs", "6 /"),
      ("repeated slash spaced", "6 / / 3"),
      ("double slash token", "2 // 3"),
      ("extra token", "6 / 3 2"),
      ("percent modulo", "2 % 3"),
      ("grouped percent", "(2 % 3)")
    ] do
    let source := returnProgramSource "RejectedDivShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<div-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.checkedDiv (.literal 6) (.literal 3))) with
  | .error (.invalidProgram
      "checked division is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject checkedDiv with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing checkedDiv"

  -- Fail-before-operands: zero denominator still hits div diagnostic first.
  match Compiler.compile (twin (.checkedDiv (.literal 8) (.literal 0))) with
  | .error (.invalidProgram
      "checked division is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject 8/0 with exact div message before operand rules, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept 8/0 programs"

  match Compiler.compile (twin (.checkedAdd (.literal 2) (.literal 3))) with
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

  match Compiler.compile (twin (.checkedSub (.literal 6) (.literal 3))) with
  | .error (.invalidProgram
      "checked subtraction is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedSub must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedSub twin must remain Typed fail-closed"

  match Compiler.compile (twin (.checkedMul (.literal 6) (.literal 3))) with
  | .error (.invalidProgram
      "checked multiplication is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedMul must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedMul twin must remain Typed fail-closed"

  match Compiler.compile (twin (.checkedNeg (.literal 2))) with
  | .error (.invalidProgram
      "checked negation is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedNeg must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedNeg twin must remain Typed fail-closed"

  match Compiler.compile (twin (.bitwiseNot (.literal 2))) with
  | .error (.invalidProgram
      "bitwise not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"bitwiseNot must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "bitwiseNot twin must remain Typed fail-closed"

  match Compiler.compile (twin (.logicalNot (.literal 2))) with
  | .error (.invalidProgram
      "logical not is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"logicalNot must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "logicalNot twin must remain Typed fail-closed"

end Tests.Language.CheckedDiv
