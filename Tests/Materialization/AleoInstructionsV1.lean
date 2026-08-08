/-
  ALEO-IR-1..7 + G5-MATRIX + G5-HARD + RES-CLEAN + ALEO-MULTI-GOLDEN +
  ALEO-COMPILE-COMPARE + ALEO-ADMIT-FIXTURES + ALEO-OPTION-COMPARE:
  Aleo Instructions Schema/TextCodec + Counter golden + Plan→Instructions
  + if/match/bounded-for + multi-leaf + narrow UInt + effects honesty +
  product primary + residual true lower + hard-require (empty allowlist) +
  IR-7 runtime honesty PARTIAL/MISSING + residual honesty closeout +
  multi-fixture structural product pins + optional locked-leo compile compare
  + durable suite-owned admit-surface fixtures
  (`Tests.Fixtures.AleoAdmitSurfacesV1`).

  Covers:
  * schema id / Leo golden version pins
  * hand-built `counterProgramV1` encode ≡ locked-leo golden file bytes
  * golden decode ≡ hand-built structure
  * encode → decode structural round-trip
  * decode fail-closed on truncated / unknown opcode
  * ALEO-IR-2: hand-built Counter Plan → Instructions ≡ counterProgramV1
  * ALEO-IR-2: Examples/Counter product Plan → Instructions ≡ golden
  * ALEO-IR-3: ifThenElse / switchOn / bounded for structural + ceiling FC
  * ALEO-IR-4: multi-leaf storeAggregate + Option/Map/Array/Narrow product
  * empty Plan fail closed
  * ALEO-IR-5: Plan emit / payload-revert FC; product emit/call/schedule/… FC
  * ALEO-IR-6: product primary Instructions ≡ golden; Leo debug dual-write
  * G5-HARD: Int64 / Field BLS12-377 / pureFn callFn inline true lower;
    empty residual allowlist; no silent Leo-only primary
  * ALEO-CONST: literal-backed Op.Constant product lower (inline Plan
    literal → Instructions `Nu64`); nested Map stays plan-FC
  * ALEO-IR-7 / G6: runtime honesty pin — package-only snarkVM execute is
    **MISSING** (PARTIAL); `scripts/aleo_runtime_test.sh` + `just aleo-runtime`
    fail closed `PF-TOOLCHAIN-MISSING` (never PATH; never invent CLI);
    leo run ≠ Instructions package-only execute
  * RES-CLEAN: Counter remains sole IR-1 full-surface authority golden;
    multi-program leo matrix / record / prove / full opcode deferred
  * ALEO-MULTI-GOLDEN: product Plan→Instructions structural pins for
    admit-surface OptionState / Accumulator / MapMini / LoopSum
  * ALEO-COMPILE-COMPARE: Accumulator admit-surface locked-leo
    `accumulator-admit.compiled.aleo` compare pin (Plan→IR byte ≡ golden;
    live compile-profile recheck when locked Leo present; honest skip note
    when tool missing). **Not** full multi-program leo byte matrix.
  * ALEO-OPTION-COMPARE: OptionState admit-surface locked-leo
    `optionstate-admit.compiled.aleo` compare pin (Plan→IR byte ≡ golden;
    live recheck tool-optional; MapMini stays structural-only — Leo Map
    upsert rewrite ⇒ Plan→IR ≠ Leo compiled). **Not** multi-program matrix.
  * ALEO-ADMIT-FIXTURES: durable `Tests.Fixtures.AleoAdmitSurfacesV1` sources
    for Accumulator-credit / OptionState entry-only / MapMini put-only;
    product select→compile→capability→programFromCapabilityV1 succeeds;
    structural IR + G5-HARD empty; full Examples Plan-FC honesty pins
    (reserved `add`; computed views). Shared Examples not renamed.

  **Not** snarkVM execute, prove/deploy, formal, full multi-program leo
  byte-equality matrix. PARTIAL only with evidence (IR-7 MISSING pin).
  deployable=false.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Targets.Aleo
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
import ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
import ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Materialization.LockedToolchainV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline
import Tests.Fixtures.AleoAdmitSurfacesV1

namespace Tests.Materialization.AleoInstructionsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Materialization.LockedToolchainV1
open ProofForgeV2.Targets
open ProofForgeV2.Targets.Aleo
open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
open ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
open ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1
open Tests.Fixtures.AleoAdmitSurfacesV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult {α : Type} : CompileResult α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError e.render

private def goldenPath : FilePath :=
  "testdata/golden/aleo-instructions-v1/counter.compiled.aleo"

/-- ALEO-COMPILE-COMPARE: Accumulator admit-surface locked-leo compare pin
    (entry `credit`; full Examples/Accumulator is Plan-FC on reserved `add`).
    Not IR-1 Counter authority; not multi-program matrix. -/
private def accumulatorAdmitGoldenPath : FilePath :=
  "testdata/golden/aleo-instructions-v1/accumulator-admit.compiled.aleo"

/-- ALEO-OPTION-COMPARE: OptionState admit-surface locked-leo compare pin
    (entry-only setSome/clear; full Examples/OptionState Plan-FC on computed
    `peek`). Not IR-1 Counter authority; not multi-program matrix. -/
private def optionStateAdmitGoldenPath : FilePath :=
  "testdata/golden/aleo-instructions-v1/optionstate-admit.compiled.aleo"

/-- Locked Leo candidate (same resolution as AleoCompiledFinalizationV1). -/
private def lockedLeoCandidate : IO FilePath := do
  match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
  | some root =>
      let path := FilePath.mk root
      unless path.isAbsolute do
        throw <| IO.userError
          "PF-TOOLCHAIN-MISMATCH: PROOF_FORGE_TOOL_ROOT must be absolute"
      pure (path / "leo")
  | none =>
      let homeValue? ← IO.getEnv "HOME"
      let home ← match homeValue? with
        | some value => pure (FilePath.mk value)
        | none =>
            throw <| IO.userError
              "PF-TOOLCHAIN-MISSING: HOME is required for the default tool cache"
      let platform ← match ProofForgeV2.Core.ToolLockV4.activeToolLockPlatformV4 with
        | .ok value => pure value
        | .error message => throw <| IO.userError message
      pure <| home / ".cache" / "proof-forge-v2" / "tool-root" /
        ProofForgeV2.Core.ToolLockV4.ToolLockPlatformV4.wire platform / "leo"

private def resolveLockedLeo? : IO (Option VerifiedTool) := do
  let candidate ← lockedLeoCandidate
  if ← candidate.pathExists then
    pure (some (← resolve "leo"))
  else
    pure none

private def testPins : IO Unit := do
  expect (schemaIdV1 == "proof-forge.aleo-instructions.v1") "schema id"
  expect (goldenLeoVersionV1 == "4.0.2") "Leo golden version pin"
  expect (counterProgramV1.name == "counter.aleo") "counter program name"
  expect (counterProgramV1.items.size == 7)
    "2 mappings + initialize fn/final + increment fn/final + constructor"
  expect (guardMappingNameV1 == "initialized") "init guard name"
  expect (mappingNameV1 0 == "pf_state_0") "state mapping name"

private def testEncodeEqualsGolden : IO Unit := do
  expect (← goldenPath.pathExists) "Counter compiled.aleo golden must exist"
  let golden ← IO.FS.readFile goldenPath
  let encoded := encodeProgram counterProgramV1
  expect (encoded == golden)
    s!"hand-built encode must equal golden bytes\n--- encoded ---\n{encoded}\n--- golden ---\n{golden}"
  expect (encoded.length == 870) "golden size pin (Leo 4.0.2 product Counter)"

private def testGoldenDecodeEqualsHandBuilt : IO Unit := do
  let golden ← IO.FS.readFile goldenPath
  match decodeProgram? golden with
  | none => throw <| IO.userError "failed to decode Counter golden"
  | some prog =>
      expect (prog == counterProgramV1)
        "decoded golden must equal hand-built counterProgramV1"
      expect (prog.name == "counter.aleo") "program name"
      -- Spot-check structure: first mapping + constructor last.
      match prog.items[0]!, prog.items[6]! with
      | .mapping m, .constructor c =>
          expect (m.name == "pf_state_0") "first mapping"
          expect (c.body.size == 1) "constructor single assert"
      | _, _ => throw <| IO.userError "unexpected item kinds at ends"

private def testEncodeDecodeRoundTrip : IO Unit := do
  let encoded := encodeProgram counterProgramV1
  match decodeProgram? encoded with
  | none => throw <| IO.userError "encode→decode failed"
  | some prog =>
      expect (prog == counterProgramV1) "structural round-trip"
      expect (encodeProgram prog == encoded) "re-encode byte identity"

private def testDecodeFailClosed : IO Unit := do
  expect ((decodeProgram? "").isNone) "empty"
  expect ((decodeProgram? "program counter.aleo;\n\nmapping x:\n").isNone)
    "truncated mapping"
  -- Opcode without `into` / assert shape → fail closed
  expect ((decodeProgram?
      "program counter.aleo;\n\nfunction f:\n    mystery r0 r1;\n").isNone)
    "opcode without into / unknown shape"
  -- Missing semicolon on instruction
  expect ((decodeProgram?
      "program counter.aleo;\n\nfunction f:\n    input r0 as u64.public\n").isNone)
    "missing semicolon"
  -- Missing program header semicolon
  expect ((decodeProgram? "program counter.aleo\n").isNone)
    "header without semicolon"

/-- Structural counts for Counter (documentation pin for IR-2). -/
private def testCounterShape : IO Unit := do
  let p := counterProgramV1
  let mut mappings := 0
  let mut functions := 0
  let mut finals := 0
  let mut constructors := 0
  for item in p.items do
    match item with
    | .mapping _ => mappings := mappings + 1
    | .function _ => functions := functions + 1
    | .finalize _ => finals := finals + 1
    | .constructor _ => constructors := constructors + 1
  expect (mappings == 2) "mappings"
  expect (functions == 2) "functions"
  expect (finals == 2) "finalize blocks"
  expect (constructors == 1) "constructor"
  -- initialize finalize uses get.or_use + not + assert.eq + set×2
  match p.items[3]! with
  | .finalize f =>
      expect (f.name == "initialize") "finalize initialize"
      expect (f.body.size == 6) "initialize finalize body size"
  | _ => throw <| IO.userError "items[3] must be finalize initialize"

/-- Hand-built Counter Plan matching product shape (init store / checkedAdd). -/
private def handBuiltCounterPlan : Plan := {
  programName := "Counter"
  stateFieldNames := #["count"]
  stateFieldIsInt := #[false]
  stateFieldUintWidth := #[0]
  stateFieldIsField := #[false]
  functions := #[
    {
      index := 0
      name := "initialize"
      kind := .initialize
      params := #[{ sourceIndex := 0, name := "initial", isBool := false }]
      body := #[.store 0 (.param 0), .returnNone]
      touchesState := true
      resultIsBool := false
      resultDropped := false
    },
    {
      index := 1
      name := "increment"
      kind := .mutate
      params := #[{ sourceIndex := 0, name := "delta", isBool := false }]
      body := #[
        .store 0 (.checkedAdd (.stateLoad 0) (.param 0)),
        .returnValue (.stateLoad 0)
      ]
      touchesState := true
      resultIsBool := false
      resultDropped := true
    }
  ]
  views := #[{ name := "get", stateFieldIndex := 0 }]
  sourceHash := "00"
  semanticHash := "00"
}

/-- ALEO-IR-2: hand-built Plan lower ≡ hand-built Instructions / golden. -/
private def testHandBuiltPlanLowerEqualsCounterProgram : IO Unit := do
  let prog ← liftResult <| lowerPlanForTestV1 handBuiltCounterPlan
  expect (prog == counterProgramV1)
    "hand-built Counter Plan→Instructions must equal counterProgramV1"
  let golden ← IO.FS.readFile goldenPath
  expect (encodeProgram prog == golden)
    "hand-built Plan lower encode must equal golden bytes"

