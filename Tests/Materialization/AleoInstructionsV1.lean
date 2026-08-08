/-
  ALEO-IR-1 + ALEO-IR-2 + ALEO-IR-3: Aleo Instructions Schema/TextCodec +
  Counter golden + Plan→Instructions Counter MVP + if/match/bounded-for.

  Covers:
  * schema id / Leo golden version pins
  * hand-built `counterProgramV1` encode ≡ locked-leo golden file bytes
  * golden decode ≡ hand-built structure
  * encode → decode structural round-trip
  * decode fail-closed on truncated / unknown opcode
  * ALEO-IR-2: hand-built Counter Plan → Instructions ≡ counterProgramV1
  * ALEO-IR-2: Examples/Counter product Plan → Instructions ≡ golden
  * ALEO-IR-2: encode(product lower) ≡ golden bytes
  * ALEO-IR-3: ifThenElse → branch.eq/position structural
  * ALEO-IR-3: switchOn (match) → is.eq + nested branch structural
  * ALEO-IR-3: bounded for → static unroll + runtime gate structural
  * ALEO-IR-3: unbounded for (maxIterations > 4096) fail closed
  * multi-leaf / empty Plan fail closed
  * profile note: default vs compile share Plan; lower is profile-insensitive

  **Not** product primary materialize cutover (IR-6), snarkVM execute,
  prove/deploy, formal.
-/
import ProofForgeV2
import ProofForgeV2.Targets.Aleo
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
import ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
import ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1
import ProofForgeV2.Core.TargetIdentityV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.AleoInstructionsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.Aleo
open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
open ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
open ProofForgeV2.Targets.Aleo.Instructions.LowerPlanV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult {α : Type} : CompileResult α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError e.render

private def goldenPath : System.FilePath :=
  "testdata/golden/aleo-instructions-v1/counter.compiled.aleo"

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

/-- Empty / multi-leaf Plan fail closed (IR-3 keeps single-leaf until IR-4). -/
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
  let multi : Plan := {
    handBuiltCounterPlan with
    stateFieldNames := #["a", "b"]
    stateFieldIsInt := #[false, false]
    stateFieldUintWidth := #[0, 0]
    stateFieldIsField := #[false, false]
  }
  match lowerPlanForTestV1 multi with
  | .ok _ => throw <| IO.userError "multi-leaf plan must fail closed"
  | .error e =>
      expect (e.render.contains "ALEO-IR")
        s!"expected ALEO-IR multi-leaf diagnostic, got: {e.render}"
  -- pure helper fail closed on Instructions path
  let purePlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        isPureHelper := true
        touchesState := false
        body := #[.returnValue (.param 0)]
        resultDropped := false }
    ]
  }
  match lowerPlanForTestV1 purePlan with
  | .ok _ => throw <| IO.userError "pure helper must fail closed"
  | .error e =>
      expect (e.render.contains "ALEO-IR")
        s!"expected ALEO-IR pure-helper diagnostic, got: {e.render}"

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
      expect (e.render.contains "ALEO-IR-3")
        s!"expected ALEO-IR-3 for ceiling diagnostic, got: {e.render}"

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
  IO.println "Tests.Materialization.AleoInstructionsV1: ok"

end Tests.Materialization.AleoInstructionsV1

/-- Allow `lake env lean --run Tests/Materialization/AleoInstructionsV1.lean`. -/
unsafe def main : IO Unit :=
  Tests.Materialization.AleoInstructionsV1.run
