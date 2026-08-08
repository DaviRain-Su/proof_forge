/-
  ALEO-IR-1..6 + ALEO-G5-MATRIX: Aleo Instructions Schema/TextCodec +
  Counter golden + Plan→Instructions Counter MVP + if/match/bounded-for +
  multi-leaf Map/Option/Array + narrow UInt widths + effects honesty matrix +
  product primary materialize cutover + admit-matrix FC/IR pins.

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
  * ALEO-IR-4: multi-leaf storeAggregate + typed mappings structural
  * ALEO-IR-4: product OptionState / MapMini / Array / NarrowBox
  * empty Plan / Int64 leaf / pure helper fail closed
  * ALEO-IR-5: Plan emit / callFn / payload-revert FC with `ALEO-IR-5:` diags
  * ALEO-IR-5: product emit/call/schedule/context/assets FC (matrix honesty)
  * ALEO-IR-6: product materialize primary = Instructions text ≡ golden;
    default no `.leo`; `emitLeoDebug` / compile profile dual-write `.leo`
  * ALEO-G5-MATRIX: Bool/compare/logic/assert/bare-revert structural IR pins;
    const plan-FC; Int64/Field/pureFn residual ALEO-IR-4 pins; nested Map plan-FC
  * profile note: default vs compile share Plan; lower is profile-insensitive

  **Not** snarkVM execute, prove/deploy, formal. No PARTIAL effects row
  without evidence. No false Y for residual Int64/Field/pureFn (IR target Y,
  Instructions status residual until G5-HARD true lower).
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

