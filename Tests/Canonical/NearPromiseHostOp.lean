import ProofForge.Frontend.Surface.Host.Near
import ProofForge.IR.Core.HostOp
import ProofForge.Target.Capability
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
import ProofForge.IR.Core.Semantics

/-! # NEAR Promise HostOp Test

Checks the exact catalog signature and rejects:
- missing gas argument (wrong arity)
- u64 deposit instead of u128 (type mismatch)
- wrong result type
- version 1.0.1 (unknown ID)
- call without nearPromise capability (pure effect mismatch)
- call resolved for EVM (missingHostOpHandler)
- call resolved for Solana (missingHostOpHandler)
-/

open ProofForge.IR.Core
open ProofForge.IR.Core.HostOp
open ProofForge.Backend.WasmHost.NearModulePlan.HostOps
open ProofForge.IR.Core.Semantics

/-- Unambiguous alias for the Surface host signature. -/
def sig := ProofForge.Frontend.Surface.Host.Near.promiseCreateSig
/-- Unambiguous alias for the Surface host ID. -/
def pcId := ProofForge.Frontend.Surface.Host.Near.promiseCreateId

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def main : IO Unit := do
  /- Check 1: near.promise.create@1.0.0 is registered. -/
  let cat ← match ProofForge.Frontend.Surface.Host.Near.nearPromiseCatalog with
    | Except.ok cat => pure cat
    | Except.error e => throw <| IO.userError s!"Failed to build catalog: {repr e}"
  match cat.lookup pcId with
  | Except.ok sig =>
    require (sig.id.namespace_ == "near.promise") "namespace mismatch"
    require (sig.id.name == "create") "name mismatch"
    require (sig.id.version.major == 1) "major version mismatch"
    require (sig.id.version.minor == 0) "minor version mismatch"
    require (sig.id.version.patch == 0) "patch version mismatch"
    require (sig.params.size == 5) "param count mismatch"
    require (sig.params[0]! == .string) "param 0 should be string"
    require (sig.params[1]! == .string) "param 1 should be string"
    require (sig.params[2]! == .bytes) "param 2 should be bytes"
    require (sig.params[3]! == .u128) "param 3 should be u128"
    require (sig.params[4]! == .u64) "param 4 should be u64"
    require (sig.results.size == 1) "result count mismatch"
    require (sig.results[0]! == .u64) "result 0 should be u64"
    require (sig.effectClass == .external) "effect class should be external"
    require (sig.requiredCapabilities.contains .nearPromise)
      "should require nearPromise capability"
  | Except.error e => throw <| IO.userError s!"Lookup failed: {repr e}"

  /- Check 2: Wrong arity (4 args instead of 5). -/
  match HostOpCatalog.validateCall sig #[.string, .string, .bytes, .u128] with
  | Except.error .wrongArity => pure ()
  | _ => throw <| IO.userError "Wrong arity should fail"

  /- Check 3: u64 deposit instead of u128. -/
  match HostOpCatalog.validateCall sig #[.string, .string, .bytes, .u64, .u64] with
  | Except.error .typeMismatch => pure ()
  | _ => throw <| IO.userError "u64 deposit should fail type mismatch"

  /- Check 4: Wrong result type (u128 instead of u64). -/
  match HostOpCatalog.validateResults sig #[.u128] with
  | Except.error .resultTypeMismatch => pure ()
  | _ => throw <| IO.userError "Wrong result type should fail"

  /- Check 5: Version 1.0.1 is not in catalog. -/
  match cat.lookup { namespace_ := "near.promise", name := "create", version := { major := 1, minor := 0, patch := 1 } } with
  | Except.error _ => pure ()
  | Except.ok _ => throw <| IO.userError "Version 1.0.1 should not be found"

  /- Check 6: Render is near.promise/create@1.0.0. -/
  require (pcId.render == "near.promise/create@1.0.0")
    "render mismatch"

  /- Check 7: External effect class is valid for hostCall. -/
  match HostOpCatalog.validateCallUsage sig with
  | Except.ok _ => pure ()
  | Except.error e => throw <| IO.userError s!"External effect should be valid: {repr e}"

  /- Check 8: NEAR target has a handler for near.promise.create. -/
  require (hasHandlerFor "wasm-near" pcId)
    "wasm-near should have a handler for near.promise.create"

  /- Check 9: EVM target does NOT have a handler (missingHostOpHandler). -/
  require (!hasHandlerFor "evm" pcId)
    "EVM should NOT have a handler for near.promise.create"

  /- Check 10: Solana target does NOT have a handler (missingHostOpHandler). -/
  require (!hasHandlerFor "solana-sbpf-asm" pcId)
    "Solana should NOT have a handler for near.promise.create"

  /- Check 11: reference semantics preserve every typed argument and index. -/
  let call : HostOpCall := { id := pcId, args := #[] }
  match nearPromiseHost #[] call #[
      .string "alice.near", .string "methodName", .bytes (ByteArray.mk #[42, 7]),
      .u128 18446744073709551619, .u64 1000] with
  | .ok (.u64 0, #[trace]) =>
      require (trace.accountId == "alice.near" && trace.methodName == "methodName")
        "promise trace identity mismatch"
      require (trace.args == ByteArray.mk #[42, 7] &&
        trace.deposit == 18446744073709551619 && trace.gas == 1000)
        "promise trace payload mismatch"
  | result => throw <| IO.userError s!"promise reference semantics failed: {repr result}"

  /- Check 12: reference semantics reject unknown patch versions. -/
  let wrongVersion : HostOpCall := { call with
    id := { pcId with version := { major := 1, minor := 0, patch := 1 } } }
  match nearPromiseHost #[] wrongVersion #[] with
  | .error (.unknownHostOp id) => require (id == wrongVersion.id) "unknown HostOp id changed"
  | result => throw <| IO.userError s!"unknown promise version accepted: {repr result}"

  IO.println "near-promise-hostop: ok"
