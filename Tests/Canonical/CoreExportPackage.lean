/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-1b: export-core package for fixtures + product Counter (experimental)
-/
import ProofForge.Cli.ExportCore

namespace ProofForge.Tests.Canonical.CoreExportPackage

open ProofForge.Cli.ExportCore

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def requireFileContains (path : System.FilePath) (needle : String) : IO Unit := do
  require (← path.pathExists) s!"missing {path}"
  let text ← IO.FS.readFile path
  require (text.contains needle) s!"{path} missing `{needle}`"

unsafe def main : IO UInt32 := do
  -- CLI parse fail-closed without --experimental.
  match parseExportCoreOptions ["--target", "evm", "--fixture", "counter", "-o", "build/x"] with
  | .ok _ => throw (IO.userError "expected --experimental required")
  | .error msg =>
      require (msg.contains "--experimental") s!"unexpected parse error: {msg}"

  -- Fixture: counter
  let counterOpts ← match parseExportCoreOptions
      ["--experimental", "--target", "evm", "--fixture", "counter",
       "-o", "build/export/lr1b-counter/evm"] with
    | .error msg => throw (IO.userError s!"counter parse failed: {msg}")
    | .ok opts => pure opts
  require ((← exportCoreCommand counterOpts) == 0) "counter export failed"
  requireFileContains (System.FilePath.mk "build/export/lr1b-counter/evm/core.v0.json")
    "\"name\": \"Counter\""
  requireFileContains (System.FilePath.mk "build/export/lr1b-counter/evm/export-meta.json")
    "\"contentHash\""

  -- Determinism on second write (Core body + contentHash + capability plan).
  let core1 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/core.v0.json")
  let plan1 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/capability-plan.v0.json")
  let meta1 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/export-meta.json")
  require ((← exportCoreCommand counterOpts) == 0) "counter re-export failed"
  let core2 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/core.v0.json")
  let plan2 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/capability-plan.v0.json")
  let meta2 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/export-meta.json")
  require (core1 == core2) "counter core.v0.json not deterministic"
  require (plan1 == plan2) "counter capability-plan.v0.json not deterministic"
  require (meta1 == meta2) "counter export-meta.json (contentHash) not deterministic"

  -- Fixture: value-vault (stateful subset)
  let vaultOpts ← match parseExportCoreOptions
      ["--experimental", "--target", "evm", "--fixture", "value-vault",
       "-o", "build/export/lr1b-value-vault/evm"] with
    | .error msg => throw (IO.userError s!"value-vault parse failed: {msg}")
    | .ok opts => pure opts
  require ((← exportCoreCommand vaultOpts) == 0) "value-vault export failed"
  requireFileContains (System.FilePath.mk "build/export/lr1b-value-vault/evm/core.v0.json")
    "\"name\": \"ValueVault\""
  requireFileContains (System.FilePath.mk "build/export/lr1b-value-vault/evm/capability-plan.v0.json")
    "\"targetId\": \"evm\""

  -- Product source: Examples/Product/Counter.lean (contract_source → Core)
  let productOpts ← match parseExportCoreOptions
      ["--experimental", "--target", "evm",
       "-o", "build/export/lr1b-product-counter/evm",
       "Examples/Product/Counter.lean"] with
    | .error msg => throw (IO.userError s!"product parse failed: {msg}")
    | .ok opts => pure opts
  require ((← exportCoreCommand productOpts) == 0) "product Counter export failed"
  requireFileContains (System.FilePath.mk "build/export/lr1b-product-counter/evm/core.v0.json")
    "\"coreSchema\": \"core.v0\""
  requireFileContains (System.FilePath.mk "build/export/lr1b-product-counter/evm/source-manifest.json")
    "contract-source"
  requireFileContains (System.FilePath.mk "build/export/lr1b-product-counter/evm/source-manifest.json")
    "Examples/Product/Counter.lean"
  -- Counter has no hostCalls; handlers array is present and empty.
  requireFileContains (System.FilePath.mk "build/export/lr1b-product-counter/evm/capability-plan.v0.json")
    "\"hostOpHandlers\""

  -- Product ValueVault (stateful)
  let productVaultOpts ← match parseExportCoreOptions
      ["--experimental", "--target", "evm",
       "-o", "build/export/lr1b-product-value-vault/evm",
       "Examples/Product/ValueVault.lean"] with
    | .error msg => throw (IO.userError s!"product vault parse failed: {msg}")
    | .ok opts => pure opts
  require ((← exportCoreCommand productVaultOpts) == 0) "product ValueVault export failed"
  requireFileContains (System.FilePath.mk "build/export/lr1b-product-value-vault/evm/core.v0.json")
    "\"name\": \"ValueVault\""
  requireFileContains (System.FilePath.mk "build/export/lr1b-product-value-vault/evm/capability-plan.v0.json")
    "\"targetId\": \"evm\""

  -- resolveHostOpHandlers fail-closed when target lacks a used host op.
  let hostOnly : ProofForge.IR.Core.Module := {
    name := "NearOnly"
    functions := #[{
      id := ⟨0⟩, params := #[], retType := .string, entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        instructions := #[{
          results := #[{ id := ⟨0⟩, type := .string }]
          op := .hostCall {
            id := {
              namespace_ := "near.context", name := "predecessor_account_id"
              version := { major := 1, minor := 0, patch := 0 }
            }
            args := #[]
          }
        }]
        terminator := .return #[{ id := ⟨0⟩, type := .string }]
      }]
    }]
  }
  match resolveHostOpHandlers hostOnly "evm" with
  | .ok _ => throw (IO.userError "NEAR host op must not resolve on evm")
  | .error msg =>
      require (msg.contains "no handler") s!"unexpected resolve error: {msg}"
  match resolveHostOpHandlers hostOnly "wasm-near" with
  | .error msg => throw (IO.userError s!"NEAR host op should resolve on wasm-near: {msg}")
  | .ok handlers =>
      require (handlers.size == 1) "expected one NEAR handler"
      require (handlers.any (·.available)) "expected available NEAR handler"

  IO.println "core-export-package: ok (fixtures + product Counter/ValueVault + hostOp handlers)"
  pure 0

end ProofForge.Tests.Canonical.CoreExportPackage

unsafe def main : IO UInt32 :=
  ProofForge.Tests.Canonical.CoreExportPackage.main
