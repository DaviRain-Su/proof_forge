import ProofForge.Backend.Stylus.Plan
import ProofForge.Target.ArtifactBundle

namespace ProofForge.Backend.Stylus.Artifact

open ProofForge.Backend.Stylus
open ProofForge.Target.ArtifactBundle

def rustSdkBundle (source : SourceIdentity)
    (cargoPath libPath abiPath clientPath wasmPath deployPath : String)
    (cargoSha libSha abiSha clientSha wasmSha deploySha : String)
    (cargoBytes libBytes abiBytes clientBytes wasmBytes deployBytes : Nat)
    (sourceTools : Array ToolProvenance := #[]) : ArtifactBundle := {
  targetId := "wasm-arbitrum-stylus"
  source
  outputs := #[
    { kind := "stylus-rust-cargo", role := .sidecar, path? := some cargoPath,
      sha256? := some cargoSha, bytes? := some cargoBytes },
    { kind := "stylus-rust-source", role := .primary, path? := some libPath,
      sha256? := some libSha, bytes? := some libBytes },
    { kind := "solidity-abi", role := .sidecar, path? := some abiPath,
      sha256? := some abiSha, bytes? := some abiBytes },
    { kind := "typescript-client", role := .sidecar, path? := some clientPath,
      sha256? := some clientSha, bytes? := some clientBytes },
    { kind := "wasm", role := .intermediate, path? := some wasmPath,
      sha256? := some wasmSha, bytes? := some wasmBytes },
    { kind := "deploy-manifest", role := .sidecar, path? := some deployPath,
      sha256? := some deploySha, bytes? := some deployBytes }
  ]
  primaryOutput? := some "stylus-rust-source"
  finalOutput? := none
  toolchain := sourceTools ++ #[
    { tool := "rustc", stage := "wasm-bootstrap", available := true,
      version? := some "1.91.0", declaredVersion? := some "1.91.0",
      observedVersion? := some "1.91.0" },
    { tool := "cargo-stylus", stage := "artifact-check", available := false,
      declaredVersion? := some "0.10.8" }
  ]
  validations := #[
    { name := "canonical-plan", state := .passed },
    { name := "rust-sdk-render", state := .passed },
    { name := "wasm-bootstrap", state := .passed },
    { name := "artifact-check", state := .unavailable,
      detail? := some "source bundle route does not run cargo stylus check" }
  ]
}

def directWasmBundle (source : SourceIdentity)
    (watPath wasmPath abiPath clientPath deployPath : String)
    (watSha wasmSha abiSha clientSha deploySha : String)
    (watBytes wasmBytes abiBytes clientBytes deployBytes : Nat)
    (sourceTools : Array ToolProvenance := #[]) : ArtifactBundle := {
  targetId := "wasm-arbitrum-stylus"
  source
  outputs := #[
    { kind := "wat", role := .intermediate, path? := some watPath,
      sha256? := some watSha, bytes? := some watBytes },
    { kind := "wasm", role := .primary, path? := some wasmPath,
      sha256? := some wasmSha, bytes? := some wasmBytes },
    { kind := "solidity-abi", role := .sidecar, path? := some abiPath,
      sha256? := some abiSha, bytes? := some abiBytes },
    { kind := "typescript-client", role := .sidecar, path? := some clientPath,
      sha256? := some clientSha, bytes? := some clientBytes },
    { kind := "deploy-manifest", role := .sidecar, path? := some deployPath,
      sha256? := some deploySha, bytes? := some deployBytes }
  ]
  primaryOutput? := some "wasm"
  finalOutput? := some "wasm"
  toolchain := sourceTools ++ #[
    { tool := "wat2wasm", stage := "direct-wasm", available := true }
  ]
  validations := #[
    { name := "canonical-plan", state := .passed },
    { name := "direct-wasm-render", state := .passed },
    { name := "wat2wasm", state := .passed }
  ]
}

def selectorHex (bytes : StylusBytes) : String :=
  bytes.foldl (fun result byte =>
    let hexDigit (value : Nat) : Char :=
      if value < 10 then Char.ofNat ('0'.toNat + value) else Char.ofNat ('a'.toNat + value - 10)
    result.push (hexDigit (byte.toNat / 16)) |>.push (hexDigit (byte.toNat % 16))) ""

def planMetadataJson (plan : StylusPlan) (renderer : String := "rust-sdk") : String :=
  let selectors := String.intercalate "," <| plan.abi.methods.toList.map fun method =>
    s!"\"{method.name}\":\"{selectorHex method.selector}\""
  "{\"planSchemaVersion\":\"stylus-plan-v1\",\"renderer\":\"" ++ renderer ++
    "\",\"selectors\":{" ++
    selectors ++ "},\"storageWords\":" ++ toString plan.storage.words.size ++ "}"

end ProofForge.Backend.Stylus.Artifact
