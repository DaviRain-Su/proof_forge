/-
  Noir Plan → ACIR capture (NOIR-IR-2 + NOIR-IR-3 / G3).

  ## Path decision (IR-2, frozen)

  **nargo-assisted capture** is the sole authority path. A pure-Lean ACIR
  opcode encoder is **not** implemented and is **not** claimed.

  ```
  ProgramV1 → Semantic → NoirPlan → relation IR → product .nr packages
       (EmitIRV1 transitional source emission; remains product OutputFile)
                              │
                              ▼
               locked nargo 1.0.0-beta.26 `nargo compile`
                              │
                              ▼
               ProgramArtifact JSON circuit core
                 (noir_version, hash, bytecode=base64(gzip ACIR))
                              │
                              ▼
               ≡ testdata/golden/noir-acir-v1/ (IR-1 inventory, Counter)
                 + G3 admit-surface circuit-hash pins (IR-3)
  ```

  Transitivity pin (always available without nargo):

  * Product Plan emit of Examples/Counter `.nr` + `Nargo.toml` must be
    byte-identical to frozen golden product packages.
  * Golden product packages were compiled under pinned nargo to produce
    golden ProgramArtifact JSON (IR-1).
  * Therefore Plan → ACIR identity for Counter holds by construction when
    the source-join pin holds; live nargo recompile is the stronger
    host-heavy check (tool-optional, honest skip when nargo missing).

  ## IR-3 / G3 admit surface

  Control-flow and aggregate fixtures already admitted by Noir Plan emit
  gain **circuit-core hash pins** under the same nargo-assisted path:

  * BranchCounter — if / else (control flow)
  * LoopSum — bounded for static unroll (control flow)
  * OptionState — Option UInt64 state + match (aggregate)
  * ArrayRet — Array UInt64 2 state/return (aggregate)
  * MapMini — Plan materialize admitted; **init** nargo capture succeeds;
    **put/get** nargo type-check fails (honesty residual, not silent pass)

  Live capture is optional: missing nargo → honest skip of live paths only
  (Counter inventory/source-join and fixture materialize package-stem pins
  still run). Does **not** expand full multi-file golden inventory for every
  fixture (that is IR-4); G3 pins are circuit-hash (+ package stem) only.

  Honesty:
  * `deployable=false`; no prove/verify/VK/witness product claim.
  * Product Finalize remains source-only (no ACIR OutputFile — IR-6).
  * Capture is host-heavy / non-hermetic when nargo is invoked.
  * Does **not** decode ACIR opcodes (bytecode stays opaque base64 gzip).
  * Does **not** invent a backend when nargo is absent.

  Schema id: `proof-forge.noir-acir-capture.v1`
-/
import ProofForgeV2.Targets.Noir.Acir.InventoryV1
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2.Targets.Noir.Acir.CaptureV1

open ProofForgeV2
open ProofForgeV2.Targets.Noir.Acir.InventoryV1
open System

/-- Engineering schema id for Plan→ACIR capture surface. -/
def schemaIdV1 : String := "proof-forge.noir-acir-capture.v1"

/-- Frozen IR-2 path decision label. -/
def pathDecisionV1 : String := "nargo-assisted"

/-- Human-readable authority note (docs/tests join). -/
def authorityNoteV1 : String :=
  "Plan→ACIR MVP authority is nargo-assisted capture of ProgramArtifact " ++
  "circuit core (noir_version+hash+bytecode) from product Plan .nr packages " ++
  "via locked nargo 1.0.0-beta.26; pure-Lean ACIR opcode encoder is not " ++
  "implemented; .nr remains transitional product emission until IR-6; " ++
  "G3 admit-surface CF/aggregate circuit-hash pins share this path; " ++
  "missing nargo → honest skip of live capture only"

/-- Path-independent circuit core of a nargo ProgramArtifact.
    Absolute `file_map.path` and debug_symbols are intentionally excluded. -/
