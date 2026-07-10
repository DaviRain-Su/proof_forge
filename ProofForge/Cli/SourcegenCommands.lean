import Lean.Util.Path
import ProofForge.Backend.Aleo.IR
import ProofForge.Backend.Aleo.Instructions
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Target.HostBridge
import ProofForge.Backend.Move.Aptos
import ProofForge.Backend.Move.Sui
import ProofForge.Cli.Artifact
import ProofForge.Cli.FileUtil
import ProofForge.Cli.JsonUtil
import ProofForge.Cli.Options
import ProofForge.Contract.SdkSchema
import ProofForge.Contract.Spec
import ProofForge.IR
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.PureMath

open System
open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

/-- Z2.3: emit Counter Aleo Instructions (`.aleo`) via direct lower bootstrap. -/
def compileCounterIrAleo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (System.FilePath.mk "build/aleo/Counter.aleo")
  let prog := ProofForge.Backend.Aleo.Instructions.Lower.lowerCounterFixture
  let text := ProofForge.Backend.Aleo.Instructions.Printer.renderProgram prog
  writeTextFile output text
  IO.println s!"wrote {output} (Aleo Instructions via Z2.3 Counter lower)"
  return 0

def compileCounterIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/Counter.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError <|
        "aleo-leo fixture `counter` is unsupported on Leo 4.0.2 because its " ++
        "mapping-backed `get() -> U64` result cannot cross `final`; " ++ err.render

def compilePureMathIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/PureMath.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.PureMath.module with
  | .ok source =>
      writeTextFile output (source ++ "\n")
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

/-- Fixture-only CosmWasm Counter **spike** adapter (region ABI + cosmwasm-check).
Product `contract_source` builds use HostBridge.cosmWasm via
`--contract-source-emitwat` instead (PF-P3-02). -/
def compileCounterIrCosmWasm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/cosmwasm/Counter.wat")
  match ProofForge.Backend.WasmHost.CosmWasm.EmitWat.renderModule
      ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def writePackageFiles (outputDir : FilePath) (pkg : Array ProofForge.Backend.Move.Aptos.PackageFile) :
    IO Unit := do
  for file in pkg do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    writeTextFile path file.content

def writeSuiPackageFiles (outputDir : FilePath) (pkg : Array ProofForge.Backend.Move.Sui.PackageFile) :
    IO Unit := do
  for file in pkg do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    writeTextFile path file.content

def compileCounterIrAptos (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aptos/counter")
  match ProofForge.Backend.Move.Aptos.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      writePackageFiles output pkg
      IO.println s!"wrote Aptos package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def compileCounterIrSui (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/sui/counter")
  let module := ProofForge.IR.Examples.Counter.module
  match ProofForge.Backend.Move.Sui.renderPackage module with
  | .ok pkg =>
      writeSuiPackageFiles output pkg
      let moveToml := output / "Move.toml"
      let sourceOutput := output / "sources" / "counter.move"
      let testsOutput := output / "tests" / "counter_tests.move"
      let clientOutput := output / "proof-forge-client.ts"
      IO.println s!"wrote Sui package to {output}"
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (output / "proof-forge-artifact.json")
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString "move-sui"),
        ("targetFamily", jsonString "move"),
        ("artifactKind", jsonString "move-package"),
        ("fixture", jsonString "counter"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Contract.SdkSchema.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("sdkSchema", jsonString "proof-forge-sdk.json"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "assertions.check"]),
        ("artifacts", jsonObject #[
          ("moveToml", ← artifactEntryJson moveToml),
          ("source", ← artifactEntryJson sourceOutput),
          ("tests", ← artifactEntryJson testsOutput)
        ]),
        ("validation", jsonObject #[
          ("sourceGeneration", jsonString "passed"),
          ("suiMoveBuild", jsonString "pending")
        ])
      ]
      writeTextFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      if opts.fromNewSurface then
        let spec := ProofForge.Contract.ContractSpec.fromIR module
        discard <| writeSdkSchemaFile "move-sui" spec output #[
          ("artifactMetadata", metadataOutput),
          ("manifest", moveToml),
          ("primary", sourceOutput),
          ("tests", testsOutput)
        ] #[("typescript", clientOutput)]
      return 0
  | .error err =>
      throw <| IO.userError err.message

end ProofForge.Cli
