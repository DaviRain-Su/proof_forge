/-
  Quint target leaf tests (Q0): Plan/IR/emitter over retained SemanticProgramV1.
  Uses planFromCompiledSemanticV1 / buildFromCompiledSemanticV1 so the suite
  does not require registry wiring. Main agent registers this suite.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Quint
import ProofForgeV2.Targets.Registry
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.QuintSourceV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def planQuint (compiled : CompiledSemanticV1) : CompileResult Targets.Quint.Plan :=
  Targets.Quint.planFromCompiledSemanticV1 compiled

private def buildQuint (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) :=
  Targets.Quint.buildFromCompiledSemanticV1 compiled

/-- StateCell: plan shape + key Quint source fragments. -/
unsafe def testStateCellQuintSource : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateCell where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-state-cell>" "Tests.QuintStateCell" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect (plan.states.map (·.name) == #["count"])
    "StateCell Quint plan must carry the count state field"
  expect (plan.entries.map (·.name) == #["increment"])
    "StateCell Quint plan must carry the increment entry"
  expect (plan.views.map (·.name) == #["get"])
    "StateCell Quint plan must carry the get view"
  match plan.initializer with
  | some initFn =>
      expect (initFn.params == #["initial"])
        "StateCell init must carry the initial parameter"
      expect (initFn.stores.size == 1)
        "StateCell init must store count"
  | none => throw <| IO.userError "StateCell must have an initializer"
  let some inc := plan.entries[0]? |
    throw <| IO.userError "missing increment entry"
  let overflowOk :=
    match inc.checks[0]? with
    | some ck => inc.checks.size == 1 && ck.kind == .overflow
    | none => false
  expect overflowOk "increment must carry a single overflow check"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (fun f => f.path == "StateCell.qnt") |
    throw <| IO.userError "quint: missing StateCell.qnt"
  expect (qntFile.mediaType == "text/x-quint")
    "StateCell.qnt media type must be text/x-quint"
  let qnt := qntFile.contents
  expect (qnt.contains "module PFModel_StateCell {")
    "Quint source must declare a target-namespaced module"
  expect (qnt.contains "pure def PF_MAX_U64: int = 18446744073709551615")
    "Quint source must define PF_MAX_U64 exactly"
  expect (qnt.contains "var pf_state_count: int")
    "Quint source must declare count under the target-owned state namespace"
  expect (qnt.contains "var pf_last_action: int")
    "Quint source must declare pf_last_action"
  expect (qnt.contains "var pf_last_ok: bool")
    "Quint source must declare pf_last_ok"
  expect (qnt.contains "var pf_last_failure: int")
    "Quint source must declare pf_last_failure"
  expect (qnt.contains "action init =")
    "Quint source must declare action init"
  expect (qnt.contains "action step = any")
    "Quint source must declare action step"
  expect (qnt.contains "oneOf(0.to(PF_MAX_U64))")
    "UInt64 parameter domain must be oneOf(0.to(PF_MAX_U64))"
  expect (qnt.contains "nondet pf_arg_a1_0 = oneOf(0.to(PF_MAX_U64))")
    "entry parameters must use the collision-free target namespace"
  expect (qnt.contains "val ck0 =" && !qnt.contains "pure val ck0 =")
    "state-reading action locals must use Quint val, never pure val"
  expect (qnt.contains "pure def pf_view_get: int = pf_state_count")
    "view get must materialize under the target-owned view namespace"
  expect (qnt.contains "pf_last_increment_arg0")
    "entry must record last arg instrumentation"
  expect (qnt.contains "pf_last_increment_result")
    "entry must record last result instrumentation"

/-- Rollback-stutter: failed checked add keeps business state identity. -/
unsafe def testRollbackStutter : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateCell where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-stutter>" "Tests.QuintStutter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "StateCell.qnt") |
    throw <| IO.userError "quint: missing StateCell.qnt"
  let qnt := qntFile.contents
  -- On failure, count' equals pre-state count (stutter), not a blocked action.
  expect (qnt.contains "pf_state_count' = " || qnt.contains "pf_state_count'=")
    "action must assign the namespaced count state"
  expect (qnt.contains
      "pf_state_count' = if (ok1) pf_state_count + pf_arg_a1_0 else pf_state_count")
    "failed checked add must commit post-state only on success and otherwise stutter"
  expect (qnt.contains "pf_last_ok' = ok1")
    "instrumentation must always publish the aggregate success bit"
  expect (qnt.contains "val fail2 = if (not(ck0)) 1 else 0")
    "overflow must be the exact first-failure code 1"
  expect (qnt.contains "pf_last_failure' = fail2")
    "instrumentation must always publish the exact first-failure code"

/-- Initializer StateLoad observes canonical UInt64 zero, never an unconstrained pre-state. -/
unsafe def testInitializerDefaultZero : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program InitRead where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := count\n" ++
    "  entry read() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-init-zero>" "Tests.QuintInitZero" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  let some initFn := plan.initializer |
    throw <| IO.userError "InitRead must retain its initializer"
  match initFn.stores[0]? with
  | some (fieldIndex, Targets.Quint.Expr.litU64 value) =>
      expect (fieldIndex == 0 && value == 0)
        "initializer StateLoad must lower from canonical zero"
  | other =>
      throw <| IO.userError s!"unexpected initializer default store: {repr other}"
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "InitRead.qnt") |
    throw <| IO.userError "quint: missing InitRead.qnt"
  expect (qntFile.contents.contains "pf_state_count' = 0")
    "initial action must not read an unconstrained unprimed state"

/-- Sequential StateStore/StateLoad observes the newest overlay value in both
    initializer and entry bodies. -/
unsafe def testSequentialStateOverlay : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Overlay where\n" ++
    "  state count : UInt64\n" ++
    "  state mirror : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := 1\n" ++
    "    count := initial\n" ++
    "    mirror := count\n" ++
    "  entry replace(next : UInt64) : UInt64 do\n" ++
    "    count := next\n" ++
    "    mirror := count\n" ++
    "    return mirror\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-overlay>" "Tests.QuintOverlay" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  let some initFn := plan.initializer |
    throw <| IO.userError "Overlay must retain its initializer"
  expect (initFn.stores == #[(0, .param 0), (1, .param 0)])
    s!"initializer must read the latest explicit write, got {repr initFn.stores}"
  let some ent := plan.entries[0]? |
    throw <| IO.userError "Overlay must retain its entry"
  expect (ent.stores == #[(0, .param 0), (1, .param 0)])
    s!"entry write-then-read must use the newest overlay, got {repr ent.stores}"
  expect (ent.result? == some (.param 0))
    "entry result must observe the newest overlay value"

/-- Multiple fallible operations retain source order in the first-failure
    cascade; div-by-zero is totalized rather than blocking the action. -/
unsafe def testFirstFailureCascade : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program FailureOrder where\n" ++
    "  entry compute(x : UInt64, y : UInt64, divisor : UInt64) : UInt64 do\n" ++
    "    return (x - y) / divisor\n" ++
    "  entry ensure(x : UInt64) : UInt64 do\n" ++
    "    assert x > 0\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-failure-order>" "Tests.QuintFailureOrder" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "FailureOrder.qnt") |
    throw <| IO.userError "quint: missing FailureOrder.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains
      "val fail3 = if (not(ck0)) 2 else if (not(ck1)) 3 else 0")
    "underflow must precede div-by-zero in the exact first-failure cascade"
  expect (qnt.contains
      "if (pf_arg_a1_2 != 0) (pf_arg_a1_0 - pf_arg_a1_1) / pf_arg_a1_2 else 0")
    "division must be totalized on the failure path instead of blocking"
  expect (qnt.contains "val fail2 = if (not(ck0)) 4 else 0")
    "bare assert must emit exact failure code 4"

/-- Zero-payload declared revert is an explicit, identity-preserving outcome. -/
unsafe def testZeroPayloadDeclaredRevert : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Stopper where\n" ++
    "  error Stop()\n" ++
    "  entry stop() : UInt64 do\n" ++
    "    revert Stop\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-revert>" "Tests.QuintRevert" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "Stopper must retain its entry"
  expect ent.terminalRevert "declared revert must be explicit in the Plan"
  match ent.checks.back? with
  | some { kind := .terminalRevert errorIndex, condition := .litBool false } =>
      expect (errorIndex == 0) "declared revert must preserve canonical ErrorId 0"
  | other =>
      throw <| IO.userError s!"unexpected terminal-revert check: {repr other}"
  let forgedEnt := { ent with
    result? := some (.litU64 0)
    terminalRevert := false
  }
  let forged := { plan with entries := #[forgedEnt] }
  match Targets.Quint.validatePlan forged with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "terminal-revert marker")
        s!"terminal marker iff gate must reject forged Plan, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "terminal marker without terminalRevert must reject"
  match Targets.Quint.engineeringQuintPlanDigestV1 forged with
  | .error msg =>
      expect (msg.contains "terminal-revert marker")
        "Plan digest must enforce terminal marker iff"
  | .ok _ => throw <| IO.userError "forged terminal marker Plan must not receive a digest"
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "Stopper.qnt") |
    throw <| IO.userError "quint: missing Stopper.qnt"
  expect (qntFile.contents.contains "val fail2 = if (not(ck0)) 256 else 0")
    "ErrorId 0 revert must emit exact identity-preserving failure code 256"

