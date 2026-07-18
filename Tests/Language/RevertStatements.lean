import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

-- RevertSurface pins complete revertStmt (bare/empty/full ExprList) in init/entry/view/fn.
-- Zero migration: no existing suite edits.
namespace Tests.Language.RevertStatementsFixture

open ProofForgeV2.Language

program RevertSurface where
  error Err
  error Multi(a : UInt64, b : UInt64)

  init() do
    revert Err
    return 0

  entry run(n : UInt64) : UInt64 do
    revert Multi(n, 1)
    return 0

  view peek() : UInt64 do
    revert Err()
    return 0

  fn helper() : UInt64 do
    revert Multi(1 + 2, f(1))
    return 0

end Tests.Language.RevertStatementsFixture

-- Escaped assignment identifier must remain assign, not revert keyword.
namespace Tests.Language.RevertStatementsFixture

open ProofForgeV2.Language

program RevertAssignmentControl where
  state «revert» : UInt64

  init() do
    «revert» := 1

  entry get() : UInt64 do
    return «revert»

end Tests.Language.RevertStatementsFixture

namespace Tests.Language.RevertStatements

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating a single statement under fixed identity. -/
private def twin (stmt : Source.Statement) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.RevertStatementsFixture.RevertTwin" "RevertTwin" #[
    .entry {
      name := "run"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[stmt, .returnValue (.literal 0)]
    }
  ]

private def returnTwin : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.RevertStatementsFixture.RevertTwin" "RevertTwin" #[
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
  "namespace Tests.Language.RevertStatementsFixture\n\n" ++
  "program RevertSurface where\n" ++
  "  error Err\n" ++
  "  error Multi(a : UInt64, b : UInt64)\n\n" ++
  "  init() do\n" ++
  "    revert Err\n" ++
  "    return 0\n\n" ++
  "  entry run(n : UInt64) : UInt64 do\n" ++
  "    revert Multi(n, 1)\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    revert Err()\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    revert Multi(1 + 2, f(1))\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.RevertStatementsFixture\n"

private def assignmentControlSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.RevertStatementsFixture\n\n" ++
  "program RevertAssignmentControl where\n" ++
  "  state «revert» : UInt64\n\n" ++
  "  init() do\n" ++
  "    «revert» := 1\n\n" ++
  "  entry get() : UInt64 do\n" ++
  "    return «revert»\n\n" ++
  "end Tests.Language.RevertStatementsFixture\n"

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

