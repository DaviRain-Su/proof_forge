import ProofForgeV2.Materialization.LockedToolchainV1

namespace Tests.CLI.ToolchainPolicy

open ProofForgeV2
open ProofForgeV2.Materialization.LockedToolchainV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  match requiredBundlePaths "solc" with
  | .error error =>
      throw <| IO.userError s!"locked solc closure could not be resolved: {error}"
  | .ok paths =>
      expect (paths == #["solc"])
        "EVM solc must depend only on its locked executable closure"
      expect (!paths.contains "jv")
        "supply-chain jv must not become an EVM product prerequisite"

  match requiredBundlePaths "wat2wasm" with
  | .error error =>
      throw <| IO.userError s!"locked wat2wasm closure could not be resolved: {error}"
  | .ok paths =>
      -- Order follows lock `bundleFiles` scan (not declared-tool order).
      if System.Platform.isOSX then
        expect (paths == #["lib/libcrypto.3.dylib", "wat2wasm"])
          "darwin wat2wasm must include locked runtime lib + executable (bundleFiles order)"
        expect (paths.contains "wat2wasm" && paths.contains "lib/libcrypto.3.dylib")
          "darwin wat2wasm closure contains executable and runtime dylib"
      else
        expect (paths == #["wat2wasm"])
          "linux wat2wasm must be executable-only as lock states"
      expect (!paths.contains "jv")
        "supply-chain jv must not become a NEAR product prerequisite"
      expect (!paths.contains "solc")
        "solc must not enter wat2wasm product closure"

  match requiredBundlePaths "not-a-locked-tool" with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "unknown locked tool unexpectedly resolved"

  -- S2b sourceBuild tool: empty content-addressed bundle closure.
  match requiredBundlePaths "sbpf" with
  | .error error =>
      throw <| IO.userError s!"locked sbpf closure could not be resolved: {error}"
  | .ok paths =>
      expect (paths == #[])
        "sourceBuild sbpf must declare an empty content-addressed bundle closure"

  -- ALEO-I3/I4: leo is content-addressed executable-only; Tool Lock binds the
  -- default source and opt-in compile CodegenProfileIds (no phantom lane).
  match requiredBundlePaths "leo" with
  | .error error =>
      throw <| IO.userError s!"locked leo closure could not be resolved: {error}"
  | .ok paths =>
      expect (paths == #["leo"])
        "Aleo leo must depend only on its locked executable closure"
      expect (!paths.contains "nargo" && !paths.contains "solc")
        "unrelated product tools must not enter leo closure"

end Tests.CLI.ToolchainPolicy