/-- Fail closed: only zero-payload declared errors/reverts belong to Q0. -/
unsafe def testFailClosedRevertPayload : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StopPayload where\n" ++
    "  error Stop(code : UInt64)\n" ++
    "  entry stop(code : UInt64) : UInt64 do\n" ++
    "    revert Stop(code)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-revert-payload>" "Tests.QuintRevertPayload" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "zero payload" || msg.contains "payload")
        s!"nonzero revert payload must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "nonzero revert payload must fail closed"

/-- Full max bound spelling (exact 2^64−1, not truncated). -/
unsafe def testFullMaxBound : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Bound where\n" ++
    "  entry id(x : UInt64) : UInt64 do\n" ++
    "    return x + 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-bound>" "Tests.QuintBound" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "Bound.qnt") |
    throw <| IO.userError "quint: missing Bound.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "18446744073709551615")
    "PF_MAX_U64 must be the full 2^64-1 decimal"
  expect (qnt.contains "oneOf(0.to(PF_MAX_U64))")
    "domain must use full PF_MAX_U64, not a truncated i64 bound"
  expect (!qnt.contains "9223372036854775807")
    "must not emit i64 max as the UInt64 domain"

/-- Materialize path + determinism. -/
unsafe def testMaterializeDeterminism : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateCell where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-det>" "Tests.QuintDet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files1 ← liftResult <| buildQuint compiled
  let files2 ← liftResult <| buildQuint compiled
  expect (files1 == files2)
    "Quint materialize must be deterministic"
  let plan1 ← liftResult <| planQuint compiled
  let plan2 ← liftResult <| planQuint compiled
  expect (plan1 == plan2)
    "Quint plan lower must be deterministic"
  match Targets.Quint.engineeringQuintPlanDigestV1 plan1 with
  | .ok d1 =>
      match Targets.Quint.engineeringQuintPlanDigestV1 plan2 with
      | .ok d2 => expect (d1 == d2) "plan digest must be deterministic"
      | .error e => throw <| IO.userError e
  | .error e => throw <| IO.userError e

