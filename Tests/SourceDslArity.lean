import ProofForge.Contract.Source

namespace Examples.Product.FiveParamProbe

open ProofForge.Contract.Source

contract_source FiveParamProbe do
  state a_slot : .u64
  entry sum (a : .u64, b : .u64, c : .u64, d : .u64, e : .u64) returns(.u64) do
    a_slot := a;
    return a;

end Examples.Product.FiveParamProbe

namespace ProofForge.Tests.SourceDslArity

open Examples.Product.FiveParamProbe

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure ()
  else throw <| IO.userError message

def main : IO UInt32 := do
  require (ProofForge.Contract.Source.sourceDslVersion == "contract_source-v1")
    s!"unexpected dsl version {ProofForge.Contract.Source.sourceDslVersion}"
  require (module.entrypoints.size == 1)
    "FiveParamProbe should declare one entry"
  match module.entrypoints.toList with
  | [ep] =>
      require (ep.name == "sum") "entry name"
      require (ep.params.size == 5) s!"expected 5 params, got {ep.params.size}"
      require (ep.returns == ProofForge.IR.ValueType.u64) "return type u64"
  | _ => throw <| IO.userError "expected exactly one entrypoint"
  IO.println "SourceDslArity: ok (5-param entry + dsl version)"
  return 0

end ProofForge.Tests.SourceDslArity

def main : IO UInt32 :=
  ProofForge.Tests.SourceDslArity.main
