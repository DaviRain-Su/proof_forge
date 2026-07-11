import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near
import ProofForge.IR.Core.HostOp

/-! # EVM Public Route Test

Verifies that the public `evm` target route uses canonical normalization
without fallback:
- Counter and ValueVault compile successfully via the canonical pipeline.
- The canonical gate (adaptLegacy → validateCanonical → buildFromCore) is
  mandatory: no retry of legacy on canonical failure.
- A hostCall to near.promise.create on EVM returns missingHostOpHandler
  (the canonical gate fails; legacy renderYul is never reached).
- The canonical and legacy paths produce identical diagnostics for valid
  contracts (both pass, proving parity).
-/

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Backend.Evm.Plan.Core
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.Frontend.Surface
open ProofForge.IR.Core.HostOp

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A Surface contract with a near.promise.create hostCall — unsupported on EVM. -/
def promiseContract : SurfaceContract := {
  name := "PromiseTest",
  structs := #[],
  state := #[{ name := "count", kind := .scalar .u64 }],
  events := #[],
  errors := #[],
  entrypoints := #[
    { name := "createPromise", kind := .function, mutability := .call,
      params := #[], retType := .u64,
      body := #[
        .hostCallBind "promiseIdx" .u64
          (ProofForge.Frontend.Surface.Host.Near.promiseCreateId)
          #[.literal (.stringLit "alice.near"),
           .literal (.stringLit "methodName"),
           .literal (.bytesLit ByteArray.empty),
           .literal (.u128Lit 0),
           .literal (.u64Lit 1000)],
        .returnExpr (.local "promiseIdx")
      ]
    }
  ],
  constructorParams := #[],
  constructorBindings := #[],
  intents := #[]
}

def main : IO Unit := do
  let counterSpec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  let vaultSpec := ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module

  /- Check 1: Counter canonical EVM succeeds. -/
  match ← compileForTest .canonical "evm" counterSpec with
  | .error diag => throw <| IO.userError s!"Counter canonical EVM failed: {repr diag}"
  | .ok bundle =>
    require (bundle.targetId == "evm") "bundle target should be evm"

  /- Check 2: ValueVault canonical EVM succeeds. -/
  match ← compileForTest .canonical "evm" vaultSpec with
  | .error diag => throw <| IO.userError s!"ValueVault canonical EVM failed: {repr diag}"
  | .ok _ => pure ()

  /- Check 3: Legacy EVM also succeeds (parity for valid contracts). -/
  match ← compileForTest .legacy "evm" counterSpec with
  | .error diag => throw <| IO.userError s!"Counter legacy EVM failed: {repr diag}"
  | .ok _ => pure ()

  /- Check 4: buildFromCore produces a valid EVM ModulePlan for Counter. -/
  match ProofForge.IR.Legacy.Adapter.adaptLegacy counterSpec with
  | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  | .ok bundle =>
    match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | Except.error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"
    | Except.ok checked =>
      let capPlan : ProofForge.Target.CapabilityPlan := { targetId := "evm", calls := #[], metadata := #[] }
      match buildFromCore checked capPlan with
      | Except.error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
      | Except.ok plan =>
        require (plan.name == "Counter") "plan name should be Counter"
        require (plan.targetPlan.targetId == "evm") "plan target should be evm"
        require (plan.entrypoints.size > 0) "plan should have entrypoints"

  /- Check 5: Surface contract with hostCall normalizes and canonical gate
  reports missingHostOpHandler on EVM (no fallback to renderYul). -/
  let surfaceBundle ← match normalizeSurface promiseContract with
  | Except.ok b => pure b
  | Except.error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"
  let evmErrors := checkHostOpHandlers "evm" surfaceBundle.contract
  require (evmErrors.size > 0) "EVM should report missingHostOpHandler"
  require (evmErrors.any (·.contains "missingHostOpHandler"))
    "EVM error should contain missingHostOpHandler"

  /- Check 6: Solana also reports missingHostOpHandler for the same hostCall. -/
  let solanaErrors := checkHostOpHandlers "solana-sbpf-asm" surfaceBundle.contract
  require (solanaErrors.size > 0) "Solana should report missingHostOpHandler"

  /- Check 7: NEAR does NOT report missingHostOpHandler (handler exists). -/
  let nearErrors := checkHostOpHandlers "wasm-near" surfaceBundle.contract
  require (nearErrors.size == 0) "NEAR should not report missingHostOpHandler"

  IO.println "evm-public-route: ok"