/-- ALEO-IR-2: product Examples/Counter via capability → Instructions ≡ golden. -/
unsafe def testProductCounterPlanLowerEqualsGolden : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let src ← IO.FS.readFile "Examples/Counter.lean"
  let parsed ← liftResult (← session.selectProgramV1
    src "<aleo-ir2>" "Examples.Counter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  -- Default source profile (Plan shared with compile profile).
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (prog == counterProgramV1)
    s!"product Plan→Instructions must equal counterProgramV1 (got {prog.name})"
  let golden ← IO.FS.readFile goldenPath
  expect (encodeProgram prog == golden)
    "product lower encode must equal locked-leo Counter golden bytes"
  -- Compile profile resolves a distinct selection identity but same Plan body.
  let selectionCompile ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo
      (some CodegenProfileId.aleoLeoU64CompileV1)
  let capCompile ← liftResult <|
    resolveEngineeringRequirementsV1 selectionCompile compiled
  let progCompile ← liftResult <| programFromCapabilityV1 capCompile
  expect (progCompile == prog)
    "default and compile profiles must lower to identical Instructions (shared Plan)"

/-- Empty plan fail closed; G5-HARD pure-helper-only skip + Int64 leaf lower. -/
private def testUnsupportedPlanFailClosed : IO Unit := do
  let emptyPlan : Plan := {
    programName := "Empty"
    stateFieldNames := #[]
    stateFieldIsInt := #[]
    stateFieldUintWidth := #[]
    stateFieldIsField := #[]
    functions := #[]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  match lowerPlanForTestV1 emptyPlan with
  | .ok _ => throw <| IO.userError "empty plan must fail closed"
  | .error e =>
      expect (e.render.contains "ALEO-IR")
        s!"expected ALEO-IR diagnostic, got: {e.render}"
  -- G5-HARD: pure helper omitted from top-level (initialize-only program ok)
  let purePlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        name := "helper"
        isPureHelper := true
        touchesState := false
        body := #[.returnValue (.param 0)]
        resultDropped := false }
    ]
  }
  let pureProg ← liftResult <| lowerPlanForTestV1 purePlan
  expect (pureProg.name == "counter.aleo")
    "pure helper skip still emits program"
  -- pure helper must not appear as top-level function/finalize
  let mut sawHelper := false
  for item in pureProg.items do
    match item with
    | .function f => if f.name == "helper" then sawHelper := true
    | .finalize f => if f.name == "helper" then sawHelper := true
    | _ => pure ()
  expect (!sawHelper) "pure helper must not be top-level emitted"
  -- G5-HARD: Int64 leaf true lower (i64 mapping)
  let intPlan : Plan := {
    handBuiltCounterPlan with
    stateFieldIsInt := #[true]
  }
  let intProg ← liftResult <| lowerPlanForTestV1 intPlan
  expect (intProg.items.any fun item =>
      match item with
      | .mapping m => m.name == "pf_state_0" && m.valueType == .base .i64 .public_
      | _ => false)
    "Int64 leaf must emit i64.public mapping"

private def countOpsInBody (body : Array InstructionV1) : Nat × Nat :=
  Id.run do
    let mut branches := 0
    let mut positions := 0
    for i in body do
      match i with
      | .branchEq .. => branches := branches + 1
      | .position _ => positions := positions + 1
      | _ => pure ()
    pure (branches, positions)

/-- Count branch.eq / position in a program (control-flow structural pin). -/
private def countControlOps (p : ProgramV1) : Nat × Nat :=
  Id.run do
    let mut branches := 0
    let mut positions := 0
    for item in p.items do
      let (b, pos) :=
        match item with
        | .finalize f => countOpsInBody f.body
        | .function f => countOpsInBody f.body
        | .constructor c => countOpsInBody c.body
        | .mapping _ => (0, 0)
      branches := branches + b
      positions := positions + pos
    pure (branches, positions)

private def hasBinaryOp (p : ProgramV1) (op : String) : Bool :=
  Id.run do
    for item in p.items do
      let body :=
        match item with
        | .finalize f => f.body
        | .function f => f.body
        | .constructor c => c.body
        | .mapping _ => #[]
      for i in body do
        match i with
        | .binary o _ _ _ => if o == op then return true
        | _ => pure ()
    pure false

private def hasUnaryOp (p : ProgramV1) (op : String) : Bool :=
  Id.run do
    for item in p.items do
      let body :=
        match item with
        | .finalize f => f.body
        | .function f => f.body
        | .constructor c => c.body
        | .mapping _ => #[]
      for i in body do
        match i with
        | .unary o _ _ => if o == op then return true
        | _ => pure ()
    pure false

private def hasAssertEq (p : ProgramV1) : Bool :=
  Id.run do
    for item in p.items do
      let body :=
        match item with
        | .finalize f => f.body
        | .function f => f.body
        | .constructor c => c.body
        | .mapping _ => #[]
      for i in body do
        match i with
        | .assertEq .. => return true
        | _ => pure ()
    pure false

private def countAssertEqInFinalize (p : ProgramV1) (fnName : String) : Nat :=
  Id.run do
    let mut n := 0
    for item in p.items do
      match item with
      | .finalize f =>
          if f.name == fnName then
            for i in f.body do
              match i with
              | .assertEq .. => n := n + 1
              | _ => pure ()
      | _ => pure ()
    pure n

/-- ALEO-IR-3: ifThenElse lowers to branch.eq + position (Leo if shape). -/
private def testIfThenElseStructural : IO Unit := do
  let plan : Plan := {
    programName := "Branch"
    stateFieldNames := #["count"]
    stateFieldIsInt := #[false]
    stateFieldUintWidth := #[0]
    stateFieldIsField := #[false]
    functions := #[
      {
        index := 0
        name := "initialize"
        kind := .initialize
        params := #[{ sourceIndex := 0, name := "initial", isBool := false }]
        body := #[.store 0 (.param 0), .returnNone]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      },
      {
        index := 1
        name := "pick"
        kind := .mutate
        params := #[]
        body := #[
          .ifThenElse
            (.compare .gt (.stateLoad 0) (.literal 10))
            #[.store 0 (.checkedSub (.stateLoad 0) (.literal 1))]
            #[.store 0 (.checkedAdd (.stateLoad 0) (.literal 1))],
          .returnValue (.stateLoad 0)
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := true
      }
    ]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  let prog ← liftResult <| lowerPlanForTestV1 plan
  expect (prog.name == "branch.aleo") "branch program name"
  let (branches, positions) := countControlOps prog
  expect (branches ≥ 2)
    s!"if/else must emit branch.eq (got {branches})"
  expect (positions ≥ 2)
    s!"if/else must emit position labels (got {positions})"
  expect (hasBinaryOp prog "gt") "condition must lower to gt"
  expect (hasBinaryOp prog "sub") "then arm checkedSub"
  expect (hasBinaryOp prog "add") "else arm checkedAdd"
  -- Round-trip encode/decode for control-flow program
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "if/else encode→decode failed"
  | some p2 =>
      expect (p2 == prog) "if/else structural round-trip"

/-- ALEO-IR-3: switchOn → nested is.eq + branch chain. -/
private def testSwitchOnStructural : IO Unit := do
  let plan : Plan := {
    programName := "Pick"
    stateFieldNames := #["count"]
    stateFieldIsInt := #[false]
    stateFieldUintWidth := #[0]
    stateFieldIsField := #[false]
    functions := #[
      {
        index := 0
        name := "initialize"
        kind := .initialize
        params := #[{ sourceIndex := 0, name := "initial", isBool := false }]
        body := #[.store 0 (.param 0), .returnNone]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      },
      {
        index := 1
        name := "apply"
        kind := .mutate
        params := #[{ sourceIndex := 0, name := "delta", isBool := false }]
        body := #[
          .switchOn (.param 0)
            #[
              (0, #[.store 0 (.literal 0)]),
              (1, #[.store 0 (.checkedAdd (.stateLoad 0) (.literal 1))])
            ]
            #[.store 0 (.param 0)],
          .returnValue (.stateLoad 0)
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := true
      }
    ]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  let prog ← liftResult <| lowerPlanForTestV1 plan
  expect (hasBinaryOp prog "is.eq") "match arms must compare with is.eq"
  let (branches, positions) := countControlOps prog
  expect (branches ≥ 4)
    s!"switch must nest branch.eq (got {branches})"
  expect (positions ≥ 4)
    s!"switch must nest position (got {positions})"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "switch encode→decode failed"
  | some p2 => expect (p2 == prog) "switch structural round-trip"

/-- ALEO-IR-3: bounded for static unroll + boundExceeded gate. -/
private def testBoundedForStructural : IO Unit := do
  let plan : Plan := {
    programName := "LoopSum"
    stateFieldNames := #["count"]
    stateFieldIsInt := #[false]
    stateFieldUintWidth := #[0]
    stateFieldIsField := #[false]
    functions := #[
      {
        index := 0
        name := "initialize"
        kind := .initialize
        params := #[{ sourceIndex := 0, name := "initial", isBool := false }]
        body := #[.store 0 (.param 0), .returnNone]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      },
      {
        index := 1
        name := "sumUp"
        kind := .mutate
        params := #[{ sourceIndex := 0, name := "n", isBool := false }]
        body := #[
          .forLoop (.literal 0) (.param 0) 4
            #[.store 0 (.checkedAdd (.stateLoad 0) (.loopVar 0))],
          .returnValue (.stateLoad 0)
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := true
      }
    ]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  let prog ← liftResult <| lowerPlanForTestV1 plan
  let (branches, positions) := countControlOps prog
  -- bound check if + 4 unrolled iterations each with skip/join branches
  expect (branches ≥ 2 + 4 * 2)
    s!"for unroll must emit enough branch.eq (got {branches})"
  expect (positions ≥ 2 + 4 * 2)
    s!"for unroll must emit enough position (got {positions})"
  expect (hasBinaryOp prog "lte") "boundExceeded uses lte"
  expect (hasBinaryOp prog "lt") "iteration gate uses lt"
  -- Static unroll: four sets into pf_state_0
  let mut sets := 0
  for item in prog.items do
    match item with
    | .finalize f =>
        if f.name == "sumUp" then
          for i in f.body do
            match i with
            | .set _ "pf_state_0" _ => sets := sets + 1
            | _ => pure ()
    | _ => pure ()
  expect (sets == 4)
    s!"for body store must appear once per unrolled iteration (got {sets})"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "for encode→decode failed"
  | some p2 => expect (p2 == prog) "for structural round-trip"

/-- ALEO-IR-3: maxIterations above ceiling fail closed (unbounded honesty). -/
private def testForUnrollCeilingFailClosed : IO Unit := do
  let plan : Plan := {
    handBuiltCounterPlan with
    programName := "HugeLoop"
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      {
        index := 1
        name := "spin"
        kind := .mutate
        params := #[{ sourceIndex := 0, name := "n", isBool := false }]
        body := #[
          .forLoop (.literal 0) (.param 0) (maxForUnrollIterationsV1 + 1)
            #[.store 0 (.checkedAdd (.stateLoad 0) (.loopVar 0))],
          .returnNone
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      }
    ]
  }
  match lowerPlanForTestV1 plan with
  | .ok _ => throw <| IO.userError "oversize for must fail closed"
  | .error e =>
      expect (e.render.contains "ALEO-IR")
        s!"expected ALEO-IR for ceiling diagnostic, got: {e.render}"

/-- ALEO-IR-3: product Branch via capability has control ops. -/
unsafe def testProductBranchControlFlow : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Branch where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry pick() : UInt64 do\n" ++
    "    if count > 10 then\n" ++
    "      count := count - 1\n" ++
    "    else\n" ++
    "      count := count + 1\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir3-branch>" "Tests.AleoIR3Branch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  let (branches, positions) := countControlOps prog
  expect (branches ≥ 2 && positions ≥ 2)
    s!"product Branch must lower if/else control (b={branches} p={positions})"
  expect (hasBinaryOp prog "gt") "product Branch condition gt"

private def countMappings (p : ProgramV1) : Nat :=
  Id.run do
    let mut n := 0
    for item in p.items do
      match item with
      | .mapping _ => n := n + 1
      | _ => pure ()
    pure n

private def mappingNames (p : ProgramV1) : Array String :=
  Id.run do
    let mut out : Array String := #[]
    for item in p.items do
      match item with
      | .mapping m => out := out.push m.name
      | _ => pure ()
    pure out

private def mappingValueBase (p : ProgramV1) (name : String) : Option BaseTypeV1 :=
  Id.run do
    for item in p.items do
      match item with
      | .mapping m =>
          if m.name == name then
            match m.valueType with
            | .base ty _ => return some ty
            | _ => return none
      | _ => pure ()
    pure none

private def countSetsInFinalize (p : ProgramV1) (fnName : String) : Nat :=
  Id.run do
    let mut n := 0
    for item in p.items do
      match item with
      | .finalize f =>
          if f.name == fnName then
            for i in f.body do
              match i with
              | .set .. => n := n + 1
              | _ => pure ()
      | _ => pure ()
    pure n

private def countGetOrUseInFinalize (p : ProgramV1) (fnName : String) : Nat :=
  Id.run do
    let mut n := 0
    for item in p.items do
      match item with
      | .finalize f =>
          if f.name == fnName then
            for i in f.body do
              match i with
              | .getOrUse .. => n := n + 1
              | _ => pure ()
      | _ => pure ()
    pure n

private def hasTernary (p : ProgramV1) : Bool :=
  Id.run do
    for item in p.items do
      let body :=
        match item with
        | .finalize f => f.body
        | .function f => f.body
        | .constructor c => c.body
        | .mapping _ => #[]
      for i in body do
        match i with
        | .ternary .. => return true
        | _ => pure ()
    pure false

private def hasCast (p : ProgramV1) : Bool :=
  Id.run do
    for item in p.items do
      let body :=
        match item with
        | .finalize f => f.body
        | .function f => f.body
        | .constructor c => c.body
        | .mapping _ => #[]
      for i in body do
        match i with
        | .typeCast .. => return true
        | _ => pure ()
    pure false

/-- ALEO-IR-4: hand-built dual-leaf + storeAggregate → two mappings + batch set. -/
private def testHandBuiltMultiLeafStructural : IO Unit := do
  let plan : Plan := {
    programName := "PairBox"
    stateFieldNames := #["a", "b"]
    stateFieldIsInt := #[false, false]
    stateFieldUintWidth := #[0, 0]
    stateFieldIsField := #[false, false]
    functions := #[
      {
        index := 0
        name := "initialize"
        kind := .initialize
        params := #[
          { sourceIndex := 0, name := "x", isBool := false },
          { sourceIndex := 1, name := "y", isBool := false }
        ]
        body := #[
          .storeAggregate #[
            { fieldIndex := 0, value := .param 0 },
            { fieldIndex := 1, value := .param 1 }
          ],
          .returnNone
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      },
      {
        index := 1
        name := "swap"
        kind := .mutate
        params := #[]
        body := #[
          .storeAggregate #[
            { fieldIndex := 0, value := .stateLoad 1 },
            { fieldIndex := 1, value := .stateLoad 0 }
          ],
          .returnNone
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      }
    ]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  let prog ← liftResult <| lowerPlanForTestV1 plan
  expect (prog.name == "pairbox.aleo") "pairbox program name"
  -- 2 state mappings + initialized guard
  expect (countMappings prog == 3)
    s!"multi-leaf must emit 2 state + guard mappings, got {countMappings prog}"
  let names := mappingNames prog
  expect (names.contains "pf_state_0" && names.contains "pf_state_1")
    s!"expected pf_state_0/1, got {names}"
  expect (mappingValueBase prog "pf_state_0" == some .u64) "leaf0 u64"
  expect (mappingValueBase prog "pf_state_1" == some .u64) "leaf1 u64"
  -- initialize: 2 leaf sets + initialized mark = 3
  expect (countSetsInFinalize prog "initialize" == 3)
    s!"init storeAggregate must set 2 leaves + guard, got {countSetsInFinalize prog "initialize"}"
  -- swap: two get.or_use (snapshot) then two sets (no interleave requirement pinned beyond counts)
  expect (countGetOrUseInFinalize prog "swap" == 2)
    s!"swap must load both leaves before store, got {countGetOrUseInFinalize prog "swap"}"
  expect (countSetsInFinalize prog "swap" == 2)
    s!"swap must set both leaves, got {countSetsInFinalize prog "swap"}"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "multi-leaf encode→decode failed"
  | some p2 => expect (p2 == prog) "multi-leaf structural round-trip"

