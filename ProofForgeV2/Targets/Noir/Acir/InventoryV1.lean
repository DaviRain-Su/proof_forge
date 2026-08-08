/-
  Noir ACIR / nargo ProgramArtifact inventory (NOIR-IR-1).

  Engineering authority for the frozen Counter golden under
  `testdata/golden/noir-acir-v1/`:

  * Product Noir relation packages (Nargo.toml + src/main.nr + relations JSON)
  * Locked nargo 1.0.0-beta.26 `nargo compile` ProgramArtifact JSON
    (path-normalized: `file_map.*.path` rewritten to package-relative
    `src/main.nr`)

  Honesty (IR-1):
  * Multi-file exact SHA-256 inventory + ProgramArtifact envelope field pins.
  * Does **not** decode ACIR opcodes (bytecode remains base64(gzip(ACIR))).
  * Does **not** claim Plan→ACIR, prove/verify, deployable, or formal.
  * Product Finalize remains source-only / non-deployable until a later slice.

  Schema id: `proof-forge.noir-acir-inventory.v1`
-/
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2.Targets.Noir.Acir.InventoryV1

open ProofForgeV2

/-- Engineering schema id for this inventory / envelope pin surface. -/
def schemaIdV1 : String := "proof-forge.noir-acir-inventory.v1"

/-- Golden directory root (repo-relative). -/
def goldenRootV1 : String := "testdata/golden/noir-acir-v1"

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
