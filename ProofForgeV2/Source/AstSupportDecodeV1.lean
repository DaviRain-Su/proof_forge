import ProofForgeV2.Source.AstScalarDecodeV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstTypeDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstSupportDecodeV1

open ProofForgeV2.Source.AstScalarDecodeV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstTypeDecodeV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α := .error detail

private def decodeHead (expected : String) (fieldCount : Nat) (family : String) :
    DecoderV1 Unit := fun c => do
  let (tag, c) ← decodeTagV1 c
  unless tag == expected do
    return ← fail s!"unknown {family} tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag fieldCount c
  pure ((), c)

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | remaining + 1 => pure { remainingNodes := remaining }

/-- Decode node-bearing `Param`: Visibility, Ident, then Type. -/
def decodeParamV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ParamV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "Param" 3 "param" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "Param" 3 "param" c
      let budget ← chargeNode budget
      let (visibility, c) ← decodeVisibilityV1 c
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((type_, budget), c) ← decodeTypeV1 remainingDepth budget c
      pure (({ visibility, name, type_ }, budget), c)

/-- Decode node-bearing `FieldDecl`: Ident, then Type. -/
def decodeFieldDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (FieldDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "FieldDecl" 2 "field-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "FieldDecl" 2 "field-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((type_, budget), c) ← decodeTypeV1 remainingDepth budget c
      pure (({ name, type_ }, budget), c)

/-- Decode node-bearing `EnumVariant`: Ident, bounded count, then Type children. -/
def decodeEnumVariantV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (EnumVariantV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "EnumVariant" 2 "enum-variant" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "EnumVariant" 2 "enum-variant" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let (countU, c) ← decodeU32le c
      let count := countU.toNat
      if count > budget.remainingNodes then
        return ← fail "array count exceeds caller limit"
      let mut payloadTypes := Array.empty
      let mut budget := budget
      let mut c := c
      for _ in [:count] do
        let ((type_, nextBudget), nextCursor) ←
          decodeTypeV1 remainingDepth budget c
        payloadTypes := payloadTypes.push type_
        budget := nextBudget
        c := nextCursor
      pure (({ name, payloadTypes }, budget), c)

end ProofForgeV2.Source.AstSupportDecodeV1
