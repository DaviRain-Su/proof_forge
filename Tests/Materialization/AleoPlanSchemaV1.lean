/-
  ALEO-I1 engineering Aleo Plan schema/digest suite.

  Covers:
  * domain pin `pf.aleo-plan.engineering.v1`
  * deterministic encode/digest on hand-built minimal Plan
  * StateCell product-path identity (digest recompute + two mints)
  * field / expr / stmt / view mutation non-aliasing
  * invalid Plan encode fail closed (validatePlan gate)

  **Not** formal Plan identity / OutputSetV1 / Aleo runtime.
-/
import ProofForgeV2
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Aleo
import ProofForgeV2.Targets.Aleo.PlanSchemaV1
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.AleoPlanSchemaV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Aleo

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def liftExcept (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def digestWire (d : Digest) : IO String :=
  liftExcept "renderDigest" (renderDigest d)

private def expectDigestDiff (label : String) (base alt : Digest) : IO Unit :=
  expect (!(base.bytes == alt.bytes)) s!"{label}: digest must change"

/-- Minimal valid Aleo Plan (initialize + bare view). -/
private def minimalPlan : Plan := {
  programName := "Mut"
  stateFieldNames := #["count"]
  stateFieldIsInt := #[false]
  stateFieldUintWidth := #[0]
  stateFieldIsField := #[false]
  functions := #[{
    index := 0
    name := "init"
    kind := .initialize
    params := #[{ sourceIndex := 0, name := "initial", isBool := false }]
    body := #[.store 0 (.param 0)]
    touchesState := true
    resultIsBool := false
    resultDropped := false
  }]
  views := #[{ name := "get", stateFieldIndex := 0 }]
  sourceHash := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  semanticHash := "sha256:1111111111111111111111111111111111111111111111111111111111111111"
}

private unsafe def compileStateCell : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load StateCell" (← session.selectProgramV1
    Examples.stateCellSourceText "<aleo-plan-schema-stateCell>"
    Examples.stateCellModuleNameV1 none)
  liftResult "compile StateCell" (Compiler.compileValidatedSourceV1 source)

private unsafe def planStateCell : IO Plan := do
  let compiled ← compileStateCell
  let selection ← liftResult "select aleo" (resolveBuildSelectionV1 TargetId.aleo none)
  let capability ← liftResult "resolve"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  liftResult "plan" (planFromCapability capability)

private def testDomain : IO Unit := do
  expect (engineeringAleoPlanDomainV1 == "pf.aleo-plan.engineering.v1") "domain"
  expect (engineeringAleoPlanDomainV1.endsWith ".engineering.v1") "suffix"

private def testMinimalPlanDeterminism : IO Unit := do
  match validatePlan minimalPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"minimal plan: {e.render}"
  let b1 ← liftExcept "e1" (encodeEngineeringAleoPlanBytesV1 minimalPlan)
  let b2 ← liftExcept "e2" (encodeEngineeringAleoPlanBytesV1 minimalPlan)
  expect (b1 == b2) "encode determinism"
  expect (b1.size > 0) "nonempty"
  let d1 ← liftExcept "d1" (engineeringAleoPlanDigestV1 minimalPlan)
  let d2 ← liftExcept "d2" (engineeringAleoPlanDigestV1 minimalPlan)
  expect (d1.algorithm == .sha256 && d1.bytes.size == 32) "sha256"
  expect (d1.bytes == d2.bytes) "digest determinism"
  let w ← digestWire d1
  expect (w.startsWith "sha256:") "wire prefix"

