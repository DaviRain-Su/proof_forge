/-
  NOIR-IR-1 + NOIR-IR-2: Counter nargo ProgramArtifact golden inventory pin
  and Plan→ACIR MVP via nargo-assisted capture.

  IR-1 freezes:
  * product Noir relation packages for Examples/Counter
  * path-normalized locked-nargo 1.0.0-beta.26 compile JSON
  * multi-file exact SHA-256 inventory (Lean pins ≡ on-disk golden)

  IR-2 adds (Counter ≡ golden):
  * product Plan materialize source-join: live `.nr`/`Nargo.toml` ≡ golden product
  * nargo-assisted capture from **product** Plan packages → circuit core ≡ golden
  * path decision documented as **nargo-assisted** (not pure-Lean ACIR encoder)

  Optional live recheck when `nargo` is present. Missing nargo → honest skip of
  live capture only (inventory pin + source-join still run).

  **Not** ACIR opcode decode, product ACIR OutputFile (IR-6), prove/verify,
  deployable, or formal.
-/
import ProofForgeV2.Targets.Noir.Acir.InventoryV1
import ProofForgeV2.Targets.Noir.Acir.CaptureV1
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.NoirAcirV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Noir.Acir.InventoryV1
open ProofForgeV2.Targets.Noir.Acir.CaptureV1
  (pathDecisionV1 authorityNoteV1 counterRelationPinsV1
   circuitCoresEqualV1 circuitCoreMatchesPinsV1 resolveNargoPathV1
   compilePackageCaptureCircuitCoreV1 loadGoldenCircuitCoreV1
   productPackageSourceJoinV1)
open System

-- Disambiguate inventory vs capture schema ids (both export `schemaIdV1`).
private def inventorySchemaId : String :=
  ProofForgeV2.Targets.Noir.Acir.InventoryV1.schemaIdV1
private def captureSchemaId : String :=
  ProofForgeV2.Targets.Noir.Acir.CaptureV1.schemaIdV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def listDirNames (dir : FilePath) : IO (Array String) := do
  let entries ← dir.readDir
  pure (entries.map (·.fileName) |>.qsort (· < ·))

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

/-- Exact multi-file SHA-256 + size pin against frozen golden. -/
def testInventoryExactPins : IO Unit := do
  expect (inventoryEntriesV1.size == 10)
    s!"IR-1 inventory must pin 10 files, got {inventoryEntriesV1.size}"
  let mut seen : Array String := #[]
  for e in inventoryEntriesV1 do
    expect (!seen.contains e.relPath)
      s!"duplicate inventory path: {e.relPath}"
    seen := seen.push e.relPath
    let path := goldenPathV1 e.relPath
    expect (← path.pathExists)
      s!"missing golden file: {path}"
    let bytes ← IO.FS.readBinFile path
    expect (bytes.size == e.size)
      s!"size mismatch {e.relPath}: got {bytes.size} want {e.size}"
    let digest := hashFileBytesV1 bytes
    expect (digest == e.sha256Hex)
      s!"sha256 mismatch {e.relPath}:\n  got  {digest}\n  want {e.sha256Hex}"
  let sorted := inventoryEntriesV1.map (·.relPath) |>.qsort (· < ·)
  expect (inventoryEntriesV1.map (·.relPath) == sorted)
    "inventoryEntriesV1 must be path-sorted"

/-- ProgramArtifact envelope + circuit hash pins on the three compile JSONs. -/
def testProgramArtifactEnvelope : IO Unit := do
  expect (inventorySchemaId == "proof-forge.noir-acir-inventory.v1")
    "schema id pin"
  expect (nargoVersionV1 == "1.0.0-beta.26") "nargo short version pin"
  expect (productProfileV1 == "noir-source-u64-relations-v1") "profile pin"
  expect (goldenProgramModuleV1 == "Examples.Counter") "program module pin"
  expect (programArtifactRequiredKeysV1.size == 6) "six envelope keys"
  for pin in circuitHashPinsV1 do
    let path := goldenPathV1 pin.artifactRelPath
    let text ← IO.FS.readFile path
    expect (envelopeKeysPresentV1 text)
      s!"{pin.relation}: missing required ProgramArtifact keys"
    expect (noirVersionPresentV1 text)
      s!"{pin.relation}: missing exact noir_version pin"
    expect (normalizedPathPresentV1 text)
      s!"{pin.relation}: missing normalized file_map path"
    expect (circuitHashPresentV1 text pin.circuitHash)
      s!"{pin.relation}: missing circuit hash {pin.circuitHash}"
    expect (!text.contains "/home/")
      s!"{pin.relation}: golden must not contain absolute /home/ path"
    expect (!text.contains "/tmp/")
      s!"{pin.relation}: golden must not contain /tmp/ path"

