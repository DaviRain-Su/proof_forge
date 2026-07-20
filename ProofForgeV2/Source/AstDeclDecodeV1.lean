import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstScalarDecodeV1
import ProofForgeV2.Source.AstSupportDecodeV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstTypeDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstDeclDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstScalarDecodeV1
open ProofForgeV2.Source.AstSupportDecodeV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstTypeDecodeV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α :=
  .error detail

private def verErr := "extension version must use canonical exact SemVer"
private def digErr := "extension digest must use canonical sha256 spelling"
private def structEmptyErr := "struct fields must be nonempty"
private def enumEmptyErr := "enum variants must be nonempty"

/-- Singleton closed head: tag → exact expected → fieldCount (before depth/node). -/
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

private def requireCanonicalExtensionVersion (version : String) : Except String Unit :=
  match parseSemVer version with
  | .error _ => fail verErr
  | .ok parsed =>
    match renderSemVer parsed with
    | .error _ => fail verErr
    | .ok canonical =>
        unless canonical == version do
          return ← fail verErr

private def requireCanonicalExtensionDigest (digest : String) : Except String Unit :=
  match parseDigest digest with
  | .error _ => fail digErr
  | .ok parsed =>
    match renderDigest parsed with
    | .error _ => fail digErr
    | .ok canonical =>
        unless canonical == digest do
          return ← fail digErr

/-- Decode node-bearing `StateDecl`: Visibility → Ident → Type. -/
def decodeStateDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (StateDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "StateDecl" 3 "state-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "StateDecl" 3 "state-decl" c
      let budget ← chargeNode budget
      let (visibility, c) ← decodeVisibilityV1 c
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((type_, budget), c) ← decodeTypeV1 remainingDepth budget c
      pure (({ visibility, name, type_ }, budget), c)

/-- Decode node-bearing `StructDecl`: Ident → nonempty FieldDecl array. -/
def decodeStructDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (StructDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "StructDecl" 2 "struct-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "StructDecl" 2 "struct-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let (countU, c) ← decodeU32le c
      let count := countU.toNat
      if count == 0 then
        return ← fail structEmptyErr
      if count > budget.remainingNodes then
        return ← fail "array count exceeds caller limit"
      let mut fields := Array.empty
      let mut budget := budget
      let mut c := c
      for _ in [:count] do
        let ((field, nextBudget), nextCursor) ←
          decodeFieldDeclV1 remainingDepth budget c
        fields := fields.push field
        budget := nextBudget
        c := nextCursor
      pure (({ name, fields }, budget), c)

/-- Decode node-bearing `EnumDecl`: Ident → nonempty EnumVariant array. -/
def decodeEnumDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (EnumDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "EnumDecl" 2 "enum-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "EnumDecl" 2 "enum-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let (countU, c) ← decodeU32le c
      let count := countU.toNat
      if count == 0 then
        return ← fail enumEmptyErr
      if count > budget.remainingNodes then
        return ← fail "array count exceeds caller limit"
      let mut variants := Array.empty
      let mut budget := budget
      let mut c := c
      for _ in [:count] do
        let ((variant, nextBudget), nextCursor) ←
          decodeEnumVariantV1 remainingDepth budget c
        variants := variants.push variant
        budget := nextBudget
        c := nextCursor
      pure (({ name, variants }, budget), c)

private def decodeParamArray (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    DecoderV1 (Array ParamV1 × DecodeBudgetV1) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > budget.remainingNodes then
    return ← fail "array count exceeds caller limit"
  let mut params := Array.empty
  let mut budget := budget
  let mut c := c
  for _ in [:count] do
    let ((param, nextBudget), nextCursor) ←
      decodeParamV1 remainingDepth budget c
    params := params.push param
    budget := nextBudget
    c := nextCursor
  pure ((params, budget), c)

/-- Decode node-bearing `EventDecl`: Ident → Param array (empty allowed). -/
def decodeEventDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (EventDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "EventDecl" 2 "event-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "EventDecl" 2 "event-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((params, budget), c) ← decodeParamArray remainingDepth budget c
      pure (({ name, params }, budget), c)

/-- Decode node-bearing `ErrorDecl`: Ident → Param array (empty allowed). -/
def decodeErrorDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ErrorDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "ErrorDecl" 2 "error-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "ErrorDecl" 2 "error-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((params, budget), c) ← decodeParamArray remainingDepth budget c
      pure (({ name, params }, budget), c)

/-- Decode node-bearing `ExtensionReq`: QID → version → digest (Common canonical). -/
def decodeExtensionReqV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ExtensionReqV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "ExtensionReq" 3 "extension-req" c
      fail "depth budget exhausted"
  | _remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "ExtensionReq" 3 "extension-req" c
      let budget ← chargeNode budget
      let (id, c) ← decodeSourceQualifiedIdV1 c
      let (version, c) ← decodeString c
      requireCanonicalExtensionVersion version
      let (digest, c) ← decodeString c
      requireCanonicalExtensionDigest digest
      pure (({ id, version, digest }, budget), c)

/-- Decode node-bearing `ProofDecl`: invariant Ident → theorem QID. -/
def decodeProofDeclV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ProofDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← decodeHead "ProofDecl" 2 "proof-decl" c
      fail "depth budget exhausted"
  | _remainingDepth + 1, budget => fun c => do
      let ((), c) ← decodeHead "ProofDecl" 2 "proof-decl" c
      let budget ← chargeNode budget
      let (invariant, c) ← decodeSourceNameComponentV1 c
      let (theorem_, c) ← decodeSourceQualifiedIdV1 c
      pure (({ invariant, theorem_ }, budget), c)

end ProofForgeV2.Source.AstDeclDecodeV1
