/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-1b: write experimental export package + refuse without experimental CLI flag
-/
import ProofForge.Cli.ExportCore
import ProofForge.Contract.Spec
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Examples.Counter

namespace ProofForge.Tests.Canonical.CoreExportPackage

open ProofForge.Cli.ExportCore

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO UInt32 := do
  -- CLI parse fail-closed without --experimental.
  match parseExportCoreOptions ["--target", "evm", "--fixture", "counter", "-o", "build/x"] with
  | .ok _ => throw (IO.userError "expected --experimental required")
  | .error msg =>
      require (msg.contains "--experimental") s!"unexpected parse error: {msg}"

  let opts ← match parseExportCoreOptions
      ["--experimental", "--target", "evm", "--fixture", "counter",
       "-o", "build/export/lr1b-counter/evm"] with
    | .error msg => throw (IO.userError s!"parse failed: {msg}")
    | .ok opts => pure opts
  let code ← exportCoreCommand opts
  require (code == 0) s!"exportCoreCommand exit {code}"

  let corePath := System.FilePath.mk "build/export/lr1b-counter/evm/core.v0.json"
  let capPath := System.FilePath.mk "build/export/lr1b-counter/evm/capability-plan.v0.json"
  let metaPath := System.FilePath.mk "build/export/lr1b-counter/evm/export-meta.json"
  require (← corePath.pathExists) "missing core.v0.json"
  require (← capPath.pathExists) "missing capability-plan.v0.json"
  require (← metaPath.pathExists) "missing export-meta.json"
  let coreText ← IO.FS.readFile corePath
  require (coreText.contains "\"coreSchema\": \"core.v0\"") "core schema"
  require (coreText.contains "\"name\": \"Counter\"") "counter module name"
  let metaText ← IO.FS.readFile metaPath
  require (metaText.contains "\"contentHash\"") "meta contentHash"
  require (!metaText.contains "\"contentHash\": \"unset\"") "contentHash should be set"

  -- Second export is byte-identical for core body.
  let code2 ← exportCoreCommand opts
  require (code2 == 0) "second export failed"
  let coreText2 ← IO.FS.readFile corePath
  require (coreText == coreText2) "core.v0.json not deterministic across writes"

  IO.println "core-export-package: ok (counter → package + experimental gate)"
  pure 0

end ProofForge.Tests.Canonical.CoreExportPackage

def main : IO UInt32 :=
  ProofForge.Tests.Canonical.CoreExportPackage.main
