/-
  NOIR-IR-1: Counter nargo ProgramArtifact golden inventory pin.

  Freezes:
  * product Noir relation packages for Examples/Counter
  * path-normalized locked-nargo 1.0.0-beta.26 compile JSON
  * multi-file exact SHA-256 inventory (Lean pins ≡ on-disk golden)

  Optional live recheck when `nargo` is present: recompile golden product
  packages, path-normalize `file_map.path`, compare to frozen artifacts.
  Missing nargo → honest skip of live recheck only (inventory pin still runs).

  **Not** Plan→ACIR, ACIR opcode decode, prove/verify, deployable, formal.
-/
import ProofForgeV2.Targets.Noir.Acir.InventoryV1
import ProofForgeV2.Core.Crypto

namespace Tests.Materialization.NoirAcirV1

open ProofForgeV2
open ProofForgeV2.Targets.Noir.Acir.InventoryV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def listDirNames (dir : FilePath) : IO (Array String) := do
  let entries ← dir.readDir
  pure (entries.map (·.fileName) |>.qsort (· < ·))

/-- Exact multi-file SHA-256 + size pin against frozen golden. -/
def testInventoryExactPins : IO Unit := do
  expect (inventoryEntriesV1.size == 10)
    s!"IR-1 inventory must pin 10 files, got {inventoryEntriesV1.size}"
  let mut seen : Array String := #[]
  for entry in inventoryEntriesV1 do
    expect (!seen.contains entry.relPath)
      s!"duplicate inventory path: {entry.relPath}"
    seen := seen.push entry.relPath
    let path := goldenPathV1 entry.relPath
    expect (← path.pathExists)
      s!"missing golden file: {path}"
    let bytes ← IO.FS.readBinFile path
    expect (bytes.size == entry.size)
      s!"size mismatch {entry.relPath}: got {bytes.size} want {entry.size}"
    let digest := hashFileBytesV1 bytes
    expect (digest == entry.sha256Hex)
      s!"sha256 mismatch {entry.relPath}:\n  got  {digest}\n  want {entry.sha256Hex}"
  -- path-sorted inventory (stable order for humans and SBOM-adjacent review)
  let sorted := inventoryEntriesV1.map (·.relPath) |>.qsort (· < ·)
  expect (inventoryEntriesV1.map (·.relPath) == sorted)
    "inventoryEntriesV1 must be path-sorted"

/-- ProgramArtifact envelope + circuit hash pins on the three compile JSONs. -/
def testProgramArtifactEnvelope : IO Unit := do
  expect (schemaIdV1 == "proof-forge.noir-acir-inventory.v1")
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
    -- absolute host paths must not leak into golden identity
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
  -- allow only documented top-level names
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
  for entry in inventoryEntriesV1 do
    expect (text.contains entry.sha256Hex)
      s!"inventory.json missing pin for {entry.relPath}"
    expect (text.contains entry.relPath)
      s!"inventory.json missing path {entry.relPath}"
  for pin in circuitHashPinsV1 do
    expect (text.contains pin.circuitHash)
      s!"inventory.json missing circuit hash {pin.relation}"

/-- Honesty notes: IR-1 is inventory-only; no product ACIR OutputFile claim. -/
def testIr1HonestyNotes : IO Unit := do
  -- Frozen compile artifacts exist as golden research pins only.
  expect (circuitHashPinsV1.size == 3) "three Counter relations"
  -- Product source packages remain transitional .nr authority until IR-2+.
  let main0 ← IO.FS.readFile
    (goldenPathV1 "product/relations/r0-init/src/main.nr")
  expect (main0.contains "fn main(") "product main.nr present"
  expect (main0.contains "pre_initialized") "Counter init relation shape"
  -- Envelope pins are not ACIR opcode decode.
  expect (!(schemaIdV1.contains "opcode"))
    "schema must not claim opcode surface"
  pure ()