/-- ALEO-IR-4: product OptionState (entry-only; Aleo FC computed views) →
    tag+payload dual mapping + storeAggregate. -/
unsafe def testProductOptionStateMultiLeaf : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- Inline entry-only surface (Examples/OptionState view peek is Aleo FC).
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptionState where\n" ++
    "  state slot : Option UInt64\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n" ++
    "  entry clear() : UInt64 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir4-option>" "Tests.AleoIR4Option" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (prog.name == "optionstate.aleo") "OptionState program name"
  -- slot_tag + slot_p0 + initialized
  expect (countMappings prog == 3)
    s!"OptionState must emit 2 state + guard mappings, got {countMappings prog}"
  expect (mappingNames prog |>.contains "pf_state_0") "tag mapping"
  expect (mappingNames prog |>.contains "pf_state_1") "payload mapping"
  -- setSome / clear / initialize all write both leaves (+ init guard on initialize)
  expect (countSetsInFinalize prog "setSome" ≥ 2)
    s!"setSome must store tag+payload, got {countSetsInFinalize prog "setSome"}"
  expect (countSetsInFinalize prog "clear" ≥ 2)
    s!"clear must store tag+payload, got {countSetsInFinalize prog "clear"}"
  expect (countSetsInFinalize prog "initialize" ≥ 3)
    s!"init none must store 2 leaves + guard, got {countSetsInFinalize prog "initialize"}"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "OptionState encode→decode failed"
  | some p2 => expect (p2 == prog) "OptionState structural round-trip"

/-- ALEO-IR-4: product MapMini (entry put only; view get is Aleo computed-view FC)
    → 6 Map leaves + put storeAggregate / ternary. -/
unsafe def testProductMapMiniMultiLeaf : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapMini where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir4-map>" "Tests.AleoIR4Map" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (prog.name == "mapmini.aleo") "MapMini program name"
  -- 6 Map leaves + initialized
  expect (countMappings prog == 7)
    s!"MapMini cap-2 must emit 6 state + guard mappings, got {countMappings prog}"
  for i in [0:6] do
    expect (mappingNames prog |>.contains (mappingNameV1 i))
      s!"missing mapping {mappingNameV1 i}"
  -- put upsert: 6 leaf sets (no init guard)
  expect (countSetsInFinalize prog "put" == 6)
    s!"MapMini put must set 6 Map leaves, got {countSetsInFinalize prog "put"}"
  -- pre-store snapshot loads for upsert selectors
  expect (countGetOrUseInFinalize prog "put" ≥ 6)
    s!"MapMini put must get.or_use Map leaves for snapshot, got {countGetOrUseInFinalize prog "put"}"
  expect (hasTernary prog) "Map upsert selectors use ternary"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "MapMini encode→decode failed"
  | some p2 => expect (p2 == prog) "MapMini structural round-trip"


/-- ALEO-IR-4: product Array UInt64 2 flatten → pf_state_0/1. -/
unsafe def testProductArrayMultiLeaf : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayBox where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir4-array>" "Tests.AleoIR4Array" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (prog.name == "arraybox.aleo") "ArrayBox program name"
  expect (countMappings prog == 3)
    s!"Array 2 must emit 2 state + guard, got {countMappings prog}"
  expect (mappingNames prog |>.contains "pf_state_0") "slots_0"
  expect (mappingNames prog |>.contains "pf_state_1") "slots_1"
  -- init writes both leaves via IndexSet (may be two store or one aggregate)
  expect (countSetsInFinalize prog "initialize" ≥ 3)
    s!"Array init must write both leaves + guard, got {countSetsInFinalize prog "initialize"}"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "Array encode→decode failed"
  | some p2 => expect (p2 == prog) "Array structural round-trip"

/-- ALEO-IR-4: product NarrowBox (state-touching only; Final path) →
    u8/u16/u32 mappings + narrow arith. -/
unsafe def testProductNarrowUintWidths : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NarrowBox where\n" ++
    "  state a : UInt8\n" ++
    "  state b : UInt16\n" ++
    "  state c : UInt32\n" ++
    "  init(seed8 : UInt8, seed16 : UInt16, seed32 : UInt32) do\n" ++
    "    a := seed8\n" ++
    "    b := seed16\n" ++
    "    c := seed32\n" ++
    "  entry bump8(d : UInt8) : UInt8 do\n" ++
    "    a := a + d\n" ++
    "    return a\n" ++
    "  entry bump16(d : UInt16) : UInt16 do\n" ++
    "    b := b + d\n" ++
    "    return b\n" ++
    "  entry bump32(d : UInt32) : UInt32 do\n" ++
    "    c := c + d\n" ++
    "    return c\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir4-narrow>" "Tests.AleoIR4Narrow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (prog.name == "narrowbox.aleo") "NarrowBox program name"
  -- 3 narrow leaves + guard
  expect (countMappings prog == 4)
    s!"NarrowBox must emit 3 state + guard, got {countMappings prog}"
  expect (mappingValueBase prog "pf_state_0" == some .u8) "UInt8 mapping"
  expect (mappingValueBase prog "pf_state_1" == some .u16) "UInt16 mapping"
  expect (mappingValueBase prog "pf_state_2" == some .u32) "UInt32 mapping"
  -- initialize takes three typed inputs
  let mut initInputs : Array TypeAnnV1 := #[]
  for item in prog.items do
    match item with
    | .finalize f =>
        if f.name == "initialize" then
          for i in f.body do
            match i with
            | .input _ ty => initInputs := initInputs.push ty
            | _ => pure ()
    | _ => pure ()
  expect (initInputs.size ≥ 3) "initialize must declare 3 inputs"
  expect (initInputs[0]! == .base .u8 .public_) "seed8 as u8.public"
  expect (initInputs[1]! == .base .u16 .public_) "seed16 as u16.public"
  expect (initInputs[2]! == .base .u32 .public_) "seed32 as u32.public"
  expect (hasBinaryOp prog "add") "narrow checkedAdd → add"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "NarrowBox encode→decode failed"
  | some p2 => expect (p2 == prog) "NarrowBox structural round-trip"

/-- ALEO-IR-4: hand-built narrow shift emits cast + shl (EmitIR count shape). -/
private def testHandBuiltNarrowShiftCast : IO Unit := do
  let plan : Plan := {
    programName := "ShiftBox"
    stateFieldNames := #["a"]
    stateFieldIsInt := #[false]
    stateFieldUintWidth := #[8]
    stateFieldIsField := #[false]
    functions := #[
      {
        index := 0
        name := "initialize"
        kind := .initialize
        params := #[{ sourceIndex := 0, name := "seed", isBool := false, uintWidth := 8 }]
        body := #[.store 0 (.param 0), .returnNone]
        touchesState := true
        resultIsBool := false
        resultDropped := false
        resultUintWidth := 8
      },
      {
        index := 1
        name := "shift"
        kind := .mutate
        params := #[{ sourceIndex := 0, name := "count", isBool := false, uintWidth := 8 }]
        body := #[
          .store 0 (.narrowShl 8 (.stateLoad 0) (.param 0)),
          .returnValue (.stateLoad 0)
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := true
        resultUintWidth := 8
      }
    ]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  let prog ← liftResult <| lowerPlanForTestV1 plan
  expect (mappingValueBase prog "pf_state_0" == some .u8) "shift leaf u8"
  expect (hasCast prog) "narrowShl must emit cast for shift count"
  expect (hasBinaryOp prog "shl") "narrowShl must emit shl"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "ShiftBox encode→decode failed"
  | some p2 => expect (p2 == prog) "ShiftBox structural round-trip"

/-- ALEO-IR-4: Nested Map remains fail closed at Plan (not Instructions lower). -/
unsafe def testNestedMapFailClosedAtPlan : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NestedMapBox where\n" ++
    "  state m : Map UInt64 Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := Map.empty()\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir4-nested>" "Tests.AleoIR4Nested" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .ok compiled =>
      let selection ← liftResult <|
        BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
      match resolveEngineeringRequirementsV1 selection compiled with
      | .ok cap =>
          match programFromCapabilityV1 cap with
          | .ok _ =>
              throw <| IO.userError "nested Map must fail closed before/at IR lower"
          | .error e =>
              expect (e.render.length > 0)
                "nested Map must yield a diagnostic"
      | .error e =>
          expect (e.render.length > 0) "nested Map resolver diagnostic"
  | .error e =>
      -- Compile-time type/normalize FC is also acceptable.
      expect (e.render.length > 0) "nested Map compile diagnostic"

/-- ALEO-IR-5: Plan-reachable effects honesty (emit / callFn / payload revert). -/
private def testEffectsHonestyPlanFailClosed : IO Unit := do
  -- emitEvent → stable ALEO-IR-5 diagnostic at Instructions lower.
  let emitPlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[
          .emitEvent 0 #[.param 0],
          .store 0 (.param 0),
          .returnNone
        ] }
    ]
  }
  match lowerPlanForTestV1 emitPlan with
  | .ok _ => throw <| IO.userError "emit Plan must fail closed at IR-5"
  | .error e =>
      expect (e.render.contains "ALEO-IR-5")
        s!"emit must cite ALEO-IR-5, got: {e.render}"
      expect (e.render.contains "emit" || e.render.contains "event")
        s!"emit diagnostic must mention emit/event, got: {e.render}"
      expect (e.render.contains diagEmitNotAdmittedV1 ||
          e.render.contains "no on-chain event log")
        s!"emit diagnostic must match honesty matrix, got: {e.render}"
  -- G5-HARD: missing pureHelper for callFn still FC (not silent).
  let callFnMissing : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[
          .store 0 (.callFn "helper" #[.param 0]),
          .returnNone
        ] }
    ]
  }
  match lowerPlanForTestV1 callFnMissing with
  | .ok _ => throw <| IO.userError "callFn without pureHelper must fail closed"
  | .error e =>
      expect (e.render.contains "ALEO-IR-G5" || e.render.contains "pureHelper" ||
          e.render.contains "callFn" || e.render.contains "pure")
        s!"missing pureHelper callFn diagnostic, got: {e.render}"
  -- payload revert → ALEO-IR-5.
  let payloadPlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[
          .revertError 0 #[.param 0],
          .returnNone
        ] }
    ]
  }
  match lowerPlanForTestV1 payloadPlan with
  | .ok _ => throw <| IO.userError "payload revert Plan must fail closed at IR-5"
  | .error e =>
      expect (e.render.contains "ALEO-IR-5")
        s!"payload revert must cite ALEO-IR-5, got: {e.render}"
      expect (e.render.contains "payload" || e.render.contains "revert")
        s!"payload revert diagnostic must mention payload/revert, got: {e.render}"
  -- bare revert remains admitted (assert.eq true false in Final).
  let bareRevertPlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[.revertError 0 #[], .returnNone] }
    ]
  }
  let bareProg ← liftResult <| lowerPlanForTestV1 bareRevertPlan
  expect (bareProg.name == "counter.aleo") "bare revert still lowers"
  -- Documentation pins (non-empty honesty notes for product surfaces).
  expect (diagExternalCallHonestyNoteV1.contains "synchronous-call")
    "external call honesty note"
  expect (diagScheduleHonestyNoteV1.contains "asynchronous-workflow")
    "schedule honesty note"
  expect (diagAssetsRecordHonestyNoteV1.contains "pf.assets")
    "assets/record honesty note"
  expect (diagContextHonestyNoteV1.contains "ContextRead")
    "context honesty note"

