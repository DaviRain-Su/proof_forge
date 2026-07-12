import ProofForge.Backend.Stylus.Artifact
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Cli.Artifact
import ProofForge.Cli.ContractSourceArtifacts
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.Options
import ProofForge.IR.Legacy.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Cli

open System

unsafe def compileContractSourceStylus (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln "Stylus build requires a Lean contract_source input"
      return 1
  let sourceSpec <- loadContractSpecForOptions opts input "wasm-arbitrum-stylus"
  let hydratedModule <- hydrateEvmSelectors opts.cast sourceSpec.module
  let spec := { sourceSpec with module := hydratedModule }
  let bundle <- match ProofForge.IR.Legacy.Adapter.adaptLegacy spec with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"Stylus canonical adapter: {repr error}"
  let capPlan <- match ProofForge.Target.requireCapabilityPlan ProofForge.Target.wasmArbitrumStylus {
      targetId := "wasm-arbitrum-stylus"
      calls := bundle.contract.contract.requirements
    } with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.render
  let plan <- match ProofForge.Backend.Stylus.Plan.Core.buildFromCore bundle.contract capPlan with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok crate => pure crate
    | .error error => throw <| IO.userError error.message
  let output := opts.output?.getD (input.parent.getD "." / s!"{spec.name}.stylus")
  match <- ProofForge.Backend.Stylus.writeCrateAtomic crate output with
  | .error error => throw <| IO.userError error.message
  | .ok () => pure ()
  let cargoPath := output / "Cargo.toml"
  let libPath := output / "src/lib.rs"
  let cargoDigest <- fileDigestAndBytes cargoPath
  let libDigest <- fileDigestAndBytes libPath
  let source : ProofForge.Target.ArtifactBundle.SourceIdentity := {
    moduleName := spec.name, path? := some input.toString, leanElaborated := true
  }
  let sourceTools <- ProofForge.Target.ArtifactBundle.sourceElaborationToolchain source opts.root?
  let artifactBundle := ProofForge.Backend.Stylus.Artifact.rustSdkBundle source
    "Cargo.toml" "src/lib.rs" cargoDigest.1 libDigest.1 cargoDigest.2 libDigest.2 sourceTools
  match ProofForge.Target.ArtifactBundle.validateHonesty artifactBundle with
  | .error error => throw <| IO.userError error.message
  | .ok () => pure ()
  let metadata := "{\"schemaVersion\":\"1\",\"target\":\"wasm-arbitrum-stylus\",\"plan\":" ++
    ProofForge.Backend.Stylus.Artifact.planMetadataJson plan ++ ",\"artifactBundle\":" ++
    artifactBundle.toJson ++ "}\n"
  IO.FS.writeFile (output / "proof-forge-artifact.json") metadata
  IO.println s!"wrote {output}"
  return 0

end ProofForge.Cli
