import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.AuthoredCrosscall

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def contract : AuthoredContract := {
  name := "CrosscallSchema"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[
    {
      name := "named"
      kind := .function
      mutability := .call
      params := #[{ name := "amount", type := .u128 }]
      retType := .u64
      body := #[.returnExpr (.crosscall .namedInvoke
        (.literal (.stringLit "vault.near")) (.literal (.u64Lit 2))
        (some (.literal (.u64Lit 30))) (some (.local "amount")) #["amount"]
        #[.local "amount"] .u64)]
    },
    {
      name := "continue"
      kind := .function
      mutability := .call
      params := #[]
      retType := .u64
      body := #[.returnExpr (.crosscall .continuation
        (.literal (.u64Lit 7)) (.literal (.u64Lit 3)) none
        (some (.literal (.u128Lit 0))) #[] #[] .u64)]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

def badArgumentNames : AuthoredContract := {
  contract with
  name := "BadArgumentNames"
  entrypoints := #[{
    name := "bad"
    kind := .function
    mutability := .call
    params := #[]
    retType := .u64
    body := #[.returnExpr (.crosscall .invoke
      (.literal (.addressLit "peer")) (.literal (.stringLit "run"))
      none none #["first", "second"] #[.literal (.u64Lit 1)] .u64)]
  }]
}

def badGasType : AuthoredContract := {
  contract with
  name := "BadGasType"
  entrypoints := #[{
    name := "bad"
    kind := .function
    mutability := .call
    params := #[]
    retType := .u64
    body := #[.returnExpr (.crosscall .invoke
      (.literal (.addressLit "peer")) (.literal (.stringLit "run"))
      (some (.literal (.u128Lit 30))) none #[] #[] .u64)]
  }]
}

def requireNormalizationFailure (candidate : AuthoredContract) (message : String) : IO Unit :=
  match normalizeAuthored candidate with
  | .ok _ => throw <| IO.userError message
  | .error _ => pure ()

def run : IO Unit := do
  let bundle ← match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"normalization failed: {repr error}"
  let operations := bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap (fun block => block.instructions.map (·.op))
  require (operations.any fun operation => match operation with
    | .crosscall spec #[argument] =>
        spec.mode == .namedInvoke && spec.gas.map (·.type) == some .u64 &&
          spec.value.map (·.type) == some .u128 && spec.argNames == #["amount"] &&
          spec.paramTypes == #[.u128] && argument.type == .u128
    | _ => false)
    "named crosscall lost gas, value, JSON argument names, or parameter types"
  require (operations.any fun operation => match operation with
    | .crosscall spec #[] =>
        spec.mode == .continuation && spec.gas.isNone &&
          spec.value.map (·.type) == some .u128 && spec.argNames.isEmpty &&
          spec.paramTypes.isEmpty
    | _ => false)
    "continuation crosscall was not preserved"
  requireNormalizationFailure badArgumentNames
    "crosscall accepted an argument-name count mismatch"
  requireNormalizationFailure badGasType
    "crosscall accepted a non-u64 gas expression"
  IO.println "authored-crosscall: ok"

end ProofForge.Tests.Canonical.AuthoredCrosscall

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredCrosscall.run
