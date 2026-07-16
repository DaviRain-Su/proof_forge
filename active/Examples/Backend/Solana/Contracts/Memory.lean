import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.Memory

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaMemory" do
    scalarState "source" .u64
    scalarState "copied" .u64
    scalarState "filled" .u64
    scalarState "cmp_result" .u64
    scalarState "moved" .u64

    entrySelectorWithParams "set_source" "0a" #[("value", .u64)] .unit do
      effect (storageScalarWrite "source" (localVar "value"))
      effect (storageScalarWrite "copied" (u64 0))
      effect (storageScalarWrite "filled" (u64 0))
      effect (storageScalarWrite "cmp_result" (u64 999))
      effect (storageScalarWrite "moved" (u64 0))

    entrySelector "copy_compare_fill" "0b" do
      memcpyState "copy_source" "copied" "source" 8
      memmoveState "move_source" "moved" "source" 8
      memcmpState "compare_copy" "source" "copied" "cmp_result" 8
      memsetState "fill_bytes" "filled" 170 8

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.Memory