/-- Full registry/capability/materialize/finalize path for the shipped target. -/
unsafe def testCapabilityProductPath : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateCell where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-capability>" "Tests.QuintCapability" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.quint none
  expect (selection.codegenProfile == CodegenProfileId.quintSourceU64ModelV1)
    "Quint selection must bind its sole source profile"
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Quint.planFromCapability capability
  expect (plan.programName == "StateCell")
    "capability Plan must retain the compiled artifact name"
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.targetIdOf artifacts == TargetId.quint)
    "materialized artifacts must bind TargetId.quint"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.size == 1 && files[0]!.path == "StateCell.qnt")
    "registry materialize must emit exactly StateCell.qnt"
  let finalized ← Targets.finalizeMaterializedArtifactsV1
    capability artifacts (System.FilePath.mk ".")
  expect (!FinalizedArtifactsV1.deployableOf finalized)
    "Quint finalization must remain non-deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized).isEmpty
    "Quint zero-tool finalization must add no files"
  let note := FinalizedArtifactsV1.evidenceNoteOf finalized
  expect (note.contains "no Quint CLI" && note.contains "no parse")
    "Quint finalization evidence must state the exact zero-tool boundary"

/-- Fail closed: private state. -/
unsafe def testFailClosedPrivateState : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Priv where\n" ++
    "  state private secret : UInt64\n" ++
    "  init() do\n" ++
    "    secret := 0\n" ++
    "  entry get() : UInt64 do\n" ++
    "    return secret\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-priv>" "Tests.QuintPriv" none)
  -- Product compile may already reject private state depending on Normalize;
  -- either compile fail or Quint plan fail is acceptable for this negative.
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      match planQuint compiled with
      | .error (.planInvariant .quint msg) =>
          expect (msg.contains "public" || msg.contains "UInt64" ||
              msg.contains "private" || msg.contains "visibility")
            s!"private state must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
      | .ok _ => throw <| IO.userError "private state must fail closed at Quint plan"

/-- Homogeneous Int64: signed decimal domain + overflow range on unbounded int. -/
unsafe def testInt64Cell : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Int64Cell where\n" ++
    "  state count : Int64\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : Int64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-int64>" "Tests.QuintInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect plan.signedNumeric "Int64Cell Plan is signed"
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "Int64Cell.qnt") |
    throw <| IO.userError "quint: missing Int64Cell.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "PF_MIN_I64") "signed model must bind PF_MIN_I64"
  expect (qnt.contains "PF_MAX_I64") "signed model must bind PF_MAX_I64"
  expect (qnt.contains "-9223372036854775808") "PF_MIN_I64 is Int64 min"
  expect (qnt.contains "9223372036854775807") "PF_MAX_I64 is Int64 max"
  expect (qnt.contains "oneOf(PF_MIN_I64.to(PF_MAX_I64))")
    "Int64 param domain is the closed signed range"
  expect (!qnt.contains "oneOf(0.to(PF_MAX_U64))")
    "signed program must not use the UInt64 param domain"

/-- Mixing UInt64 and Int64 user-facing slots is fail closed. -/
unsafe def testMixedInt64UInt64Fc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MixInt64 where\n" ++
    "  state count : Int64\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-mix-int64>" "Tests.QuintMixInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "mixes")
        s!"mixed Int64/UInt64 must name mixes, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "mixed Int64/UInt64 must fail closed at Quint plan"

/-- Homogeneous Array UInt64 2 flatten: two Plan/`.qnt` var leaves, no List. -/
unsafe def testArraySlotsFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArraySlots where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-array-slots>" "Tests.QuintArraySlots" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect (!plan.signedNumeric) "ArraySlots stays unsigned"
  expect (plan.states.map (·.name) == #["slots_0", "slots_1"])
    "Array UInt64 2 must flatten to slots_0/slots_1 Plan leaves"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 2)
        "ArraySlots init must store both flattened leaves"
  | none => throw <| IO.userError "ArraySlots must have an initializer"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "ArraySlots.qnt") |
    throw <| IO.userError "quint: missing ArraySlots.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "var pf_state_slots_0")
    "ArraySlots.qnt must declare pf_state_slots_0"
  expect (qnt.contains "var pf_state_slots_1")
    "ArraySlots.qnt must declare pf_state_slots_1"
  expect (!qnt.contains "List[")
    "Array flatten must not emit a native Quint List"

/-- N=9 exceeds the 1..8 flatten cap. -/
unsafe def testArrayN9FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayNine where\n" ++
    "  state slots : Array UInt64 9\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-array-n9>" "Tests.QuintArrayNine" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "cap" || msg.contains "container")
        s!"Array UInt64 9 must cite cap/container, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Array UInt64 9 must fail closed at Quint plan"

/-- OptBox: Option UInt64 construct/store flattens to o_tag / o_p0. -/
unsafe def testOptBoxFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptBox where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(v)\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-opt-box>" "Tests.QuintOptBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect (!plan.signedNumeric) "OptBox stays unsigned"
  expect (plan.states.map (·.name) == #["o_tag", "o_p0"])
    "Option UInt64 must flatten to o_tag/o_p0 Plan leaves"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 2)
        "OptBox init must store both Option leaves"
  | none => throw <| IO.userError "OptBox must have an initializer"
  let some setSome := plan.entries[0]? |
    throw <| IO.userError "missing setSome entry"
  expect (setSome.stores.size == 2)
    "OptBox setSome must store both Option leaves"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "OptBox.qnt") |
    throw <| IO.userError "quint: missing OptBox.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "var pf_state_o_tag")
    "OptBox.qnt must declare pf_state_o_tag"
  expect (qnt.contains "var pf_state_o_p0")
    "OptBox.qnt must declare pf_state_o_p0"
  expect (!qnt.contains "List[")
    "Option flatten must not emit a native Quint List"

