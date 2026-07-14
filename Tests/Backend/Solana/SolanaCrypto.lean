import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.SbpfAsm
import Examples.Backend.Solana.Contracts.Crypto
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaCrypto

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

def scopedCryptoCall? (plan : CapabilityPlan) (name entrypoint : String) : Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .cryptoHash &&
    metadataValue? call "solana.crypto.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def main : IO UInt32 := do
  let spec := Examples.Backend.Solana.Contracts.Crypto.spec
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana crypto routing failed: {err.render}"

  require (hasCapability plan .cryptoHash)
    "Solana crypto plan missing crypto.hash capability"
  require (hasCapability plan .storageScalar)
    "Solana crypto plan missing storage.scalar capability"

  let hashCall ←
    match scopedCryptoCall? plan "hash_preimage" "hash_preimage" with
    | some call => pure call
    | none => throw <| IO.userError "Solana crypto plan missing hash_preimage action"
  require (hashCall.operation == .builtin "solana.crypto.sha256")
    "hash_preimage should lower through solana.crypto.sha256"
  requireMetadata hashCall "solana.extension" "crypto"
  requireMetadata hashCall "solana.crypto.op" "sha256"
  requireMetadata hashCall "solana.crypto.input_state" "preimage"
  requireMetadata hashCall "solana.crypto.bytes" "8"
  requireMetadata hashCall "solana.crypto.output_states" "hash0,hash1,hash2,hash3"
  requireMetadata hashCall "solana.crypto.feature_gated" "false"

  let keccakCall ←
    match scopedCryptoCall? plan "keccak_preimage" "keccak_preimage" with
    | some call => pure call
    | none => throw <| IO.userError "Solana crypto plan missing keccak_preimage action"
  require (keccakCall.operation == .builtin "solana.crypto.keccak256")
    "keccak_preimage should lower through solana.crypto.keccak256"
  requireMetadata keccakCall "solana.extension" "crypto"
  requireMetadata keccakCall "solana.crypto.op" "keccak256"
  requireMetadata keccakCall "solana.crypto.input_state" "preimage"
  requireMetadata keccakCall "solana.crypto.bytes" "8"
  requireMetadata keccakCall "solana.crypto.output_states" "keccak0,keccak1,keccak2,keccak3"
  requireMetadata keccakCall "solana.crypto.feature_gated" "false"

  let blake3Call ←
    match scopedCryptoCall? plan "blake3_preimage" "blake3_preimage" with
    | some call => pure call
    | none => throw <| IO.userError "Solana crypto plan missing blake3_preimage action"
  require (blake3Call.operation == .builtin "solana.crypto.blake3")
    "blake3_preimage should lower through solana.crypto.blake3"
  requireMetadata blake3Call "solana.extension" "crypto"
  requireMetadata blake3Call "solana.crypto.op" "blake3"
  requireMetadata blake3Call "solana.crypto.input_state" "preimage"
  requireMetadata blake3Call "solana.crypto.bytes" "8"
  requireMetadata blake3Call "solana.crypto.output_states" "blake0,blake1,blake2,blake3"
  requireMetadata blake3Call "solana.crypto.feature_gated" "true"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-crypto-hash" spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "crypto package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "crypto package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "[[solana.entrypoint_crypto]]")
        "crypto manifest missing entrypoint crypto action section"
      require (contains manifest "crypto = \"hash_preimage\"")
        "crypto manifest missing hash_preimage action"
      require (contains manifest "op = \"sha256\"")
        "crypto manifest missing sha256 op"
      require (contains manifest "input_state = \"preimage\"")
        "crypto manifest missing input state"
      require (contains manifest "output_states = [\"hash0\", \"hash1\", \"hash2\", \"hash3\"]")
        "crypto manifest missing output states"
      require (contains manifest "feature_gated = false")
        "crypto manifest missing non-feature-gated hash markers"
      require (contains manifest "crypto = \"keccak_preimage\"")
        "crypto manifest missing keccak_preimage action"
      require (contains manifest "op = \"keccak256\"")
        "crypto manifest missing keccak256 op"
      require (contains manifest "output_states = [\"keccak0\", \"keccak1\", \"keccak2\", \"keccak3\"]")
        "crypto manifest missing keccak output states"
      require (contains manifest "crypto = \"blake3_preimage\"")
        "crypto manifest missing blake3_preimage action"
      require (contains manifest "op = \"blake3\"")
        "crypto manifest missing blake3 op"
      require (contains manifest "output_states = [\"blake0\", \"blake1\", \"blake2\", \"blake3\"]")
        "crypto manifest missing blake3 output states"
      require (contains manifest "feature_gated = true")
        "crypto manifest missing blake3 feature gate"
      require (contains asm "solana.crypto.action hash_preimage")
        "assembly missing crypto action"
      require (contains asm "sol_crypto_sha256_hash_preimage:")
        "assembly missing sha256 helper label"
      require (contains asm "solana.crypto.hash hash_preimage: op=sha256 input=preimage bytes=8")
        "assembly missing crypto hash marker"
      require (contains asm "call sol_sha256")
        "assembly missing sol_sha256 syscall"
      require (contains asm "solana.crypto.action keccak_preimage")
        "assembly missing keccak crypto action"
      require (contains asm "sol_crypto_keccak256_keccak_preimage:")
        "assembly missing keccak256 helper label"
      require (contains asm "solana.crypto.hash keccak_preimage: op=keccak256 input=preimage bytes=8")
        "assembly missing keccak hash marker"
      require (contains asm "call sol_keccak256")
        "assembly missing sol_keccak256 syscall"
      require (contains asm "solana.crypto.action blake3_preimage")
        "assembly missing blake3 crypto action"
      require (contains asm "sol_crypto_blake3_blake3_preimage:")
        "assembly missing blake3 helper label"
      require (contains asm "solana.crypto.hash blake3_preimage: op=blake3 input=preimage bytes=8 feature_gated=true")
        "assembly missing blake3 hash marker"
      require (contains asm "call sol_blake3")
        "assembly missing sol_blake3 syscall"
      require (contains asm "solana.crypto.output hash_preimage[3] state=hash3")
        "assembly missing fourth hash output copy"
      require (contains asm "solana.crypto.output keccak_preimage[3] state=keccak3")
        "assembly missing fourth keccak output copy"
      require (contains asm "solana.crypto.output blake3_preimage[3] state=blake3")
        "assembly missing fourth blake3 output copy"
      require (contains asm "add64 r5, 24")
        "assembly should read the fourth digest word from result_ptr + 24"
  | .error err =>
      throw <| IO.userError s!"Solana crypto package render failed: {err.render}"

  IO.println "solana-crypto: ok"
  return 0

end ProofForge.Tests.SolanaCrypto

def main : IO UInt32 :=
  ProofForge.Tests.SolanaCrypto.main
