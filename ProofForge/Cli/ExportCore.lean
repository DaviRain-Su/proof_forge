/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Experimental `export-core` CLI (LR-1b / D-057 Seam A)

This is the **Rust-backend interface export** (checked Canonical Core as
`core.v0.json`), **not** product ABI / SDK / deploy-manifest JSON.

Writes a versioned Core package after Authored→Core normalize + Validate.
**Not** a product build path: requires `--experimental` and does not lower to
target plans or bytecode.

```
proof-forge export-core --experimental --target evm --fixture counter \
  -o build/export/counter/evm

proof-forge export-core --experimental --target evm \
  -o build/export/product-counter/evm Examples/Product/Counter.lean
```
-/
import ProofForge.Cli.Artifact
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.HexUtil
import ProofForge.Cli.Options
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
  input? : Option FilePath := none
  output? : Option FilePath := none
  root? : Option FilePath := none
  moduleName? : Option Lean.Name := none
  deriving Repr

def usage : String :=
  String.intercalate "\n" [
    "proof-forge export-core — experimental core.v0 package (D-057 / Seam A)",
    "",
    "  This exports CHECKED CANONICAL CORE for a future Rust backend / inspect",
    "  tool. It is NOT the product ABI, SDK schema, or deploy-manifest export.",
    "",
    "  REQUIRED: --experimental",
    "  proof-forge export-core --experimental --target <id> --fixture <id> -o DIR",
    "  proof-forge export-core --experimental --target <id> -o DIR Product.lean",
    "",
    "Fixtures (portable IR → Core): counter | value-vault",
    "Product path: any contract_source Lean module loadable via ContractLoader",
    "",
    "Writes DIR/{core.v0.json,capability-plan.v0.json,export-meta.json,source-manifest.json}",
    "Does NOT build target plans, bytecode, or ABI clients."
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
    | "--module" :: name :: rest =>
        loop rest { acc with moduleName? := some (ProofForge.Cli.parseModuleName name) }
    | "-o" :: path :: rest | "--output" :: path :: rest =>
        loop rest { acc with output? := some (FilePath.mk path) }
    | "--root" :: path :: rest =>
        loop rest { acc with root? := some (FilePath.mk path) }
    | "--help" :: _ | "-h" :: _ => throw "help"
    | other :: rest =>
        if other.startsWith "-" then
          throw s!"unknown export-core argument `{other}`"
        else if acc.input?.isSome then
          throw s!"unexpected extra argument `{other}`"
        else
          loop rest { acc with input? := some (FilePath.mk other) }
  let opts ← loop args {}
  if !opts.experimental then
    throw "export-core requires --experimental (not a product path; see D-057)"
  if opts.targetId.isEmpty then
    throw "export-core requires --target <id>"
  if opts.fixture?.isSome && opts.input?.isSome then
    throw "export-core: use either --fixture or a product Lean path, not both"
  if opts.fixture?.isNone && opts.input?.isNone then
    throw "export-core requires --fixture <id> or a product .lean path"
  if opts.output?.isNone then
    throw "export-core requires -o / --output DIR"
  pure opts

private def fixtureSpec? (fixtureId : String) : Option ProofForge.Contract.ContractSpec :=
  match fixtureId with
  | "counter" => some (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module)
  | "value-vault" => some (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module)
  | _ => none

/-- SHA-256 of UTF-8 bytes via a temp file (avoids argv length limits). -/
private def sha256Utf8 (text : String) : IO String := do
  let tmp := FilePath.mk s!"build/export/.hash-{text.hash}.bin"
  if let some parent := tmp.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile tmp text
  try
    let (digest, _) ← ProofForge.Cli.fileDigestAndBytes tmp
    pure digest
  finally
    try IO.FS.removeFile tmp catch _ => pure ()

private def readToolchainPin (root? : Option FilePath) : IO String := do
  let root := root?.getD (FilePath.mk ".")
  let pinPath := root / "lean-toolchain"
  if ← pinPath.pathExists then
    return trimAsciiString (← IO.FS.readFile pinPath)
  else
    return "unknown"

private def dedupIds (ids : Array String) : Array String :=
  ids.foldl (init := #[]) fun acc id =>
    if acc.any (· == id) then acc else acc.push id

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
  let contentHash ← sha256Utf8 (coreBody ++ capBody)
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

private def exportFromSpec
    (opts : ExportCoreOptions)
    (spec : ProofForge.Contract.ContractSpec)
    (sourceKind productPath : String) : IO UInt32 := do
  let some output := opts.output?
    | IO.eprintln "export-core: missing -o"; pure (1 : UInt32)
  if ProofForge.Target.find? opts.targetId |>.isNone then
    IO.eprintln s!"export-core: unknown target `{opts.targetId}`"
    return (1 : UInt32)
  match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
  | .error err =>
      IO.eprintln s!"export-core: normalize/validate failed: {repr err}"
      pure (1 : UInt32)
  | .ok bundle => do
      let canonical := bundle.contract.contract
      let caps := dedupIds (canonical.requirements.map (fun call => call.capability.id))
      try
        writeExportPackage
          output
          opts.targetId
          canonical.module
          caps
          sourceKind
          productPath
          (some canonical.hostOpCatalog)
          opts.root?
        pure (0 : UInt32)
      catch e =>
        IO.eprintln s!"export-core: {e}"
        pure (1 : UInt32)

unsafe def exportCoreCommand (opts : ExportCoreOptions) : IO UInt32 := do
  match opts.fixture?, opts.input? with
  | some fixtureId, none =>
      match fixtureSpec? fixtureId with
      | none =>
          IO.eprintln s!"export-core: unknown fixture `{fixtureId}` (supported: counter, value-vault)"
          pure (1 : UInt32)
      | some spec =>
          exportFromSpec opts spec "portable-ir-fixture"
            s!"ProofForge.IR.Examples (fixture={fixtureId})"
  | none, some input => do
      if !(← input.pathExists) then
        IO.eprintln s!"export-core: input does not exist: {input}"
        pure (1 : UInt32)
      else
        try
          let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
          exportFromSpec opts spec "contract-source" input.toString
        catch e =>
          IO.eprintln s!"export-core: load product source failed: {e}"
          pure (1 : UInt32)
  | some _, some _ =>
      IO.eprintln "export-core: use either --fixture or a product path, not both"
      pure (1 : UInt32)
  | none, none =>
      IO.eprintln "export-core: missing --fixture or product path"
      pure (1 : UInt32)

end ProofForge.Cli.ExportCore
