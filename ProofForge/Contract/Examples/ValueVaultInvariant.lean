import ProofForge.Contract.Examples.ValueVault
import ProofForge.IR.Semantics

namespace ProofForge.Contract.Examples.ValueVaultInvariant

open ProofForge.IR

abbrev SemState := ProofForge.IR.Semantics.State
abbrev SemValue := ProofForge.IR.Semantics.Value

structure ScenarioInputs where
  initial : Nat
  deposit : Nat
  grossCharge : Nat
  feeBps : Nat
  release : Nat
  deriving Repr, BEq

structure ScenarioResult where
  state : SemState
  observedReturns : Array (Option SemValue)
  deriving Repr, BEq

def defaultInputs : ScenarioInputs := {
  initial := 100
  deposit := 25
  grossCharge := 100
  feeBps := 250
  release := 23
}

def expectedFee (inputs : ScenarioInputs) : Nat :=
  inputs.grossCharge * inputs.feeBps / 10000

def expectedNetCharge (inputs : ScenarioInputs) : Nat :=
  inputs.grossCharge - expectedFee inputs

def expectedSuppliedValue (inputs : ScenarioInputs) : Nat :=
  inputs.initial + inputs.deposit + inputs.grossCharge

def expectedBalance (inputs : ScenarioInputs) : Nat :=
  inputs.initial + inputs.deposit + expectedNetCharge inputs - inputs.release

def expectedNetValue (inputs : ScenarioInputs) : Nat :=
  expectedBalance inputs - expectedFee inputs

def module : Module :=
  ProofForge.Contract.Examples.ValueVault.module

def entrypoint? (name : String) : Option Entrypoint :=
  module.entrypoints.find? fun entrypoint => entrypoint.name == name

def runNamed (state : SemState) (name : String) (args : Array SemValue := #[]) :
    Except String (SemState × Option SemValue) := do
  let entrypoint ←
    match entrypoint? name with
    | some entrypoint => .ok entrypoint
    | none => .error s!"ValueVault entrypoint `{name}` not found"
  ProofForge.IR.Semantics.runEntrypointWithArgs state entrypoint args

def runScenario (inputs : ScenarioInputs) : Except String ScenarioResult := do
  let (stateAfterInitialize, initializeReturn) ←
    runNamed ProofForge.IR.Semantics.State.empty "initialize" #[.u64 inputs.initial]
  let (stateAfterInitialBalance, initialBalance) ←
    runNamed stateAfterInitialize "get_balance"
  let (stateAfterDeposit, depositReturn) ←
    runNamed stateAfterInitialBalance "deposit" #[.u64 inputs.deposit]
  let (stateAfterDepositBalance, depositBalance) ←
    runNamed stateAfterDeposit "get_balance"
  let (stateAfterCharge, chargeReturn) ←
    runNamed stateAfterDepositBalance "charge_fee" #[.u64 inputs.grossCharge, .u64 inputs.feeBps]
  let (stateAfterChargeBalance, chargeBalance) ←
    runNamed stateAfterCharge "get_balance"
  let (stateAfterChargeNet, chargeNet) ←
    runNamed stateAfterChargeBalance "get_net_value"
  let (stateAfterRelease, releaseReturn) ←
    runNamed stateAfterChargeNet "release" #[.u64 inputs.release]
  let (stateAfterReleaseBalance, releaseBalance) ←
    runNamed stateAfterRelease "get_balance"
  let (stateAfterSnapshot, snapshotReturn) ←
    runNamed stateAfterReleaseBalance "snapshot"
  let (finalState, finalNet) ←
    runNamed stateAfterSnapshot "get_net_value"
  .ok {
    state := finalState
    observedReturns := #[
      initializeReturn,
      initialBalance,
      depositReturn,
      depositBalance,
      chargeReturn,
      chargeBalance,
      chargeNet,
      releaseReturn,
      releaseBalance,
      snapshotReturn,
      finalNet
    ]
  }

def readU64? (state : SemState) (name : String) : Option Nat :=
  match state.read name with
  | some (.u64 value) => some value
  | _ => none

def readU64D (state : SemState) (name : String) : Nat :=
  (readU64? state name).getD 0

def accountingValue (state : SemState) : Nat :=
  readU64D state "balance" + readU64D state "released" + readU64D state "fees"

def accountingInvariantHolds (inputs : ScenarioInputs) (state : SemState) : Bool :=
  accountingValue state == expectedSuppliedValue inputs

def finalStorageMatches (inputs : ScenarioInputs) (state : SemState) : Bool :=
  readU64? state "balance" == some (expectedBalance inputs) &&
    readU64? state "released" == some inputs.release &&
    readU64? state "fees" == some (expectedFee inputs) &&
    readU64? state "last_value" == some inputs.release &&
    readU64? state "last_checkpoint" == some 0 &&
    readU64? state "operations" == some 4

def returnU64At? (result : ScenarioResult) (index : Nat) : Option Nat :=
  match result.observedReturns[index]? with
  | some (some (.u64 value)) => some value
  | _ => none

def expectedReturns (inputs : ScenarioInputs) : Array (Option SemValue) := #[
  none,
  some (.u64 inputs.initial),
  none,
  some (.u64 (inputs.initial + inputs.deposit)),
  none,
  some (.u64 (inputs.initial + inputs.deposit + expectedNetCharge inputs)),
  some (.u64 (inputs.initial + inputs.deposit + expectedNetCharge inputs - expectedFee inputs)),
  none,
  some (.u64 (expectedBalance inputs)),
  some (.u64 (expectedBalance inputs)),
  some (.u64 (expectedNetValue inputs))
]

def defaultScenarioTraceOk : Bool :=
  match runScenario defaultInputs with
  | .ok result => result.observedReturns == expectedReturns defaultInputs
  | .error _ => false

def defaultScenarioAccountingOk : Bool :=
  match runScenario defaultInputs with
  | .ok result =>
      accountingInvariantHolds defaultInputs result.state &&
        finalStorageMatches defaultInputs result.state
  | .error _ => false

def netValueInvariantHolds (state : SemState) (netValue : Nat) : Bool :=
  netValue == readU64D state "balance" - readU64D state "fees"

def defaultScenarioNetValueOk : Bool :=
  match runScenario defaultInputs with
  | .ok result =>
      returnU64At? result 10 == some (expectedNetValue defaultInputs) &&
        match returnU64At? result 10 with
        | some netValue => netValueInvariantHolds result.state netValue
        | none => false
  | .error _ => false

theorem value_vault_default_trace_ok :
    defaultScenarioTraceOk = true := by
  native_decide

theorem value_vault_accounting_invariant_trace_ok :
    defaultScenarioAccountingOk = true := by
  native_decide

theorem value_vault_net_value_invariant_trace_ok :
    defaultScenarioNetValueOk = true := by
  native_decide

end ProofForge.Contract.Examples.ValueVaultInvariant
