/-
  Noir ACIR / nargo ProgramArtifact inventory (NOIR-IR-1 + NOIR-IR-4).

  Engineering authority for the frozen golden under
  `testdata/golden/noir-acir-v1/`:

  * IR-1 Counter: product Noir relation packages + path-normalized nargo
    ProgramArtifact JSON (`file_map.*.path` → package-relative `src/main.nr`)
  * IR-4 multi-fixture: path-normalized ProgramArtifact inventory for G3
    admit surfaces that nargo-compile successfully (BranchCounter / LoopSum /
    OptionState / ArrayRet full capture + MapMini **init only**). Product
    source leaves for fixtures are **not** frozen (not a full byte matrix);
    MapMini put/get stay nargo-fail honesty residuals with no inventory leaves.

  Honesty:
  * Multi-file exact SHA-256 inventory + ProgramArtifact envelope field pins.
  * Does **not** decode ACIR opcodes (bytecode remains base64(gzip(ACIR))).
  * Does **not** claim prove/verify, deployable, or formal.
  * IR-6: default Finalize zero-tool; opt-in nargo ACIR profile dual-writes
    path-normalized ProgramArtifact as finalized-extra (still non-deployable).

  Schema ids:
  * Counter inventory: `proof-forge.noir-acir-inventory.v1`
  * Admit multi-fixture inventory doc: `proof-forge.noir-acir-admit-inventory.v1`
-/
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2.Targets.Noir.Acir.InventoryV1

open ProofForgeV2

/-- Engineering schema id for this inventory / envelope pin surface. -/
def schemaIdV1 : String := "proof-forge.noir-acir-inventory.v1"

/-- Engineering schema id for IR-4 multi-fixture admit inventory documentation. -/
def admitInventorySchemaIdV1 : String :=
  "proof-forge.noir-acir-admit-inventory.v1"

/-- Golden directory root (repo-relative). -/
def goldenRootV1 : String := "testdata/golden/noir-acir-v1"

/-- IR-4 admit inventory JSON leaf under golden root. -/
def admitInventoryRelPathV1 : String := "inventory-admit.json"

/-- Tool Lock nargo version pin (short). -/
def nargoVersionV1 : String := "1.0.0-beta.26"

/-- Exact `noir_version` string embedded in ProgramArtifact JSON. -/
def noirVersionExactV1 : String :=
  "1.0.0-beta.26+40d6574f851d926f93e0c3a271bac3e6e82ac905"

/-- nargo git hash component of `noirVersionExactV1`. -/
def nargoGitHashV1 : String :=
  "40d6574f851d926f93e0c3a271bac3e6e82ac905"

/-- Product profile that emitted the golden packages. -/
def productProfileV1 : String := "noir-source-u64-relations-v1"

/-- Golden program module. -/
def goldenProgramModuleV1 : String := "Examples.Counter"

/-- Required top-level keys of nargo 1.0.0-beta.26 ProgramArtifact JSON
    (observed; unknown extra keys fail closed at envelope check). -/
def programArtifactRequiredKeysV1 : Array String :=
  #["noir_version", "hash", "abi", "bytecode", "debug_symbols", "file_map"]

/-- Path-normalized package-relative source path written into golden
    `file_map.*.path`. Host absolute paths are **not** golden identity. -/
def normalizedSourcePathV1 : String := "src/main.nr"

/-- One inventory leaf: repo-relative path under golden root, exact size,
    exact SHA-256 of file bytes. -/
structure InventoryEntryV1 where
  relPath : String
  size : Nat
  sha256Hex : String
  deriving Repr, BEq, Inhabited

/-- Frozen multi-file inventory (path-sorted). Sizes/hashes captured from
    locked nargo 1.0.0-beta.26 on Examples/Counter product packages with
    path-normalized ProgramArtifact JSON. -/
