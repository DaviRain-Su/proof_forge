import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy

namespace Examples.Backend.Solana.Contracts.EpochRewards

open ProofForge.Contract.Builder

def spec : ProofForge.Contract.ContractSpec :=
  build "SolanaEpochRewards" do
    scalarState "distribution_starting_block_height" .u64
    scalarState "num_partitions" .u64
    scalarState "parent_blockhash_word0" .u64
    scalarState "parent_blockhash_word1" .u64
    scalarState "parent_blockhash_word2" .u64
    scalarState "parent_blockhash_word3" .u64
    scalarState "total_points_low" .u64
    scalarState "total_points_high" .u64
    scalarState "total_rewards" .u64
    scalarState "distributed_rewards" .u64
    scalarState "active" .u64

    entrySelector "record_epoch_rewards" "12" do
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsDistributionStartingBlockHeightToState
        "read_distribution_starting_block_height"
        "distribution_starting_block_height"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsNumPartitionsToState
        "read_num_partitions"
        "num_partitions"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsParentBlockhashWord0ToState
        "read_parent_blockhash_word0"
        "parent_blockhash_word0"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsParentBlockhashWord1ToState
        "read_parent_blockhash_word1"
        "parent_blockhash_word1"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsParentBlockhashWord2ToState
        "read_parent_blockhash_word2"
        "parent_blockhash_word2"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsParentBlockhashWord3ToState
        "read_parent_blockhash_word3"
        "parent_blockhash_word3"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsTotalPointsLowToState
        "read_total_points_low"
        "total_points_low"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsTotalPointsHighToState
        "read_total_points_high"
        "total_points_high"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsTotalRewardsToState
        "read_total_rewards"
        "total_rewards"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsDistributedRewardsToState
        "read_distributed_rewards"
        "distributed_rewards"
      ProofForge.Contract.Source.Solana.Legacy.epochRewardsActiveToState
        "read_active"
        "active"

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Backend.Solana.Contracts.EpochRewards
