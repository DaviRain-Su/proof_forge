import Tests.Language.ParserSession
import ProofForgeV2.Language.ProgramExport
import ProofForgeV2.Language.ProgramElaborationV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.FrontendParity

open Lean
open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

namespace Fixture
open ProofForgeV2.Language

program CompleteAlpha where
  state total : UInt64

  init(public seed : UInt64, private witness : UInt64) do
    total := seed + 1

  entry update(amount : UInt64, public extra : UInt64, private secret : UInt64) : UInt64 do
    total := total + amount
    call External.Peer()
    return total

  view literal() : UInt64 do
    return 7

program EdgeAlpha where
  entry callEdge() : UInt64 do
    call External.Peer()
    schedule External.Peer()
    return 18446744073709551615

end Tests.Language.FrontendParity.Fixture

namespace Tests.Language.FrontendParity

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Fixture\n\n" ++
  "program CompleteAlpha where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(public seed : UInt64, private witness : UInt64) do\n" ++
  "    total := seed + 1\n\n" ++
  "  entry update(amount : UInt64, public extra : UInt64, private secret : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    call External.Peer()\n" ++
  "    return total\n\n" ++
  "  view literal() : UInt64 do\n" ++
  "    return 7\n\n" ++
  "program EdgeAlpha where\n" ++
  "  entry callEdge() : UInt64 do\n" ++
  "    call External.Peer()\n" ++
  "    schedule External.Peer()\n" ++
  "    return 18446744073709551615\n\n" ++
  "end Fixture\n"

private def moduleName : String := "Tests.Language.FrontendParity"

private def programName (source : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1) : String :=
  source.program.name.raw

private def entryNames (source : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1) : Array String :=
  source.program.items.filterMap fun item =>
    match item with
    | .entry e => some e.name.raw
    | .view v => some v.name.raw
    | _ => none

private def hasStateNamed (source : ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1) (name : String) : Bool :=
  source.program.items.any fun item =>
    match item with
    | .state s => s.name.raw == name
    | _ => false

private def liftPayload (label : String) (result : Except String ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1) : IO ProofForgeV2.Source.ValidatedSourceV1.ValidatedSourceV1 :=
  match result with
  | .ok value => pure value
  | .error message => throw <| IO.userError s!"{label}: {message}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let programs ← match ← session.parseProgramsV1 source "<frontend-parity>" moduleName with
  | .error error => throw <| IO.userError error.render
  | .ok programs => pure programs
  expect (programs.size == 2)
    s!"frontend parity source produced {programs.size} programs"
  let complete := programs.find? (programName · == "CompleteAlpha")
  let edge := programs.find? (programName · == "EdgeAlpha")
  match complete with
  | none => throw <| IO.userError "Loader must preserve CompleteAlpha program"
  | some c =>
      expect (c.program.name.raw == "CompleteAlpha")
        "Loader must preserve CompleteAlpha short name"
      expect (c.programIdentity.components.toArray.map (·.raw) ==
        #["Tests", "Language", "FrontendParity", "Fixture", "CompleteAlpha"])
        "Loader must preserve CompleteAlpha fully-qualified identity"
      expect (hasStateNamed c "total") "Loader must preserve state declaration"
      expect (entryNames c == #["update", "literal"])
        "Loader must preserve entries in source order"
  match edge with
  | none => throw <| IO.userError "Loader must preserve EdgeAlpha program"
  | some e =>
      expect (e.program.name.raw == "EdgeAlpha")
        "Loader must preserve EdgeAlpha short name"
      expect (entryNames e == #["callEdge"])
        "Loader must preserve EdgeAlpha entry"

  let env ← Lean.importModules
    (imports := #[{ module := `Tests.Language.FrontendParity }])
    (opts := {})
    (trustLevel := 0)
  let payloadComplete ← liftPayload "CompleteAlpha payload"
    (ProofForgeV2.Language.ProgramExport.programPayloadV2 env `Tests.Language.FrontendParity.Fixture.CompleteAlpha)
  let payloadEdge ← liftPayload "EdgeAlpha payload"
    (ProofForgeV2.Language.ProgramExport.programPayloadV2 env `Tests.Language.FrontendParity.Fixture.EdgeAlpha)
  let some complete := programs.find? (programName · == "CompleteAlpha")
    | throw <| IO.userError "Loader CompleteAlpha missing for payload parity"
  let some edge := programs.find? (programName · == "EdgeAlpha")
    | throw <| IO.userError "Loader EdgeAlpha missing for payload parity"
  expect (payloadComplete.programIdentity == complete.programIdentity)
    "Lean command and Loader must agree on CompleteAlpha identity"
  expect (payloadEdge.programIdentity == edge.programIdentity)
    "Lean command and Loader must agree on EdgeAlpha identity"
  let completeBytes ← match ProofForgeV2.Source.ValidatedSourceV1.canonicalValidatedSourceAstBytesV1 complete with
    | .ok bytes => pure bytes
    | .error message => throw <| IO.userError message
  let payloadCompleteBytes ← match ProofForgeV2.Source.ValidatedSourceV1.canonicalValidatedSourceAstBytesV1 payloadComplete with
    | .ok bytes => pure bytes
    | .error message => throw <| IO.userError message
  let edgeBytes ← match ProofForgeV2.Source.ValidatedSourceV1.canonicalValidatedSourceAstBytesV1 edge with
    | .ok bytes => pure bytes
    | .error message => throw <| IO.userError message
  let payloadEdgeBytes ← match ProofForgeV2.Source.ValidatedSourceV1.canonicalValidatedSourceAstBytesV1 payloadEdge with
    | .ok bytes => pure bytes
    | .error message => throw <| IO.userError message
  expect (completeBytes == payloadCompleteBytes)
    "Lean command and Loader must produce the same CompleteAlpha canonical bytes"
  expect (edgeBytes == payloadEdgeBytes)
    "Lean command and Loader must produce the same EdgeAlpha canonical bytes"

end Tests.Language.FrontendParity