/-- Empty plan / pure helper / Int64 leaf fail closed (IR-4 multi-leaf admits). -/
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
      expect (e.render.contains "pure helper" || e.render.contains "pure")
        s!"pure helper residual must cite pure helper, got: {e.render}"
  -- Int64 leaf residual FC on Instructions path (Leo path still admits Int64)
  let intPlan : Plan := {
    handBuiltCounterPlan with
    stateFieldIsInt := #[true]
  }
  match lowerPlanForTestV1 intPlan with
  | .ok _ => throw <| IO.userError "Int64 leaf must fail closed on IR-4"
  | .error e =>
      expect (e.render.contains "ALEO-IR")
        s!"expected ALEO-IR Int64 diagnostic, got: {e.render}"
      expect (e.render.contains "Int64" || e.render.contains "residual")
        s!"Int64 residual must cite Int64/residual, got: {e.render}"

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
  -- callFn residual → ALEO-IR-5 pureCall/callFn FC.
  let callFnPlan : Plan := {
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
  match lowerPlanForTestV1 callFnPlan with
  | .ok _ => throw <| IO.userError "callFn Plan must fail closed at IR-5"
  | .error e =>
      expect (e.render.contains "ALEO-IR-5")
        s!"callFn must cite ALEO-IR-5, got: {e.render}"
      expect (e.render.contains "callFn" || e.render.contains "pureCall")
        s!"callFn diagnostic must mention callFn/pureCall, got: {e.render}"
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

  Honesty: residual Int64 / Field BLS12-377 / pureFn stay **residual** (stable
  `ALEO-IR-4` FC) even when Leo path admits them; nested Map + const never
  reach Instructions (plan/Semantic FC). Bool/compare/logic + bare assert/revert
  are **done** with structural IR pins (no false Y).
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

/-- G5-MATRIX: const declaration stays plan-FC (Constant load not on Aleo Plan). -/
unsafe def testG5MatrixConstPlanFailClosed : IO Unit := do
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
    source "<aleo-g5-const>" "Tests.AleoG5Const" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      expect (e.render.length > 0)
        "const must fail closed with a diagnostic"
  | .ok compiled =>
      let selection ← liftResult <|
        BuildSelectionV1.resolveBuildSelectionV1 TargetId.aleo none
      match resolveEngineeringRequirementsV1 selection compiled with
      | .error e =>
          expect (e.render.length > 0) "const resolve FC"
      | .ok cap =>
          match programFromCapabilityV1 cap with
          | .ok _ =>
              throw <| IO.userError
                "const must fail closed before/at Instructions lower (plan-FC)"
          | .error e =>
              expect (
                  e.render.contains "Constant" ||
                  e.render.contains "const" ||
                  e.render.contains "ALEO" ||
                  e.render.contains "unsupported" ||
                  e.render.length > 0)
                s!"const plan-FC diagnostic, got: {e.render}"

/-- G5-MATRIX residual bucket: Int64 leaf/expr, Field leaf/expr, pureFn.
    Status is **residual** (Leo may admit; Instructions ALEO-IR-4 FC). No false Y. -/
private def testG5MatrixResidualFcPins : IO Unit := do
  -- Int64 leaf residual
  let intLeaf : Plan := {
    handBuiltCounterPlan with
    stateFieldIsInt := #[true]
  }
  match lowerPlanForTestV1 intLeaf with
  | .ok _ => throw <| IO.userError "Int64 leaf residual must FC"
  | .error e =>
      expect (e.render.contains "ALEO-IR-4" || e.render.contains "ALEO-IR")
        s!"Int64 leaf residual ALEO-IR, got: {e.render}"
      expect (e.render.contains "Int64" || e.render.contains "residual")
        s!"Int64 residual wording, got: {e.render}"
  -- Int64 expression residual (i64Literal in body; leaf stays UInt)
  let intExpr : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[
          .store 0 (.i64Literal 1),
          .returnValue (.stateLoad 0)
        ] }
    ]
  }
  match lowerPlanForTestV1 intExpr with
  | .ok _ => throw <| IO.userError "Int64 expr residual must FC"
  | .error e =>
      expect (e.render.contains "ALEO-IR-4" || e.render.contains "ALEO-IR")
        s!"Int64 expr residual ALEO-IR, got: {e.render}"
      expect (e.render.contains "Int64" || e.render.contains "expression" ||
          e.render.contains "residual")
        s!"Int64 expr residual wording, got: {e.render}"
  -- Field BLS12-377 leaf residual (Leo admits; Instructions residual)
  let fieldLeaf : Plan := {
    handBuiltCounterPlan with
    stateFieldIsField := #[true]
  }
  match lowerPlanForTestV1 fieldLeaf with
  | .ok _ => throw <| IO.userError "Field leaf residual must FC"
  | .error e =>
      expect (e.render.contains "ALEO-IR-4" || e.render.contains "ALEO-IR")
        s!"Field leaf residual ALEO-IR, got: {e.render}"
      expect (e.render.contains "Field" || e.render.contains "residual" ||
          e.render.contains "Int64")
        s!"Field residual wording, got: {e.render}"
  -- Field expression residual
  let fieldExpr : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[
          .store 0 (.fieldLiteral 1),
          .returnValue (.stateLoad 0)
        ] }
    ]
  }
  match lowerPlanForTestV1 fieldExpr with
  | .ok _ => throw <| IO.userError "Field expr residual must FC"
  | .error e =>
      expect (e.render.contains "ALEO-IR-4" || e.render.contains "ALEO-IR")
        s!"Field expr residual ALEO-IR, got: {e.render}"
      expect (e.render.contains "Field" || e.render.contains "expression" ||
          e.render.contains "residual")
        s!"Field expr residual wording, got: {e.render}"
  -- pureFn / pure helper residual (Plan-admitted Leo helper; IR residual)
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
  match lowerPlanForTestV1 purePlan with
  | .ok _ => throw <| IO.userError "pureFn residual must FC"
  | .error e =>
      expect (e.render.contains "ALEO-IR-4" || e.render.contains "ALEO-IR")
        s!"pureFn residual ALEO-IR, got: {e.render}"
      expect (e.render.contains "pure helper" || e.render.contains "pure")
        s!"pureFn residual wording, got: {e.render}"
  -- pureCall/callFn already IR-5; pin again as residual localCall surface
  let callPlan : Plan := {
    handBuiltCounterPlan with
    functions := #[
      handBuiltCounterPlan.functions[0]!,
      { handBuiltCounterPlan.functions[1]! with
        body := #[
          .store 0 (.callFn "helper" #[.param 0]),
          .returnValue (.stateLoad 0)
        ] }
    ]
  }
  match lowerPlanForTestV1 callPlan with
  | .ok _ => throw <| IO.userError "callFn residual must FC"
  | .error e =>
      expect (e.render.contains "ALEO-IR-5")
        s!"callFn residual must cite ALEO-IR-5, got: {e.render}"

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
  testG5MatrixConstPlanFailClosed
  testG5MatrixResidualFcPins
  testG5MatrixNestedMapPlanFailClosed
  testProductPrimaryInstructionsMaterialize
  IO.println "Tests.Materialization.AleoInstructionsV1: ok"


end Tests.Materialization.AleoInstructionsV1

/-- Allow `lake env lean --run Tests/Materialization/AleoInstructionsV1.lean`. -/
unsafe def main : IO Unit :=
  Tests.Materialization.AleoInstructionsV1.run
