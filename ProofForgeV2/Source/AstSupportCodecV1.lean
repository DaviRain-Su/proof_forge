import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstSupportCodecV1

open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireCodecV1

/-- Encode `Param` (fieldCount 3): Visibility ‖ Ident ‖ Type. -/
def encodeParamV1 (p : ParamV1) : Except String ByteArray := do
  let vis ← encodeVisibilityV1 p.visibility
  let name ← encodeSourceNameComponentV1 p.name
  let ty ← encodeTypeV1 p.type_
  encodeTagged "Param" #[vis, name, ty]

/-- Encode `FieldDecl` (fieldCount 2): Ident ‖ Type. -/
def encodeFieldDeclV1 (f : FieldDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 f.name
  let ty ← encodeTypeV1 f.type_
  encodeTagged "FieldDecl" #[name, ty]

/-- Encode `EnumVariant` (fieldCount 2): Ident ‖ Array Type (empty allowed). -/
def encodeEnumVariantV1 (v : EnumVariantV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 v.name
  let payloads ← encodeArray encodeTypeV1 v.payloadTypes
  encodeTagged "EnumVariant" #[name, payloads]

end ProofForgeV2.Source.AstSupportCodecV1
