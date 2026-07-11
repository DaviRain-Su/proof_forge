import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near
import ProofForge.IR.Core.HostOp
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Target

/-! # Solana Public Route Test

Verifies that the canonical validation gate runs on the `solana-sbpf-asm`
public route:

- `runCanonicalValidationGate` succeeds for Counter and ValueVault.
- A Surface contract with a `near.promise.create` hostCall reports
  `missingHostOpHandler` on `solana-sbpf-asm`.
- The gate is advisory when `adaptLegacy` fails (adapter coverage gap).
- `buildFromCore` produces a valid Solana `SolanaModulePlan` for Counter.
-/

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Backend.Solana.Plan.Core
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.Frontend.Surface
open ProofForge.IR.Core.HostOp

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def withoutSelectors (module : ProofForge.IR.Module) : ProofForge.IR.Module :=
  { module with entrypoints := module.entrypoints.map (fun entrypoint =>
      { entrypoint with selector? := none }) }

/-- A Surface contract with a near.promise.create hostCall — unsupported on Solana. -/
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
  let counterSpec := ContractSpec.fromIR (withoutSelectors ProofForge.IR.Examples.Counter.module)
  let vaultSpec := ContractSpec.fromIR (withoutSelectors ProofForge.IR.Examples.ValueVault.module)

  /- Check 1: gate succeeds for Counter (product contract, adapter covers it). -/
  match runCanonicalValidationGate "solana-sbpf-asm" counterSpec with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Counter canonical gate failed: {e}"

  /- Check 2: gate succeeds for ValueVault. -/
  match runCanonicalValidationGate "solana-sbpf-asm" vaultSpec with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ValueVault canonical gate failed: {e}"

  /- Check 3: buildFromCore produces a valid Solana plan for Counter. -/
  match ProofForge.IR.Legacy.Adapter.adaptLegacy counterSpec with
  | .error e => throw <| IO.userError s!"adaptLegacy failed: {repr e}"
  | .ok bundle =>
    match ProofForge.IR.Canonical.validateCanonical bundle.contract.contract with
    | .error e => throw <| IO.userError s!"validateCanonical failed: {repr e}"
    | .ok checked =>
      let capPlan : ProofForge.Target.CapabilityPlan := { targetId := "solana-sbpf-asm", calls := checked.contract.requirements, metadata := #[] }
      match buildFromCore checked capPlan with
      | .error e => throw <| IO.userError s!"buildFromCore failed: {e.message}"
      | .ok plan =>
        require (plan.targetId == "solana-sbpf-asm") "plan target should be solana-sbpf-asm"
        require (plan.entrypoints.size > 0) "plan should have entrypoints"

  /- Check 4: Surface contract with near.promise.create hostCall reports
  missingHostOpHandler on Solana (same as EVM). -/
  let surfaceBundle ← match normalizeSurface promiseContract with
  | .ok b => pure b
  | .error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"
  let solanaErrors := checkHostOpHandlers "solana-sbpf-asm" surfaceBundle.contract
  require (solanaErrors.size > 0) "Solana should report missingHostOpHandler"
  require (solanaErrors.any (·.contains "missingHostOpHandler"))
    "Solana error should contain missingHostOpHandler"

  /- Check 5: NEAR does NOT report missingHostOpHandler (handler exists). -/
  let nearErrors := checkHostOpHandlers "wasm-near" surfaceBundle.contract
  require (nearErrors.size == 0) "NEAR should not report missingHostOpHandler"

  /- Check 6: gate is advisory when adaptLegacy fails (adapter coverage gap).
  Use an IR module with an unbound release that the adapter cannot handle. -/
  let unsupportedModule : ProofForge.IR.Module := {
    name := "UnsupportedAdapter"
    state := #[]
    entrypoints := #[{
      name := "run"
      selector? := none
      body := #[.release "unbound"]
    }]
  }
  let unsupportedSpec := ContractSpec.fromIR unsupportedModule
  match runCanonicalValidationGate "solana-sbpf-asm" unsupportedSpec with
  | .ok () => pure ()  /- advisory: adaptLegacy failed, gate passes -/
  | .error e => throw <| IO.userError s!"gate should be advisory on adapter failure, got: {e}"

  IO.println "solana-public-route: ok"