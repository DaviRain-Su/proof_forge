import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- IndexAccessSurface pins bare-base rvalue indexAccess in init/entry/view/fn return and let.
-- Zero migration: no existing suite edits.
namespace Tests.Language.IndexAccessesFixture

open ProofForgeV2.Language

program IndexAccessSurface where
  init() do
    let seed : UInt64 := x[41]
    return seed

  entry run(n : UInt64) : UInt64 do
    return x[n]

  view peek() : UInt64 do
    let v := x[0]
    return v

  fn helper() : UInt64 do
    return x[1 + 2]

end Tests.Language.IndexAccessesFixture

namespace Tests.Language.IndexAccesses

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.IndexAccessesFixture.IndexAccessTwin" "IndexAccessTwin" #[
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
  "namespace Tests.Language.IndexAccessesFixture\n\n" ++
  "program IndexAccessSurface where\n" ++
  "  init() do\n" ++
  "    let seed : UInt64 := x[41]\n" ++
  "    return seed\n\n" ++
  "  entry run(n : UInt64) : UInt64 do\n" ++
  "    return x[n]\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let v := x[0]\n" ++
  "    return v\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return x[1 + 2]\n\n" ++
  "end Tests.Language.IndexAccessesFixture\n"

private def returnProgramSource (name expr : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return " ++ expr ++ "\n"

private def assignProgramSource (name stmt : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  state cell : UInt64\n" ++
  "  entry run() : UInt64 do\n" ++
  "    " ++ stmt ++ "\n" ++
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
  let elaborated := Tests.Language.IndexAccessesFixture.IndexAccessSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .u64)
            (.indexAccess "x" (.literal 41)),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : UInt64 := x[41]"
  | none => throw <| IO.userError "IndexAccessSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.indexAccess "x" (.variable "n"))] =>
          pure ()
      | _ =>
          throw <| IO.userError "entry body must retain return x[n]"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "v" none (.indexAccess "x" (.literal 0)),
          .returnValue (.variable "v")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain let v := x[0] and return v"
  | _ => throw <| IO.userError "IndexAccessSurface must retain run entry and peek view"
  match elaborated.functions.back? with
  | some helper =>
      expect (helper.name == "helper") "last fn must be helper"
      match helper.body with
      | #[.returnValue
            (.indexAccess "x"
              (.checkedAdd (.literal 1) (.literal 2)))] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn helper body must retain return x[1 + 2]"
  | none => throw <| IO.userError "IndexAccessSurface must retain functions"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<index-accesses>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same indexAccess Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same indexAccess sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Spacing equality: x[0] vs x [0].
  let zero ← select session (returnProgramSource "Zero" "x[0]") "<idx-zero>"
  expectReturnExpr "x[0]" zero (.indexAccess "x" (.literal 0))

  let zeroSpaced ← select session (returnProgramSource "Zero" "x [0]") "<idx-zero-sp>"
  expectReturnExpr "x [0]" zeroSpaced (.indexAccess "x" (.literal 0))
  expect (zero == zeroSpaced)
    "x[0] and x [0] must share Source.Program under identical identity"
  expect (zero.canonicalBytes == zeroSpaced.canonicalBytes)
    "x[0] and x [0] must share canonical bytes under identical identity"
  expect (zero.sourceHash == zeroSpaced.sourceHash)
    "x[0] and x [0] must share sourceHash under identical identity"

  -- Escaped ordinary single-component base.
  let escapedBase ← select session
    (returnProgramSource "Escaped" "«x»[0]") "<idx-escaped-base>"
  expectReturnExpr "«x»[0]" escapedBase (.indexAccess "x" (.literal 0))
  expect (escapedBase == zero)
    "escaped portable base must share Source under identical identity"
  expect (escapedBase.sourceHash == zero.sourceHash)
    "escaped portable base must share sourceHash under identical identity"

  -- Full operator / group / local-call / constructor index expressions.
  let opIndex ← select session
    (returnProgramSource "OpIdx" "x[1 + 2]") "<idx-op>"
  expectReturnExpr "x[1 + 2]" opIndex
    (.indexAccess "x" (.checkedAdd (.literal 1) (.literal 2)))

  let groupIndex ← select session
    (returnProgramSource "GroupIdx" "x[(1)]") "<idx-group>"
  let directIndex ← select session
    (returnProgramSource "GroupIdx" "x[1]") "<idx-direct>"
  expect (groupIndex == directIndex)
    "x[(1)] and x[1] must share Source under identical identity"
  expect (groupIndex.canonicalBytes == directIndex.canonicalBytes)
    "x[(1)] and x[1] must share canonical bytes"
  expect (groupIndex.sourceHash == directIndex.sourceHash)
    "x[(1)] and x[1] must share sourceHash"
  expectReturnExpr "x[(1)]" groupIndex (.indexAccess "x" (.literal 1))

  let callIndex ← select session
    (returnProgramSource "CallIdx" "x[f(1)]") "<idx-call>"
  expectReturnExpr "x[f(1)]" callIndex
    (.indexAccess "x" (.localFnCall "f" #[.literal 1]))

  let ctorIndex ← select session
    (returnProgramSource "CtorIdx" "x[A.B(1)]") "<idx-ctor>"
  expectReturnExpr "x[A.B(1)]" ctorIndex
    (.indexAccess "x" (.constructorExpr #["A", "B"] #[.literal 1]))

  -- Index access as unary / binary operand.
  let unaryOp ← select session
    (returnProgramSource "UnaryOp" "-x[0]") "<idx-unary-op>"
  expectReturnExpr "-x[0]" unaryOp
    (.checkedNeg (.indexAccess "x" (.literal 0)))

  let binLeft ← select session
    (returnProgramSource "BinLeft" "x[0] + 1") "<idx-bin-left>"
  expectReturnExpr "x[0] + 1" binLeft
    (.checkedAdd (.indexAccess "x" (.literal 0)) (.literal 1))

  let binRight ← select session
    (returnProgramSource "BinRight" "1 + x[0]") "<idx-bin-right>"
  expectReturnExpr "1 + x[0]" binRight
    (.checkedAdd (.literal 1) (.indexAccess "x" (.literal 0)))

  -- Prospective goldens (UNBOUND until GREEN).
  let twinZero := twin (.indexAccess "x" (.literal 0))
  let twinOne := twin (.indexAccess "x" (.literal 1))
  let twinBaseY := twin (.indexAccess "y" (.literal 0))
  let twinOp := twin
    (.indexAccess "x" (.checkedAdd (.literal 1) (.literal 2)))
  let twinCall := twin
    (.indexAccess "x" (.localFnCall "f" #[.literal 1]))
  let twinCtor := twin
    (.indexAccess "x" (.constructorExpr #["A", "B"] #[.literal 1]))
  let twinVarX := twin (.variable "x")
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twinZero.sourceHash ==
      "UNBOUND_INDEX_ACCESS_ZERO_GOLDEN")
    s!"indexAccess x[0] IndexAccessTwin sourceHash golden must remain stable; got {twinZero.sourceHash}"
  expect (twinOne.sourceHash ==
      "UNBOUND_INDEX_ACCESS_ONE_GOLDEN")
    s!"indexAccess x[1] IndexAccessTwin sourceHash golden must remain stable; got {twinOne.sourceHash}"
  expect (twinBaseY.sourceHash ==
      "UNBOUND_INDEX_ACCESS_BASE_Y_GOLDEN")
    s!"indexAccess y[0] IndexAccessTwin sourceHash golden must remain stable; got {twinBaseY.sourceHash}"
  expect (twinOp.sourceHash ==
      "UNBOUND_INDEX_ACCESS_OP_GOLDEN")
    s!"indexAccess x[1+2] IndexAccessTwin sourceHash golden must remain stable; got {twinOp.sourceHash}"
  expect (twinCall.sourceHash ==
      "UNBOUND_INDEX_ACCESS_CALL_GOLDEN")
    s!"indexAccess x[f(1)] IndexAccessTwin sourceHash golden must remain stable; got {twinCall.sourceHash}"
  expect (twinCtor.sourceHash ==
      "UNBOUND_INDEX_ACCESS_CTOR_GOLDEN")
    s!"indexAccess x[A.B(1)] IndexAccessTwin sourceHash golden must remain stable; got {twinCtor.sourceHash}"

  -- Non-alias: base value, index value/tree, tag28 vs variable tag1.
  expect (twinZero.sourceHash != twinOne.sourceHash)
    "x[0] must not alias x[1] (index value)"
  expect (twinZero.sourceHash != twinBaseY.sourceHash)
    "x[0] must not alias y[0] (base value)"
  expect (twinOne.sourceHash != twinOp.sourceHash)
    "x[1] must not alias x[1 + 2] (index tree)"
  expect (twinZero.sourceHash != twinVarX.sourceHash)
    "indexAccess x[0] must not alias variable x (tag 28 vs tag 1)"

  -- Parser-boundary rejects.
  for (label, expr) in [
      ("missing close bracket", "x[0"),
      ("missing open bracket", "x 0]"),
      ("empty index", "x[]"),
      ("missing base", "[0]"),
      ("extra payload", "x[0] 1"),
      ("grouped base", "(x)[0]"),
      ("call base", "f()[0]"),
      ("chained index", "x[0][1]")
    ] do
    let source := returnProgramSource "RejectedIdx" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<idx-{label}>")
    expectParserRejected label source result

  -- Indexed assignment must fail closed (not bare-ident assign).
  let assignSource := assignProgramSource "RejectedAssign" "x[0] := 1"
  let (_, assignResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms assignSource "<idx-assign>")
  expectParserRejected "indexed assignment" assignSource assignResult

  -- Qualified base before index decode (Bool index must not preempt).
  let qualifiedSource := returnProgramSource "RejectedQualified" "A.B[true]"
  let (_, qualifiedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms qualifiedSource "<idx-qualified>")
  expectExactInvalid "qualified base before Bool index" qualifiedSource
    "index access base must be unqualified" qualifiedResult

  -- Reserved portable base policy (decoded before index).
  let reservedSource := returnProgramSource "RejectedReserved" "«struct»[0]"
  let (_, reservedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms reservedSource "<idx-reserved>")
  expectExactInvalid "reserved base" reservedSource
    "reserved portable identifier 'struct'" reservedResult

  -- Typed fail-before base resolution / index checking.
  match Compiler.compile
      (twin (.indexAccess "x" (.literal 0))) with
  | .error (.invalidProgram
      "index access is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject indexAccess with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing indexAccess"

  match Compiler.compile
      (twin (.indexAccess "missing" (.literal 0))) with
  | .error (.invalidProgram
      "index access is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject indexAccess before unknown-base diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept indexAccess with unknown base"

  match Compiler.compile
      (twin (.indexAccess "x" (.boolLiteral true))) with
  | .error (.invalidProgram
      "index access is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject indexAccess before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept indexAccess with Bool index"

  match Compiler.compile
      (twin (.indexAccess "x" (.stringLiteral "i"))) with
  | .error (.invalidProgram
      "index access is not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject indexAccess before string diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept indexAccess with string index"

  match Compiler.compile twinAdd with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

end Tests.Language.IndexAccesses
