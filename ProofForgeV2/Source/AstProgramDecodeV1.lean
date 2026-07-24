import ProofForgeV2.Source.AstProgramItemDecodeV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstProgramDecodeV1

open ProofForgeV2.Source.AstProgramItemDecodeV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α :=
  .error detail

private def decodeHead : DecoderV1 Unit := fun cursor => do
  let (tag, cursor) ← decodeTagV1 cursor
  unless tag == "Program" do
    return ← fail s!"unknown program tag '{tag}'"
  let ((), cursor) ← decodeFieldCountV1 tag 2 cursor
  pure ((), cursor)

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | remaining + 1 => pure { remainingNodes := remaining }

/-- Decode Program/2 while threading one caller-owned depth/node session through
    the Program parent and every source-order no-wrapper item. -/
def decodeProgramV1 : (depth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (ProgramV1 × DecodeBudgetV1)
  | 0, _budget => fun cursor => do
      let ((), _cursor) ← decodeHead cursor
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun cursor => do
      let ((), cursor) ← decodeHead cursor
      let budget ← chargeNode budget
      let (name, cursor) ← decodeSourceNameComponentV1 cursor
      let (countValue, cursor) ← decodeU32le cursor
      let count := countValue.toNat
      if count == 0 then
        return ← fail "program items must be nonempty"
      if count > budget.remainingNodes then
        return ← fail "array count exceeds caller limit"
      let mut items : Array ProgramItemV1 := #[]
      let mut budget := budget
      let mut cursor := cursor
      for _index in [:count] do
        let ((item, nextBudget), nextCursor) ←
          decodeProgramItemV1 remainingDepth budget cursor
        items := items.push item
        budget := nextBudget
        cursor := nextCursor
      pure (({ name, items }, budget), cursor)

end ProofForgeV2.Source.AstProgramDecodeV1
