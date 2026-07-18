import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- LocalFnCallSurface pins complete LocalFnCall (zero/one/multi args) in init/entry/view/fn
-- return and let positions. Migration: exactly Grouping.lean call-like `f(1)`.
namespace Tests.Language.LocalFnCallsFixture

open ProofForgeV2.Language

program LocalFnCallSurface where
  fn f() : UInt64 do
    return 0

  fn g(x : UInt64) : UInt64 do
    return x

  fn h(a : UInt64, b : UInt64) : UInt64 do
    return a

  init() do
    let seed : UInt64 := g(41)
    return seed

  entry run(n : UInt64) : UInt64 do
    return h(n, 1)

  view peek() : UInt64 do
    let v := f()
    return v

  fn helper() : UInt64 do
    return g(h(1, 2))

end Tests.Language.LocalFnCallsFixture

namespace Tests.Language.LocalFnCalls

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.LocalFnCallsFixture.LocalFnCallTwin" "LocalFnCallTwin" #[
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
  "namespace Tests.Language.LocalFnCallsFixture\n\n" ++
  "program LocalFnCallSurface where\n" ++
  "  fn f() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "  fn g(x : UInt64) : UInt64 do\n" ++
  "    return x\n\n" ++
  "  fn h(a : UInt64, b : UInt64) : UInt64 do\n" ++
  "    return a\n\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := g(41)\n" ++
  "    return seed\n\n" ++
  "  entry run(n : UInt64) : UInt64 do\n" ++
  "    return h(n, 1)\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let v := f()\n" ++
  "    return v\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return g(h(1, 2))\n\n" ++
  "end Tests.Language.LocalFnCallsFixture\n"