/-- Option Int64 payload stays fail closed. -/
unsafe def testOptionInt64PayloadFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptInt where\n" ++
    "  state o : Option Int64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-opt-int>" "Tests.QuintOptInt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "Option element must be UInt64")
        s!"Option Int64 must cite UInt64 payload, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Option Int64 must fail closed at Quint plan"

/-- Option Bool payload stays fail closed. -/
unsafe def testOptionBoolPayloadFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptBool where\n" ++
    "  state o : Option Bool\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setNone() : UInt64 do\n" ++
    "    o := Option.none()\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-opt-bool>" "Tests.QuintOptBool" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "Option element must be UInt64")
        s!"Option Bool must cite UInt64 payload, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Option Bool must fail closed at Quint plan"

/-- Option entry/view return stays outside Q0. -/
unsafe def testOptionReturnFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let retSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptRet where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry peek() : Option UInt64 do\n" ++
    "    return o\n"
  let parsedRet ← liftResult (← session.selectProgramV1
    retSource "<quint-opt-ret>" "Tests.QuintOptRet" none)
  let compiledRet ← liftResult <| Compiler.compileValidatedSourceV1 parsedRet
  match planQuint compiledRet with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "Option return is outside Q0")
        s!"Option entry return must cite outside Q0, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Option entry return must fail closed at Quint plan"
  let viewSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptView where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setNone() : UInt64 do\n" ++
    "    o := Option.none()\n" ++
    "    return 0\n" ++
    "  view peek() : Option UInt64 do\n" ++
    "    return o\n"
  let parsedView ← liftResult (← session.selectProgramV1
    viewSource "<quint-opt-view>" "Tests.QuintOptView" none)
  let compiledView ← liftResult <| Compiler.compileValidatedSourceV1 parsedView
  match planQuint compiledView with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "Option return is outside Q0")
        s!"Option view return must cite outside Q0, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Option view return must fail closed at Quint plan"

/-- signedNumeric Int64 programs cannot carry Option state. -/
unsafe def testSignedNumericOptionFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptSigned where\n" ++
    "  state n : Int64\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    n := 0\n" ++
    "    o := Option.none()\n" ++
    "  entry set(v : Int64) : Int64 do\n" ++
    "    n := v\n" ++
    "    return n\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-opt-signed>" "Tests.QuintOptSigned" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "signedNumeric" && msg.contains "Option")
        s!"signedNumeric+Option must cite both, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric+Option must fail closed at Quint plan"

/-- Map UInt64 UInt64 dense cap-8: 24 Plan leaves, empty + IndexSet. -/
unsafe def testMapMiniFlatten : IO Unit := do
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
    source "<quint-map-mini>" "Tests.QuintMapMini" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect (!plan.signedNumeric) "MapMini stays unsigned"
  expect (plan.states.size == 24)
    s!"Map UInt64 cap-8 must flatten to 24 leaves, got {plan.states.size}"
  expect (plan.states[0]!.name == "m_0" && plan.states[23]!.name == "m_23")
    "Map flatten leaf names must be m_0..m_23"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 24)
        "MapMini init must store all 24 Map leaves"
  | none => throw <| IO.userError "MapMini must have an initializer"
  expect (plan.entries.size == 1) "MapMini has one entry"
  expect (plan.entries[0]!.stores.size == 24)
    "MapMini put must store all 24 Map leaves"
  expect (plan.entries[0]!.checks.size ≥ 1)
    "MapMini put must check cap-8 overflow"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "MapMini.qnt") |
    throw <| IO.userError "quint: missing MapMini.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "var pf_state_m_0")
    "MapMini.qnt must declare pf_state_m_0"
  expect (qnt.contains "var pf_state_m_23")
    "MapMini.qnt must declare pf_state_m_23"
  expect (!qnt.contains "Map[")
    "Map flatten must not emit a native Quint Map"

/-- Map of Int64 stays fail closed. -/
unsafe def testMapInt64PayloadFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapInt where\n" ++
    "  state m : Map UInt64 Int64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-map-int>" "Tests.QuintMapInt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "Map state admits only Map UInt64 UInt64")
        s!"Map Int64 must cite Map UInt64 UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Map Int64 must fail closed at Quint plan"

/-- Map entry return stays outside Q0. -/
unsafe def testMapReturnFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapRet where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry peek() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-map-ret>" "Tests.QuintMapRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "Array/Map return is outside Q0")
        s!"Map return must cite outside Q0, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Map return must fail closed at Quint plan"

/-- signedNumeric Int64 programs cannot carry Map state. -/
unsafe def testSignedNumericMapFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MixMap where\n" ++
    "  state n : Int64\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    n := 0\n" ++
    "    m := Map.empty()\n" ++
    "  entry bump(d : Int64) : Int64 do\n" ++
    "    n := n + d\n" ++
    "    return n\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-signed-map>" "Tests.QuintMixMap" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "signedNumeric" && msg.contains "Map")
        s!"signedNumeric+Map must cite both, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric+Map must fail closed at Quint plan"

/-- Fail closed: Int32 (narrow signed; Int64 is the admitted width). -/
unsafe def testFailClosedInt32 : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program I32 where\n" ++
    "  entry id(x : Int32) : Int32 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-int32>" "Tests.QuintInt32" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "UInt64/Int64" || msg.contains "width")
        s!"Int32 must fail closed on the width needle, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "Int32 must fail closed at Quint plan"

