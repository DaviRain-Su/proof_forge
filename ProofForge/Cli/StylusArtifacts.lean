import ProofForge.Backend.Stylus.Artifact
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Backend.Stylus.Token
import ProofForge.Cli.Artifact
import ProofForge.Cli.ContractSourceArtifacts
import ProofForge.Cli.EvmAbi
import ProofForge.Cli.Options
import ProofForge.Cli.TokenLoader
import ProofForge.IR.Legacy.Adapter
import ProofForge.Target.Registry
import ProofForge.Compiler.Wasm.Printer

namespace ProofForge.Cli

open System

private def runProcessEnv (cmd : String) (args : Array String)
    (env : Array (String × Option String)) : IO Unit := do
  let output <- IO.Process.output { cmd, args, env }
  if output.exitCode != 0 then
    throw <| IO.userError s!"{cmd} failed with exit code {output.exitCode}: {output.stderr}"

unsafe def compileContractSourceStylus (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln "Stylus build requires a Lean contract_source input"
      return 1
  let sourceSpec <- if opts.token then do
      let (_, tokenSpec) <- ProofForge.Cli.TokenLoader.loadToken input opts.root? opts.moduleName?
      pure <| ProofForge.Backend.Stylus.Token.specFor tokenSpec
    else
      loadContractSpecForOptions opts input "wasm-arbitrum-stylus"
  let hydratedModule <- if opts.token then
      pure sourceSpec.module
    else
      hydrateEvmSelectors opts.cast sourceSpec.module
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
  let crate? <- match opts.stylusRenderer with
    | .directWasm => pure none
    | .rustSdk => match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
      | .ok crate => pure (some crate)
      | .error error => throw <| IO.userError error.message
  let finalOutput := opts.output?.getD (input.parent.getD "." / s!"{spec.name}.stylus")
  if ← finalOutput.pathExists then
    throw <| IO.userError s!"Stylus artifact output already exists: {finalOutput}"
  let pid ← IO.Process.getPID
  let output := System.FilePath.mk s!"{finalOutput}.bundle-tmp-{pid}"
  if ← output.pathExists then IO.FS.removeDirAll output
  match crate? with
  | some crate =>
      match <- ProofForge.Backend.Stylus.writeCrateAtomic crate output with
      | .error error => throw <| IO.userError error.message
      | .ok () => pure ()
  | none => IO.FS.createDirAll output
  let cargoPath := output / "Cargo.toml"
  let libPath := output / "src/lib.rs"
  let abiPath := output / "proof-forge-abi.json"
  let clientPath := output / "proof-forge-client.ts"
  let wasmPath := output / "contract.wasm"
  let watPath := output / "contract.wat"
  let deployPath := output / "proof-forge-deploy.json"
  let clientSpec := if opts.token then
      { spec with module := { spec.module with
          entrypoints := spec.module.entrypoints.map fun entrypoint =>
            let paramAbiWords := entrypoint.paramAbiWords.map fun word =>
              if word == some "uint256" then none else word
            let returnAbiWord? :=
              if entrypoint.returnAbiWord? == some "uint256" then none
              else entrypoint.returnAbiWord?
            if returnAbiWord? == some "uint8" then
              { entrypoint with
                paramAbiWords := paramAbiWords
                returnAbiWord? := returnAbiWord?
                «returns» := .u8 }
            else
              { entrypoint with
                paramAbiWords := paramAbiWords
                returnAbiWord? := returnAbiWord? } } }
    else spec
  let abi <- match ProofForge.Contract.Client.abiJson clientSpec.module with
    | .ok abi => pure abi
    | .error error => throw <| IO.userError error
  let client <- match ProofForge.Contract.Client.renderEvmAbiWrapper clientSpec "contract" with
    | .ok client => pure client
    | .error error => throw <| IO.userError error
  IO.FS.writeFile abiPath (abi ++ "\n")
  IO.FS.writeFile clientPath (client ++ "\n")
  match opts.stylusRenderer, crate? with
  | .directWasm, none =>
      let module <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
        | .ok module => pure module
        | .error error => throw <| IO.userError error.message
      IO.FS.writeFile watPath (ProofForge.Compiler.Wasm.Printer.render module)
      runProcessEnv "wat2wasm" #[watPath.toString, "-o", wasmPath.toString] #[]
  | .rustSdk, some crate =>
      let rustc <- runProcess "rustup" #["which", "--toolchain", "1.91.0", "rustc"]
      let rustdoc <- runProcess "rustup" #["which", "--toolchain", "1.91.0", "rustdoc"]
      let cargoTarget := output / ".cargo-target"
      runProcessEnv "rustup" #["run", "1.91.0", "cargo", "build", "--manifest-path",
        cargoPath.toString, "--target", "wasm32-unknown-unknown", "--release"] #[
          ("RUSTC", some rustc.trimAscii.toString),
          ("RUSTDOC", some rustdoc.trimAscii.toString),
          ("CARGO_TARGET_DIR", some cargoTarget.toString)
        ]
      let wasmFileName := crate.name.replace "-" "_" ++ ".wasm"
      let builtWasm := cargoTarget / "wasm32-unknown-unknown/release" / wasmFileName
      IO.FS.writeBinFile wasmPath (← IO.FS.readBinFile builtWasm)
      IO.FS.removeDirAll cargoTarget
  | _, _ => throw <| IO.userError "internal Stylus renderer/artifact mismatch"
  let deployJson := "{\"schemaVersion\":\"1\",\"target\":\"wasm-arbitrum-stylus\"," ++
    s!"\"renderer\":\"{opts.stylusRenderer.id}\",\"wasm\":\"contract.wasm\"," ++
    "\"broadcast\":false,\"contractAddress\":null,\"transactionHash\":null," ++
    "\"activationValidation\":\"notRun\"}\n"
  IO.FS.writeFile deployPath deployJson
  let abiDigest <- fileDigestAndBytes abiPath
  let clientDigest <- fileDigestAndBytes clientPath
  let wasmDigest <- fileDigestAndBytes wasmPath
  let deployDigest <- fileDigestAndBytes deployPath
  let source : ProofForge.Target.ArtifactBundle.SourceIdentity := {
    moduleName := spec.name, path? := some input.toString, leanElaborated := true
  }
  let sourceTools <- ProofForge.Target.ArtifactBundle.sourceElaborationToolchain source opts.root?
  let artifactBundle <- match opts.stylusRenderer with
    | .rustSdk => do
        let cargoDigest <- fileDigestAndBytes cargoPath
        let libDigest <- fileDigestAndBytes libPath
        pure <| ProofForge.Backend.Stylus.Artifact.rustSdkBundle source
          "Cargo.toml" "src/lib.rs" "proof-forge-abi.json" "proof-forge-client.ts" "contract.wasm"
          "proof-forge-deploy.json"
          cargoDigest.1 libDigest.1 abiDigest.1 clientDigest.1 wasmDigest.1 deployDigest.1
          cargoDigest.2 libDigest.2 abiDigest.2 clientDigest.2 wasmDigest.2 deployDigest.2 sourceTools
    | .directWasm => do
        let watDigest <- fileDigestAndBytes watPath
        pure <| ProofForge.Backend.Stylus.Artifact.directWasmBundle source
          "contract.wat" "contract.wasm" "proof-forge-abi.json" "proof-forge-client.ts"
          "proof-forge-deploy.json" watDigest.1 wasmDigest.1 abiDigest.1 clientDigest.1 deployDigest.1
          watDigest.2 wasmDigest.2 abiDigest.2 clientDigest.2 deployDigest.2 sourceTools
  match ProofForge.Target.ArtifactBundle.validateHonesty artifactBundle with
  | .error error => throw <| IO.userError error.message
  | .ok () => pure ()
  let metadata := "{\"schemaVersion\":\"1\",\"target\":\"wasm-arbitrum-stylus\",\"plan\":" ++
    ProofForge.Backend.Stylus.Artifact.planMetadataJson plan opts.stylusRenderer.id ++ ",\"artifactBundle\":" ++
    artifactBundle.toJson ++ "}\n"
  IO.FS.writeFile (output / "proof-forge-artifact.json") metadata
  IO.FS.rename output finalOutput
  IO.println s!"wrote {finalOutput}"
  return 0

end ProofForge.Cli
