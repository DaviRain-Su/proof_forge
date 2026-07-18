import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- EmitSurface pins the complete mandatory-parentheses emit Source carrier.
-- Zero migration: no existing suite edits.
namespace Tests.Language.EmitStatementsFixture

open ProofForgeV2.Language

program EmitSurface where
  event Tick()
  event Transfer(value : UInt64)
  event Log(first : UInt64, second : UInt64)

  init() do
    emit Tick()
    return 0

  entry run(value : UInt64) : UInt64 do
    emit Transfer(value)
    return 0

  view peek() : UInt64 do
    emit Log(1 + 2, "hi")
    return 0

  fn helper() : UInt64 do
    emit Log(f(1), A.B(2))
    return 0

end Tests.Language.EmitStatementsFixture

namespace Tests.Language.EmitStatementsFixture

open ProofForgeV2.Language

program EmitAssignmentControl where
  state «emit» : UInt64

  init() do
    «emit» := 1

  entry get() : UInt64 do
    return «emit»

end Tests.Language.EmitStatementsFixture

namespace Tests.Language.EmitStatements

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Fixed-identity statement twin followed by one valid value return. -/
private def twin (statement : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.EmitStatementsFixture.EmitTwin" "EmitTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[statement, .returnValue (.literal 0)]
    }
  ]

private def returnTwin : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.EmitStatementsFixture.EmitTwin" "EmitTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue (.literal 0)]
    }
  ]

private def eventTableControl : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.EmitStatementsFixture.EventTableControl" "EventTableControl" #[
    .eventDecl { name := "Tick", params := #[] },
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue (.literal 0)]
    }
  ]

private def surfaceSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.EmitStatementsFixture\n\n" ++
  "program EmitSurface where\n" ++
  "  event Tick()\n" ++
  "  event Transfer(value : UInt64)\n" ++
  "  event Log(first : UInt64, second : UInt64)\n\n" ++
  "  init() do\n" ++
  "    emit Tick()\n" ++
  "    return 0\n\n" ++
  "  entry run(value : UInt64) : UInt64 do\n" ++
  "    emit Transfer(value)\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    emit Log(1 + 2, \"hi\")\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    emit Log(f(1), A.B(2))\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.EmitStatementsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.EmitStatementsFixture\n\n" ++
  "program EmitAssignmentControl where\n" ++
  "  state «emit» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «emit» := 1\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «emit»\n\n" ++
  "end Tests.Language.EmitStatementsFixture\n"

private def bodyProgramSource (name body : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    " ++ body ++ "\n" ++
  "    return 0\n"

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
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}' for {source}"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private unsafe def decodeFirst (session : Language.Loader.ParserSession)
    (name body : String) : IO Source.Statement := do
  let decoded ← select session (bodyProgramSource name body) s!"<emit-{name}>"
  match decoded.entries with
  | #[onlyEntry] =>
      match onlyEntry.body with
      | #[statement, .returnValue (.literal 0)] => pure statement
      | _ => throw <| IO.userError s!"{name}: expected emit then return body"
  | _ => throw <| IO.userError s!"{name}: expected one entry"

