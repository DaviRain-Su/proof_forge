import ProofForge.Contract.SdkSchema
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.SdkSchemaDiagnostics

open ProofForge.Contract
open ProofForge.Contract.SdkSchema
open ProofForge.IR
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def dummyRef (path : String) : FileRef :=
  { path := path, sha256 := "0000000000000000000000000000000000000000000000000000000000000000", bytes := 1 }

def renderResult (targetId : String) (spec : ContractSpec) (extension? : Option TargetExtension := none) :
    Except String String :=
  SdkSchema.render targetId spec
    #[("artifactMetadata", dummyRef "proof-forge-artifact.json")]
    #[("typescript", dummyRef "proof-forge-client.ts")]
    extension?

def expectErrorContains (result : Except String String) (needles : Array String) (context : String) : IO Unit := do
  match result with
  | .ok json => throw <| IO.userError s!"{context}: expected diagnostic, got schema {json}"
  | .error err =>
      for needle in needles do
        require (contains err needle) s!"{context}: diagnostic `{err}` missing `{needle}`"

def mapModule : Module := {
  name := "MapNotSuiMvp"
  state := #[{
    id := "balances"
    kind := .map .address 16
    type := .u64
  }]
  entrypoints := #[{
    name := "contains"
    returns := .bool
    params := #[("owner", .address)]
    body := #[
      .return (.effect (.storageMapContains "balances" (.local "owner")))
    ]
  }]
}

def main : IO UInt32 := do
  let spec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let solanaOnlyEvmExtension : TargetExtension := {
    key := "evm"
    targetId := "evm"
    fields := #[
      ("cpi", Json.array #[]),
      ("pda", Json.array #[])
    ]
    requiredCapabilities := #[.crosscallCpi, .storagePda]
  }
  expectErrorContains
    (renderResult "evm" spec (some solanaOnlyEvmExtension))
    #["evm", "crosscall.cpi", "storage.pda"]
    "Solana-only metadata under evm"

  expectErrorContains
    (renderResult "move-sui" (ContractSpec.fromIR mapModule))
    #["move-sui", "storage.map"]
    "non-MVP Sui map shape"

  expectErrorContains
    (renderResult "unknown-target" spec)
    #["unknown SDK schema target", "unknown-target"]
    "unknown target"

  IO.println "sdk-schema-diagnostics: ok"
  return 0

end ProofForge.Tests.SdkSchemaDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.SdkSchemaDiagnostics.main