def inventoryEntriesV1 : Array InventoryEntryV1 :=
  #[
    { relPath := "nargo-compile/r0-init/pf_relation_0.json"
      size := 1343
      sha256Hex :=
        "90113b872a13f2cdcc8db7acd9d5b4e10829015f726fdd9e39ade75e6f429dfd" },
    { relPath := "nargo-compile/r1-increment/pf_relation_1.json"
      size := 1816
      sha256Hex :=
        "140c8fbd22f87826759a7e7fe8df165efb5a664d54c8563aed60f4644d2125f6" },
    { relPath := "nargo-compile/r2-get/pf_relation_2.json"
      size := 1510
      sha256Hex :=
        "2509aabd7b3e4a90afc59c73e3b2b0868f7a46aaf2a206475d01ce4547309976" },
    { relPath := "product/Counter.noir-relations.json"
      size := 2694
      sha256Hex :=
        "405842221219e2d910c8d6fcb16cadb9c8ea0e148d020d652eefc9d12deb3ed7" },
    { relPath := "product/relations/r0-init/Nargo.toml"
      size := 74
      sha256Hex :=
        "22be6c4c3537c091cc0cdd053ce799f02aa2a9ac0923cecc68ffe1ec6ff64eb3" },
    { relPath := "product/relations/r0-init/src/main.nr"
      size := 209
      sha256Hex :=
        "0cbe64f5935b2444b275c2d4e050f3cac68cf0bff81ff521701e8f846864505f" },
    { relPath := "product/relations/r1-increment/Nargo.toml"
      size := 74
      sha256Hex :=
        "8e363e3997222567815d17af032e382b4ca4d9d102cf4ca747783069e358c81f" },
    { relPath := "product/relations/r1-increment/src/main.nr"
      size := 299
      sha256Hex :=
        "0456dfe54e6bf6bf51c886fa162d10f5b91102d3bb67d4368c20738643118059" },
    { relPath := "product/relations/r2-get/Nargo.toml"
      size := 74
      sha256Hex :=
        "03f5a6e2391ed4e67d7e093716df7555d180cf134ab30eab0f9a9fa6d570d3cc" },
    { relPath := "product/relations/r2-get/src/main.nr"
      size := 255
      sha256Hex :=
        "e081745332ca9e36b691e435f68357d0d168f2400ed44f801f5727b58e12c382" }
  ]

/-- nargo ProgramArtifact `hash` field (decimal string) for each Counter
    relation package — path-independent circuit identity under the pinned
    nargo. -/
def circuitHashR0InitV1 : String := "17547139497077004670"
def circuitHashR1IncrementV1 : String := "13787203750271229385"
def circuitHashR2GetV1 : String := "15142158172902813876"

structure CircuitHashPinV1 where
  relation : String
  artifactRelPath : String
  circuitHash : String
  deriving Repr, BEq, Inhabited

def circuitHashPinsV1 : Array CircuitHashPinV1 :=
  #[
    { relation := "r0-init"
      artifactRelPath := "nargo-compile/r0-init/pf_relation_0.json"
      circuitHash := circuitHashR0InitV1 },
    { relation := "r1-increment"
      artifactRelPath := "nargo-compile/r1-increment/pf_relation_1.json"
      circuitHash := circuitHashR1IncrementV1 },
    { relation := "r2-get"
      artifactRelPath := "nargo-compile/r2-get/pf_relation_2.json"
      circuitHash := circuitHashR2GetV1 }
  ]

/-! ### NOIR-IR-4 multi-fixture admit inventory

  Path-normalized ProgramArtifact JSON only (no product-source matrix).
  14 leaves = G3 success capture pins. MapMini put/get intentionally absent.
-/

/-- Frozen IR-4 multi-fixture inventory (path-sorted). 14 nargo-ok relations
    under `fixtures/{FixtureId}/nargo-compile/{stem}/pf_relation_N.json`. -/
