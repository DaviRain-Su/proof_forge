import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- ShiftLeftSurface pins binary `<<` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
-- Zero migration: no existing << negatives in the suite.
namespace Tests.Language.ShiftLeftFixture

open ProofForgeV2.Language

program ShiftLeftSurface where
  init() do
    let seed : UInt64 := 1 << 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a << b

  view peek() : UInt64 do
    let value := 1 + 2 << 3
    return value

  fn helper() : UInt64 do
    return 1 << 2 << 3

end Tests.Language.ShiftLeftFixture

namespace Tests.Language.ShiftLeft

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ShiftLeftFixture.ShiftLeftTwin" "ShiftLeftTwin" #[
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
  "namespace Tests.Language.ShiftLeftFixture\n\n" ++
  "program ShiftLeftSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 << 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a << b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 << 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 << 2 << 3\n\n" ++
  "end Tests.Language.ShiftLeftFixture\n"

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
  let elaborated := Tests.Language.ShiftLeftFixture.ShiftLeftSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.shiftLeft (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 << 2"
  | none => throw <| IO.userError "ShiftLeftSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.shiftLeft (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a << b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.shiftLeft (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 << 3 as (1+2)<<3"
  | _ => throw <| IO.userError "ShiftLeftSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.shiftLeft (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 << 2 << 3"
  | _ => throw <| IO.userError "ShiftLeftSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<shift-left>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same shiftLeft Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same shiftLeft sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 60/61 vs Add 65 / Mul 70).
  let shl12 ← select session (returnProgramSource "Shl12" "1 << 2") "<shl-1-2>"
  expectReturnExpr "1 << 2" shl12 (.shiftLeft (.literal 1) (.literal 2))

  let shl21 ← select session (returnProgramSource "Shl21" "2 << 1") "<shl-2-1>"
  expectReturnExpr "2 << 1" shl21 (.shiftLeft (.literal 2) (.literal 1))

  let shlAB ← select session (varReturnProgramSource "ShlAB" "a << b") "<shl-a-b>"
  expectReturnExpr "a << b" shlAB (.shiftLeft (.variable "a") (.variable "b"))

  let addShl ← select session (returnProgramSource "AddShl" "1 + 2 << 3") "<add-shl>"
  expectReturnExpr "1 + 2 << 3" addShl
    (.shiftLeft (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let shlAdd ← select session (returnProgramSource "ShlAdd" "1 << 2 + 3") "<shl-add>"
  expectReturnExpr "1 << 2 + 3" shlAdd
    (.shiftLeft (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let shlMul ← select session (returnProgramSource "ShlMul" "8 << 2 * 3") "<shl-mul>"
  expectReturnExpr "8 << 2 * 3" shlMul
    (.shiftLeft (.literal 8) (.checkedMul (.literal 2) (.literal 3)))

  let mulShl ← select session (returnProgramSource "MulShl" "8 * 2 << 3") "<mul-shl>"
  expectReturnExpr "8 * 2 << 3" mulShl
    (.shiftLeft (.checkedMul (.literal 8) (.literal 2)) (.literal 3))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 << 2 << 3") "<shl-left>"
  expectReturnExpr "1 << 2 << 3" leftChain
    (.shiftLeft (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 << (2 << 3)") "<shl-right>"
  expectReturnExpr "1 << (2 << 3)" rightNest
    (.shiftLeft (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let groupShl ← select session
    (returnProgramSource "GroupShl" "(1 + 2) << 3") "<group-shl>"
  expectReturnExpr "(1 + 2) << 3" groupShl
    (.shiftLeft (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negShl ← select session (returnProgramSource "NegShl" "-1 << 2") "<neg-shl>"
  expectReturnExpr "-1 << 2" negShl
    (.shiftLeft (.checkedNeg (.literal 1)) (.literal 2))

  let shlNeg ← select session (returnProgramSource "ShlNeg" "1 << -2") "<shl-neg>"
  expectReturnExpr "1 << -2" shlNeg
    (.shiftLeft (.literal 1) (.checkedNeg (.literal 2)))

  let zeroLhs ← select session (returnProgramSource "ZeroLhs" "0 << 1") "<zero-lhs>"
  expectReturnExpr "0 << 1" zeroLhs (.shiftLeft (.literal 0) (.literal 1))

  let zeroCount ← select session (returnProgramSource "ZeroCount" "1 << 0") "<zero-count>"
  expectReturnExpr "1 << 0" zeroCount (.shiftLeft (.literal 1) (.literal 0))

  let count64 ← select session (returnProgramSource "Count64" "1 << 64") "<count-64>"
  expectReturnExpr "1 << 64" count64 (.shiftLeft (.literal 1) (.literal 64))

  -- Same-identity desugar: (1 << 2) == 1 << 2.
  let bareEq ← select session (returnProgramSource "ShlEq" "1 << 2") "<shl-eq-bare>"
  let groupEq ← select session (returnProgramSource "ShlEq" "(1 << 2)") "<shl-eq-group>"
  expect (bareEq == groupEq)
    "1 << 2 and (1 << 2) must share Source.Program under identical identity"
  expect (bareEq.canonicalBytes == groupEq.canonicalBytes)
    "1 << 2 and (1 << 2) must share canonical bytes under identical identity"
  expect (bareEq.sourceHash == groupEq.sourceHash)
    "1 << 2 and (1 << 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for ShiftLeftTwin (Expr tag 12 + lhs/rhs).
  let twin12 := twin (.shiftLeft (.literal 1) (.literal 2))
  let twin21 := twin (.shiftLeft (.literal 2) (.literal 1))
  let twinAddShl := twin
    (.shiftLeft (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinShlAdd := twin
    (.shiftLeft (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShlMul := twin
    (.shiftLeft (.literal 8) (.checkedMul (.literal 2) (.literal 3)))
  let twinMulShl := twin
    (.shiftLeft (.checkedMul (.literal 8) (.literal 2)) (.literal 3))
  let twinLeft := twin
    (.shiftLeft (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.shiftLeft (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinNegShl := twin
    (.shiftLeft (.checkedNeg (.literal 1)) (.literal 2))
  let twinShlNeg := twin
    (.shiftLeft (.literal 1) (.checkedNeg (.literal 2)))
  let twinZeroLhs := twin (.shiftLeft (.literal 0) (.literal 1))
  let twinZeroCount := twin (.shiftLeft (.literal 1) (.literal 0))
  let twinCount64 := twin (.shiftLeft (.literal 1) (.literal 64))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinAB := twin (.shiftLeft (.variable "a") (.variable "b"))

  expect (twin12.sourceHash ==
      "9cef54adbb9d41fc6098537cba57f99c3c1aee3f784eef1ebcc0bee79659b52a")
    s!"shiftLeft 1<<2 ShiftLeftTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 225)
    s!"shiftLeft 1<<2 ShiftLeftTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "2ea816eb5c33fb9a4db7ded3ce5559c895aa9750ba2a8ad75cd2eb67ad6ffaba")
    s!"shiftLeft 2<<1 ShiftLeftTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 225)
    s!"shiftLeft 2<<1 ShiftLeftTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAddShl.sourceHash ==
      "afe2de8b02b34f3f2eac7fec021f711e712b1cccb84641e695ac257de3ff1b7c")
    s!"1+2<<3 ShiftLeftTwin sourceHash golden must remain stable; got {twinAddShl.sourceHash}"
  expect (twinAddShl.canonicalBytes.size == 235)
    s!"1+2<<3 ShiftLeftTwin size golden must remain stable; got {twinAddShl.canonicalBytes.size}"
  expect (twinShlAdd.sourceHash ==
      "534a7ef3d83b90d17f8519dee5bc40a635a05fe0576a55de18659999658e8598")
    s!"1<<2+3 ShiftLeftTwin sourceHash golden must remain stable; got {twinShlAdd.sourceHash}"
  expect (twinShlAdd.canonicalBytes.size == 235)
    s!"1<<2+3 ShiftLeftTwin size golden must remain stable; got {twinShlAdd.canonicalBytes.size}"
  expect (twinShlMul.sourceHash ==
      "35345090c62fe81b81a3e59f28c368f5071646117b41d485849d47560297c949")
    s!"8<<2*3 ShiftLeftTwin sourceHash golden must remain stable; got {twinShlMul.sourceHash}"
  expect (twinShlMul.canonicalBytes.size == 235)
    s!"8<<2*3 ShiftLeftTwin size golden must remain stable; got {twinShlMul.canonicalBytes.size}"
  expect (twinMulShl.sourceHash ==
      "0d297eace8399f4e8740c0eef4e86c8561f4d0303fb6a82c0e37c91fdd4ed0a1")
    s!"8*2<<3 ShiftLeftTwin sourceHash golden must remain stable; got {twinMulShl.sourceHash}"
  expect (twinMulShl.canonicalBytes.size == 235)
    s!"8*2<<3 ShiftLeftTwin size golden must remain stable; got {twinMulShl.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "77888b16028ea0a4c6eca69f983ce466f24cdad4640721cc96ffce7c57ae5047")
    s!"left 1<<2<<3 ShiftLeftTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 235)
    s!"left 1<<2<<3 ShiftLeftTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "289c76fa2d69cd10cda5f8a95d1655421575393a0e15be67895259a8d12da00f")
    s!"right 1<<(2<<3) ShiftLeftTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 235)
    s!"right 1<<(2<<3) ShiftLeftTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegShl.sourceHash ==
      "4c60b8cfb9654d6fccac90f12d82224f509c1d02242bab9c6f91e71c34ae0451")
    s!"-1<<2 ShiftLeftTwin sourceHash golden must remain stable; got {twinNegShl.sourceHash}"
  expect (twinNegShl.canonicalBytes.size == 226)
    s!"-1<<2 ShiftLeftTwin size golden must remain stable; got {twinNegShl.canonicalBytes.size}"
  expect (twinShlNeg.sourceHash ==
      "42c55ba25b8676399bf1fcdcfcf6f3cab5755c07ba4d4fe2f6f9680fcd48f412")
    s!"1<<-2 ShiftLeftTwin sourceHash golden must remain stable; got {twinShlNeg.sourceHash}"
  expect (twinShlNeg.canonicalBytes.size == 226)
    s!"1<<-2 ShiftLeftTwin size golden must remain stable; got {twinShlNeg.canonicalBytes.size}"
  expect (twinZeroLhs.sourceHash ==
      "723b32003ad5de9781ae67e5d0fec60d66e184f303d554865686ebb4b819a815")
    s!"0<<1 ShiftLeftTwin sourceHash golden must remain stable; got {twinZeroLhs.sourceHash}"
  expect (twinZeroLhs.canonicalBytes.size == 225)
    s!"0<<1 ShiftLeftTwin size golden must remain stable; got {twinZeroLhs.canonicalBytes.size}"
  expect (twinZeroCount.sourceHash ==
      "b891f6f7837af84b8d26c7e730df077be72e57235e0e1577e1e5d9ee7443fa04")
    s!"1<<0 ShiftLeftTwin sourceHash golden must remain stable; got {twinZeroCount.sourceHash}"
  expect (twinZeroCount.canonicalBytes.size == 225)
    s!"1<<0 ShiftLeftTwin size golden must remain stable; got {twinZeroCount.canonicalBytes.size}"
  expect (twinCount64.sourceHash ==
      "6ccb1d81aeb484b85841f78378f1e588b2ee457a685fb001a3c42f244709777b")
    s!"1<<64 ShiftLeftTwin sourceHash golden must remain stable; got {twinCount64.sourceHash}"
  expect (twinCount64.canonicalBytes.size == 225)
    s!"1<<64 ShiftLeftTwin size golden must remain stable; got {twinCount64.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "4375c32056bdb07ca709c33781502615e592d22d83417c3e14982558a1cbdbc3")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 225)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "c4596ec2967b308a246b96298dc9cd2b0bbdfb59aecc9979a9025841a5554d8a")
    s!"a<<b ShiftLeftTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 227)
    s!"a<<b ShiftLeftTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"

  -- Non-alias / precedence discriminators (60/61 looser than Add 65).
  expect (twin12.sourceHash != twin21.sourceHash)
    "shiftLeft 1<<2 must not alias 2<<1 (operand order)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "shiftLeft 1<<2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinAdd.canonicalBytes.size)
    "shiftLeft and checkedAdd of two small literals must share size (tag-only distinction)"
  expect (twinAddShl.sourceHash != twinWrong.sourceHash)
    "1+2<<3 must not alias wrong C-style 1+(2<<3)"
  expect (twinAddShl.sourceHash != twinShlAdd.sourceHash)
    "1+2<<3 must not alias 1<<2+3 (lhs60/rhs61 add placement)"
  expect (twinShlMul.sourceHash != twinMulShl.sourceHash)
    "8<<2*3 must not alias 8*2<<3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested shiftLeft must not alias"
  expect (twinNegShl.sourceHash != twinShlNeg.sourceHash)
    "-1<<2 must not alias 1<<-2 (unary placement)"
  expect (twinZeroCount.sourceHash != twinCount64.sourceHash)
    "1<<0 must not alias 1<<64 (count payload)"
  expect (twinZeroCount.sourceHash != twin12.sourceHash)
    "1<<0 must not alias 1<<2"

  -- Parser-boundary malformed shapes; >> remains deferred retention reject.
  for (label, expr) in [
      ("bare shift", "<<"),
      ("missing lhs", "<< 2"),
      ("missing rhs", "1 <<"),
      ("spaced split", "1 < < 2"),
      ("triple shift", "1 <<< 2"),
      ("extra token", "1 << 2 3"),
      ("deferred shift-right", "1 >> 2")
    ] do
    let source := returnProgramSource "RejectedShlShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<shl-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including over-width count).
  match Compiler.compile (twin (.shiftLeft (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "shift left is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject shiftLeft with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing shiftLeft"

  match Compiler.compile (twin (.shiftLeft (.literal 1) (.literal 64))) with
  | .error (.invalidProgram
      "shift left is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject 1<<64 with exact shift message before count rules, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept 1<<64 programs"

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

end Tests.Language.ShiftLeft
