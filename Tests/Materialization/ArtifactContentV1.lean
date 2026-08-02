/-
  D3-E7 commit 1/2: ArtifactContentV1 pure role/order/validation + sole scanner.

  Engineering static observation only. Not formal OutputSetV1 / TOCTOU /
  contained / hermetic publisher. Cleanup only under build/v2.
-/
import ProofForgeV2
import ProofForgeV2.Materialization.ArtifactContentV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Crypto

namespace Tests.Materialization.ArtifactContentV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectIoErrorContains (label needle : String) (act : IO Unit) : IO Unit := do
  try
    act
    throw <| IO.userError s!"{label}: expected failure containing {needle}"
  catch e =>
    let msg := toString e
    if (msg.splitOn label).length > 1 && (msg.splitOn "expected failure").length > 1 then
      throw e
    expect ((msg.splitOn needle).length > 1)
      s!"{label}: expected '{needle}' in:\n{msg}"

private def resetDir (p : FilePath) : IO Unit := do
  if ← p.pathExists then IO.FS.removeDirAll p
  IO.FS.createDirAll p

private def writeRel (root : FilePath) (rel content : String) : IO Unit := do
  let target := root / rel
  if let some parent := target.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile target content

/-! ## Pure role / order / validation -/

private def testRoleWireAndRank : IO Unit := do
  expect (ArtifactContentRoleV1.toWire .materializedBase == "materialized-base")
    "base wire"
  expect (ArtifactContentRoleV1.toWire .finalizedExtra == "finalized-extra")
    "extra wire"
  expect (ArtifactContentRoleV1.rank .materializedBase == 0) "base rank"
  expect (ArtifactContentRoleV1.rank .finalizedExtra == 1) "extra rank"
  expect (ArtifactContentRoleV1.ofWire? "materialized-base" == some .materializedBase)
    "parse base"
  expect (ArtifactContentRoleV1.ofWire? "finalized-extra" == some .finalizedExtra)
    "parse extra"
  expect (ArtifactContentRoleV1.ofWire? "other" == none) "reject unknown role"
  expect (ArtifactContentRoleV1.ofWire? "materializedBase" == none) "reject camel wire"

private def testClaimSortOrder : IO Unit := do
  let claims : Array ArtifactPathClaimV1 := #[
    { role := .finalizedExtra, path := "z.bin" },
    { role := .materializedBase, path := "b.txt" },
    { role := .materializedBase, path := "a.txt" },
    { role := .finalizedExtra, path := "a.extra" }
  ]
  let sorted := sortArtifactPathClaimsV1 claims
  expect (sorted.size == 4) "sort size"
  match sorted.toList with
  | c0 :: c1 :: c2 :: c3 :: [] =>
      expect (c0.role == .materializedBase && c0.path == "a.txt") "ord0"
      expect (c1.role == .materializedBase && c1.path == "b.txt") "ord1"
      expect (c2.role == .finalizedExtra && c2.path == "a.extra") "ord2"
      expect (c3.role == .finalizedExtra && c3.path == "z.bin") "ord3"
  | _ => throw <| IO.userError "sort size mismatch"

