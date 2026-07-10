/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Three-host client schema parity (U6.4)

Locks the **shared product contract** for clients:

1. **Entrypoint names** are identical across SdkSchema (evm / solana-sbpf-asm /
   wasm-near) and match the IR module (Product Counter: initialize, increment, get).
2. **Error catalogue** uses the same `assertionId` + `userCode` on EVM TS,
   NEAR TS, Solana IDL/client, and SdkSchema (ErrorRefProbe).
3. Shared lookup helper name: `errorByAssertionId` on all three TS surfaces.

Does **not** force host-specific decode helpers to share one name
(`decodeProofForgeRevert` vs `parseProofForgePanic` vs `errorBySolanaCustomCode`)
— those stay host-idiomatic; only the catalogue ids and entrypoint names unify.
-/
import Examples.Product.Counter
import ProofForge.Contract.Client
import ProofForge.Contract.Spec
import ProofForge.Contract.SdkSchema
import ProofForge.Backend.Solana.Client
import ProofForge.Backend.Solana.Idl
import ProofForge.IR.Examples.ErrorRefProbe

namespace ProofForge.Tests.ClientSchemaParity

open ProofForge.Contract
open ProofForge.IR

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def renderEvm (spec : ContractSpec) (name : String) : IO String :=
  match ProofForge.Contract.Client.renderEvmAbiWrapper spec name with
  | .ok wrapper => pure wrapper
  | .error err => throw <| IO.userError s!"EVM client render failed: {err}"

def counterModule : Module := Examples.Product.Counter.module
def counterSpec : ContractSpec := ContractSpec.fromIR counterModule
def errorSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module

/-- Extract `"name": "…"` entries under entrypoints-ish JSON (loose). -/
def hasEntrypointName (json name : String) : Bool :=
  contains json s!"\"name\": \"{name}\""

def testSdkSchemaEntrypointNames : IO Unit := do
  let expected := #["initialize", "increment", "get"]
  for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let json ← match SdkSchema.render targetId counterSpec #[] #[] with
      | .ok j => pure j
      | .error e => throw (IO.userError s!"SdkSchema {targetId}: {e}")
    require (contains json "\"entrypoints\"") s!"{targetId} missing entrypoints"
    for name in expected do
      require (hasEntrypointName json name)
        s!"{targetId} sdk-schema missing entrypoint name {name}"
    -- parity: same three names, no host rename
    require (contains json (s!"\"target\": \"{targetId}\""))
      s!"{targetId} schema target field"

def testTsClientEntrypointNames : IO Unit := do
  let evm ← renderEvm counterSpec "Counter"
  let near := ProofForge.Contract.Client.renderNearWrapper counterSpec
  let sol := ProofForge.Backend.Solana.Client.render counterModule
  for name in #["initialize", "increment", "get"] do
    require (contains evm s!"export async function {name}")
      s!"EVM client missing function {name}"
    require (contains near s!"export async function {name}")
      s!"NEAR client missing function {name}"
  -- Solana uses IDL instruction names, not per-export functions
  let idl := ProofForge.Backend.Solana.Idl.render counterModule
  for name in #["initialize", "increment", "get"] do
    require (contains idl s!"\"name\": \"{name}\"")
      s!"Solana IDL missing instruction {name}"
  require (contains sol "InstructionName")
    "Solana client should expose InstructionName from IDL"

def testErrorCatalogueParity : IO Unit := do
  let evm ← renderEvm errorSpec "ErrorRefProbe"
  let near := ProofForge.Contract.Client.renderNearWrapper errorSpec
  let sol := ProofForge.Backend.Solana.Client.render errorSpec.module
  let idl := ProofForge.Backend.Solana.Idl.render errorSpec.module
  for surface in #[("EVM", evm), ("NEAR", near), ("Solana client", sol)] do
    require (contains surface.snd "errorByAssertionId")
      s!"{surface.fst} missing shared errorByAssertionId"
    require (contains surface.snd "\"assertionId\": 1")
      s!"{surface.fst} missing assertionId 1"
    require (contains surface.snd "\"assertionId\": 2")
      s!"{surface.fst} missing assertionId 2"
    require (contains surface.snd "Counter::Overflow")
      s!"{surface.fst} missing Counter::Overflow"
    require (contains surface.snd "Counter::ExactMatch")
      s!"{surface.fst} missing Counter::ExactMatch"
  require (contains idl "\"assertionId\": 1") "Solana IDL missing id 1"
  require (contains idl "\"assertionId\": 2") "Solana IDL missing id 2"
  -- Host-specific decoders stay distinct (U6.4 non-goal: one decode name)
  require (contains evm "decodeProofForgeRevert") "EVM host decoder"
  require (contains near "parseProofForgePanic") "NEAR host decoder"
  require (contains sol "errorBySolanaCustomCode") "Solana host decoder"

def testSdkSchemaErrorsOnAllTargets : IO Unit := do
  for targetId in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let json ← match SdkSchema.render targetId errorSpec #[] #[] with
      | .ok j => pure j
      | .error e => throw (IO.userError s!"SdkSchema errors {targetId}: {e}")
    require (contains json "\"errors\"") s!"{targetId} missing errors array"
    require (contains json "\"assertionId\": 1") s!"{targetId} errors id 1"
    require (contains json "Counter::Overflow") s!"{targetId} Overflow userCode"

def main : IO UInt32 := do
  testSdkSchemaEntrypointNames
  testTsClientEntrypointNames
  testErrorCatalogueParity
  testSdkSchemaErrorsOnAllTargets
  IO.println
    "client-schema-parity: ok (entrypoints · assertionId · errorByAssertionId × triad)"
  pure 0

end ProofForge.Tests.ClientSchemaParity

def main : IO UInt32 :=
  ProofForge.Tests.ClientSchemaParity.main
