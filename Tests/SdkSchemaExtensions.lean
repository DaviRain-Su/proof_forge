import ProofForge.Contract.SdkSchema
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.SdkSchemaExtensions

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

def dummyRef (path : String) : FileRef :=
  { path := path, sha256 := "0000000000000000000000000000000000000000000000000000000000000000", bytes := 1 }

def renderTarget (targetId : String) : IO String := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  requireOk (SdkSchema.render targetId spec
    #[("artifactMetadata", dummyRef "proof-forge-artifact.json")]
    #[("typescript", dummyRef "proof-forge-client.ts")])
    s!"render {targetId}"

def requireOnlySelectedExtension (targetId key json : String) : IO Unit := do
  require (contains json ("\"extensions\": {\"" ++ key ++ "\":"))
    s!"{targetId} SDK schema missing selected {key} extension block: {json}"
  for other in #["evm", "solana", "near", "sui"] do
    if other != key then
      require (!contains json ("\"" ++ other ++ "\": {\"targetId\""))
        s!"{targetId} SDK schema unexpectedly populated {other} extension: {json}"

def main : IO UInt32 := do
  let evm ← renderTarget "evm"
  requireOnlySelectedExtension "evm" "evm" evm
  require (contains evm "\"abi\":")
    "EVM extension missing ABI metadata"
  require (contains evm "\"runtimeBytecode\":")
    "EVM extension missing bytecode metadata"
  require (contains evm "\"deployManifest\":")
    "EVM extension missing deploy manifest metadata"

  let solana ← renderTarget "solana-sbpf-asm"
  requireOnlySelectedExtension "solana-sbpf-asm" "solana" solana
  require (contains solana "\"idl\":")
    "Solana extension missing IDL metadata"
  require (contains solana "\"accounts\":")
    "Solana extension missing account metadata"
  require (contains solana "\"pda\":")
    "Solana extension missing PDA metadata"
  require (contains solana "\"cpi\":")
    "Solana extension missing CPI metadata"
  require (contains solana "\"computeBudget\":")
    "Solana extension missing compute-budget metadata"

  let near ← renderTarget "wasm-near"
  requireOnlySelectedExtension "wasm-near" "near" near
  require (contains near "\"wat\":")
    "NEAR extension missing WAT metadata"
  require (contains near "\"wasm\":")
    "NEAR extension missing Wasm metadata"
  require (contains near "\"offlineHost\":")
    "NEAR extension missing offline host metadata"

  let sui ← renderTarget "move-sui"
  requireOnlySelectedExtension "move-sui" "sui" sui
  require (contains sui "\"packageDir\":")
    "Sui extension missing package metadata"
  require (contains sui "\"object\":")
    "Sui extension missing object metadata"
  require (contains sui "\"uidType\": \"UID\"")
    "Sui extension missing UID metadata"
  require (contains sui "\"ownership\":")
    "Sui extension missing ownership metadata"

  IO.println "sdk-schema-extensions: ok"
  return 0

end ProofForge.Tests.SdkSchemaExtensions

def main : IO UInt32 :=
  ProofForge.Tests.SdkSchemaExtensions.main
