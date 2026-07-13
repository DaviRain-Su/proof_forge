import ProofForge.Backend.Stylus.Artifact
import ProofForge.Backend.Stylus.AbiJson
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
import ProofForge.Compiler.CanonicalPipeline
import ProofForge.Target.Registry
import ProofForge.Compiler.Wasm.Printer

namespace ProofForge.Cli

open System

private def runProcessEnv (cmd : String) (args : Array String)
    (env : Array (String × Option String)) : IO Unit := do
  let output <- IO.Process.output { cmd, args, env }
  if output.exitCode != 0 then
    throw <| IO.userError s!"{cmd} failed with exit code {output.exitCode}: {output.stderr}"

private partial def stylusLegacyAbiType : ProofForge.IR.ValueType -> Except String String
  | .bool => pure "bool"
  | .u8 => pure "uint8"
  | .u32 => pure "uint32"
  | .u64 => pure "uint64"
  | .u128 => pure "uint128"
  | .address => pure "address"
  | .hash => pure "bytes32"
  | .bytes => pure "bytes"
  | .string => pure "string"
  | .fixedArray element size => do
      let elementType <- stylusLegacyAbiType element
      pure s!"{elementType}[{size}]"
  | .array element => do
      let elementType <- stylusLegacyAbiType element
      pure s!"{elementType}[]"
  | .unit => .error "unit is not a Stylus ABI parameter type"
  | .structType name => .error s!"Stylus struct parameter `{name}` needs a resolved tuple layout"

private def stylusEntrypointSignature (entrypoint : ProofForge.IR.Entrypoint) : Except String String := do
  let mut types := #[]
  for h : index in [0:entrypoint.params.size] do
    let param := entrypoint.params[index]
    let abiType <- match entrypointParamEvmAbiWord entrypoint index with
      | some override => pure override
      | none => stylusLegacyAbiType param.snd
    types := types.push abiType
  pure s!"{entrypoint.name}({String.intercalate "," types.toList})"

private def hydrateStylusSelectors (cast : String) (module : ProofForge.IR.Module) :
    IO ProofForge.IR.Module := do
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    let signature <- match stylusEntrypointSignature entrypoint with
      | .ok signature => pure signature
      | .error message => throw <| IO.userError message
    let derived <- selectorFor cast signature
    match entrypoint.selector? with
    | some selector =>
        if selector.toLower != derived.toLower then
          throw <| IO.userError
            s!"entrypoint `{entrypoint.name}` selector `{selector}` does not match Stylus ABI signature `{signature}` selector `{derived}`"
        entrypoints := entrypoints.push entrypoint
    | none => entrypoints := entrypoints.push { entrypoint with selector? := some derived }
  pure { module with entrypoints }

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
      hydrateStylusSelectors opts.cast sourceSpec.module
  let spec := { sourceSpec with
    module := ProofForge.Target.PeerMap.applyToModule hydratedModule opts.peerMap }
  let bundle <- match ProofForge.Compiler.adaptContractSpecCanonical spec with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"Stylus canonical adapter: {error}"
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
  let planPath := output / "proof-forge-plan.txt"
  let storagePath := output / "proof-forge-storage.txt"
  let wasmPath := output / "contract.wasm"
  let watPath := output / "contract.wat"
  let deployPath := output / "proof-forge-deploy.json"
  let evidencePath := output / "proof-forge-evidence.json"
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
  let abi := ProofForge.Backend.Stylus.AbiJson.render plan
  let client <- match ProofForge.Contract.Client.renderEvmAbiWrapperWithAbi clientSpec abi "contract" with
    | .ok client => pure client
    | .error error => throw <| IO.userError error
  IO.FS.writeFile abiPath (abi ++ "\n")
  IO.FS.writeFile clientPath (client ++ "\n")
  IO.FS.writeFile planPath ("stylus-plan-v1\n" ++ reprStr plan ++ "\n")
  IO.FS.writeFile storagePath ("stylus-storage-v1\n" ++ reprStr plan.storage ++ "\n")
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
  let planDigest <- fileDigestAndBytes planPath
  let storageDigest <- fileDigestAndBytes storagePath
  let wasmDigest <- fileDigestAndBytes wasmPath
  let deployDigest <- fileDigestAndBytes deployPath
  let evidenceInput <- match ← IO.getEnv "PROOF_FORGE_STYLUS_EVIDENCE" with
    | some path => pure <| FilePath.mk path
    | none => pure <| opts.root?.getD "." / "build/evidence/stylus/final.json"
  let evidenceVerified <- if ← evidenceInput.pathExists then do
      let script := opts.root?.getD "." / "scripts/stylus/check-cutover-evidence.py"
      let result <- IO.Process.output {
        cmd := "python3"
        args := #[script.toString, "--input", evidenceInput.toString,
          "--output", evidencePath.toString, "--plan-sha256", planDigest.1,
          "--storage-sha256", storageDigest.1, "--abi-sha256", abiDigest.1]
      }
      if result.exitCode != 0 then
        IO.FS.removeDirAll output
        throw <| IO.userError result.stderr.trimAscii.toString
      pure true
    else do
      IO.FS.writeFile evidencePath <|
        "{\"schemaVersion\":\"1\",\"target\":\"wasm-arbitrum-stylus\"," ++
        "\"state\":\"unavailable\",\"reason\":\"live Nitro cutover evidence not provided\"," ++
        "\"planSchemaVersion\":\"stylus-plan-v1\",\"identities\":{" ++
        s!"\"planSha256\":\"{planDigest.1}\",\"storageSha256\":\"{storageDigest.1}\",\"abiSha256\":\"{abiDigest.1}\"" ++
        "}}\n"
      pure false
  let evidenceDigest <- fileDigestAndBytes evidencePath
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
  let extraOutputs : Array ProofForge.Target.ArtifactBundle.TypedOutput := #[
    { kind := "stylus-plan", role := .sidecar, path? := some "proof-forge-plan.txt",
      sha256? := some planDigest.1, bytes? := some planDigest.2 },
    { kind := "stylus-storage-layout", role := .sidecar, path? := some "proof-forge-storage.txt",
      sha256? := some storageDigest.1, bytes? := some storageDigest.2 },
    { kind := "stylus-cutover-evidence", role := .sidecar, path? := some "proof-forge-evidence.json",
      sha256? := some evidenceDigest.1, bytes? := some evidenceDigest.2 }
  ]
  let evidenceValidation : ProofForge.Target.ArtifactBundle.ValidationEntry :=
    if evidenceVerified then
      { name := "nitro-evidence", state := .passed }
    else
      { name := "nitro-evidence", state := .unavailable,
        detail? := some "live Nitro evidence is required before release promotion" }
  let artifactBundle := { artifactBundle with outputs := artifactBundle.outputs ++ extraOutputs }
  let artifactBundle := { artifactBundle with
    validations := artifactBundle.validations.push evidenceValidation }
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
