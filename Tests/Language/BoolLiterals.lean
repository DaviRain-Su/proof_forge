import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- BoolSurface pins bare true/false in every declaration body position: init, entry,
-- view, and fn. Covers both return-value and let-value reachability for boolLiteral.
namespace Tests.Language.BoolLiteralsFixture

open ProofForgeV2.Language

program BoolSurface where
  init() do
    let seed : Bool := true
    return seed

  entry run() : UInt64 do
    return false

  view peek() : UInt64 do
    let flag := true
    return 0

  fn helper() : UInt64 do
    return true

end Tests.Language.BoolLiteralsFixture

namespace Tests.Language.BoolLiterals

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.BoolLiteralsFixture.BoolTwin" "BoolTwin" #[
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
  "namespace Tests.Language.BoolLiteralsFixture\n\n" ++
  "program BoolSurface where\n" ++
  "  init() do\n" ++
  "    let seed : Bool := true\n" ++
  "    return seed\n\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return false\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let flag := true\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return true\n\n" ++
  "end Tests.Language.BoolLiteralsFixture\n"

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

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

/-- Assert entry body is exactly `return <expr>`. -/
private def expectReturnExpr (label : String) (sourceProgram : Source.Program)
    (expr : Source.Expr) : IO Unit := do
  match sourceProgram.entries with
  | #[runEntry] =>
      expect (runEntry.body == #[.returnValue expr])
        s!"{label}: entry body must be return of expected expression"
  | _ => throw <| IO.userError s!"{label}: expected a single entry"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.BoolLiteralsFixture.BoolSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "seed" (some .bool) (.boolLiteral true),
          .returnValue (.variable "seed")] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let seed : Bool := true and return seed"
  | none => throw <| IO.userError "BoolSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.boolLiteral false)] => pure ()
      | _ => throw <| IO.userError "entry body must retain return false as boolLiteral"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "flag" none (.boolLiteral true), .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain omitted-type let flag := true and return 0"
  | _ => throw <| IO.userError "BoolSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue (.boolLiteral true)] => pure ()
      | _ => throw <| IO.userError "fn body must retain return true as boolLiteral"
  | _ => throw <| IO.userError "BoolSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<bool-literals>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same bool-literal Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same bool-literal sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Frozen prospective goldens for BoolTwin boolLiteral vs integer-literal controls.
  let falseTwin := twin (.boolLiteral false)
  let trueTwin := twin (.boolLiteral true)
  let int0Twin := twin (.literal 0)
  let int1Twin := twin (.literal 1)
  expect (falseTwin.sourceHash ==
      "cbf554a833b9fd88fe8029b085547992d663c8e1fa13abc93a94e80e7ebf3ad4")
    s!"boolLiteral false BoolTwin sourceHash golden must remain stable; got {falseTwin.sourceHash}"
  expect (falseTwin.canonicalBytes.size == 201)
    s!"boolLiteral false BoolTwin canonical size golden must remain stable; got {falseTwin.canonicalBytes.size}"
  expect (trueTwin.sourceHash ==
      "f979745e8773cfe7caee45cb003801af2db23dd151bbda1b4c860aca9d453676")
    s!"boolLiteral true BoolTwin sourceHash golden must remain stable; got {trueTwin.sourceHash}"
  expect (trueTwin.canonicalBytes.size == 201)
    s!"boolLiteral true BoolTwin canonical size golden must remain stable; got {trueTwin.canonicalBytes.size}"
  expect (int0Twin.sourceHash ==
      "4bac3a3ee625da64b5c70416a5a289e44ffa007ed08320ebffb1141286fe46b0")
    s!"integer 0 BoolTwin sourceHash golden must remain stable; got {int0Twin.sourceHash}"
  expect (int0Twin.canonicalBytes.size == 208)
    s!"integer 0 BoolTwin canonical size golden must remain stable; got {int0Twin.canonicalBytes.size}"
  expect (int1Twin.sourceHash ==
      "b35a702ce96574ebb8abc004492d9a75cfc80f062c3765ca2a8e2bb17030a50f")
    s!"integer 1 BoolTwin sourceHash golden must remain stable; got {int1Twin.sourceHash}"
  expect (int1Twin.canonicalBytes.size == 208)
    s!"integer 1 BoolTwin canonical size golden must remain stable; got {int1Twin.canonicalBytes.size}"

  -- Distinctness: false/true/int0/int1 must not alias.
  expect (falseTwin.sourceHash != trueTwin.sourceHash)
    "boolLiteral false/true must bind sourceHash distinctly"
  expect (falseTwin.sourceHash != int0Twin.sourceHash)
    "boolLiteral false must not alias integer literal 0"
  expect (trueTwin.sourceHash != int1Twin.sourceHash)
    "boolLiteral true must not alias integer literal 1"
  expect (int0Twin.sourceHash != int1Twin.sourceHash)
    "integer literal 0/1 must bind sourceHash distinctly"

  -- One-byte marker implication: false/true share size (marker byte only) while
  -- integer UInt64 payloads are larger and same-width for 0/1.
  expect (falseTwin.canonicalBytes.size == trueTwin.canonicalBytes.size)
    "boolLiteral false/true must share canonical size (single marker byte payload)"
  expect (int0Twin.canonicalBytes.size == int1Twin.canonicalBytes.size)
    "integer 0/1 must share canonical size (fixed UInt64 payload)"
  expect (falseTwin.canonicalBytes.size + 7 == int0Twin.canonicalBytes.size)
    "boolLiteral must be 7 bytes smaller than UInt64 literal (tag+1 vs tag+8)"

  -- Bare true/false via ParserSession must decode as boolLiteral (not variable).
  let bareFalse ← select session
    (returnProgramSource "BareFalse" "false") "<bool-bare-false>"
  expectReturnExpr "bare false" bareFalse (.boolLiteral false)
  let bareTrue ← select session
    (returnProgramSource "BareTrue" "true") "<bool-bare-true>"
  expectReturnExpr "bare true" bareTrue (.boolLiteral true)

  -- Variable controls: escaped, qualified, case variants, trueValue/falseValue.
  for (label, spelling, name) in [
      ("escaped true", "«true»", "true"),
      ("escaped false", "«false»", "false"),
      ("qualified true", "Std.true", "Std.true"),
      ("qualified false", "Std.false", "Std.false"),
      ("case True", "True", "True"),
      ("case FALSE", "FALSE", "FALSE"),
      ("trueValue", "trueValue", "trueValue"),
      ("falseValue", "falseValue", "falseValue")
    ] do
    let control ← select session
      (returnProgramSource "VarControl" spelling) s!"<bool-var-{label}>"
    expectReturnExpr label control (.variable name)

  -- Parser-boundary: extra independent token after a bare bool literal.
  for (label, expr) in [
      ("extra token after true", "true false"),
      ("extra token after false", "false true"),
      ("extra numeral after true", "true 0")
    ] do
    let source := returnProgramSource "RejectedBoolShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<bool-{label}>")
    expectParserRejected label source result

  -- Typed fail-closed: Source may retain boolLiteral, but Typed.check must reject.
  match Compiler.compile (twin (.boolLiteral true)) with
  | .error (.invalidProgram
      "boolean literals are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject boolLiteral with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing boolLiteral"

end Tests.Language.BoolLiterals