/-- Golden directory layout honesty: only documented roles. -/
def testGoldenDirLayout : IO Unit := do
  let root := FilePath.mk goldenRootV1
  expect (← root.pathExists) s!"missing golden root {root}"
  expect (← (root / "inventory.json").pathExists) "inventory.json required"
  expect (← (root / "README.md").pathExists) "README.md required"
  let top ← listDirNames root
  for name in top do
    expect
      (name == "README.md" || name == "inventory.json" ||
        name == "product" || name == "nargo-compile")
      s!"unexpected top-level golden entry: {name}"
  let nargoRels ← listDirNames (root / "nargo-compile")
  expect (nargoRels == #["r0-init", "r1-increment", "r2-get"])
    s!"nargo-compile relations, got {nargoRels}"
  let productRels ← listDirNames (root / "product" / "relations")
  expect (productRels == #["r0-init", "r1-increment", "r2-get"])
    s!"product relations, got {productRels}"

/-- inventory.json documents the same sha256 pins as Lean (documentation join). -/
def testInventoryJsonJoin : IO Unit := do
  let text ← IO.FS.readFile (FilePath.mk goldenRootV1 / "inventory.json")
  expect (text.contains "\"schema\": \"proof-forge.noir-acir-golden.v1\"")
    "inventory.json schema"
  expect (text.contains nargoVersionV1) "inventory.json nargo version"
  expect (text.contains noirVersionExactV1) "inventory.json exact noir version"
  for e in inventoryEntriesV1 do
    expect (text.contains e.sha256Hex)
      s!"inventory.json missing pin for {e.relPath}"
    expect (text.contains e.relPath)
      s!"inventory.json missing path {e.relPath}"
  for pin in circuitHashPinsV1 do
    expect (text.contains pin.circuitHash)
      s!"inventory.json missing circuit hash {pin.relation}"

/-- IR-1 inventory honesty + IR-2 capture authority notes. -/
def testIrHonestyNotes : IO Unit := do
  expect (circuitHashPinsV1.size == 3) "three Counter relations"
  expect (counterRelationPinsV1.size == 3) "three capture pins"
  expect (pathDecisionV1 == "nargo-assisted")
    "IR-2 path decision must be nargo-assisted"
  expect (captureSchemaId == "proof-forge.noir-acir-capture.v1")
    "capture schema id"
  expect (authorityNoteV1.contains "nargo-assisted")
    "authority note must declare nargo-assisted"
  expect (authorityNoteV1.contains "pure-Lean")
    "authority note must deny pure-Lean encoder claim"
  expect (authorityNoteV1.contains "transitional")
    ".nr transitional note required"
  let main0 ← IO.FS.readFile
    (goldenPathV1 "product/relations/r0-init/src/main.nr")
  expect (main0.contains "fn main(") "product main.nr present"
  expect (main0.contains "pre_initialized") "Counter init relation shape"
  expect (!(inventorySchemaId.contains "opcode"))
    "schema must not claim opcode surface"
  expect (!(captureSchemaId.contains "opcode"))
    "capture schema must not claim opcode surface"

/-- Load golden circuit cores and verify extract + pin join. -/
def testGoldenCircuitCoreExtract : IO Unit := do
  for pin in counterRelationPinsV1 do
    let core ← loadGoldenCircuitCoreV1 pin
    expect (circuitCoreMatchesPinsV1 core pin.expectedCircuitHash)
      s!"{pin.relation}: golden core pin mismatch"
    expect (core.noirVersion == noirVersionExactV1)
      s!"{pin.relation}: golden noir_version"
    expect (!core.bytecodeB64.isEmpty)
      s!"{pin.relation}: empty bytecode"
  let c0 ← loadGoldenCircuitCoreV1 counterRelationPinsV1[0]!
  let c1 ← loadGoldenCircuitCoreV1 counterRelationPinsV1[1]!
  let c2 ← loadGoldenCircuitCoreV1 counterRelationPinsV1[2]!
  expect (!circuitCoresEqualV1 c0 c1) "r0≠r1 circuit core"
  expect (!circuitCoresEqualV1 c1 c2) "r1≠r2 circuit core"
  expect (!circuitCoresEqualV1 c0 c2) "r0≠r2 circuit core"

/-- Product Plan materialize Counter packages under tmp; return relation-stem → root. -/
private unsafe def materializeCounterPackages
    (tmp : FilePath) : IO (Array (String × FilePath)) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<noir-acir-ir2-counter>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult "compile Counter" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult "select noir" <|
    resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult "resolve noir" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult "materialize noir" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  expect (!files.isEmpty) "Counter: no materialize files"
  let mut packages : Array (String × FilePath) := #[]
  for f in files do
    let path := tmp / f.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile path f.contents
    if f.path.endsWith "Nargo.toml" then
      if let some parent := path.parent then
        let stem := parent.fileName.getD ""
        packages := packages.push (stem, parent)
  expect (packages.size == 3)
    s!"Counter: expected 3 Nargo packages, got {packages.size} paths={files.map (·.path)}"
  pure (packages.qsort (fun a b => a.1 < b.1))

/-- IR-2: product Plan emit source packages ≡ frozen golden product packages. -/
unsafe def testProductPlanSourceJoinCounter : IO Unit := do
  let tmp := FilePath.mk "build/v2/noir-acir-ir2-product-source-join"
  if ← tmp.pathExists then IO.FS.removeDirAll tmp
  IO.FS.createDirAll tmp
  let packages ← materializeCounterPackages tmp
  expect (packages.map (·.1) == #["r0-init", "r1-increment", "r2-get"])
    s!"package stems, got {packages.map (·.1)}"
  for pair in packages.zip counterRelationPinsV1 do
    let stem := pair.1.1
    let pkgDir := pair.1.2
    let pin := pair.2
    expect (stem == pin.relation)
      s!"stem/pin order: {stem} vs {pin.relation}"
    productPackageSourceJoinV1 pkgDir pin
    IO.println s!"  product source join: {stem}"

/-- Optional live nargo recompile of frozen product packages → circuit core ≡ golden. -/
def testLiveNargoRecheckOptional : IO Unit := do
  match ← resolveNargoPathV1 with
  | none =>
      IO.println "  live nargo recheck: skipped (nargo unavailable)"
  | some nargo => do
      let ver ← IO.Process.output { cmd := nargo, args := #["--version"] }
      IO.println s!"  live nargo recheck: {nargo}"
      IO.println s!"  {ver.stdout.trimAscii.copy}"
      let tmp := FilePath.mk "build/v2/noir-acir-ir1-live-recheck"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      for pin in counterRelationPinsV1 do
        let pkgSrc :=
          FilePath.mk goldenRootV1 / "product" / "relations" / pin.relation
        let pkgDst := tmp / pin.relation
        IO.FS.createDirAll (pkgDst / "src")
        let toml ← IO.FS.readFile (pkgSrc / "Nargo.toml")
        let main ← IO.FS.readFile (pkgSrc / "src" / "main.nr")
        IO.FS.writeFile (pkgDst / "Nargo.toml") toml
        IO.FS.writeFile (pkgDst / "src" / "main.nr") main
        let live ← compilePackageCaptureCircuitCoreV1
          nargo pkgDst pin.packageArtifactName
        let gold ← loadGoldenCircuitCoreV1 pin
        expect (circuitCoresEqualV1 live gold)
          s!"{pin.relation}: live golden-package circuit core ≠ golden pin"
        expect (circuitCoreMatchesPinsV1 live pin.expectedCircuitHash)
          s!"{pin.relation}: live circuit hash pin"
        IO.println s!"  live circuit-core match: {pin.relation}"
      IO.println "  live nargo recheck: ok"

/-- IR-2: product Plan packages → nargo-assisted capture → circuit core ≡ golden. -/
unsafe def testProductPlanAcirCaptureCounter : IO Unit := do
  match ← resolveNargoPathV1 with
  | none =>
      IO.println "  product Plan→ACIR capture: skipped (nargo unavailable)"
  | some nargo => do
      let ver ← IO.Process.output { cmd := nargo, args := #["--version"] }
      IO.println s!"  product Plan→ACIR capture: {nargo}"
      IO.println s!"  {ver.stdout.trimAscii.copy}"
      let tmp := FilePath.mk "build/v2/noir-acir-ir2-product-capture"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      let packages ← materializeCounterPackages tmp
      for pair in packages.zip counterRelationPinsV1 do
        let stem := pair.1.1
        let pkgDir := pair.1.2
        let pin := pair.2
        expect (stem == pin.relation)
          s!"capture stem/pin: {stem} vs {pin.relation}"
        productPackageSourceJoinV1 pkgDir pin
        let live ← compilePackageCaptureCircuitCoreV1
          nargo pkgDir pin.packageArtifactName
        let gold ← loadGoldenCircuitCoreV1 pin
        expect (circuitCoresEqualV1 live gold)
          (s!"{pin.relation}: product Plan nargo-assisted circuit core ≠ golden\n" ++
            s!"  live hash={live.circuitHash} gold hash={gold.circuitHash}")
        expect (live.noirVersion == noirVersionExactV1)
          s!"{pin.relation}: product capture noir_version"
        IO.println s!"  product Plan→ACIR ≡ golden: {stem}"
      IO.println "  product Plan→ACIR capture: ok"

unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.NoirAcirV1: start"
  testInventoryExactPins
  IO.println "  inventory exact pins: ok"
  testProgramArtifactEnvelope
  IO.println "  program artifact envelope: ok"
  testGoldenDirLayout
  IO.println "  golden dir layout: ok"
  testInventoryJsonJoin
  IO.println "  inventory.json join: ok"
  testIrHonestyNotes
  IO.println "  IR honesty notes: ok"
  testGoldenCircuitCoreExtract
  IO.println "  golden circuit core extract: ok"
  testProductPlanSourceJoinCounter
  IO.println "  product Plan source join Counter: ok"
  testLiveNargoRecheckOptional
  testProductPlanAcirCaptureCounter
  IO.println "Tests.Materialization.NoirAcirV1: ok"

/-- Focused entry for `lake env lean --run` / optional lake_exe (namespaced). -/
unsafe def main : IO Unit := run

end Tests.Materialization.NoirAcirV1
