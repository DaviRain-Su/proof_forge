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

  -- Determinism on second write.
  let core1 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/core.v0.json")
  require ((← exportCoreCommand counterOpts) == 0) "counter re-export failed"
  let core2 ← IO.FS.readFile (System.FilePath.mk "build/export/lr1b-counter/evm/core.v0.json")
  require (core1 == core2) "counter core.v0.json not deterministic"

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

  IO.println "core-export-package: ok (counter + value-vault + product Counter)"
  pure 0

end ProofForge.Tests.Canonical.CoreExportPackage

unsafe def main : IO UInt32 :=
  ProofForge.Tests.Canonical.CoreExportPackage.main
