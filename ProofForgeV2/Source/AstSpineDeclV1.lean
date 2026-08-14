import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstSpineEqV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.AstSpineDeclV1

open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1

structure ConstDeclV1 where
  name : SourceNameComponentV1
  type_ : TypeV1
  value : ExprV1
  deriving DecidableEq, Repr, Lean.ToExpr

structure InvariantDeclV1 where
  name : SourceNameComponentV1
  predicate : ExprV1
  deriving DecidableEq, Repr, Lean.ToExpr

structure InitDeclV1 where
  params : Array ParamV1
  body : BlockV1
  deriving DecidableEq, Repr, Lean.ToExpr

structure EntryDeclV1 where
  name : SourceNameComponentV1
  params : Array ParamV1
  result : TypeV1
  body : BlockV1
  deriving DecidableEq, Repr, Lean.ToExpr

structure ViewDeclV1 where
  name : SourceNameComponentV1
  params : Array ParamV1
  result : TypeV1
  body : BlockV1
  deriving DecidableEq, Repr, Lean.ToExpr

structure FnDeclV1 where
  name : SourceNameComponentV1
  params : Array ParamV1
  result : TypeV1
  body : BlockV1
  deriving DecidableEq, Repr, Lean.ToExpr

end ProofForgeV2.Source.AstSpineDeclV1
