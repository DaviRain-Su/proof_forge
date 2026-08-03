import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ProofBridgeV1

/-
  ProofForgeV2.Semantic.SimpleClosureCertV1 — production author semantic bridge
  for the Normalize simple-closure shape `invariant name : true`.

  Purpose: generalize the evaluator / theorem composition that tests previously
  hardcoded around a single Proofed carrier (ordinal, QN, byte spine) into
  parametric production theorems over any `ValidatedSemanticProgramV1`.

  The selected invariant must be exactly:
    nullary `.invariant` callable · single block · single Bool literal `true`
    instruction · `return (some 0)` · `invariantSteps = some 3`

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO
    * no second semantic model, residual encoder, or Tests / byte-spine hardcoding
    * no private validation field; sole wire validation is `carrier.hvalidate`
      from the private-ctor `ValidatedSemanticProgramV1`
    * does not auto-claim arbitrary invariants true — every table lookup, shape
      equality, and canonical Bool-true premise is explicit on the witness
-/

namespace ProofForgeV2.Semantic.SimpleClosureCertV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1

/-- Explicit production shape witness for a nullary literal-`true` invariant.

    Every field is a production-table lookup or structure equality. There is no
    validation field: authors still obtain wire validation only from a
    `ValidatedSemanticProgramV1` carrier. `rootName` / `visibility` / `typeName`
    are free parameters so the theorem applies under any program identity /
    surrounding callables / state tables as long as the selected invariant body
    is exactly the literal-true micro-shape. -/
structure LiteralTrueInvariantWitnessV1
    (data : SemanticProgramDataV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String) : Prop where
  /-- Ordinal selects this invariant declaration row. -/
  hselection : data.invariants[invariantOrdinal.toNat]? = some invariant
  /-- Bool type id resolves to an anonymous-or-named Bool type. -/
  htype : data.types[boolTypeId.toNat]? = some {
    id := boolTypeId, name := typeName, shape := .bool }
  /-- Root callable is the exact nullary literal-true invariant micro-shape. -/
  hroot : data.callables[invariant.callableId.toNat]? = some {
    id := invariant.callableId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .literal boolTypeId (encodeU8 1)
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := some 3
  }
  /-- Canonical Bool-true valueBytes under the production type table. -/
  hcanonical :
    validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ()

/-- Ordinal is in-range once the selection premise holds. -/
theorem lt_invariants_size_of_literalTrueWitness
    (data : SemanticProgramDataV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (w : LiteralTrueInvariantWitnessV1 data invariantOrdinal invariant
      boolTypeId rootName visibility typeName) :
    invariantOrdinal.toNat < data.invariants.size :=
  (Array.getElem?_eq_some_iff.mp w.hselection).1

/-- Evaluator half: any conforming state returns `.returnedTrue` for a
    witnessed literal-true simple-closure invariant on a validated carrier. -/
theorem evalInvariantV1_eq_returnedTrue_of_literalTrueWitness
    (carrier : ValidatedSemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (w : LiteralTrueInvariantWitnessV1 carrier.data invariantOrdinal invariant
      boolTypeId rootName visibility typeName)
    (state : LogicalStateV1)
    (hconforms : StateConformsV1 carrier.program state) :
    evalInvariantV1 carrier.program invariantOrdinal state = .returnedTrue := by
  obtain ⟨hinitialized, overlay, hdecodeState⟩ :=
    stateConformsV1_elim_of_validate_eq_ok
      carrier.program carrier.data state carrier.hvalidate hconforms
  have hrun :
      runInvariantCallableV1 carrier.data invariant.callableId state =
        .returnedTrue := by
    exact runInvariantCallableV1_eq_returnedTrue_of_single_nullary_literal_true
      carrier.data state overlay invariant.callableId boolTypeId rootName
      visibility typeName hinitialized hdecodeState w.htype w.hroot w.hcanonical
  exact evalInvariantV1_eq_of_validated_selection
    carrier.program carrier.data invariantOrdinal invariant state overlay
    .returnedTrue carrier.hvalidate hinitialized hdecodeState w.hselection hrun

/-- Close `InvariantTheoremV1` from a proof-carrying validated carrier and an
    explicit literal-true simple-closure witness. Reuses
    `invariantTheoremV1_of_validated`; does not invent wire validation. -/
theorem invariantTheoremV1_of_literalTrueWitness
    (carrier : ValidatedSemanticProgramV1)
    (invariantOrdinal : InvariantOrdinalV1)
    (invariant : InvariantDeclV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (w : LiteralTrueInvariantWitnessV1 carrier.data invariantOrdinal invariant
      boolTypeId rootName visibility typeName) :
    InvariantTheoremV1 carrier.program invariantOrdinal := by
  apply invariantTheoremV1_of_validated carrier invariantOrdinal
  · exact lt_invariants_size_of_literalTrueWitness carrier.data invariantOrdinal
      invariant boolTypeId rootName visibility typeName w
  · intro state hconforms
    exact evalInvariantV1_eq_returnedTrue_of_literalTrueWitness
      carrier invariantOrdinal invariant boolTypeId rootName visibility typeName
      w state hconforms

end ProofForgeV2.Semantic.SimpleClosureCertV1
