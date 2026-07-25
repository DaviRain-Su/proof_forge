import Tests.Language.ParserSession

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
      expect (decodedComplete.name == "CompleteAlpha")
        "Loader must preserve CompleteAlpha short name"
      expect (decodedComplete.qualifiedName == "Tests.Language.FrontendParityFixture.CompleteAlpha")
        "Loader must preserve CompleteAlpha fully-qualified identity"
      expect (decodedComplete.state.map (·.name) == #["total"])
        "Loader must preserve state declaration"
      expect (decodedComplete.entries.map (·.name) == #["update", "literal"])
        "Loader must preserve entries in source order"
      expect (decodedEdge.name == "EdgeAlpha")
        "Loader must preserve EdgeAlpha short name"
      expect (decodedEdge.entries.map (·.name) == #["callEdge"])
        "Loader must preserve EdgeAlpha entry"
      expect (decodedEdge.sourceHash.length == 64)
        "Loader must produce a stable 64-character source hash"
  | .ok programs =>
      throw <| IO.userError s!"frontend parity source produced {programs.size} programs"
  | .error error => throw <| IO.userError error.render

end Tests.Language.FrontendParity