structure CircuitCoreV1 where
  noirVersion : String
  circuitHash : String
  bytecodeB64 : String
  deriving Repr, BEq, Inhabited

/-- One Counter relation capture pin: package stem + nargo artifact name +
    expected circuit hash (from IR-1 inventory). -/
structure RelationCapturePinV1 where
  relation : String
  packageArtifactName : String
  productRelDir : String
  goldenArtifactRelPath : String
  expectedCircuitHash : String
  deriving Repr, BEq, Inhabited

/-- Frozen Counter three-relation capture pins (source order: init, increment, get). -/
def counterRelationPinsV1 : Array RelationCapturePinV1 :=
  #[
    { relation := "r0-init"
      packageArtifactName := "pf_relation_0.json"
      productRelDir := "product/relations/r0-init"
      goldenArtifactRelPath := "nargo-compile/r0-init/pf_relation_0.json"
      expectedCircuitHash := circuitHashR0InitV1 },
    { relation := "r1-increment"
      packageArtifactName := "pf_relation_1.json"
      productRelDir := "product/relations/r1-increment"
      goldenArtifactRelPath := "nargo-compile/r1-increment/pf_relation_1.json"
      expectedCircuitHash := circuitHashR1IncrementV1 },
    { relation := "r2-get"
      packageArtifactName := "pf_relation_2.json"
      productRelDir := "product/relations/r2-get"
      goldenArtifactRelPath := "nargo-compile/r2-get/pf_relation_2.json"
      expectedCircuitHash := circuitHashR2GetV1 }
  ]

/-- Extract a top-level JSON string field (`"key":"..."`) from compact nargo
    ProgramArtifact text. Not a full JSON parser; sufficient for the six-key
    envelope frozen in IR-1. -/
def extractJsonStringFieldV1 (text key : String) : Option String :=
  let needle := s!"\"{key}\":\""
  match text.splitOn needle with
  | [_, rest] =>
      match rest.splitOn "\"" with
      | value :: _ => some value
      | [] => none
  | _ => none

/-- Parse path-independent circuit core from ProgramArtifact UTF-8 text. -/
def extractCircuitCoreV1 (text : String) : Option CircuitCoreV1 := do
  let noirVersion ← extractJsonStringFieldV1 text "noir_version"
  let circuitHash ← extractJsonStringFieldV1 text "hash"
  let bytecodeB64 ← extractJsonStringFieldV1 text "bytecode"
  pure { noirVersion, circuitHash, bytecodeB64 }

/-- Exact circuit-core equality (noir_version + hash + bytecode). -/
def circuitCoresEqualV1 (a b : CircuitCoreV1) : Bool :=
  a.noirVersion == b.noirVersion &&
    a.circuitHash == b.circuitHash &&
    a.bytecodeB64 == b.bytecodeB64

/-- Whether a circuit core matches the Tool Lock exact nargo version pin and
    a frozen expected circuit hash (bytecode compared by caller against golden). -/
def circuitCoreMatchesPinsV1 (core : CircuitCoreV1) (expectedHash : String) : Bool :=
  core.noirVersion == noirVersionExactV1 &&
    core.circuitHash == expectedHash

/-- SHA-256 hex of UTF-8 file bytes (same pure Crypto as inventory). -/
def hashUtf8V1 (text : String) : String :=
  Crypto.sha256Hex text.toUTF8

/-- Resolve locked / ambient nargo binary path. Returns `none` when absent
    (callers must honest-skip; do not invent a backend). -/
def resolveNargoPathV1 : IO (Option String) := do
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

/-- Run `nargo compile --silence-warnings` in `packageDir` and capture the
    ProgramArtifact circuit core for `artifactName` under `target/`.

    Host-heavy / non-hermetic. Caller must have already resolved a real nargo. -/
