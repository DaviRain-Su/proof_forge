import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineDecodeV1
import ProofForgeV2.Source.AstSpineStmtDecodeV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportDecodeV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstTypeDecodeV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstSpineDeclDecodeV1

open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineDecodeV1
open ProofForgeV2.Source.AstSpineStmtDecodeV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportDecodeV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstTypeDecodeV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α := .error detail

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | n + 1 => pure { remainingNodes := n }

/-- Closed singleton head: exact tag, exact fieldCount, then parent node charge.
    Unknown fails before fieldCount; depth and node fail after head parses. -/
private def singletonHead (expected : String) (fieldCount : Nat) (family : String) :
    DecoderV1 Unit := fun c => do
  let (tag, c) ← decodeTagV1 c
  unless tag == expected do
    return ← fail s!"unknown {family} tag '{tag}'"
  let ((), c) ← decodeFieldCountV1 tag fieldCount c
  pure ((), c)

/-- Non-SCC Param array. Cap vs residual after parent charge; siblings thread residual. -/
private def decodeParamArray (d : Nat) (budget : DecodeBudgetV1) :
    DecoderV1 (Array ParamV1 × DecodeBudgetV1) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > budget.remainingNodes then
    return ← fail "array count exceeds caller limit"
  let mut params : Array ParamV1 := #[]
  let mut budget := budget
  let mut c := c
  for _ in [:count] do
    let ((param, nextBudget), nextCursor) ← decodeParamV1 d budget c
    params := params.push param
    budget := nextBudget
    c := nextCursor
  pure ((params, budget), c)

/-! Six spine-dependent declaration decoders. Each is non-mutual because all
    child decoders (Type, Expr, Param array, Block) already close in earlier
    modules. Each def total-matches on `d`; priority is
    tag → unknown → fieldCount → depth → parent node charge → wire-order fields.
    Parent node is charged exactly once per decl; children receive `d-1` and
    the charged budget. Siblings thread the same residual left-to-right. -/

def decodeConstDeclV1 : (d : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ConstDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← singletonHead "ConstDecl" 3 "const-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← singletonHead "ConstDecl" 3 "const-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((type_, budget), c) ← decodeTypeV1 remainingDepth budget c
      let ((value, budget), c) ← decodeExprV1 remainingDepth budget c
      pure (({ name, type_, value }, budget), c)

def decodeInvariantDeclV1 : (d : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (InvariantDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← singletonHead "InvariantDecl" 2 "invariant-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← singletonHead "InvariantDecl" 2 "invariant-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((predicate, budget), c) ← decodeExprV1 remainingDepth budget c
      pure (({ name, predicate }, budget), c)

def decodeInitDeclV1 : (d : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (InitDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← singletonHead "InitDecl" 2 "init-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← singletonHead "InitDecl" 2 "init-decl" c
      let budget ← chargeNode budget
      let ((params, budget), c) ← decodeParamArray remainingDepth budget c
      let ((body, budget), c) ← decodeBlockV1 remainingDepth budget c
      pure (({ params, body }, budget), c)

def decodeEntryDeclV1 : (d : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (EntryDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← singletonHead "EntryDecl" 4 "entry-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← singletonHead "EntryDecl" 4 "entry-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((params, budget), c) ← decodeParamArray remainingDepth budget c
      let ((result, budget), c) ← decodeTypeV1 remainingDepth budget c
      let ((body, budget), c) ← decodeBlockV1 remainingDepth budget c
      pure (({ name, params, result, body }, budget), c)

def decodeViewDeclV1 : (d : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ViewDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← singletonHead "ViewDecl" 4 "view-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← singletonHead "ViewDecl" 4 "view-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((params, budget), c) ← decodeParamArray remainingDepth budget c
      let ((result, budget), c) ← decodeTypeV1 remainingDepth budget c
      let ((body, budget), c) ← decodeBlockV1 remainingDepth budget c
      pure (({ name, params, result, body }, budget), c)

def decodeFnDeclV1 : (d : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (FnDeclV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let ((), _c) ← singletonHead "FnDecl" 4 "fn-decl" c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let ((), c) ← singletonHead "FnDecl" 4 "fn-decl" c
      let budget ← chargeNode budget
      let (name, c) ← decodeSourceNameComponentV1 c
      let ((params, budget), c) ← decodeParamArray remainingDepth budget c
      let ((result, budget), c) ← decodeTypeV1 remainingDepth budget c
      let ((body, budget), c) ← decodeBlockV1 remainingDepth budget c
      pure (({ name, params, result, body }, budget), c)

end ProofForgeV2.Source.AstSpineDeclDecodeV1