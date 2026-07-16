import ProofForge.IR.SemanticsFuel
import ProofForge.IR.CounterSemantics
import ProofForge.IR.ValueVaultSemantics
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

/-! ## FV-9.0 M6: shared fueled IR interpreter smoke gate

Exercises the generic, total, fuel-indexed interpreter
(`ProofForge.IR.SemanticsFuel`) that the FV-9 `∀ module` compiler-correctness
theorem quantifies over. This gate is the M6 deliverable and lives in
`just check` so the shared interpreter stays green on every commit.
-/

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.SemanticsFuel
open ProofForge.IR.CounterSemantics
open ProofForge.IR.ValueVaultSemantics
open ProofForge.IR.Examples.Counter
open ProofForge.IR.Examples.ValueVault

-- 1. The shared interpreter exists and is total (no contract names inside).
#check (evalExprFuel : Nat → State → Frame → Expr → Except String ExprResult)
#check (execStmtFuel : Nat → State → Frame → Statement → Except String (State × Frame × Option Value))
#check (execStatementsFuel : Nat → List Statement → State → Frame → Except String (State × Option Value))
#check (runEntrypointFuel : State → Entrypoint → Except String (State × Option Value))

-- 2. Counter is fully re-pointed: the Counter entrypoint lemmas still hold
-- through the shared interpreter via the re-export.
#check initialize_total_ok
#check get_total_ok_of_count
#check increment_total_ok_of_count
#check counter_trace_matches_legacy

-- 3. ValueVault is bridged: every product entrypoint body is within the
-- shared fueled interpreter's covered fragment (M5 + F1.3 full surface).
#check valueVault_getNetValue_in_fuel_coverage
#check valueVault_all_entrypoints_in_fuel_coverage
#check valueVault_step_simulates_all_calls

-- 4. Executable witness: the shared fueled interpreter runs the Counter
-- trace (initialize → increment → get) and returns 1, matching the legacy
-- partial interpreter's `counterTrace`.
def fuelCounterTrace : Except String (State × Option Value) := do
  let (s1, _) ← runEntrypointFuel State.empty
    ProofForge.IR.Examples.Counter.initializeEntrypoint
  let (s2, _) ← runEntrypointFuel s1
    ProofForge.IR.Examples.Counter.increment
  runEntrypointFuel s2 ProofForge.IR.Examples.Counter.get

def fuelCounterGetsOne : Bool :=
  resultMatches fuelCounterTrace (.ok ({ storage := [("count", .u64 1)] }, some (.u64 1)))

theorem fuelCounterTrace_gets_one :
    fuelCounterGetsOne = true := by
  native_decide

-- 5. The fueled and partial Counter traces agree (M3 witness — the broader
-- ∀-constructor agreement is FV-9.2's scope).
theorem fuelCounterTrace_matches_legacy :
    resultMatches fuelCounterTrace ProofForge.IR.Semantics.counterTrace = true := by
  native_decide

-- 6. ValueVault `getNetValue` on a concrete state via the shared fueled
-- interpreter produces balance - fees (executed by `runEntrypointWithArgsFuel`,
-- not the shallow step).
def valueVaultM6State : State :=
  State.empty
    |>.write "balance" (.u64 250)
    |>.write "fees" (.u64 75)

def valueVaultM6FuelGetNetValue : Bool :=
  match runEntrypointWithArgsFuel defaultFuel valueVaultM6State getNetValueEntrypoint #[] with
  | .ok (_, some (.u64 n)) => n == 175
  | _ => false

theorem valueVaultM6_getNetValue_fuel_ok :
    valueVaultM6FuelGetNetValue = true := by
  native_decide

def main : IO UInt32 := do
  IO.println "semantics-fuel-smoke: shared total fueled IR interpreter (FV-9.0) checked"
  return 0