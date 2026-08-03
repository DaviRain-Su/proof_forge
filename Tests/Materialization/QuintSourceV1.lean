/-
  Quint target leaf tests (Q0): Plan/IR/emitter over retained SemanticProgramV1.
  Uses planFromCompiledSemanticV1 / buildFromCompiledSemanticV1 so the suite
  does not require registry wiring. Main agent registers this suite.
-/
import ProofForgeV2
import ProofForgeV2.Targets.Quint
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

/-- Counter: plan shape + key Quint source fragments. -/
unsafe def testCounterQuintSource : IO Unit := do
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
    source "<quint-counter>" "Tests.QuintCounter" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planQuint compiled
  expect (plan.states.map (·.name) == #["count"])
    "Counter Quint plan must carry the count state field"
  expect (plan.entries.map (·.name) == #["increment"])
    "Counter Quint plan must carry the increment entry"
  expect (plan.views.map (·.name) == #["get"])
    "Counter Quint plan must carry the get view"
  match plan.initializer with
  | some initFn =>
      expect (initFn.params == #["initial"])
        "Counter init must carry the initial parameter"
      expect (initFn.stores.size == 1)
        "Counter init must store count"
  | none => throw <| IO.userError "Counter must have an initializer"
  let some inc := plan.entries[0]? |
    throw <| IO.userError "missing increment entry"
  let overflowOk :=
    match inc.checks[0]? with
    | some ck => inc.checks.size == 1 && ck.kind == .overflow
    | none => false
  expect overflowOk "increment must carry a single overflow check"
  liftResult <| Targets.Quint.validatePlan plan
  let files ← liftResult <| buildQuint compiled
  let some qntFile := files.find? (fun f => f.path == "Counter.qnt") |
    throw <| IO.userError "quint: missing Counter.qnt"
  expect (qntFile.mediaType == "text/x-quint")
    "Counter.qnt media type must be text/x-quint"
  let qnt := qntFile.contents
  expect (qnt.contains "module PFModel_Counter {")
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
    "program Counter where\n" ++
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
  let some qntFile := files.find? (·.path == "Counter.qnt") |
    throw <| IO.userError "quint: missing Counter.qnt"
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
    "program Counter where\n" ++
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
  expect (plan.programName == "Counter")
    "capability Plan must retain the compiled artifact name"
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.targetIdOf artifacts == TargetId.quint)
    "materialized artifacts must bind TargetId.quint"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.size == 1 && files[0]!.path == "Counter.qnt")
    "registry materialize must emit exactly Counter.qnt"
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

/-- Fail closed: Int64. -/
unsafe def testFailClosedInt : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program I where\n" ++
    "  entry neg(x : Int64) : Int64 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<quint-int>" "Tests.QuintInt" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      match planQuint compiled with
      | .error (.planInvariant .quint msg) =>
          expect (msg.contains "Int" || msg.contains "width" ||
              msg.contains "UInt64" || msg.contains "parameter")
            s!"Int must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .quint, got {e.render}"
      | .ok _ => throw <| IO.userError "Int must fail closed at Quint plan"

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

unsafe def run : IO Unit := do
  testCounterQuintSource
  testRollbackStutter
  testInitializerDefaultZero
  testSequentialStateOverlay
  testFirstFailureCascade
  testZeroPayloadDeclaredRevert
  testFailClosedRevertPayload
  testFullMaxBound
  testMaterializeDeterminism
  testCapabilityProductPath
  testFailClosedPrivateState
  testFailClosedInt
  testFailClosedUInt32
  testFailClosedMultiblock
  testFailClosedConstant
  testFailClosedEvent
  testFailClosedUnusedPureFn
  testExpandedExpressionBudget
  testCheckCascadeBudget
  testPlanRejectsForgedMissingResult
  testBoolPureFnInvariant
  IO.println "Tests.Materialization.QuintSourceV1: ok"

end Tests.Materialization.QuintSourceV1
