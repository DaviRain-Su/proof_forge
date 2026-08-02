/-
  Tests.Typed.ContextExtensionCheckV1 — T-2 context/extension CheckV1 gate.
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CheckV1
import ProofForgeV2.Typed.ContextExtensionCheckV1
import Tests.Language.ParserSession

namespace Tests.Typed.ContextExtensionCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CheckV1
open ProofForgeV2.Typed.ContextExtensionCheckV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def hasSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private unsafe def load (session : ParserSession) (src label mod_ : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 src label mod_ none with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e.render}"

private unsafe def testAdmittedCallerOk (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program CtxOk where\n" ++
    "  entry run() : Principal do\n" ++
    "    return context.caller\n"
  let v ← load session src "<ctx-ok>" "Tests.CtxOk"
  let r := checkContextExtensionResultV1 v
  expect (r.ok && r.diagnostics.isEmpty) "admitted context.caller ok"
  expect (checkProgramTypedResultV1 v).ok "CheckV1 ok with caller"

/-- Non-admitted `context.*` place that still name-resolves: state named
    `context` with field `foo` is not ContextRead (only caller/unixTimeSeconds
    are admitted). NameResolution/TypeCheck succeed; ContextExtensionCheck
    must emit the exact reqPrecondition gate. -/
private unsafe def testBadContextSurface (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program CtxBad where\n" ++
    "  struct Bag where\n" ++
    "    foo : UInt64\n" ++
    "  state context : Bag\n" ++
    "  init() do\n" ++
    "    context := Bag.new(0)\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return context.foo\n"
  let v ← load session src "<ctx-bad>" "Tests.CtxBad"
  let r := checkContextExtensionResultV1 v
  expect r.analysisComplete
    "ctx-bad: ContextExtension analysis must complete (resolution ok)"
  expect (!r.ok) "ctx-bad: ContextExtension must fail closed"
  expect (r.diagnostics.size ≥ 1) "ctx-bad: must emit diagnostics"
  let d := r.diagnostics[0]!
  expect (d.code == .reqPrecondition)
    s!"ctx-bad: code must be reqPrecondition, got {d.code.wire}"
  expect (d.message ==
      "unsupported context surface (only context.caller and context.unixTimeSeconds are admitted)")
    s!"ctx-bad: exact message, got {d.message}"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok) "ctx-bad: CheckV1 composition must fail"
  expect (composed.diagnostics.any fun x =>
      x.code == .reqPrecondition &&
        x.message ==
          "unsupported context surface (only context.caller and context.unixTimeSeconds are admitted)")
    "ctx-bad: CheckV1 must surface the same ContextExtension gate"

private unsafe def testExtensionFailClosed (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program ExtBad where\n" ++
    "  requires extension proof.forge.feature version \"1.0.0\"\n" ++
    "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let v ← load session src "<ext-bad>" "Tests.ExtBad"
  let r := checkContextExtensionResultV1 v
  expect (!r.ok) "extension must fail closed on engineering Check"
  expect (r.diagnostics.any fun d => d.code == .ext001)
    "extension uses ext001"
  expect (!(checkProgramTypedResultV1 v).ok) "CheckV1 composition fails"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAdmittedCallerOk session
  testBadContextSurface session
  testExtensionFailClosed session
  IO.println "Tests.Typed.ContextExtensionCheckV1: ok"

end Tests.Typed.ContextExtensionCheckV1
