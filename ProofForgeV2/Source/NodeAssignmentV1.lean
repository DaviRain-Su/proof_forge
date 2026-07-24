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

/-- Compile-time shared assignment loop; runtime production remains fixed to `nodeIdV1`. -/
syntax "source_node_assignment_loop_v1% " term:arg " | " term:arg " | " term:arg
  " | " term:arg " | " term:arg " | " term:arg : term

macro_rules
  | `(source_node_assignment_loop_v1% $moduleName:term | $programIdentity:term |
        $sourceProgram:term | $candidate:term | $visitTransform:term | $finish:term) =>
      `(do
        validateSourceProgramIdentityV1 $moduleName $programIdentity
        let canonicalVisits ← canonicalNodeVisitsV1 $sourceProgram
        let visits := ($visitTransform) canonicalVisits
        let mut seen : Std.HashMap ByteArray
            (ByteArray × NormalizedSyntacticPathV1) :=
          Std.HashMap.emptyWithCapacity visits.size
        let mut assignments : Array NodeIdAssignmentV1 := #[]
        for visit in visits do
          let preimage ← nodeIdPreimageV1 $moduleName $programIdentity visit.path
          let candidateBytes ← ($candidate) preimage visit.path
          unless candidateBytes.size == 16 do
            throw "node id candidate must contain exactly 16 raw bytes"
          let nodeId : NodeId := { bytes := candidateBytes }
          validateNodeId nodeId
          let observed := (preimage, visit.path)
          let (previous?, updated) :=
            seen.getThenInsertIfNew? candidateBytes observed
          match previous? with
          | none =>
              seen := updated
              assignments := assignments.push {
                constructorTag := visit.constructorTag
                path := visit.path
                nodeId
              }
          | some previous =>
              if previous.1 == preimage then
                throw "PF-INTERNAL: duplicate-node-visit"
              else
                throw "PF-SRC-NODEID-COLLISION: distinct canonical source node preimages produced the same NodeId"
        return ← ($finish) assignments)

private def productionCandidate16
    (moduleName programIdentity : SourceQualifiedNameV1)
    (_preimage : ByteArray) (path : NormalizedSyntacticPathV1) :
    Except String ByteArray := do
  let nodeId ← nodeIdV1 moduleName programIdentity path
  pure nodeId.bytes

/-- Assign fixed production NodeIds without exposing candidate replacement. -/
def assignNodeIdsV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String NodeOriginTableV1 :=
  source_node_assignment_loop_v1% moduleName | programIdentity | program |
    (productionCandidate16 moduleName programIdentity) | id |
    (fun assignments => pure ⟨assignments⟩)

end ProofForgeV2.Source.NodeAssignmentV1
