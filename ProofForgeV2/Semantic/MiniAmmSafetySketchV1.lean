import ProofForgeV2.Semantic.WireV1

/-!
  ProofForgeV2.Semantic.MiniAmmSafetySketchV1 — **first L1 program instance**.

  Platform formalization ladder: RESEARCH-023.
  * **Generic**: `Preserves` shape (init + step keeps P) is the reusable pattern.
  * **This module**: MiniAmm-specific `State` / `Effect` / predicates P1… only.
  * A later non-AMM instance must reuse the *shape*, not these predicates.

  This module:

  * does **not** encode/decode product `SemanticProgramV1`;
  * does **not** close `InvariantTheoremV1` for MiniAmm carriers;
  * does **not** claim Reference `step` preservation is implemented;
  * does **not** define the only allowed safety theory in the product.

  Engineering only — not formal TASK-D2-07 / TST-SEM-002/003.
-/

namespace ProofForgeV2.Semantic.MiniAmmSafetySketchV1

open ProofForgeV2.Semantic.WireV1

/-- Vault-internal MiniAmm abstract state (product fields, no Map payload yet).
    LP map is deferred to a later slice (P2). -/
structure MiniAmmState where
  reserve0 : UInt64
  reserve1 : UInt64
  totalSupply : UInt64
  deriving BEq, Repr, Inhabited

/-- Product init zeros (matches Examples/MiniAmm init). -/
def initialMiniAmmState : MiniAmmState :=
  { reserve0 := 0, reserve1 := 0, totalSupply := 0 }

/-! ### Business predicates (P1…; not yet proved under product step) -/

/-- P1 — empty pool consistency: zero supply implies zero reserves. -/
def P1_emptyPool (s : MiniAmmState) : Prop :=
  s.totalSupply = 0 → s.reserve0 = 0 ∧ s.reserve1 = 0

/-- P3 sketch — reserves never "negative" in UInt64 model (always true as UInt).
    Placeholder for checked-sub postconditions on remove/swap. -/
def P3_reservesWellFormed (_s : MiniAmmState) : Prop :=
  True

/-- P4 sketch — fee-free constant-product inequality after a successful swap0to1.
    Stated relationally; not tied to a product entry yet. -/
def P4_swap0to1_product
    (s s' : MiniAmmState) (amountIn amountOut : UInt64) : Prop :=
  s'.reserve0 = s.reserve0 + amountIn ∧
  s'.reserve1 + amountOut = s.reserve1 ∧
  -- Integer product may overflow UInt64; later slices must use wider math or
  -- an explicit checked-mul model. Here we only name the *intent*.
  True

/-! ### Preservation interface (L1 target shape) -/

/-- Abstract effect labels for vault-internal MiniAmm (no pf.assets). -/
inductive MiniAmmEffect where
  | init
  | addLiquidity (amount0 amount1 : UInt64)
  | swap0to1 (amountIn amountOutMin : UInt64)
  | swap1to0 (amountIn amountOutMin : UInt64)
  | removeLiquidity (lpAmount : UInt64)
  deriving BEq, Repr

/-- Placeholder step relation. A later slice must define this as the
    Reference/Normalize-aligned transition (or prove equivalence to it).
    Until then, no theorem may treat this as executable semantics. -/
opaque miniAmmStep (s : MiniAmmState) (e : MiniAmmEffect) : Option MiniAmmState

/-- L1 preservation goal for a state predicate `P`. -/
def PreservesMiniAmm (P : MiniAmmState → Prop) : Prop :=
  P initialMiniAmmState ∧
  ∀ (s : MiniAmmState) (e : MiniAmmEffect) (s' : MiniAmmState),
    miniAmmStep s e = some s' → P s → P s'

/-- Named goal: empty-pool consistency is preserved by abstract steps. -/
def PreservesP1_emptyPool : Prop :=
  PreservesMiniAmm P1_emptyPool

/-- Init discharges P1 (small, total; does not use `miniAmmStep`). -/
theorem P1_emptyPool_initial : P1_emptyPool initialMiniAmmState := by
  intro h
  exact ⟨rfl, rfl⟩

/-- Package the init half of `PreservesP1` without claiming step closure. -/
theorem PreservesP1_emptyPool_init_half :
    P1_emptyPool initialMiniAmmState :=
  P1_emptyPool_initial

/-!
  ## Explicit open obligations (do not forge)

  | ID | Obligation |
  |---|---|
  | O-STEP | Define `miniAmmStep` from product Semantic/Reference (or prove eq) |
  | O-P1-STEP | `PreservesP1_emptyPool` full (init already closed above) |
  | O-P2 | LP map sum = totalSupply |
  | O-P4 | Checked product inequality under UInt64 / wide model |
  | O-JOIN | Product `invariant` eval ⇔ abstract `P` on decoded state |
  | O-MAT | Materializer nonempty-invariant policy (separate epic) |
-/

end ProofForgeV2.Semantic.MiniAmmSafetySketchV1
