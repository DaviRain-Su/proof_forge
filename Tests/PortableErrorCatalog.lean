/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

T3.4: same assertionId catalogue surfaces on EVM · Solana · NEAR clients and
shared contract-spec / SDK schema (ErrorRefProbe fixture).
-/
import ProofForge.Contract.Client
import ProofForge.Contract.Spec
import ProofForge.Contract.Spec.Json
import ProofForge.Contract.SdkSchema
import ProofForge.Backend.Solana.Client
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.Layout
import ProofForge.IR.Examples.ErrorRefProbe

namespace ProofForge.Tests.PortableErrorCatalog

open ProofForge.Contract
open ProofForge.Contract.Spec.Json
open ProofForge.Backend.WasmHost.Layout

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def module : ProofForge.IR.Module :=
  ProofForge.IR.Examples.ErrorRefProbe.module

def spec : ContractSpec :=
  ContractSpec.fromIR module

/-- Canonical catalogue: assertion ids 1/2 with stable user codes. -/
def testCanonicalCatalog : IO Unit := do
  let catalog := errorCatalog module
  require (catalog.size == 2)
    s!"ErrorRefProbe catalogue should have 2 entries, got {catalog.size}"
  let overflow? := catalog.find? (fun e => e.assertionId == 1)
  let exact? := catalog.find? (fun e => e.assertionId == 2)
  match overflow? with
  | none => throw <| IO.userError "missing assertionId 1 (Counter::Overflow)"
  | some e =>
      require (e.userCode? == some "Counter::Overflow") "id 1 userCode"
      require (e.message == "count must be under five") "id 1 message"
      require (e.entrypoints == #["guarded_increment"]) "id 1 entrypoints"
  match exact? with
  | none => throw <| IO.userError "missing assertionId 2 (Counter::ExactMatch)"
  | some e =>
      require (e.userCode? == some "Counter::ExactMatch") "id 2 userCode"
      require (e.message == "count must equal seven") "id 2 message"
      require (e.entrypoints == #["exact_increment"]) "id 2 entrypoints"

def requireSharedIds (label body : String) : IO Unit := do
  require (contains body "\"assertionId\": 1") s!"{label} missing assertionId 1"
  require (contains body "\"assertionId\": 2") s!"{label} missing assertionId 2"
  require (contains body "Counter::Overflow") s!"{label} missing Counter::Overflow"
  require (contains body "Counter::ExactMatch") s!"{label} missing Counter::ExactMatch"
  require (contains body "errorByAssertionId") s!"{label} missing errorByAssertionId"

/-- EVM TS wrapper: ERRORS + decodeProofForgeRevert share the same ids. -/
def testEvmClient : IO Unit := do
  let wrapper ← match ProofForge.Contract.Client.renderEvmAbiWrapper spec "ErrorRefProbe" with
    | .ok wrapper => pure wrapper
    | .error err => throw <| IO.userError s!"EVM client render failed: {err}"
  requireSharedIds "EVM client" wrapper
  require (contains wrapper "decodeProofForgeRevert")
    "EVM client missing decodeProofForgeRevert"
  require (contains wrapper "uint32")
    "EVM client missing uint32 assertionId ABI decode"

/-- NEAR TS wrapper: ERRORS + parseProofForgePanic (PF:id:code). -/
def testNearClient : IO Unit := do
  let wrapper := ProofForge.Contract.Client.renderNearWrapper spec
  requireSharedIds "NEAR client" wrapper
  require (contains wrapper "parseProofForgePanic")
    "NEAR client missing parseProofForgePanic"
  require (contains wrapper "PF:(\\d+):([^\\s]+)")
    "NEAR client missing PF:id:code panic parser"

/-- Solana IDL + client: same catalogue + custom-error decode. -/
def testSolanaClient : IO Unit := do
  let idl := ProofForge.Backend.Solana.Idl.render module
  require (contains idl "\"errors\": [") "Solana IDL missing errors array"
  require (contains idl "\"assertionId\": 1") "Solana IDL missing id 1"
  require (contains idl "\"assertionId\": 2") "Solana IDL missing id 2"
  require (contains idl "Counter::Overflow") "Solana IDL missing Overflow"
  require (contains idl "Counter::ExactMatch") "Solana IDL missing ExactMatch"
  let client := ProofForge.Backend.Solana.Client.render module
  requireSharedIds "Solana client" client
  require (contains client "errorBySolanaCustomCode")
    "Solana client missing custom-error helper"
  require (contains client "0x100000000n")
    "Solana client missing 2^32+assertionId normalization"

/-- SdkSchema embeds the same errors array for the three primary SDK targets. -/
def testSdkSchemaTargets : IO Unit := do
  for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let json ← match SdkSchema.render targetId spec #[] #[] with
      | .ok j => pure j
      | .error e => throw <| IO.userError s!"SdkSchema.render {targetId}: {e}"
    require (contains json "\"errors\":") s!"{targetId} sdk-schema missing errors"
    require (contains json "\"assertionId\": 1") s!"{targetId} sdk-schema missing id 1"
    require (contains json "\"assertionId\": 2") s!"{targetId} sdk-schema missing id 2"
    require (contains json "Counter::Overflow") s!"{targetId} sdk-schema missing Overflow"
    require (contains json "Counter::ExactMatch") s!"{targetId} sdk-schema missing ExactMatch"

/-- EmitWat (NEAR/Soroban host path) embeds PF:assertionId:userCode panic strings. -/
def testEmitWatPanicFormat : IO Unit := do
  require (panicMessage { assertionId := 1, userCode? := some "Counter::Overflow" } ==
      "PF:1:Counter::Overflow")
    "panicMessage format for id 1"
  require (panicMessage { assertionId := 2, userCode? := some "Counter::ExactMatch" } ==
      "PF:2:Counter::ExactMatch")
    "panicMessage format for id 2"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule module with
  | .error e => throw <| IO.userError s!"EmitWat ErrorRefProbe: {e.message}"
  | .ok wat =>
      require (contains wat "PF:1:Counter::Overflow")
        "WAT missing PF:1:Counter::Overflow panic string"
      require (contains wat "PF:2:Counter::ExactMatch")
        "WAT missing PF:2:Counter::ExactMatch panic string"

def main : IO UInt32 := do
  testCanonicalCatalog
  testEvmClient
  testNearClient
  testSolanaClient
  testSdkSchemaTargets
  testEmitWatPanicFormat
  IO.println "portable-error-catalog: ok (evm · solana · near · emitwat PF ids)"
  return 0

end ProofForge.Tests.PortableErrorCatalog

def main : IO UInt32 :=
  ProofForge.Tests.PortableErrorCatalog.main
