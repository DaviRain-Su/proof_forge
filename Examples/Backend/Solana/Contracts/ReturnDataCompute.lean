import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.ReturnDataCompute

open ProofForge.Contract.Builder
open ProofForge.Contract.Source.Solana.Legacy

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaReturnDataCompute" do
    scalarState "result" .u64
    scalarState "last_return" .u64
    scalarState "return_len" .u64
    scalarState "return_program0" .u64
    scalarState "return_program1" .u64
    scalarState "return_program2" .u64
    scalarState "return_program3" .u64
    scalarState "remaining" .u64

    entrySelectorWithParams "set_result" "12" #[("value", .u64)] .unit do
      effect (storageScalarWrite "result" (localVar "value"))
      effect (storageScalarWrite "last_return" (u64 0))
      effect (storageScalarWrite "return_len" (u64 0))
      effect (storageScalarWrite "return_program0" (u64 0))
      effect (storageScalarWrite "return_program1" (u64 0))
      effect (storageScalarWrite "return_program2" (u64 0))
      effect (storageScalarWrite "return_program3" (u64 0))
      effect (storageScalarWrite "remaining" (u64 0))

    entrySelector "publish_result" "13" do
      setReturnDataFromState "publish_result_data" "result" 8

    entrySelector "record_compute" "14" do
      remainingComputeUnitsToState "record_remaining" "remaining"

    entrySelector "read_return_data" "15" do
      getReturnDataToState "read_latest_return_data" "last_return" 8
        (lengthState? := some "return_len")
        (programIdStates := #[
          "return_program0",
          "return_program1",
          "return_program2",
          "return_program3"
        ])

    entrySelector "log_compute" "16" do
      logRemainingComputeUnits "log_remaining"

    entrySelector "roundtrip_return_data" "17" do
      setReturnDataFromState "roundtrip_publish_result_data" "result" 8
      getReturnDataToState "roundtrip_read_return_data" "last_return" 8
        (lengthState? := some "return_len")
        (programIdStates := #[
          "return_program0",
          "return_program1",
          "return_program2",
          "return_program3"
        ])

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.ReturnDataCompute
