import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.LeanInvariant
import ProofForge.IR.Semantics

/-! ## FV-8 user-authored Lean invariants — ValueVault authoring example

This file is the canonical example of the FV-8 user-invariant authoring
mode (Track 1.7). The contract author declares invariants next to
`contract_source`, proven pre-codegen against the IR semantics — a pure-Lean,
backend-agnostic product surface (no Quint MBT, no per-target lowering
dependency).

The pattern (see `ProofForge.Contract.LeanInvariant` for the reusable
machinery):

1. Define the contract (`contract_source` in `ValueVault.lean`).
2. Declare named Lean invariants as `State → Bool` predicates.
3. Bundle them into a `ContractInvariants` via `InvariantSpec.declare`.
4. Define a scenario (a prefix of entrypoint calls from an initial state).
5. Machine-check `verifyInvariantsAfterScenario` returns `true`, yielding the
   `invariants_hold_after_scenario` soundness witness.

This turns the previous one-off scenario test into a reusable authoring mode:
any contract follows the same shape, and the gate machine-checks the invariants
pre-codegen.
-/

namespace ProofForge.Contract.Examples.ValueVaultInvariant

open ProofForge.IR
open ProofForge.Contract.LeanInvariant

abbrev SemState := ProofForge.IR.Semantics.State
abbrev SemValue := ProofForge.IR.Semantics.Value

structure ScenarioInputs where
  initial : Nat
  deposit : Nat
  grossCharge : Nat
  feeBps : Nat
  release : Nat
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

/-! ### User-declared Lean invariants (the FV-8 authoring surface)

Each invariant is a `State → Bool` predicate. These are the *Lean* invariants
(parallel to the `quint_invariant` annotations, which are string expressions
for Quint MBT). The Lean invariants are machine-checked here pre-codegen. -/

/-- Accounting invariant: balance + released + fees equals the total supplied
value (initial + deposit + grossCharge). -/
def accountingInvariant (inputs : ScenarioInputs) (state : SemState) : Bool :=
  readU64D state "balance" + readU64D state "released" + readU64D state "fees"
    == expectedSuppliedValue inputs

/-- Net-value invariant: `get_net_value` returns balance - fees. -/
def netValueInvariant (inputs : ScenarioInputs) (state : SemState) : Bool :=
  let netValue := expectedNetValue inputs
  netValue == readU64D state "balance" - readU64D state "fees"

/-- Final-storage invariant: the canonical scenario drives the six scalar
fields to their expected values. -/
def finalStorageInvariant (inputs : ScenarioInputs) (state : SemState) : Bool :=
  readU64? state "balance" == some (expectedBalance inputs) &&
    readU64? state "released" == some inputs.release &&
    readU64? state "fees" == some (expectedFee inputs) &&
    readU64? state "last_value" == some inputs.release &&
    readU64? state "last_checkpoint" == some 0 &&
    readU64? state "operations" == some 4

/-- The ValueVault invariant bundle for the canonical scenario. -/
def valueVaultInvariants (inputs : ScenarioInputs) : ContractInvariants :=
  { moduleName := module.name
    invariants := #[
      InvariantSpec.declare "accounting" (accountingInvariant inputs),
      InvariantSpec.declare "net_value" (netValueInvariant inputs),
      InvariantSpec.declare "final_storage" (finalStorageInvariant inputs)
    ] }

/-! ### Scenario (prefix of entrypoint calls from the empty initial state) -/

def canonicalScenario (inputs : ScenarioInputs) : Array ScenarioStep := #[
  { entrypointName := "initialize", args := #[.u64 inputs.initial] },
  { entrypointName := "get_balance" },
  { entrypointName := "deposit", args := #[.u64 inputs.deposit] },
  { entrypointName := "get_balance" },
  { entrypointName := "charge_fee", args := #[.u64 inputs.grossCharge, .u64 inputs.feeBps] },
  { entrypointName := "get_balance" },
  { entrypointName := "get_net_value" },
  { entrypointName := "release", args := #[.u64 inputs.release] },
  { entrypointName := "get_balance" },
  { entrypointName := "snapshot" },
  { entrypointName := "get_net_value" }
  ]

def initialState : SemState := ProofForge.IR.Semantics.State.empty

/-! ### Pre-codegen machine check

`verifyInvariantsAfterScenario` runs the canonical scenario from the empty
state and checks every declared invariant holds on the final state. The
following theorem is the soundness witness. -/

def verified : Bool :=
  verifyInvariantsAfterScenario module (valueVaultInvariants defaultInputs)
    initialState (canonicalScenario defaultInputs)

theorem value_vault_invariants_hold_after_scenario :
    verified = true := by
  native_decide

/-- Soundness: the verified flag implies the scenario ran successfully and all
invariants hold on the final state. -/
theorem value_vault_invariants_sound :
    verified = true →
      ∃ finalState, allInvariantsHold (valueVaultInvariants defaultInputs) finalState = true ∧
        (∃ observed, runScenario module initialState (canonicalScenario defaultInputs) = .ok (finalState, observed)) :=
  value_vault_invariants_hold_after_scenario ▸
    invariants_hold_after_scenario module (valueVaultInvariants defaultInputs)
      initialState (canonicalScenario defaultInputs)

/-! ### Backward-compatible scenario API

The Wasm/NEAR offline-host refinement (`ProofForge.Backend.WasmHost.Refinement.Core`)
consumes the scenario runner and per-scenario expected results/final-state
predicates. These keep the pre-refinement shape so that side of the pipeline
is unaffected by the FV-8 authoring refactor. -/

structure ScenarioResult where
  state : SemState
  observedReturns : Array (Option SemValue)
  deriving Repr, BEq

def runNamed (state : SemState) (name : String) (args : Array SemValue := #[]) :
    Except String (SemState × Option SemValue) := do
  let entrypoint ←
    match module.entrypoints.find? (fun e => e.name == name) with
    | some e => .ok e
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
      initializeReturn, initialBalance, depositReturn, depositBalance,
      chargeReturn, chargeBalance, chargeNet, releaseReturn, releaseBalance,
      snapshotReturn, finalNet
    ]
  }

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

def accountingInvariantHolds (inputs : ScenarioInputs) (state : SemState) : Bool :=
  accountingInvariant inputs state

def finalStorageMatches (inputs : ScenarioInputs) (state : SemState) : Bool :=
  finalStorageInvariant inputs state

/-! ### Backward-compatible default-scenario Bool checks -/

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
      match result.observedReturns[10]? with
      | some (some (ProofForge.IR.Semantics.Value.u64 netValue)) =>
          netValue == expectedNetValue defaultInputs &&
            netValueInvariantHolds result.state netValue
      | _ => false
  | .error _ => false

/-- Backward-compatible theorem name. -/
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