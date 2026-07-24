import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstPatternCodecV1

open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.WireCodecV1

mutual
  /-- Kernel-total Pattern encode: QID before args; child chunks then `encodeArray pure`. -/
  def encodePatternV1 : PatternV1 → Except String ByteArray
    | .wildcard => encodeTagged "Pattern.Wildcard" #[]
    | .bind name => do
        let payload ← encodeSourceNameComponentV1 name
        encodeTagged "Pattern.Bind" #[payload]
    | .literal value => do
        let payload ← encodeLiteralV1 value
        encodeTagged "Pattern.Literal" #[payload]
    | .constructor ctor args => do
        let ctorBytes ← encodeSourceQualifiedIdV1 ctor
        let chunks ← encodePatternArrayV1 args
        let argsBytes ← encodeArray pure chunks
        encodeTagged "Pattern.Constructor" #[ctorBytes, argsBytes]
    termination_by structural pattern => pattern

  private def encodePatternArrayV1 : Array PatternV1 → Except String (Array ByteArray)
    | ⟨patterns⟩ => encodePatternListV1 patterns #[]
    termination_by structural patterns => patterns

  private def encodePatternListV1 :
      List PatternV1 → Array ByteArray → Except String (Array ByteArray)
    | [], chunks => pure chunks
    | pattern :: patterns, chunks => do
        let chunk ← encodePatternV1 pattern
        encodePatternListV1 patterns (chunks.push chunk)
    termination_by structural patterns => patterns
end

end ProofForgeV2.Source.AstPatternCodecV1
