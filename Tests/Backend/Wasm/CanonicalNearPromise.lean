import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.IR.Core.HostOp
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near

/-! # Canonical NEAR Promise Backend Test

Verifies that:
- The NEAR canonical path builds for standard fixtures (Counter, ValueVault).
- The EVM canonical path reports missingHostOpHandler when a host call is present.
- The Solana canonical path reports missingHostOpHandler when a host call is present.
- The NEAR canonical path does NOT report missingHostOpHandler for a host call.
- The handler registry is correctly populated.
-/

open ProofForge.Compiler
open ProofForge.Contract
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp
open ProofForge.Frontend.Surface

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- The exact near.promise.create@1.0.0 HostOpId from the Surface host module. -/
def pcId : HostOpId := ProofForge.Frontend.Surface.Host.Near.promiseCreateId

/-- A Surface contract that uses near.promise.create@1.0.0. -/
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
        .hostCallBind "promiseIdx" .u64 pcId
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
  /- Check 1: nearPromiseRegistry builds successfully. -/
  let reg ← match nearPromiseRegistry with
  | Except.ok r => pure r
  | Except.error e => throw <| IO.userError s!"nearPromiseRegistry failed: {e}"
  require (reg.handlers.size == 1) "registry should have exactly one handler"
  require (reg.handlers[0]!.targetId == "wasm-near") "handler target should be wasm-near"
  require (reg.handlers[0]!.id == pcId) "handler id should be near.promise.create@1.0.0"

  /- Check 2: Counter canonical on NEAR succeeds. -/
  let counterSpec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  match ← compileForTest .canonical "wasm-near" counterSpec with
  | .error diag => throw <| IO.userError s!"Counter canonical NEAR failed: {repr diag}"
  | .ok _ => pure ()

  /- Check 3: ValueVault canonical on NEAR succeeds. -/
  let vaultSpec := ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module
  match ← compileForTest .canonical "wasm-near" vaultSpec with
  | .error diag => throw <| IO.userError s!"ValueVault canonical NEAR failed: {repr diag}"
  | .ok _ => pure ()

  /- Check 4: Counter canonical on EVM succeeds (no host calls). -/
  match ← compileForTest .canonical "evm" counterSpec with
  | .error diag => throw <| IO.userError s!"Counter canonical EVM failed: {repr diag}"
  | .ok _ => pure ()

  /- Check 5: hasHandlerFor returns true for NEAR, false for EVM/Solana. -/
  require (hasHandlerFor "wasm-near" pcId) "NEAR should have handler"
  require (!hasHandlerFor "evm" pcId) "EVM should not have handler"
  require (!hasHandlerFor "solana-sbpf-asm" pcId) "Solana should not have handler"

  /- Check 6: pcId render matches. -/
  require (pcId.render == "near.promise/create@1.0.0") "render mismatch"

  /- Check 7: Surface contract with hostCallBind normalizes. -/
  let bundle ← match normalizeSurface promiseContract with
  | Except.ok b => pure b
  | Except.error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"

  /- Check 8: EVM reports missingHostOpHandler for promise.create. -/
  let evmErrors := checkHostOpHandlers "evm" bundle.contract
  require (evmErrors.size > 0) "EVM should report missingHostOpHandler"
  require (evmErrors.any (·.contains "missingHostOpHandler"))
    "EVM error should contain missingHostOpHandler"

  /- Check 9: Solana reports missingHostOpHandler for promise.create. -/
  let solanaErrors := checkHostOpHandlers "solana-sbpf-asm" bundle.contract
  require (solanaErrors.size > 0) "Solana should report missingHostOpHandler"
  require (solanaErrors.any (·.contains "missingHostOpHandler"))
    "Solana error should contain missingHostOpHandler"

  /- Check 10: NEAR does NOT report missingHostOpHandler for promise.create. -/
  let nearErrors := checkHostOpHandlers "wasm-near" bundle.contract
  require (nearErrors.size == 0) "NEAR should not report missingHostOpHandler"

  IO.println "canonical-near-promise: ok"