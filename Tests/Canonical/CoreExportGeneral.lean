/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-1d: general Seam A export properties (not one-off examples)

1. Primary-triad multi-target: same Core body across targets; plans differ.
2. Package always carries interface.v0 + targetHostOpCatalog.
3. Data-driven product smoke (catalog products) exercises the general path.
-/
import ProofForge.Cli.ExportCore

namespace ProofForge.Tests.Canonical.CoreExportGeneral

open ProofForge.Cli.ExportCore

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def triad : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

/-- Portable product sources used as smoke for the *general* path (not features).
Drawn from catalog products that claim primary-triad support; the list is a
smoke matrix, not an exhaustive catalog sweep. -/
def productSmoke : Array String := #[
  "Examples/Product/Counter.lean",
  "Examples/Product/ValueVault.lean",
  "Examples/Product/Ownable.lean",
  "Examples/Product/Pausable.lean",
  "Examples/Product/GuestBook.lean"
]

def corePath (stem target : String) : System.FilePath :=
  System.FilePath.mk s!"build/export/lr1d-{stem}/{target}/core.v0.json"

def planPath (stem target : String) : System.FilePath :=
  System.FilePath.mk s!"build/export/lr1d-{stem}/{target}/capability-plan.v0.json"

def ifacePath (stem target : String) : System.FilePath :=
  System.FilePath.mk s!"build/export/lr1d-{stem}/{target}/interface.v0.json"

def stemOf (product : String) : String :=
  let base := product.splitOn "/" |>.getLast!
  if base.endsWith ".lean" then
    (base.dropEnd 5).toString
  else base

unsafe def exportProduct (product target : String) : IO Unit := do
  let stem := stemOf product
  let out := s!"build/export/lr1d-{stem.toLower}/{target}"
  let opts ← match parseExportCoreOptions
      ["--experimental", "--target", target, "-o", out, product] with
    | .error msg => throw (IO.userError s!"parse {product}@{target}: {msg}")
    | .ok o => pure o
  let code ← exportCoreCommand opts
  require (code == 0) s!"export failed {product}@{target} exit={code}"
  require (← (corePath stem.toLower target).pathExists) s!"missing core {stem}@{target}"
  require (← (planPath stem.toLower target).pathExists) s!"missing plan {stem}@{target}"
  require (← (ifacePath stem.toLower target).pathExists) s!"missing interface {stem}@{target}"

unsafe def main : IO UInt32 := do
  -- General catalogs for primary triad are non-empty.
  for t in triad do
    let cat := targetHostOpCatalog t
    require (cat.size > 0) s!"targetHostOpCatalog empty for {t}"

  -- Multi-target Core identity: prove once on Counter (full triad).
  for t in triad do
    exportProduct "Examples/Product/Counter.lean" t
  let coreEvm ← IO.FS.readFile (corePath "counter" "evm")
  let coreSol ← IO.FS.readFile (corePath "counter" "solana-sbpf-asm")
  let coreNear ← IO.FS.readFile (corePath "counter" "wasm-near")
  require (coreEvm == coreSol && coreSol == coreNear)
    "Core must be target-neutral (identical body across triad)"
  let planEvm ← IO.FS.readFile (planPath "counter" "evm")
  let planSol ← IO.FS.readFile (planPath "counter" "solana-sbpf-asm")
  require (planEvm.contains "\"targetId\": \"evm\"") "evm plan target"
  require (planSol.contains "\"targetId\": \"solana-sbpf-asm\"") "solana plan target"
  require (planEvm.contains "targetHostOpCatalog") "general target catalog in plan"
  require (planEvm.contains "\"requirements\"") "requirements in plan"
  let iface ← IO.FS.readFile (ifacePath "counter" "evm")
  require (iface.contains "\"interfaceSchema\": \"interface.v0\"") "interface schema"
  require (iface.contains "initialize" || iface.contains "\"name\"") "interface entrypoints"

  -- Second product on triad (stateful) without exploding the matrix.
  for t in triad do
    exportProduct "Examples/Product/ValueVault.lean" t
  let vvE ← IO.FS.readFile (corePath "valuevault" "evm")
  let vvS ← IO.FS.readFile (corePath "valuevault" "solana-sbpf-asm")
  let vvN ← IO.FS.readFile (corePath "valuevault" "wasm-near")
  require (vvE == vvS && vvS == vvN) "ValueVault Core must match across triad"

  -- Broader product smoke on a single target (proves path is not Counter-special).
  -- Full product×triad is too heavy for lean --run memory; keep that for CI lanes later.
  for product in productSmoke do
    exportProduct product "evm"
    let stem := (stemOf product).toLower
    let plan ← IO.FS.readFile (planPath stem "evm")
    require (plan.contains "targetHostOpCatalog") s!"{product} missing target catalog"
    let core ← IO.FS.readFile (corePath stem "evm")
    require (core.contains "\"coreSchema\": \"core.v0\"") s!"{product} bad core schema"

  IO.println s!"core-export-general: ok (Counter+ValueVault triad identity + {productSmoke.size} evm product smokes)"
  pure 0

end ProofForge.Tests.Canonical.CoreExportGeneral

unsafe def main : IO UInt32 :=
  ProofForge.Tests.Canonical.CoreExportGeneral.main
