import ProofForge.Contract.SdkSchema
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.SuiSdkSchema

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

def main : IO UInt32 := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let json ← requireOk (SdkSchema.render "move-sui" spec
    #[("artifactMetadata", dummyRef "proof-forge-artifact.json")]
    #[("typescript", dummyRef "proof-forge-client.ts")])
    "render move-sui schema"

  require (contains json "\"schema\": \"proof-forge.sdk-schema.v0\"")
    "Sui SDK schema missing schema id"
  require (contains json "\"target\": \"move-sui\"")
    "Sui SDK schema missing target id"
  require (contains json "\"client\": \"proof-forge-client.ts\"")
    "Sui extension missing client reference"
  require (contains json "\"objectType\": \"Counter\"")
    "Sui extension missing Counter object type"
  require (contains json "\"uidField\": \"id\"")
    "Sui extension missing UID field"
  require (contains json "\"uidType\": \"UID\"")
    "Sui extension missing UID type"
  require (contains json "\"ownership\": \"owned-object\"")
    "Sui extension missing ownership mode"
  require (contains json "\"stateFieldMapping\"")
    "Sui extension missing scalar state field mapping"
  require (contains json "\"count\"")
    "Sui extension missing count state mapping"
  require (contains json "\"initialize\"")
    "Sui extension missing initialize entrypoint object metadata"
  require (contains json "\"txContext\": \"&mut TxContext\"")
    "Sui create/init metadata must require TxContext"
  require (contains json "\"returnsOrTransfers\": \"returns new Counter\"")
    "Sui create/init metadata must record new Counter result semantics"
  require (contains json "\"increment\"")
    "Sui extension missing increment entrypoint metadata"
  require (contains json "\"mutability\": \"mutable\"")
    "Sui increment metadata must require a mutable Counter"
  require (contains json "\"value\"")
    "Sui extension missing value entrypoint metadata"
  require (contains json "\"get\"")
    "Sui extension missing get entrypoint metadata"
  require (contains json "\"mutability\": \"immutable\"")
    "Sui value/get metadata must require an immutable Counter"
  require (contains json "\"returns\": \"u64\"")
    "Sui value/get metadata must record u64 return"

  IO.println "sui-sdk-schema: ok"
  return 0

end ProofForge.Tests.SuiSdkSchema

def main : IO UInt32 :=
  ProofForge.Tests.SuiSdkSchema.main
