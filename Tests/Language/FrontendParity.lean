import Tests.Language.ParserSession

namespace Tests.Language.FrontendParityFixture

open ProofForgeV2.Language

program CompleteAlpha where
  state total : UInt64

  init(public seed : UInt64, private witness : UInt64) do
    total := seed + 1

  entry update(amount : UInt64, public extra : UInt64, private secret : UInt64) : UInt64 do
    total := total + amount
    call "peer"
    return total

  view literal() : UInt64 do
    return 7

program EdgeAlpha where
  entry callEdge() : UInt64 do
    call "peer\n\"quoted\"\\path"
    return 18446744073709551615

end Tests.Language.FrontendParityFixture

namespace Tests.Language.FrontendParity

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.FrontendParityFixture\n\n" ++
  "program CompleteAlpha where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(public seed : UInt64, private witness : UInt64) do\n" ++
  "    total := seed + 1\n\n" ++
  "  entry update(amount : UInt64, public extra : UInt64, private secret : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    call \"peer\"\n" ++
  "    return total\n\n" ++
  "  view literal() : UInt64 do\n" ++
  "    return 7\n\n" ++
  "program EdgeAlpha where\n" ++
  "  entry callEdge() : UInt64 do\n" ++
  "    call \"peer\\n\\\"quoted\\\"\\\\path\"\n" ++
  "    return 18446744073709551615\n\n" ++
  "end Tests.Language.FrontendParityFixture\n"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.parsePrograms source "<frontend-parity>" with
  | .ok #[decodedComplete, decodedEdge] =>
      let elaboratedComplete := Tests.Language.FrontendParityFixture.CompleteAlpha
      let elaboratedEdge := Tests.Language.FrontendParityFixture.EdgeAlpha
      expect (decodedComplete == elaboratedComplete)
        "Lean command and Loader must produce the same complete Source.Program"
      expect (decodedComplete.sourceHash == elaboratedComplete.sourceHash)
        "Lean command and Loader must produce the same complete source hash"
      expect (decodedEdge == elaboratedEdge)
        "Lean command and Loader must preserve empty arrays, Option.none, escaped strings, and UInt64.max"
      expect (decodedEdge.sourceHash == elaboratedEdge.sourceHash)
        "Lean command and Loader must produce the same edge source hash"
  | .ok programs =>
      throw <| IO.userError s!"frontend parity source produced {programs.size} programs"
  | .error error => throw <| IO.userError error.render

end Tests.Language.FrontendParity
