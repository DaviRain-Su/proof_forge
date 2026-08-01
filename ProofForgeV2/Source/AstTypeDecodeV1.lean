import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstTypeDecodeV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α :=
  .error detail

private def allowedWidth (width : UInt16) : Bool :=
  width == 8 || width == 16 || width == 32 ||
  width == 64 || width == 128 || width == 256

private def requireWidth (width : UInt16) : Except String Unit := do
  unless allowedWidth width do
    return ← fail "integer width must be one of 8,16,32,64,128,256"

private def requireLen (kind : String) (length : UInt32) : Except String Unit := do
  unless length.toNat ≤ 4096 do
    return ← fail s!"{kind} length must be 0..4096"

/-- Closed 11-tag field counts; unknown before any fieldCount read. -/
private def expectedFieldCount (tag : String) : Except String Nat :=
  match tag with
  | "Type.Bool" | "Type.Principal" | "Type.Unit" | "Type.String" => pure 0
  | "Type.UInt" | "Type.Int" | "Type.Named" | "Type.Option" |
      "Type.Bytes" | "Type.Field" => pure 1
  | "Type.Array" | "Type.Map" => pure 2
  | _ => fail s!"unknown type tag '{tag}'"

/-- Tag → closed dispatch → exact fieldCount (before depth/node/body). -/
private def decodeHead : DecoderV1 String := fun c => do
  let (tag, c) ← decodeTagV1 c
  let expected ← expectedFieldCount tag
  let ((), c) ← decodeFieldCountV1 tag expected c
  pure (tag, c)

private def chargeNode (budget : DecodeBudgetV1) : Except String DecodeBudgetV1 :=
  match budget.remainingNodes with
  | 0 => fail "node budget exhausted"
  | remaining + 1 => pure { remainingNodes := remaining }

/-- Kernel-total recursive Type decoder. Fuel is `remainingDepth` (structural Nat).
    Priority: tag → unknown → fieldCount → depth → node → ordered fields.
    No Type-root helper that mints 256/100000; caller supplies both parameters. -/
def decodeTypeV1 : (remainingDepth : Nat) → (budget : DecodeBudgetV1) →
    DecoderV1 (TypeV1 × DecodeBudgetV1)
  | 0, _budget => fun c => do
      let (_tag, _c) ← decodeHead c
      fail "depth budget exhausted"
  | remainingDepth + 1, budget => fun c => do
      let (tag, c) ← decodeHead c
      let budget ← chargeNode budget
      match tag with
      | "Type.Bool" => pure ((TypeV1.bool, budget), c)
      | "Type.Principal" => pure ((TypeV1.principal, budget), c)
      | "Type.Unit" => pure ((TypeV1.unit, budget), c)
      | "Type.String" => pure ((TypeV1.string, budget), c)
      | "Type.UInt" => do
          let (width, c) ← decodeU16le c
          requireWidth width
          pure ((TypeV1.uint width, budget), c)
      | "Type.Int" => do
          let (width, c) ← decodeU16le c
          requireWidth width
          pure ((TypeV1.int width, budget), c)
      | "Type.Named" => do
          let (name, c) ← decodeSourceNameComponentV1 c
          pure ((TypeV1.named name, budget), c)
      | "Type.Bytes" => do
          let (length, c) ← decodeU32le c
          requireLen "bytes" length
          pure ((TypeV1.bytes length, budget), c)
      | "Type.Field" => do
          let (id, c) ← decodeSourceNameComponentV1 c
          unless id.raw == "bn254_fr" do
            return ← fail "field id must be bn254_fr"
          pure ((TypeV1.field id, budget), c)
      | "Type.Option" => do
          let ((element, budget), c) ← decodeTypeV1 remainingDepth budget c
          pure ((TypeV1.option element, budget), c)
      | "Type.Array" => do
          let ((element, budget), c) ← decodeTypeV1 remainingDepth budget c
          let (length, c) ← decodeU32le c
          requireLen "array" length
          pure ((TypeV1.array element length, budget), c)
      | "Type.Map" => do
          -- siblings share remainingDepth; value gets key's residual nodes
          let ((key, budget), c) ← decodeTypeV1 remainingDepth budget c
          let ((value, budget), c) ← decodeTypeV1 remainingDepth budget c
          pure ((TypeV1.map key value, budget), c)
      | _ => fail "unreachable closed type dispatch"

end ProofForgeV2.Source.AstTypeDecodeV1
