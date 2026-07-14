import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.Crypto

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def hashOutputStates : Array String :=
  #["hash0", "hash1", "hash2", "hash3"]

def keccakOutputStates : Array String :=
  #["keccak0", "keccak1", "keccak2", "keccak3"]

def blake3OutputStates : Array String :=
  #["blake0", "blake1", "blake2", "blake3"]

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaCryptoHash" do
    scalarState "preimage" .u64
    scalarState "hash0" .u64
    scalarState "hash1" .u64
    scalarState "hash2" .u64
    scalarState "hash3" .u64
    scalarState "keccak0" .u64
    scalarState "keccak1" .u64
    scalarState "keccak2" .u64
    scalarState "keccak3" .u64
    scalarState "blake0" .u64
    scalarState "blake1" .u64
    scalarState "blake2" .u64
    scalarState "blake3" .u64

    entrySelectorWithParams "set_preimage" "0c" #[("value", .u64)] .unit do
      effect (storageScalarWrite "preimage" (localVar "value"))
      effect (storageScalarWrite "hash0" (u64 0))
      effect (storageScalarWrite "hash1" (u64 0))
      effect (storageScalarWrite "hash2" (u64 0))
      effect (storageScalarWrite "hash3" (u64 0))
      effect (storageScalarWrite "keccak0" (u64 0))
      effect (storageScalarWrite "keccak1" (u64 0))
      effect (storageScalarWrite "keccak2" (u64 0))
      effect (storageScalarWrite "keccak3" (u64 0))
      effect (storageScalarWrite "blake0" (u64 0))
      effect (storageScalarWrite "blake1" (u64 0))
      effect (storageScalarWrite "blake2" (u64 0))
      effect (storageScalarWrite "blake3" (u64 0))

    entrySelector "hash_preimage" "0d" do
      sha256StateToStates "hash_preimage" "preimage" 8 hashOutputStates

    entrySelector "keccak_preimage" "0e" do
      keccak256StateToStates "keccak_preimage" "preimage" 8 keccakOutputStates

    entrySelector "blake3_preimage" "0f" do
      blake3StateToStates "blake3_preimage" "preimage" 8 blake3OutputStates

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.Crypto