private def testClaimValidationNegatives : IO Unit := do
  expectIoErrorContains "unsafe" "unsafe artifact path" do
    validateArtifactPathClaimsV1 #[{ role := .materializedBase, path := "../x" }]
  expectIoErrorContains "empty" "unsafe artifact path" do
    validateArtifactPathClaimsV1 #[{ role := .materializedBase, path := "" }]
  expectIoErrorContains "abs" "unsafe artifact path" do
    validateArtifactPathClaimsV1 #[{ role := .materializedBase, path := "/tmp/x" }]
  expectIoErrorContains "control" "unsafe artifact path" do
    validateArtifactPathClaimsV1 #[{ role := .materializedBase, path := "a\tb" }]
  expectIoErrorContains "dup" "duplicate artifact path" do
    validateArtifactPathClaimsV1 #[
      { role := .materializedBase, path := "a.txt" },
      { role := .finalizedExtra, path := "a.txt" }
    ]
  expectIoErrorContains "prefix" "file/directory prefix conflict" do
    validateArtifactPathClaimsV1 #[
      { role := .materializedBase, path := "nested" },
      { role := .finalizedExtra, path := "nested/child.txt" }
    ]
  expectIoErrorContains "sidecar evidence" "sidecar path collides" do
    let _ ← validateArtifactClaimsAgainstAuxV1
      #[{ role := .materializedBase, path := "evidence.json" }]
      #[evidenceSidecarNameV1, manifestSidecarNameV1]
    pure ()
  expectIoErrorContains "sidecar manifest" "sidecar path collides" do
    let _ ← validateArtifactClaimsAgainstAuxV1
      #[{ role := .finalizedExtra, path := "manifest.json" }]
      #[evidenceSidecarNameV1, manifestSidecarNameV1]
    pure ()
  -- File count limit with aux.
  do
    let mut claims : Array ArtifactPathClaimV1 := #[]
    for i in [:maxEngineeringDiskClosureFilesV1] do
      claims := claims.push { role := .materializedBase, path := s!"f{i}.bin" }
    expectIoErrorContains "filecount" "too many closure files" do
      let _ ← validateArtifactClaimsAgainstAuxV1 claims #[evidenceSidecarNameV1]
      pure ()

private def testMetaObservationHelper : IO Unit := do
  let root := FilePath.mk "build/v2/artifact-content-meta"
  resetDir root
  writeRel root "t.bin" "hello"
  let md ← (root / "t.bin").symlinkMetadata
  let obs := observeFileMetaV1 md
  expect (obs.type == .file) "obs type file"
  expect (obs.numLinks == 1) "obs single link"
  expect (obs.byteSize.toNat == "hello".toUTF8.size) "obs size"
  -- Same snapshot compares equal.
  expect (obs == observeFileMetaV1 md) "obs beq"

/-! ## Real nested/flat scan + exact size/hash -/

private def testFlatScanExactHash : IO Unit := do
  let root := FilePath.mk "build/v2/artifact-content-flat"
  resetDir root
  let bodyA := "alpha-bytes\n"
  let bodyB := "beta-extra\n"
  writeRel root "a.txt" bodyA
  writeRel root "extra.bin" bodyB
  writeRel root "evidence.json" "{\"e\":1}\n"
  writeRel root "manifest.json" "{\"m\":1}\n"
  let claims : Array ArtifactPathClaimV1 := #[
    { role := .finalizedExtra, path := "extra.bin" },
    { role := .materializedBase, path := "a.txt" }
  ]
  let inv ← scanArtifactContentClosureV1 root claims
    #[evidenceSidecarNameV1, manifestSidecarNameV1]
  let ds := ArtifactContentInventoryV1.descriptorsOf inv
  expect (ds.size == 2) "inventory excludes aux"
  match ds.toList with
  | d0 :: d1 :: [] =>
      expect (d0.role == .materializedBase && d0.path == "a.txt") "first base"
      expect (d1.role == .finalizedExtra && d1.path == "extra.bin") "second extra"
      expect (d0.size == bodyA.toUTF8.size) "size a"
      expect (d1.size == bodyB.toUTF8.size) "size b"
      let ha := sha256Bytes bodyA.toUTF8
      let hb := sha256Bytes bodyB.toUTF8
      expect (d0.contentSha256.bytes == ha.bytes) "hash a"
      expect (d1.contentSha256.bytes == hb.bytes) "hash b"
  | _ => throw <| IO.userError "flat inventory size mismatch"
  validateArtifactContentInventoryV1 inv

