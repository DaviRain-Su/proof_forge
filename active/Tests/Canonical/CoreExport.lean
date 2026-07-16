/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-1a: experimental core.v0 export gate

Valid modules export; invalid modules fail closed with no semantic body.
-/
import ProofForge.IR.Core.Export

namespace ProofForge.Tests.Canonical.CoreExport

open ProofForge.IR.Core
open ProofForge.IR.Core.Export

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

/-- Tiny validated Core module: one function returning constant 0. -/
def tinyModule : Module := {
  name := "TinyCounter"
  state := #[{ id := ⟨0⟩, shape := .scalar .u64 }]
  functions := #[{
    id := ⟨0⟩
    params := #[]
    retType := .u64
    entry := ⟨0⟩
    blocks := #[{
      id := ⟨0⟩
      instructions := #[
        {
          results := #[{ id := ⟨0⟩, type := .u64 }]
          op := .pure (.literal (.u64Lit 0))
        }
      ]
      terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
    }]
  }]
}

/-- Invalid: empty functions with claimed state only is ok, but unknown jump is not. -/
def invalidJumpModule : Module := {
  name := "BadJump"
  functions := #[{
    id := ⟨0⟩
    params := #[]
    retType := .unit
    entry := ⟨0⟩
    blocks := #[{
      id := ⟨0⟩
      instructions := #[]
      terminator := .jump ⟨99⟩ #[] none
    }]
  }]
}

def main : IO UInt32 := do
  require (coreSchema == "core.v0") "coreSchema drift"
  require (envelopeSchemaVersion == 0) "envelope schema drift"

  match exportModuleJson tinyModule with
  | .error err => throw (IO.userError s!"tiny export failed: {err.message}")
  | .ok json => do
      require (json.contains "\"coreSchema\": \"core.v0\"") "missing coreSchema"
      require (json.contains "\"name\": \"TinyCounter\"") "missing module name"
      require (json.contains "\"kind\": \"u64\"") "missing u64 type"
      require (json.contains "\"kind\": \"literal\"") "missing literal op"
      -- Determinism: second export is byte-identical.
      match exportModuleJson tinyModule with
      | .error err => throw (IO.userError err.message)
      | .ok json2 =>
          require (json == json2) "core export not deterministic"

  match exportModuleJson invalidJumpModule with
  | .ok _ => throw (IO.userError "invalid module must not export")
  | .error err =>
      require (err.message.contains "core export refused")
        s!"expected refuse diagnostic, got {err.message}"

  let cap := capabilityPlanJson "evm" #["storage.scalar"]
    #[{ capability := "storage.scalar", operation := "storage.scalar" }]
    #[] #[]
  require (cap.contains "capability-plan.v0") "capability plan schema"
  require (cap.contains "\"targetId\": \"evm\"") "capability plan target"
  require (cap.contains "\"hostOpHandlers\": []") "empty used handlers"
  require (cap.contains "\"targetHostOpCatalog\": []") "empty catalog ok in unit test"
  require (cap.contains "\"requirements\"") "requirements array"

  -- Used host-op collector + handler row shape.
  let hostMod : Module := {
    name := "HostProbe"
    functions := #[{
      id := ⟨0⟩, params := #[], retType := .u64, entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        instructions := #[{
          results := #[{ id := ⟨0⟩, type := .u64 }]
          op := .hostCall {
            id := {
              namespace_ := "evm.context", name := "origin"
              version := { major := 1, minor := 0, patch := 0 }
            }
            args := #[]
          }
        }]
        terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
      }]
    }]
  }
  let used := collectUsedHostOpIds hostMod
  require (used.size == 1) "one used host op"
  let originId := {
    namespace_ := "evm.context", name := "origin"
    version := { major := 1, minor := 0, patch := 0 }
  }
  require (used.any (· == originId)) "origin host op collected"
  let handlers : Array HostOpHandlerEntry := #[{
    id := originId
    available := true
    handler := "evm:evm.context/origin@1.0.0"
    requiredCapabilities := #["caller.sender"]
  }]
  let cap2 := capabilityPlanJson "evm" #[] #[] handlers handlers
  require (cap2.contains "\"available\": true") "handler available"
  require (cap2.contains "origin") "handler id"
  require (cap2.contains "targetHostOpCatalog") "target catalog field"

  IO.println "core-export-v0: ok (tiny validated export + invalid refuse)"
  pure 0

end ProofForge.Tests.Canonical.CoreExport

def main : IO UInt32 :=
  ProofForge.Tests.Canonical.CoreExport.main
