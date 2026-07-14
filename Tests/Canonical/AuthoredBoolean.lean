import ProofForge.Frontend.Authored
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Target.Registry

namespace ProofForge.Tests.Canonical.AuthoredBoolean

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def contract : AuthoredContract := {
  name := "BooleanPortable"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[]
  entrypoints := #[
    {
      name := "both"
      kind := .function
      mutability := .view
      selector? := some "01020304"
      params := #[{ name := "lhs", type := .bool }, { name := "rhs", type := .bool }]
      retType := .bool
      body := #[.returnExpr (.boolAnd (.local "lhs") (.local "rhs"))]
    },
    {
      name := "either"
      kind := .function
      mutability := .view
      selector? := some "05060708"
      params := #[{ name := "lhs", type := .bool }, { name := "rhs", type := .bool }]
      retType := .bool
      body := #[.returnExpr (.boolOr (.local "lhs") (.local "rhs"))]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

def badContract : AuthoredContract := {
  contract with
  name := "BadBoolean"
  entrypoints := #[{
    name := "bad"
    kind := .function
    mutability := .view
    selector? := some "090a0b0c"
    params := #[]
    retType := .bool
    body := #[.returnExpr (.boolAnd
      (.literal (.u64Lit 1)) (.literal (.boolLit true)))]
  }]
}

def plan (targetId : String) (bundle : ProofForge.IR.Canonical.CanonicalBundle) :
    CapabilityPlan := { targetId, calls := bundle.contract.contract.requirements }

def run : IO Unit := do
  let bundle ← match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"boolean normalization failed: {repr error}"
  let operations := bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap (fun block => block.instructions.map (·.op))
  require (operations.any fun operation => match operation with
      | .pure (.boolean .and _ _) => true | _ => false)
    "Authored boolAnd did not become the portable Core boolean operation"
  require (operations.any fun operation => match operation with
      | .pure (.boolean .or _ _) => true | _ => false)
    "Authored boolOr did not become the portable Core boolean operation"
  match normalizeAuthored badContract with
  | .ok _ => throw <| IO.userError "boolean operation accepted a non-bool operand"
  | .error _ => pure ()
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore bundle.contract (plan evm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"EVM boolean planning failed: {error.message}"
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract
      (plan solanaSbpfAsm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"Solana boolean planning failed: {error.message}"
  match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore bundle.contract
      (plan wasmNear.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"NEAR boolean planning failed: {error.message}"
  IO.println "authored-boolean: ok"

end ProofForge.Tests.Canonical.AuthoredBoolean

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredBoolean.run
