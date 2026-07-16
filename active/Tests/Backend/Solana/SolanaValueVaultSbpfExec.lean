import ProofForge.Backend.Solana.ValueVaultSbpfExec

/-! ValueVault genericity smoke for the reusable sBPF execution layer. -/

namespace ProofForge.Tests.SolanaValueVaultSbpfExec

open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.SbpfExec
open ProofForge.Backend.Solana.ValueVaultSbpfExec

example :
    step depositStorageProgram (depositStorageInitialState 10 4 3) =
      .ok (depositState1 10 4 3) :=
  deposit_step0 10 4 3

example :
    step depositStorageProgram (depositState7 10 4 3) =
      .ok (depositState8 10 4 3) :=
  deposit_step7 10 4 3

example :
    (depositState8 10 4 3).memory.read depositNextScratch = 14 :=
  deposit_state8_next_balance_scratch 10 4 3

example :
    step depositStorageProgram (depositState16 10 4 3) =
      .ok (depositState17 10 4 3) :=
  deposit_step16 10 4 3

example :
    step depositStorageProgram (depositState17 10 4 3) =
      .ok (depositState18 10 4 3) :=
  deposit_step17 10 4 3

example :
    (depositState18 10 4 3).memory.read balanceOff = 14 :=
  deposit_state18_balance 10 4 3

example :
    runSteps depositStorageProgram 24 (depositStorageInitialState 10 4 3) =
      .ok (depositFinalState 10 4 3) :=
  deposit_runSteps 10 4 3

example :
    (depositFinalState 10 4 3).memory.read balanceOff = 14 :=
  depositFinal_balance 10 4 3

example :
    (depositFinalState 10 4 3).memory.read lastValueOff = 4 :=
  depositFinal_last_value 10 4 3

example :
    (depositFinalState 10 4 3).memory.read operationsOff = 4 :=
  depositFinal_operations 10 4 3

example :
    runSteps getNetValueStorageProgram 18 (getNetValueInitialState 20 7) =
      .ok (getNetFinalState 20 7) :=
  getNetValue_runSteps 20 7

example :
    (getNetFinalState 20 7).returnData = some 13 :=
  getNetValue_return_data 20 7

example :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "balance" =
      some balanceOff :=
  balanceOff_matches_layout

example :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "fees" =
      some feesOff :=
  feesOff_matches_layout

example :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "last_value" =
      some lastValueOff :=
  lastValueOff_matches_layout

example :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "operations" =
      some operationsOff :=
  operationsOff_matches_layout

end ProofForge.Tests.SolanaValueVaultSbpfExec

def main : IO UInt32 := do
  IO.println "solana-value-vault-sbpf-exec: generic SbpfExec reuse checked"
  return 0
