/-
  Tests.Materialization.PsyDpnV1 — PSY-DPN-1/2/3 schema + Counter golden +
  Plan lower + if/match/for structural probes.

  Pins:
    * OpType / DataType exact discriminants used by Counter (+ Select)
    * encodeIndexedId (dataType<<32)|index
    * golden parse → package structural equality with hand-built
    * encode round-trip
    * Examples/Counter product Plan → DPN package ≡ golden (DPN-2)
    * DPN-3: if → Select + conditional store; match → nested Select/eq;
      bounded for → static unroll; while-shaped FC via maxIter budget
-/
import ProofForgeV2
import ProofForgeV2.Targets.Psy
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1
import ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.PsyDpnV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.Psy
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1
open ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1
open ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1

private def expect (cond : Bool) (message : String) : IO Unit :=
  unless cond do throw <| IO.userError message

private def liftResult {α : Type} : CompileResult α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError e.render

def testOpTypeDiscriminants : IO Unit := do
  expect (OpTypeV1.inputTarget.toUInt16 == 0) "InputTarget=0"
  expect (OpTypeV1.constant.toUInt16 == 1) "Constant=1"
  expect (OpTypeV1.constantTrue.toUInt16 == 2) "ConstantTrue=2"
  expect (OpTypeV1.add.toUInt16 == 4) "Add=4"
  expect (OpTypeV1.gte.toUInt16 == 15) "Gte=15"
  expect (OpTypeV1.select.toUInt16 == 23) "Select=23"
  expect (OpTypeV1.getStateCommandResultSingle.toUInt16 == 54)
    "GetStateCommandResultSingle=54"
  -- hole 39 must not map
  expect (OpTypeV1.ofUInt16? 39 |>.isNone) "op 39 is a hole"
  expect (OpTypeV1.ofUInt16? 54 == some .getStateCommandResultSingle)
    "ofUInt16 54"
  expect (OpTypeV1.ofUInt16? 23 == some .select) "ofUInt16 Select"

def testEncodeIndexedId : IO Unit := do
  expect (encodeIndexedId .bool 0 == 4294967296) "bool#0"
  expect (encodeIndexedId .bool 1 == 4294967297) "bool#1"
  expect (encodeIndexedId .target 0 == 0) "target#0"
  match decodeIndexedId 4294967296 with
  | some (.bool, 0) => pure ()
  | other => throw <| IO.userError s!"decode bool#0 failed: {repr other}"

/-- Official dargo package JSON (field order may differ from Lean mkObj). -/
def testCounterGoldenDecode : IO Unit := do
  let goldenRaw ← IO.FS.readFile "testdata/golden/psy-dpn-v1/counter-package.v1.json"
  let golden := "".intercalate (goldenRaw.splitOn "\n")
  match parsePackage? golden with
  | none => throw <| IO.userError "failed to parse Counter DPN golden"
  | some pkg =>
      expect (pkg == counterPackageGoldenV1)
        "decoded dargo golden must equal hand-built counterPackageGoldenV1"
      expect (pkg.size == 3) "get + increment + initialize"
      expect (pkg[0]!.name == "get") "first method name-sorted"
      expect (pkg[1]!.name == "increment") "second method"
      expect (pkg[2]!.name == "initialize") "third method"
      expect (pkg[1]!.assertions.size == 1) "overflow assert present"
      expect (pkg[1]!.assertions[0]!.message == "u64 add overflow") "assert message"

/-- Encode → parse structural round-trip (ProofForge compact JSON key order). -/
def testCounterEncodeRoundTrip : IO Unit := do
  let encoded := encodePackageCompact counterPackageGoldenV1
  match parsePackage? encoded with
  | none => throw <| IO.userError s!"failed to parse our encode: {encoded}"
  | some pkg =>
      expect (pkg == counterPackageGoldenV1)
        "encodePackageCompact round-trip must preserve Counter package"

