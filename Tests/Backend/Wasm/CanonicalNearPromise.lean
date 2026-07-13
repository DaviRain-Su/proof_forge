import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.IR.Core.HostOp
import ProofForge.Frontend.Surface
import ProofForge.Frontend.Surface.Host.Near
import ProofForge.Backend.WasmHost.ModulePlan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Lower

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
           .literal (.bytesLit (ByteArray.mk #[42, 7])),
           .literal (.u128Lit 18446744073709551619),
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
  let supportedIds := ProofForge.Target.HostOps.Near.supportedIds
  require (reg.handlers.size == supportedIds.size)
    "handler registry and target-owned signature catalog must have equal size"
  require (reg.handlers.all (·.targetId == "wasm-near"))
    "all handler targets should be wasm-near"
  require (supportedIds.all fun id => reg.handlers.any (·.id == id))
    "every target-owned NEAR HostOp signature must have a plan handler"
  require (reg.handlers.any (·.id == pcId))
    "registry should contain near.promise.create@1.0.0"
  require (reg.handlers.any (·.id == promiseResultU64Id))
    "registry should contain near.promise.result_u64@1.0.0"
  require (reg.handlers.any (·.id == promiseResultsCountId))
    "registry should contain near.promise.results_count@1.0.0"
  require (reg.handlers.any (·.id == promiseResultStatusId))
    "registry should contain near.promise.result_status@1.0.0"

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

  /- Check 5: target profiles own exact HostOp support declarations. -/
  require (ProofForge.Target.wasmNear.hostOps.contains pcId) "NEAR profile should advertise handler"
  require (!ProofForge.Target.evm.hostOps.contains pcId) "EVM profile must not advertise NEAR handler"
  require (!ProofForge.Target.solanaSbpfAsm.hostOps.contains pcId)
    "Solana profile must not advertise NEAR handler"

  /- Check 6: pcId render matches. -/
  require (pcId.render == "near.promise/create@1.0.0") "render mismatch"

  /- Check 7: Surface contract with hostCallBind normalizes. -/
  let bundle ← match normalizeSurface promiseContract with
  | Except.ok b => pure b
  | Except.error e => throw <| IO.userError s!"normalizeSurface failed: {repr e}"
  require (bundle.contract.contract.requirements.any fun call =>
      call.capability == ProofForge.Target.Capability.nearPromise &&
      call.operation == .hostOp pcId)
    "canonical requirements must retain the exact HostOp ID and capability"

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

  /- Check 11: the actual Core -> NEAR plan consumes the typed HostOp. -/
  let capabilities : ProofForge.Target.CapabilityPlan := {
    targetId := "wasm-near", calls := bundle.contract.contract.requirements, metadata := #[] }
  let plan ← match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore
      bundle.contract capabilities with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"promise Core -> NEAR plan failed: {e.message}"
  let hasPromise := plan.functions.any fun function => function.blocks.any fun block =>
    block.ops.any fun op => match op with
      | .promiseCreate _ "alice.near" "methodName" payload deposit 1000 =>
          payload == ByteArray.mk #[42, 7] && deposit == 18446744073709551619
      | _ => false
  require hasPromise "NEAR plan did not preserve promise.create payload"

  /- Check 12: required capability is enforced by the target plan boundary. -/
  match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore bundle.contract {
      targetId := "wasm-near", calls := #[], metadata := #[] } with
  | .error e =>
      require (e.message.contains "capability")
        s!"missing capability diagnostic: {e.message}"
  | .ok _ => throw <| IO.userError "NEAR promise plan accepted no nearPromise capability"

  /- Check 13: lower the promise plan to real WAT. -/
  let module ← match ProofForge.Backend.WasmHost.ModulePlan.lowerFromPlan plan with
    | .ok module => pure module
    | .error e => throw <| IO.userError s!"promise NEAR lowering failed: {e.message}"
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  require (wat.contains "(import \"env\" \"promise_create\"") "promise_create import missing"
  require (wat.contains "call $promise_create") "promise_create call missing"
  require (wat.contains "alice.near" && wat.contains "methodName") "promise string data missing"
  require (wat.contains "i32.const 42" && wat.contains "i32.const 7") "promise args bytes missing"
  IO.FS.createDirAll "build/canonical/near-promise"
  IO.FS.writeFile "build/canonical/near-promise/contract.wat" wat

  IO.println "canonical-near-promise: ok"
