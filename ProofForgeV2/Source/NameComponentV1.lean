import Init.Meta
import ProofForgeV2.Core.Unicode

namespace ProofForgeV2.Source.NameComponentV1

open Lean
open ProofForgeV2.Core.Unicode

/-- Raw Lean `Name.str` payload carrier (source wire Ident). Not rendered spelling. -/
structure SourceNameComponentV1 where
  private mk ::
  raw : String
  deriving DecidableEq, Repr

private def fail (detail : String) : Except String α :=
  .error detail

/-- Validate and construct from a raw `Name.str` payload string. -/
def parseSourceNameComponentV1 (raw : String) : Except String SourceNameComponentV1 := do
  let utf8 := raw.toUTF8
  unless 1 ≤ utf8.size && utf8.size ≤ 240 do
    return ← fail "source name component must contain 1..240 UTF-8 bytes"
  requireNfc raw
  for c in raw.toList do
    if isUnicodeCc c then
      return ← fail "source name component must not contain a Cc code point"
    if c.val == 0x00BB then
      return ← fail "source name component must not contain closing guillemet"
  pure ⟨raw⟩

/-- Accept only a final `.str` Lean name; payload reuses `parseSourceNameComponentV1`. -/
def sourceNameComponentV1FromLeanName (name : Name) : Except String SourceNameComponentV1 :=
  match name with
  | .str _ value => parseSourceNameComponentV1 value
  | _ => fail "source name component requires a final .str Lean name"

/-- Diagnostic/export render only — never enters wire/hash identity. -/
def renderSourceNameComponentV1 (component : SourceNameComponentV1) : String :=
  (Name.str .anonymous component.raw).toString

end ProofForgeV2.Source.NameComponentV1
