import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.AstDeclV1

open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

structure StateDeclV1 where
  visibility : VisibilityV1
  name : SourceNameComponentV1
  type_ : TypeV1
  deriving DecidableEq, Repr

structure StructDeclV1 where
  name : SourceNameComponentV1
  fields : Array FieldDeclV1
  deriving DecidableEq, Repr

structure EnumDeclV1 where
  name : SourceNameComponentV1
  variants : Array EnumVariantV1
  deriving DecidableEq, Repr

structure EventDeclV1 where
  name : SourceNameComponentV1
  params : Array ParamV1
  deriving DecidableEq, Repr

structure ErrorDeclV1 where
  name : SourceNameComponentV1
  params : Array ParamV1
  deriving DecidableEq, Repr

structure ExtensionReqV1 where
  id : SourceQualifiedNameV1
  version : String
  digest : String
  deriving DecidableEq, Repr

structure ProofDeclV1 where
  invariant : SourceNameComponentV1
  theorem_ : SourceQualifiedNameV1
  deriving DecidableEq, Repr

end ProofForgeV2.Source.AstDeclV1
