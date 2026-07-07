/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic

namespace ProofForge.Backend.WasmNear.Diagnostics

/-! Diagnostic messages and error wrapper shared by the wasm-near emitter. -/

def nativeValueUnsupportedMessage : String :=
  "EmitWat: NEAR native value (attached deposit) requires an exact U128 projection; IR v0 cannot lower nativeValue yet"

def indexedEventUnsupportedMessage (name : String) : String :=
  s!"EmitWat: event `{name}` uses indexed fields, but NEAR logs do not support EVM-style topic indexing"

def crosscallUnsupportedMessage : String :=
  "EmitWat: crosscall.invoke maps to NEAR Promise-based execution, but EmitWat v0 has no Promise lowering yet"

def crosscallEvmOnlyMessage (kind : String) : String :=
  s!"EmitWat: NEAR crosscall does not support `{kind}`; use `crosscallInvoke` with `nearCrosscallStrings` address literals"

def crosscallTypedUnsupportedMessage : String :=
  "EmitWat: typed crosscall is not supported on NEAR; use untyped `crosscallInvoke`"

structure EmitError where
  message : String
  deriving Repr, Inhabited

instance : ProofForge.Backend.Diagnostic.LoweringError EmitError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "wasm-near" }

def err (msg : String) : Except EmitError α := .error { message := msg }

end ProofForge.Backend.WasmNear.Diagnostics