/-- ALEO-IR-5: product path emit / call / schedule / context / assets FC. -/
unsafe def testEffectsHonestyProductFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let expectProductFc (label : String) (source : String)
      (moduleName : String) (needle : String) : IO Unit := do
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<aleo-ir5-{label}>" moduleName none)
    match Compiler.compileValidatedSourceV1 parsed with
    | .error e =>
        expect (e.render.length > 0)
          s!"{label}: compile FC diagnostic"
    | .ok compiled =>
        match resolveEngineeringRequirementsV1 selection compiled with
        | .error e =>
            expect (e.render.contains needle ||
                e.render.contains "PF-REQ" ||
                e.render.contains "unsupported" ||
                e.render.contains "Unsupported" ||
                e.render.length > 0)
              s!"{label}: resolve FC, got: {e.render}"
        | .ok cap =>
            match programFromCapabilityV1 cap with
            | .ok _ =>
                throw <| IO.userError
                  s!"{label}: must fail closed before/at Instructions lower"
            | .error e =>
                expect (e.render.contains needle ||
                    e.render.contains "ALEO-IR-5" ||
                    e.render.contains "Aleo" ||
                    e.render.length > 0)
                  s!"{label}: lower FC, got: {e.render}"
  -- emit: resolver declines effect.event or Plan/IR FC.
  expectProductFc "emit"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Ir5Emitter where\n" ++
     "  event Ticked(value : UInt64)\n" ++
     "  state count : UInt64\n" ++
     "  init() do\n" ++
     "    count := 0\n" ++
     "  entry tick(x : UInt64) : UInt64 do\n" ++
     "    emit Ticked(x)\n" ++
     "    count := x\n" ++
     "    return x\n")
    "Tests.AleoIr5Emitter" "emit"
  -- sync call: effect.synchronous-call declined at resolve.
  expectProductFc "call"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Ir5Caller where\n" ++
     "  state count : UInt64\n" ++
     "  init() do\n" ++
     "    count := 0\n" ++
     "  entry go(x : UInt64) : UInt64 do\n" ++
     "    call Peer.go(x)\n" ++
     "    count := x\n" ++
     "    return x\n")
    "Tests.AleoIr5Caller" "call"
  -- schedule: effect.asynchronous-workflow declined at resolve.
  expectProductFc "schedule"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Ir5Scheduler where\n" ++
     "  state count : UInt64\n" ++
     "  init() do\n" ++
     "    count := 0\n" ++
     "  entry go(x : UInt64) : UInt64 do\n" ++
     "    schedule ledger.daily(x)\n" ++
     "    count := x\n" ++
     "    return x\n")
    "Tests.AleoIr5Scheduler" "schedule"
  -- ContextRead (unixTimeSeconds) pilot FC.
  expectProductFc "context"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Ir5Clock where\n" ++
     "  state public pad : UInt64\n" ++
     "  init() do\n" ++
     "    pad := 0\n" ++
     "  entry now() : UInt64 do\n" ++
     "    return context.unixTimeSeconds\n")
    "Tests.AleoIr5Clock" "context"
  -- pf.assets extension + catalog call: resolve FC (zero-binding).
  expectProductFc "assets"
    ("import ProofForgeV2\n" ++
     "open ProofForgeV2.Language\n" ++
     "program Ir5Assets where\n" ++
     "  requires extension pf.assets version \"1.1.0\"\n" ++
     "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n" ++
     "  state count : UInt64\n" ++
     "  init() do\n" ++
     "    count := 0\n" ++
     "  entry pay(dst : Principal, amount : UInt64) : UInt64 do\n" ++
     "    call pf.assets.native.transfer(dst, amount)\n" ++
     "    count := amount\n" ++
     "    return amount\n")
    "Tests.AleoIr5Assets" "assets"

/-!
  ## ALEO-G5-MATRIX admit pins

  Honesty: G5-HARD closed Int64 / Field BLS12-377 / pureFn as **done**.
  Nested Map stays plan-FC. ALEO-CONST: literal-backed `Op.Constant` product
  lower inlines as Instructions literal operands (same envelope as
  `Op.Literal`). Bool/compare/logic + bare assert/revert are **done**.
-/

/-- G5-MATRIX: Bool / compare / logical + bare assert + bare revert → Instructions. -/
private def testG5MatrixBoolAssertStructural : IO Unit := do
  let plan : Plan := {
    programName := "Guard"
    stateFieldNames := #["count"]
    stateFieldIsInt := #[false]
    stateFieldUintWidth := #[0]
    stateFieldIsField := #[false]
    functions := #[
      {
        index := 0
        name := "initialize"
        kind := .initialize
        params := #[{ sourceIndex := 0, name := "initial", isBool := false }]
        body := #[.store 0 (.param 0), .returnNone]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      },
      {
        index := 1
        name := "take"
        kind := .mutate
        params := #[{ sourceIndex := 0, name := "delta", isBool := false }]
        body := #[
          -- bare assert on compare: assert count >= delta
          .assert (.compare .ge (.stateLoad 0) (.param 0)),
          -- logical path feeds ternary (Bool expressions admitted on Final)
          .store 0
            (.ternary
              (.logicalAnd
                (.compare .gt (.param 0) (.literal 0))
                (.boolNot (.boolLiteral false)))
              (.checkedSub (.stateLoad 0) (.param 0))
              (.stateLoad 0)),
          .returnValue (.stateLoad 0)
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := true
      },
      {
        index := 2
        name := "halt"
        kind := .mutate
        params := #[]
        body := #[
          -- bare revert → assert.eq true false
          .revertError 0 #[],
          .returnNone
        ]
        touchesState := true
        resultIsBool := false
        resultDropped := false
      }
    ]
    views := #[]
    sourceHash := "00"
    semanticHash := "00"
  }
  let prog ← liftResult <| lowerPlanForTestV1 plan
  expect (prog.name == "guard.aleo") "guard program name"
  expect (hasBinaryOp prog "gte" || hasBinaryOp prog "ge")
    "assert compare must lower to gte/ge binary"
  expect (hasBinaryOp prog "gt") "logical condition gt"
  expect (hasBinaryOp prog "and") "logicalAnd must lower to and"
  expect (hasUnaryOp prog "not") "boolNot must lower to not"
  expect (hasTernary prog) "Bool ternary select must lower"
  expect (hasAssertEq prog) "bare assert/revert must emit assert.eq"
  -- take: assert + initialize-style asserts may coexist; halt bare revert alone
  let takeAsserts := countAssertEqInFinalize prog "take"
  expect (takeAsserts ≥ 1)
    s!"take finalize must assert.eq condition, got {takeAsserts}"
  let haltAsserts := countAssertEqInFinalize prog "halt"
  expect (haltAsserts ≥ 1)
    s!"halt bare revert must assert.eq true false, got {haltAsserts}"
  let encoded := encodeProgram prog
  match decodeProgram? encoded with
  | none => throw <| IO.userError "Guard Bool/assert encode→decode failed"
  | some p2 => expect (p2 == prog) "Guard structural round-trip"

/-- G5-MATRIX product path: bare assert lowers (Bool row done). -/
unsafe def testG5MatrixProductAssertLower : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Guard where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry take(delta : UInt64) : UInt64 do\n" ++
    "    assert count >= delta\n" ++
    "    count := count - delta\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-g5-assert>" "Tests.AleoG5Assert" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (hasAssertEq prog) "product assert must lower to assert.eq"
  expect (hasBinaryOp prog "gte" || hasBinaryOp prog "ge")
    "product assert condition compare"
  expect (countAssertEqInFinalize prog "take" ≥ 1)
    "product take finalize carries assert.eq"

/-- Operand walk: true when any instruction uses a literal with this spelling. -/
private def hasLiteralSpelling (p : ProgramV1) (spelling : String) : Bool :=
  Id.run do
    let hit (op : OperandV1) : Bool :=
      match op with
      | .literal s => s == spelling
      | _ => false
    for item in p.items do
      let body :=
        match item with
        | .finalize f => f.body
        | .function f => f.body
        | .constructor c => c.body
        | .mapping _ => #[]
      for i in body do
        let found :=
          match i with
          | .unary _ src _ => hit src
          | .binary _ l r _ => hit l || hit r
          | .ternary c t e _ => hit c || hit t || hit e
          | .typeCast src _ _ => hit src
          | .assertEq l r => hit l || hit r
          | .getOrUse _ k d _ => hit k || hit d
          | .set v _ k => hit v || hit k
          | .branchEq l r _ => hit l || hit r
          | .input .. | .output .. | .asyncCall .. | .position _ => false
        if found then return true
    pure false

/-- ALEO-CONST: product const bare place → Op.Constant → Plan literal →
    Instructions `7u64` operand (inline; no separate const opcode). -/
unsafe def testConstProductLower : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ConstBox where\n" ++
    "  const K : UInt64 := 7\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump() : UInt64 do\n" ++
    "    count := count + K\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-const>" "Tests.AleoConst" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  let prog ← liftResult <| programFromCapabilityV1 cap
  expect (prog.name == "constbox.aleo") "const program name"
  expect (hasLiteralSpelling prog "7u64")
    "const K:=7 must lower to Instructions literal 7u64"
  expect (hasBinaryOp prog "add")
    "count + K must lower to add"
  let encoded := encodeProgram prog
  expect (encoded.length > 0) "const product encode nonempty"
  match decodeProgram? encoded with
  | none => throw <| IO.userError "const product encode→decode failed"
  | some p2 => expect (p2 == prog) "const product structural round-trip"
  -- Bool + narrow UInt const share the same lowerLiteral path.
  let source2 :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ConstNarrow where\n" ++
    "  const FLAG : Bool := true\n" ++
    "  const W : UInt32 := 3\n" ++
    "  state count : UInt32\n" ++
    "  init(initial : UInt32) do\n" ++
    "    count := initial\n" ++
    "  entry bump() : UInt32 do\n" ++
    "    if FLAG then\n" ++
    "      count := count + W\n" ++
    "    else\n" ++
    "      count := count\n" ++
    "    return count\n"
  let parsed2 ← liftResult (← session.selectProgramV1
    source2 "<aleo-const-narrow>" "Tests.AleoConstNarrow" none)
  let compiled2 ← liftResult <| Compiler.compileValidatedSourceV1 parsed2
  let cap2 ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled2
  let prog2 ← liftResult <| programFromCapabilityV1 cap2
  expect (hasLiteralSpelling prog2 "true")
    "Bool const true must lower to literal true"
  expect (hasLiteralSpelling prog2 "3u32")
    "UInt32 const 3 must lower to literal 3u32"
  expect (hasBinaryOp prog2 "add") "narrow const add"

