/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic

namespace ProofForge.Backend.WasmHost.Diagnostics

/-! Diagnostic messages and error wrapper shared by the wasm-near emitter. -/

def nativeValueUnsupportedMessage : String :=
  "EmitWat: NEAR native value (attached deposit) requires an exact U128 projection; IR v0 cannot lower nativeValue yet"

def indexedEventUnsupportedMessage (name : String) : String :=
  s!"EmitWat: event `{name}` uses indexed fields, but NEAR logs do not support EVM-style topic indexing"

def crosscallUnsupportedMessage : String :=
  "EmitWat: portable crosscall.invoke materializes as NEAR promise_create; populate module.crosscallStrings with account/method names (address-literal indices)"

def crosscallEvmOnlyMessage (kind : String) : String :=
  s!"EmitWat: NEAR does not support `{kind}` (EVM-only); use portable `crosscallInvoke` with crosscallStrings address literals → promise_create"

def crosscallTypedUnsupportedMessage : String :=
  "EmitWat: typed crosscall returns are not supported on NEAR; use untyped `crosscallInvoke` (Promise materialization returns promise id u64)"

/-- NEAR Promise host-extension constructors never lower on Soroban. Portable
`crosscall.invoke` materializes as `invoke_contract` instead of `promise_create`. -/
def sorobanNearPromiseUnsupportedMessage : String :=
  "EmitWat: NEAR Promise constructors are not materializable on Soroban host bridge; use portable crosscall.invoke → soroban-invoke (`invoke_contract`)"

structure EmitError where
  message : String
  deriving Repr, Inhabited

instance : ProofForge.Backend.Diagnostic.LoweringError EmitError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "wasm-near" }

def err (msg : String) : Except EmitError α := .error { message := msg }

end ProofForge.Backend.WasmHost.Diagnostics