/-- Fail closed: non-Q0 UInt widths are never silently widened to Quint int. -/
unsafe def testFailClosedUInt32 : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Narrow where\n" ++
    "  entry id(x : UInt32) : UInt32 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-u32>" "Tests.QuintUInt32" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "UInt64" || msg.contains "width" || msg.contains "parameter")
        s!"UInt32 must fail closed without widening, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "UInt32 must fail closed at Quint plan"

/-- Fail closed: multi-block if. -/
unsafe def testFailClosedMultiblock : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Branch where\n" ++
    "  entry pick(c : UInt64, a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    if c > 0 then\n" ++
    "      return a\n" ++
    "    else\n" ++
    "      return b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-if>" "Tests.QuintIf" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      match planQuint compiled with
      | .error (.planInvariant .quint msg) =>
          expect (msg.contains "one block" || msg.contains "multi" ||
              msg.contains "block" || msg.contains "outside Q0")
            s!"multi-block must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
      | .ok _ => throw <| IO.userError "multi-block if must fail closed at Quint plan"

/-- Fail closed: constants are not silently substituted by a second evaluator. -/
unsafe def testFailClosedConstant : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ConstUse where\n" ++
    "  const base : UInt64 := 1\n" ++
    "  entry get() : UInt64 do\n" ++
    "    return base\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-const>" "Tests.QuintConst" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "constants" || msg.contains "constant")
        s!"nonempty constants must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "nonempty constants must fail closed at Quint plan"

/-- SYS-S4: Quint has no unixTime/blockHeight/attachedValue/chainId host.
    Named UInt64 ContextRead keys stay Plan fail closed. caller/self are
    Principal and stay on the generic outside-Q0 envelope (Q0 results are
    not Principal; no caller/self host). -/
unsafe def testFailClosedContextReadAttachedValue : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanFc (label place schemaId : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++
      "  state public pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry collect() : UInt64 do\n" ++
      s!"    return {place}\n"
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<quint-{label}>" s!"Examples.{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    let needle := "has no Quint host binding"
    match planQuint compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        expect (e.render.contains s!"ContextRead '{schemaId}'")
          s!"{label} Plan FC must name ContextRead '{schemaId}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Quint context host)"
    match buildQuint compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} materialize FC must contain '{needle}', got: {e.render}"
        expect (e.render.contains s!"ContextRead '{schemaId}'")
          s!"{label} materialize FC must name ContextRead '{schemaId}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must fail closed at Quint materialize"
  expectPlanFc "CtxUnixTime" "context.unixTimeSeconds"
    "proof-forge.context.unix-time-seconds.v1"
  expectPlanFc "CtxBlockHeight" "context.blockHeight"
    "proof-forge.context.block-height.v1"
  expectPlanFc "CtxAttached" "context.attachedValue"
    "proof-forge.context.attached-value.v1"
  expectPlanFc "CtxChainId" "context.chainId"
    "proof-forge.context.chain-id.v1"

/-- Fail closed: events. -/
unsafe def testFailClosedEvent : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Ev where\n" ++
    "  event Ticked(v : UInt64)\n" ++
    "  entry tick(x : UInt64) : UInt64 do\n" ++
    "    emit Ticked(x)\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-ev>" "Tests.QuintEv" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      let selection ← liftResult <|
        Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.quint none
      match Targets.resolveEngineeringRequirementsV1 selection compiled with
      | .error (.unsupportedRequirementV1 msg) =>
          expect (msg.contains "effect.event")
            s!"event resolver failure must name effect.event, got: {msg}"
      | .error e =>
          throw <| IO.userError s!"expected unsupportedRequirementV1, got {e.render}"
      | .ok _ => throw <| IO.userError "event must fail at Quint capability resolution"
      match planQuint compiled with
      | .error (.planInvariant .quint msg) =>
          expect (msg.contains "event" || msg.contains "events" ||
              msg.contains "outside Q0" || msg.contains "empty")
            s!"event must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
      | .ok _ => throw <| IO.userError "event must fail closed at Quint plan"

/-- Fail closed: unreachable pureFns are still validated, so unsupported dead
    code cannot disappear from the target model. -/
unsafe def testFailClosedUnusedPureFn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program DeadFn where\n" ++
    "  fn dead(x : UInt64) : UInt64 do\n" ++
    "    return x & 1\n" ++
    "  entry id(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-dead-fn>" "Tests.QuintDeadFn" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "bitwise" || msg.contains "outside Q0")
        s!"unused unsupported pureFn must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "unused unsupported pureFn must not be erased"

private def guardedExpansionSource (programName op : String) : String := Id.run do
  let mut source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    s!"program {programName} where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 1\n" ++
    "  entry explode() : UInt64 do\n"
  for _ in [0:14] do
    source := source ++ s!"    count := 1 {op} count\n"
  pure (source ++ "    return count\n")

private unsafe def expectGuardedExpansionRejected
    (session : Language.Loader.ParserSession)
    (label programName op : String) : IO Unit := do
  let parsed ← liftResult (← session.selectProgramV1
    (guardedExpansionSource programName op)
    s!"<quint-expand-{label}>" s!"Tests.QuintExpand{programName}" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "expanded expression" && msg.contains "nodes")
        s!"{label} totalization expansion must fail before rendering, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label} totalization expansion must fail closed"

/-- Fail closed before rendering: a linear CFG that repeatedly duplicates an
    SSA/state expression must not create exponentially large Quint source. -/
unsafe def testExpandedExpressionBudget : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Expand where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 1\n" ++
    "  entry explode() : UInt64 do\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    count := count + count\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-expand>" "Tests.QuintExpand" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "expanded expression" && msg.contains "nodes")
        s!"expanded expression must fail with a bounded target error, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "exponential expression expansion must fail closed"
  expectGuardedExpansionRejected session "division" "ExpandDiv" "/"
  expectGuardedExpansionRejected session "modulo" "ExpandMod" "%"