def compilePackageCaptureCircuitCoreV1
    (nargo : String) (packageDir : FilePath) (artifactName : String) :
    IO CircuitCoreV1 := do
  let process ← IO.Process.output {
    cmd := nargo
    args := #["compile", "--silence-warnings"]
    cwd := some packageDir
  }
  unless process.exitCode == 0 do
    throw <| IO.userError
      (s!"nargo-assisted capture: nargo compile failed in {packageDir}\n" ++
        process.stdout ++ process.stderr)
  let livePath := packageDir / "target" / artifactName
  unless ← livePath.pathExists do
    throw <| IO.userError
      s!"nargo-assisted capture: missing ProgramArtifact {livePath}"
  let raw ← IO.FS.readFile livePath
  match extractCircuitCoreV1 raw with
  | some core => pure core
  | none =>
      throw <| IO.userError
        s!"nargo-assisted capture: cannot extract circuit core from {livePath}"

/-- Load frozen golden ProgramArtifact circuit core for a Counter relation pin. -/
def loadGoldenCircuitCoreV1 (pin : RelationCapturePinV1) : IO CircuitCoreV1 := do
  let path := goldenPathV1 pin.goldenArtifactRelPath
  unless ← path.pathExists do
    throw <| IO.userError s!"missing golden artifact {path}"
  let text ← IO.FS.readFile path
  match extractCircuitCoreV1 text with
  | some core =>
      unless circuitCoreMatchesPinsV1 core pin.expectedCircuitHash do
        throw <| IO.userError
          s!"golden {pin.relation}: circuit pin mismatch (version/hash)"
      pure core
  | none =>
      throw <| IO.userError
        s!"golden {pin.relation}: cannot extract circuit core"

/-- Product source leaves under a relation package (transitional .nr path). -/
def productSourceLeafNamesV1 : Array String :=
  #["Nargo.toml", "src/main.nr"]

/-- Exact byte-join of product Plan emit package directory against frozen
    golden product package for one Counter relation. -/
def productPackageSourceJoinV1
    (livePackageDir : FilePath) (pin : RelationCapturePinV1) : IO Unit := do
  for leaf in productSourceLeafNamesV1 do
    let livePath := livePackageDir / leaf
    let goldPath := goldenPathV1 (pin.productRelDir ++ "/" ++ leaf)
    unless ← livePath.pathExists do
      throw <| IO.userError
        s!"product source join {pin.relation}: missing live {livePath}"
    unless ← goldPath.pathExists do
      throw <| IO.userError
        s!"product source join {pin.relation}: missing golden {goldPath}"
    let live ← IO.FS.readBinFile livePath
    let gold ← IO.FS.readBinFile goldPath
    unless live == gold do
      throw <| IO.userError
        (s!"product source join {pin.relation}/{leaf}: live≠golden " ++
          s!"(live sha={hashFileBytesV1 live} gold sha={hashFileBytesV1 gold})")

/-! ### IR-3 / G3 admit-surface circuit-hash pins

  Product Plan materialize → nargo-assisted capture for control-flow and
  aggregate fixtures already admitted by Noir Plan. Pins are path-independent
  circuit hashes under locked nargo 1.0.0-beta.26 (not full multi-file inventory;
  IR-4 may expand goldens later).
-/

/-- Admit-surface family label (honesty matrix join). -/
inductive AdmitSurfaceFamilyV1 where
  | controlFlowIf
  | controlFlowFor
  | aggregateOption
  | aggregateArray
  | aggregateMapPartial
  deriving Repr, BEq, Inhabited

def AdmitSurfaceFamilyV1.toString : AdmitSurfaceFamilyV1 → String
  | .controlFlowIf => "control-flow-if"
  | .controlFlowFor => "control-flow-for"
  | .aggregateOption => "aggregate-option"
  | .aggregateArray => "aggregate-array"
  | .aggregateMapPartial => "aggregate-map-partial"

