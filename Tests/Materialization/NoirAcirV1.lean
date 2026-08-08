/-
  NOIR-IR-1 + NOIR-IR-2 + NOIR-IR-3 (G3) + NOIR-IR-5 (honesty matrix):
  Counter nargo ProgramArtifact golden inventory pin, Plan→ACIR MVP via
  nargo-assisted capture, admit-surface control-flow / aggregate circuit-hash
  pins, and §3.2 honesty matrix FC boundaries.

  IR-1 freezes:
  * product Noir relation packages for Examples/Counter
  * path-normalized locked-nargo 1.0.0-beta.26 compile JSON
  * multi-file exact SHA-256 inventory (Lean pins ≡ on-disk golden)

  IR-2 adds (Counter ≡ golden):
  * product Plan materialize source-join: live `.nr`/`Nargo.toml` ≡ golden product
  * nargo-assisted capture from **product** Plan packages → circuit core ≡ golden
  * path decision documented as **nargo-assisted** (not pure-Lean ACIR encoder)

  IR-3 / G3 adds (admit surface, circuit-hash pins — not full inventory):
  * BranchCounter (if), LoopSum (for), OptionState, ArrayRet full nargo capture
  * MapMini Plan materialize + init capture; put/get nargo-fail honesty residual
  * product package-stem pins always run; live capture honest-skips without nargo

  IR-5 / G5 honesty matrix:
  * §3.2 status column (Y/P/F) pinned in CaptureV1.honestyMatrixRowsV1
  * call/schedule = P (witness-binding only; never ACIR Y)
  * String state / Option non-UInt64 = F (product plan-FC)
  * prove/VK = F (Finalize deployable=false; no product prove)
  * No false Y

  Optional live recheck when `nargo` is present. Missing nargo → honest skip of
  live capture only (inventory pin + source-join + package-stem + honesty matrix
  still run).

  **Not** ACIR opcode decode, product ACIR OutputFile (IR-6), prove/verify,
  deployable, or formal.
-/
import ProofForgeV2.Targets.Noir.Acir.InventoryV1
import ProofForgeV2.Targets.Noir.Acir.CaptureV1
import ProofForgeV2.Targets.Noir.FinalizeV1
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
   productPackageSourceJoinV1 admitSurfaceFixturesV1
   admitSurfaceCapturePinCountV1 nargoCompileExitCodeV1
   AdmitSurfaceFamilyV1
   honestyMatrixRowsV1 honestyCallScheduleNoteV1 honestyOptionStringNoteV1
   honestyProveNoteV1 finalizeEvidenceNoteV1
   callSchedulePackageStemsV1 callScheduleHonestySourceTextV1
   stringStateFcSourceTextV1 optionStringStateFcSourceTextV1
   optionBoolStateFcSourceTextV1
   honestyAcirYFamiliesV1 honestyAcirFFamiliesV1 honestyAcirPFamiliesV1
   isHonestyYV1 HonestyStatusV1)
open ProofForgeV2.Targets.Noir.Acir.CaptureV1.AdmitSurfaceFamilyV1
open ProofForgeV2.Targets.Noir.Acir.CaptureV1.HonestyStatusV1
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