/-- Check instrumentation has its own bound so the generated success/failure
    cascades cannot exceed the renderer recursion envelope. -/
unsafe def testCheckCascadeBudget : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := Id.run do
    let mut text :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      "program CheckBudget where\n" ++
      "  entry guard(x : UInt64) : UInt64 do\n"
    for _ in [0:129] do
      text := text ++ "    assert x >= 0\n"
    pure (text ++ "    return x\n")
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-check-budget>" "Tests.QuintCheckBudget" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "check count" && msg.contains "128")
        s!"check cascade must fail at the target bound, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "129 checks must fail before IR rendering"

/-- Plan canonicity: non-Unit/no-result is legal only for an explicitly
    recorded terminal revert with its canonical final false check. -/
unsafe def testPlanRejectsForgedMissingResult : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ResultGate where\n" ++
    "  entry id(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-result-gate>" "Tests.QuintResultGate" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "ResultGate must retain its entry"
  let forged := { plan with entries := #[{ ent with result? := none }] }
  match Targets.Quint.validatePlan forged with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "missing" && msg.contains "terminal revert")
        s!"forged missing result must fail canonically, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "forged non-Unit/no-result Plan must be rejected"
  match Targets.Quint.engineeringQuintPlanDigestV1 forged with
  | .error msg =>
      expect (msg.contains "missing" && msg.contains "terminal revert")
        "Plan digest must bind the same canonicity gate"
  | .ok _ => throw <| IO.userError "forged Plan must not receive an engineering digest"
  let wrongType := { plan with entries := #[{ ent with result? := some (.litBool true) }] }
  match Targets.Quint.validatePlan wrongType with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "type" && msg.contains "use site")
        s!"forged result type must fail Plan validation, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
  | .ok _ => throw <| IO.userError "forged result type must be rejected"
  let badRef := { plan with entries := #[{ ent with result? := some (.param 1) }] }
  match Targets.Quint.engineeringQuintPlanDigestV1 badRef with
  | .error msg =>
      expect (msg.contains "unknown parameter 1")
        "Plan digest must reject out-of-range expression references"
  | .ok _ => throw <| IO.userError "out-of-range Plan reference must not receive a digest"

/-- Bool body + pureFn inline + zero-param Bool invariant. -/
unsafe def testBoolPureFnInvariant : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Logic where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  fn isPositive(x : UInt64) : Bool do\n" ++
    "    return x > 0\n" ++
    "  entry check(delta : UInt64) : Bool do\n" ++
    "    return isPositive(delta) && count >= 0\n" ++
    "  invariant nonNeg : count >= 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-logic>" "Tests.QuintLogic" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect (plan.invariants.map (·.name) == #["nonNeg"])
    "invariant must lower"
  expect (plan.entries.size == 1)
    "single entry"
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "Logic.qnt") |
    throw <| IO.userError "quint: missing Logic.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "val pf_invariant_nonNeg =")
    "invariant must emit under the target-owned invariant namespace"
  expect (!qnt.contains "val pf_invariant_nonNeg = pf_last_")
    "invariant must not reference instrumentation"
  expect (qnt.contains "and" || qnt.contains ">")
    "Bool body / pureFn inline must appear in step or val"

/-- ADR-0029 frozen pf.assets extension digest. -/
private def pfAssetsDigestV1 : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

private def pfAssetsRequiresBlock : String :=
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"" ++ pfAssetsDigestV1 ++ "\"\n"

/-- A5: native deposit/transfer lower to vault + nondet outcome + stutter. -/
unsafe def testPfAssetsVaultDepositTransfer : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Tip where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.deposit(amount)\n" ++
    "    call pf.assets.native.transfer(dst, amount)\n" ++
    "    count := count + amount\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-pf-assets-tip>" "Tests.QuintPfAssetsTip" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect plan.usesVaultNative "Tip must enable vaultNative"
  let some tip := plan.entries[0]? |
    throw <| IO.userError "Tip must have tip entry"
  expect (tip.assetOps.size == 2) "tip: deposit + transfer asset ops"
  expect (tip.paramIsPrincipal == #[true, false])
    "tip: Principal then UInt64 params"
  -- Checks: ext0, vaultOverflow, ext1, vaultUnderflow, arith overflow (count+amount)
  expect (tip.checks.size >= 4)
    "tip: at least external+vault checks for two ops"
  let kinds := tip.checks.map (·.kind)
  expect (kinds.contains .externalCallFailed)
    "tip: externalCallFailed checks present"
  expect (kinds.contains .vaultOverflow)
    "tip: vaultOverflow check for deposit"
  expect (kinds.contains .vaultUnderflow)
    "tip: vaultUnderflow check for transfer"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "Tip.qnt") |
    throw <| IO.userError "quint: missing Tip.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "var pf_vault_native: int")
    "Tip.qnt must declare pf_vault_native"
  expect (qnt.contains "nondet pf_ext_ok_a1_0 = oneOf(0.to(1))")
    "deposit outcome nondet"
  expect (qnt.contains "nondet pf_ext_ok_a1_1 = oneOf(0.to(1))")
    "transfer outcome nondet"
  expect (qnt.contains "pf_vault_native' = if (ok")
    "vault assignment is success-gated (stutter on failure)"
  expect (qnt.contains "pf_ext_ok_a1_0 == 1" || qnt.contains "pf_ext_ok_a1_0 ==1")
    "externalOk lowers to == 1"
  -- Failure code 5 for external, 6 vault overflow, 7 vault underflow appear.
  expect (qnt.contains ") 5 else" || qnt.contains ") 5 else 0" ||
      qnt.contains " 5 else")
    "externalCallFailed code 5 in first-failure cascade"
  expect (qnt.contains " 6 else" || qnt.contains ") 6 else")
    "vaultOverflow code 6"
  expect (qnt.contains " 7 else" || qnt.contains ") 7 else")
    "vaultUnderflow code 7"

/-- A5: pf.assets catalog QN without extension declaration fail closed. -/
unsafe def testPfAssetsRequiresDeclaration : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NoExt where\n" ++
    "  entry transfer(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.transfer(dst, amount)\n" ++
    "    return amount\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-pf-assets-noext>" "Tests.QuintPfAssetsNoExt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "extension.pf-assets" || msg.contains "pf.assets catalog")
        s!"no-declaration must cite extension gate, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "pf.assets without extension must fail closed"

/-- A5: non-catalog QN (Oracle.feed) resolves sync-call but Plan FC. -/
unsafe def testNonCatalogExternalCallFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OracleCall where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(x)\n" ++
    "    count := count + x\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-oracle>" "Tests.QuintOracle" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  -- Resolver admits effect.synchronous-call on Quint (A5).
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.quint none
  let cap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf cap == TargetId.quint)
    "Oracle.feed resolves on Quint via sync-call"
  match Targets.Quint.planFromCapability cap with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "not a Quint-admitted pf.assets" ||
          msg.contains "externalCall")
        s!"non-catalog must fail at Plan, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "Oracle.feed must fail closed at Quint Plan"

