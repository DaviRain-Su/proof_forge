import ProofForge.IR.Legacy.Classification
import Lean

open ProofForge.IR.Legacy
open Lean Elab Term

elab "contractSpecFieldNames" : term => do
  let fields := getStructureFields (← getEnv) ``ProofForge.Contract.ContractSpec
  let names := fields.map (fun name => Syntax.mkStrLit name.getString!)
  let stx ← `(#[ $[$names],* ])
  elabTerm stx none

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def nonBlank (s : String) : Bool :=
  s.any (fun c => !c.isWhitespace)

def isUnique (xs : Array String) : Bool :=
  Id.run do
    for i in [0:xs.size] do
      for j in [i+1:xs.size] do
        if xs[i]! == xs[j]! then
          return false
    return true

def emptyLegacyModule : ProofForge.IR.Module := {
  name := "LegacyInventory"
  state := #[]
  entrypoints := #[]
}

def main : IO Unit := do
  require (allDecisions.all fun decision => nonBlank decision.reason)
    "legacy decision without reason"
  require (allDecisions.all fun decision => nonBlank decision.owner)
    "legacy decision without owner"
  require (isUnique allNodeTags)
    "duplicate legacy node tag"
  require (allPayloadDecisions.all fun decision => nonBlank decision.reason)
    "legacy payload decision without reason"
  require (allPayloadDecisions.all fun decision => nonBlank decision.owner)
    "legacy payload decision without owner"
  require (isUnique (allPayloadDecisions.map (·.nodeTag)))
    "duplicate legacy payload node tag"
  let spec := ProofForge.Contract.ContractSpec.fromIR emptyLegacyModule
  let fieldDecisions := classifySpecFields spec
  require (fieldDecisions.map (·.field) == contractSpecFieldNames)
    "ContractSpec field inventory drift"
  require (fieldDecisions.all fun decision => nonBlank decision.field)
    "ContractSpec decision without field name"
  require (fieldDecisions.all fun decision => nonBlank decision.reason)
    "ContractSpec decision without reason"
  require (fieldDecisions.all fun decision => nonBlank decision.owner)
    "ContractSpec decision without owner"
  require (isUnique (fieldDecisions.map (·.field)))
    "duplicate ContractSpec field decision"
  IO.println "canonical-legacy-inventory: ok"
