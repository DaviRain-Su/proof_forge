import Std.Data.HashMap
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireV1

namespace ProofForgeV2.Source.NodeAssignmentV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireV1

/-- One production NodeId paired with its canonical traversal identity. -/
structure NodeIdAssignmentV1 where
  constructorTag : String
  path : NormalizedSyntacticPathV1
  nodeId : NodeId
  deriving DecidableEq, Repr

/-- Opaque pre-span NodeId assignments in canonical ProgramV1 preorder. -/
structure NodeOriginTableV1 where
  private mk ::
  private assignments : Array NodeIdAssignmentV1
  deriving DecidableEq, Repr

/-- The sole observable table projection, fixed to canonical preorder. -/
def nodeAssignmentsPreorderV1 (table : NodeOriginTableV1) :
    Array NodeIdAssignmentV1 :=
  table.assignments

private structure SeenNodeV1 where
  canonicalPreimage : ByteArray
  path : NormalizedSyntacticPathV1

private def fail (detail : String) : Except String α :=
  .error detail

private def duplicateVisit : Except String α :=
  fail "PF-INTERNAL: duplicate-node-visit"

private def candidateCollision : Except String α :=
  fail "PF-SRC-NODEID-COLLISION: distinct canonical source node preimages produced the same NodeId"

/-- Assign fixed production NodeIds without exposing candidate replacement. -/
def assignNodeIdsV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String NodeOriginTableV1 := do
  validateSourceProgramIdentityV1 moduleName programIdentity
  let visits ← canonicalNodeVisitsV1 program
  let mut seen : Std.HashMap ByteArray SeenNodeV1 :=
    Std.HashMap.emptyWithCapacity visits.size
  let mut assignments : Array NodeIdAssignmentV1 := #[]
  for visit in visits do
    let canonicalPreimage ← nodeIdPreimageV1 moduleName programIdentity visit.path
    let nodeId ← nodeIdV1 moduleName programIdentity visit.path
    let observed : SeenNodeV1 := {
      canonicalPreimage
      path := visit.path
    }
    let (previous?, updated) :=
      seen.getThenInsertIfNew? nodeId.bytes observed
    match previous? with
    | none =>
        seen := updated
        assignments := assignments.push {
          constructorTag := visit.constructorTag
          path := visit.path
          nodeId
        }
    | some previous =>
        if previous.canonicalPreimage == canonicalPreimage then
          return ← duplicateVisit
        else
          return ← candidateCollision
  pure ⟨assignments⟩

end ProofForgeV2.Source.NodeAssignmentV1