private def expectBody (label : String) (sourceProgram : Source.Program)
    (stmt : Source.Statement) : IO Unit := do
  match sourceProgram.entries with
  | #[runEntry] =>
      expect (runEntry.body == #[stmt, .returnValue (.literal 0)])
        s!"{label}: entry body must retain expected statement then return 0"
  | _ => throw <| IO.userError s!"{label}: expected a single entry"

set_option maxRecDepth 2048 in
unsafe def run : IO Unit := do
  let elaborated := Tests.Language.RevertStatementsFixture.RevertSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.revertStmt "Err" #[], .returnValue (.literal 0)] => pure ()
      | _ =>
          throw <| IO.userError "init body must retain revert Err then return 0"
  | none => throw <| IO.userError "RevertSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.revertStmt "Multi" #[.variable "n", .literal 1],
          .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError "entry body must retain revert Multi(n, 1)"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.revertStmt "Err" #[], .returnValue (.literal 0)] => pure ()
      | _ =>
          throw <| IO.userError "view body must retain revert Err()"
  | _ => throw <| IO.userError "RevertSurface must retain run entry and peek view"
  match elaborated.functions.back? with
  | some helper =>
      expect (helper.name == "helper") "last fn must be helper"
      match helper.body with
      | #[.revertStmt "Multi"
            #[.checkedAdd (.literal 1) (.literal 2),
              .localFnCall "f" #[.literal 1]],
          .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "fn helper body must retain revert Multi(1 + 2, f(1))"
  | none => throw <| IO.userError "RevertSurface must retain functions"

  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgram surfaceSource "<revert-statements>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same revertStmt Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same revertStmt sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Bare vs empty-paren canonical equality.
  let bare ← select session (bodyProgramSource "Bare" "revert Err") "<rev-bare>"
  expectBody "revert Err" bare (.revertStmt "Err" #[])

  let empty ← select session (bodyProgramSource "Bare" "revert Err()") "<rev-empty>"
  expectBody "revert Err()" empty (.revertStmt "Err" #[])
  expect (bare == empty)
    "revert Err and revert Err() must share Source.Program under identical identity"
  expect (bare.canonicalBytes == empty.canonicalBytes)
    "revert Err and revert Err() must share canonical bytes under identical identity"
  expect (bare.sourceHash == empty.sourceHash)
    "revert Err and revert Err() must share sourceHash under identical identity"

  let emptySpaced ← select session
    (bodyProgramSource "Bare" "revert Err ()") "<rev-empty-sp>"
  expectBody "revert Err ()" emptySpaced (.revertStmt "Err" #[])
  expect (emptySpaced == bare)
    "revert Err () must share Source with bare under identical identity"

  -- One / multi args.
  -- Longest-match control: parenthesized rule must win over bare strict-prefix
  -- fallback. If bare swallowed `revert Err` first, `(1)` would be leftover
  -- payload and fail at the statement parser instead of forming one arg.
  let one ← select session (bodyProgramSource "One" "revert Err(1)") "<rev-one>"
  expectBody "revert Err(1)" one (.revertStmt "Err" #[.literal 1])
  expect (one != bare)
    "revert Err(1) must not collapse to bare revert Err (parenthesized longest match)"

  let multi ← select session
    (bodyProgramSource "Multi" "revert Multi(1, 2)") "<rev-multi>"
  expectBody "revert Multi(1, 2)" multi
    (.revertStmt "Multi" #[.literal 1, .literal 2])

  -- Operator / group / string / local-call / constructor / index args and nested tree.
  let opArgs ← select session
    (bodyProgramSource "OpArgs" "revert Err(1 + 2, \"x\")") "<rev-op-str>"
  expectBody "revert Err(1 + 2, \"x\")" opArgs
    (.revertStmt "Err"
      #[.checkedAdd (.literal 1) (.literal 2), .stringLiteral "x"])

  let groupArg ← select session
    (bodyProgramSource "GroupArg" "revert Err((1))") "<rev-group>"
  let directArg ← select session
    (bodyProgramSource "GroupArg" "revert Err(1)") "<rev-direct>"
  expect (groupArg == directArg)
    "grouped and direct same argument must share Source under identical identity"
  expectBody "revert Err((1))" groupArg (.revertStmt "Err" #[.literal 1])

  let callArg ← select session
    (bodyProgramSource "CallArg" "revert Err(f(1))") "<rev-call>"
  expectBody "revert Err(f(1))" callArg
    (.revertStmt "Err" #[.localFnCall "f" #[.literal 1]])

  let ctorArg ← select session
    (bodyProgramSource "CtorArg" "revert Err(A.B(1))") "<rev-ctor>"
  expectBody "revert Err(A.B(1))" ctorArg
    (.revertStmt "Err" #[.constructorExpr #["A", "B"] #[.literal 1]])

  let indexArg ← select session
    (bodyProgramSource "IdxArg" "revert Err(x[0])") "<rev-idx>"
  expectBody "revert Err(x[0])" indexArg
    (.revertStmt "Err" #[.indexAccess "x" (.literal 0)])

  let nested ← select session
    (bodyProgramSource "Nested" "revert Err(f(g(1)), 2)") "<rev-nested>"
  expectBody "revert Err(f(g(1)), 2)" nested
    (.revertStmt "Err"
      #[.localFnCall "f" #[.localFnCall "g" #[.literal 1]], .literal 2])

  -- Prospective goldens (UNBOUND until GREEN).
  let twinBare := twin (.revertStmt "Err" #[])
  let twinOne := twin (.revertStmt "Err" #[.literal 1])
  let twinTwo := twin (.revertStmt "Err" #[.literal 1, .literal 2])
  let twinOrder := twin (.revertStmt "Err" #[.literal 2, .literal 1])
  let twinName := twin (.revertStmt "Other" #[])
  let twinNested := twin
    (.revertStmt "Err"
      #[.localFnCall "f" #[.localFnCall "g" #[.literal 1]], .literal 2])
  let twinCall := twin (.synchronousCall "Err")
  let twinAssert := twin (.assertStmt (.boolLiteral true))
  let twinReturn := twin (.returnValue (.literal 0))

  expect (twinBare.sourceHash ==
      "c52fc7afa243bb9ea5e9ebe28a6094525c137462d78e83312041216c51d90716")
    s!"revertStmt Err RevertTwin sourceHash golden must remain stable; got {twinBare.sourceHash}"
  expect (toString twinBare.canonicalBytes.size ==
      "236")
    s!"revertStmt Err RevertTwin size golden must remain stable; got {twinBare.canonicalBytes.size}"
  expect (twinOne.sourceHash ==
      "b2b26b8586fc68dc45ad8c99c6a0a36208d060699bee3618bf033b7e12074f67")
    s!"revertStmt Err(1) RevertTwin sourceHash golden must remain stable; got {twinOne.sourceHash}"
  expect (toString twinOne.canonicalBytes.size ==
      "245")
    s!"revertStmt Err(1) RevertTwin size golden must remain stable; got {twinOne.canonicalBytes.size}"
  expect (twinTwo.sourceHash ==
      "9732b4f7ae5ad6670d51d95af81001d19622bed60116eb9561c15152bb3019a1")
    s!"revertStmt Err(1,2) RevertTwin sourceHash golden must remain stable; got {twinTwo.sourceHash}"
  expect (twinOrder.sourceHash ==
      "f118fe75245f1cc69ebd46d9965177d9a4a8a5cb51dc32aa377e2f5cd912744e")
    s!"revertStmt Err(2,1) RevertTwin sourceHash golden must remain stable; got {twinOrder.sourceHash}"
  expect (twinName.sourceHash ==
      "ec29ebf0a385d704e795e81f1e9f656410dfae920a0cb8bdec9a74e8680c5acb")
    s!"revertStmt Other RevertTwin sourceHash golden must remain stable; got {twinName.sourceHash}"
  expect (twinNested.sourceHash ==
      "045cd8c6c2f5a1906da0b3704a5b245e717792537fa55cfabbd18dc9fc3ec9c5")
    s!"revertStmt nested RevertTwin sourceHash golden must remain stable; got {twinNested.sourceHash}"

  -- Non-alias: name, arg count/order/nesting, tag5 vs call tag2 / assert / return.
  expect (twinBare.sourceHash != twinOne.sourceHash)
    "Err must not alias Err(1) (argument count)"
  expect (twinOne.sourceHash != twinTwo.sourceHash)
    "Err(1) must not alias Err(1, 2) (argument count)"
  expect (twinTwo.sourceHash != twinOrder.sourceHash)
    "Err(1, 2) must not alias Err(2, 1) (argument order)"
  expect (twinBare.sourceHash != twinName.sourceHash)
    "Err must not alias Other (error name)"
  expect (twinTwo.sourceHash != twinNested.sourceHash)
    "flat Err(1, 2) must not alias nested argument tree"
  expect (twinBare.sourceHash != twinCall.sourceHash)
    "revertStmt Err must not alias synchronousCall Err (tag 5 vs tag 2)"
  expect (twinBare.sourceHash != twinAssert.sourceHash)
    "revertStmt must not alias assertStmt"
  expect (twinBare.sourceHash != twinReturn.sourceHash)
    "revertStmt must not alias returnValue"

  -- Parser-boundary rejects.
  for (label, body) in [
      ("missing name", "revert"),
      ("missing close paren", "revert Err(1"),
      ("missing open paren", "revert Err 1)"),
      ("leading comma", "revert Err(,1)"),
      ("trailing comma", "revert Err(1,)"),
      ("double comma", "revert Err(1,,2)"),
      ("adjacent arg", "revert Err(1 2)"),
      ("extra payload", "revert Err 1"),
      ("unescaped keyword assign", "revert := 1")
    ] do
    let source := bodyProgramSource "RejectedRevert" body
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<rev-{label}>")
    expectParserRejected label source result

  -- Qualified name before argument decode (Bool must not preempt).
  let qualifiedSource := bodyProgramSource "RejectedQualified" "revert A.B(true)"
  let (_, qualifiedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms qualifiedSource "<rev-qualified>")
  expectExactInvalid "qualified name before Bool arg" qualifiedSource
    "revert error name must be unqualified" qualifiedResult

  -- Reserved portable name policy before args.
  let reservedSource := bodyProgramSource "RejectedReserved" "revert «struct»(1)"
  let (_, reservedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms reservedSource "<rev-reserved>")
  expectExactInvalid "reserved error name" reservedSource
    "reserved portable identifier 'struct'" reservedResult

  -- Escaped assignment identifier retention.
  let assignControl := Tests.Language.RevertStatementsFixture.RevertAssignmentControl
  match assignControl.initializer with
  | some initializer =>
      expect (initializer.body == #[.assign "revert" (.literal 1)])
        "«revert» := 1 must remain Source.Statement.assign to identifier 'revert'"
  | none => throw <| IO.userError "RevertAssignmentControl must retain initializer"
  match ← session.selectProgram assignmentControlSource "<revert-assignment-control>" none with
  | .ok decoded =>
      expect (decoded == assignControl)
        "Loader and Lean command must agree on revert-assignment positive control"
  | .error error => throw <| IO.userError error.render

  -- Typed fail-before error lookup / argument checking.
  match Compiler.compile (twin (.revertStmt "Err" #[])) with
  | .error (.invalidProgram
      "revert statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject revertStmt with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing revertStmt"

  match Compiler.compile (twin (.revertStmt "Missing" #[])) with
  | .error (.invalidProgram
      "revert statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject revert before unknown-name diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept revert with unknown name"

  match Compiler.compile
      (twin (.revertStmt "Err" #[.boolLiteral true])) with
  | .error (.invalidProgram
      "revert statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject revert before Bool diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept revert with Bool arg"

  match Compiler.compile
      (twin (.revertStmt "Err" #[.stringLiteral "x"])) with
  | .error (.invalidProgram
      "revert statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject revert before string diagnostic, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept revert with string arg"

  -- Existing statement controls still compile under RevertTwin identity.
  match Compiler.compile returnTwin with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"return control under RevertTwin must still compile, got {error.render}"

  match Compiler.compile (twin (.assertStmt (.boolLiteral true))) with
  | .error (.invalidProgram
      "assert statements are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"assert control must keep exact assert fail-closed, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "assert control must not compile successfully"

  let assignTwin :=
    Source.Program.buildQualified
      "Tests.Language.RevertStatementsFixture.RevertTwin" "RevertTwin" #[
      .stateDecl { name := "cell", type := .u64 },
      .entry {
        name := "run"
        params := #[]
        result := .u64
        mode := .mutate
        body := #[
          .assign "cell" (.literal 1),
          .returnValue (.literal 0)
        ]
      }
    ]
  match Compiler.compile assignTwin with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"assign control under RevertTwin must still compile, got {error.render}"

end Tests.Language.RevertStatements