private def testTamperMatrix : IO Unit := do
  let base ← liftExcept "base" (engineeringAleoPlanDigestV1 minimalPlan)
  expectDigestDiff "programName" base
    (← liftExcept "n" (engineeringAleoPlanDigestV1 { minimalPlan with programName := "MutX" }))
  expectDigestDiff "state name" base
    (← liftExcept "s" (engineeringAleoPlanDigestV1 {
      minimalPlan with stateFieldNames := #["total"] }))
  expectDigestDiff "state isInt" base
    (← liftExcept "si" (engineeringAleoPlanDigestV1 {
      minimalPlan with stateFieldIsInt := #[true] }))
  expectDigestDiff "state uint width" base
    (← liftExcept "sw" (engineeringAleoPlanDigestV1 {
      minimalPlan with stateFieldUintWidth := #[32] }))
  expectDigestDiff "state isField" base
    (← liftExcept "sf" (engineeringAleoPlanDigestV1 {
      minimalPlan with stateFieldIsField := #[true] }))
  expectDigestDiff "sourceHash" base
    (← liftExcept "sh" (engineeringAleoPlanDigestV1 {
      minimalPlan with sourceHash :=
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }))
  expectDigestDiff "semanticHash" base
    (← liftExcept "mh" (engineeringAleoPlanDigestV1 {
      minimalPlan with semanticHash :=
        "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }))
  -- View mutation
  expectDigestDiff "view name" base
    (← liftExcept "vn" (engineeringAleoPlanDigestV1 {
      minimalPlan with views := #[{ name := "read", stateFieldIndex := 0 }] }))
  expectDigestDiff "view field index" base
    (← liftExcept "vi" (engineeringAleoPlanDigestV1 {
      minimalPlan with
        stateFieldNames := #["count", "other"]
        stateFieldIsInt := #[false, false]
        stateFieldUintWidth := #[0, 0]
        stateFieldIsField := #[false, false]
        views := #[{ name := "get", stateFieldIndex := 1 }] }))
  -- Function / param / kind
  expectDigestDiff "fn name" base
    (← liftExcept "fn" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with name := "setup" }] }))
  expectDigestDiff "fn kind" base
    (← liftExcept "fk" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with kind := .mutate, resultDropped := true }] }))
  expectDigestDiff "param name" base
    (← liftExcept "pn" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with params := #[{
          sourceIndex := 0, name := "seed", isBool := false }] }] }))
  expectDigestDiff "param isBool" base
    (← liftExcept "pb" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with
          params := #[{ sourceIndex := 0, name := "flag", isBool := true }]
          body := #[.store 0 (.boolLiteral true)] }] }))
  -- Expr mutations inside body
  expectDigestDiff "store literal" base
    (← liftExcept "el" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with body := #[.store 0 (.literal 7)] }] }))
  expectDigestDiff "checkedAdd" base
    (← liftExcept "ea" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with
          body := #[.store 0 (.checkedAdd (.param 0) (.literal 1))] }] }))
  expectDigestDiff "compare" base
    (← liftExcept "ec" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with
          body := #[
            .assert (.compare .gt (.param 0) (.literal 0)),
            .store 0 (.param 0)] }] }))
  -- Statement shape mutations
  expectDigestDiff "ifThenElse" base
    (← liftExcept "st" (engineeringAleoPlanDigestV1 {
      minimalPlan with functions := #[{
        minimalPlan.functions[0]! with
          body := #[
            .ifThenElse (.compare .eq (.param 0) (.literal 0))
              #[.store 0 (.literal 1)]
              #[.store 0 (.param 0)]] }] }))
  let purePlan : Plan := {
    programName := "Pure"
    stateFieldNames := #[]
    stateFieldIsInt := #[]
    stateFieldUintWidth := #[]
    stateFieldIsField := #[]
    functions := #[{
      index := 0
      name := "pureish"
      kind := .mutate
      params := #[]
      body := #[.returnValue (.literal 1)]
      touchesState := false
      resultIsBool := false
      resultDropped := false
    }]
    views := #[]
    sourceHash := minimalPlan.sourceHash
    semanticHash := minimalPlan.semanticHash
  }
  expectDigestDiff "returnValue" base
    (← liftExcept "rv" (engineeringAleoPlanDigestV1 purePlan))

private def testInvalidPlanEncodeFails : IO Unit := do
  -- resultDropped on pure (non-state-touching) function.
  let badDrop : Plan := {
    programName := "Tiny"
    stateFieldNames := #["count"]
    stateFieldIsInt := #[false]
    stateFieldUintWidth := #[0]
    stateFieldIsField := #[false]
    functions := #[{
      index := 0
      name := "pureish"
      kind := .mutate
      params := #[]
      body := #[.returnValue (.literal 1)]
      touchesState := false
      resultIsBool := false
      resultDropped := true
    }]
    views := #[]
    sourceHash := minimalPlan.sourceHash
    semanticHash := minimalPlan.semanticHash
  }
  match encodeEngineeringAleoPlanBytesV1 badDrop with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "encode must reject resultDropped on pure fn"
  -- State signedness table length mismatch.
  let badState : Plan := {
    minimalPlan with stateFieldIsInt := #[]
  }
  match encodeEngineeringAleoPlanBytesV1 badState with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "encode must reject state table length mismatch"

private unsafe def testProductPathRecompute : IO Unit := do
  let plan ← planStateCell
  expect (plan.programName == "StateCell") "StateCell name"
  let d1 ← liftExcept "d1" (engineeringAleoPlanDigestV1 plan)
  let bytes ← liftExcept "enc" (encodeEngineeringAleoPlanBytesV1 plan)
  let recomputed ← liftExcept "dom"
    (domainSeparatedSha256 engineeringAleoPlanDomainV1 bytes)
  expect (d1.bytes == recomputed.bytes) "recompute"
  let plan2 ← planStateCell
  let d2 ← liftExcept "d2" (engineeringAleoPlanDigestV1 plan2)
  expect (d1.bytes == d2.bytes) "two mints"
  let b1 ← liftExcept "b1" (encodeEngineeringAleoPlanBytesV1 plan)
  let b2 ← liftExcept "b2" (encodeEngineeringAleoPlanBytesV1 plan2)
  expect (b1 == b2) "bytes equal"
  -- Distinct from minimal hand-built plan.
  let dMin ← liftExcept "min" (engineeringAleoPlanDigestV1 minimalPlan)
  expectDigestDiff "StateCell≠minimal" d1 dMin

private def testWirePresence : IO Unit := do
  let schema ← IO.Process.output {
    cmd := "rg"
    args := #["-n",
      "^def encodeEngineeringAleoPlanBytesV1\\b|^def engineeringAleoPlanDigestV1\\b|^def engineeringAleoPlanDomainV1\\b",
      "ProofForgeV2/Targets/Aleo/PlanSchemaV1.lean"]
  }
  expect (schema.exitCode == 0 &&
      schema.stdout.contains "encodeEngineeringAleoPlanBytesV1" &&
      schema.stdout.contains "engineeringAleoPlanDigestV1" &&
      schema.stdout.contains "engineeringAleoPlanDomainV1")
    s!"schema surface: {schema.stdout}"
  let reg ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "engineeringAleoPlanDigestV1",
      "ProofForgeV2/Targets/Registry.lean"]
  }
  expect (reg.exitCode == 0 && reg.stdout.contains "engineeringAleoPlanDigestV1")
    s!"registry wiring: {reg.stdout}"

unsafe def run : IO Unit := do
  testDomain
  testMinimalPlanDeterminism
  testTamperMatrix
  testInvalidPlanEncodeFails
  testProductPathRecompute
  testWirePresence
  IO.println "Tests.Materialization.AleoPlanSchemaV1: ok"

end Tests.Materialization.AleoPlanSchemaV1
