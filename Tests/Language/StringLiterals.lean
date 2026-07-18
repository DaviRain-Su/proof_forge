import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

-- StringSurface pins StringLiteral in every declaration body position: init, entry,
-- view, and fn (return and let values). Zero migration: no existing suite edits.
namespace Tests.Language.StringLiteralsFixture

open ProofForgeV2.Language

program StringSurface where
  init() do
    let label := "seed"
    return 0

  entry run() : UInt64 do
    return "ok"

  view peek() : UInt64 do
    let msg := "peek"
    return 0

  fn helper() : UInt64 do
    return "fn\t"

end Tests.Language.StringLiteralsFixture

namespace Tests.Language.StringLiterals

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Minimal entry-body twin isolating returnValue expr under one fixed identity. -/
private def twin (expr : Source.Expr) : Source.Program :=
  Source.Program.buildQualified
    "Tests.Language.StringLiteralsFixture.StringTwin" "StringTwin" #[
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
  "namespace Tests.Language.StringLiteralsFixture\n\n" ++
  "program StringSurface where\n" ++
  "  init() do\n" ++
  "    let label := \"seed\"\n" ++
  "    return 0\n\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return \"ok\"\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    let msg := \"peek\"\n" ++
  "    return 0\n\n" ++
  "  fn helper() : UInt64 do\n" ++
  "    return \"fn\\t\"\n\n" ++
  "end Tests.Language.StringLiteralsFixture\n"

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

