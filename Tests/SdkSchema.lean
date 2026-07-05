import ProofForge.Contract.SdkSchema
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.SdkSchema

open ProofForge.Contract
open ProofForge.Contract.SdkSchema

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def requireOk {α : Type} (result : Except String α) (context : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"{context}: {err}"

def writeFile (path contents : String) : IO Unit := do
  if let some parent := (System.FilePath.mk path).parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents

def makeRef (dir rel contents : String) : IO FileRef := do
  writeFile (joinPath dir rel) contents
  FileRef.fromRelative dir rel

def targetArtifacts (targetId dir : String) : IO (Array (String × FileRef)) := do
  match targetId with
  | "evm" =>
      return #[
        ("artifactMetadata", ← makeRef dir "proof-forge-artifact.json" "{\"target\":\"evm\"}\n"),
        ("primary", ← makeRef dir "Counter.bin" "6001600055\n"),
        ("secondary", ← makeRef dir "Counter.init.bin" "600a600c600039600a6000f3\n"),
        ("deployManifest", ← makeRef dir "proof-forge-deploy.json" "{\"target\":\"evm\"}\n")
      ]
  | "solana-sbpf-asm" =>
      return #[
        ("artifactMetadata", ← makeRef dir "proof-forge-artifact.json" "{\"target\":\"solana-sbpf-asm\"}\n"),
        ("primary", ← makeRef dir "Counter.s" ".text\n"),
        ("interface", ← makeRef dir "proof-forge-idl.json" "{\"name\":\"Counter\"}\n"),
        ("manifest", ← makeRef dir "manifest.toml" "name = \"Counter\"\n")
      ]
  | "wasm-near" =>
      return #[
        ("artifactMetadata", ← makeRef dir "proof-forge-artifact.json" "{\"target\":\"wasm-near\"}\n"),
        ("primary", ← makeRef dir "counter.wat" "(module)\n"),
        ("secondary", ← makeRef dir "counter.wasm" "wasm-bytes\n"),
        ("deployManifest", ← makeRef dir "proof-forge-deploy.json" "{\"target\":\"wasm-near\"}\n"),
        ("contractSpec", ← makeRef dir "Counter.contract-spec.json" "{\"schema\":\"proof-forge.contract-spec.v0\"}\n")
      ]
  | "move-sui" =>
      return #[
        ("artifactMetadata", ← makeRef dir "proof-forge-artifact.json" "{\"target\":\"move-sui\"}\n"),
        ("manifest", ← makeRef dir "Move.toml" "[package]\nname = \"counter\"\n"),
        ("primary", ← makeRef dir "sources/counter.move" "module proof_forge::counter {}\n"),
        ("tests", ← makeRef dir "tests/counter_tests.move" "#[test]\nfun test_counter() {}\n")
      ]
  | other =>
      throw <| IO.userError s!"unexpected test target {other}"

def targetClients (targetId dir : String) : IO (Array (String × FileRef)) := do
  match targetId with
  | "evm" =>
      return #[
        ("typescript", ← makeRef dir "proof-forge-client.ts" "export const target = \"evm\";\n"),
        ("nativeWrapper", ← makeRef dir "proof-forge-evm-abi.ts" "export const ABI = [];\n")
      ]
  | "solana-sbpf-asm" =>
      return #[("typescript", ← makeRef dir "proof-forge-client.ts" "export const target = \"solana-sbpf-asm\";\n")]
  | "wasm-near" =>
      return #[("typescript", ← makeRef dir "proof-forge-near.ts" "export const target = \"wasm-near\";\n")]
  | "move-sui" =>
      return #[("typescript", ← makeRef dir "proof-forge-client.ts" "export const target = \"move-sui\";\n")]
  | other =>
      throw <| IO.userError s!"unexpected test target {other}"

def renderTarget (targetId : String) : IO String := do
  let dir := joinPath "build/sdk" targetId
  IO.FS.createDirAll (System.FilePath.mk dir)
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let artifacts ← targetArtifacts targetId dir
  let clients ← targetClients targetId dir
  let json ← requireOk (SdkSchema.render targetId spec artifacts clients)
    s!"render {targetId}"
  writeFile (joinPath dir "proof-forge-sdk.json") (json ++ "\n")
  return json

def requireRootFields (targetId json : String) : IO Unit := do
  for field in #[
    "schema", "schemaVersion", "contract", "target", "irVersion", "state",
    "types", "entrypoints", "errors", "events", "capabilities", "artifacts",
    "clients", "extensions"
  ] do
    require (contains json s!"\"{field}\":")
      s!"{targetId} SDK schema missing root field {field}: {json}"
  require (contains json "\"schema\": \"proof-forge.sdk-schema.v0\"")
    s!"{targetId} SDK schema missing stable schema marker"
  require (contains json "\"schemaVersion\": 0")
    s!"{targetId} SDK schema missing numeric schemaVersion"
  require (contains json "\"irVersion\": \"portable-ir-v0\"")
    s!"{targetId} SDK schema missing portable IR version"
  require (contains json s!"\"target\": \"{targetId}\"")
    s!"{targetId} SDK schema missing target id"
  require (contains json "\"extensions\": {")
    s!"{targetId} SDK schema missing target extension object"

def main : IO UInt32 := do
  let targets := #["evm", "solana-sbpf-asm", "wasm-near", "move-sui"]
  for targetId in targets do
    let json ← renderTarget targetId
    requireRootFields targetId json
  IO.println "sdk-schema: target-neutral root ok"
  return 0

end ProofForge.Tests.SdkSchema

def main : IO UInt32 :=
  ProofForge.Tests.SdkSchema.main
