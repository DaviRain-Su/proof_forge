import ProofForge.Backend.Stylus.Plan
import ProofForge.Target.ArtifactBundle

namespace ProofForge.Backend.Stylus.Artifact

open ProofForge.Backend.Stylus
open ProofForge.Target.ArtifactBundle

def rustSdkBundle (source : SourceIdentity) (cargoPath libPath : String)
    (cargoSha libSha : String) (cargoBytes libBytes : Nat)
    (sourceTools : Array ToolProvenance := #[]) : ArtifactBundle := {
  targetId := "wasm-arbitrum-stylus"
  source
  outputs := #[
    { kind := "stylus-rust-cargo", role := .sidecar, path? := some cargoPath,
      sha256? := some cargoSha, bytes? := some cargoBytes },
    { kind := "stylus-rust-source", role := .primary, path? := some libPath,
      sha256? := some libSha, bytes? := some libBytes }
  ]
  primaryOutput? := some "stylus-rust-source"
  finalOutput? := none
  toolchain := sourceTools ++ #[
    { tool := "rustc", stage := "wasm-bootstrap", available := false,
      declaredVersion? := some "1.91.0" },
    { tool := "cargo-stylus", stage := "artifact-check", available := false,
      declaredVersion? := some "0.10.8" }
  ]
  validations := #[
    { name := "canonical-plan", state := .passed },
    { name := "rust-sdk-render", state := .passed },
    { name := "wasm-bootstrap", state := .unavailable,
      detail? := some "source bundle route does not run Rust compilation" },
    { name := "artifact-check", state := .unavailable,
      detail? := some "source bundle route does not run cargo stylus check" }
  ]
}

def selectorHex (bytes : StylusBytes) : String :=
  bytes.foldl (fun result byte =>
    let hexDigit (value : Nat) : Char :=
      if value < 10 then Char.ofNat ('0'.toNat + value) else Char.ofNat ('a'.toNat + value - 10)
    result.push (hexDigit (byte.toNat / 16)) |>.push (hexDigit (byte.toNat % 16))) ""

def planMetadataJson (plan : StylusPlan) : String :=
  let selectors := String.intercalate "," <| plan.abi.methods.toList.map fun method =>
    s!"\"{method.name}\":\"{selectorHex method.selector}\""
  "{\"planSchemaVersion\":\"stylus-plan-v1\",\"renderer\":\"rust-sdk-0.10.8\",\"selectors\":{" ++
    selectors ++ "},\"storageWords\":" ++ toString plan.storage.words.size ++ "}"

end ProofForge.Backend.Stylus.Artifact
