import ProofForgeV2.CLI.Toolchain

namespace Tests.CLI.ToolchainPolicy

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  match CLI.Toolchain.requiredBundlePaths "solc" with
  | .error error =>
      throw <| IO.userError s!"locked solc closure could not be resolved: {error}"
  | .ok paths =>
      expect (paths == #["solc"])
        "EVM solc must depend only on its locked executable closure"
      expect (!paths.contains "jv")
        "supply-chain jv must not become an EVM product prerequisite"

  match CLI.Toolchain.requiredBundlePaths "not-a-locked-tool" with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "unknown locked tool unexpectedly resolved"

end Tests.CLI.ToolchainPolicy
