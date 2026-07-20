import ProofForgeV2.Source.AstProgramItemCodecV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstProgramCodecV1

open ProofForgeV2.Source.AstProgramItemCodecV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireCodecV1

private def fail (detail : String) : Except String α :=
  .error detail

private def itemsEmptyErr := "program items must be nonempty"

def encodeProgramV1 (p : ProgramV1) : Except String ByteArray := do
  unless p.items.size ≥ 1 do
    return ← fail itemsEmptyErr
  let nameB ← encodeSourceNameComponentV1 p.name
  let itemsB ← encodeArray encodeProgramItemV1 p.items
  encodeTagged "Program" #[nameB, itemsB]

end ProofForgeV2.Source.AstProgramCodecV1
