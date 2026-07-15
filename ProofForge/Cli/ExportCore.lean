/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Experimental `export-core` CLI (LR-1b / D-057 Seam A)

Writes a versioned Core export package after Authored→Core normalize + Validate.
**Not** a product build path: requires `--experimental` and does not lower to
target plans or bytecode.

```
proof-forge export-core --experimental --target evm --fixture counter \
  -o build/export/counter/evm
```
-/
import ProofForge.Cli.Artifact
import ProofForge.Cli.HexUtil
import ProofForge.Cli.Process
import ProofForge.Contract.Spec
import ProofForge.Frontend.Authored.Normalize
import ProofForge.IR.Core.Export
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Target

open System
open ProofForge.Cli.HexUtil
open ProofForge.IR.Core.Export

namespace ProofForge.Cli.ExportCore

structure ExportCoreOptions where
  experimental : Bool := false
  targetId : String := ""
  fixture? : Option String := none
  output? : Option FilePath := none
  root? : Option FilePath := none
  deriving Repr

def usage : String :=
  String.intercalate "\n" [
    "proof-forge export-core — experimental core.v0 package (D-057 / LR-1b)",
    "",
    "  REQUIRED: --experimental",
    "  proof-forge export-core --experimental --target <id> --fixture <id> -o DIR",
    "",
    "Fixtures (IR → Canonical Core): counter | value-vault",
    "Targets: any public id (recorded in capability-plan; handlers still stub)",
    "",
    "Writes DIR/{core.v0.json,capability-plan.v0.json,export-meta.json,source-manifest.json}",
    "Does NOT build target plans or bytecode. Not a product compile path."
  ]

def parseExportCoreOptions (args : List String) : Except String ExportCoreOptions := do
  let rec loop (args : List String) (acc : ExportCoreOptions) : Except String ExportCoreOptions :=
    match args with
    | [] => pure acc
    | "--experimental" :: rest => loop rest { acc with experimental := true }
    | "--target" :: tid :: rest =>
        if tid.isEmpty then throw "--target requires a non-empty id"
        else loop rest { acc with targetId := tid }
    | "--fixture" :: fid :: rest =>
        if fid.isEmpty then throw "--fixture requires a non-empty id"
        else loop rest { acc with fixture? := some fid }
    | "-o" :: path :: rest | "--output" :: path :: rest =>
        loop rest { acc with output? := some (FilePath.mk path) }
    | "--root" :: path :: rest =>
        loop rest { acc with root? := some (FilePath.mk path) }
    | "--help" :: _ | "-h" :: _ => throw "help"
    | other :: _ => throw s!"unknown export-core argument `{other}`"
  let opts ← loop args {}
  if !opts.experimental then
    throw "export-core requires --experimental (not a product path; see D-057)"
  if opts.targetId.isEmpty then
    throw "export-core requires --target <id>"
  if opts.fixture?.isNone then
    throw "export-core requires --fixture <id> (product-source path deferred)"
  if opts.output?.isNone then
    throw "export-core requires -o / --output DIR"
  pure opts

private def fixtureSpec? (fixtureId : String) : Option ProofForge.Contract.ContractSpec :=
  match fixtureId with
  | "counter" => some (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module)
  | "value-vault" => some (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module)
  | _ => none

private def sha256String (text : String) : IO String := do
  let script := "import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest())"
  let digest := trimAsciiString (← ProofForge.Cli.runProcess "python3" #["-c", script, text])
  if digest.length == 64 then
    return digest
  else
    throw <| IO.userError s!"python3 returned invalid SHA-256 for export content: {digest}"

private def readToolchainPin (root? : Option FilePath) : IO String := do
  let root := root?.getD (FilePath.mk ".")
  let pinPath := root / "lean-toolchain"
  if ← pinPath.pathExists then
    return trimAsciiString (← IO.FS.readFile pinPath)
  else
    return "unknown"

/-- Write the four-file experimental export package. -/
def writeExportPackage
    (dir : FilePath)
    (targetId : String)
    (module : ProofForge.IR.Core.Module)
    (capabilityIds : Array String)
    (sourceKind : String)
    (productPath? : String)
    (catalog? : Option ProofForge.IR.Core.HostOp.HostOpCatalog)
    (root? : Option FilePath) : IO Unit := do
  let coreJson ← match exportModuleJson module catalog? with
    | .ok json => pure json
    | .error err => throw <| IO.userError err.message
  let capJson := capabilityPlanJson targetId capabilityIds
  -- Hash the exact on-disk bodies (trailing newline included) so pf-core-inspect
  -- can recompute contentHash from files without a second encoding policy.
  let coreBody := coreJson ++ "\n"
  let capBody := capJson ++ "\n"
  let contentHash ← sha256String (coreBody ++ capBody)
  let leanPin ← readToolchainPin root?
  let metaJson := exportMetaJson
    targetId module.name contentHash leanPin Lean.versionString
  let manifestJson := sourceManifestJson sourceKind productPath? targetId
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "core.v0.json") coreBody
  IO.FS.writeFile (dir / "capability-plan.v0.json") capBody
  IO.FS.writeFile (dir / "export-meta.json") (metaJson ++ "\n")
  IO.FS.writeFile (dir / "source-manifest.json") (manifestJson ++ "\n")
  IO.println s!"wrote {dir / "core.v0.json"}"
  IO.println s!"wrote {dir / "capability-plan.v0.json"}"
  IO.println s!"wrote {dir / "export-meta.json"}"
  IO.println s!"wrote {dir / "source-manifest.json"}"
  IO.println s!"export-core: experimental package ok module={module.name} target={targetId} hash={contentHash.take 12}…"

def exportCoreCommand (opts : ExportCoreOptions) : IO UInt32 := do
  let some fixtureId := opts.fixture?
    | IO.eprintln "export-core: missing --fixture"; return 1
  let some output := opts.output?
    | IO.eprintln "export-core: missing -o"; return 1
  let some spec := fixtureSpec? fixtureId
    | IO.eprintln s!"export-core: unknown fixture `{fixtureId}` (supported: counter, value-vault)"
      return 1
  if ProofForge.Target.find? opts.targetId |>.isNone then
    IO.eprintln s!"export-core: unknown target `{opts.targetId}`"
    return 1
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
  | .error err =>
      IO.eprintln s!"export-core: normalize/validate failed: {repr err}"
      return 1
  | .ok bundle => do
      let canonical := bundle.contract.contract
      let caps := canonical.requirements.map (fun call => call.capability.id)
      -- Dedup preserving first-seen order.
      let caps := caps.foldl (init := #[]) fun acc id =>
        if acc.any (· == id) then acc else acc.push id
      try
        writeExportPackage
          output
          opts.targetId
          canonical.module
          caps
          "portable-ir-fixture"
          s!"ProofForge.IR.Examples (fixture={fixtureId})"
          (some canonical.hostOpCatalog)
          opts.root?
        return 0
      catch e =>
        IO.eprintln s!"export-core: {e}"
        return 1

end ProofForge.Cli.ExportCore