def admitInventoryEntriesV1 : Array InventoryEntryV1 :=
  #[
    { relPath := "fixtures/ArrayRet/nargo-compile/r0-init/pf_relation_0.json"
      size := 1638
      sha256Hex :=
        "3126733018a681a509bd73676334b48cb944c083192ed58b7fe16853fe7fbe28" },
    { relPath := "fixtures/ArrayRet/nargo-compile/r1-setArr/pf_relation_1.json"
      size := 2218
      sha256Hex :=
        "8cbcf7d16db1116d4d8821ac65f7c867a8a242d3d106ba60db6cea8e5fe5ec9c" },
    { relPath := "fixtures/ArrayRet/nargo-compile/r2-getArr/pf_relation_2.json"
      size := 1985
      sha256Hex :=
        "cbd953acf863f318b9b79adc9e6096028f8f63d1a1368a0462c55cf9e1cdd645" },
    { relPath :=
        "fixtures/BranchCounter/nargo-compile/r0-init/pf_relation_0.json"
      size := 1343
      sha256Hex :=
        "90113b872a13f2cdcc8db7acd9d5b4e10829015f726fdd9e39ade75e6f429dfd" },
    { relPath :=
        "fixtures/BranchCounter/nargo-compile/r1-bump/pf_relation_1.json"
      size := 2749
      sha256Hex :=
        "4a8e32173ed7386e4e8fa6ed89862d2ce797a13b6566bd46a044689086bd49ae" },
    { relPath :=
        "fixtures/BranchCounter/nargo-compile/r2-get/pf_relation_2.json"
      size := 1510
      sha256Hex :=
        "2509aabd7b3e4a90afc59c73e3b2b0868f7a46aaf2a206475d01ce4547309976" },
    { relPath := "fixtures/LoopSum/nargo-compile/r0-init/pf_relation_0.json"
      size := 1343
      sha256Hex :=
        "90113b872a13f2cdcc8db7acd9d5b4e10829015f726fdd9e39ade75e6f429dfd" },
    { relPath := "fixtures/LoopSum/nargo-compile/r1-run/pf_relation_1.json"
      size := 7571
      sha256Hex :=
        "fe78b804230e9e892e687d4028f69fef64acf59ffa1af6516eee0759842d233f" },
    { relPath := "fixtures/LoopSum/nargo-compile/r2-get/pf_relation_2.json"
      size := 1510
      sha256Hex :=
        "2509aabd7b3e4a90afc59c73e3b2b0868f7a46aaf2a206475d01ce4547309976" },
    { relPath := "fixtures/MapMini/nargo-compile/r0-init/pf_relation_0.json"
      size := 4898
      sha256Hex :=
        "07eef853ba06667b1e074528df7cd620e56a8bee16597876effbdcde3a6cbcd6" },
    { relPath :=
        "fixtures/OptionState/nargo-compile/r0-init/pf_relation_0.json"
      size := 1315
      sha256Hex :=
        "8b5db577300045f5e01cb931af3f45c8c489b4a75d843bb5492232f74a950e8a" },
    { relPath :=
        "fixtures/OptionState/nargo-compile/r1-setSome/pf_relation_1.json"
      size := 1911
      sha256Hex :=
        "7f0f16eae85432e46725677d6c992f8cf0933b371a562d2a9b998fde42c8257b" },
    { relPath :=
        "fixtures/OptionState/nargo-compile/r2-clear/pf_relation_2.json"
      size := 1761
      sha256Hex :=
        "52738ce970dc93b6fb7eb6a15421a50ea9b116f55061ff0cfad5f55c19727bf3" },
    { relPath :=
        "fixtures/OptionState/nargo-compile/r3-peek/pf_relation_3.json"
      size := 2463
      sha256Hex :=
        "a1badd71d7e2dd1b0b0068a200ba4f448a4eb2a8f478c5056b723c9edac9b428" }
  ]

/-- Expected admit inventory leaf count (G3 success pins). -/
def admitInventoryEntryCountV1 : Nat := 14

/-- One IR-4 admit inventory pin: fixture + relation + golden path + circuit hash. -/
structure AdmitInventoryPinV1 where
  fixtureId : String
  relation : String
  packageArtifactName : String
  artifactRelPath : String
  circuitHash : String
  deriving Repr, BEq, Inhabited

/-- Frozen IR-4 admit inventory pins (fixture-order then relation source order).
    Aligns with `CaptureV1.admitSurfaceFixturesV1` capturePins. -/