/-- One relation package circuit-hash pin (no golden file path required). -/
structure AdmitRelationPinV1 where
  relation : String
  packageArtifactName : String
  expectedCircuitHash : String
  deriving Repr, BEq, Inhabited

/-- Full admit fixture: product materialize + live capture pins. -/
structure AdmitSurfaceFixtureV1 where
  fixtureId : String
  family : AdmitSurfaceFamilyV1
  moduleName : String
  sourceText : String
  /-- Expected relation package directory stems in source order. -/
  packageStems : Array String
  /-- Relations that must nargo-compile and match circuit hash. -/
  capturePins : Array AdmitRelationPinV1
  /-- Relations that Plan materializes but nargo compile must fail (honesty). -/
  nargoFailStems : Array String
  deriving Repr, BEq, Inhabited

/-- BranchCounter: if/else control-flow admit surface (bump branch). -/
def branchCounterSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program BranchCounter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    if count >= delta then\n" ++
  "      count := count - delta\n" ++
  "    else\n" ++
  "      count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- LoopSum: bounded-for static-unroll control-flow admit surface. -/
def loopSumSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program LoopSum where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    total := initial\n\n" ++
  "  entry run(n : UInt64) : UInt64 do\n" ++
  "    let limit : UInt64 := n + 4\n" ++
  "    for i in n ..< limit bounded 8 do\n" ++
  "      total := total + 1\n" ++
  "    return total\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- OptionState: Option UInt64 state + match aggregate admit surface. -/
def optionStateSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program OptionState where\n" ++
  "  state slot : Option UInt64\n\n" ++
  "  init() do\n" ++
  "    slot := Option.none()\n\n" ++
  "  entry setSome(v : UInt64) : UInt64 do\n" ++
  "    slot := Option.some(v)\n" ++
  "    return v\n\n" ++
  "  entry clear() : UInt64 do\n" ++
  "    slot := Option.none()\n" ++
  "    return 0\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    match slot with\n" ++
  "    | Option.some(x) => do\n" ++
  "      return x\n" ++
  "    | _ => do\n" ++
  "      return 0\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- ArrayRet: fixed Array UInt64 2 state/return aggregate admit surface. -/
def arrayRetSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ArrayRet where\n" ++
  "  state slots : Array UInt64 2\n\n" ++
  "  init(a : UInt64, b : UInt64) do\n" ++
  "    slots[0] := a\n" ++
  "    slots[1] := b\n\n" ++
  "  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do\n" ++
  "    slots[0] := a\n" ++
  "    slots[1] := b\n" ++
  "    return slots\n\n" ++
  "  view getArr() : Array UInt64 2 do\n" ++
  "    return slots\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- MapMini: dense Map state Plan-admitted; put/get nargo type residual. -/
def mapMiniSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program MapMini where\n" ++
  "  state m : Map UInt64 UInt64\n\n" ++
  "  init() do\n" ++
  "    m := Map.empty()\n\n" ++
  "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
  "    m[k] := v\n" ++
  "    return v\n\n" ++
  "  view get(k : UInt64) : UInt64 do\n" ++
  "    match m[k] with\n" ++
  "    | Option.some(v) => do\n" ++
  "      return v\n" ++
  "    | _ => do\n" ++
  "      return 0\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Frozen G3 admit-surface fixtures (product materialize + capture pins). -/