private def testNestedScanExactHash : IO Unit := do
  let root := FilePath.mk "build/v2/artifact-content-nested"
  resetDir root
  let body := "nested-rel\n"
  writeRel root "relations/Main.nr" body
  writeRel root "Nargo.toml" "[package]\n"
  writeRel root "evidence.json" "{}\n"
  writeRel root "manifest.json" "{}\n"
  let claims : Array ArtifactPathClaimV1 := #[
    { role := .materializedBase, path := "Nargo.toml" },
    { role := .materializedBase, path := "relations/Main.nr" }
  ]
  let inv ← scanArtifactContentClosureV1 root claims
    #[evidenceSidecarNameV1, manifestSidecarNameV1]
  let ds := ArtifactContentInventoryV1.descriptorsOf inv
  expect (ds.size == 2) "nested inventory size"
  match ds.toList with
  | d0 :: d1 :: [] =>
      -- Path UTF-8 order within same role: Nargo.toml < relations/Main.nr
      expect (d0.path == "Nargo.toml") "nested ord0"
      expect (d1.path == "relations/Main.nr") "nested ord1"
      expect (d1.contentSha256.bytes == (sha256Bytes body.toUTF8).bytes) "nested hash"
  | _ => throw <| IO.userError "nested inventory size mismatch"

private def testContentMutationChangesInventory : IO Unit := do
  let root := FilePath.mk "build/v2/artifact-content-mutate"
  resetDir root
  writeRel root "a.txt" "v1\n"
  writeRel root "evidence.json" "{}\n"
  writeRel root "manifest.json" "{}\n"
  let claims : Array ArtifactPathClaimV1 := #[
    { role := .materializedBase, path := "a.txt" }
  ]
  let inv1 ← scanArtifactContentClosureV1 root claims
    #[evidenceSidecarNameV1, manifestSidecarNameV1]
  writeRel root "a.txt" "v2-mutated\n"
  let inv2 ← scanArtifactContentClosureV1 root claims
    #[evidenceSidecarNameV1, manifestSidecarNameV1]
  expect (!(ArtifactContentInventoryV1.beq inv1 inv2)) "mutation changes inventory"
  match (ArtifactContentInventoryV1.descriptorsOf inv1).toList,
        (ArtifactContentInventoryV1.descriptorsOf inv2).toList with
  | d1 :: [], d2 :: [] =>
      expect (d1.contentSha256.bytes != d2.contentSha256.bytes) "hash changed"
      expect (d1.size != d2.size) "size changed"
  | _, _ => throw <| IO.userError "mutation inventory shape"

private def testArtifactOnlyScanNoAux : IO Unit := do
  let root := FilePath.mk "build/v2/artifact-content-noaux"
  resetDir root
  writeRel root "only.txt" "solo\n"
  -- No sidecars present; aux empty.
  let inv ← scanArtifactContentClosureV1 root
    #[{ role := .materializedBase, path := "only.txt" }] #[]
  expect (ArtifactContentInventoryV1.size inv == 1) "no-aux size"
  -- Extra unlisted sidecar would fail if present.
  writeRel root "evidence.json" "{}\n"
  expectIoErrorContains "extra aux file" "unexpected file" do
    let _ ← scanArtifactContentClosureV1 root
      #[{ role := .materializedBase, path := "only.txt" }] #[]
    pure ()

/-! ## Physical negatives -/

