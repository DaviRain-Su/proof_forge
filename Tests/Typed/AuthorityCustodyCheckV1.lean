/-
  Tests.Typed.AuthorityCustodyCheckV1 — T-1 authority/custody engineering.

  Drives shipped `checkAuthorityCustodyResultV1` and product `CheckV1`
  composition. Authority is not PF-VIS-001; uses reqPrecondition messages.
-/
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.AuthorityCustodyCheckV1
import ProofForgeV2.Typed.CheckV1
import Tests.Language.ParserSession

namespace Tests.Typed.AuthorityCustodyCheckV1

open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.AuthorityCustodyCheckV1
open ProofForgeV2.Typed.CheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def hasSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private unsafe def load (session : ParserSession)
    (src label moduleName : String) : IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 src label moduleName none with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e.render}"

/-- Positive: private state write with context.caller authority evidence. -/
private unsafe def testPrivateWriteWithCaller
    (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program AuthOk where\n" ++
    "  state private secret : UInt64\n" ++
    "  init() do\n" ++
    "    secret := 0\n" ++
    "  entry setSecret(v : UInt64) : UInt64 do\n" ++
    "    let who : Principal := context.caller\n" ++
    "    secret := v\n" ++
    "    return v\n"
  let v ← load session src "<auth-ok>" "Tests.AuthOk"
  let r := checkAuthorityCustodyResultV1 v
  expect r.analysisComplete "AuthOk analysis complete"
  expect r.ok "AuthOk authority/custody ok"
  expect (r.diagnostics.isEmpty) "AuthOk no diagnostics"
  let composed := checkProgramTypedResultV1 v
  expect composed.ok "AuthOk CheckV1 ok"
  expect composed.analysisComplete "AuthOk CheckV1 complete"

/-- Negative: private state write on entry without context.caller. -/
private unsafe def testPrivateWriteWithoutCaller
    (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program AuthFail where\n" ++
    "  state private secret : UInt64\n" ++
    "  init() do\n" ++
    "    secret := 0\n" ++
    "  entry setSecret(v : UInt64) : UInt64 do\n" ++
    "    secret := v\n" ++
    "    return v\n"
  let v ← load session src "<auth-fail>" "Tests.AuthFail"
  let r := checkAuthorityCustodyResultV1 v
  expect r.analysisComplete "AuthFail analysis complete"
  expect (!r.ok) "AuthFail not ok"
  expect (r.diagnostics.size ≥ 1) "AuthFail has diagnostics"
  let d := r.diagnostics[0]!
  expect (d.code == .reqPrecondition)
    s!"AuthFail code must be reqPrecondition, got {d.code.wire}"
  expect (hasSubstr d.message "authority/custody")
    s!"AuthFail message must mention authority/custody, got {d.message}"
  expect (hasSubstr d.message "context.caller")
    s!"AuthFail message must mention context.caller, got {d.message}"
  expect (!(hasSubstr d.message "disclosure") && d.code != .visibilityViolation)
    "must not conflate with visibility (PF-VIS-001)"
  let composed := checkProgramTypedResultV1 v
  expect (!composed.ok) "AuthFail CheckV1 not ok"
  expect (composed.diagnostics.any fun x =>
      x.code == .reqPrecondition && hasSubstr x.message "authority/custody")
    "CheckV1 composition must surface authority diagnostic"

/-- Public-only programs remain ok (no private custody surface). -/
private unsafe def testPublicCounterOk
    (session : ParserSession) : IO Unit := do
  let src :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PubOk where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry bump(v : UInt64) : UInt64 do\n" ++
    "    count := v\n" ++
    "    return count\n"
  let v ← load session src "<pub-ok>" "Tests.PubOk"
  let r := checkAuthorityCustodyResultV1 v
  expect (r.ok && r.diagnostics.isEmpty) "public program authority ok"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testPrivateWriteWithCaller session
  testPrivateWriteWithoutCaller session
  testPublicCounterOk session
  IO.println "Tests.Typed.AuthorityCustodyCheckV1: ok"

end Tests.Typed.AuthorityCustodyCheckV1