private def expectGolden (label : String) (source : Source.Program)
    (expectedHash expectedSize : String) : IO Unit := do
  expect (source.sourceHash == expectedHash)
    s!"{label} sourceHash golden must remain stable; got {source.sourceHash}"
  expect (toString source.canonicalBytes.size == expectedSize)
    s!"{label} canonical size must remain stable; got {source.canonicalBytes.size}"

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.EmitStatementsFixture.EmitSurface
  match elaborated.initializer with
  | some initializer =>
      expect (initializer.body == #[.emitStmt "Tick" #[], .returnValue (.literal 0)])
        "initializer must retain empty-argument emitStmt"
  | none => throw <| IO.userError "EmitSurface initializer missing"
  match elaborated.entries with
  | #[runEntry, peekEntry] =>
      expect (runEntry.body == #[.emitStmt "Transfer" #[.variable "value"],
          .returnValue (.literal 0)])
        "entry must retain variable emit argument"
      expect (peekEntry.body == #[.emitStmt "Log" #[.checkedAdd (.literal 1) (.literal 2),
          .stringLiteral "hi"], .returnValue (.literal 0)])
        "view must retain operator and string emit arguments"
  | _ => throw <| IO.userError "EmitSurface must retain entry and view"
  match elaborated.functions with
  | #[helper] =>
      expect (helper.body == #[.emitStmt "Log" #[.localFnCall "f" #[.literal 1],
          .constructorExpr #["A", "B"] #[.literal 2]], .returnValue (.literal 0)])
        "fn must retain local-call and constructor emit arguments"
  | _ => throw <| IO.userError "EmitSurface helper missing"

  let session ← Tests.Language.ParserSession.shared
  let decoded ← select session surfaceSource "<emit-surface>"
  expect (decoded == elaborated)
    "Loader and Lean command must agree on complete emit Source"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must agree on emit source identity"

  let empty ← decodeFirst session "EmitEmpty" "emit Tick()"
  let one ← decodeFirst session "EmitOne" "emit Tick(1)"
  let two ← decodeFirst session "EmitTwo" "emit Tick(1, 2)"
  let ordered ← decodeFirst session "EmitOrder" "emit Tick(2, 1)"
  let direct ← decodeFirst session "EmitDirect" "emit Tick(1 + 2)"
  let grouped ← decodeFirst session "EmitGrouped" "emit Tick((1 + 2))"
  let stringArg ← decodeFirst session "EmitString" "emit Tick(\"hi\")"
  let localCall ← decodeFirst session "EmitLocal" "emit Tick(f(1))"
  let constructor ← decodeFirst session "EmitCtor" "emit Tick(A.B(1))"
  let index ← decodeFirst session "EmitIndex" "emit Tick(x[0])"
  let nested ← decodeFirst session "EmitNested" "emit Tick(A.B(f(x[0])))"
  expect (empty == .emitStmt "Tick" #[]) "emit Tick() must retain empty args"
  expect (one == .emitStmt "Tick" #[.literal 1]) "emit Tick(1) must retain one arg"
  expect (two == .emitStmt "Tick" #[.literal 1, .literal 2])
    "emit Tick(1, 2) must retain argument order"
  expect (ordered == .emitStmt "Tick" #[.literal 2, .literal 1])
    "emit Tick(2, 1) must retain reversed argument order"
  expect (direct == .emitStmt "Tick" #[.checkedAdd (.literal 1) (.literal 2)] &&
      grouped == direct)
    "grouping must desugar while preserving the complete emit expression"
  expect (stringArg == .emitStmt "Tick" #[.stringLiteral "hi"])
    "emit must retain string arguments"
  expect (localCall == .emitStmt "Tick" #[.localFnCall "f" #[.literal 1]])
    "emit must retain local-call arguments"
  expect (constructor == .emitStmt "Tick" #[.constructorExpr #["A", "B"] #[.literal 1]])
    "emit must retain constructor arguments"
  expect (index == .emitStmt "Tick" #[.indexAccess "x" (.literal 0)])
    "emit must retain index arguments"
  expect (nested == .emitStmt "Tick" #[.constructorExpr #["A", "B"]
      #[.localFnCall "f" #[.indexAccess "x" (.literal 0)]]])
    "emit must retain nested argument trees"

  let twinEmpty := twin (.emitStmt "Tick" #[])
  let twinOne := twin (.emitStmt "Tick" #[.literal 1])
  let twinTwo := twin (.emitStmt "Tick" #[.literal 1, .literal 2])
  let twinOrder := twin (.emitStmt "Tick" #[.literal 2, .literal 1])
  let twinName := twin (.emitStmt "Tock" #[])
  let twinNested := twin (.emitStmt "Tick" #[.constructorExpr #["A", "B"]
    #[.localFnCall "f" #[.indexAccess "x" (.literal 0)]]])
  expectGolden "emit empty" twinEmpty
    "UNBOUND_EMIT_EMPTY_HASH" "UNBOUND_EMIT_EMPTY_SIZE"
  expectGolden "emit one" twinOne
    "UNBOUND_EMIT_ONE_HASH" "UNBOUND_EMIT_ONE_SIZE"
  expectGolden "emit two" twinTwo
    "UNBOUND_EMIT_TWO_HASH" "UNBOUND_EMIT_TWO_SIZE"
  expectGolden "emit order" twinOrder
    "UNBOUND_EMIT_ORDER_HASH" "UNBOUND_EMIT_ORDER_SIZE"
  expectGolden "emit name" twinName
    "UNBOUND_EMIT_NAME_HASH" "UNBOUND_EMIT_NAME_SIZE"
  expectGolden "emit nested" twinNested
    "UNBOUND_EMIT_NESTED_HASH" "UNBOUND_EMIT_NESTED_SIZE"

  expect (twinEmpty.sourceHash != twinOne.sourceHash &&
      twinOne.sourceHash != twinTwo.sourceHash &&
      twinTwo.sourceHash != twinOrder.sourceHash &&
      twinEmpty.sourceHash != twinName.sourceHash &&
      twinTwo.sourceHash != twinNested.sourceHash)
    "emit event name, argument count/order/value/tree must bind source identity"
  expect (twinEmpty.sourceHash != (twin (.revertStmt "Tick" #[])).sourceHash)
    "emit tag 7 must not alias revert tag 5"
  expect (twinEmpty.sourceHash != (twin (.synchronousCall "Tick")).sourceHash)
    "emit must not alias synchronousCall"
  expect (twinOne.sourceHash != (twin (.assertStmt (.literal 1))).sourceHash)
    "emit must not alias assertStmt"
  expect (twinOne.sourceHash != (twin (.returnValue (.literal 1))).sourceHash)
    "emit must not alias returnValue"

  for (label, body) in [
      ("missing name", "emit"),
      ("missing name before paren", "emit (1)"),
      ("bare name", "emit Tick"),
      ("missing open paren", "emit Tick 1)"),
      ("missing close paren", "emit Tick(1"),
      ("leading comma", "emit Tick(,1)"),
      ("trailing comma", "emit Tick(1,)"),
      ("double comma", "emit Tick(1,,2)"),
      ("adjacent argument", "emit Tick(1 2)"),
      ("extra payload", "emit Tick() 1"),
      ("unescaped keyword assign", "emit := 1")
    ] do
    let source := bodyProgramSource "RejectedEmit" body
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<emit-{label}>")
    expectParserRejected label source result

  let qualifiedSource := bodyProgramSource "QualifiedEmit" "emit A.B(true)"
  let (_, qualifiedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms qualifiedSource "<emit-qualified>")
  expectExactInvalid "qualified event before Bool arg" qualifiedSource
    "emit event name must be unqualified" qualifiedResult

  let reservedSource := bodyProgramSource "ReservedEmit" "emit «struct»(true)"
  let (_, reservedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms reservedSource "<emit-reserved>")
  expectExactInvalid "reserved event before Bool arg" reservedSource
    "reserved portable identifier 'struct'" reservedResult

  let assignmentControl := Tests.Language.EmitStatementsFixture.EmitAssignmentControl
  match assignmentControl.initializer with
  | some initializer =>
      expect (initializer.body == #[.assign "emit" (.literal 1)])
        "escaped emit assignment must remain assign"
  | none => throw <| IO.userError "EmitAssignmentControl initializer missing"
  match ← session.selectProgram assignmentControlSource "<emit-assignment>" none with
  | .ok control =>
      expect (control == assignmentControl)
        "Loader and Lean command must agree on escaped emit assignment"
  | .error error => throw <| IO.userError error.render

  for (label, statement) in [
      ("literal", Source.Statement.emitStmt "Tick" #[.literal 1]),
      ("bool", Source.Statement.emitStmt "Tick" #[.boolLiteral true]),
      ("string", Source.Statement.emitStmt "Tick" #[.stringLiteral "x"])
    ] do
    match Compiler.compile (twin statement) with
    | .error (.invalidProgram
        "emit statements are not yet supported by typed checking") => pure ()
    | .error other =>
        throw <| IO.userError s!"{label}: Typed emit priority mismatch: {other.render}"
    | .ok _ => throw <| IO.userError s!"{label}: Typed unexpectedly accepted emit"

  match Compiler.compile eventTableControl with
  | .error (.invalidProgram
      "event declarations are not yet supported by typed checking") => pure ()
  | .error other =>
      throw <| IO.userError s!"generic event gate changed: {other.render}"
  | .ok _ => throw <| IO.userError "event table unexpectedly compiled"

  match Compiler.compile returnTwin with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"return control failed: {error.render}"
  match Compiler.compile (twin (.assertStmt (.boolLiteral true))) with
  | .error (.invalidProgram
      "assert statements are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"assert control changed: {other.render}"
  | .ok _ => throw <| IO.userError "assert control unexpectedly compiled"
  match Compiler.compile (twin (.revertStmt "Err" #[])) with
  | .error (.invalidProgram
      "revert statements are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"revert control changed: {other.render}"
  | .ok _ => throw <| IO.userError "revert control unexpectedly compiled"

end Tests.Language.EmitStatements
