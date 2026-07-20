import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstScalarDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstPatternDecodeV1

open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstScalarDecodeV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α := .error detail

/-- Closed Pattern tag table. Dispatch is completed before field-count decoding. -/
private def expectedFieldCount (tag : String) : Except String Nat :=
  match tag with
  | "Pattern.Wildcard" => pure 0
  | "Pattern.Bind" | "Pattern.Literal" => pure 1
  | "Pattern.Constructor" => pure 2
  | _ => fail s!"unknown pattern tag '{tag}'"

private def decodeHead : DecoderV1 String := fun c => do
  let (tag, c) ← decodeTagV1 c
  let expected ← expectedFieldCount tag
  let ((), c) ← decodeFieldCountV1 tag expected c
  pure (tag, c)

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | n + 1 => pure { remainingNodes := n }

/-- Kernel-total recursive Pattern decoder. Constructor QID precedes the bounded
    args count; siblings share child depth and thread session node residual. -/
def decodePatternV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (PatternV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let (_tag, _c) ← decodeHead c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let (tag, c) ← decodeHead c
      let budget ← chargeNode budget
      match tag with
      | "Pattern.Wildcard" => pure ((.wildcard, budget), c)
      | "Pattern.Bind" => do
          let (name, c) ← decodeSourceNameComponentV1 c
          pure ((.bind name, budget), c)
      | "Pattern.Literal" => do
          let (value, c) ← decodeLiteralV1 c
          pure ((.literal value, budget), c)
      | "Pattern.Constructor" => do
          let (ctor, c) ← decodeSourceQualifiedIdV1 c
          let (countU, c) ← decodeU32le c
          let count := countU.toNat
          if count > budget.remainingNodes then
            return ← fail "array count exceeds caller limit"
          let mut args : Array PatternV1 := Array.empty
          let mut budget := budget
          let mut c := c
          for _ in [:count] do
            let ((arg, nextBudget), nextCursor) ←
              decodePatternV1 remainingDepth budget c
            args := args.push arg
            budget := nextBudget
            c := nextCursor
          pure ((.constructor ctor args, budget), c)
      | _ => fail "unreachable closed pattern dispatch"

end ProofForgeV2.Source.AstPatternDecodeV1