private def expectReturnExpr (label : String) (sourceProgram : Source.Program)
    (expr : Source.Expr) : IO Unit := do
  match sourceProgram.entries with
  | #[runEntry] =>
      expect (runEntry.body == #[.returnValue expr])
        s!"{label}: entry body must be return of expected expression"
  | _ => throw <| IO.userError s!"{label}: expected a single entry"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.StringLiteralsFixture.StringSurface
  match elaborated.initializer with
  | some initializer =>
      match initializer.body with
      | #[.letDecl "label" none (.stringLiteral "seed"),
          .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "init body must retain let label := \"seed\" and return 0"
  | none => throw <| IO.userError "StringSurface must retain initializer"
  match elaborated.entries with
  | #[runEntry, peekView] =>
      match runEntry.body with
      | #[.returnValue (.stringLiteral "ok")] => pure ()
      | _ =>
          throw <| IO.userError
            "entry body must retain return \"ok\" as stringLiteral"
      expect (peekView.mode == .view) "peek must remain a view"
      match peekView.body with
      | #[.letDecl "msg" none (.stringLiteral "peek"),
          .returnValue (.literal 0)] =>
          pure ()
      | _ =>
          throw <| IO.userError
            "view body must retain omitted-type let msg := \"peek\" and return 0"
  | _ => throw <| IO.userError "StringSurface must retain run entry and peek view"
  match elaborated.functions with
  | #[helper] =>
      match helper.body with
      | #[.returnValue (.stringLiteral "fn\t")] => pure ()
      | _ =>
          throw <| IO.userError
            "fn body must retain return \"fn\\t\" as stringLiteral with tab value"
  | _ => throw <| IO.userError "StringSurface must retain helper fn"

  let session ← Language.Loader.ParserSession.create
  match ← session.selectProgram surfaceSource "<string-literals>" none with
  | .ok decoded =>
      expect (decoded == elaborated)
        "Loader and Lean command must produce the same string-literal Source.Program"
      expect (decoded.sourceHash == elaborated.sourceHash)
        "Loader and Lean command must produce the same string-literal sourceHash"
  | .error error => throw <| IO.userError error.render

  -- Exact decoded-value AST pins via ParserSession.
  let empty ← select session (returnProgramSource "Empty" "\"\"") "<str-empty>"
  expectReturnExpr "empty string" empty (.stringLiteral "")

  let ascii ← select session (returnProgramSource "Ascii" "\"hi\"") "<str-ascii>"
  expectReturnExpr "ASCII hi" ascii (.stringLiteral "hi")

  let escQuote ← select session
    (returnProgramSource "EscQuote" "\"\\\"\"") "<str-esc-quote>"
  expectReturnExpr "escaped quote" escQuote (.stringLiteral "\"")

  let escBackslash ← select session
    (returnProgramSource "EscBackslash" "\"\\\\\"") "<str-esc-backslash>"
  expectReturnExpr "escaped backslash" escBackslash (.stringLiteral "\\")

  let escTab ← select session
    (returnProgramSource "EscTab" "\"\\t\"") "<str-esc-tab>"
  expectReturnExpr "escaped tab" escTab (.stringLiteral "\t")

  let unicode ← select session
    (returnProgramSource "Unicode" "\"α\"") "<str-unicode>"
  expectReturnExpr "Unicode scalar α" unicode (.stringLiteral "α")

  -- Alternate Lean escape spellings that decode to the same String value.
  let newlineSpell ← select session
    (returnProgramSource "NewlineSame" "\"\\n\"") "<str-nl-spell>"
  let newlineHex ← select session
    (returnProgramSource "NewlineSame" "\"\\x0a\"") "<str-nl-hex>"
  expect (newlineSpell == newlineHex)
    "\"\\n\" and \"\\x0a\" must share Source.Program under identical identity"
  expect (newlineSpell.canonicalBytes == newlineHex.canonicalBytes)
    "\"\\n\" and \"\\x0a\" must share canonical bytes under identical identity"
  expect (newlineSpell.sourceHash == newlineHex.sourceHash)
    "\"\\n\" and \"\\x0a\" must share sourceHash under identical identity"
  expectReturnExpr "newline value" newlineSpell (.stringLiteral "\n")

  let alphaSpell ← select session
    (returnProgramSource "AlphaSame" "\"α\"") "<str-alpha-spell>"
  let alphaU ← select session
    (returnProgramSource "AlphaSame" "\"\\u03b1\"") "<str-alpha-u>"
  expect (alphaSpell == alphaU)
    "\"α\" and \"\\u03b1\" must share Source.Program under identical identity"
  expect (alphaSpell.canonicalBytes == alphaU.canonicalBytes)
    "\"α\" and \"\\u03b1\" must share canonical bytes under identical identity"
  expect (alphaSpell.sourceHash == alphaU.sourceHash)
    "\"α\" and \"\\u03b1\" must share sourceHash under identical identity"

  -- Prospective goldens (placeholders until GREEN production seam lands).
  let twinEmpty := twin (.stringLiteral "")
  let twinHi := twin (.stringLiteral "hi")
  let twinQuote := twin (.stringLiteral "\"")
  let twinBackslash := twin (.stringLiteral "\\")
  let twinTab := twin (.stringLiteral "\t")
  let twinAlpha := twin (.stringLiteral "α")
  let twinA := twin (.stringLiteral "a")
  let twinVarA := twin (.variable "a")
  let twinAdd := twin (.checkedAdd (.literal 1) (.literal 2))

  expect (twinEmpty.sourceHash ==
      "4cde697b099c9c7c778517b19f2a6f6468aa07c575682fe83cc35b0b7d1e443c")
    s!"stringLiteral empty StringTwin sourceHash golden must remain stable; got {twinEmpty.sourceHash}"
  expect (twinHi.sourceHash ==
      "a1d09765c39adc277751185ce9f0cf28c6d50809b0e79273747d242d41a2f80c")
    s!"stringLiteral hi StringTwin sourceHash golden must remain stable; got {twinHi.sourceHash}"
  expect (twinQuote.sourceHash ==
      "27488c4f1854da8f415becbda9bf7be6546707b691997b7a31f6a97d3cfcfcd5")
    s!"stringLiteral quote StringTwin sourceHash golden must remain stable; got {twinQuote.sourceHash}"
  expect (twinBackslash.sourceHash ==
      "535ea5e1f0725f98309fc792eb59eba2ffcf365c976662b3310700c9bb348453")
    s!"stringLiteral backslash StringTwin sourceHash golden must remain stable; got {twinBackslash.sourceHash}"
  expect (twinTab.sourceHash ==
      "39e8c5ec3fcc7759b6d26b12efb6f08429217cbbbb4de277e57b605c3691f951")
    s!"stringLiteral tab StringTwin sourceHash golden must remain stable; got {twinTab.sourceHash}"
  expect (twinAlpha.sourceHash ==
      "cebe2440eb6d1605ec287c20a76d31830299cb58efcc01073dec8a66cb92a527")
    s!"stringLiteral α StringTwin sourceHash golden must remain stable; got {twinAlpha.sourceHash}"
  expect (twinA.sourceHash ==
      "eae154b721a1c4ce5cbf1dee4de56f2827c7dfe37edc50cc46f16fa2cc4964d3")
    s!"stringLiteral a StringTwin sourceHash golden must remain stable; got {twinA.sourceHash}"

  -- Tag-only nonalias: string "a" vs variable a under fixed identity.
  expect (twinA.sourceHash != twinVarA.sourceHash)
    "stringLiteral \"a\" must not alias variable a (tag 25 vs tag 1)"
  expect (twinEmpty.sourceHash != twinHi.sourceHash)
    "empty string must not alias ASCII hi"
  expect (twinHi.sourceHash != twinTab.sourceHash)
    "ASCII hi must not alias tab payload"
  expect (twinAlpha.sourceHash != twinHi.sourceHash)
    "Unicode α must not alias ASCII hi"

  -- Parser-boundary: adjacent literals, interpolated s!, unterminated string.
  for (label, expr) in [
      ("adjacent literals", "\"a\" \"b\""),
      ("interpolated s!", "s!\"a\"")
    ] do
    let source := returnProgramSource "RejectedStringShape" expr
    let (_, result) ← IO.FS.withIsolatedStreams
      (session.parsePrograms source s!"<str-{label}>")
    expectParserRejected label source result

  let unterminatedSource :=
    "import ProofForgeV2\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program RejectedUnterminated where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return \"unterminated\n"
  let (_, unterminatedResult) ← IO.FS.withIsolatedStreams
    (session.parsePrograms unterminatedSource "<str-unterminated>")
  expectParserRejected "unterminated string" unterminatedSource unterminatedResult

  -- Typed fail-closed before operand checking.
  match Compiler.compile (twin (.stringLiteral "hi")) with
  | .error (.invalidProgram
      "string literals are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject stringLiteral with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept programs containing stringLiteral"

  match Compiler.compile (twin (.stringLiteral "")) with
  | .error (.invalidProgram
      "string literals are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError
        s!"Typed must reject empty stringLiteral with exact message, got {other.render}"
  | .ok _ =>
      throw <| IO.userError "Typed must not accept empty stringLiteral programs"

  match Compiler.compile twinAdd with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError
        s!"existing checkedAdd twin must still compile successfully, got {error.render}"

end Tests.Language.StringLiterals
