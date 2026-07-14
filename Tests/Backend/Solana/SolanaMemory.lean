import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.SbpfAsm
import Examples.Backend.Solana.Contracts.Memory
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaMemory

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun c => c == capability)

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

def scopedMemoryCall? (plan : CapabilityPlan) (name entrypoint : String) : Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .runtimeMemory &&
    metadataValue? call "solana.memory.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def main : IO UInt32 := do
  let spec := Examples.Backend.Solana.Contracts.Memory.spec
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana memory routing failed: {err.render}"

  require (hasCapability plan .runtimeMemory)
    "Solana memory plan missing runtime.memory capability"
  require (hasCapability plan .storageScalar)
    "Solana memory plan missing storage.scalar capability"

  let copyCall ←
    match scopedMemoryCall? plan "copy_source" "copy_compare_fill" with
    | some call => pure call
    | none => throw <| IO.userError "Solana memory plan missing copy_source action"
  require (copyCall.operation == .builtin "solana.memory.memcpy")
    "copy_source should lower through solana.memory.memcpy"
  requireMetadata copyCall "solana.extension" "memory"
  requireMetadata copyCall "solana.memory.op" "memcpy"
  requireMetadata copyCall "solana.memory.dst_state" "copied"
  requireMetadata copyCall "solana.memory.src_state" "source"
  requireMetadata copyCall "solana.memory.bytes" "8"

  let moveCall ←
    match scopedMemoryCall? plan "move_source" "copy_compare_fill" with
    | some call => pure call
    | none => throw <| IO.userError "Solana memory plan missing move_source action"
  require (moveCall.operation == .builtin "solana.memory.memmove")
    "move_source should lower through solana.memory.memmove"
  requireMetadata moveCall "solana.memory.op" "memmove"
  requireMetadata moveCall "solana.memory.dst_state" "moved"
  requireMetadata moveCall "solana.memory.src_state" "source"
  requireMetadata moveCall "solana.memory.bytes" "8"

  let cmpCall ←
    match scopedMemoryCall? plan "compare_copy" "copy_compare_fill" with
    | some call => pure call
    | none => throw <| IO.userError "Solana memory plan missing compare_copy action"
  requireMetadata cmpCall "solana.memory.op" "memcmp"
  requireMetadata cmpCall "solana.memory.lhs_state" "source"
  requireMetadata cmpCall "solana.memory.rhs_state" "copied"
  requireMetadata cmpCall "solana.memory.result_state" "cmp_result"

  let fillCall ←
    match scopedMemoryCall? plan "fill_bytes" "copy_compare_fill" with
    | some call => pure call
    | none => throw <| IO.userError "Solana memory plan missing fill_bytes action"
  requireMetadata fillCall "solana.memory.op" "memset"
  requireMetadata fillCall "solana.memory.dst_state" "filled"
  requireMetadata fillCall "solana.memory.value" "170"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-memory" spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "memory package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "memory package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "[[solana.entrypoint_memory]]")
        "memory manifest missing entrypoint memory action section"
      require (contains manifest "memory = \"copy_source\"")
        "memory manifest missing copy_source action"
      require (contains manifest "op = \"memcpy\"")
        "memory manifest missing memcpy op"
      require (contains manifest "bytes = 8")
        "memory manifest missing byte count"
      require (contains manifest "value = 170")
        "memory manifest missing memset byte value"
      require (contains asm "solana.memory.action copy_source")
        "assembly missing memory copy action"
      require (contains asm "sol_memory_memcpy_copy_source:")
        "assembly missing memcpy helper label"
      require (contains asm "solana.memory.memcpy copy_source: dst=copied src=source bytes=8")
        "assembly missing memcpy marker"
      require (contains asm "call sol_memcpy_")
        "assembly missing sol_memcpy_ syscall"
      require (contains manifest "memory = \"move_source\"")
        "memory manifest missing move_source action"
      require (contains manifest "op = \"memmove\"")
        "memory manifest missing memmove op"
      require (contains asm "sol_memory_memmove_move_source:")
        "assembly missing memmove helper label"
      require (contains asm "call sol_memmove_")
        "assembly missing sol_memmove_ syscall"
      require (contains asm "sol_memory_memcmp_compare_copy:")
        "assembly missing memcmp helper label"
      require (contains asm "call sol_memcmp_")
        "assembly missing sol_memcmp_ syscall"
      require (contains asm "stxdw [r5+0], r3")
        "assembly missing memcmp result state write"
      require (contains asm "sol_memory_memset_fill_bytes:")
        "assembly missing memset helper label"
      require (contains asm "call sol_memset_")
        "assembly missing sol_memset_ syscall"
  | .error err =>
      throw <| IO.userError s!"Solana memory package render failed: {err.render}"

  IO.println "solana-memory: ok"
  return 0

end ProofForge.Tests.SolanaMemory

def main : IO UInt32 :=
  ProofForge.Tests.SolanaMemory.main