private def resolveNargoPath : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String :=
    #["/opt/homebrew/bin/nargo", "/usr/local/bin/nargo"]
  if let some h := home then
    absCandidates :=
      absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/darwin-arm64/nargo")
    absCandidates :=
      absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/linux-x86_64/nargo")
    absCandidates := absCandidates.push (h ++ "/.nargo/bin/nargo")
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    absCandidates := #[root ++ "/nargo"] ++ absCandidates
  for c in absCandidates do
    if ← (FilePath.mk c).pathExists then
      return some c
  let which ← IO.Process.output { cmd := "which", args := #["nargo"] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

/-- Extract a top-level JSON string field value (`"key":"..."`) from compact
    nargo ProgramArtifact text. Not a full JSON parser. -/
private def extractJsonStringField (text key : String) : Option String :=
  let needle := s!"\"{key}\":\""
  match text.splitOn needle with
  | [_, rest] =>
      match rest.splitOn "\"" with
      | value :: _ => some value
      | [] => none
  | _ => none

/-- Optional live nargo recompile of frozen product packages → compare circuit
    core (noir_version, hash, bytecode) to golden. Skip when nargo missing.

    Compares path-independent circuit core only: absolute `file_map.path` is
    host-local and is **not** part of golden identity (normalized in golden). -/
def testLiveNargoRecheckOptional : IO Unit := do
  match ← resolveNargoPath with
  | none =>
      IO.println "  live nargo recheck: skipped (nargo unavailable)"
  | some nargo => do
      let ver ← IO.Process.output { cmd := nargo, args := #["--version"] }
      IO.println s!"  live nargo recheck: {nargo}"
      IO.println s!"  {ver.stdout.trimAscii.copy}"
      let tmp := FilePath.mk "build/v2/noir-acir-ir1-live-recheck"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      let relations : Array (String × String × String) :=
        #[("r0-init", "pf_relation_0.json", circuitHashR0InitV1),
          ("r1-increment", "pf_relation_1.json", circuitHashR1IncrementV1),
          ("r2-get", "pf_relation_2.json", circuitHashR2GetV1)]
      for (rel, artifactName, expectedHash) in relations do
        let pkgSrc :=
          FilePath.mk goldenRootV1 / "product" / "relations" / rel
        let pkgDst := tmp / rel
        IO.FS.createDirAll (pkgDst / "src")
        let toml ← IO.FS.readFile (pkgSrc / "Nargo.toml")
        let main ← IO.FS.readFile (pkgSrc / "src" / "main.nr")
        IO.FS.writeFile (pkgDst / "Nargo.toml") toml
        IO.FS.writeFile (pkgDst / "src" / "main.nr") main
        let process ← IO.Process.output {
          cmd := nargo
          args := #["compile", "--silence-warnings"]
          cwd := some pkgDst
        }
        unless process.exitCode == 0 do
          throw <| IO.userError
            (s!"live recheck {rel}: nargo compile failed\n" ++
              process.stdout ++ process.stderr)
        let livePath := pkgDst / "target" / artifactName
        expect (← livePath.pathExists)
          s!"live recheck {rel}: missing {livePath}"
        let liveRaw ← IO.FS.readFile livePath
        let goldenText ← IO.FS.readFile
          (goldenPathV1 s!"nargo-compile/{rel}/{artifactName}")
        let liveVer ← match extractJsonStringField liveRaw "noir_version" with
          | some v => pure v
          | none => throw <| IO.userError s!"{rel}: live missing noir_version"
        let goldVer ← match extractJsonStringField goldenText "noir_version" with
          | some v => pure v
          | none => throw <| IO.userError s!"{rel}: golden missing noir_version"
        expect (liveVer == goldVer)
          s!"{rel}: noir_version live≠golden"
        expect (liveVer == noirVersionExactV1)
          s!"{rel}: noir_version must equal Tool Lock exact pin"
        let liveHash ← match extractJsonStringField liveRaw "hash" with
          | some v => pure v
          | none => throw <| IO.userError s!"{rel}: live missing hash"
        expect (liveHash == expectedHash)
          s!"{rel}: circuit hash live≠pin ({liveHash} vs {expectedHash})"
        let liveBc ← match extractJsonStringField liveRaw "bytecode" with
          | some v => pure v
          | none => throw <| IO.userError s!"{rel}: live missing bytecode"
        let goldBc ← match extractJsonStringField goldenText "bytecode" with
          | some v => pure v
          | none => throw <| IO.userError s!"{rel}: golden missing bytecode"
        expect (liveBc == goldBc)
          s!"{rel}: bytecode live≠golden"
        IO.println s!"  live circuit-core match: {rel}"
      IO.println "  live nargo recheck: ok"

def run : IO Unit := do
  IO.println "Tests.Materialization.NoirAcirV1: start"
  testInventoryExactPins
  IO.println "  inventory exact pins: ok"
  testProgramArtifactEnvelope
  IO.println "  program artifact envelope: ok"
  testGoldenDirLayout
  IO.println "  golden dir layout: ok"
  testInventoryJsonJoin
  IO.println "  inventory.json join: ok"
  testIr1HonestyNotes
  IO.println "  IR-1 honesty notes: ok"
  testLiveNargoRecheckOptional
  IO.println "Tests.Materialization.NoirAcirV1: ok"

/-- Focused entry for `lake env lean --run` / optional lake_exe (namespaced). -/
def main : IO Unit := run

end Tests.Materialization.NoirAcirV1