/-- PSY-DPN-2: product Plan for Examples/Counter lowers to golden package. -/
unsafe def testCounterPlanLowerEqualsGolden : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let src ← IO.FS.readFile "Examples/Counter.lean"
  let parsed ← liftResult (← session.selectProgramV1 src "<dpn-c>" "Examples.Counter" none)
  let compiled ← liftResult <| compileValidatedSourceV1 parsed
  let selection ← liftResult <| BuildSelectionV1.resolveBuildSelectionV1 TargetId.psy none
  let cap ← liftResult <| resolveEngineeringRequirementsV1 selection compiled
  let pkg ← liftResult <| packageFromCapabilityV1 cap
  expect (pkg == counterPackageGoldenV1)
    s!"Plan→DPN package must equal Counter golden (got {pkg.map (·.name)})"

/-- Hand-built PlanFunction: if param>0 then store param else store 0; return load. -/
def testIfThenElseSelectAndConditionalStore : IO Unit := do
  let fn : PlanFunction := {
    index := 0
    name := "maybeSet"
    kind := .mutate
    params := #[{ sourceIndex := 0, name := "x", isBool := false }]
    body := #[
      .ifThenElse (.compare .gt (.param 0) (.literal 0))
        #[.store 0 (.param 0)]
        #[.store 0 (.literal 0)],
      .returnValue (.stateLoad 0)
    ]
    resultIsBool := false
    resultIsUnit := false
  }
  let d ← liftResult <| lowerFunctionForTestV1 fn
  -- Store-in-if uses complementary conditional Sets (and BoolAnd with writeCond).
  -- Select appears when arms return (see switch test) or for gated asserts.
  let sets := d.stateCommands.filterMap fun
    | .setContractStateSlotSingle cond _ _ => some cond
    | _ => none
  expect (sets.size == 2)
    s!"both if arms store → two Sets, got {sets.size}"
  let hasNonTrueCond := sets.any fun c => c != encodeIndexedId .bool 0
  expect hasNonTrueCond
    "store-in-if must gate SetContractStateSlotSingle on branch condition"
  expect (d.definitions.any fun defn => defn.opType == .gt)
    "param > 0 must lower to Gt"
  expect (d.definitions.any fun defn => defn.opType == .boolAnd)
    "branch write condition must BoolAnd with outer writeCond"
  expect (d.circuitOutputs.size == 1) "must return a value wire"

/-- Match/switch desugars to eq + Select path. -/
def testSwitchOnDesugarsToEqSelect : IO Unit := do
  let fn : PlanFunction := {
    index := 0
    name := "byTag"
    kind := .mutate
    params := #[{ sourceIndex := 0, name := "tag", isBool := false }]
    body := #[
      .switchOn (.param 0)
        #[(1, #[.returnValue (.literal 10)]),
          (2, #[.returnValue (.literal 20)])]
        #[.returnValue (.literal 0)]
    ]
    resultIsBool := false
    resultIsUnit := false
  }
  let d ← liftResult <| lowerFunctionForTestV1 fn
  expect (d.definitions.any fun defn => defn.opType == .eq)
    "switch cases must compare scrutinee with eq"
  expect (d.definitions.any fun defn => defn.opType == .select)
    "switch arms must Select-merge return values"
  expect (d.circuitOutputs.size == 1) "switch must produce one output"