def admitInventoryPinsV1 : Array AdmitInventoryPinV1 :=
  #[
    { fixtureId := "BranchCounter"
      relation := "r0-init"
      packageArtifactName := "pf_relation_0.json"
      artifactRelPath :=
        "fixtures/BranchCounter/nargo-compile/r0-init/pf_relation_0.json"
      circuitHash := "17547139497077004670" },
    { fixtureId := "BranchCounter"
      relation := "r1-bump"
      packageArtifactName := "pf_relation_1.json"
      artifactRelPath :=
        "fixtures/BranchCounter/nargo-compile/r1-bump/pf_relation_1.json"
      circuitHash := "5326684273681879262" },
    { fixtureId := "BranchCounter"
      relation := "r2-get"
      packageArtifactName := "pf_relation_2.json"
      artifactRelPath :=
        "fixtures/BranchCounter/nargo-compile/r2-get/pf_relation_2.json"
      circuitHash := "15142158172902813876" },
    { fixtureId := "LoopSum"
      relation := "r0-init"
      packageArtifactName := "pf_relation_0.json"
      artifactRelPath :=
        "fixtures/LoopSum/nargo-compile/r0-init/pf_relation_0.json"
      circuitHash := "17547139497077004670" },
    { fixtureId := "LoopSum"
      relation := "r1-run"
      packageArtifactName := "pf_relation_1.json"
      artifactRelPath :=
        "fixtures/LoopSum/nargo-compile/r1-run/pf_relation_1.json"
      circuitHash := "1663100142809567421" },
    { fixtureId := "LoopSum"
      relation := "r2-get"
      packageArtifactName := "pf_relation_2.json"
      artifactRelPath :=
        "fixtures/LoopSum/nargo-compile/r2-get/pf_relation_2.json"
      circuitHash := "15142158172902813876" },
    { fixtureId := "OptionState"
      relation := "r0-init"
      packageArtifactName := "pf_relation_0.json"
      artifactRelPath :=
        "fixtures/OptionState/nargo-compile/r0-init/pf_relation_0.json"
      circuitHash := "15390717378386485224" },
    { fixtureId := "OptionState"
      relation := "r1-setSome"
      packageArtifactName := "pf_relation_1.json"
      artifactRelPath :=
        "fixtures/OptionState/nargo-compile/r1-setSome/pf_relation_1.json"
      circuitHash := "12137904358083423139" },
    { fixtureId := "OptionState"
      relation := "r2-clear"
      packageArtifactName := "pf_relation_2.json"
      artifactRelPath :=
        "fixtures/OptionState/nargo-compile/r2-clear/pf_relation_2.json"
      circuitHash := "12246679460574536583" },
    { fixtureId := "OptionState"
      relation := "r3-peek"
      packageArtifactName := "pf_relation_3.json"
      artifactRelPath :=
        "fixtures/OptionState/nargo-compile/r3-peek/pf_relation_3.json"
      circuitHash := "4152353602006729362" },
    { fixtureId := "ArrayRet"
      relation := "r0-init"
      packageArtifactName := "pf_relation_0.json"
      artifactRelPath :=
        "fixtures/ArrayRet/nargo-compile/r0-init/pf_relation_0.json"
      circuitHash := "10250360699151576765" },
    { fixtureId := "ArrayRet"
      relation := "r1-setArr"
      packageArtifactName := "pf_relation_1.json"
      artifactRelPath :=
        "fixtures/ArrayRet/nargo-compile/r1-setArr/pf_relation_1.json"
      circuitHash := "5874709250556069158" },
    { fixtureId := "ArrayRet"
      relation := "r2-getArr"
      packageArtifactName := "pf_relation_2.json"
      artifactRelPath :=
        "fixtures/ArrayRet/nargo-compile/r2-getArr/pf_relation_2.json"
      circuitHash := "292703840847091457" },
    { fixtureId := "MapMini"
      relation := "r0-init"
      packageArtifactName := "pf_relation_0.json"
      artifactRelPath :=
        "fixtures/MapMini/nargo-compile/r0-init/pf_relation_0.json"
      circuitHash := "996379632831450032" }
  ]

/-- Fixture ids that have IR-4 inventory leaves (MapMini included for init only). -/
def admitInventoryFixtureIdsV1 : Array String :=
  #["ArrayRet", "BranchCounter", "LoopSum", "MapMini", "OptionState"]

/-- Resolve an inventory entry path under the golden root. -/
def goldenPathV1 (relPath : String) : System.FilePath :=
  System.FilePath.mk goldenRootV1 / relPath

/-- SHA-256 hex of raw file bytes (same pure Crypto as the rest of V2). -/
def hashFileBytesV1 (bytes : ByteArray) : String :=
  Crypto.sha256Hex bytes

/-- Minimal ProgramArtifact envelope check on UTF-8 text:
    required top-level key strings appear as `"key":` JSON object keys.
    This is **not** a full JSON parser and does not decode ACIR. -/
def envelopeKeysPresentV1 (text : String) : Bool :=
  programArtifactRequiredKeysV1.all fun key =>
    text.contains s!"\"{key}\":"

/-- Exact noir_version pin appears in artifact text. -/
def noirVersionPresentV1 (text : String) : Bool :=
  text.contains noirVersionExactV1

/-- Normalized source path pin appears in artifact text. -/
def normalizedPathPresentV1 (text : String) : Bool :=
  text.contains s!"\"path\":\"{normalizedSourcePathV1}\""

/-- Circuit hash pin appears in artifact text as JSON string value. -/
def circuitHashPresentV1 (text circuitHash : String) : Bool :=
  text.contains s!"\"hash\":\"{circuitHash}\""

end ProofForgeV2.Targets.Noir.Acir.InventoryV1
