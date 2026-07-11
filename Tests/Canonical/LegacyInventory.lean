import ProofForge.IR.Legacy.Classification

open ProofForge.IR.Legacy

def expectedContractSpecFields : Array String := #[
  "name",
  "module",
  "intents",
  "upgradePolicy?",
  "proxyPattern?",
  "constructorParams",
  "constructorInitBindings",
  "quintInvariants",
  "quintLiveness",
  "leanInvariants"
]

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

def main : IO Unit := do
  require (allDecisions.all fun decision => nonBlank decision.reason)
    "legacy decision without reason"
  require (allDecisions.all fun decision => nonBlank decision.owner)
    "legacy decision without owner"
  require (isUnique allNodeTags)
    "duplicate legacy node tag"
  require (contractSpecFieldDecisions.map (·.field) == expectedContractSpecFields)
    "ContractSpec field inventory drift"
  IO.println "canonical-legacy-inventory: ok"
