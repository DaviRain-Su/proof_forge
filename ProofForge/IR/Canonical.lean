import ProofForge.IR.Core
import ProofForge.IR.Core.Validate
import ProofForge.Target.Capability
import ProofForge.Target.Plan

namespace ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.Target

/- Evidence owned types. These are intentionally non-semantic: removing them
cannot change capabilities, target code, or observable runtime behavior. -/

structure SourceMap where
  entries : Array (FunctionId × Option BlockId × Option Nat × SourceLocation)
  deriving Repr, BEq

structure VerificationAnnotations where
  invariants : Array String := #[]
  liveness : Array String := #[]
  deriving Repr, BEq

structure LegacyClassificationEvidence where
  nodeTag : String
  decision : String
  reason : String
  deriving Repr, BEq

structure CanonicalEvidence where
  sourceMap : SourceMap
  verification : VerificationAnnotations
  legacyClassification : Array LegacyClassificationEvidence
  deriving Repr, BEq

/- Interface contract: artifact-affecting metadata about entrypoints. -/

structure InterfaceEntrypoint where
  functionId : FunctionId
  kind : String
  mutatesState : Bool
  deriving Repr, BEq

structure InterfaceContract where
  entrypoints : Array InterfaceEntrypoint
  dispatchHints : Array String := #[]
  deriving Repr, BEq

/- Materialization contract: constructor bindings, allocator, upgrade, and
proxy policy that affect generated artifacts. -/

structure ConstructorBinding where
  stateId : StateId
  value : CoreLiteral
  deriving Repr, BEq

structure MaterializationContract where
  constructorBindings : Array ConstructorBinding := #[]
  allocatorRequirement : Option String := none
  upgradePolicy : Option String := none
  deriving Repr, BEq

/- Canonical contract: the checked runtime/materialization boundary passed to
plan builders. Evidence is not part of this type. -/

structure CanonicalContract where
  schemaVersion : Nat
  module : Core.Module
  interface : InterfaceContract
  materialization : MaterializationContract
  requirements : Array CapabilityCall
  deriving Repr, BEq

structure CheckedCanonicalContract where
  contract : CanonicalContract
  deriving Repr, BEq

structure CanonicalBundle where
  contract : CheckedCanonicalContract
  evidence : CanonicalEvidence
  deriving Repr, BEq

def emptyEvidence : CanonicalEvidence := {
  sourceMap := { entries := #[] }
  verification := {}
  legacyClassification := #[]
}

namespace CanonicalEvidence

def withSourceMap (evidence : CanonicalEvidence) (sourceMap : SourceMap) :
    CanonicalEvidence := { evidence with sourceMap := sourceMap }

def withVerification (evidence : CanonicalEvidence)
    (verification : VerificationAnnotations) : CanonicalEvidence :=
  { evidence with verification := verification }

def withLegacyClassification (evidence : CanonicalEvidence)
    (classification : Array LegacyClassificationEvidence) : CanonicalEvidence :=
  { evidence with legacyClassification := classification }

end CanonicalEvidence

/- Decorate a validation error with a source span from the evidence source map.
Decoration must not change the error tag or validation result. -/

def decorateValidationError (evidence : CanonicalEvidence)
    (e : ValidationError) : ValidationError :=
  let match? := evidence.sourceMap.entries.find? (fun entry =>
    let (fid, bid, idx, _) := entry
    fid == e.function && bid == e.block && idx == e.instruction)
  match match? with
  | none => e
  | some (_, _, _, loc) => e.withLocation loc

/- Required capabilities are determined entirely by the checked contract;
evidence plays no role. -/

def capabilityRequirements (bundle : CanonicalBundle) : Array CapabilityCall :=
  bundle.contract.contract.requirements

private def validateInterface (module : Core.Module)
    (interface : InterfaceContract) : Except ValidationError Unit := do
  for ep in interface.entrypoints do
    unless module.functions.any (·.id == ep.functionId) do
      .error <| ValidationError.mkSimple .invalidInterface "interface"
        s!"interface references unknown function {repr ep.functionId}"

private def validateMaterialization (module : Core.Module)
    (materialization : MaterializationContract) : Except ValidationError Unit := do
  for b in materialization.constructorBindings do
    unless module.state.any (·.id == b.stateId) do
      .error <| ValidationError.mkSimple .invalidMaterialization "materialization"
        s!"constructor binding references unknown state {repr b.stateId}"

private def validateRequirements (requirements : Array CapabilityCall) :
    Except ValidationError Unit := do
  for call in requirements do
    if call.operation.isEmpty then
      .error <| ValidationError.mkSimple .unknownReference "capability"
        s!"capability call for {call.capability} has empty operation"

/- Validate a canonical contract in the required fixed order. The result is a
`CheckedCanonicalContract`; evidence is not consumed by validation. -/

def validateCanonical (c : CanonicalContract) :
    Except ValidationError CheckedCanonicalContract := do
  let checkedModule ← Validate.validateModule c.module
  validateInterface checkedModule.module c.interface
  validateMaterialization checkedModule.module c.materialization
  validateRequirements c.requirements
  return { contract := c }

/- Manual `Inhabited` instances for panic/debug contexts. These defaults are
not valid contracts and are not produced by `validateCanonical`. -/

instance : Inhabited SourceMap where default := { entries := #[] }
instance : Inhabited VerificationAnnotations where default := {}
instance : Inhabited LegacyClassificationEvidence where default := { nodeTag := "", decision := "", reason := "" }
instance : Inhabited CanonicalEvidence where default := { sourceMap := default, verification := default, legacyClassification := #[] }
instance : Inhabited InterfaceEntrypoint where default := { functionId := ⟨0⟩, kind := "", mutatesState := false }
instance : Inhabited InterfaceContract where default := { entrypoints := #[] }
instance : Inhabited ConstructorBinding where default := { stateId := ⟨0⟩, value := .unitLit }
instance : Inhabited MaterializationContract where default := { constructorBindings := #[] }
instance : Inhabited CanonicalContract where default := { schemaVersion := 0, module := default, interface := default, materialization := default, requirements := #[] }
instance : Inhabited CheckedCanonicalContract where default := { contract := default }
instance : Inhabited CanonicalBundle where default := { contract := default, evidence := default }

end ProofForge.IR.Canonical