/-- Value-position Oracle.feed is a distinct Q0 gate from the void statement
    pin above. Resolver still admits effect.synchronous-call (A5); Plan
    rejects the result-bearing form by name. -/
unsafe def testResultBearingExternalCallFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OracleCallRet where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    let y : UInt64 := call Oracle.feed(x)\n" ++
    "    count := count + x\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-oracle-ret>" "Tests.QuintOracleRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.quint none
  let cap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf cap == TargetId.quint)
    "result-bearing Oracle.feed resolves on Quint via sync-call"
  match Targets.Quint.planFromCapability cap with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "result-bearing externalCall is outside Q0")
        s!"result-bearing must fail at the named Q0 gate, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "result-bearing Oracle.feed must fail closed at Quint Plan"
  IO.println "QUINT-CALL-RET-FC: result-bearing Oracle.feed Plan FC ok"

/-- SYS-S5: Quint has no sha256 host. Exact `pf.crypto.*` stays Plan fail
    closed instead of the generic pf.assets catch-all. -/
unsafe def testCryptoSha256StayFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanFc (label body needle : String)
      (also : String := "") : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<quint-{label}>" s!"Tests.Quint{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match Targets.Quint.planFromCompiledSemanticV1 compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{label} Plan FC must contain '{also}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Quint crypto host)"
  expectPlanFc "Sha256Quint"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    call pf.crypto.sha256(w)\n" ++
      "    return pad\n")
    "has no Quint host binding"
  expectPlanFc "Sha256QuintHashNoPad"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.hashNoPad(w)\n" ++
      "    return pad\n")
    "has no Quint host binding"
  expectPlanFc "Keccak256Quint"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    call pf.crypto.keccak256(w)\n" ++
      "    return pad\n")
    "has no Quint host binding"
  expectPlanFc "EcdsaRecoverQuint"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.ecdsaRecoverSecp256k1(w)\n" ++
      "    return pad\n")
    "has no Quint host binding" "ecdsaRecoverSecp256k1"

/-- A5: async / token pf.assets QNs fail closed (no fake modeling). -/
unsafe def testPfAssetsAsyncAndTokenFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let asyncSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program AsyncXfer where\n" ++
    pfAssetsRequiresBlock ++
    "  entry go(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.transferAsync(dst, amount)\n" ++
    "    return amount\n"
  let parsedA ← liftResult (← session.selectProgramV1
    asyncSrc "<quint-async>" "Tests.QuintAsync" none)
  let compiledA ← liftResult <| Compiler.compileValidatedSourceV1 parsedA
  match planQuint compiledA with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "transferAsync" || msg.contains "async/token")
        s!"async must cite Phase A scope, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant async, got {e.render}"
  | .ok _ => throw <| IO.userError "transferAsync must fail closed"
  let tokenSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program TokenXfer where\n" ++
    pfAssetsRequiresBlock ++
    "  entry go(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.token.transfer(mint, dst, amount)\n" ++
    "    return amount\n"
  let parsedT ← liftResult (← session.selectProgramV1
    tokenSrc "<quint-token>" "Tests.QuintToken" none)
  let compiledT ← liftResult <| Compiler.compileValidatedSourceV1 parsedT
  match planQuint compiledT with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "token" || msg.contains "async/token")
        s!"token must cite Phase A scope, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant token, got {e.render}"
  | .ok _ => throw <| IO.userError "token.transfer must fail closed"

/-- A5: dual extension declaration (solana.cpi + pf.assets) → Quint resolve FC
    on the Solana CPI row; pf.assets + S2 keys alone still coexist. -/
