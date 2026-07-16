import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.EpochSchedule

open ProofForge.Contract.Builder

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaEpochSchedule" do
    scalarState "slots_per_epoch" .u64
    scalarState "leader_schedule_slot_offset" .u64
    scalarState "warmup" .u64
    scalarState "first_normal_epoch" .u64
    scalarState "first_normal_slot" .u64

    entrySelector "record_epoch_schedule" "10" do
      ProofForge.Contract.Source.Solana.Legacy.epochScheduleSlotsPerEpochToState
        "read_epoch_schedule"
        "slots_per_epoch"
      ProofForge.Contract.Source.Solana.Legacy.epochScheduleLeaderScheduleSlotOffsetToState
        "read_leader_schedule_slot_offset"
        "leader_schedule_slot_offset"
      ProofForge.Contract.Source.Solana.Legacy.epochScheduleWarmupToState
        "read_warmup"
        "warmup"
      ProofForge.Contract.Source.Solana.Legacy.epochScheduleFirstNormalEpochToState
        "read_first_normal_epoch"
        "first_normal_epoch"
      ProofForge.Contract.Source.Solana.Legacy.epochScheduleFirstNormalSlotToState
        "read_first_normal_slot"
        "first_normal_slot"

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.EpochSchedule
