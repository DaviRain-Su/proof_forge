import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- BitwiseOrSurface pins binary `|` in every declaration body position plus same-program
-- enum Flag variants (Off / On(UInt64)). Migration: exactly BitwiseXor deferred `1 | 2`.
namespace Tests.Language.BitwiseOrFixture

open ProofForgeV2.Language

program BitwiseOrSurface where
  enum Flag where
    | Off
    | On(UInt64)

  init() do
    let seed : UInt64 := 1 | 2
    return seed

  entry run(a : UInt64, b : UInt64) : UInt64 do
    return a | b

  view peek() : UInt64 do
    let value := 1 ^ 2 | 3
    return value

  fn helper() : UInt64 do
    return 1 | 2 | 3

end Tests.Language.BitwiseOrFixture

namespace Tests.Language.BitwiseOr

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.BitwiseOrFixture.BitwiseOrTwin" "BitwiseOrTwin" #[
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
  "namespace Tests.Language.BitwiseOrFixture\n\n" ++
  "program BitwiseOrSurface where\n" ++
  "  enum Flag where\n" ++
  "    | Off\n" ++
  "    | On(UInt64)\n\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := 1 | 2\n" ++
  "    return seed\n\n" ++
  "  entry run(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a | b\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let value := 1 ^ 2 | 3\n" ++
  "    return value\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return 1 | 2 | 3\n\n" ++
  "end Tests.Language.BitwiseOrFixture\n"

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
  let elaborated := Tests.Language.BitwiseOrFixture.BitwiseOrSurface
  match elaborated.enums with
  | #[flag] =>
      expect (flag.name == "Flag") "coexist enum must retain name Flag"
      match flag.variants with
      | #[off, on] =>
          expect (off.name == "Off" && off.payloadTypes.isEmpty)
            "enum variant Off must remain nullary"
          expect (on.name == "On" && on.payloadTypes == #[.u64])
            "enum variant On must retain UInt64 payload"
      | _ => throw <| IO.userError "Flag must retain Off and On variants"
  | _ => throw <| IO.userError "BitwiseOrSurface must retain coexist enum Flag"
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.bitwiseOr (.literal 1) (.literal 2)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := 1 | 2"
  | none => throw <| IO.userError "BitwiseOrSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.bitwiseOr (.variable "a") (.variable "b"))] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return a | b with variable operands"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "value" none
            (.bitwiseOr (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3)),
          .returnValue (.variable "value")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let value := 1 ^ 2 | 3 as (1^2)|3"
  | _ => throw <| IO.userError "BitwiseOrSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue
            (.bitwiseOr (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain left-associative return 1 | 2 | 3"
  | _ => throw <| IO.userError "BitwiseOrSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<bitwise-or>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same bitwiseOr Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same bitwiseOr sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact AST pins (precedence 35 left-assoc, looser than BitXor 40).
  let or12 ← select session (returnProgramSource "Or12" "1 | 2") "<or-1-2>"
  expectReturnExpr "1 | 2" or12 (.bitwiseOr (.literal 1) (.literal 2))

  let or21 ← select session (returnProgramSource "Or21" "2 | 1") "<or-2-1>"
  expectReturnExpr "2 | 1" or21 (.bitwiseOr (.literal 2) (.literal 1))

  let orAB ← select session (varReturnProgramSource "OrAB" "a | b") "<or-a-b>"
  expectReturnExpr "a | b" orAB (.bitwiseOr (.variable "a") (.variable "b"))

  let or00 ← select session (returnProgramSource "Or00" "0 | 0") "<or-0-0>"
  expectReturnExpr "0 | 0" or00 (.bitwiseOr (.literal 0) (.literal 0))

  let orTF ← select session (returnProgramSource "OrTF" "true | false") "<or-t-f>"
  expectReturnExpr "true | false" orTF
    (.bitwiseOr (.boolLiteral true) (.boolLiteral false))

  let orFT ← select session (returnProgramSource "OrFT" "false | true") "<or-f-t>"
  expectReturnExpr "false | true" orFT
    (.bitwiseOr (.boolLiteral false) (.boolLiteral true))

  let addOr ← select session (returnProgramSource "AddOr" "1 + 2 | 3") "<add-or>"
  expectReturnExpr "1 + 2 | 3" addOr
    (.bitwiseOr (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let orAdd ← select session (returnProgramSource "OrAdd" "1 | 2 + 3") "<or-add>"
  expectReturnExpr "1 | 2 + 3" orAdd
    (.bitwiseOr (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))

  let mulOr ← select session (returnProgramSource "MulOr" "1 * 2 | 3") "<mul-or>"
  expectReturnExpr "1 * 2 | 3" mulOr
    (.bitwiseOr (.checkedMul (.literal 1) (.literal 2)) (.literal 3))

  let orMul ← select session (returnProgramSource "OrMul" "1 | 2 * 3") "<or-mul>"
  expectReturnExpr "1 | 2 * 3" orMul
    (.bitwiseOr (.literal 1) (.checkedMul (.literal 2) (.literal 3)))

  let shlOr ← select session (returnProgramSource "ShlOr" "1 << 2 | 3") "<shl-or>"
  expectReturnExpr "1 << 2 | 3" shlOr
    (.bitwiseOr (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))

  let orShl ← select session (returnProgramSource "OrShl" "1 | 2 << 3") "<or-shl>"
  expectReturnExpr "1 | 2 << 3" orShl
    (.bitwiseOr (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))

  let shrOr ← select session (returnProgramSource "ShrOr" "1 >> 2 | 3") "<shr-or>"
  expectReturnExpr "1 >> 2 | 3" shrOr
    (.bitwiseOr (.shiftRight (.literal 1) (.literal 2)) (.literal 3))

  let orShr ← select session (returnProgramSource "OrShr" "1 | 2 >> 3") "<or-shr>"
  expectReturnExpr "1 | 2 >> 3" orShr
    (.bitwiseOr (.literal 1) (.shiftRight (.literal 2) (.literal 3)))

  let orEq ← select session (returnProgramSource "OrEq" "1 | 2 == 3") "<or-eq>"
  expectReturnExpr "1 | 2 == 3" orEq
    (.bitwiseOr (.literal 1) (.equal (.literal 2) (.literal 3)))

  let eqOr ← select session (returnProgramSource "EqOr" "1 == 2 | 3") "<eq-or>"
  expectReturnExpr "1 == 2 | 3" eqOr
    (.bitwiseOr (.equal (.literal 1) (.literal 2)) (.literal 3))

  let andOr ← select session (returnProgramSource "AndOr" "1 & 2 | 3") "<and-or>"
  expectReturnExpr "1 & 2 | 3" andOr
    (.bitwiseOr (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))

  let orAnd ← select session (returnProgramSource "OrAnd" "1 | 2 & 3") "<or-and>"
  expectReturnExpr "1 | 2 & 3" orAnd
    (.bitwiseOr (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))

  let xorOr ← select session (returnProgramSource "XorOr" "1 ^ 2 | 3") "<xor-or>"
  expectReturnExpr "1 ^ 2 | 3" xorOr
    (.bitwiseOr (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))

  let orXor ← select session (returnProgramSource "OrXor" "1 | 2 ^ 3") "<or-xor>"
  expectReturnExpr "1 | 2 ^ 3" orXor
    (.bitwiseOr (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))

  let leftChain ← select session
    (returnProgramSource "LeftChain" "1 | 2 | 3") "<or-left>"
  expectReturnExpr "1 | 2 | 3" leftChain
    (.bitwiseOr (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))

  let rightNest ← select session
    (returnProgramSource "RightNest" "1 | (2 | 3)") "<or-right>"
  expectReturnExpr "1 | (2 | 3)" rightNest
    (.bitwiseOr (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))

  let groupOr ← select session
    (returnProgramSource "GroupOr" "(1 + 2) | 3") "<group-or>"
  expectReturnExpr "(1 + 2) | 3" groupOr
    (.bitwiseOr (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))

  let negOr ← select session (returnProgramSource "NegOr" "-1 | 2") "<neg-or>"
  expectReturnExpr "-1 | 2" negOr
    (.bitwiseOr (.checkedNeg (.literal 1)) (.literal 2))

  let orNeg ← select session (returnProgramSource "OrNeg" "1 | -2") "<or-neg>"
  expectReturnExpr "1 | -2" orNeg
    (.bitwiseOr (.literal 1) (.checkedNeg (.literal 2)))

  -- Same-identity desugar.
  let bareOr ← select session (returnProgramSource "OrSame" "1 | 2") "<or-same-bare>"
  let groupSame ← select session
    (returnProgramSource "OrSame" "(1 | 2)") "<or-same-group>"
  expect (bareOr == groupSame)
    "1 | 2 and (1 | 2) must share Source.Program under identical identity"
  expect (bareOr.canonicalBytes == groupSame.canonicalBytes)
    "1 | 2 and (1 | 2) must share canonical bytes under identical identity"
  expect (bareOr.sourceHash == groupSame.sourceHash)
    "1 | 2 and (1 | 2) must share sourceHash under identical identity"

  -- Frozen prospective goldens for BitwiseOrTwin (Expr tag 22 + lhs/rhs).
  let twin12 := twin (.bitwiseOr (.literal 1) (.literal 2))
  let twin21 := twin (.bitwiseOr (.literal 2) (.literal 1))
  let twinAB := twin (.bitwiseOr (.variable "a") (.variable "b"))
  let twin00 := twin (.bitwiseOr (.literal 0) (.literal 0))
  let twinTF := twin (.bitwiseOr (.boolLiteral true) (.boolLiteral false))
  let twinFT := twin (.bitwiseOr (.boolLiteral false) (.boolLiteral true))
  let twinAddOr := twin
    (.bitwiseOr (.checkedAdd (.literal 1) (.literal 2)) (.literal 3))
  let twinOrAdd := twin
    (.bitwiseOr (.literal 1) (.checkedAdd (.literal 2) (.literal 3)))
  let twinWrong := twin
    (.checkedAdd (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))
  let twinMulOr := twin
    (.bitwiseOr (.checkedMul (.literal 1) (.literal 2)) (.literal 3))
  let twinOrMul := twin
    (.bitwiseOr (.literal 1) (.checkedMul (.literal 2) (.literal 3)))
  let twinShlOr := twin
    (.bitwiseOr (.shiftLeft (.literal 1) (.literal 2)) (.literal 3))
  let twinOrShl := twin
    (.bitwiseOr (.literal 1) (.shiftLeft (.literal 2) (.literal 3)))
  let twinShrOr := twin
    (.bitwiseOr (.shiftRight (.literal 1) (.literal 2)) (.literal 3))
  let twinOrShr := twin
    (.bitwiseOr (.literal 1) (.shiftRight (.literal 2) (.literal 3)))
  let twinOrEq := twin
    (.bitwiseOr (.literal 1) (.equal (.literal 2) (.literal 3)))
  let twinEqOr := twin
    (.bitwiseOr (.equal (.literal 1) (.literal 2)) (.literal 3))
  let twinAndOr := twin
    (.bitwiseOr (.bitwiseAnd (.literal 1) (.literal 2)) (.literal 3))
  let twinOrAnd := twin
    (.bitwiseOr (.literal 1) (.bitwiseAnd (.literal 2) (.literal 3)))
  let twinXorOr := twin
    (.bitwiseOr (.bitwiseXor (.literal 1) (.literal 2)) (.literal 3))
  let twinOrXor := twin
    (.bitwiseOr (.literal 1) (.bitwiseXor (.literal 2) (.literal 3)))
  let twinLeft := twin
    (.bitwiseOr (.bitwiseOr (.literal 1) (.literal 2)) (.literal 3))
  let twinRight := twin
    (.bitwiseOr (.literal 1) (.bitwiseOr (.literal 2) (.literal 3)))
  let twinNegOr := twin
    (.bitwiseOr (.checkedNeg (.literal 1)) (.literal 2))
  let twinOrNeg := twin
    (.bitwiseOr (.literal 1) (.checkedNeg (.literal 2)))
  let twinXorCtrl := twin (.bitwiseXor (.literal 1) (.literal 2))
  let twinAndCtrl := twin (.bitwiseAnd (.literal 1) (.literal 2))
  let twinEq := twin (.equal (.literal 1) (.literal 2))
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twin12.sourceHash ==
      "3cced4a96e08ffe5cfb73a7a9cbd4886d3a8179cb0f871d054a9f91b3ebd30c8")
    s!"bitwiseOr 1|2 BitwiseOrTwin sourceHash golden must remain stable; got {twin12.sourceHash}"
  expect (twin12.canonicalBytes.size == 225)
    s!"bitwiseOr 1|2 BitwiseOrTwin size golden must remain stable; got {twin12.canonicalBytes.size}"
  expect (twin21.sourceHash ==
      "b7a77e633e0c68205c8d854963092d37fd4ee1d5c03338db7e0522aa3b418b28")
    s!"bitwiseOr 2|1 BitwiseOrTwin sourceHash golden must remain stable; got {twin21.sourceHash}"
  expect (twin21.canonicalBytes.size == 225)
    s!"bitwiseOr 2|1 BitwiseOrTwin size golden must remain stable; got {twin21.canonicalBytes.size}"
  expect (twinAB.sourceHash ==
      "9f5a49e9922d5379984c2c4d2433b3c963bb730808c6dd2a4ecdc191c7d8c4a8")
    s!"a|b BitwiseOrTwin sourceHash golden must remain stable; got {twinAB.sourceHash}"
  expect (twinAB.canonicalBytes.size == 227)
    s!"a|b BitwiseOrTwin size golden must remain stable; got {twinAB.canonicalBytes.size}"
  expect (twin00.sourceHash ==
      "9420698443f8e753778e396ba7a2de425e95819612fcaa12e35896450b5efe0b")
    s!"0|0 BitwiseOrTwin sourceHash golden must remain stable; got {twin00.sourceHash}"
  expect (twin00.canonicalBytes.size == 225)
    s!"0|0 BitwiseOrTwin size golden must remain stable; got {twin00.canonicalBytes.size}"
  expect (twinTF.sourceHash ==
      "2e800d99d11df1f31b9ce2a6997607339a097f148ff4570657a47bb972049d68")
    s!"true|false BitwiseOrTwin sourceHash golden must remain stable; got {twinTF.sourceHash}"
  expect (twinTF.canonicalBytes.size == 211)
    s!"true|false BitwiseOrTwin size golden must remain stable; got {twinTF.canonicalBytes.size}"
  expect (twinFT.sourceHash ==
      "862af67aadf2834bf7663a5b70c4cf032c6d2d7385eda67982ef3c407320e1ee")
    s!"false|true BitwiseOrTwin sourceHash golden must remain stable; got {twinFT.sourceHash}"
  expect (twinFT.canonicalBytes.size == 211)
    s!"false|true BitwiseOrTwin size golden must remain stable; got {twinFT.canonicalBytes.size}"
  expect (twinAddOr.sourceHash ==
      "a7b07d01e380b1f9cd3e1309ce5fc0cb98c29a7cf7d88b26128894a7dc15453c")
    s!"1+2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinAddOr.sourceHash}"
  expect (twinAddOr.canonicalBytes.size == 235)
    s!"1+2|3 BitwiseOrTwin size golden must remain stable; got {twinAddOr.canonicalBytes.size}"
  expect (twinOrAdd.sourceHash ==
      "74f446a40464b980fd4f17c73568516f946777c3f3d4bcc7786159ff201d4604")
    s!"1|2+3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrAdd.sourceHash}"
  expect (twinOrAdd.canonicalBytes.size == 235)
    s!"1|2+3 BitwiseOrTwin size golden must remain stable; got {twinOrAdd.canonicalBytes.size}"
  expect (twinMulOr.sourceHash ==
      "1303174fbac4eb9665e80a58b684399631ab36cccea383d584c526ec21364484")
    s!"1*2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinMulOr.sourceHash}"
  expect (twinMulOr.canonicalBytes.size == 235)
    s!"1*2|3 BitwiseOrTwin size golden must remain stable; got {twinMulOr.canonicalBytes.size}"
  expect (twinOrMul.sourceHash ==
      "9e0f03708ae161364e1cc69c4fbaa5072736562ba503978027f78f83fcb2702f")
    s!"1|2*3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrMul.sourceHash}"
  expect (twinOrMul.canonicalBytes.size == 235)
    s!"1|2*3 BitwiseOrTwin size golden must remain stable; got {twinOrMul.canonicalBytes.size}"
  expect (twinShlOr.sourceHash ==
      "723ccdbb5800b267bc1f37240e5b2eaad140a5813afe95ff5e23360263be62d0")
    s!"1<<2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinShlOr.sourceHash}"
  expect (twinShlOr.canonicalBytes.size == 235)
    s!"1<<2|3 BitwiseOrTwin size golden must remain stable; got {twinShlOr.canonicalBytes.size}"
  expect (twinOrShl.sourceHash ==
      "0c37459913384818b182b8ff7e370c00757aa7ca1400a44d58de5d2551cc4cb0")
    s!"1|2<<3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrShl.sourceHash}"
  expect (twinOrShl.canonicalBytes.size == 235)
    s!"1|2<<3 BitwiseOrTwin size golden must remain stable; got {twinOrShl.canonicalBytes.size}"
  expect (twinShrOr.sourceHash ==
      "de8dd0a4ff3c777b64aab1a3250286ec6b66745fbbff201627d0b2af9e12e7ec")
    s!"1>>2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinShrOr.sourceHash}"
  expect (twinShrOr.canonicalBytes.size == 235)
    s!"1>>2|3 BitwiseOrTwin size golden must remain stable; got {twinShrOr.canonicalBytes.size}"
  expect (twinOrShr.sourceHash ==
      "84cf474120ef47d379a1a8bc6f440f78ca285859d882b46397bb6d2ab0b3bc3e")
    s!"1|2>>3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrShr.sourceHash}"
  expect (twinOrShr.canonicalBytes.size == 235)
    s!"1|2>>3 BitwiseOrTwin size golden must remain stable; got {twinOrShr.canonicalBytes.size}"
  expect (twinOrEq.sourceHash ==
      "4774cc61bbc9d764bd16d800922991d4233f428f84a21fad4debefb0a671c1c5")
    s!"1|2==3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrEq.sourceHash}"
  expect (twinOrEq.canonicalBytes.size == 235)
    s!"1|2==3 BitwiseOrTwin size golden must remain stable; got {twinOrEq.canonicalBytes.size}"
  expect (twinEqOr.sourceHash ==
      "76fc479809984a7108e127d8fa37c573dcbf03e00a9b897f2ed49ceffc67ccb5")
    s!"1==2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinEqOr.sourceHash}"
  expect (twinEqOr.canonicalBytes.size == 235)
    s!"1==2|3 BitwiseOrTwin size golden must remain stable; got {twinEqOr.canonicalBytes.size}"
  expect (twinAndOr.sourceHash ==
      "a7934979feb4f7374664d30f11028543f9ecaf1cffa6b27dee74b4317431c54f")
    s!"1&2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinAndOr.sourceHash}"
  expect (twinAndOr.canonicalBytes.size == 235)
    s!"1&2|3 BitwiseOrTwin size golden must remain stable; got {twinAndOr.canonicalBytes.size}"
  expect (twinOrAnd.sourceHash ==
      "5320c8c10406c6080693c75313181bb97acd304903ef31c7b7fa5b5415a3f16f")
    s!"1|2&3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrAnd.sourceHash}"
  expect (twinOrAnd.canonicalBytes.size == 235)
    s!"1|2&3 BitwiseOrTwin size golden must remain stable; got {twinOrAnd.canonicalBytes.size}"
  expect (twinXorOr.sourceHash ==
      "3548042164a277935676b5992f4b511246a7d9b67f81d0f5394140a6cbd843b6")
    s!"1^2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinXorOr.sourceHash}"
  expect (twinXorOr.canonicalBytes.size == 235)
    s!"1^2|3 BitwiseOrTwin size golden must remain stable; got {twinXorOr.canonicalBytes.size}"
  expect (twinOrXor.sourceHash ==
      "b96df12aeaa701df5f8ed84dcb4dec989b03ed8e141c7151ededf302a8cf02c8")
    s!"1|2^3 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrXor.sourceHash}"
  expect (twinOrXor.canonicalBytes.size == 235)
    s!"1|2^3 BitwiseOrTwin size golden must remain stable; got {twinOrXor.canonicalBytes.size}"
  expect (twinLeft.sourceHash ==
      "5d4f73a1ab3d659589df6c9ca2a6f50b34645f37c536886deab3fddd17b8eeeb")
    s!"left 1|2|3 BitwiseOrTwin sourceHash golden must remain stable; got {twinLeft.sourceHash}"
  expect (twinLeft.canonicalBytes.size == 235)
    s!"left 1|2|3 BitwiseOrTwin size golden must remain stable; got {twinLeft.canonicalBytes.size}"
  expect (twinRight.sourceHash ==
      "853e9535cac8269427d487d433ec94e061014a418a15983b1ac6f69e45048e62")
    s!"right 1|(2|3) BitwiseOrTwin sourceHash golden must remain stable; got {twinRight.sourceHash}"
  expect (twinRight.canonicalBytes.size == 235)
    s!"right 1|(2|3) BitwiseOrTwin size golden must remain stable; got {twinRight.canonicalBytes.size}"
  expect (twinNegOr.sourceHash ==
      "9349879cecca5704e6192afdc2eb24abb3e4e57cdc3ed19740f195f379669bae")
    s!"-1|2 BitwiseOrTwin sourceHash golden must remain stable; got {twinNegOr.sourceHash}"
  expect (twinNegOr.canonicalBytes.size == 226)
    s!"-1|2 BitwiseOrTwin size golden must remain stable; got {twinNegOr.canonicalBytes.size}"
  expect (twinOrNeg.sourceHash ==
      "2e1c020ac9cac3bd0d961a739fb8dd9cd51a975de25a8474830105a7b6cc45d4")
    s!"1|-2 BitwiseOrTwin sourceHash golden must remain stable; got {twinOrNeg.sourceHash}"
  expect (twinOrNeg.canonicalBytes.size == 226)
    s!"1|-2 BitwiseOrTwin size golden must remain stable; got {twinOrNeg.canonicalBytes.size}"
  expect (twinXorCtrl.sourceHash ==
      "420d2e875f30d598fb774634c0d5274116d041b051636e419c1bf70d3ce78eb4")
    s!"bitwiseXor 1^2 control sourceHash golden must remain stable; got {twinXorCtrl.sourceHash}"
  expect (twinXorCtrl.canonicalBytes.size == 225)
    s!"bitwiseXor 1^2 control size golden must remain stable; got {twinXorCtrl.canonicalBytes.size}"
  expect (twinAndCtrl.sourceHash ==
      "dab9eb1fd462df9c0647b16a63fb10a1eeef4974e6b10fc82439650c6ae6da43")
    s!"bitwiseAnd 1&2 control sourceHash golden must remain stable; got {twinAndCtrl.sourceHash}"
  expect (twinAndCtrl.canonicalBytes.size == 225)
    s!"bitwiseAnd 1&2 control size golden must remain stable; got {twinAndCtrl.canonicalBytes.size}"
  expect (twinEq.sourceHash ==
      "d827bf3b1700b19f32e838340061b7ca3a9904048de0b9eb0bbad616e5f26618")
    s!"equal 1==2 control sourceHash golden must remain stable; got {twinEq.sourceHash}"
  expect (twinEq.canonicalBytes.size == 225)
    s!"equal 1==2 control size golden must remain stable; got {twinEq.canonicalBytes.size}"
  expect (twinAdd.sourceHash ==
      "b8756ed78018d4cfb2b98d38f4acf2685b8438a99e35531746e55076b3f527f7")
    s!"checkedAdd 1+2 control sourceHash golden must remain stable; got {twinAdd.sourceHash}"
  expect (twinAdd.canonicalBytes.size == 225)
    s!"checkedAdd 1+2 control size golden must remain stable; got {twinAdd.canonicalBytes.size}"

  -- Non-alias discriminators.
  expect (twin12.sourceHash != twin21.sourceHash)
    "bitwiseOr 1|2 must not alias 2|1 (operand order)"
  expect (twin12.sourceHash != twinXorCtrl.sourceHash)
    "bitwiseOr 1|2 must not alias bitwiseXor 1^2 (operator tag)"
  expect (twin12.sourceHash != twinAndCtrl.sourceHash)
    "bitwiseOr 1|2 must not alias bitwiseAnd 1&2 (operator tag)"
  expect (twin12.sourceHash != twinEq.sourceHash)
    "bitwiseOr 1|2 must not alias equal 1==2 (operator tag)"
  expect (twin12.sourceHash != twinAdd.sourceHash)
    "bitwiseOr 1|2 must not alias checkedAdd 1+2 (operator tag)"
  expect (twin12.canonicalBytes.size == twinXorCtrl.canonicalBytes.size)
    "bitwiseOr and bitwiseXor of two small literals must share size (tag-only distinction)"
  expect (twinAddOr.sourceHash != twinWrong.sourceHash)
    "1+2|3 must not alias wrong C-style 1+(2|3)"
  expect (twinAddOr.sourceHash != twinOrAdd.sourceHash)
    "1+2|3 must not alias 1|2+3"
  expect (twinMulOr.sourceHash != twinOrMul.sourceHash)
    "1*2|3 must not alias 1|2*3"
  expect (twinShlOr.sourceHash != twinOrShl.sourceHash)
    "1<<2|3 must not alias 1|2<<3"
  expect (twinShrOr.sourceHash != twinOrShr.sourceHash)
    "1>>2|3 must not alias 1|2>>3"
  expect (twinOrEq.sourceHash != twinEqOr.sourceHash)
    "1|2==3 must not alias 1==2|3"
  expect (twinAndOr.sourceHash != twinOrAnd.sourceHash)
    "1&2|3 must not alias 1|2&3"
  expect (twinXorOr.sourceHash != twinOrXor.sourceHash)
    "1^2|3 must not alias 1|2^3"
  expect (twinLeft.sourceHash != twinRight.sourceHash)
    "left-nested and right-nested bitwiseOr must not alias"
  expect (twinNegOr.sourceHash != twinOrNeg.sourceHash)
    "-1|2 must not alias 1|-2"
  expect (twinTF.sourceHash != twinFT.sourceHash)
    "true|false must not alias false|true"
  expect (twin00.sourceHash != twin12.sourceHash)
    "0|0 must not alias 1|2"

  -- Parser-boundary: malformed and deferred LogicOr.
  for (label, expr) in [
      ("bare or", "|"),
      ("missing lhs", "| 2"),
      ("missing rhs", "1 |"),
      ("spaced split", "1 | | 2"),
      ("extra token", "1 | 2 3")
    ] do
    let source := returnProgramSource "RejectedOrShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<or-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.bitwiseOr (.literal 1) (.literal 2))) with
  | .error (.invalidProgram
      "bitwise or is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject bitwiseOr with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing bitwiseOr"

  match Compiler.compile
      (twin (.bitwiseOr (.boolLiteral true) (.boolLiteral false))) with
  | .error (.invalidProgram
      "bitwise or is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject true|false with bitwise-or message before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept true|false programs"

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

end Tests.Language.BitwiseOr