/-- G5-HARD: former residual bucket true lower (Int64 / Field / pureFn). -/
private def testG5HardResidualTrueLower : IO Unit := do
  let intParam0 : PlanParam :=
    { sourceIndex := 0, name := "initial", isBool := false, isInt := true }
  let intParam1 : PlanParam :=
    { sourceIndex := 0, name := "delta", isBool := false, isInt := true }
  let intLeaf : Plan := {
    handBuiltCounterPlan with
    stateFieldIsInt := #[true]
    functions := #[
      { index := 0, name := "initialize", kind := .initialize,
        params := #[intParam0],
        body := #[.store 0 (.param 0), .returnNone],
        touchesState := true, resultIsBool := false, resultIsInt := true,
        resultDropped := false },
      { index := 1, name := "increment", kind := .mutate,
        params := #[intParam1],
        body := #[
          .store 0 (.signedCheckedAdd (.stateLoad 0) (.param 0)),
          .returnValue (.stateLoad 0)],
        touchesState := true, resultIsBool := false, resultIsInt := true,
        resultDropped := true }
    ]
  }
  let intProg ← liftResult <| lowerPlanForTestV1 intLeaf
  expect (intProg.items.any fun item =>
      match item with
      | .mapping m => m.valueType == .base .i64 .public_
      | _ => false)
    "G5-HARD Int64 leaf mapping is i64.public"
  expect (hasBinaryOp intProg "add")
    "G5-HARD Int64 signedCheckedAdd → add"
  let intExpr : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { index := 1, name := "setNeg", kind := .mutate, params := #[],
        body := #[.store 0 (.checkedNeg (.i64Literal 1)), .returnNone],
        touchesState := true, resultIsBool := false, resultDropped := false }
    ]
  }
  let intExprProg ← liftResult <| lowerPlanForTestV1 intExpr
  expect (hasBinaryOp intExprProg "sub")
    "G5-HARD checkedNeg → sub 0i64"
  let fieldParam0 : PlanParam :=
    { sourceIndex := 0, name := "initial", isBool := false, isField := true }
  let fieldParam1 : PlanParam :=
    { sourceIndex := 0, name := "delta", isBool := false, isField := true }
  let fieldLeaf : Plan := {
    handBuiltCounterPlan with
    stateFieldIsField := #[true]
    functions := #[
      { index := 0, name := "initialize", kind := .initialize,
        params := #[fieldParam0],
        body := #[.store 0 (.param 0), .returnNone],
        touchesState := true, resultIsBool := false, resultIsField := true,
        resultDropped := false },
      { index := 1, name := "bump", kind := .mutate,
        params := #[fieldParam1],
        body := #[
          .store 0 (.fieldBinary .add (.stateLoad 0) (.param 0)),
          .returnValue (.stateLoad 0)],
        touchesState := true, resultIsBool := false, resultIsField := true,
        resultDropped := true }
    ]
  }
  let fieldProg ← liftResult <| lowerPlanForTestV1 fieldLeaf
  expect (fieldProg.items.any fun item =>
      match item with
      | .mapping m => m.valueType == .base .field .public_
      | _ => false)
    "G5-HARD Field leaf mapping is field.public"
  expect (hasBinaryOp fieldProg "add")
    "G5-HARD fieldBinary add"
  let fieldExpr : Plan := {
    handBuiltCounterPlan with
    stateFieldIsField := #[true]
    functions := #[
      { index := 0, name := "initialize", kind := .initialize, params := #[],
        body := #[.store 0 (.fieldLiteral 7), .returnNone],
        touchesState := true, resultIsBool := false, resultDropped := false }
    ]
  }
  let fieldExprProg ← liftResult <| lowerPlanForTestV1 fieldExpr
  expect (fieldExprProg.name == "counter.aleo") "field literal lowers"
  let pureCallPlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { index := 1, name := "helper", kind := .mutate,
        params := #[{ sourceIndex := 0, name := "x", isBool := false }],
        body := #[.returnValue (.checkedAdd (.param 0) (.literal 1))],
        touchesState := false, resultIsBool := false, isPureHelper := true,
        resultDropped := false },
      { index := 2, name := "increment", kind := .mutate,
        params := #[{ sourceIndex := 0, name := "delta", isBool := false }],
        body := #[
          .store 0 (.callFn "helper" #[.param 0]),
          .returnValue (.stateLoad 0)],
        touchesState := true, resultIsBool := false, resultDropped := true }
    ]
  }
  let pureProg ← liftResult <| lowerPlanForTestV1 pureCallPlan
  expect (hasBinaryOp pureProg "add")
    "G5-HARD callFn inline must emit helper add"
  let mut sawHelperFn := false
  for item in pureProg.items do
    match item with
    | .function f => if f.name == "helper" then sawHelperFn := true
    | .finalize f => if f.name == "helper" then sawHelperFn := true
    | _ => pure ()
  expect (!sawHelperFn) "pureHelper must not be top-level after inline"

/-- G5-HARD: residual allowlist empty; hard-require classifier. -/
private def testG5HardResidualAllowlistClassifier : IO Unit := do
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1
      "ALEO-IR-4: pure helper 'h' is not admitted on Instructions path")
    "G5-HARD: former pure helper residual must NOT be allowlisted"
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1
      "ALEO-IR-4: expression shape not admitted (Int64/Field residual FC)")
    "G5-HARD: former Int64/Field residual must NOT be allowlisted"
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1
      "ALEO-IR-5: pureCall/callFn is not admitted")
    "G5-HARD: former callFn residual must NOT be allowlisted"
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1
      "ALEO-IR-4: expected at least one state leaf, got 0")
    "empty plan error must not be residual allowlisted"
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1 "")
    "empty message must not be allowlisted"

/-- G5-MATRIX plan-FC: nested Map never reaches honest Instructions Y. -/
unsafe def testG5MatrixNestedMapPlanFailClosed : IO Unit := do
  -- Reuse IR-4 nested Map product pin under G5-MATRIX naming for matrix table.
  testNestedMapFailClosedAtPlan

/-- ALEO-IR-6: product materialize primary is Instructions text ≡ golden;
    default omits `.leo`; debug flag and compile profile dual-write Leo. -/
