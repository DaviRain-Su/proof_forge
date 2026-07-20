import Init.Meta
import ProofForgeV2.Core.Common
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.QualifiedNameV1

open Lean
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.NameComponentV1

/-- Source-only ordered raw name components (1..256). Not common `QualifiedName`. -/
structure SourceQualifiedNameV1 where
  private mk ::
  components : NonEmptyArray SourceNameComponentV1
  deriving DecidableEq, Repr

private def fail (detail : String) : Except String α :=
  .error detail

private def qnCountError : String :=
  "source qualified name must contain 1..256 components"

private def qidCountError : String :=
  "source qualified id must contain 2..256 components"

def sourceQualifiedNameV1OfComponents (components : Array SourceNameComponentV1) :
    Except String SourceQualifiedNameV1 := do
  unless 1 ≤ components.size && components.size ≤ 256 do
    return ← fail qnCountError
  let nonempty ← NonEmptyArray.ofArray components
  pure ⟨nonempty⟩

def parseSourceQualifiedNameV1 (raws : Array String) :
    Except String SourceQualifiedNameV1 := do
  unless 1 ≤ raws.size && raws.size ≤ 256 do
    return ← fail qnCountError
  let mut components : Array SourceNameComponentV1 := #[]
  for raw in raws do
    components := components.push (← parseSourceNameComponentV1 raw)
  sourceQualifiedNameV1OfComponents components

/-- Pure `.str` chain ending at `.anonymous`, root-to-leaf raw order. -/
private def collectPureStrChain (name : Name) (remaining : Nat) :
    Except String (Array String) :=
  match name with
  | .anonymous => pure #[]
  | .str pre value => do
      if remaining == 0 then
        return ← fail qnCountError
      let preRaws ← collectPureStrChain pre (remaining - 1)
      pure (preRaws.push value)
  | .num _ _ => fail "source qualified name requires a pure .str Lean name chain"

def sourceQualifiedNameV1FromLeanName (name : Name) :
    Except String SourceQualifiedNameV1 := do
  let raws ← collectPureStrChain name 256
  parseSourceQualifiedNameV1 raws

def validateSourceQualifiedIdV1 (name : SourceQualifiedNameV1) : Except String Unit := do
  let size := (NonEmptyArray.toArray name.components).size
  unless 2 ≤ size && size ≤ 256 do
    return ← fail qidCountError

def validateSourceProgramIdentityV1
    (moduleName programIdentity : SourceQualifiedNameV1) : Except String Unit := do
  validateSourceQualifiedIdV1 programIdentity
  let moduleComps := NonEmptyArray.toArray moduleName.components
  let programComps := NonEmptyArray.toArray programIdentity.components
  unless programComps.size > moduleComps.size do
    return ← fail "program identity must strictly extend the module name"
  let mut i := 0
  while i < moduleComps.size do
    match moduleComps[i]?, programComps[i]? with
    | some m, some p =>
        unless m == p do
          return ← fail "program identity must begin with the exact module name components"
    | _, _ =>
        return ← fail "program identity must begin with the exact module name components"
    i := i + 1

end ProofForgeV2.Source.QualifiedNameV1
