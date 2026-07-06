import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.UnboundedIntProbe

open ProofForge.IR

/-- A U128 literal well above typical `MAX_UINT` scenario bounds. -/
def largeLiteral : Nat := 1000000

def stateBalance : StateDecl := {
  id := "balance"
  kind := .scalar
  type := .u128
}

def writeLarge : Entrypoint := {
  name := "write_large"
  returns := .unit
  body := #[
    .effect (.storageScalarWrite "balance" (.literal (.u128 largeLiteral)))
  ]
}

def addAmount : Entrypoint := {
  name := "add_amount"
  params := #[("amount", .u128)]
  returns := .u128
  body := #[
    .letBind "cur" .u128 (.effect (.storageScalarRead "balance")),
    .effect (.storageScalarWrite "balance" (.add (.local "cur") (.local "amount"))),
    .return (.effect (.storageScalarRead "balance"))
  ]
}

def module : Module := {
  name := "UnboundedIntProbe"
  state := #[stateBalance]
  entrypoints := #[writeLarge, addAmount]
}

end ProofForge.IR.Examples.UnboundedIntProbe