private def returnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private def programWithFn (name fnDecls expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  fnDecls ++
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
  let elaborated := Tests.Language.LocalFnCallsFixture.LocalFnCallSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.localFnCall "g" #[.literal 41]),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := g(41)"
  | none => throw <| IO.userError "LocalFnCallSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue
            (.localFnCall "h" #[.variable "n", .literal 1])] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return h(n, 1)"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "v" none (.localFnCall "f" #[]),
          .returnValue (.variable "v")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let v := f() and return v"
  | _ => throw <| IO.userError "LocalFnCallSurface must retain run entry and peek view"
  -- functions: f, g, h, helper — helper is last
  match elaborated.functions.back? with
  | some helper =>
      expect (helper.name == "helper") "last fn must be helper"
      match helper.body with
      | #[.returnValue
            (.localFnCall "g"
              #[.localFnCall "h" #[.literal 1, .literal 2]])] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn helper body must retain return g(h(1, 2))"
  | none => throw <| IO.userError "LocalFnCallSurface must retain functions"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<local-fn-calls>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same localFnCall Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same localFnCall sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Zero / spaced-zero / one / multi args.
  let zero ← select session (returnProgramSource "Zero" "f()") "<call-zero>"
  expectReturnExpr "f()" zero (.localFnCall "f" #[])

  let zeroSpaced ← select session (returnProgramSource "Zero" "f ()") "<call-zero-sp>"
  expectReturnExpr "f ()" zeroSpaced (.localFnCall "f" #[])
  expect (zero == zeroSpaced)
    "f() and f () must share Source.Program under identical identity"
  expect (zero.canonicalBytes == zeroSpaced.canonicalBytes)
    "f() and f () must share canonical bytes under identical identity"
  expect (zero.sourceHash == zeroSpaced.sourceHash)
    "f() and f () must share sourceHash under identical identity"

  let one ← select session (returnProgramSource "One" "f(1)") "<call-one>"
  expectReturnExpr "f(1)" one (.localFnCall "f" #[.literal 1])

  let multi ← select session (returnProgramSource "Multi" "f(1, 2)") "<call-multi>"
  expectReturnExpr "f(1, 2)" multi
    (.localFnCall "f" #[.literal 1, .literal 2])

  -- Operator / string / group args.
  let opArgs ← select session
    (returnProgramSource "OpArgs" "f(1 + 2, \"x\")") "<call-op-str>"
  expectReturnExpr "f(1 + 2, \"x\")" opArgs
    (.localFnCall "f"
      #[.checkedAdd (.literal 1) (.literal 2), .stringLiteral "x"])

  let groupArg ← select session
    (returnProgramSource "GroupArg" "f((1))") "<call-group-arg>"
  let directArg ← select session
    (returnProgramSource "GroupArg" "f(1)") "<call-direct-arg>"
  expect (groupArg == directArg)
    "f((1)) and f(1) must share Source under identical identity"
  expect (groupArg.canonicalBytes == directArg.canonicalBytes)
    "f((1)) and f(1) must share canonical bytes"
  expect (groupArg.sourceHash == directArg.sourceHash)
    "f((1)) and f(1) must share sourceHash"
  expectReturnExpr "f((1))" groupArg (.localFnCall "f" #[.literal 1])

  -- Nested calls.
  let nested ← select session
    (returnProgramSource "Nested" "f(g(1), 2)") "<call-nested>"
  expectReturnExpr "f(g(1), 2)" nested
    (.localFnCall "f"
      #[.localFnCall "g" #[.literal 1], .literal 2])

  -- Call as unary / binary operand.
  let unaryOp ← select session
    (returnProgramSource "UnaryOp" "-f(1)") "<call-unary-op>"
  expectReturnExpr "-f(1)" unaryOp
    (.checkedNeg (.localFnCall "f" #[.literal 1]))

  let binLeft ← select session
    (returnProgramSource "BinLeft" "f(1) + 2") "<call-bin-left>"
  expectReturnExpr "f(1) + 2" binLeft
    (.checkedAdd (.localFnCall "f" #[.literal 1]) (.literal 2))

  let binRight ← select session
    (returnProgramSource "BinRight" "1 + f(2)") "<call-bin-right>"
  expectReturnExpr "1 + f(2)" binRight
    (.checkedAdd (.literal 1) (.localFnCall "f" #[.literal 2]))

  -- Escaped ordinary single-component callee.
  let escaped ← select session
    (returnProgramSource "Escaped" "«g»(1)") "<call-escaped>"
  expectReturnExpr "«g»(1)" escaped (.localFnCall "g" #[.literal 1])

  -- Prospective goldens (UNBOUND until GREEN).
  let twinZero := twin (.localFnCall "f" #[])
  let twinOne := twin (.localFnCall "f" #[.literal 1])
  let twinTwo := twin (.localFnCall "f" #[.literal 1, .literal 2])
  let twinOrder := twin (.localFnCall "f" #[.literal 2, .literal 1])
  let twinCallee := twin (.localFnCall "g" #[.literal 1])
  let twinNested := twin
    (.localFnCall "f" #[.localFnCall "g" #[.literal 1], .literal 2])
  let twinVarF := twin (.variable "f")
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twinZero.sourceHash ==
      "UNBOUND_LOCAL_FN_CALL_ZERO_GOLDEN")
    s!"localFnCall f() LocalFnCallTwin sourceHash golden must remain stable; got {twinZero.sourceHash}"
  expect (twinOne.sourceHash ==
      "UNBOUND_LOCAL_FN_CALL_ONE_GOLDEN")
    s!"localFnCall f(1) LocalFnCallTwin sourceHash golden must remain stable; got {twinOne.sourceHash}"
  expect (twinTwo.sourceHash ==
      "UNBOUND_LOCAL_FN_CALL_TWO_GOLDEN")
    s!"localFnCall f(1,2) LocalFnCallTwin sourceHash golden must remain stable; got {twinTwo.sourceHash}"
  expect (twinOrder.sourceHash ==
      "UNBOUND_LOCAL_FN_CALL_ORDER_GOLDEN")
    s!"localFnCall f(2,1) LocalFnCallTwin sourceHash golden must remain stable; got {twinOrder.sourceHash}"
  expect (twinCallee.sourceHash ==
      "UNBOUND_LOCAL_FN_CALL_CALLEE_GOLDEN")
    s!"localFnCall g(1) LocalFnCallTwin sourceHash golden must remain stable; got {twinCallee.sourceHash}"
  expect (twinNested.sourceHash ==
      "UNBOUND_LOCAL_FN_CALL_NESTED_GOLDEN")
    s!"localFnCall nested LocalFnCallTwin sourceHash golden must remain stable; got {twinNested.sourceHash}"

  -- Non-alias: callee, count, order, nesting, tag26 vs variable tag1.
  expect (twinZero.sourceHash != twinOne.sourceHash)
    "f() must not alias f(1) (argument count)"
  expect (twinOne.sourceHash != twinTwo.sourceHash)
    "f(1) must not alias f(1, 2) (argument count)"
  expect (twinTwo.sourceHash != twinOrder.sourceHash)
    "f(1, 2) must not alias f(2, 1) (argument order)"
  expect (twinOne.sourceHash != twinCallee.sourceHash)
    "f(1) must not alias g(1) (callee)"
  expect (twinTwo.sourceHash != twinNested.sourceHash)
    "flat f(1, 2) must not alias nested f(g(1), 2)"
  expect (twinZero.sourceHash != twinVarF.sourceHash)
    "localFnCall f() must not alias variable f (tag 26 vs tag 1)"

  -- Parser-boundary rejects.
  for (label, expr) in [
      ("missing close paren", "f(1"),
      ("missing open paren", "f 1)"),
      ("leading comma", "f(,1)"),
      ("trailing comma", "f(1,)"),
      ("double comma", "f(1,,2)"),
      ("adjacent arg", "f(1 2)"),
      ("extra payload", "f(1) 2"),
      ("unescaped reserved", "state(1)")
    ] do
    let source := returnProgramSource "RejectedCall" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<call-{label}>")
    expectParserRejected label source result

  -- Qualified constructor retention: exact unqualified-callee diagnostic (before args).
  for (label, expr) in [
      ("qualified zero", "A.B()"),
      ("qualified one", "A.B(1)")
    ] do
    let source := returnProgramSource "RejectedQualified" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<call-{label}>")
    expectExactInvalid label source
      "local function call callee must be unqualified" result

  -- Typed fail-before argument checking / fn lookup.
  match Compiler.compile (twin (.localFnCall "f" #[.literal 1])) with
  | .error (.invalidProgram
      "local function calls are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject localFnCall with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing localFnCall"

  match Compiler.compile
      (twin (.localFnCall "f" #[.boolLiteral true])) with
  | .error (.invalidProgram
      "local function calls are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject localFnCall before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept localFnCall with Bool arg"

  match Compiler.compile
      (twin (.localFnCall "f" #[.stringLiteral "x"])) with
  | .error (.invalidProgram
      "local function calls are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject localFnCall before string diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept localFnCall with string arg"

  match Compiler.compile twinAdd with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

end Tests.Language.LocalFnCalls
