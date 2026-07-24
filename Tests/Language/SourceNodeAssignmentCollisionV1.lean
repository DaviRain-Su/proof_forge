import ProofForgeV2.Source.NodeAssignmentV1

namespace Tests.Language.SourceNodeAssignmentCollisionV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireV1

abbrev NodeIdCandidate16V1 := ByteArray → Except String ByteArray

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def expectError (label expected : String) (result : Except String α) : IO Unit :=
  match result with
  | .error detail => expect (detail == expected) s!"{label}: expected {expected}, got {detail}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def assignNodeIdsV1ForTestCore
    (candidate16 : NodeIdCandidate16V1)
    (transformVisits : Array NodeVisitV1 → Array NodeVisitV1)
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String (Array NodeIdAssignmentV1) :=
  source_node_assignment_loop_v1% moduleName | programIdentity | program |
    (fun preimage _path => candidate16 preimage) | transformVisits | pure

/-- Test-build-only digest seam; the opaque production table is observed as its sole array projection. -/
def assignNodeIdsV1ForTestWithCandidate
    (candidate16 : NodeIdCandidate16V1)
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String (Array NodeIdAssignmentV1) :=
  assignNodeIdsV1ForTestCore candidate16 id moduleName programIdentity program

private def productionCandidate16 (preimage : ByteArray) : Except String ByteArray := do
  let domain := "pf.source-node.v1".toUTF8.push 0
  unless preimage.extract 0 domain.size == domain do
    throw "candidate did not receive a canonical NodeId preimage"
  pure ((Crypto.sha256 preimage).extract 0 16)

private def constantCandidate16 (_preimage : ByteArray) : Except String ByteArray :=
  pure (ByteArray.mk (Array.replicate 16 0))

private def shortCandidate15 (_preimage : ByteArray) : Except String ByteArray :=
  pure (ByteArray.mk (Array.replicate 15 0))

private def longCandidate17 (_preimage : ByteArray) : Except String ByteArray :=
  pure (ByteArray.mk (Array.replicate 17 0))

private def failingCandidate (_preimage : ByteArray) : Except String ByteArray :=
  .error "candidate-failure"

private def duplicateRootVisit (visits : Array NodeVisitV1) : Array NodeVisitV1 :=
  match visits[0]? with
  | none => visits
  | some root => #[root] ++ visits

private def simpleProgram (name : SourceNameComponentV1) : ProgramV1 := {
  name
  items := #[.state { visibility := .public_, name, type_ := .bool }]
}

/-- D1-PA-124: forced candidate collision, duplicate visit, and callback boundaries. -/
def run : IO Unit := do
  let name ← liftResult "name" (parseSourceNameComponentV1 "n")
  let moduleName ← liftResult "module" (parseSourceQualifiedNameV1 #["M"])
  let identity ← liftResult "identity" (parseSourceQualifiedNameV1 #["M", "n"])
  let program := simpleProgram name

  let productionTable ← liftResult "production assignment"
    (assignNodeIdsV1 moduleName identity program)
  let productionRows := nodeAssignmentsPreorderV1 productionTable
  let testRows ← liftResult "test production candidate"
    (assignNodeIdsV1ForTestWithCandidate productionCandidate16 moduleName identity program)
  expect (decide (testRows = productionRows))
    "test SHA candidate must equal the production table projection"
  expect (testRows.map (·.constructorTag) == #["Program", "StateDecl", "Type.Bool"])
    "positive test assignment preorder"

  expectError "constant candidate collision"
    "PF-SRC-NODEID-COLLISION: distinct canonical source node preimages produced the same NodeId"
    (assignNodeIdsV1ForTestWithCandidate constantCandidate16 moduleName identity program)
  expectError "short candidate" "node id candidate must contain exactly 16 raw bytes"
    (assignNodeIdsV1ForTestWithCandidate shortCandidate15 moduleName identity program)
  expectError "long candidate" "node id candidate must contain exactly 16 raw bytes"
    (assignNodeIdsV1ForTestWithCandidate longCandidate17 moduleName identity program)
  expectError "candidate error" "candidate-failure"
    (assignNodeIdsV1ForTestWithCandidate failingCandidate moduleName identity program)

  expectError "duplicate visit" "PF-INTERNAL: duplicate-node-visit"
    (assignNodeIdsV1ForTestCore productionCandidate16 duplicateRootVisit
      moduleName identity program)
  expectError "duplicate before collision" "PF-INTERNAL: duplicate-node-visit"
    (assignNodeIdsV1ForTestCore constantCandidate16 duplicateRootVisit
      moduleName identity program)

  let wrongIdentity ← liftResult "wrong identity"
    (parseSourceQualifiedNameV1 #["Elsewhere", "n"])
  expectError "identity before candidate"
    "program identity must begin with the exact module name components"
    (assignNodeIdsV1ForTestWithCandidate failingCandidate moduleName wrongIdentity program)

end Tests.Language.SourceNodeAssignmentCollisionV1