def admitSurfaceFixturesV1 : Array AdmitSurfaceFixtureV1 :=
  #[
    { fixtureId := "BranchCounter"
      family := .controlFlowIf
      moduleName := "Examples.BranchCounter"
      sourceText := branchCounterSourceTextV1
      packageStems := #["r0-init", "r1-bump", "r2-get"]
      capturePins :=
        #[
          { relation := "r0-init"
            packageArtifactName := "pf_relation_0.json"
            expectedCircuitHash := "17547139497077004670" },
          { relation := "r1-bump"
            packageArtifactName := "pf_relation_1.json"
            expectedCircuitHash := "5326684273681879262" },
          { relation := "r2-get"
            packageArtifactName := "pf_relation_2.json"
            expectedCircuitHash := "15142158172902813876" }
        ]
      nargoFailStems := #[] },
    { fixtureId := "LoopSum"
      family := .controlFlowFor
      moduleName := "Examples.LoopSum"
      sourceText := loopSumSourceTextV1
      packageStems := #["r0-init", "r1-run", "r2-get"]
      capturePins :=
        #[
          { relation := "r0-init"
            packageArtifactName := "pf_relation_0.json"
            expectedCircuitHash := "17547139497077004670" },
          { relation := "r1-run"
            packageArtifactName := "pf_relation_1.json"
            expectedCircuitHash := "1663100142809567421" },
          { relation := "r2-get"
            packageArtifactName := "pf_relation_2.json"
            expectedCircuitHash := "15142158172902813876" }
        ]
      nargoFailStems := #[] },
    { fixtureId := "OptionState"
      family := .aggregateOption
      moduleName := "Examples.OptionState"
      sourceText := optionStateSourceTextV1
      packageStems := #["r0-init", "r1-setSome", "r2-clear", "r3-peek"]
      capturePins :=
        #[
          { relation := "r0-init"
            packageArtifactName := "pf_relation_0.json"
            expectedCircuitHash := "15390717378386485224" },
          { relation := "r1-setSome"
            packageArtifactName := "pf_relation_1.json"
            expectedCircuitHash := "12137904358083423139" },
          { relation := "r2-clear"
            packageArtifactName := "pf_relation_2.json"
            expectedCircuitHash := "12246679460574536583" },
          { relation := "r3-peek"
            packageArtifactName := "pf_relation_3.json"
            expectedCircuitHash := "4152353602006729362" }
        ]
      nargoFailStems := #[] },
    { fixtureId := "ArrayRet"
      family := .aggregateArray
      moduleName := "Examples.ArrayRet"
      sourceText := arrayRetSourceTextV1
      packageStems := #["r0-init", "r1-setArr", "r2-getArr"]
      capturePins :=
        #[
          { relation := "r0-init"
            packageArtifactName := "pf_relation_0.json"
            expectedCircuitHash := "10250360699151576765" },
          { relation := "r1-setArr"
            packageArtifactName := "pf_relation_1.json"
            expectedCircuitHash := "5874709250556069158" },
          { relation := "r2-getArr"
            packageArtifactName := "pf_relation_2.json"
            expectedCircuitHash := "292703840847091457" }
        ]
      nargoFailStems := #[] },
    { fixtureId := "MapMini"
      family := .aggregateMapPartial
      moduleName := "Examples.MapMini"
      sourceText := mapMiniSourceTextV1
      packageStems := #["r0-init", "r1-put", "r2-get"]
      -- Plan admits dense Map; init empties compile; put/get emit nargo-ill-typed
      -- leaf arithmetic (u64/bool mix) — honesty residual, not silent success.
      capturePins :=
        #[
          { relation := "r0-init"
            packageArtifactName := "pf_relation_0.json"
            expectedCircuitHash := "996379632831450032" }
        ]
      nargoFailStems := #["r1-put", "r2-get"] }
  ]

/-- Expected total full-capture pins across G3 success relations (excl. Map fail). -/
def admitSurfaceCapturePinCountV1 : Nat :=
  admitSurfaceFixturesV1.foldl (init := 0) fun acc f => acc + f.capturePins.size

/-- Run nargo compile and report success/failure without inventing a backend.
    Used for MapMini put/get honesty residual (must fail closed under nargo). -/
def nargoCompileExitCodeV1 (nargo : String) (packageDir : FilePath) : IO UInt32 := do
  let process ← IO.Process.output {
    cmd := nargo
    args := #["compile", "--silence-warnings"]
    cwd := some packageDir
  }
  pure process.exitCode

end ProofForgeV2.Targets.Noir.Acir.CaptureV1