/-- Bounded for static unroll: body store(load+1) repeated under step guards. -/
def testBoundedForStaticUnroll : IO Unit := do
  let fn : PlanFunction := {
    index := 0
    name := "addFour"
    kind := .mutate
    params := #[{ sourceIndex := 0, name := "n", isBool := false }]
    body := #[
      .forLoop (.param 0) (.checkedAdd (.param 0) (.literal 4)) 4
        #[.store 0 (.checkedAdd (.stateLoad 0) (.literal 1))],
      .returnValue (.stateLoad 0)
    ]
    resultIsBool := false
    resultIsUnit := false
  }
  let d ← liftResult <| lowerFunctionForTestV1 fn
  -- Bound assert present
  expect (d.assertions.any fun a => a.message == "boundExceeded")
    "bounded for must assert span <= maxIter when range nonempty"
  -- Four unrolled step guards → multiple Add (start+k and body +1) and Lt
  let addCount := d.definitions.foldl (fun n defn =>
    if defn.opType == .add then n + 1 else n) 0
  expect (addCount >= 4)
    s!"unroll must emit several Add ops, got {addCount}"
  let setCount := d.stateCommands.foldl (fun n c =>
    match c with
    | .setContractStateSlotSingle .. => n + 1
    | _ => n) 0
  expect (setCount == 4)
    s!"each unrolled step body store must emit a Set, got {setCount}"
  -- Step conditions should not all be ConstantTrue (uses i < end)
  let setConds := d.stateCommands.filterMap fun
    | .setContractStateSlotSingle cond _ _ => some cond
    | _ => none
  expect (setConds.any fun c => c != encodeIndexedId .bool 0)
    "unrolled stores must be gated by step condition (i < end)"

/-- Over-budget forLoop fails closed (no while/unbounded). -/
def testBoundedForOverBudgetFailClosed : IO Unit := do
  let fn : PlanFunction := {
    index := 0
    name := "tooBig"
    kind := .mutate
    params := #[]
    body := #[
      .forLoop (.literal 0) (.literal 100) 65
        #[.store 0 (.literal 1)]
    ]
    resultIsBool := false
    resultIsUnit := true
  }
  match lowerFunctionForTestV1 fn with
  | .error e =>
      expect (e.render.contains "unroll budget" || e.render.contains "PSY-DPN-3")
        s!"over-budget for must mention unroll budget, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "maxIterations=65 must fail closed (budget 64)"

/-- Examples/LoopSum product Plan lowers (structural; not dargo golden). -/
unsafe def testLoopSumProductLower : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let src ← IO.FS.readFile "Examples/LoopSum.lean"
  let parsed ← liftResult (← session.selectProgramV1 src "<dpn-loop>" "Examples.LoopSum" none)
  let compiled ← liftResult <| compileValidatedSourceV1 parsed
  let selection ← liftResult <| BuildSelectionV1.resolveBuildSelectionV1 TargetId.psy none
  let cap ← liftResult <| resolveEngineeringRequirementsV1 selection compiled
  let pkg ← liftResult <| packageFromCapabilityV1 cap
  expect (pkg.size == 3)
    s!"LoopSum must lower 3 methods, got {pkg.map (·.name)}"
  expect (pkg.any fun f => f.name == "run") "must include run"
  expect (pkg.any fun f => f.name == "initialize") "must include initialize"
  expect (pkg.any fun f => f.name == "get") "must include get"
  let some run := pkg.find? (·.name == "run") |
    throw <| IO.userError "missing run after lower"
  expect (run.assertions.any fun a => a.message == "boundExceeded")
    "LoopSum run must carry boundExceeded assert"
  let setCount := run.stateCommands.foldl (fun n c =>
    match c with
    | .setContractStateSlotSingle .. => n + 1
    | _ => n) 0
  -- LoopSum bounded 8 → 8 unrolled body stores
  expect (setCount == 8)
    s!"LoopSum run must emit 8 gated Sets for bounded 8, got {setCount}"

unsafe def run : IO Unit := do
  testOpTypeDiscriminants
  testEncodeIndexedId
  testCounterGoldenDecode
  testCounterEncodeRoundTrip
  testCounterPlanLowerEqualsGolden
  testIfThenElseSelectAndConditionalStore
  testSwitchOnDesugarsToEqSelect
  testBoundedForStaticUnroll
  testBoundedForOverBudgetFailClosed
  testLoopSumProductLower
  IO.println "Tests.Materialization.PsyDpnV1: ok"

end Tests.Materialization.PsyDpnV1

/-- Allow `lake env lean --run Tests/Materialization/PsyDpnV1.lean`. -/
unsafe def main : IO Unit :=
  Tests.Materialization.PsyDpnV1.run