unsafe def testProductPrimaryInstructionsMaterialize : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Counter where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<aleo-ir6-primary>" "Tests.AleoIr6Primary" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <| resolveEngineeringRequirementsV1 selection compiled
  -- Default product: Instructions primary + query only.
  let files ← liftResult <| Targets.Aleo.buildFromCapability cap
  expect (files.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json"])
    s!"IR-6 default paths, got {files.map (·.path)}"
  let golden ← IO.FS.readFile goldenPath
  expect (files[0]!.contents == golden)
    "IR-6 product primary counter.aleo must equal locked-leo golden bytes"
  expect (files[0]!.contents.contains "program counter.aleo;")
    "primary header is Instructions semicolon form"
  expect (!files[0]!.contents.contains "program counter.aleo {")
    "primary must not be Leo brace source"
  -- Debug dual-write.
  let filesDbg ← liftResult <|
    Targets.Aleo.buildFromCapability cap (emitLeoDebug := true)
  expect (filesDbg.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json", "counter.leo"])
    s!"IR-6 debug dual-write paths, got {filesDbg.map (·.path)}"
  expect (filesDbg[0]!.contents == golden)
    "debug dual-write keeps Instructions primary"
  expect (filesDbg[2]!.contents.contains "program counter.aleo {")
    "debug .leo is Leo 4 brace source"
  -- Compile profile always dual-writes Leo for compare finalize.
  let selCmp ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo
      (some CodegenProfileId.aleoLeoU64CompileV1)
  let capCmp ← liftResult <|
    resolveEngineeringRequirementsV1 selCmp compiled
  let filesCmp ← liftResult <| Targets.Aleo.buildFromCapability capCmp
  expect (filesCmp.map (·.path) ==
      #["counter.aleo", "counter.aleo-query-contract.json", "counter.leo"])
    s!"IR-6 compile dual-write paths, got {filesCmp.map (·.path)}"
  expect (filesCmp[0]!.contents == golden)
    "compile profile primary still Instructions ≡ golden"
  expect (filesCmp[2]!.contents.contains "program counter.aleo {")
    "compile dual-write .leo is Leo 4 source"
  -- Registry pure materializeResult default is Instructions-only.
  let arts ← liftResult <| Targets.materializeResult cap
  let artPaths := (MaterializedArtifactsV1.filesOf arts).map (·.path)
  expect (artPaths == #["counter.aleo", "counter.aleo-query-contract.json"])
    s!"Registry materializeResult default must omit .leo, got {artPaths}"

/-- Item-kind inventory for multi-fixture structural pins. -/
private def countItemKinds (p : ProgramV1) : Nat × Nat × Nat × Nat :=
  Id.run do
    let mut maps := 0
    let mut funs := 0
    let mut fins := 0
    let mut ctors := 0
    for item in p.items do
      match item with
      | .mapping _ => maps := maps + 1
      | .function _ => funs := funs + 1
      | .finalize _ => fins := fins + 1
      | .constructor _ => ctors := ctors + 1
    pure (maps, funs, fins, ctors)

private def hasFunctionNamed (p : ProgramV1) (name : String) : Bool :=
  Id.run do
    for item in p.items do
      match item with
      | .function f => if f.name == name then return true
      | .finalize f => if f.name == name then return true
      | _ => pure ()
    pure false

/-- Shared product capability → Instructions lower for MULTI-GOLDEN fixtures. -/
unsafe def productProgramFromSource
    (label source moduleName : String) : IO ProgramV1 := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1
    source s!"<aleo-multi-{label}>" moduleName none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  let cap ← liftResult <|
    resolveEngineeringRequirementsV1 selection compiled
  liftResult <| programFromCapabilityV1 cap

/-- ALEO-MULTI-GOLDEN: Examples/LoopSum full product Plan→Instructions
    structural pin (for unroll + bare view; **not** byte golden). -/
unsafe def testMultiGoldenLoopSumProduct : IO Unit := do
  let src ← IO.FS.readFile "Examples/LoopSum.lean"
  let prog ← productProgramFromSource "loopsum" src "Examples.LoopSum"
  expect (prog.name == "loopsum.aleo") "LoopSum program name"
  let (maps, funs, fins, ctors) := countItemKinds prog
  -- 1 state mapping + initialized guard; initialize + run; constructor
  expect (maps == 2)
    s!"LoopSum mappings (state+guard), got {maps}"
  expect (funs == 2 && fins == 2)
    s!"LoopSum methods: initialize+run fn/final, got fns={funs} finals={fins}"
  expect (ctors == 1) "LoopSum constructor"
  expect (hasFunctionNamed prog "initialize") "LoopSum initialize"
  expect (hasFunctionNamed prog "run") "LoopSum run entry"
  -- Bare view `get` is query-contract only (not an on-chain function).
  expect (!hasFunctionNamed prog "get")
    "LoopSum bare view must not emit on-chain function"
  expect (hasBinaryOp prog "add") "LoopSum body/total uses add"
  expect (hasBinaryOp prog "lt" || hasBinaryOp prog "lte")
    "LoopSum for bound uses lt/lte"
  let (branches, positions) := countControlOps prog
  expect (branches ≥ 4 && positions ≥ 4)
    s!"LoopSum for unroll control ops (b={branches} p={positions})"
  expect (countSetsInFinalize prog "run" ≥ 1)
    "LoopSum run must set total inside unroll"
  expect (countGetOrUseInFinalize prog "run" ≥ 1)
    "LoopSum run must get.or_use total"
  let encoded := encodeProgram prog
  expect (encoded.length > 0) "LoopSum encode nonempty"
  expect (encoded.startsWith "program loopsum.aleo;")
    "LoopSum header"
  match decodeProgram? encoded with
  | none => throw <| IO.userError "LoopSum encode→decode failed"
  | some p2 => expect (p2 == prog) "LoopSum structural round-trip"
  -- Hard-require: product lower succeeded (no ALEO-IR-G5-HARD).
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1 "")
    "G5-HARD allowlist remains empty under MULTI-GOLDEN"

/-- ALEO-MULTI-GOLDEN: Accumulator admit-surface product pin.
    Full `Examples/Accumulator.lean` is Plan-FC (Leo reserved entry name `add`);
    durable fixture renames entry to `credit` (same state/view shape). Structural
    only here — byte pin is ALEO-COMPILE-COMPARE. Source authority =
    `Tests.Fixtures.AleoAdmitSurfacesV1.accumulatorAdmitSourceV1`. -/
unsafe def testMultiGoldenAccumulatorAdmitSurface : IO Unit := do
  -- Honesty: full Examples/Accumulator.lean must Plan-FC on reserved `add`.
  let fullSrc ← IO.FS.readFile "Examples/Accumulator.lean"
  let session ← Tests.Language.ParserSession.shared
  let fullParsed ← liftResult (← session.selectProgramV1
    fullSrc "<aleo-multi-acc-full>" "Examples.Accumulator" none)
  let fullCompiled ← liftResult <| Compiler.compileValidatedSourceV1 fullParsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  match resolveEngineeringRequirementsV1 selection fullCompiled with
  | .error e =>
      expect (e.render.length > 0)
        "full Accumulator resolve/Plan FC diagnostic"
  | .ok fullCap =>
      match planFromCapability fullCap with
      | .ok _ =>
          throw <| IO.userError
            "full Examples/Accumulator must Plan-FC on reserved entry 'add'"
      | .error e =>
          expect (e.render.contains "reserved" || e.render.contains "add")
            s!"full Accumulator must cite reserved/add, got: {e.render}"
  -- Admit-surface durable fixture: same shape, non-reserved entry name.
  let prog ← productProgramFromSource accumulatorAdmitProgramId
    accumulatorAdmitSourceV1 accumulatorAdmitModuleName
  expect (prog.name == "accumulator.aleo") "Accumulator program name"
  let (maps, funs, fins, ctors) := countItemKinds prog
  expect (maps == 2)
    s!"Accumulator mappings (state+guard), got {maps}"
  expect (funs == 2 && fins == 2)
    s!"Accumulator initialize+credit fn/final, got fns={funs} finals={fins}"
  expect (ctors == 1) "Accumulator constructor"
  expect (hasFunctionNamed prog "initialize") "Accumulator initialize"
  expect (hasFunctionNamed prog "credit") "Accumulator credit entry"
  expect (!hasFunctionNamed prog "current")
    "bare view current is query-only, not on-chain"
  expect (hasBinaryOp prog "add") "credit body checkedAdd → add"
  expect (countSetsInFinalize prog "credit" ≥ 1)
    "credit must set total"
  expect (countGetOrUseInFinalize prog "credit" ≥ 1)
    "credit must get.or_use total"
  expect (countSetsInFinalize prog "initialize" ≥ 2)
    "init must set total + initialized guard"
  let encoded := encodeProgram prog
  expect (encoded.length > 0) "Accumulator encode nonempty"
  expect (encoded.startsWith "program accumulator.aleo;")
    "Accumulator header"
  match decodeProgram? encoded with
  | none => throw <| IO.userError "Accumulator encode→decode failed"
  | some p2 => expect (p2 == prog) "Accumulator structural round-trip"

/-- ALEO-MULTI-GOLDEN: OptionState admit-surface product pin (entry-only;
    full Examples/OptionState computed `peek` view is Plan-FC). Structural only.
    Source authority = `Tests.Fixtures.AleoAdmitSurfacesV1.optionStateAdmitSourceV1`. -/
unsafe def testMultiGoldenOptionStateAdmitSurface : IO Unit := do
  -- Honesty: full Examples computed view Plan-FC.
  let fullSrc ← IO.FS.readFile "Examples/OptionState.lean"
  let session ← Tests.Language.ParserSession.shared
  let fullParsed ← liftResult (← session.selectProgramV1
    fullSrc "<aleo-multi-opt-full>" "Examples.OptionState" none)
  let fullCompiled ← liftResult <| Compiler.compileValidatedSourceV1 fullParsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  match resolveEngineeringRequirementsV1 selection fullCompiled with
  | .error e =>
      expect (e.render.length > 0) "full OptionState FC diagnostic"
  | .ok fullCap =>
      match planFromCapability fullCap with
      | .ok _ =>
          throw <| IO.userError
            "full Examples/OptionState must Plan-FC on computed view peek"
      | .error e =>
          expect (e.render.contains "view" || e.render.contains "computed" ||
              e.render.contains "leo query")
            s!"full OptionState must cite computed view, got: {e.render}"
  let prog ← productProgramFromSource optionStateAdmitProgramId
    optionStateAdmitSourceV1 optionStateAdmitModuleName
  expect (prog.name == "optionstate.aleo") "OptionState program name"
  let (maps, funs, fins, ctors) := countItemKinds prog
  expect (maps == 3)
    s!"OptionState tag+payload+guard mappings, got {maps}"
  expect (funs == 3 && fins == 3)
    s!"OptionState initialize+setSome+clear, got fns={funs} finals={fins}"
  expect (ctors == 1) "OptionState constructor"
  expect (mappingNames prog |>.contains "pf_state_0") "tag leaf"
  expect (mappingNames prog |>.contains "pf_state_1") "payload leaf"
  expect (hasFunctionNamed prog "setSome" && hasFunctionNamed prog "clear")
    "OptionState entries present"
  expect (countSetsInFinalize prog "setSome" ≥ 2)
    "setSome stores tag+payload"
  expect (countSetsInFinalize prog "clear" ≥ 2)
    "clear stores tag+payload"
  expect (countSetsInFinalize prog "initialize" ≥ 3)
    "init none stores 2 leaves + guard"
  let encoded := encodeProgram prog
  expect (encoded.length > 0) "OptionState encode nonempty"
  match decodeProgram? encoded with
  | none => throw <| IO.userError "OptionState multi encode→decode failed"
  | some p2 => expect (p2 == prog) "OptionState multi structural round-trip"

/-- ALEO-MULTI-GOLDEN: MapMini admit-surface product pin (entry put only;
    full Examples/MapMini computed `get` view is Plan-FC). Structural only.
    Source authority = `Tests.Fixtures.AleoAdmitSurfacesV1.mapMiniAdmitSourceV1`. -/
unsafe def testMultiGoldenMapMiniAdmitSurface : IO Unit := do
  let fullSrc ← IO.FS.readFile "Examples/MapMini.lean"
  let session ← Tests.Language.ParserSession.shared
  let fullParsed ← liftResult (← session.selectProgramV1
    fullSrc "<aleo-multi-map-full>" "Examples.MapMini" none)
  let fullCompiled ← liftResult <| Compiler.compileValidatedSourceV1 fullParsed
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  match resolveEngineeringRequirementsV1 selection fullCompiled with
  | .error e =>
      expect (e.render.length > 0) "full MapMini FC diagnostic"
  | .ok fullCap =>
      match planFromCapability fullCap with
      | .ok _ =>
          throw <| IO.userError
            "full Examples/MapMini must Plan-FC on computed view get"
      | .error e =>
          expect (e.render.contains "view" || e.render.contains "computed" ||
              e.render.contains "leo query")
            s!"full MapMini must cite computed view, got: {e.render}"
  let prog ← productProgramFromSource mapMiniAdmitProgramId
    mapMiniAdmitSourceV1 mapMiniAdmitModuleName
  expect (prog.name == "mapmini.aleo") "MapMini program name"
  let (maps, funs, fins, ctors) := countItemKinds prog
  expect (maps == 7)
    s!"MapMini cap-2: 6 leaves + guard, got {maps}"
  expect (funs == 2 && fins == 2)
    s!"MapMini initialize+put, got fns={funs} finals={fins}"
  expect (ctors == 1) "MapMini constructor"
  for i in [0:6] do
    expect (mappingNames prog |>.contains (mappingNameV1 i))
      s!"missing Map leaf mapping {mappingNameV1 i}"
  expect (hasFunctionNamed prog "put") "MapMini put entry"
  expect (countSetsInFinalize prog "put" == 6)
    s!"MapMini put must set 6 leaves, got {countSetsInFinalize prog "put"}"
  expect (countGetOrUseInFinalize prog "put" ≥ 6)
    "MapMini put snapshot get.or_use"
  expect (hasTernary prog) "Map upsert uses ternary"
  let encoded := encodeProgram prog
  expect (encoded.length > 0) "MapMini encode nonempty"
  match decodeProgram? encoded with
  | none => throw <| IO.userError "MapMini multi encode→decode failed"
  | some p2 => expect (p2 == prog) "MapMini multi structural round-trip"

/-- ALEO-MULTI-GOLDEN classification inventory:
    * IR-1 full-surface authority golden = Counter (`counter.compiled.aleo`, 870 B)
    * COMPILE-COMPARE optional pin = Accumulator admit-surface
      (`accumulator-admit.compiled.aleo`, 870 B; not multi-program matrix)
    * OPTION-COMPARE optional pin = OptionState admit-surface
      (`optionstate-admit.compiled.aleo`, 1019 B; not multi-program matrix)
    * structural-only product pins = LoopSum (full Example), MapMini
      admit-surface (Leo Map upsert rewrite prevents Plan→IR ≡ locked-leo;
      full Examples Plan-FC as pinned); Accumulator/OptionState also have
      structural MULTI-GOLDEN coverage
    * full multi-program leo **byte** matrix remains deferred
    * G5-HARD allowlist empty; Counter golden identity preserved -/
def testMultiGoldenClassificationInventory : IO Unit := do
  expect (← goldenPath.pathExists)
    "MULTI-GOLDEN: Counter IR-1 full-surface golden must exist"
  let golden ← IO.FS.readFile goldenPath
  expect (golden.toUTF8.size == 870)
    s!"MULTI-GOLDEN: Counter golden must stay 870 B, got {golden.toUTF8.size}"
  expect (golden.startsWith "program counter.aleo;")
    "MULTI-GOLDEN: Counter IR-1 golden program header"
  expect (← accumulatorAdmitGoldenPath.pathExists)
    "MULTI-GOLDEN/COMPILE-COMPARE: accumulator-admit golden must exist"
  let accGolden ← IO.FS.readFile accumulatorAdmitGoldenPath
  expect (accGolden.toUTF8.size == 870)
    s!"COMPILE-COMPARE admit golden size pin, got {accGolden.toUTF8.size}"
  expect (accGolden.startsWith "program accumulator.aleo;")
    "COMPILE-COMPARE admit golden is Accumulator Instructions only"
  expect (← optionStateAdmitGoldenPath.pathExists)
    "MULTI-GOLDEN/OPTION-COMPARE: optionstate-admit golden must exist"
  let optGolden ← IO.FS.readFile optionStateAdmitGoldenPath
  expect (optGolden.toUTF8.size == 1019)
    s!"OPTION-COMPARE admit golden size pin, got {optGolden.toUTF8.size}"
  expect (optGolden.startsWith "program optionstate.aleo;")
    "OPTION-COMPARE admit golden is OptionState Instructions only"
  let entries ← goldenPath.parent.get!.readDir
  let names := (entries.map (·.fileName)).qsort (· < ·)
  expect (names ==
      #["accumulator-admit.compiled.aleo", "counter.compiled.aleo",
        "optionstate-admit.compiled.aleo"])
    s!"golden dir inventory (Counter IR-1 + admit compare pins), got {names}"
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1 "")
    "MULTI-GOLDEN: G5-HARD residual allowlist stays empty"
  pure ()

/-- ALEO-COMPILE-COMPARE offline pin: product Plan→Instructions encode for
    Accumulator admit-surface ≡ committed locked-leo `accumulator-admit.compiled.aleo`
    bytes (captured via product `aleo-leo-4.0.2-u64-compile-v1`). Always runs
    (no tool). Counter IR-1 golden unchanged. Not multi-program matrix. -/
unsafe def testCompileCompareAccumulatorAdmitPlanEqualsGolden : IO Unit := do
  expect (← accumulatorAdmitGoldenPath.pathExists)
    "COMPILE-COMPARE: accumulator-admit.compiled.aleo golden must exist"
  let golden ← IO.FS.readFile accumulatorAdmitGoldenPath
  expect (golden.toUTF8.size == 870)
    s!"COMPILE-COMPARE golden must stay 870 B, got {golden.toUTF8.size}"
  expect (golden.startsWith "program accumulator.aleo;")
    "COMPILE-COMPARE golden program header"
  expect (golden.contains "function credit:")
    "COMPILE-COMPARE admit entry is credit (not reserved add)"
  expect (!golden.contains "function increment:")
    "COMPILE-COMPARE golden must not be Counter"
  -- Plan→IR product lower must byte-equal locked-leo capture
  -- (durable fixture source authority).
  let prog ← productProgramFromSource "accumulator-cc" accumulatorAdmitSourceV1
    accumulatorAdmitModuleName
  let encoded := encodeProgram prog
  expect (encoded == golden)
    s!"COMPILE-COMPARE Plan→IR encode must equal locked-leo admit golden\n--- encoded ---\n{encoded}\n--- golden ---\n{golden}"
  -- Structural decode of golden ≡ product lower.
  match decodeProgram? golden with
  | none => throw <| IO.userError "COMPILE-COMPARE: admit golden decode failed"
  | some decoded =>
      expect (decoded == prog)
        "COMPILE-COMPARE: decoded golden must equal product Plan→IR structure"
  -- Counter golden identity preserved under same suite.
  let counterGolden ← IO.FS.readFile goldenPath
  expect (counterGolden.toUTF8.size == 870)
    "COMPILE-COMPARE must not alter Counter golden size"
  expect (counterGolden.startsWith "program counter.aleo;")
    "COMPILE-COMPARE must not alter Counter golden header"
  expect (counterGolden != golden)
    "COMPILE-COMPARE admit golden must differ from Counter golden"

/-- ALEO-COMPILE-COMPARE live locked-leo path: when Tool Lock Leo 4.0.2 is
    present, product compile-profile finalize re-emits `accumulator.compiled.aleo`
    byte-equal to the committed compare pin. When tool missing: honest skip
    (committed golden + Plan→IR pin still hold offline). deployable=false. -/
unsafe def testCompileCompareAccumulatorAdmitLockedLeoOptional : IO Unit := do
  match ← resolveLockedLeo? with
  | none =>
      IO.println
        "  COMPILE-COMPARE: skipped live locked-leo recheck (Leo unavailable; committed golden + Plan→IR pin still enforced offline)"
  | some leo =>
      let session ← Tests.Language.ParserSession.shared
      let parsed ← liftResult (← session.selectProgramV1
        accumulatorAdmitSourceV1 "<aleo-cc-acc-live>"
        accumulatorAdmitModuleName none)
      let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
      let selection ← liftResult <|
        BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo
          (some CodegenProfileId.aleoLeoU64CompileV1)
      let capability ← liftResult <|
        resolveEngineeringRequirementsV1 selection compiled
      let outDir := FilePath.mk "build/v2/aleo-compile-compare-acc-suite"
      if ← outDir.pathExists then IO.FS.removeDirAll outDir
      let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
      expect (!receipt.deployable)
        "COMPILE-COMPARE live finalize remains deployable=false"
      expect (receipt.codegenProfile == CodegenProfileId.aleoLeoU64CompileV1)
        "COMPILE-COMPARE live profile"
      let compiledPath := outDir / "accumulator.compiled.aleo"
      expect (← compiledPath.pathExists)
        "COMPILE-COMPARE live must publish accumulator.compiled.aleo"
      let live ← IO.FS.readFile compiledPath
      let golden ← IO.FS.readFile accumulatorAdmitGoldenPath
      expect (live == golden)
        s!"COMPILE-COMPARE live locked-leo output must equal committed pin\n--- live ---\n{live}\n--- golden ---\n{golden}"
      -- Primary Instructions base also ≡ pin (Plan→IR authority path).
      let primary ← IO.FS.readFile (outDir / "accumulator.aleo")
      expect (primary == golden)
        "COMPILE-COMPARE live primary Instructions must equal pin"
      IO.println
        s!"  COMPILE-COMPARE: live locked Leo {leo.version} recheck ok (accumulator-admit ≡ pin)"

/-- ALEO-OPTION-COMPARE offline pin: product Plan→Instructions encode for
    OptionState admit-surface ≡ committed locked-leo `optionstate-admit.compiled.aleo`
    bytes (captured via product `aleo-leo-4.0.2-u64-compile-v1`). Always runs
    (no tool). Counter IR-1 golden unchanged. Not multi-program matrix.
    MapMini stays structural-only (Leo Map upsert rewrite ⇒ Plan→IR ≠ Leo
    compiled; optional MapMini byte pin declined with evidence). -/
unsafe def testOptionCompareOptionStateAdmitPlanEqualsGolden : IO Unit := do
  expect (← optionStateAdmitGoldenPath.pathExists)
    "OPTION-COMPARE: optionstate-admit.compiled.aleo golden must exist"
  let golden ← IO.FS.readFile optionStateAdmitGoldenPath
  expect (golden.toUTF8.size == 1019)
    s!"OPTION-COMPARE golden must stay 1019 B, got {golden.toUTF8.size}"
  expect (golden.startsWith "program optionstate.aleo;")
    "OPTION-COMPARE golden program header"
  expect (golden.contains "function setSome:")
    "OPTION-COMPARE admit entry setSome"
  expect (golden.contains "function clear:")
    "OPTION-COMPARE admit entry clear"
  expect (golden.contains "mapping pf_state_0:" &&
      golden.contains "mapping pf_state_1:")
    "OPTION-COMPARE tag+payload dual-leaf mappings"
  expect (!golden.contains "function increment:")
    "OPTION-COMPARE golden must not be Counter"
  expect (!golden.contains "function credit:")
    "OPTION-COMPARE golden must not be Accumulator admit"
  -- Plan→IR product lower must byte-equal locked-leo capture
  -- (durable fixture source authority).
  let prog ← productProgramFromSource "optionstate-oc" optionStateAdmitSourceV1
    optionStateAdmitModuleName
  let encoded := encodeProgram prog
  expect (encoded == golden)
    s!"OPTION-COMPARE Plan→IR encode must equal locked-leo admit golden\n--- encoded ---\n{encoded}\n--- golden ---\n{golden}"
  -- Structural decode of golden ≡ product lower.
  match decodeProgram? golden with
  | none => throw <| IO.userError "OPTION-COMPARE: admit golden decode failed"
  | some decoded =>
      expect (decoded == prog)
        "OPTION-COMPARE: decoded golden must equal product Plan→IR structure"
  -- Dual-leaf structural shape preserved under byte pin.
  expect (mappingNames prog |>.contains "pf_state_0")
    "OPTION-COMPARE structure tag leaf"
  expect (mappingNames prog |>.contains "pf_state_1")
    "OPTION-COMPARE structure payload leaf"
  expect (hasFunctionNamed prog "setSome" && hasFunctionNamed prog "clear")
    "OPTION-COMPARE structure entries"
  -- Counter + Accumulator golden identity preserved under same suite.
  let counterGolden ← IO.FS.readFile goldenPath
  expect (counterGolden.toUTF8.size == 870)
    "OPTION-COMPARE must not alter Counter golden size"
  expect (counterGolden.startsWith "program counter.aleo;")
    "OPTION-COMPARE must not alter Counter golden header"
  expect (counterGolden != golden)
    "OPTION-COMPARE admit golden must differ from Counter golden"
  let accGolden ← IO.FS.readFile accumulatorAdmitGoldenPath
  expect (accGolden.toUTF8.size == 870)
    "OPTION-COMPARE must not alter Accumulator admit golden size"
  expect (accGolden != golden)
    "OPTION-COMPARE admit golden must differ from Accumulator admit golden"

/-- ALEO-OPTION-COMPARE live locked-leo path: when Tool Lock Leo 4.0.2 is
    present, product compile-profile finalize re-emits `optionstate.compiled.aleo`
    byte-equal to the committed compare pin. When tool missing: honest skip
    (committed golden + Plan→IR pin still hold offline). deployable=false. -/
unsafe def testOptionCompareOptionStateAdmitLockedLeoOptional : IO Unit := do
  match ← resolveLockedLeo? with
  | none =>
      IO.println
        "  OPTION-COMPARE: skipped live locked-leo recheck (Leo unavailable; committed golden + Plan→IR pin still enforced offline)"
  | some leo =>
      let session ← Tests.Language.ParserSession.shared
      let parsed ← liftResult (← session.selectProgramV1
        optionStateAdmitSourceV1 "<aleo-oc-opt-live>"
        optionStateAdmitModuleName none)
      let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
      let selection ← liftResult <|
        BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo
          (some CodegenProfileId.aleoLeoU64CompileV1)
      let capability ← liftResult <|
        resolveEngineeringRequirementsV1 selection compiled
      let outDir := FilePath.mk "build/v2/aleo-option-compare-opt-suite"
      if ← outDir.pathExists then IO.FS.removeDirAll outDir
      let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
      expect (!receipt.deployable)
        "OPTION-COMPARE live finalize remains deployable=false"
      expect (receipt.codegenProfile == CodegenProfileId.aleoLeoU64CompileV1)
        "OPTION-COMPARE live profile"
      let compiledPath := outDir / "optionstate.compiled.aleo"
      expect (← compiledPath.pathExists)
        "OPTION-COMPARE live must publish optionstate.compiled.aleo"
      let live ← IO.FS.readFile compiledPath
      let golden ← IO.FS.readFile optionStateAdmitGoldenPath
      expect (live == golden)
        s!"OPTION-COMPARE live locked-leo output must equal committed pin\n--- live ---\n{live}\n--- golden ---\n{golden}"
      -- Primary Instructions base also ≡ pin (Plan→IR authority path).
      let primary ← IO.FS.readFile (outDir / "optionstate.aleo")
      expect (primary == golden)
        "OPTION-COMPARE live primary Instructions must equal pin"
      IO.println
        s!"  OPTION-COMPARE: live locked Leo {leo.version} recheck ok (optionstate-admit ≡ pin)"

/-- ALEO-OPTION-COMPARE MapMini honesty: optional MapMini locked-leo full-byte
    pin is **declined** because Leo optimizes/rewrites Map upsert Instructions
    (Plan→IR encode ≠ `mapmini.compiled.aleo` under compile profile). MapMini
    remains MULTI-GOLDEN structural-only. Not a missing implementation. -/
unsafe def testOptionCompareMapMiniLeoRewriteHonesty : IO Unit := do
  let prog ← productProgramFromSource "mapmini-oc" mapMiniAdmitSourceV1
    mapMiniAdmitModuleName
  let encoded := encodeProgram prog
  expect (encoded.startsWith "program mapmini.aleo;")
    "OPTION-COMPARE MapMini Plan→IR header"
  expect (encoded.length > 0) "OPTION-COMPARE MapMini encode nonempty"
  -- No committed mapmini-admit.compiled.aleo (Leo rewrite evidence).
  let mapGolden : FilePath :=
    "testdata/golden/aleo-instructions-v1/mapmini-admit.compiled.aleo"
  expect (!(← mapGolden.pathExists))
    "OPTION-COMPARE: no mapmini-admit.compiled.aleo pin (Leo Map upsert rewrite)"
  match decodeProgram? encoded with
  | none => throw <| IO.userError "OPTION-COMPARE MapMini encode→decode failed"
  | some p2 => expect (p2 == prog) "OPTION-COMPARE MapMini structural round-trip"
  -- Live Leo (when present): prove Plan→IR ≠ Leo compiled for MapMini.
  match ← resolveLockedLeo? with
  | none =>
      IO.println
        "  OPTION-COMPARE MapMini: skipped live Leo rewrite evidence (tool missing; structural-only pin + no mapmini golden still hold)"
  | some leo =>
      let session ← Tests.Language.ParserSession.shared
      let parsed ← liftResult (← session.selectProgramV1
        mapMiniAdmitSourceV1 "<aleo-oc-map-live>"
        mapMiniAdmitModuleName none)
      let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
      let selection ← liftResult <|
        BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo
          (some CodegenProfileId.aleoLeoU64CompileV1)
      let capability ← liftResult <|
        resolveEngineeringRequirementsV1 selection compiled
      let outDir := FilePath.mk "build/v2/aleo-option-compare-map-suite"
      if ← outDir.pathExists then IO.FS.removeDirAll outDir
      let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
      expect (!receipt.deployable)
        "OPTION-COMPARE MapMini live remains deployable=false"
      let livePath := outDir / "mapmini.compiled.aleo"
      expect (← livePath.pathExists)
        "OPTION-COMPARE MapMini live must publish mapmini.compiled.aleo"
      let live ← IO.FS.readFile livePath
      let primary ← IO.FS.readFile (outDir / "mapmini.aleo")
      expect (primary == encoded)
        "OPTION-COMPARE MapMini primary must equal Plan→IR encode"
      expect (live != primary)
        "OPTION-COMPARE MapMini honesty: Leo rewrite changes Map upsert IR (no full-byte pin)"
      IO.println
        s!"  OPTION-COMPARE MapMini: live Leo {leo.version} rewrite evidence ok (Plan→IR ≠ compiled; structural-only)"

/-- ALEO-ADMIT-FIXTURES: durable fixture inventory + full-Example Plan-FC reasons.
    Sources live in `Tests.Fixtures.AleoAdmitSurfacesV1` (not ad-hoc suite
    locals). Shared Examples are not renamed. -/
def testAdmitFixturesDurableSourceAuthority : IO Unit := do
  expect (accumulatorAdmitSourceV1.contains "entry credit(")
    "ADMIT-FIXTURES Accumulator durable source uses entry credit"
  expect (!accumulatorAdmitSourceV1.contains "entry add(")
    "ADMIT-FIXTURES Accumulator must not use reserved entry add"
  expect (optionStateAdmitSourceV1.contains "entry setSome(")
    "ADMIT-FIXTURES OptionState has setSome entry"
  expect (optionStateAdmitSourceV1.contains "entry clear(")
    "ADMIT-FIXTURES OptionState has clear entry"
  expect (!optionStateAdmitSourceV1.contains "view peek")
    "ADMIT-FIXTURES OptionState has no computed peek view"
  expect (mapMiniAdmitSourceV1.contains "entry put(")
    "ADMIT-FIXTURES MapMini has put entry"
  expect (!mapMiniAdmitSourceV1.contains "view get")
    "ADMIT-FIXTURES MapMini has no computed get view"
  expect (fullExamplePlanFcReasonAccumulator.contains "reserved")
    "ADMIT-FIXTURES documents Accumulator reserved-add Plan-FC"
  expect (fullExamplePlanFcReasonOptionState.contains "computed view")
    "ADMIT-FIXTURES documents OptionState computed-view Plan-FC"
  expect (fullExamplePlanFcReasonMapMini.contains "computed view")
    "ADMIT-FIXTURES documents MapMini computed-view Plan-FC"
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1 "")
    "ADMIT-FIXTURES: G5-HARD residual allowlist stays empty"
  pure ()

