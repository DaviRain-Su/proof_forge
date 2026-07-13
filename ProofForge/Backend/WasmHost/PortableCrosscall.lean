/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Portable crosscall → NEAR Promise materialization (Phase B.3 / D-050 Slice 3)

Authors write portable `crosscall.invoke` with address-literal indices into
`module.crosscallStrings`. EmitWat materializes that as `promise_create`.

**Portable product path (authors):**
* `crosscall.invoke` / untyped invoke only
* `crosscallStrings` host string pool (target metadata, not business logic)

**NEAR host-extension only (fixtures / advanced):**
* `nearPromiseThen`, `nearPromiseResultsCount`, `nearPromiseResultStatus`,
  `nearPromiseResultU64`, `nearCrosscallInvokePool`

These remain IR constructors for EmitWat coverage but classify as
`targetFamilyOnly .wasmHost` in `ProofForge.IR.Portability` and must not appear
in Shared portable examples.
-/
import ProofForge.IR.Contract
import ProofForge.IR.Portability

namespace ProofForge.Backend.WasmHost.PortableCrosscall

open ProofForge.IR
open ProofForge.IR.Portability

private def isPromiseExtensionFinding (f : PortabilityFinding) : Bool :=
  match f.class_ with
  | .targetFamilyOnly .wasmHost =>
      f.detail.startsWith "nearPromise" || f.detail.startsWith "nearCrosscallInvokePool"
  | _ => false

/-- True when the module uses NEAR-only Promise constructors (host extension). -/
def moduleUsesPromiseExtension (module : Module) : Bool :=
  (classifyModule module).any isPromiseExtensionFinding

/-- True when the module uses portable `crosscall.invoke` (family-shared)
without requiring Promise host-extension constructors. -/
def moduleUsesPortableInvoke (module : Module) : Bool :=
  let findings := classifyModule module
  findings.any (fun f => f.detail.startsWith "crosscall.invoke") &&
    !(findings.any isPromiseExtensionFinding)

def materializationNote (module : Module) : String :=
  if moduleUsesPromiseExtension module then
    "NEAR host-extension: promise_then / result decode present (not portable product path)"
  else if moduleUsesPortableInvoke module then
    "portable crosscall.invoke → promise_create (crosscallStrings indices)"
  else if !module.crosscallStrings.isEmpty then
    "crosscallStrings present without portable invoke body"
  else
    "no portable NEAR crosscall sites"

/-- Soroban host-adapter note (not NEAR Promise). -/
def sorobanMaterializationNote (module : Module) : String :=
  if moduleUsesPromiseExtension module then
    "Soroban: NEAR Promise constructors unsupported on this host bridge"
  else if moduleUsesPortableInvoke module then
    "Soroban: portable crosscall.invoke → invoke_contract (soroban-invoke; crosscallStrings pool)"
  else
    "Soroban: no portable crosscall sites (storage/auth host surface only)"

/-- CosmWasm host-adapter note (general peer remote, not token-only). -/
def cosmWasmMaterializationNote (module : Module) : String :=
  if moduleUsesPromiseExtension module then
    "CosmWasm: NEAR Promise constructors unsupported on this host bridge"
  else if moduleUsesPortableInvoke module then
    "CosmWasm SPIKE: portable crosscall.invoke → execute_msg (WasmMsg-shaped STUB — not full CosmWasm submessages; Gate G1a not started)"
  else
    "CosmWasm: no portable crosscall sites (db storage surface only)"

end ProofForge.Backend.WasmHost.PortableCrosscall
