import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- CheckedModSurface pins binary `%` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
-- Migrated positives: `2 % 3` / `(2 % 3)` from CheckedMul, Grouping, and CheckedDiv.
namespace Tests.Language.CheckedModFixture

open ProofForgeV2.Language

program CheckedModSurface where
  init() do
    let seed : UInt64 := 7 % 3
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a % b

  view peek() : UInt64 do
    let value := (1 + 2) % 3
    return value

  fn helper() : UInt64 do
    return 2 * 7 % 3

end Tests.Language.CheckedModFixture

namespace Tests.Language.CheckedMod

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.CheckedModFixture.CheckedModTwin" "CheckedModTwin" #[
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
  "namespace Tests.Language.CheckedModFixture\n\n" ++
  "program CheckedModSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 7 % 3\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a % b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := (1 + 2) % 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 2 * 7 % 3\n\n" ++
  "end Tests.Language.CheckedModFixture\n"

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
  let elaborated := Tests.Language.CheckedModFixture.CheckedModSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.checkedMod (.literal 7) (.literal 3)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 7 % 3"
  | none => throw <| IO.userError "CheckedModSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.checkedMod (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a % b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.checkedMod (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := (1 + 2) % 3"
  | _ => throw <| IO.userError "CheckedModSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.checkedMod (.checkedMul (.literal 2) (.literal 7)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 2 * 7 % 3"
  | _ => throw <| IO.userError "CheckedModSurface must retain helper fn"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<checked-mod>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same checkedMod Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same checkedMod sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze.
  let mod73 ← select session (returnProgramSource "Mod73" "7 % 3") "<mod-7-3>"
  expectReturnExpr "7 % 3" mod73 (.checkedMod (.literal 7) (.literal 3))

  let mod37 ← select session (returnProgramSource "Mod37" "3 % 7") "<mod-3-7>"
  expectReturnExpr "3 % 7" mod37 (.checkedMod (.literal 3) (.literal 7))

  let modAB ← select session (varReturnProgramSource "ModAB" "a % b") "<mod-a-b>"
  expectReturnExpr "a % b" modAB (.checkedMod (.variable "a") (.variable "b"))

  let addMod ← select session (returnProgramSource "AddMod" "1 + 7 % 3") "<add-mod>"
  expectReturnExpr "1 + 7 % 3" addMod
    (.checkedAdd (.literal 1) (.checkedMod (.literal 7) (.literal 3)))

  let modAdd ← select session (returnProgramSource "ModAdd" "7 % 3 + 1") "<mod-add>"
  expectReturnExpr "7 % 3 + 1" modAdd
    (.checkedAdd (.checkedMod (.literal 7) (.literal 3)) (.literal 1))

  let modSub ← select session (returnProgramSource "ModSub" "7 % 3 - 1") "<mod-sub>"
  expectReturnExpr "7 % 3 - 1" modSub
    (.checkedSub (.checkedMod (.literal 7) (.literal 3)) (.literal 1))

  let leftChain ← select session (returnProgramSource "LeftChain" "7 % 3 % 2") "<mod-left>"
  expectReturnExpr "7 % 3 % 2" leftChain
    (.checkedMod (.checkedMod (.literal 7) (.literal 3)) (.literal 2))

  let rightNest ← select session
    (returnProgramSource "RightNest" "7 % (3 % 2)") "<mod-right>"
  expectReturnExpr "7 % (3 % 2)" rightNest
    (.checkedMod (.literal 7) (.checkedMod (.literal 3) (.literal 2)))

  let mulMod ← select session (returnProgramSource "MulMod" "2 * 7 % 3") "<mul-mod>"
  expectReturnExpr "2 * 7 % 3" mulMod
    (.checkedMod (.checkedMul (.literal 2) (.literal 7)) (.literal 3))

  let mulOfMod ← select session
    (returnProgramSource "MulOfMod" "2 * (7 % 3)") "<mul-of-mod>"
  expectReturnExpr "2 * (7 % 3)" mulOfMod
    (.checkedMul (.literal 2) (.checkedMod (.literal 7) (.literal 3)))

  let modMul ← select session (returnProgramSource "ModMul" "7 % 3 * 2") "<mod-mul>"
  expectReturnExpr "7 % 3 * 2" modMul
    (.checkedMul (.checkedMod (.literal 7) (.literal 3)) (.literal 2))

  let divMod ← select session (returnProgramSource "DivMod" "8 / 4 % 2") "<div-mod>"
  expectReturnExpr "8 / 4 % 2" divMod
    (.checkedMod (.checkedDiv (.literal 8) (.literal 4)) (.literal 2))

  let modDiv ← select session (returnProgramSource "ModDiv" "8 % 4 / 2") "<mod-div>"
  expectReturnExpr "8 % 4 / 2" modDiv
    (.checkedDiv (.checkedMod (.literal 8) (.literal 4)) (.literal 2))

  let groupMod ← select session
    (returnProgramSource "GroupMod" "(1 + 2) % 3") "<group-mod>"
  expectReturnExpr "(1 + 2) % 3" groupMod
    (.checkedMod (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negMod ← select session (returnProgramSource "NegMod" "-8 % 3") "<neg-mod>"
  expectReturnExpr "-8 % 3" negMod
    (.checkedMod (.checkedNeg (.literal 8)) (.literal 3))

  let modNeg ← select session (returnProgramSource "ModNeg" "8 % -3") "<mod-neg>"
  expectReturnExpr "8 % -3" modNeg
    (.checkedMod (.literal 8) (.checkedNeg (.literal 3)))

  let modZero ← select session (returnProgramSource "ModZero" "8 % 0") "<mod-zero>"
  expectReturnExpr "8 % 0" modZero
    (.checkedMod (.literal 8) (.literal 0))

  -- Migrated positives from temporary percent negatives (4 entries / 3 suites).
  let migrated23 ← select session (returnProgramSource "Migrated23" "2 % 3") "<migrated-2-3>"
  expectReturnExpr "2 % 3" migrated23 (.checkedMod (.literal 2) (.literal 3))
  let migratedGroup ← select session
    (returnProgramSource "MigratedGroup" "(2 % 3)") "<migrated-group-2-3>"
  expectReturnExpr "(2 % 3)" migratedGroup (.checkedMod (.literal 2) (.literal 3))

  -- Same-identity desugar: (7 % 3) == 7 % 3.
  let bareEq ← select session (returnProgramSource "ModEq" "7 % 3") "<mod-eq-bare>"
  let groupEq ← select session (returnProgramSource "ModEq" "(7 % 3)") "<mod-eq-group>"
  expect (bareEq == groupEq)
    "7 % 3 and (7 % 3) must share Source.Program under identical identity"
  expect (bareEq.canonicalBytes == groupEq.canonicalBytes)
    "7 % 3 and (7 % 3) must share canonical bytes under identical identity"
  expect (bareEq.sourceHash == groupEq.sourceHash)
    "7 % 3 and (7 % 3) must share sourceHash under identical identity"

  -- Frozen prospective goldens for CheckedModTwin (Expr tag 11 + lhs/rhs).
  let twin73 := twin (.checkedMod (.literal 7) (.literal 3))
  let twin37 := twin (.checkedMod (.literal 3) (.literal 7))
  let twinMul73 := twin (.checkedMul (.literal 7) (.literal 3))
  let twinDiv73 := twin (.checkedDiv (.literal 7) (.literal 3))
  let twinSub73 := twin (.checkedSub (.literal 7) (.literal 3))
  let twinAddMod := twin
    (.checkedAdd (.literal 1) (.checkedMod (.literal 7) (.literal 3)))
  let twinModAdd := twin
    (.checkedAdd (.checkedMod (.literal 7) (.literal 3)) (.literal 1))
  let twinModSub := twin
    (.checkedSub (.checkedMod (.literal 7) (.literal 3)) (.literal 1))
  let twinLeft := twin
    (.checkedMod (.checkedMod (.literal 7) (.literal 3)) (.literal 2))
  let twinRight := twin
    (.checkedMod (.literal 7) (.checkedMod (.literal 3) (.literal 2)))
  let twinMulMod := twin
    (.checkedMod (.checkedMul (.literal 2) (.literal 7)) (.literal 3))
  let twinMulOfMod := twin
    (.checkedMul (.literal 2) (.checkedMod (.literal 7) (.literal 3)))
  let twinModMul := twin
    (.checkedMul (.checkedMod (.literal 7) (.literal 3)) (.literal 2))
  let twinDivMod := twin
    (.checkedMod (.checkedDiv (.literal 8) (.literal 4)) (.literal 2))
  let twinModDiv := twin
    (.checkedDiv (.checkedMod (.literal 8) (.literal 4)) (.literal 2))
  let twinGroup := twin
    (.checkedMod (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinNegMod := twin
    (.checkedMod (.checkedNeg (.literal 8)) (.literal 3))
  let twinModNeg := twin
    (.checkedMod (.literal 8) (.checkedNeg (.literal 3)))
  let twinModZero := twin (.checkedMod (.literal 8) (.literal 0))
  let twin23 := twin (.checkedMod (.literal 2) (.literal 3))

  expect (twin73.sourceHash ==
      "27734454ca6f13690f578919cd0a6a801b52d0c022075138380b12667de799ce")
    s!"checkedMod 7%3 CheckedModTwin sourceHash golden must remain stable; got {twin73.sourceHash}"
  expect (twin73.canonicalBytes.size == 228)
    s!"checkedMod 7%3 CheckedModTwin size golden must remain stable; got {twin73.canonicalBytes.size}"
  expect (twin37.sourceHash ==
      "ed0965b100295c4cabbd06abe3ed9aa2511015c53ea6a7bdb4ac1580d1f65cd5")
    s!"checkedMod 3%7 CheckedModTwin sourceHash golden must remain stable; got {twin37.sourceHash}"
  expect (twin37.canonicalBytes.size == 228)
    s!"checkedMod 3%7 CheckedModTwin size golden must remain stable; got {twin37.canonicalBytes.size}"
  expect (twinMul73.sourceHash ==
      "1fa94ff49380afb95bb44465df0c36527cd5d277b7646f8a58772f9040ee52c4")
    s!"checkedMul 7*3 control sourceHash golden must remain stable; got {twinMul73.sourceHash}"
  expect (twinMul73.canonicalBytes.size == 228)
    s!"checkedMul 7*3 control size golden must remain stable; got {twinMul73.canonicalBytes.size}"
  expect (twinDiv73.sourceHash ==
      "48c7b8ca298769afdc5fd40e01697b1102761d6dbb3aa7a00abe15d6917c86b2")
    s!"checkedDiv 7/3 control sourceHash golden must remain stable; got {twinDiv73.sourceHash}"
  expect (twinDiv73.canonicalBytes.size == 228)
    s!"checkedDiv 7/3 control size golden must remain stable; got {twinDiv73.canonicalBytes.size}"
  expect (twinSub73.sourceHash ==
      "cdcfd5ddd5ee490f6221abc82a2c7aa60647dcd8eb40e661d9d587675f48dc32")
    s!"checkedSub 7-3 control sourceHash golden must remain stable; got {twinSub73.sourceHash}"
  expect (twinSub73.canonicalBytes.size == 228)
    s!"checkedSub 7-3 control size golden must remain stable; got {twinSub73.canonicalBytes.size}"
  expect (twinAddMod.sourceHash ==
      "018dd2e8a46d08659a3160a90c9ae2192daa83e0321694a52a3553f23bc6c430")
    s!"1+7%3 CheckedModTwin sourceHash golden must remain stable; got {twinAddMod.sourceHash}"
  expect (twinAddMod.canonicalBytes.size == 238)
    s!"1+7%3 CheckedModTwin size golden must remain stable; got {twinAddMod.canonicalBytes.size}"
  expect (twinModAdd.sourceHash ==
      "ae2956e31d2142f6a6df712a49e7fa2b9fcfcb775e43a398802e6da4e1838688")
    s!"7%3+1 CheckedModTwin sourceHash golden must remain stable; got {twinModAdd.sourceHash}"
  expect (twinModAdd.canonicalBytes.size == 238)
    s!"7%3+1 CheckedModTwin size golden must remain stable; got {twinModAdd.canonicalBytes.size}"
  expect (twinModSub.sourceHash ==
      "f64222c7725ed34020a743243526a953b56139e5933410395ab2a4d5944f00a0")
    s!"7%3-1 CheckedModTwin sourceHash golden must remain stable; got {twinModSub.sourceHash}"
  expect (twinModSub.canonicalBytes.size == 238)
    s!"7%3-1 CheckedModTwin size golden must remain stable; got {twinModSub.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "c65ffab1f8bba66aaf900eeb8895e4d2f6e3fc901e2176c72595949df7dc41d1")
    s!"left 7%3%2 CheckedModTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 238)
    s!"left 7%3%2 CheckedModTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "d35012b51a215db44c7fb358add004febf5838cccdb9b84f2179f143e174c019")
    s!"right 7%(3%2) CheckedModTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 238)
    s!"right 7%(3%2) CheckedModTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinMulMod.sourceHash ==
      "6f083d1cc04c3668be09951f8f0d4d49b40b9c5ec195204e9caf40103029c2d2")
    s!"2*7%3 CheckedModTwin sourceHash golden must remain stable; got {twinMulMod.sourceHash}"
  expect (twinMulMod.canonicalBytes.size == 238)
    s!"2*7%3 CheckedModTwin size golden must remain stable; got {twinMulMod.canonicalBytes.size}"
  expect (twinMulOfMod.sourceHash ==
      "e171ff4ed998b14f97b3e85b27b0d7691c7f652813c7631b451f75d14ce1a013")
    s!"2*(7%3) CheckedModTwin sourceHash golden must remain stable; got {twinMulOfMod.sourceHash}"
  expect (twinMulOfMod.canonicalBytes.size == 238)
    s!"2*(7%3) CheckedModTwin size golden must remain stable; got {twinMulOfMod.canonicalBytes.size}"
  expect (twinModMul.sourceHash ==
      "5c020bbe60f6d56a1c2e7891a9b16b8ae2826859470905a62f1a09d77f4f39c1")
    s!"7%3*2 CheckedModTwin sourceHash golden must remain stable; got {twinModMul.sourceHash}"
  expect (twinModMul.canonicalBytes.size == 238)
    s!"7%3*2 CheckedModTwin size golden must remain stable; got {twinModMul.canonicalBytes.size}"
  expect (twinDivMod.sourceHash ==
      "d850ef57e1a45f769e9747301ef189252c00a3db216b28dace96351e3c84baca")
    s!"8/4%2 CheckedModTwin sourceHash golden must remain stable; got {twinDivMod.sourceHash}"
  expect (twinDivMod.canonicalBytes.size == 238)
    s!"8/4%2 CheckedModTwin size golden must remain stable; got {twinDivMod.canonicalBytes.size}"
  expect (twinModDiv.sourceHash ==
      "52e37ff3ad2137c27461d313f470d8f827df35d67feda4a8fbb7b62e73c7df64")
    s!"8%4/2 CheckedModTwin sourceHash golden must remain stable; got {twinModDiv.sourceHash}"
  expect (twinModDiv.canonicalBytes.size == 238)
    s!"8%4/2 CheckedModTwin size golden must remain stable; got {twinModDiv.canonicalBytes.size}"
  expect (twinGroup.sourceHash ==
      "a4b706a72f14bd4ca2f3099615a28e16f30d4c58b688b72b0df6c69f1c0534d0")
    s!"(1+2)%3 CheckedModTwin sourceHash golden must remain stable; got {twinGroup.sourceHash}"
  expect (twinGroup.canonicalBytes.size == 238)
    s!"(1+2)%3 CheckedModTwin size golden must remain stable; got {twinGroup.canonicalBytes.size}"
  expect (twinNegMod.sourceHash ==
      "ae40122f64169a918a01dc2dea320a2bd3886f7aca093d378157e3dd80db03d6")
    s!"-8%3 CheckedModTwin sourceHash golden must remain stable; got {twinNegMod.sourceHash}"
  expect (twinNegMod.canonicalBytes.size == 229)
    s!"-8%3 CheckedModTwin size golden must remain stable; got {twinNegMod.canonicalBytes.size}"
  expect (twinModNeg.sourceHash ==
      "300a38f1ea740050ee94135e1b61ae3d4789510106312999c23d72c6008ebd27")
    s!"8%-3 CheckedModTwin sourceHash golden must remain stable; got {twinModNeg.sourceHash}"
  expect (twinModNeg.canonicalBytes.size == 229)
    s!"8%-3 CheckedModTwin size golden must remain stable; got {twinModNeg.canonicalBytes.size}"
  expect (twinModZero.sourceHash ==
      "4fff7a5bdc1482ae4ffa706dda1c9aad5dacc62788ae389427ca37a6e6bd2a9f")
    s!"8%0 CheckedModTwin sourceHash golden must remain stable; got {twinModZero.sourceHash}"
  expect (twinModZero.canonicalBytes.size == 228)
    s!"8%0 CheckedModTwin size golden must remain stable; got {twinModZero.canonicalBytes.size}"
  expect (twin23.sourceHash ==
      "6e84d4d6cd67e9324a771bfb97219edd05fb8acef1189f4ba456389792490e42")
    s!"migrated 2%3 CheckedModTwin sourceHash golden must remain stable; got {twin23.sourceHash}"
  expect (twin23.canonicalBytes.size == 228)
    s!"migrated 2%3 CheckedModTwin size golden must remain stable; got {twin23.canonicalBytes.size}"

  -- Non-alias controls.
  expect (twin73.sourceHash != twinMul73.sourceHash)
    "checkedMod 7%3 must not alias checkedMul 7*3 (operator tag)"
  expect (twin73.sourceHash != twinDiv73.sourceHash)
    "checkedMod 7%3 must not alias checkedDiv 7/3 (operator tag)"
  expect (twin73.sourceHash != twinSub73.sourceHash)
    "checkedMod 7%3 must not alias checkedSub 7-3 (operator tag)"
  expect (twin73.canonicalBytes.size == twinMul73.canonicalBytes.size)
    "checkedMod and checkedMul of same operands must share size (tag-only distinction)"
  expect (twin73.sourceHash != twin37.sourceHash)
    "checkedMod 7%3 must not alias 3%7 (operand order)"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested checkedMod must not alias"
  expect (twinMulMod.sourceHash != twinMulOfMod.sourceHash)
    "2*7%3 must not alias 2*(7%3)"
  expect (twinAddMod.sourceHash != twinModAdd.sourceHash)
    "1+7%3 must not alias 7%3+1"
  expect (twinDivMod.sourceHash != twinModDiv.sourceHash)
    "8/4%2 must not alias 8%4/2 (cross */%// order)"
  expect (twinNegMod.sourceHash != twinModNeg.sourceHash)
    "-8%3 must not alias 8%-3 (unary placement)"
  expect (twin73.sourceHash != twinModZero.sourceHash)
    "7%3 must not alias 8%0 (zero modulus accepted as distinct AST)"

  -- Parser-boundary malformed shapes.
  for (label, expr) in [
      ("bare percent", "%"),
      ("missing lhs", "% 3"),
      ("missing rhs", "7 %"),
      ("repeated percent spaced", "7 % % 3"),
      ("double percent token", "2 %% 3"),
      ("extra token", "7 % 3 2")
    ] do
    let source := returnProgramSource "RejectedModShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<mod-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.checkedMod (.literal 7) (.literal 3))) with
  | .error (.invalidProgram
      "checked modulo is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject checkedMod with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing checkedMod"

  match Compiler.compile (twin (.checkedMod (.literal 8) (.literal 0))) with
  | .error (.invalidProgram
      "checked modulo is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject 8%0 with exact mod message before operand rules, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept 8%0 programs"

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

  match Compiler.compile (twin (.checkedSub (.literal 7) (.literal 3))) with
  | .error (.invalidProgram
      "checked subtraction is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedSub must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedSub twin must remain Typed fail-closed"

  match Compiler.compile (twin (.checkedMul (.literal 7) (.literal 3))) with
  | .error (.invalidProgram
      "checked multiplication is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedMul must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedMul twin must remain Typed fail-closed"

  match Compiler.compile (twin (.checkedDiv (.literal 7) (.literal 3))) with
  | .error (.invalidProgram
      "checked division is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"checkedDiv must retain exact fail-closed diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "checkedDiv twin must remain Typed fail-closed"

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

end Tests.Language.CheckedMod