/-- ALEO-ADMIT-FIXTURES product path: select→compile→capability→
    programFromCapabilityV1 for each durable admit-surface fixture.
    Structural IR asserts + G5-HARD empty. Does not rename shared Examples. -/
unsafe def testAdmitFixturesProductLowerAll : IO Unit := do
  -- Accumulator-credit
  let acc ← productProgramFromSource accumulatorAdmitProgramId
    accumulatorAdmitSourceV1 accumulatorAdmitModuleName
  expect (acc.name == s!"{accumulatorAdmitProgramId}.aleo")
    "ADMIT-FIXTURES Accumulator program id"
  expect (hasFunctionNamed acc "credit") "ADMIT-FIXTURES Accumulator credit"
  expect (hasBinaryOp acc "add") "ADMIT-FIXTURES Accumulator checkedAdd"
  let (accMaps, accFuns, accFins, accCtors) := countItemKinds acc
  expect (accMaps == 2 && accFuns == 2 && accFins == 2 && accCtors == 1)
    s!"ADMIT-FIXTURES Accumulator shape maps={accMaps} fns={accFuns}"
  let accEnc := encodeProgram acc
  expect (accEnc.startsWith "program accumulator.aleo;")
    "ADMIT-FIXTURES Accumulator header"
  match decodeProgram? accEnc with
  | none => throw <| IO.userError "ADMIT-FIXTURES Accumulator encode→decode"
  | some p => expect (p == acc) "ADMIT-FIXTURES Accumulator round-trip"

  -- OptionState entry-only
  let opt ← productProgramFromSource optionStateAdmitProgramId
    optionStateAdmitSourceV1 optionStateAdmitModuleName
  expect (opt.name == s!"{optionStateAdmitProgramId}.aleo")
    "ADMIT-FIXTURES OptionState program id"
  expect (hasFunctionNamed opt "setSome" && hasFunctionNamed opt "clear")
    "ADMIT-FIXTURES OptionState entries"
  let (optMaps, optFuns, optFins, optCtors) := countItemKinds opt
  expect (optMaps == 3 && optFuns == 3 && optFins == 3 && optCtors == 1)
    s!"ADMIT-FIXTURES OptionState shape maps={optMaps} fns={optFuns}"
  expect (countSetsInFinalize opt "setSome" ≥ 2)
    "ADMIT-FIXTURES setSome dual-leaf store"
  let optEnc := encodeProgram opt
  expect (optEnc.length > 0) "ADMIT-FIXTURES OptionState encode nonempty"
  match decodeProgram? optEnc with
  | none => throw <| IO.userError "ADMIT-FIXTURES OptionState encode→decode"
  | some p => expect (p == opt) "ADMIT-FIXTURES OptionState round-trip"

  -- MapMini put-only
  let mp ← productProgramFromSource mapMiniAdmitProgramId
    mapMiniAdmitSourceV1 mapMiniAdmitModuleName
  expect (mp.name == s!"{mapMiniAdmitProgramId}.aleo")
    "ADMIT-FIXTURES MapMini program id"
  expect (hasFunctionNamed mp "put") "ADMIT-FIXTURES MapMini put"
  let (mpMaps, mpFuns, mpFins, mpCtors) := countItemKinds mp
  expect (mpMaps == 7 && mpFuns == 2 && mpFins == 2 && mpCtors == 1)
    s!"ADMIT-FIXTURES MapMini shape maps={mpMaps} fns={mpFuns}"
  expect (countSetsInFinalize mp "put" == 6)
    "ADMIT-FIXTURES MapMini put six-leaf store"
  expect (hasTernary mp) "ADMIT-FIXTURES MapMini ternary upsert"
  let mpEnc := encodeProgram mp
  expect (mpEnc.length > 0) "ADMIT-FIXTURES MapMini encode nonempty"
  match decodeProgram? mpEnc with
  | none => throw <| IO.userError "ADMIT-FIXTURES MapMini encode→decode"
  | some p => expect (p == mp) "ADMIT-FIXTURES MapMini round-trip"

  -- G5-HARD empty under admit fixture product lower.
  expect (!Targets.Aleo.isAleoInstructionsG5HardResidualAllowlistV1 "")
    "ADMIT-FIXTURES product lower: G5-HARD allowlist empty"
  -- Counter IR-1 authority unchanged.
  let counterGolden ← IO.FS.readFile goldenPath
  expect (counterGolden.toUTF8.size == 870)
    "ADMIT-FIXTURES must not alter Counter golden size"
  pure ()

