import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- ShiftRightSurface pins binary `>>` in every declaration body position: init, entry,
-- view, and fn. Covers return-value and let-value reachability plus variable operands.
-- Migration: exactly one deferred negative from ShiftLeft.lean (`1 >> 2`).
namespace Tests.Language.ShiftRightFixture

open ProofForgeV2.Language

program ShiftRightSurface where
  init() do
    let seed : UInt64 := 1 >> 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a >> b

  view peek() : UInt64 do
    let value := 1 + 2 >> 3
    return value

  fn helper() : UInt64 do
    return 1 >> 2 >> 3

end Tests.Language.ShiftRightFixture

namespace Tests.Language.ShiftRight

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ShiftRightFixture.ShiftRightTwin" "ShiftRightTwin" #[
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
  "namespace Tests.Language.ShiftRightFixture\n\n" ++
  "program ShiftRightSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 >> 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a >> b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 + 2 >> 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 >> 2 >> 3\n\n" ++
  "end Tests.Language.ShiftRightFixture\n"

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
  let elaborated := Tests.Language.ShiftRightFixture.ShiftRightSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.shiftRight (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 >> 2"
  | none => throw <| IO.userError "ShiftRightSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.shiftRight (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a >> b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.shiftRight (.checkedAdd (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 + 2 >> 3 as (1+2)>>3"
  | _ => throw <| IO.userError "ShiftRightSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.shiftRight (.shiftRight (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 >> 2 >> 3"
  | _ => throw <| IO.userError "ShiftRightSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<shift-right>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same shiftRight Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same shiftRight sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins from freeze (precedence 60/61, cross <<>> left-assoc).
  let shr12 ← select session (returnProgramSource "Shr12" "1 >> 2") "<shr-1-2>"
  expectReturnExpr "1 >> 2" shr12 (.shiftRight (.literal 1) (.literal 2))

  let shr21 ← select session (returnProgramSource "Shr21" "2 >> 1") "<shr-2-1>"
  expectReturnExpr "2 >> 1" shr21 (.shiftRight (.literal 2) (.literal 1))

  let shrAB ← select session (varReturnProgramSource "ShrAB" "a >> b") "<shr-a-b>"
  expectReturnExpr "a >> b" shrAB (.shiftRight (.variable "a") (.variable "b"))

  let addShr ← select session (returnProgramSource "AddShr" "1 + 2 >> 3") "<add-shr>"
  expectReturnExpr "1 + 2 >> 3" addShr
    (.shiftRight (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let shrAdd ← select session (returnProgramSource "ShrAdd" "1 >> 2 + 3") "<shr-add>"
  expectReturnExpr "1 >> 2 + 3" shrAdd
    (.shiftRight (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let shrMul ← select session (returnProgramSource "ShrMul" "8 >> 2 * 3") "<shr-mul>"
  expectReturnExpr "8 >> 2 * 3" shrMul
    (.shiftRight (.literal 8) (.checkedMul (.literal 2) (.literal 3)))

  let mulShr ← select session (returnProgramSource "MulShr" "8 * 2 >> 3") "<mul-shr>"
  expectReturnExpr "8 * 2 >> 3" mulShr
    (.shiftRight (.checkedMul (.literal 8) (.literal 2)) (.literal 3))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 >> 2 >> 3") "<shr-left>"
  expectReturnExpr "1 >> 2 >> 3" leftChain
    (.shiftRight (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 >> (2 >> 3)") "<shr-right>"
  expectReturnExpr "1 >> (2 >> 3)" rightNest
    (.shiftRight (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let groupShr ← select session
    (returnProgramSource "GroupShr" "(1 + 2) >> 3") "<group-shr>"
  expectReturnExpr "(1 + 2) >> 3" groupShr
    (.shiftRight (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negShr ← select session (returnProgramSource "NegShr" "-1 >> 2") "<neg-shr>"
  expectReturnExpr "-1 >> 2" negShr
    (.shiftRight (.checkedNeg (.literal 1)) (.literal 2))

  let shrNeg ← select session (returnProgramSource "ShrNeg" "1 >> -2") "<shr-neg>"
  expectReturnExpr "1 >> -2" shrNeg
    (.shiftRight (.literal 1) (.checkedNeg (.literal 2)))

  let zeroLhs ← select session (returnProgramSource "ZeroLhs" "0 >> 1") "<zero-lhs>"
  expectReturnExpr "0 >> 1" zeroLhs (.shiftRight (.literal 0) (.literal 1))

  let zeroCount ← select session (returnProgramSource "ZeroCount" "1 >> 0") "<zero-count>"
  expectReturnExpr "1 >> 0" zeroCount (.shiftRight (.literal 1) (.literal 0))

  let count64 ← select session (returnProgramSource "Count64" "1 >> 64") "<count-64>"
  expectReturnExpr "1 >> 64" count64 (.shiftRight (.literal 1) (.literal 64))

  let shlThenShr ← select session
    (returnProgramSource "ShlThenShr" "1 << 2 >> 3") "<shl-then-shr>"
  expectReturnExpr "1 << 2 >> 3" shlThenShr
    (.shiftRight (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let shrThenShl ← select session
    (returnProgramSource "ShrThenShl" "1 >> 2 << 3") "<shr-then-shl>"
  expectReturnExpr "1 >> 2 << 3" shrThenShl
    (.shiftLeft (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  -- Same-identity desugar: (1 >> 2) == 1 >> 2.
  let bareEq ← select session (returnProgramSource "ShrEq" "1 >> 2") "<shr-eq-bare>"
  let groupEq ← select session (returnProgramSource "ShrEq" "(1 >> 2)") "<shr-eq-group>"
  expect (bareEq == groupEq)
    "1 >> 2 and (1 >> 2) must share Source.Program under identical identity"
  expect (bareEq.canonicalBytes == groupEq.canonicalBytes)
    "1 >> 2 and (1 >> 2) must share canonical bytes under identical identity"
  expect (bareEq.sourceHash == groupEq.sourceHash)
    "1 >> 2 and (1 >> 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for ShiftRightTwin (Expr tag 13 + lhs/rhs).
  let twin12 := twin (.shiftRight (.literal 1) (.literal 2))
  let twin21 := twin (.shiftRight (.literal 2) (.literal 1))
  let twinAddShr := twin
    (.shiftRight (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinShrAdd := twin
    (.shiftRight (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinShrMul := twin
    (.shiftRight (.literal 8) (.checkedMul (.literal 2) (.literal 3)))
  let twinMulShr := twin
    (.shiftRight (.checkedMul (.literal 8) (.literal 2)) (.literal 3))
  let twinLeft := twin
    (.shiftRight (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.shiftRight (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinNegShr := twin
    (.shiftRight (.checkedNeg (.literal 1)) (.literal 2))
  let twinShrNeg := twin
    (.shiftRight (.literal 1) (.checkedNeg (.literal 2)))
  let twinZeroLhs := twin (.shiftRight (.literal 0) (.literal 1))
  let twinZeroCount := twin (.shiftRight (.literal 1) (.literal 0))
  let twinCount64 := twin (.shiftRight (.literal 1) (.literal 64))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))
  let twinAB := twin (.shiftRight (.variable "a") (.variable "b"))
  let twinShlThenShr := twin
    (.shiftRight (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinShrThenShl := twin
    (.shiftLeft (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinShlCtrl := twin (.shiftLeft (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "a3566f68f52b46f51c9307718b70133fe5520f23952f9d41d429dac57a28637e")
    s!"shiftRight 1>>2 ShiftRightTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 228)
    s!"shiftRight 1>>2 ShiftRightTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "3ee8a82eaa290fd4ba206c7f92995b0e3924cba79cd0864c51d1c90addfd943d")
    s!"shiftRight 2>>1 ShiftRightTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 228)
    s!"shiftRight 2>>1 ShiftRightTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAddShr.sourceHash ==
      "30b1759079dfddfe1a5e3668177d30aeefe956120e23aaab703b64327b6b93ff")
    s!"1+2>>3 ShiftRightTwin sourceHash golden must remain stable; got {twinAddShr.sourceHash}"
  expect (twinAddShr.canonicalBytes.size == 238)
    s!"1+2>>3 ShiftRightTwin size golden must remain stable; got {twinAddShr.canonicalBytes.size}"
  expect (twinShrAdd.sourceHash ==
      "a7a939b3de47b27ebb9996fe77f2dfadf3f9a0c2d54727e1b4c1e82443b46043")
    s!"1>>2+3 ShiftRightTwin sourceHash golden must remain stable; got {twinShrAdd.sourceHash}"
  expect (twinShrAdd.canonicalBytes.size == 238)
    s!"1>>2+3 ShiftRightTwin size golden must remain stable; got {twinShrAdd.canonicalBytes.size}"
  expect (twinShrMul.sourceHash ==
      "4f94982f4b352ef96c82fef20e5ac1a1d88523589a86e5ec9f3390c149010f44")
    s!"8>>2*3 ShiftRightTwin sourceHash golden must remain stable; got {twinShrMul.sourceHash}"
  expect (twinShrMul.canonicalBytes.size == 238)
    s!"8>>2*3 ShiftRightTwin size golden must remain stable; got {twinShrMul.canonicalBytes.size}"
  expect (twinMulShr.sourceHash ==
      "6f6da998ebd40b9d10d6864a6c4155a1fa24889173212d828e020cfa9f240da8")
    s!"8*2>>3 ShiftRightTwin sourceHash golden must remain stable; got {twinMulShr.sourceHash}"
  expect (twinMulShr.canonicalBytes.size == 238)
    s!"8*2>>3 ShiftRightTwin size golden must remain stable; got {twinMulShr.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "e90c2caa954ca8f92c5f0f22b8ab3cefa2b448ff4d0cbc6f4a752241a4a531a9")
    s!"left 1>>2>>3 ShiftRightTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 238)
    s!"left 1>>2>>3 ShiftRightTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "eab0cc18fd52efeabc7b7540be798194f87b9fda776fe742daa2c6ad57639803")
    s!"right 1>>(2>>3) ShiftRightTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 238)
    s!"right 1>>(2>>3) ShiftRightTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegShr.sourceHash ==
      "5ab9bd927665c4211c3f9a7f93aa08bbfbef7ccd97f220b0065fd7443318e687")
    s!"-1>>2 ShiftRightTwin sourceHash golden must remain stable; got {twinNegShr.sourceHash}"
  expect (twinNegShr.canonicalBytes.size == 229)
    s!"-1>>2 ShiftRightTwin size golden must remain stable; got {twinNegShr.canonicalBytes.size}"
  expect (twinShrNeg.sourceHash ==
      "62fa0f5e81ace29e82956f0d0d149342ab4a85efff605d965762627ce621dd63")
    s!"1>>-2 ShiftRightTwin sourceHash golden must remain stable; got {twinShrNeg.sourceHash}"
  expect (twinShrNeg.canonicalBytes.size == 229)
    s!"1>>-2 ShiftRightTwin size golden must remain stable; got {twinShrNeg.canonicalBytes.size}"
  expect (twinZeroLhs.sourceHash ==
      "5a64339ebb09954464226acc66de07a067e390cba2ccb57a4ccd2c7df9a2804b")
    s!"0>>1 ShiftRightTwin sourceHash golden must remain stable; got {twinZeroLhs.sourceHash}"
  expect (twinZeroLhs.canonicalBytes.size == 228)
    s!"0>>1 ShiftRightTwin size golden must remain stable; got {twinZeroLhs.canonicalBytes.size}"
  expect (twinZeroCount.sourceHash ==
      "844410d41848fb116302673984f538fac4e6849f1ca182607caab8008cb2e9b3")
    s!"1>>0 ShiftRightTwin sourceHash golden must remain stable; got {twinZeroCount.sourceHash}"
  expect (twinZeroCount.canonicalBytes.size == 228)
    s!"1>>0 ShiftRightTwin size golden must remain stable; got {twinZeroCount.canonicalBytes.size}"
  expect (twinCount64.sourceHash ==
      "f29d87c9b953de738e3559eb792c6ec98fb816c8c3386d63936c5c6da0fa2925")
    s!"1>>64 ShiftRightTwin sourceHash golden must remain stable; got {twinCount64.sourceHash}"
  expect (twinCount64.canonicalBytes.size == 228)
    s!"1>>64 ShiftRightTwin size golden must remain stable; got {twinCount64.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "b4c401ac62adae682eb70dabd9e31d1bcd9745fb8e0bd146299f1c6e9ea0e01b")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 228)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "2674494ad7b3496f13ba4ff31edc58217365fbe8c2e8cd4ed99e8bce5bfe0876")
    s!"a>>b ShiftRightTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 230)
    s!"a>>b ShiftRightTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twinShlThenShr.sourceHash ==
      "a9c338f2cb43f52d59f03a0441f255a1f7309ea5dd4eadf1dcfba5c73ada60e8")
    s!"1<<2>>3 ShiftRightTwin sourceHash golden must remain stable; got {twinShlThenShr.sourceHash}"
  expect (twinShlThenShr.canonicalBytes.size == 238)
    s!"1<<2>>3 ShiftRightTwin size golden must remain stable; got {twinShlThenShr.canonicalBytes.size}"
  expect (twinShrThenShl.sourceHash ==
      "bd6d1a6f808cedf83d1b2a6530e4d52ab285b9bfaa61ef5a28fafad964c441b3")
    s!"1>>2<<3 ShiftRightTwin sourceHash golden must remain stable; got {twinShrThenShl.sourceHash}"
  expect (twinShrThenShl.canonicalBytes.size == 238)
    s!"1>>2<<3 ShiftRightTwin size golden must remain stable; got {twinShrThenShl.canonicalBytes.size}"
  expect (twinShlCtrl.sourceHash ==
      "720153ef413f91f71bd50489e3fdf4457bcc6c4b8287558633a902e816e09bbd")
    s!"shiftLeft 1<<2 control sourceHash golden must remain stable; got {twinShlCtrl.sourceHash}"
  expect (twinShlCtrl.canonicalBytes.size == 228)
    s!"shiftLeft 1<<2 control size golden must remain stable; got {twinShlCtrl.canonicalBytes.size}"

  -- Non-alias / precedence / cross-shift discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "shiftRight 1>>2 must not alias 2>>1 (operand order)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "shiftRight 1>>2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.sourceHash != twinShlCtrl.sourceHash)
    "shiftRight 1>>2 must not alias shiftLeft 1<<2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinAdd.canonicalBytes.size)
    "shiftRight and checkedAdd of two small literals must share size (tag-only distinction)"
  expect (twin12.canonicalBytes.size == twinShlCtrl.canonicalBytes.size)
    "shiftRight and shiftLeft of two small literals must share size (tag-only distinction)"
  expect (twinAddShr.sourceHash != twinWrong.sourceHash)
    "1+2>>3 must not alias wrong C-style 1+(2>>3)"
  expect (twinAddShr.sourceHash != twinShrAdd.sourceHash)
    "1+2>>3 must not alias 1>>2+3 (lhs60/rhs61 add placement)"
  expect (twinShrMul.sourceHash != twinMulShr.sourceHash)
    "8>>2*3 must not alias 8*2>>3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested shiftRight must not alias"
  expect (twinNegShr.sourceHash != twinShrNeg.sourceHash)
    "-1>>2 must not alias 1>>-2 (unary placement)"
  expect (twinZeroCount.sourceHash != twinCount64.sourceHash)
    "1>>0 must not alias 1>>64 (count payload)"
  expect (twinZeroCount.sourceHash != twin12.sourceHash)
    "1>>0 must not alias 1>>2"
  expect (twinShlThenShr.sourceHash != twinShrThenShl.sourceHash)
    "1<<2>>3 must not alias 1>>2<<3 (cross-shift order)"
  expect (twinShlThenShr.sourceHash != twinLeft.sourceHash)
    "1<<2>>3 must not alias pure left 1>>2>>3"

  -- Parser-boundary malformed shapes for >>.
  for (label, expr) in [
      ("bare shift", ">>"),
      ("missing lhs", ">> 2"),
      ("missing rhs", "1 >>"),
      ("spaced split", "1 > > 2"),
      ("triple shift", "1 >>> 2"),
      ("extra token", "1 >> 2 3")
    ] do
    let source := returnProgramSource "RejectedShrShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<shr-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking (including over-width count).
  match Compiler.compile (twin (.shiftRight (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "shift right is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject shiftRight with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing shiftRight"

  match Compiler.compile (twin (.shiftRight (.literal 1) (.literal 64))) with
  | .error (.invalidProgram
      "shift right is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject 1>>64 with exact shift message before count rules, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept 1>>64 programs"

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

end Tests.Language.ShiftRight
