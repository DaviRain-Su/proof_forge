import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- ConstructorExprSurface pins ConstructorExpr (qualified path + args) in init/entry/view/fn
-- return and let positions. Migration: exactly LocalFnCalls A.B()/A.B(1) qualified negatives.
namespace Tests.Language.ConstructorExprsFixture

open ProofForgeV2.Language

program ConstructorExprSurface where
  init() do
    let seed : UInt64 := A.B(41)
    return seed

  entry run(n : UInt64) : UInt64 do
    return A.B(n, 1)

  view peek() : UInt64 do
    let v := A.B()
    return v

  fn helper() : UInt64 do
    return A.B(C.D(1), 2)

end Tests.Language.ConstructorExprsFixture

namespace Tests.Language.ConstructorExprs

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.ConstructorExprsFixture.ConstructorExprTwin" "ConstructorExprTwin" #[
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
  "namespace Tests.Language.ConstructorExprsFixture\n\n" ++
  "program ConstructorExprSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := A.B(41)\n" ++
  "    return seed\n\n" ++
  "  entry run(n : UInt64) : UInt64 do\n" ++
  "    return A.B(n, 1)\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let v := A.B()\n" ++
  "    return v\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return A.B(C.D(1), 2)\n\n" ++
  "end Tests.Language.ConstructorExprsFixture\n"

private def returnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
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