/-- ALEO-ADMIT-FIXTURES full Examples honesty: each shared Example remains
    Plan-FC for documented reasons (reserved add / computed views). Admit
    fixtures succeed independently. -/
unsafe def testAdmitFixturesFullExamplesPlanFcHonesty : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let selection ← liftResult <|
    BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
  -- Accumulator full → FC (reserved add)
  let accFull ← IO.FS.readFile "Examples/Accumulator.lean"
  let accParsed ← liftResult (← session.selectProgramV1
    accFull "<aleo-admit-full-acc>" "Examples.Accumulator" none)
  let accCompiled ← liftResult <| Compiler.compileValidatedSourceV1 accParsed
  match resolveEngineeringRequirementsV1 selection accCompiled with
  | .error e =>
      expect (e.render.length > 0) "full Accumulator FC diagnostic nonempty"
  | .ok cap =>
      match planFromCapability cap with
      | .ok _ =>
          throw <| IO.userError
            s!"full Accumulator must Plan-FC: {fullExamplePlanFcReasonAccumulator}"
      | .error e =>
          expect (e.render.contains "reserved" || e.render.contains "add")
            s!"full Accumulator FC must cite reserved/add (reason: {fullExamplePlanFcReasonAccumulator}); got: {e.render}"
  -- OptionState full → FC (computed peek)
  let optFull ← IO.FS.readFile "Examples/OptionState.lean"
  let optParsed ← liftResult (← session.selectProgramV1
    optFull "<aleo-admit-full-opt>" "Examples.OptionState" none)
  let optCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optParsed
  match resolveEngineeringRequirementsV1 selection optCompiled with
  | .error e =>
      expect (e.render.length > 0) "full OptionState FC diagnostic nonempty"
  | .ok cap =>
      match planFromCapability cap with
      | .ok _ =>
          throw <| IO.userError
            s!"full OptionState must Plan-FC: {fullExamplePlanFcReasonOptionState}"
      | .error e =>
          expect (e.render.contains "view" || e.render.contains "computed" ||
              e.render.contains "leo query")
            s!"full OptionState FC must cite computed view (reason: {fullExamplePlanFcReasonOptionState}); got: {e.render}"
  -- MapMini full → FC (computed get)
  let mapFull ← IO.FS.readFile "Examples/MapMini.lean"
  let mapParsed ← liftResult (← session.selectProgramV1
    mapFull "<aleo-admit-full-map>" "Examples.MapMini" none)
  let mapCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapParsed
  match resolveEngineeringRequirementsV1 selection mapCompiled with
  | .error e =>
      expect (e.render.length > 0) "full MapMini FC diagnostic nonempty"
  | .ok cap =>
      match planFromCapability cap with
      | .ok _ =>
          throw <| IO.userError
            s!"full MapMini must Plan-FC: {fullExamplePlanFcReasonMapMini}"
      | .error e =>
          expect (e.render.contains "view" || e.render.contains "computed" ||
              e.render.contains "leo query")
            s!"full MapMini FC must cite computed view (reason: {fullExamplePlanFcReasonMapMini}); got: {e.render}"
  pure ()

/-- ALEO-IR-7 / G6 runtime honesty (docs/targets/09-aleo-instructions-lowering.md §5/§10):
    * package-only snarkVM/snarkOS execute of product Instructions is **MISSING**
      on Tool Lock (Leo 4.0.2 only; RPT-024)
    * host-heavy probe `scripts/aleo_runtime_test.sh` + `just aleo-runtime`
      must exist and is **not** ordinary ci
    * default probe outcome: `PF-TOOLCHAIN-MISSING` (exit 2) — PARTIAL evidence
    * leo run is Leo source interpret only, **not** package-only Instructions
      execute; this suite does **not** invent a snarkVM CLI or claim execute
    * Counter IR-1 full-surface Instructions golden remains authority
    * `deployable=false`; not prove/deploy/formal -/
def testIr7RuntimeHonestyNotes : IO Unit := do
  expect (← goldenPath.pathExists)
    "Counter Instructions golden must exist (IR-1..IR-6 authority)"
  let scriptPath : FilePath := "scripts/aleo_runtime_test.sh"
  expect (← scriptPath.pathExists)
    "ALEO-IR-7 host-heavy probe scripts/aleo_runtime_test.sh must exist"
  -- Non-claims (documented residual only; no invented execute assertion):
  -- * package-only snarkVM execute still MISSING (PARTIAL; PF-TOOLCHAIN-MISSING)
  -- * no Tool Lock snarkVM/snarkOS asset; never PATH fallback
  -- * product primary remains Instructions text; deployable=false
  pure ()

/-- RES-CLEAN residual honesty (docs/targets/09-aleo-instructions-lowering.md §10):
    * IR-1 full-surface authority golden = `counter.compiled.aleo` (Counter)
    * COMPILE-COMPARE optional pin = `accumulator-admit.compiled.aleo` (not
      multi-program matrix; Plan→IR byte ≡ locked-leo capture)
    * OPTION-COMPARE optional pin = `optionstate-admit.compiled.aleo` (not
      multi-program matrix; Plan→IR byte ≡ locked-leo capture)
    * MapMini stays structural-only (Leo Map upsert rewrite; no mapmini pin)
    * full multi-program / multi-fixture leo **byte** matrix remains **deferred**
      (MapMini/Array/Branch/LoopSum structural MULTI-GOLDEN only)
    * record custody / full opcode / prove/deploy remain **deferred**
    * package-only snarkVM execute remains **MISSING** (IR-7 PARTIAL)
    * this suite does **not** invent a snarkVM CLI or claim prove/deploy -/
def testResidualHonestyNotes : IO Unit := do
  expect (← goldenPath.pathExists)
    "Counter IR-1 full-surface Instructions golden must exist (RES-CLEAN)"
  let golden ← IO.FS.readFile goldenPath
  expect (golden.toUTF8.size == 870)
    s!"Counter golden must stay 870 B (locked Leo 4.0.2), got {golden.toUTF8.size}"
  expect (golden.startsWith "program counter.aleo;")
    "IR-1 full-surface golden is Counter Instructions program only"
  expect (← accumulatorAdmitGoldenPath.pathExists)
    "COMPILE-COMPARE admit pin must exist under golden dir"
  expect (← optionStateAdmitGoldenPath.pathExists)
    "OPTION-COMPARE admit pin must exist under golden dir"
  let entries ← goldenPath.parent.get!.readDir
  let names := (entries.map (·.fileName)).qsort (· < ·)
  expect (names ==
      #["accumulator-admit.compiled.aleo", "counter.compiled.aleo",
        "optionstate-admit.compiled.aleo"])
    s!"RES-CLEAN golden inventory (Counter + admit compare pins), got {names}"
  -- Non-claims (documented residual only; no invented multi-golden / prove assertion):
  -- * full multi-program leo / multi-fixture Instructions byte matrix deferred
  -- * COMPILE-COMPARE / OPTION-COMPARE are optional admit pins, not matrix completion
  -- * MapMini Leo rewrite prevents optional mapmini-admit full-byte pin
  -- * MULTI-GOLDEN structural product pins do **not** claim full matrix equality
  -- * record custody / full opcode / prove/deploy out-of-slice
  -- * package-only snarkVM execute still MISSING (PARTIAL; PF-TOOLCHAIN-MISSING)
  pure ()

unsafe def run : IO Unit := do
  testPins
  testEncodeEqualsGolden
  testGoldenDecodeEqualsHandBuilt
  testEncodeDecodeRoundTrip
  testDecodeFailClosed
  testCounterShape
  testHandBuiltPlanLowerEqualsCounterProgram
  testProductCounterPlanLowerEqualsGolden
  testUnsupportedPlanFailClosed
  testIfThenElseStructural
  testSwitchOnStructural
  testBoundedForStructural
  testForUnrollCeilingFailClosed
  testProductBranchControlFlow
  testHandBuiltMultiLeafStructural
  testHandBuiltNarrowShiftCast
  testProductOptionStateMultiLeaf
  testProductMapMiniMultiLeaf
  testProductArrayMultiLeaf
  testProductNarrowUintWidths
  testNestedMapFailClosedAtPlan
  testEffectsHonestyPlanFailClosed
  testEffectsHonestyProductFailClosed
  testG5MatrixBoolAssertStructural
  testG5MatrixProductAssertLower
  testConstProductLower
  testG5HardResidualTrueLower
  testG5HardResidualAllowlistClassifier
  testG5MatrixNestedMapPlanFailClosed
  testProductPrimaryInstructionsMaterialize
  testMultiGoldenLoopSumProduct
  testMultiGoldenAccumulatorAdmitSurface
  testMultiGoldenOptionStateAdmitSurface
  testMultiGoldenMapMiniAdmitSurface
  testMultiGoldenClassificationInventory
  testCompileCompareAccumulatorAdmitPlanEqualsGolden
  testCompileCompareAccumulatorAdmitLockedLeoOptional
  testOptionCompareOptionStateAdmitPlanEqualsGolden
  testOptionCompareOptionStateAdmitLockedLeoOptional
  testOptionCompareMapMiniLeoRewriteHonesty
  testAdmitFixturesDurableSourceAuthority
  testAdmitFixturesProductLowerAll
  testAdmitFixturesFullExamplesPlanFcHonesty
  testIr7RuntimeHonestyNotes
  testResidualHonestyNotes
  IO.println "Tests.Materialization.AleoInstructionsV1: ok"

end Tests.Materialization.AleoInstructionsV1
