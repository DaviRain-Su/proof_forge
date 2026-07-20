import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.AstSupportV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1

/-- Wire `Param`: visibility, raw Ident, Type. -/
structure ParamV1 where
  visibility : VisibilityV1
  name : SourceNameComponentV1
  type_ : TypeV1
  deriving DecidableEq, Repr

/-- Wire `FieldDecl`: raw Ident, Type. -/
structure FieldDeclV1 where
  name : SourceNameComponentV1
  type_ : TypeV1
  deriving DecidableEq, Repr

/-- Wire `EnumVariant`: raw Ident, Array Type (empty allowed). -/
structure EnumVariantV1 where
  name : SourceNameComponentV1
  payloadTypes : Array TypeV1
  deriving DecidableEq, Repr

end ProofForgeV2.Source.AstSupportV1
