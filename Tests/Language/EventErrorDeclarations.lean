import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.EventErrorDeclarationsFixture

open ProofForgeV2.Language

program EventErrorSurface where
  event Transfer(from : UInt64, to : UInt64)
  event Tick()
  error Unauthorized
  error Insufficient(balance : UInt64, needed : UInt64)

  entry ping() : UInt64 do
    return 0

end Tests.Language.EventErrorDeclarationsFixture

namespace Tests.Language.EventErrorDeclarations

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.EventErrorDeclarationsFixture\n\n" ++
  "program EventErrorSurface where\n" ++
  "  event Transfer(from : UInt64, to : UInt64)\n" ++
  "  event Tick()\n" ++
  "  error Unauthorized\n" ++
  "  error Insufficient(balance : UInt64, needed : UInt64)\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.EventErrorDeclarationsFixture\n"

private def programSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private def expectInvalid (label expected : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}'"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  let elaborated := Tests.Language.EventErrorDeclarationsFixture.EventErrorSurface
  match elaborated.events with
  | #[transfer, tick] =>
      expect (transfer.name == "Transfer" &&
          transfer.params.map (fun param => (param.name, param.type)) ==
            #[("from", .u64), ("to", .u64)])
        "event name and parameter order must survive Lean command elaboration"
      expect (tick.name == "Tick" && tick.params.isEmpty)
        "an empty event parameter list must survive Lean command elaboration"
  | _ => throw <| IO.userError "EventErrorSurface must retain two event declarations"
  match elaborated.errors with
  | #[unauthorized, insufficient] =>
      expect (unauthorized.name == "Unauthorized" && unauthorized.params.isEmpty)
        "an error without parentheses must materialize an empty parameter list"
      expect (insufficient.name == "Insufficient" &&
          insufficient.params.map (fun param => (param.name, param.type)) ==
            #[("balance", .u64), ("needed", .u64)])
        "error name and parameter order must survive Lean command elaboration"
  | _ => throw <| IO.userError "EventErrorSurface must retain two error declarations"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<event-error-declarations>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same event/error Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same event/error source hash"

  let canonicalBase ← select session
    (programSource "CanonicalEventError" "") "<event-error-base>"
  let canonicalEventAB ← select session
    (programSource "CanonicalEventError" "  event A(value : UInt64)\n  event B()\n")
    "<event-error-event-ab>"
  let canonicalEventBA ← select session
    (programSource "CanonicalEventError" "  event B()\n  event A(value : UInt64)\n")
    "<event-error-event-ba>"
  let canonicalErrorNoParens ← select session
    (programSource "CanonicalEventError" "  error Failed\n")
    "<event-error-error-no-parens>"
  let canonicalErrorEmptyParens ← select session
    (programSource "CanonicalEventError" "  error Failed()\n")
    "<event-error-error-empty-parens>"
  expect (canonicalBase.sourceHash != canonicalEventAB.sourceHash &&
      canonicalEventAB.sourceHash != canonicalEventBA.sourceHash &&
      canonicalBase.sourceHash != canonicalErrorNoParens.sourceHash)
    "event/error declarations, parameters, and within-kind order must bind the source hash"
  expect (canonicalErrorNoParens == canonicalErrorEmptyParens &&
      canonicalErrorNoParens.sourceHash == canonicalErrorEmptyParens.sourceHash)
    "omitted and explicit empty error parameter lists must canonicalize identically"

  expectInvalid "duplicate event declarations"
    "program 'DuplicateEvent' contains duplicate event declarations"
    (← session.parsePrograms
      (programSource "DuplicateEvent" "  event Changed()\n  event Changed()\n")
      "<duplicate-event>")
  expectInvalid "duplicate error declarations"
    "program 'DuplicateError' contains duplicate error declarations"
    (← session.parsePrograms
      (programSource "DuplicateError" "  error Failed\n  error Failed()\n")
      "<duplicate-error>")
  expectInvalid "event parameter declaration order"
    "event 'First' contains duplicate parameters"
    (← session.parsePrograms
      (programSource "DuplicateEventParam"
        "  event First(value : UInt64, value : UInt64)\n  event Second(other : UInt64, other : UInt64)\n")
      "<duplicate-event-param>")
  expectInvalid "error parameter declaration order"
    "error 'First' contains duplicate parameters"
    (← session.parsePrograms
      (programSource "DuplicateErrorParam"
        "  error First(value : UInt64, value : UInt64)\n  error Second(other : UInt64, other : UInt64)\n")
      "<duplicate-error-param>")

  match Typed.check elaborated with
  | .error (.invalidProgram "event declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"event declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "typed checking must not silently erase event declarations"

  let errorOnly ← select session
    (programSource "ErrorOnly" "  error Failed\n") "<error-only>"
  match Typed.check errorOnly with
  | .error (.invalidProgram "error declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"error declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "typed checking must not silently erase error declarations"

end Tests.Language.EventErrorDeclarations
