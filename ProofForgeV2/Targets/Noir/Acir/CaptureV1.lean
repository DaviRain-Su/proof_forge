/-
  Noir Plan → ACIR capture (NOIR-IR-2 + NOIR-IR-3 / G3 + NOIR-IR-5 + NOIR-IR-6
  + NOIR-IR-7 / G6 prove honesty PARTIAL+MISSING).

  ## Path decision (IR-2, frozen)

  **nargo-assisted capture** is the sole authority path. A pure-Lean ACIR
  opcode encoder is **not** implemented and is **not** claimed.

  ```
  ProgramV1 → Semantic → NoirPlan → relation IR → product .nr packages
       (EmitIRV1 transitional / debug base emission)
                              │
                              ▼
               locked nargo 1.0.0-beta.26 `nargo compile`
                              │
                              ▼
               path-normalized ProgramArtifact JSON
                 (noir_version, hash, bytecode=base64(gzip ACIR), …)
                              │
                              ▼
               ≡ testdata/golden/noir-acir-v1/ (IR-1 inventory, Counter)
                 + G3 admit-surface circuit-hash pins (IR-3)
                 + IR-5 honesty matrix (no false Y)
                 + IR-6 optional profile dual-write extras
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

  ## IR-5 / G5 honesty matrix

  §3.2 status column (Y / P / F) is pinned here + product FC boundaries:

  * call/schedule slots = **P** (witness-binding relation only; circuit does
    **not** execute external call; proof does **not** attest on-chain call)
  * String state / Option non-UInt64 = **F** (plan-FC)
  * prove/VK = **F** (Finalize `deployable=false`; no product prove; IR-7/G6
    prove lane is host-heavy PARTIAL+MISSING — see below)

  No false Y: every Y row has IR-1/IR-2/IR-3 capture evidence; F/P rows have
  plan-FC or honesty notes (not silent pass).

  ## IR-6 / G4 product dual-write

  Host-dependent ACIR cannot be ordinary zero-tool Finalize. Product path:

  * default `noir-source-u64-relations-v1` — zero-tool; transitional `.nr` base;
    evidence notes ACIR authority is nargo-assisted + optional profile
  * explicit `noir-nargo-1.0.0-beta.26-acir-v1` — Finalize dual-writes
    path-normalized ProgramArtifact JSON as `finalized-extra` under
    `nargo-compile/{stem}/{pf_relation_N}.json`; missing nargo fail-closed
    (`PF-TOOLCHAIN-MISSING`); still `deployable=false`; no prove/VK

  ## IR-7 / G6 prove honesty (PARTIAL + MISSING)

  Tool Lock `unresolved.barretenberg=null`; no bb/barretenberg asset. Host-heavy
  probe `scripts/noir_runtime_test.sh` + `just noir-runtime` fail closed with
  `PF-TOOLCHAIN-MISSING` (never PATH; never invent prove CLI/CRS). nargo is
  compile-only (IR-1..IR-6), **not** prove authority. Matrix prove/VK stays **F**;
  product `deployable=false`. When a real backend pin lands, extend the probe
  with a minimal Counter prove pin (still not ordinary ci).

  Honesty:
  * `deployable=false`; no prove/verify/VK/witness product claim.
  * Default Finalize remains zero-tool (no host ACIR).
  * Capture / ACIR profile Finalize is host-heavy / non-hermetic when nargo runs.
  * Does **not** decode ACIR opcodes (bytecode stays opaque base64 gzip).
  * Does **not** invent a backend when nargo is absent on live-skip paths;
    ACIR profile requires nargo.
  * Does **not** invent Barretenberg/bb prove/CRS when Tool Lock pin is null.

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
  "Plan→ACIR authority is nargo-assisted capture of ProgramArtifact " ++
  "circuit core (noir_version+hash+bytecode) from product Plan .nr packages " ++
  "via locked nargo 1.0.0-beta.26; pure-Lean ACIR opcode encoder is not " ++
  "implemented; .nr remains transitional/debug base emission; " ++
  "IR-6 product dual-write is opt-in profile noir-nargo-1.0.0-beta.26-acir-v1 " ++
  "(path-normalized ProgramArtifact finalized-extra; default Finalize zero-tool); " ++
  "G3 admit-surface CF/aggregate circuit-hash pins share this path; " ++
  "IR-5 honesty matrix pins call/schedule P (witness-binding only), " ++
  "String/Option non-UInt64 F (plan-FC), prove/VK F (no product prove); " ++
  "IR-7/G6 prove honesty PARTIAL+MISSING (Tool Lock barretenberg=null; " ++
  "just noir-runtime → PF-TOOLCHAIN-MISSING; never invent bb/CRS); " ++
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

/-- Rewrite every JSON `"path":"..."` field to the frozen package-relative
    `src/main.nr` pin and ensure a trailing newline. Host absolute paths in
    raw nargo `file_map` are not product identity. -/
def pathNormalizeProgramArtifactTextV1 (raw : String) : String :=
  let needle := "\"path\":\""
  match raw.splitOn needle with
  | [] => if raw.endsWith "\n" then raw else raw ++ "\n"
  | head :: rest =>
      let out :=
        rest.foldl (init := head) fun acc (segment : String) =>
          match segment.splitOn "\"" with
          | _old :: after =>
              acc ++ needle ++ normalizedSourcePathV1 ++ "\"" ++
                String.intercalate "\"" after
          | [] => acc ++ needle
      if out.endsWith "\n" then out else out ++ "\n"

/-- Extract `[package] name = "…"` from product `Nargo.toml` text. -/
def extractNargoPackageNameV1 (toml : String) : Option String :=
  let needle := "name = \""
  match toml.splitOn needle with
  | [_, rest] =>
      match rest.splitOn "\"" with
      | name :: _ => if name.isEmpty then none else some name
      | [] => none
  | _ => none

/-- Extra path layout for IR-6 dual-write: `nargo-compile/{stem}/{artifact}.json`. -/
def acirExtraRelPathV1 (relationStem artifactFileName : String) : String :=
  s!"nargo-compile/{relationStem}/{artifactFileName}"

/-- Run `nargo compile --silence-warnings` in `packageDir` and return the
    path-normalized ProgramArtifact UTF-8 text for `artifactName` under
    `target/` plus its circuit core.

    Host-heavy / non-hermetic. Caller must have already resolved a real nargo. -/
def compilePackageCaptureProgramArtifactV1
    (nargo : String) (packageDir : FilePath) (artifactName : String) :
    IO (String × CircuitCoreV1) := do
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
  let normalized := pathNormalizeProgramArtifactTextV1 raw
  match extractCircuitCoreV1 normalized with
  | some core => pure (normalized, core)
  | none =>
      throw <| IO.userError
        s!"nargo-assisted capture: cannot extract circuit core from {livePath}"

/-- Run `nargo compile --silence-warnings` in `packageDir` and capture the
    ProgramArtifact circuit core for `artifactName` under `target/`.

    Host-heavy / non-hermetic. Caller must have already resolved a real nargo. -/
def compilePackageCaptureCircuitCoreV1
    (nargo : String) (packageDir : FilePath) (artifactName : String) :
    IO CircuitCoreV1 := do
  let (_text, core) ←
    compilePackageCaptureProgramArtifactV1 nargo packageDir artifactName
  pure core

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

/-! ### NOIR-IR-5 / G5 honesty matrix

  Pins docs/targets/07-noir-acir-lowering.md §3.2 status column. Legend:

  * `Y` — true admit: ACIR capture or equivalent IR-1/IR-2/IR-3 pin
  * `P` — PARTIAL: Plan/slot admit without full platform/proof claim
  * `F` — fail closed or not claimed (plan-FC / no product path)

  **No false Y:** every Y row cites capture evidence; F/P rows cite plan-FC
  or honesty notes. call/schedule must never be written as ACIR Y.
-/

/-- Honesty matrix cell status (plan §3.2). -/
inductive HonestyStatusV1 where
  | Y
  | P
  | F
  deriving Repr, BEq, Inhabited

def HonestyStatusV1.toString : HonestyStatusV1 → String
  | .Y => "Y"
  | .P => "P"
  | .F => "F"

/-- One §3.2 matrix row: existing Noir Plan path vs ACIR claim + evidence. -/
structure HonestyMatrixRowV1 where
  family : String
  /-- Existing Noir Plan / `.nr` path status. -/
  noirPathStatus : HonestyStatusV1
  /-- ACIR / nargo-assisted capture claim (must not overclaim vs Plan). -/
  acirStatus : HonestyStatusV1
  /-- Evidence label (test / pin / plan-FC / honesty note). -/
  evidence : String
  deriving Repr, BEq, Inhabited

/-- Frozen §3.2 honesty matrix (IR-5). Order matches plan table. -/
def honestyMatrixRowsV1 : Array HonestyMatrixRowV1 :=
  #[
    { family := "UInt*/Field bn254 arithmetic"
      noirPathStatus := .Y
      acirStatus := .Y
      evidence := "Counter IR-1 inventory + IR-2 Plan→ACIR capture" },
    { family := "Bool / compare / logical"
      noirPathStatus := .Y
      acirStatus := .Y
      evidence := "Counter / BranchCounter compare path; G3 if capture" },
    { family := "Array/Map/Bytes flatten"
      noirPathStatus := .P
      acirStatus := .P
      evidence :=
        "ArrayRet Y capture; MapMini init Y + put/get nargo-fail residual; " ++
        "Bytes remains Plan surface only" },
    { family := "if/match/for"
      noirPathStatus := .Y
      acirStatus := .Y
      evidence :=
        "BranchCounter if; LoopSum for; OptionState match G3 pins" },
    { family := "pureFn"
      noirPathStatus := .Y
      acirStatus := .Y
      evidence := "Counter relation pure path / product regression (no extra G3 fixture)" },
    { family := "call/schedule slots"
      noirPathStatus := .P
      acirStatus := .P
      evidence :=
        "witness-binding status/arg slots only (B-CALL-SEM); circuit does not " ++
        "execute external call; proof does not attest on-chain call; " ++
        "result-bearing call remains FC" },
    { family := "Option UInt64 state"
      noirPathStatus := .Y
      acirStatus := .Y
      evidence := "OptionState G3 full capture pins" },
    { family := "String state / Option non-UInt64"
      noirPathStatus := .F
      acirStatus := .F
      evidence := "plan-FC (String state / Option String / Option Bool / nested Option)" },
    { family := "prove/VK"
      noirPathStatus := .F
      acirStatus := .F
      evidence :=
        "G6 PARTIAL+MISSING (barretenberg null; just noir-runtime " ++
        "PF-TOOLCHAIN-MISSING); Finalize deployable=false; no product " ++
        "prove/verify/VK path" }
  ]

/-- ExtFlow product package stems (call + schedule witness-binding; status P). -/
def callSchedulePackageStemsV1 : Array String :=
  #["r0-init", "r1-bump", "r2-later", "r3-get"]

/-- ExtFlow source: emit + call + schedule (Plan admits slots; ACIR claim stays P). -/
def callScheduleHonestySourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ExtFlowHonesty where\n" ++
  "  state count : UInt64\n\n" ++
  "  event Ping(x : UInt64)\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    emit Ping(count)\n" ++
  "    call Oracle.feed(count)\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  entry later(delta : UInt64) : UInt64 do\n" ++
  "    schedule ledger.daily(count)\n" ++
  "    schedule ledger.weekly(delta)\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Product-path plan-FC: String state. -/
def stringStateFcSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program StringStateFc where\n" ++
  "  state label : String\n\n" ++
  "  init() do\n" ++
  "    label := \"x\"\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Product-path plan-FC: Option String state (non-UInt64 Option payload). -/
def optionStringStateFcSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program OptionStringStateFc where\n" ++
  "  state maybe : Option String\n\n" ++
  "  init() do\n" ++
  "    maybe := Option.none()\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- Product-path plan-FC: Option Bool state (non-UInt64 Option payload). -/
def optionBoolStateFcSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program OptionBoolStateFc where\n" ++
  "  state flag : Option Bool\n\n" ++
  "  init() do\n" ++
  "    flag := Option.none()\n\n" ++
  "  view peek() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end ProofForgeV2.Examples\n"

/-- call/schedule honesty note (docs/tests join; must not claim platform call Y). -/
def honestyCallScheduleNoteV1 : String :=
  "Noir call/schedule is witness-binding only (status/arg public-input slots); " ++
  "the circuit executes no external call and the proof does not attest that any " ++
  "on-chain call happened; ACIR status is P not Y (B-CALL-SEM); " ++
  "result-bearing call stays fail closed pending response-witness contract"

/-- String / Option non-UInt64 honesty note (plan-FC). -/
def honestyOptionStringNoteV1 : String :=
  "String state and Option non-UInt64 (including Option String) stay plan-FC on " ++
  "Noir; ACIR status F; only Option UInt64 state is G3-capture Y"

/-- prove/VK honesty note (no product prove; IR-7/G6 PARTIAL+MISSING). -/
def honestyProveNoteV1 : String :=
  "no product prove/verify/VK path; Finalize deployable=false; evidence notes " ++
  "deny ACIR/witness/proof/verification; prove/VK matrix row remains F; " ++
  "NOIR-IR-7 / G6 prove honesty is PARTIAL+MISSING (Tool Lock " ++
  "barretenberg=null; scripts/noir_runtime_test.sh + just noir-runtime → " ++
  "PF-TOOLCHAIN-MISSING; never invent bb/CRS CLI)"

/-- Exact default-profile Finalize evidence note text (join with FinalizeV1).
    Zero-tool; ACIR product dual-write is opt-in profile only (NOIR-IR-6). -/
def finalizeEvidenceNoteV1 : String :=
  "NOIR-IR-6: default noir-source-u64-relations-v1 finalization is zero-tool; " ++
  "relation source/schema (.nr transitional/debug base) were emitted without " ++
  "invoking nargo; ACIR product dual-write is opt-in profile " ++
  "noir-nargo-1.0.0-beta.26-acir-v1 (nargo-assisted path-normalized " ++
  "ProgramArtifact finalized-extra); no witness execution, proof, or " ++
  "verification (deployable=false); pure-Lean ACIR opcode encoder is not " ++
  "implemented"

/-- Exact ACIR-profile Finalize evidence note prefix (nargo path/version filled
    by FinalizeV1; suite joins on stable substrings). -/
def finalizeAcirEvidenceNotePrefixV1 : String :=
  "NOIR-IR-6: noir-nargo-1.0.0-beta.26-acir-v1 nargo-assisted dual-write of " ++
  "path-normalized ProgramArtifact JSON as finalized-extra under " ++
  "nargo-compile/{relation}/{pf_relation_N}.json; " ++
  ".nr bases remain transitional/debug nargo input; no prove/verify/VK/" ++
  "witness product claim (deployable=false)"

/-- Product ACIR profile id wire string (join with TargetIdentity). -/
def productAcirProfileV1 : String := "noir-nargo-1.0.0-beta.26-acir-v1"

/-- True when a status is a true Y admit (used to guard false-Y). -/
def isHonestyYV1 (s : HonestyStatusV1) : Bool :=
  match s with | .Y => true | _ => false

/-- Families whose ACIR status is Y (must have capture evidence). -/
def honestyAcirYFamiliesV1 : Array String :=
  honestyMatrixRowsV1.filterMap fun row =>
    if isHonestyYV1 row.acirStatus then some row.family else none

/-- Families whose ACIR status is F (must have plan-FC / no-product evidence). -/
def honestyAcirFFamiliesV1 : Array String :=
  honestyMatrixRowsV1.filterMap fun row =>
    match row.acirStatus with
    | .F => some row.family
    | _ => none

/-- Families whose ACIR status is P (partial honesty). -/
def honestyAcirPFamiliesV1 : Array String :=
  honestyMatrixRowsV1.filterMap fun row =>
    match row.acirStatus with
    | .P => some row.family
    | _ => none

end ProofForgeV2.Targets.Noir.Acir.CaptureV1
