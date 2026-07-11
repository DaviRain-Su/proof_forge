import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Manifest
import ProofForge.Contract.Builder
import ProofForge.Solana
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaAllocator

open ProofForge.Contract.Builder
open ProofForge.Solana
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def metadataValue? (call : CapabilityCall) (key : String) : Option String :=
  call.metadata.foldl
    (fun found metadata =>
      match found with
      | some _ => found
      | none =>
          if metadata.key == key then
            some metadata.value
          else
            none)
    none

def allocatorCall? (plan : CapabilityPlan) : Option CapabilityCall :=
  plan.calls.find? (fun call => call.operation == .builtin "solana.runtime.allocator")

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"allocator metadata `{key}` mismatch"

def bumpSpec : ProofForge.Contract.ContractSpec :=
  build "AllocatorBump" do
    bumpAllocator

def noAllocSpec : ProofForge.Contract.ContractSpec :=
  build "AllocatorNone" do
    noAllocator

def requireAllocatorPlan
    (spec : ProofForge.Contract.ContractSpec)
    (kind model heapBytes assemblyNeedle manifestNeedle releaseNeedle : String) : IO Unit := do
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"allocator routing failed: {err.render}"
  require (plan.capabilities.any (fun capability => capability == .runtimeAllocator))
    "plan missing runtime.allocator capability"
  let call ←
    match allocatorCall? plan with
    | some call => pure call
    | none => throw <| IO.userError "plan missing solana.runtime.allocator call"
  requireMetadata call "solana.extension" "allocator"
  requireMetadata call "solana.allocator.kind" kind
  requireMetadata call "solana.allocator.heap_start" "0x300000000"
  requireMetadata call "solana.allocator.heap_bytes" heapBytes
  requireMetadata call "solana.allocator.model" model

  let extensions := ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan
  require (extensions.allocators.size == 1) "extensions should contain one runtime allocator"
  let manifest := ProofForge.Backend.Solana.Manifest.renderManifestWithPlan spec.module plan
  require (contains manifest "[[solana.allocator]]") "manifest missing allocator table"
  require (contains manifest manifestNeedle) "manifest missing allocator metadata"
  let asm := ProofForge.Backend.Solana.Asm.renderNodes
    (ProofForge.Backend.Solana.Extension.lowerPlan plan)
  require (contains asm assemblyNeedle) "assembly missing allocator metadata"
  let idl := ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan
  require (contains idl "\"strategy\": \"bump\"") "idl missing shared strategy"
  require (contains idl ("\"release\": \"" ++ releaseNeedle ++ "\"")) "idl missing shared release"
  require (contains idl "\"base\": \"12884901888\"") "idl missing shared region base"
  require (contains idl ("\"size\": \"" ++ heapBytes ++ "\"")) "idl missing shared region size"

def main : IO UInt32 := do
  requireAllocatorPlan bumpSpec "bump" "downward-bump" "32768"
    "solana.allocator runtime: kind=bump model=downward-bump heap_start=0x300000000 heap_bytes=32768"
    "model = \"downward-bump\""
    "noop"
  requireAllocatorPlan noAllocSpec "none" "deny-dynamic" "0"
    "solana.allocator runtime: kind=none model=deny-dynamic heap_start=0x300000000 heap_bytes=0"
    "model = \"deny-dynamic\""
    "none"

  match resolveSpec evm bumpSpec with
  | .ok _ => throw <| IO.userError "EVM unexpectedly accepted Solana runtime allocator"
  | .error err =>
      require (contains err.render "cannot use Solana target extension metadata")
        s!"unexpected EVM diagnostic: {err.render}"

  IO.println "solana-allocator: ok"
  return 0

end ProofForge.Tests.SolanaAllocator

def main : IO UInt32 :=
  ProofForge.Tests.SolanaAllocator.main
