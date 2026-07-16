import ProofForge.Backend.Refinement.ConstructorCoverage
import Examples.Product.Counter
import Examples.Product.HostEnvProbe
import Examples.Product.RemoteCall
import Examples.Product.Ownable
import Examples.Product.ValueVault
import ProofForge.IR.Examples.LoopProbe
import ProofForge.Backend.Refinement.CounterUniversal

/-! ## FV-9.2: constructor coverage table + IR-side preservation smoke gate

Exercises the FV-9.2 deliverable: the constructor coverage predicates, the
status table, the IR-side fueled-eval preservation lemmas (arithmetic core),
and the counter-model per-entrypoint preservation restated through
`TargetSemantics.irStateRel` (FV-9.1 field). This gate is the FV-9.2 deliverable
and lives in `just check`.
-/

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.SemanticsFuel
open ProofForge.Backend.Refinement
open ProofForge.Backend.Refinement.ConstructorCoverage
open ProofForge.Backend.Refinement.CounterUniversal

-- 1. Coverage predicates exist and are decidable.
#check (fuelCoveredExpr : Expr → Bool)
#check (fuelCoveredEffect : Effect → Bool)
#check (fuelCoveredStatement : Statement → Bool)

-- 2. Status table maps covered constructors to `.covered`.
#check (exprStatus : Expr → ConstructorStatus)
#check (effectStatus : Effect → ConstructorStatus)
#check (statementStatus : Statement → ConstructorStatus)

-- 3. IR-side preservation lemmas (arithmetic core) exist.
#check evalExprFuel_add_eq
#check evalExprFuel_sub_eq
#check evalExprFuel_mul_eq

-- 4. Counter-model per-entrypoint preservation consumes irStateRel (FV-9.2c).
#check counter_step_simulates_via_irStateRel

-- 5. Concrete coverage witnesses: the Counter `increment` body's
-- arithmetic + storage constructors are all `covered` (decidable check).
theorem counter_increment_add_covered :
    fuelCoveredExpr (.add (.local "current") (.local "amount") true) = true := by
  decide

theorem counter_increment_storageScalarRead_covered :
    fuelCoveredEffect (.storageScalarRead "balance") = true := by
  decide

theorem counter_increment_letBind_covered :
    fuelCoveredStatement
      (.letBind "next" .u64 (.add (.local "current") (.local "amount"))) = true := by
  decide

-- 6. The `add` preservation lemma fires on a concrete operand pair.
theorem counter_increment_add_preservation_witness
    (fuel : Nat) (state : Semantics.State) (frame : Semantics.Frame)
    (hLhs : evalExprFuel fuel state frame (.local "current") = .ok (state, .u64 5))
    (hRhs : evalExprFuel fuel state frame (.local "amount") = .ok (state, .u64 3)) :
    evalExprFuel (fuel + 1) state frame (.add (.local "current") (.local "amount") true) =
      .ok (state, .u64 8) := by
  exact evalExprFuel_add_eq fuel state frame _ _ true hLhs hRhs

-- 7. A gap constructor is correctly marked `gap`.
theorem crosscallInvoke_is_gap :
    exprStatus (.crosscallInvoke (.local "t") (.local "m") #[]) = .gap := by
  decide

-- 8. FV-9.4 module-level fragment scoping: the module coverage predicate and
-- the honesty bridge exist.
#check (moduleInCoveredFragment : Module → Bool)
#check (exprFullyCovered : Expr → Bool)
#check (effectFullyCovered : Effect → Bool)
#check (statementFullyCovered : Statement → Bool)

-- 9. Honesty bridge: structural ∀ m (FV-9.4+) + canonical corollary.
#check counterModel_fragmentAccepts_implies_covered_all
#check counterModel_fragmentAccepts_implies_covered

theorem sample_isCounterModule_implies_covered :
    ∀ m, isCounterModule m = true → moduleInCoveredFragment m = true :=
  counterModel_fragmentAccepts_implies_covered_all

-- 10. A module containing a gap constructor is rejected by the coverage walk
-- (honesty: the fragment predicate excludes modules it cannot prove).
theorem gap_module_not_covered :
    moduleInCoveredFragment
      ({ name := "GapMod", structs := #[], state := #[],
         entrypoints := #[{ name := "bad", body := #[.effect (.storageArrayRead "a" (.literal (.u64 0)))] }] }
        : Module) = false := by
  native_decide

-- 11. FV-9.4+ capability-registry wire: the covered fragment uses only
-- covered capabilities. The canonical Counter module's capabilities are all
-- in `coveredCapabilities`, witnessed by `native_decide`.
#check (coveredCapabilities : Array ProofForge.Target.Capability)
#check (coveredFragment_implies_coveredCapabilities :
  capsAllCovered ProofForge.IR.Examples.Counter.module.capabilities = true)

theorem coveredFragment_uses_only_covered_capabilities :
    capsAllCovered ProofForge.IR.Examples.Counter.module.capabilities = true := by
  native_decide

-- 12. U5.1 / U5.3: Product modules vs covered fragment.
-- Counter / HostEnvProbe stay in fragment; RemoteCall (crosscall stub) is out.
theorem product_counter_in_covered_fragment :
    moduleInCoveredFragment Examples.Product.Counter.module = true := by
  native_decide

theorem product_hostEnvProbe_in_covered_fragment :
    moduleInCoveredFragment Examples.Product.HostEnvProbe.module = true := by
  native_decide

theorem product_ownable_in_covered_fragment :
    moduleInCoveredFragment Examples.Product.Ownable.module = true := by
  native_decide

theorem product_valueVault_in_covered_fragment :
    moduleInCoveredFragment Examples.Product.ValueVault.module = true := by
  native_decide

theorem product_remoteCall_out_of_covered_fragment :
    moduleInCoveredFragment Examples.Product.RemoteCall.module = false := by
  native_decide

theorem remote_crosscall_expr_is_gap :
    exprStatus (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[]) = .gap := by
  decide

-- 13. U5.2: boundedFor is fuel-covered; LoopProbe is in the covered fragment.
theorem boundedFor_statement_is_covered :
    fuelCoveredStatement (.boundedFor "_i" 0 3 #[]) = true := by
  decide

theorem whileLoop_statement_is_still_gap :
    fuelCoveredStatement (.whileLoop (.literal (.bool true)) #[]) = false := by
  decide

theorem loopProbe_in_covered_fragment :
    moduleInCoveredFragment ProofForge.IR.Examples.LoopProbe.module = true := by
  native_decide


def main : IO UInt32 := do
  -- Runtime re-check of U5 product map (native_decide theorems above).
  if !(moduleInCoveredFragment Examples.Product.Counter.module) then
    throw (IO.userError "Product Counter must be in covered fragment")
  if !(moduleInCoveredFragment Examples.Product.HostEnvProbe.module) then
    throw (IO.userError "Product HostEnvProbe must be in covered fragment")
  if moduleInCoveredFragment Examples.Product.RemoteCall.module then
    throw (IO.userError "Product RemoteCall must stay OUT of covered fragment (crosscall stub)")
  IO.println
    "constructor-coverage-smoke: FV-9.2/9.4 + U5 product map + U5.2 boundedFor (LoopProbe in; RemoteCall out)"
  return 0