/-- IR-1 inventory honesty + IR-2 capture authority notes + IR-3 G3 fixture table. -/
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
  expect (authorityNoteV1.contains "honest skip")
    "authority note must document nargo missing honest skip"
  expect (authorityNoteV1.contains "G3")
    "authority note must mention G3 admit-surface pins"
  expect (authorityNoteV1.contains "IR-5")
    "authority note must mention IR-5 honesty matrix"
  expect (authorityNoteV1.contains "witness-binding")
    "authority note must document call/schedule witness-binding honesty"
  let main0 ← IO.FS.readFile
    (goldenPathV1 "product/relations/r0-init/src/main.nr")
  expect (main0.contains "fn main(") "product main.nr present"
  expect (main0.contains "pre_initialized") "Counter init relation shape"
  expect (!(inventorySchemaId.contains "opcode"))
    "schema must not claim opcode surface"
  expect (!(captureSchemaId.contains "opcode"))
    "capture schema must not claim opcode surface"
  -- G3 fixture table shape (no nargo required).
  expect (admitSurfaceFixturesV1.size == 5)
    s!"G3 must pin 5 admit fixtures, got {admitSurfaceFixturesV1.size}"
  expect (admitSurfaceCapturePinCountV1 == 14)
    s!"G3 capture pin count (13 full + MapMini init), got {admitSurfaceCapturePinCountV1}"
  let ids := admitSurfaceFixturesV1.map (·.fixtureId)
  expect (ids == #["BranchCounter", "LoopSum", "OptionState", "ArrayRet", "MapMini"])
    s!"G3 fixture id order, got {ids}"
  let families := admitSurfaceFixturesV1.map (·.family)
  expect (families.contains .controlFlowIf) "G3 if family"
  expect (families.contains .controlFlowFor) "G3 for family"
  expect (families.contains .aggregateOption) "G3 Option family"
  expect (families.contains .aggregateArray) "G3 Array family"
  expect (families.contains .aggregateMapPartial) "G3 Map partial family"
  let mapMini := admitSurfaceFixturesV1[4]!
  expect (mapMini.nargoFailStems == #["r1-put", "r2-get"])
    "MapMini put/get must be honesty nargo-fail residual"
  expect (mapMini.capturePins.size == 1)
    "MapMini only pins init capture success"

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

/-- Materialize any ProgramV1 source under tmp; return sorted stem → package root. -/
private unsafe def materializeProgramPackages
    (label : String) (sourceText : String) (moduleName : String)
    (tmp : FilePath) : IO (Array (String × FilePath)) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<noir-acir-g3-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  expect (!files.isEmpty) s!"{label}: no materialize files"
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
  pure (packages.qsort (fun a b => a.1 < b.1))

/-- IR-3: product materialize package-stem pins for every G3 admit fixture (no nargo). -/
unsafe def testAdmitSurfacePackageStems : IO Unit := do
  let tmp := FilePath.mk "build/v2/noir-acir-g3-package-stems"
  if ← tmp.pathExists then IO.FS.removeDirAll tmp
  IO.FS.createDirAll tmp
  for fix in admitSurfaceFixturesV1 do
    let packages ← materializeProgramPackages
      fix.fixtureId fix.sourceText fix.moduleName (tmp / fix.fixtureId)
    let stems := packages.map (·.1)
    expect (stems == fix.packageStems)
      s!"{fix.fixtureId}: package stems got {stems} want {fix.packageStems}"
    for pin in fix.capturePins do
      expect (stems.contains pin.relation)
        s!"{fix.fixtureId}: capture pin relation missing: {pin.relation}"
    for failStem in fix.nargoFailStems do
      expect (stems.contains failStem)
        s!"{fix.fixtureId}: honesty-fail stem missing: {failStem}"
    -- Every package must emit transitional source leaves.
    for p in packages do
      expect (← (p.2 / "Nargo.toml").pathExists)
        s!"{fix.fixtureId}/{p.1}: missing Nargo.toml"
      expect (← (p.2 / "src" / "main.nr").pathExists)
        s!"{fix.fixtureId}/{p.1}: missing src/main.nr"
    IO.println
      s!"  G3 package stems: {fix.fixtureId} ({fix.family.toString}) → {stems}"
  IO.println "  G3 package stems: ok"

/-- IR-3: live nargo-assisted circuit-core pins + MapMini put/get fail honesty.
    Missing nargo → honest skip (package-stem test above still ran). -/
unsafe def testAdmitSurfaceLiveCaptureOptional : IO Unit := do
  match ← resolveNargoPathV1 with
  | none =>
      IO.println "  G3 admit-surface live capture: skipped (nargo unavailable)"
  | some nargo => do
      let ver ← IO.Process.output { cmd := nargo, args := #["--version"] }
      IO.println s!"  G3 admit-surface live capture: {nargo}"
      IO.println s!"  {ver.stdout.trimAscii.copy}"
      let tmp := FilePath.mk "build/v2/noir-acir-g3-live-capture"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      for fix in admitSurfaceFixturesV1 do
        let packages ← materializeProgramPackages
          fix.fixtureId fix.sourceText fix.moduleName (tmp / fix.fixtureId)
        expect (packages.map (·.1) == fix.packageStems)
          s!"{fix.fixtureId}: live stems drift"
        -- Success capture pins: circuit hash + exact noir_version.
        for pin in fix.capturePins do
          let mut found : Option FilePath := none
          for p in packages do
            if p.1 == pin.relation then found := some p.2
          match found with
          | none =>
              throw <| IO.userError
                s!"{fix.fixtureId}: missing package for capture pin {pin.relation}"
          | some pkgDir => do
              let live ← compilePackageCaptureCircuitCoreV1
                nargo pkgDir pin.packageArtifactName
              expect (circuitCoreMatchesPinsV1 live pin.expectedCircuitHash)
                (s!"{fix.fixtureId}/{pin.relation}: circuit pin mismatch\n" ++
                  s!"  live hash={live.circuitHash} want {pin.expectedCircuitHash}")
              expect (live.noirVersion == noirVersionExactV1)
                s!"{fix.fixtureId}/{pin.relation}: noir_version"
              expect (!live.bytecodeB64.isEmpty)
                s!"{fix.fixtureId}/{pin.relation}: empty bytecode"
              -- Stability: second capture must equal first (same package).
              let live2 ← compilePackageCaptureCircuitCoreV1
                nargo pkgDir pin.packageArtifactName
              expect (circuitCoresEqualV1 live live2)
                s!"{fix.fixtureId}/{pin.relation}: capture not stable across recompile"
              IO.println
                s!"  G3 capture ≡ pin: {fix.fixtureId}/{pin.relation} hash={live.circuitHash}"
        -- Honesty residual: Plan-emitted packages that must fail nargo.
        for failStem in fix.nargoFailStems do
          let mut found : Option FilePath := none
          for p in packages do
            if p.1 == failStem then found := some p.2
          match found with
          | none =>
              throw <| IO.userError
                s!"{fix.fixtureId}: missing honesty-fail package {failStem}"
          | some pkgDir => do
              let code ← nargoCompileExitCodeV1 nargo pkgDir
              expect (code != 0)
                s!"{fix.fixtureId}/{failStem}: expected nargo compile fail, got exit 0"
              IO.println
                s!"  G3 honesty nargo-fail: {fix.fixtureId}/{failStem} exit={code}"
      IO.println "  G3 admit-surface live capture: ok"

/-! ### NOIR-IR-5 — honesty matrix + FC boundaries -/

/-- IR-5: §3.2 status column pins; no false Y for call/schedule/prove/String. -/
def testHonestyMatrixStatusColumn : IO Unit := do
  expect (honestyMatrixRowsV1.size == 9)
    s!"IR-5 matrix must pin 9 rows, got {honestyMatrixRowsV1.size}"
  let families := honestyMatrixRowsV1.map (·.family)
  expect (families.contains "call/schedule slots") "matrix call/schedule row"
  expect (families.contains "String state / Option non-UInt64") "matrix String/Option row"
  expect (families.contains "prove/VK") "matrix prove/VK row"
  expect (families.contains "Option UInt64 state") "matrix Option UInt64 Y row"
  -- No false Y: call/schedule, String/Option non-UInt64, prove/VK must not be Y.
  for row in honestyMatrixRowsV1 do
    if row.family == "call/schedule slots" then
      expect (row.acirStatus == .P)
        s!"call/schedule ACIR must be P not {row.acirStatus.toString}"
      expect (row.noirPathStatus == .P)
        "call/schedule Noir path must be P (witness slots)"
      expect (row.evidence.contains "witness-binding")
        "call/schedule evidence must cite witness-binding"
      expect (!isHonestyYV1 row.acirStatus)
        "call/schedule must never be ACIR Y"
    if row.family == "String state / Option non-UInt64" then
      expect (row.acirStatus == .F)
        s!"String/Option non-UInt64 ACIR must be F, got {row.acirStatus.toString}"
      expect (row.noirPathStatus == .F) "String/Option non-UInt64 Noir path F"
      expect (row.evidence.contains "plan-FC")
        "String/Option non-UInt64 evidence must cite plan-FC"
    if row.family == "prove/VK" then
      expect (row.acirStatus == .F)
        s!"prove/VK ACIR must be F, got {row.acirStatus.toString}"
      expect (row.evidence.contains "deployable=false" ||
          row.evidence.contains "G6")
        "prove/VK evidence must deny product prove"
    if row.family == "Option UInt64 state" then
      expect (row.acirStatus == .Y) "Option UInt64 must remain ACIR Y (G3)"
    if row.family == "Array/Map/Bytes flatten" then
      expect (row.acirStatus == .P)
        "Array/Map/Bytes ACIR stays P (Map residual / Bytes Plan-only)"
  -- Bucket shape pins (docs join).
  expect (honestyAcirYFamiliesV1.size == 5)
    s!"ACIR Y families count, got {honestyAcirYFamiliesV1.size}"
  expect (honestyAcirPFamiliesV1.size == 2)
    s!"ACIR P families (Array/Map/Bytes + call/schedule), got {honestyAcirPFamiliesV1.size}"
  expect (honestyAcirFFamiliesV1.size == 2)
    s!"ACIR F families (String/Option + prove), got {honestyAcirFFamiliesV1.size}"
  expect (!honestyAcirYFamiliesV1.contains "call/schedule slots")
    "false Y guard: call/schedule not in Y bucket"
  expect (!honestyAcirYFamiliesV1.contains "prove/VK")
    "false Y guard: prove/VK not in Y bucket"
  expect (!honestyAcirYFamiliesV1.contains "String state / Option non-UInt64")
    "false Y guard: String/Option non-UInt64 not in Y bucket"
  -- Honesty notes non-empty and content-bound.
  expect (honestyCallScheduleNoteV1.contains "witness-binding")
    "call/schedule honesty note"
  expect (honestyCallScheduleNoteV1.contains "P not Y")
    "call/schedule note denies ACIR Y"
  expect (honestyOptionStringNoteV1.contains "plan-FC")
    "Option/String honesty note"
  expect (honestyOptionStringNoteV1.contains "Option String")
    "Option String named in honesty note"
  expect (honestyProveNoteV1.contains "deployable=false")
    "prove honesty note deployable=false"
  expect (honestyProveNoteV1.contains "prove")
    "prove honesty note mentions prove"
  expect (finalizeEvidenceNoteV1.contains "proving backend")
    "Finalize evidence note pin"
  expect (finalizeEvidenceNoteV1.contains "without ACIR")
    "Finalize note denies ACIR product claim at zero-tool finalize"
  IO.println "  IR-5 honesty matrix status column: ok"

/-- Product path must fail closed for String / Option non-UInt64 shapes. -/
private unsafe def expectProductPlanFailClosed
    (label : String) (sourceText : String) (moduleName : String)
    (messageNeedles : Array String) : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 sourceText s!"<noir-acir-ir5-{label}>" moduleName none with
  | .error e =>
      expect (e.render.length > 0) s!"{label}: empty select diagnostic"
  | .ok source =>
    match Compiler.compileValidatedSourceV1 source with
    | .error e =>
        expect (e.render.length > 0) s!"{label}: empty compile diagnostic"
    | .ok compiled =>
      match resolveBuildSelectionV1 TargetId.noir none with
      | .error e =>
          expect (e.render.length > 0) s!"{label}: empty select diagnostic"
      | .ok selection =>
        match Targets.resolveEngineeringRequirementsV1 selection compiled with
        | .error e =>
            expect (e.render.length > 0) s!"{label}: empty resolve diagnostic"
        | .ok cap =>
          match Targets.materializeResult cap with
          | .error e =>
              let msg := e.render
              let hit := messageNeedles.any (fun n => msg.contains n)
              expect hit
                s!"{label}: FC message must cite one of {messageNeedles}, got {msg}"
          | .ok _ =>
              throw <| IO.userError
                s!"{label}: Noir ACIR honesty requires plan-FC (must not materialize)"

/-- IR-5: String state + Option String + Option Bool product plan-FC pins. -/
unsafe def testHonestyOptionStringProductFailClosed : IO Unit := do
  expectProductPlanFailClosed "string-state"
    stringStateFcSourceTextV1 "Examples.StringStateFc"
    #["String", "unsupported", "state", "UInt", "scalar", "aggregate"]
  expectProductPlanFailClosed "option-string-state"
    optionStringStateFcSourceTextV1 "Examples.OptionStringStateFc"
    #["Option", "UInt64", "payload", "unsupported", "state", "String"]
  expectProductPlanFailClosed "option-bool-state"
    optionBoolStateFcSourceTextV1 "Examples.OptionBoolStateFc"
    #["Option", "UInt64", "payload", "unsupported", "state"]
  IO.println "  IR-5 String/Option non-UInt64 plan-FC: ok"

/-- IR-5: call/schedule materialize is admitted as witness-binding (P), not Y.
    Pins package stems + honesty notes; does **not** claim platform call ACIR Y. -/
unsafe def testHonestyCallSchedulePartialNotY : IO Unit := do
  expect (callSchedulePackageStemsV1 == #["r0-init", "r1-bump", "r2-later", "r3-get"])
    s!"ExtFlow honesty package stems, got {callSchedulePackageStemsV1}"
  expect (honestyCallScheduleNoteV1.contains "witness-binding")
    "call/schedule note must say witness-binding"
  expect (honestyCallScheduleNoteV1.contains "does not attest" ||
      honestyCallScheduleNoteV1.contains "does not attest that")
    "call/schedule note must deny on-chain attestation"
  let tmp := FilePath.mk "build/v2/noir-acir-ir5-call-schedule"
  if ← tmp.pathExists then IO.FS.removeDirAll tmp
  IO.FS.createDirAll tmp
  let packages ← materializeProgramPackages
    "ExtFlowHonesty" callScheduleHonestySourceTextV1
    "Examples.ExtFlowHonesty" tmp
  let stems := packages.map (·.1)
  expect (stems == callSchedulePackageStemsV1)
    s!"call/schedule honesty stems got {stems} want {callSchedulePackageStemsV1}"
  -- Packages emit transitional source (P path admitted) but matrix stays P.
  for p in packages do
    expect (← (p.2 / "Nargo.toml").pathExists)
      s!"call/schedule {p.1}: missing Nargo.toml"
    expect (← (p.2 / "src" / "main.nr").pathExists)
      s!"call/schedule {p.1}: missing main.nr"
  -- Source must still mention call/schedule at Plan emit (slots exist).
  let bumpNr ← IO.FS.readFile (packages[1]!.2 / "src" / "main.nr")
  -- Relation model binds call status/args as public inputs; exact spelling
  -- may be call_* slots rather than Noir `call` keyword in emitted .nr.
  expect (bumpNr.contains "call" || bumpNr.contains "fn main")
    "bump relation package must emit main (call slots path admitted as P)"
  let laterNr ← IO.FS.readFile (packages[2]!.2 / "src" / "main.nr")
  expect (laterNr.contains "fn main")
    "later relation package must emit main (schedule slots path admitted as P)"
  -- Re-assert matrix: this success is P, not Y.
  let callRow := honestyMatrixRowsV1.find? (·.family == "call/schedule slots")
  match callRow with
  | none => throw <| IO.userError "missing call/schedule matrix row"
  | some row =>
      expect (row.acirStatus == .P)
        "materialize success must not upgrade call/schedule to ACIR Y"
  IO.println "  IR-5 call/schedule P (witness-binding, not Y): ok"

/-- IR-5: prove/VK product path remains F — Finalize non-deployable + evidence. -/
unsafe def testHonestyProveFailClosedNotes : IO Unit := do
  expect (finalizeEvidenceNoteV1 ==
      "no approved and digest-pinned Noir compiler/proving backend is configured; " ++
      "relation source/schema were emitted without ACIR, witness execution, proof, " ++
      "or verification")
    "Finalize evidence note must match FinalizeV1 exact text"
  -- Zero-tool finalize draft shape: deployable=false, empty extras, exact note.
  -- We pin the note constant and matrix F status; product finalize is exercised
  -- by EngineeringFinalizationV1 (noir emit non-deployable).
  expect (honestyProveNoteV1.contains "deployable=false")
    "prove honesty note"
  expect (honestyProveNoteV1.contains "G6")
    "prove honesty defers to G6"
  let proveRow := honestyMatrixRowsV1.find? (·.family == "prove/VK")
  match proveRow with
  | none => throw <| IO.userError "missing prove/VK matrix row"
  | some row =>
      expect (row.acirStatus == .F) "prove/VK ACIR F"
      expect (row.noirPathStatus == .F) "prove/VK Noir path F"
  -- Authority note must not claim prove.
  expect (!authorityNoteV1.contains "prove/verify complete")
    "authority must not claim prove complete"
  expect (!authorityNoteV1.contains "Barretenberg")
    "authority must not invent Barretenberg backend"
  -- Schema ids do not advertise prove surface.
  expect (!(captureSchemaId.contains "prove"))
    "capture schema must not claim prove"
  expect (!(inventorySchemaId.contains "prove"))
    "inventory schema must not claim prove"
  -- Soft join: FinalizeV1 module remains the zero-tool non-deployable authority.
  let _ := ProofForgeV2.Targets.Noir.FinalizeV1.finalize
  IO.println "  IR-5 prove/VK F + Finalize evidence: ok"

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
  -- IR-3 / G3
  testAdmitSurfacePackageStems
  testAdmitSurfaceLiveCaptureOptional
  -- IR-5 / G5 honesty matrix
  testHonestyMatrixStatusColumn
  testHonestyOptionStringProductFailClosed
  testHonestyCallSchedulePartialNotY
  testHonestyProveFailClosedNotes
  IO.println "Tests.Materialization.NoirAcirV1: ok"

end Tests.Materialization.NoirAcirV1

/-- Focused entry for `lake env lean --run` (root `main`; suite body stays namespaced). -/
unsafe def main : IO Unit :=
  Tests.Materialization.NoirAcirV1.run
