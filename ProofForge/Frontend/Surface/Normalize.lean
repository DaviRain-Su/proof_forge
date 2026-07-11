import ProofForge.Frontend.Surface.NormalizeStmt
import ProofForge.IR.Core.Error
import ProofForge.IR.Canonical

/-! # Surface AST — Top-Level Normalization to CanonicalBundle

Assembles the validated Surface contract into a `CanonicalBundle` using
the monadic infrastructure from NormalizeEnv/NormalizeExpr/NormalizeStmt.
-/

namespace ProofForge.Frontend.Surface

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.IR.Canonical

/-- Build the interface contract from the Surface contract and Core module. -/
def buildInterface (contract : SurfaceContract) (mod : Module) :
    SurfaceM InterfaceContract := do
  let env := (← get).env
  let entrypoints ← contract.entrypoints.mapIdxM fun idx ep => do
    let fid : FunctionId := ⟨idx⟩
    let function ← match mod.functions.find? (fun candidate => candidate.id == fid) with
      | some function => pure function
      | none => throw (SurfaceNormalizeError.unknownFunction ep.name)
    unless function.params.size == ep.params.size do
      throw (SurfaceNormalizeError.typeMismatch
        s!"{ep.params.size} interface parameters" s!"{function.params.size} Core parameters")
    let params ← ep.params.mapIdxM fun pidx p => do
      let coreTy ← liftExcept (resolveSurfaceType env.typeIds p.type)
      let valueDef := function.params[pidx]!
      return { valueId := valueDef.id, name := p.name, type := coreTy : InterfaceParam }
    let retType ← liftExcept (resolveSurfaceType env.typeIds ep.retType)
    return {
      functionId := fid,
      name := ep.name,
      kind := adaptEntrypointKind ep.kind,
      mutability := adaptMutability ep.mutability,
      selector? := ep.selector?,
      params := params,
      retType := retType
    : InterfaceEntrypoint }
  let events ← contract.events.mapIdxM fun idx ev => do
    let fields ← ev.fields.mapIdxM fun fidx f => do
      let coreTy ← liftExcept (resolveSurfaceType env.typeIds f.type)
      return { fieldId := ⟨fidx⟩, name := f.name, type := coreTy, indexed := f.indexed : InterfaceEventField }
    return { eventId := ⟨idx⟩, name := ev.name, fields := fields : InterfaceEvent }
  let errors ← contract.errors.mapIdxM fun idx e => do
    let decl ← match mod.errors.find? (fun d => d.id == ⟨idx⟩) with
      | some d => pure d
      | none => throw (SurfaceNormalizeError.unknownError e.name)
    return {
      errorId := ⟨idx⟩,
      namespace_ := "$surface",
      coreName := decl.name,
      name := e.name,
      userCode? := none,
      code := idx,
      message := e.message,
      params := decl.params
    : InterfaceError }
  return {
    contractName := contract.name,
    entrypoints := entrypoints,
    events := events,
    errors := errors
  }

/-- Build the materialization contract. -/
def buildMaterialization (contract : SurfaceContract) (interface : InterfaceContract) :
    SurfaceM MaterializationContract := do
  let bindings ← contract.constructorBindings.mapM fun b => do
    let stateId ← lookupState b.stateName
    return { stateId := stateId, paramName := b.paramName, kind := adaptCtorKind b.kind : ConstructorBinding }
  let stateSymbols ← contract.state.mapIdxM fun idx s => do
    return { stateId := ⟨idx⟩, name := s.name : StateDisplaySymbol }
  let typeLayouts ← contract.structs.mapIdxM fun idx s => do
    let fields ← s.fields.mapIdxM fun fidx f =>
      return { fieldId := ⟨fidx⟩, name := f.name, isPublic := true : TypeFieldMetadata }
    return { typeId := ⟨idx⟩, name := s.name, isPublic := true, deriveStorage := false, fields := fields : TypeLayoutMetadata }
  let eventEncodings := interface.events.map fun ev =>
    { eventId := ev.eventId, fields := ev.fields.filterMap (fun f =>
        f.abiWord?.map (fun w => { fieldId := f.fieldId, abiWord := w : EventFieldEncoding })) }
  let errorEncodings := interface.errors.map fun err =>
    { errorId := err.errorId, form := ErrorEncodingForm.assertFallback : ErrorEncoding }
  let intents := contract.intents.map fun i =>
    { kind := match i.kind with
        | .module => .module | .state => .state
        | .entrypoint => .entrypoint | .capability => .capability,
      label := i.label,
      capability? := i.capability?,
      metadata := i.metadata : MaterializationIntent }
  return {
    constructorBindings := bindings,
    constructorParams := contract.constructorParams.map fun p =>
      { name := p.name, abiType := p.abiType : ConstructorParam },
    stateSymbols := stateSymbols,
    typeLayouts := typeLayouts,
    eventEncodings := eventEncodings,
    errorEncodings := errorEncodings,
    intents := intents
  }

/-- Build canonical evidence from the Surface contract.
SourceSpans populate the SourceMap. -/
def buildEvidence (contract : SurfaceContract) : CanonicalEvidence :=
  let entries : Array (FunctionId × Option BlockId × Option Nat × SourceLocation) :=
    contract.entrypoints.mapIdx fun idx ep =>
      let loc : SourceLocation := match ep.span with
        | some span => { file := span.file, line := span.line, column := span.col }
        | none => { file := "", line := 0, column := 0 }
      (⟨idx⟩, none, none, loc)
  {
    sourceMap := { entries := entries },
    verification := {},
    intentSources := contract.intents.mapIdx fun idx i =>
      match i.source? with
      | some src => { intentIndex := idx, source := src : IntentSourceEvidence }
      | none => { intentIndex := idx, source := "" : IntentSourceEvidence },
    legacyClassification := #[]
  }

/-- Normalize a Surface contract to a CanonicalBundle.
This assigns canonical IDs by declaration order and maps all Surface
constructs to Core IR types. -/
def normalizeSurface (contract : SurfaceContract) :
    Except SurfaceNormalizeError CanonicalBundle := do
  match validateSurface contract with
  | Except.error e => Except.error (SurfaceNormalizeError.duplicateName "" e.message)
  | Except.ok _ => pure ()
  let env ← buildEnv contract
  let st := SurfaceState.ofEnv env
  let (mod, finalSt) ← StateT.run (adaptModule contract) st
  let (interface, _) ← StateT.run (buildInterface contract mod) finalSt
  let (materialization, _) ← StateT.run (buildMaterialization contract interface) finalSt
  let requirements := deriveCapabilityRequirements mod materialization
  let evidence := buildEvidence contract
  let canonical : CanonicalContract := {
    schemaVersion := canonicalSchemaVersion,
    module := mod,
    interface := interface,
    materialization := materialization,
    requirements := requirements,
    hostOpCatalog := ProofForge.IR.Core.HostOp.canonicalHostOpCatalog
  }
  match validateCanonical canonical with
  | Except.ok checked => pure { contract := checked, evidence := evidence }
  | Except.error e => Except.error (SurfaceNormalizeError.validation e)

end ProofForge.Frontend.Surface