private def testPhysicalNegatives : IO Unit := do
  -- Missing leaf.
  do
    let root := FilePath.mk "build/v2/artifact-content-missing"
    resetDir root
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    expectIoErrorContains "missing" "missing regular file" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "gone.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
  -- Extra file.
  do
    let root := FilePath.mk "build/v2/artifact-content-extra"
    resetDir root
    writeRel root "a.txt" "a\n"
    writeRel root "noise.txt" "n\n"
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    expectIoErrorContains "extra" "unexpected file" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "a.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
  -- Symlink file.
  do
    let root := FilePath.mk "build/v2/artifact-content-symlink"
    resetDir root
    writeRel root "real.txt" "r\n"
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    let _ ← IO.Process.output {
      cmd := "ln"
      args := #["-s", "real.txt", (root / "link.txt").toString]
    }
    expectIoErrorContains "symlink" "symbolic link" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "real.txt" },
          { role := .materializedBase, path := "link.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
  -- FIFO.
  do
    let root := FilePath.mk "build/v2/artifact-content-fifo"
    resetDir root
    writeRel root "a.txt" "a\n"
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    let _ ← IO.Process.output {
      cmd := "mkfifo"
      args := #[(root / "pipe.fifo").toString]
    }
    expectIoErrorContains "fifo" "non-regular" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "a.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
  -- Hardlink (numLinks != 1).
  do
    let root := FilePath.mk "build/v2/artifact-content-hardlink"
    resetDir root
    writeRel root "a.txt" "shared\n"
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    let _ ← IO.Process.output {
      cmd := "ln"
      args := #[(root / "a.txt").toString, (root / "b.txt").toString]
    }
    -- Walk sees unexpected b.txt if not claimed; claim both same content via two paths.
    expectIoErrorContains "hardlink extra" "unexpected file" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "a.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
    -- Claim both hardlinks: content phase rejects numLinks != 1.
    expectIoErrorContains "hardlink nlink" "single-link" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "a.txt" },
          { role := .finalizedExtra, path := "b.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
  -- Auxiliary sidecars use the same single-link content observation.
  do
    let parent := FilePath.mk "build/v2/artifact-content-aux-hardlink"
    resetDir parent
    let root := parent / "staging"
    IO.FS.createDirAll root
    writeRel root "a.txt" "artifact\n"
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    let _ ← IO.Process.output {
      cmd := "ln"
      args := #[(root / "evidence.json").toString,
        (parent / "evidence-peer.json").toString]
    }
    expectIoErrorContains "aux hardlink nlink" "single-link" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "a.txt" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
  -- Per-file size limit (metadata before read).
  do
    let root := FilePath.mk "build/v2/artifact-content-filesize"
    resetDir root
    writeRel root "evidence.json" "{}\n"
    writeRel root "manifest.json" "{}\n"
    let target := root / "big.bin"
    let over := maxEngineeringDiskClosureFileBytesV1 + 1
    let _ ← IO.Process.output {
      cmd := "dd"
      args := #["if=/dev/zero", s!"of={target}", "bs=1", s!"count=0",
        s!"seek={over}", "status=none"]
    }
    expectIoErrorContains "filesize" "PF-OUTPUT-LIMIT" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "big.bin" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()
    expectIoErrorContains "filesize msg" "file exceeds size limit" do
      let _ ← scanArtifactContentClosureV1 root
        #[{ role := .materializedBase, path := "big.bin" }]
        #[evidenceSidecarNameV1, manifestSidecarNameV1]
      pure ()

private def testSoleScannerPin : IO Unit := do
  let (ec, hits) ← do
    let out ← IO.Process.output {
      cmd := "rg"
      args := #["--glob", "*.lean", "-n", "--no-heading",
        "^\\s*def scanArtifactContentClosureV1\\b", "ProofForgeV2"]
    }
    pure (out.exitCode, out.stdout)
  expect (ec == 0) s!"scanArtifactContentClosureV1 must exist:\n{hits}"
  let lines := (hits.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (lines.length == 1)
    s!"sole scanArtifactContentClosureV1, got {lines.length}:\n{hits}"
  expect ((hits.splitOn "ArtifactContentV1.lean").length > 1)
    "sole scanner must live in ArtifactContentV1.lean"
  -- EngineeringDiskClosure must not reimplement walkPhysicalClosure.
  let (ec2, hits2) ← do
    let out ← IO.Process.output {
      cmd := "rg"
      args := #["--glob", "*.lean", "-n", "--no-heading",
        "walkPhysicalClosure", "ProofForgeV2/Materialization"]
    }
    pure (out.exitCode, out.stdout)
  -- Only private helper in ArtifactContentV1 (walkPhysicalClosureV1).
  expect (ec2 == 0 || ec2 == 1) "rg walkPhysicalClosure"
  expect ((hits2.splitOn "EngineeringDiskClosureV1.lean").length == 1)
    s!"EngineeringDiskClosure must not define walkPhysicalClosure:\n{hits2}"

unsafe def run : IO Unit := do
  testRoleWireAndRank
  testClaimSortOrder
  testClaimValidationNegatives
  testMetaObservationHelper
  testFlatScanExactHash
  testNestedScanExactHash
  testContentMutationChangesInventory
  testArtifactOnlyScanNoAux
  testPhysicalNegatives
  testSoleScannerPin
  IO.println "Tests.Materialization.ArtifactContentV1: ok"

end Tests.Materialization.ArtifactContentV1
