import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
import ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

/-!
# Psy EmitIRV1 — direct Plan → DPN

The Psy target owns one product IR: the versioned DPN package. There is no Psy
source AST, renderer, debug dual-write, or compiler fallback. Any Plan admitted
by `ValidatePlanV1` that cannot lower to DPN fails closed at this boundary.
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1
open ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
open ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

/-- Target-owned DPN IR bound to the exact validated Plan that produced it. -/
structure IR where
  sourcePlan : Plan
  package : PackageV1
  deriving BEq, Inhabited, Repr

private def lowerDpnPackageV1 (plan : Plan) : CompileResult PackageV1 := do
  match lowerPlanToPackageV1 plan with
  | .ok package => pure package
  | .error (.planInvariant .psy message) =>
      planError s!"PSY-DPN-G5-HARD: Plan admitted but DPN lower failed: {message}"
  | .error error => .error error

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let package ← lowerDpnPackageV1 plan
  pure { sourcePlan := plan, package }

/-- Validate the Plan join and canonical JSON codec round trip. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  let expected ← lowerDpnPackageV1 ir.sourcePlan
  unless expected == ir.package do
    planError "Psy DPN IR does not match its source Plan"
  let encoded := encodePackageCompact ir.package
  unless parsePackage? encoded == some ir.package do
    planError "Psy DPN package failed canonical codec round trip"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  pure #[{
    path := s!"{ir.sourcePlan.programName}.dpn.json"
    mediaType := "application/json"
    contents := encodePackageCompact ir.package
  }]

/-- Capability-gated public DPN IR entry. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  lower plan

/-- Capability-gated public DPN materializer. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  emitFromIR (← irFromCapability capability)

/-- Engineering/test materializer from a retained Plan. -/
def buildFromPlanV1 (plan : Plan) : CompileResult (Array OutputFile) := do
  emitFromIR (← lower plan)

/-- Engineering/test IR entry over retained SemanticProgramV1. -/
def irFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult IR := do
  lower (← planFromCompiledSemanticV1 compiled)

/-- Engineering/test DPN materializer over retained SemanticProgramV1. -/
def buildFromCompiledSemanticV1 (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  emitFromIR (← irFromCompiledSemanticV1 compiled)

end ProofForgeV2.Targets.Psy