unsafe def testDualExtensionResolveFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let solanaDigest :=
    ProofForgeV2.Core.RequirementIdsV1.solanaCpiAccountsExtensionDigestV1
  let dualSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program DualExt where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"" ++ solanaDigest ++ "\"\n" ++
    pfAssetsRequiresBlock ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    dualSource "<quint-dual>" "Tests.QuintDual" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.quint none
  let semantic := CompiledSemanticV1.semanticV1Of compiled
  let frozen ← match Semantic.WireV1.validateSemanticProgramV1 semantic with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"dual validate: {repr e}"
  expect (frozen.items.any (·.id == "extension.solana-cpi-accounts"))
    "dual freeze carries solana CPI extension"
  expect (frozen.items.any (·.id == "extension.pf-assets"))
    "dual freeze carries pf.assets extension"
  match Targets.resolveEngineeringRequirementsV1 selection compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        "dual solana+pf.assets must PF-REQ-UNSUPPORTED on Quint"
  | .ok _ =>
      throw <| IO.userError "dual solana extension must not resolve on Quint"
  -- Coexistence: pf.assets alone with no call site still resolves.
  let onlyPf :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OnlyPf where\n" ++
    pfAssetsRequiresBlock ++
    "  entry run() : UInt64 do\n" ++
    "    return 0\n"
  let parsed2 ← liftResult (← session.selectProgramV1
    onlyPf "<quint-only-pf>" "Tests.QuintOnlyPf" none)
  let compiled2 ← liftResult <| Compiler.compileValidatedSourceV1 parsed2
  let cap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled2
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf cap == TargetId.quint)
    "pf.assets alone still resolves (S2 + extension coexistence)"

/-- ADR-0030 E2-Quint: native balanceOfSelf lowers to vaultNative in a view;
    usesVaultNative is true; emitted .qnt reads pf_vault_native. -/
unsafe def testEnvReadNativeBalanceOfSelf : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EnvReadTip where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.deposit(amount)\n" ++
    "    call pf.assets.native.transfer(dst, amount)\n" ++
    "    count := count + amount\n" ++
    "    return count\n" ++
    "  view nativeBalance() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-envread-native>" "Tests.QuintEnvReadNative" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect plan.usesVaultNative "EnvReadTip must enable vaultNative"
  let some balView := plan.views.find? (·.name == "nativeBalance") |
    throw <| IO.userError "nativeBalance view must exist"
  expect (balView.value == .vaultNative)
    "nativeBalance view value must be vaultNative"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "EnvReadTip.qnt") |
    throw <| IO.userError "quint: missing EnvReadTip.qnt"
  let qnt := qntFile.contents
  expect (qnt.contains "var pf_vault_native: int")
    "EnvReadTip.qnt must declare pf_vault_native"
  expect (qnt.contains "pf_vault_native")
    "view body must reference pf_vault_native"

/-- E2-Quint: env-read-only program (no deposit/transfer) still emits vault. -/
unsafe def testEnvReadOnlyEnablesVault : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EnvOnly where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    count := count + x\n" ++
    "    return count\n" ++
    "  view nativeBalance() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-envread-only>" "Tests.QuintEnvReadOnly" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect plan.usesVaultNative
    "env-read-only program must still set usesVaultNative"
  expect (plan.entries.all (·.assetOps.isEmpty))
    "env-read-only: no asset ops on entries"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (·.path == "EnvOnly.qnt") |
    throw <| IO.userError "quint: missing EnvOnly.qnt"
  expect (qntFile.contents.contains "var pf_vault_native: int")
    "env-read-only .qnt must declare pf_vault_native (init to 0)"

/-- E2-Quint: token balanceOfSelf permanently fail closed with Q0 Map diagnosis.
    Uses an entry (views reject Principal params at the Q0 surface gate). -/
unsafe def testEnvReadTokenBalanceFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program TokenBal where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry tokenBalance(mint : Principal) : UInt64 do\n" ++
    "    return pf.assets.token.balanceOfSelf(mint)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-envread-token>" "Tests.QuintEnvReadToken" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planQuint compiled with
  | .error (.planInvariant .quint msg) =>
      expect (msg.contains "permanently fail closed" &&
          (msg.contains "token" || msg.contains "Map" || msg.contains "Q0"))
        s!"token balanceOfSelf must cite permanent FC + Q0 Map reason, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "token.balanceOfSelf must fail closed on Quint"

/-- QUINT-1a: grammar-valid but unregistered profile stays unknown.
    Do not invent a Quint ITF/MBT/verify CodegenProfileId. -/
unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match Targets.BuildSelectionV1.resolveBuildSelectionV1
          TargetId.quint (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown Quint profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown Quint profile must fail closed, got {sel.codegenProfile}"

unsafe def run : IO Unit := do
  testStateCellQuintSource
  testRollbackStutter
  testInitializerDefaultZero
  testSequentialStateOverlay
  testFirstFailureCascade
  testZeroPayloadDeclaredRevert
  testFailClosedRevertPayload
  testFullMaxBound
  testMaterializeDeterminism
  testCapabilityProductPath
  testUnknownProfileFailClosed
  testFailClosedPrivateState
  testInt64Cell
  testMixedInt64UInt64Fc
  testArraySlotsFlatten
  testArrayN9FailClosed
  testOptBoxFlatten
  testOptionInt64PayloadFc
  testOptionBoolPayloadFc
  testOptionReturnFc
  testSignedNumericOptionFc
  testMapMiniFlatten
  testMapInt64PayloadFc
  testMapReturnFc
  testSignedNumericMapFc
  testFailClosedInt32
  testFailClosedUInt32
  testFailClosedMultiblock
  testFailClosedConstant
  testFailClosedContextReadAttachedValue
  testFailClosedEvent
  testFailClosedUnusedPureFn
  testExpandedExpressionBudget
  testCheckCascadeBudget
  testPlanRejectsForgedMissingResult
  testBoolPureFnInvariant
  testPfAssetsVaultDepositTransfer
  testPfAssetsRequiresDeclaration
  testNonCatalogExternalCallFailClosed
  testResultBearingExternalCallFailClosed
  testCryptoSha256StayFailClosed
  testPfAssetsAsyncAndTokenFailClosed
  testDualExtensionResolveFailClosed
  testEnvReadNativeBalanceOfSelf
  testEnvReadOnlyEnablesVault
  testEnvReadTokenBalanceFailClosed
  IO.println "Tests.Materialization.QuintSourceV1: ok"

end Tests.Materialization.QuintSourceV1
