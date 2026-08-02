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

private unsafe def testBadContextSurface (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program CtxBad where\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return context.authorizers\n"
  let v ← load session src "<ctx-bad>" "Tests.CtxBad"
  let r := checkContextExtensionResultV1 v
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok) "unsupported context surface must not pass CheckV1"
  -- When analysis completes, expect dedicated context gate; otherwise NR/type
  -- may fail first with empty context-phase drafts.
  if r.analysisComplete && !r.ok then
    expect (r.diagnostics.any fun d =>
        hasSubstr d.message "unsupported context" ||
        d.code == .reqPrecondition ||
        hasSubstr d.message "context")
      s!"context phase diagnostic: {r.diagnostics.map (·.message)}"
  else
    expect (composed.diagnostics.size ≥ 1)
      s!"composed must fail with diags: {composed.diagnostics.map (·.message)}"

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