private def expectExactInvalid (label source expected : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram message) =>
      expect (message == expected)
        s!"{label}: expected exact '{expected}', got {message}"
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
  let elaborated := Tests.Language.ConstructorExprsFixture.ConstructorExprSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.constructorExpr #["A", "B"] #[.literal 41]),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := A.B(41)"
  | none => throw <| IO.userError "ConstructorExprSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue
            (.constructorExpr #["A", "B"] #[.variable "n", .literal 1])] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return A.B(n, 1)"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "v" none (.constructorExpr #["A", "B"] #[]),
          .returnValue (.variable "v")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let v := A.B() and return v"
  | _ => throw <| IO.userError "ConstructorExprSurface must retain run entry and peek view"
  match elaborated.functions.back? with
  | some helper =>
      expect (helper.name == "helper") "last fn must be helper"
      match helper.body with
      | #[.returnValue
            (.constructorExpr #["A", "B"]
              #[.constructorExpr #["C", "D"] #[.literal 1], .literal 2])] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn helper body must retain return A.B(C.D(1), 2)"
  | none => throw <| IO.userError "ConstructorExprSurface must retain functions"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<constructor-exprs>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same constructorExpr Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same constructorExpr sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Zero / spaced-zero / one / multi args (migrated A.B()/A.B(1) positives).
  let zero ← select session (returnProgramSource "Zero" "A.B()") "<ctor-zero>"
  expectReturnExpr "A.B()" zero (.constructorExpr #["A", "B"] #[])

  let zeroSpaced ← select session (returnProgramSource "Zero" "A.B ()") "<ctor-zero-sp>"
  expectReturnExpr "A.B ()" zeroSpaced (.constructorExpr #["A", "B"] #[])
  expect (zero == zeroSpaced)
    "A.B() and A.B () must share Source.Program under identical identity"
  expect (zero.canonicalBytes == zeroSpaced.canonicalBytes)
    "A.B() and A.B () must share canonical bytes under identical identity"
  expect (zero.sourceHash == zeroSpaced.sourceHash)
    "A.B() and A.B () must share sourceHash under identical identity"

  let one ← select session (returnProgramSource "One" "A.B(1)") "<ctor-one>"
  expectReturnExpr "A.B(1)" one (.constructorExpr #["A", "B"] #[.literal 1])

  let multi ← select session (returnProgramSource "Multi" "A.B(1, 2)") "<ctor-multi>"
  expectReturnExpr "A.B(1, 2)" multi
    (.constructorExpr #["A", "B"] #[.literal 1, .literal 2])

  -- Operator / string / group args.
  let opArgs ← select session
    (returnProgramSource "OpArgs" "A.B(1 + 2, \"x\")") "<ctor-op-str>"
  expectReturnExpr "A.B(1 + 2, \"x\")" opArgs
    (.constructorExpr #["A", "B"]
      #[.checkedAdd (.literal 1) (.literal 2), .stringLiteral "x"])

  let groupArg ← select session
    (returnProgramSource "GroupArg" "A.B((1))") "<ctor-group-arg>"
  let directArg ← select session
    (returnProgramSource "GroupArg" "A.B(1)") "<ctor-direct-arg>"
  expect (groupArg == directArg)
    "A.B((1)) and A.B(1) must share Source under identical identity"
  expect (groupArg.canonicalBytes == directArg.canonicalBytes)
    "A.B((1)) and A.B(1) must share canonical bytes"
  expect (groupArg.sourceHash == directArg.sourceHash)
    "A.B((1)) and A.B(1) must share sourceHash"
  expectReturnExpr "A.B((1))" groupArg (.constructorExpr #["A", "B"] #[.literal 1])

  -- Nested constructors.
  let nested ← select session
    (returnProgramSource "Nested" "A.B(C.D(1), 2)") "<ctor-nested>"
  expectReturnExpr "A.B(C.D(1), 2)" nested
    (.constructorExpr #["A", "B"]
      #[.constructorExpr #["C", "D"] #[.literal 1], .literal 2])

  -- Constructor as unary / binary operand.
  let unaryOp ← select session
    (returnProgramSource "UnaryOp" "-A.B(1)") "<ctor-unary-op>"
  expectReturnExpr "-A.B(1)" unaryOp
    (.checkedNeg (.constructorExpr #["A", "B"] #[.literal 1]))

  let binLeft ← select session
    (returnProgramSource "BinLeft" "A.B(1) + 2") "<ctor-bin-left>"
  expectReturnExpr "A.B(1) + 2" binLeft
    (.checkedAdd (.constructorExpr #["A", "B"] #[.literal 1]) (.literal 2))

  let binRight ← select session
    (returnProgramSource "BinRight" "1 + A.B(2)") "<ctor-bin-right>"
  expectReturnExpr "1 + A.B(2)" binRight
    (.checkedAdd (.literal 1) (.constructorExpr #["A", "B"] #[.literal 2]))

  -- Two- and multi-component paths; escaped portable component.
  let three ← select session
    (returnProgramSource "Three" "A.B.C(1)") "<ctor-three>"
  expectReturnExpr "A.B.C(1)" three
    (.constructorExpr #["A", "B", "C"] #[.literal 1])

  let escapedComp ← select session
    (returnProgramSource "Escaped" "A.«x»(1)") "<ctor-escaped-comp>"
  expectReturnExpr "A.«x»(1)" escapedComp
    (.constructorExpr #["A", "x"] #[.literal 1])

  let plainPath ← select session
    (returnProgramSource "EscapedPath" "A.B(1)") "<ctor-plain-path>"
  let escapedFirst ← select session
    (returnProgramSource "EscapedPath" "«A».B(1)") "<ctor-escaped-first>"
  let escapedSecond ← select session
    (returnProgramSource "EscapedPath" "A.«B»(1)") "<ctor-escaped-second>"
  expect (plainPath == escapedFirst && plainPath == escapedSecond)
    "escaped portable path components must preserve the canonical constructor path"

  -- Unqualified local call must remain localFnCall (classification).
  let localCall ← select session (returnProgramSource "Local" "f(1)") "<ctor-local>"
  expectReturnExpr "f(1)" localCall (.localFnCall "f" #[.literal 1])

  let dottedVariable ← select session
    (returnProgramSource "DottedVariable" "A.B") "<ctor-dotted-variable>"
  expectReturnExpr "bare A.B" dottedVariable (.variable "A.B")

  -- Whole-escaped dotted single-component stays localFnCall (empirical loader spelling).
  let wholeEscaped ← select session
    (returnProgramSource "WholeEsc" "«A.B»()") "<ctor-whole-escaped>"
  expectReturnExpr "«A.B»()" wholeEscaped (.localFnCall "«A.B»" #[])

  -- Prospective goldens (UNBOUND until GREEN).
  let twinZero := twin (.constructorExpr #["A", "B"] #[])
  let twinPathValue := twin (.constructorExpr #["A", "C"] #[])
  let twinOne := twin (.constructorExpr #["A", "B"] #[.literal 1])
  let twinArgValue := twin (.constructorExpr #["A", "B"] #[.literal 2])
  let twinTwo := twin (.constructorExpr #["A", "B"] #[.literal 1, .literal 2])
  let twinOrder := twin (.constructorExpr #["A", "B"] #[.literal 2, .literal 1])
  let twinPathOrder := twin (.constructorExpr #["B", "A"] #[])
  let twinPathCount := twin (.constructorExpr #["A", "B", "C"] #[])
  let twinNested := twin
    (.constructorExpr #["A", "B"]
      #[.constructorExpr #["C", "D"] #[.literal 1], .literal 2])
  let twinLocal := twin (.localFnCall "f" #[])
  let twinVarF := twin (.variable "f")
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twinZero.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_ZERO_GOLDEN")
    s!"constructorExpr A.B() ConstructorExprTwin sourceHash golden must remain stable; got {twinZero.sourceHash}"
  expect (twinPathValue.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_PATH_VALUE_GOLDEN")
    s!"constructorExpr A.C() ConstructorExprTwin sourceHash golden must remain stable; got {twinPathValue.sourceHash}"
  expect (twinOne.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_ONE_GOLDEN")
    s!"constructorExpr A.B(1) ConstructorExprTwin sourceHash golden must remain stable; got {twinOne.sourceHash}"
  expect (twinArgValue.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_ARG_VALUE_GOLDEN")
    s!"constructorExpr A.B(2) ConstructorExprTwin sourceHash golden must remain stable; got {twinArgValue.sourceHash}"
  expect (twinTwo.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_TWO_GOLDEN")
    s!"constructorExpr A.B(1,2) ConstructorExprTwin sourceHash golden must remain stable; got {twinTwo.sourceHash}"
  expect (twinOrder.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_ARG_ORDER_GOLDEN")
    s!"constructorExpr A.B(2,1) ConstructorExprTwin sourceHash golden must remain stable; got {twinOrder.sourceHash}"
  expect (twinPathOrder.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_PATH_ORDER_GOLDEN")
    s!"constructorExpr B.A() ConstructorExprTwin sourceHash golden must remain stable; got {twinPathOrder.sourceHash}"
  expect (twinPathCount.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_PATH_COUNT_GOLDEN")
    s!"constructorExpr A.B.C() ConstructorExprTwin sourceHash golden must remain stable; got {twinPathCount.sourceHash}"
  expect (twinNested.sourceHash ==
      "UNBOUND_CONSTRUCTOR_EXPR_NESTED_GOLDEN")
    s!"constructorExpr nested ConstructorExprTwin sourceHash golden must remain stable; got {twinNested.sourceHash}"

  -- Non-alias: path value/count/order, arg value/count/order/nesting, tag27 vs local26 vs variable1.
  expect (twinZero.sourceHash != twinPathValue.sourceHash)
    "A.B() must not alias A.C() (same-count path value)"
  expect (twinOne.sourceHash != twinArgValue.sourceHash)
    "A.B(1) must not alias A.B(2) (single-arg value)"
  expect (twinZero.sourceHash != twinOne.sourceHash)
    "A.B() must not alias A.B(1) (argument count)"
  expect (twinOne.sourceHash != twinTwo.sourceHash)
    "A.B(1) must not alias A.B(1, 2) (argument count)"
  expect (twinTwo.sourceHash != twinOrder.sourceHash)
    "A.B(1, 2) must not alias A.B(2, 1) (argument order)"
  expect (twinZero.sourceHash != twinPathOrder.sourceHash)
    "A.B() must not alias B.A() (component order)"
  expect (twinZero.sourceHash != twinPathCount.sourceHash)
    "A.B() must not alias A.B.C() (component count)"
  expect (twinTwo.sourceHash != twinNested.sourceHash)
    "flat A.B(1, 2) must not alias nested A.B(C.D(1), 2)"
  expect (twinZero.sourceHash != twinLocal.sourceHash)
    "constructorExpr A.B() must not alias localFnCall f() (tag 27 vs tag 26)"
  expect (twinZero.sourceHash != twinVarF.sourceHash)
    "constructorExpr A.B() must not alias variable f (tag 27 vs tag 1)"

  -- Parser-boundary rejects (malformed call-like list / numeric / empty component).
  for (label, expr) in [
      ("missing close paren", "A.B(1"),
      ("missing open paren", "A.B 1)"),
      ("leading comma", "A.B(,1)"),
      ("trailing comma", "A.B(1,)"),
      ("double comma", "A.B(1,,2)"),
      ("adjacent arg", "A.B(1 2)"),
      ("extra payload", "A.B(1) 2"),
      ("numeric component", "A.1()"),
      ("empty component", "A..B()")
    ] do
    let source := returnProgramSource "RejectedCtor" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<ctor-{label}>")
    expectParserRejected label source result

  -- Reserved / invalid qualified path components (decoded before arguments).
  for (label, expr, expected) in [
      ("reserved second component", "A.«struct»()",
        "reserved portable identifier 'struct'"),
      ("reserved first component", "«fn».B(1)",
        "reserved portable identifier 'fn'"),
      -- Invalid escaped component; string arg must not preempt path diagnostic.
      ("invalid dotted escaped component", "A.«x.y»(\"x\")",
        "qualified-name component must use Lean identifier characters")
    ] do
    let source := returnProgramSource "RejectedPath" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<ctor-{label}>")
    expectExactInvalid label source expected result

  -- Typed fail-before argument checking / constructor lookup.
  match Compiler.compile
      (twin (.constructorExpr #["A", "B"] #[.literal 1])) with
  | .error (.invalidProgram
      "constructor expressions are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject constructorExpr with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing constructorExpr"

  match Compiler.compile
      (twin (.constructorExpr #["A", "B"] #[.boolLiteral true])) with
  | .error (.invalidProgram
      "constructor expressions are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject constructorExpr before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept constructorExpr with Bool arg"

  match Compiler.compile
      (twin (.constructorExpr #["A", "B"] #[.stringLiteral "x"])) with
  | .error (.invalidProgram
      "constructor expressions are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject constructorExpr before string diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept constructorExpr with string arg"

  match Compiler.compile twinAdd with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

end Tests.Language.ConstructorExprs
