import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Contract.Spec
import ProofForge.Target.Plan

/-!
# Intent Materializer Registry

Target-neutral dispatch from `(targetId, IntentFamily)` to a
`IntentMaterializer` that produces a `ContractSpec`.

The registry owns the only `(targetId, intent family)` dispatch.
Frontend DSL, Surface helpers, Canonical Core, and reusable product
sources do not switch on `targetId`.
-/

namespace ProofForge.Contract

/-- The product family of an intent. -/
inductive IntentFamily where
  | fungibleToken
  | nonFungibleToken
  | governance
  | vault
  deriving BEq, Repr

/-- Author-facing intent: target-neutral, checked before target selection. -/
structure IntentContract where
  family : IntentFamily
  name : String
  symbol? : Option String := none
  requirements : Array ProofForge.Target.CapabilityCall := #[]
  featureIds : Array String := #[]
  deriving Repr

/-- The output of a successful materialization: a real ContractSpec
plus metadata about the resolved standard. -/
structure IntentMaterialization where
  targetId : String
  standardId : String
  contractSpec : ProofForge.Contract.ContractSpec
  evidence : Array String := #[]
  deriving Repr

/-- A target-specific materializer: maps an IntentContract to a
ContractSpec for one target. -/
structure IntentMaterializer where
  targetId : String
  family : IntentFamily
  materialize : IntentContract → Except String IntentMaterialization

/-- A registry of materializers keyed by (targetId, family).
Duplicate keys are rejected at creation time. -/
structure IntentRegistry where
  entries : Array IntentMaterializer := #[]

/-- The empty registry. -/
def IntentRegistry.empty : IntentRegistry := { entries := #[] }

/-- Create a registry from a list of materializers.
Rejects duplicate `(targetId, family)` keys. -/
def IntentRegistry.create (materializers : Array IntentMaterializer) :
    Except String IntentRegistry :=
  materializers.foldl (fun acc m =>
    match acc with
    | .error e => .error e
    | .ok reg =>
      if reg.entries.any (fun e => e.targetId == m.targetId && e.family == m.family) then
        .error s!"duplicate materializer for target `{m.targetId}` and family {repr m.family}"
      else .ok { entries := reg.entries.push m })
    (.ok IntentRegistry.empty)

/-- Look up a materializer by (targetId, family). -/
def IntentRegistry.resolve (reg : IntentRegistry) (targetId : String)
    (family : IntentFamily) : Except String IntentMaterializer :=
  match reg.entries.find? (fun m => m.targetId == targetId && m.family == family) with
  | some m => .ok m
  | none => .error
    s!"no materializer for target `{targetId}` and family {repr family}"

end ProofForge.Contract