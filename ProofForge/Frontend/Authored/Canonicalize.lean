import ProofForge.Frontend.Authored.Canonicalize.Statement
import ProofForge.IR.Core.Error
import ProofForge.IR.Canonical
import ProofForge.Target.HostOps.Near
import ProofForge.Target.HostOps.Evm
import ProofForge.Target.HostOps.Solana
import ProofForge.Target.InterfaceOps.Evm

/-! # Authored AST — Top-Level Normalization to CanonicalBundle

Assembles the validated authored contract into a `CanonicalBundle` using
the monadic infrastructure from Canonicalize.Env/Expr/Statement.
-/

namespace ProofForge.Frontend.Authored.Canonicalize

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.IR.Canonical

/-- Build the interface contract from the authored contract and Core module. -/
def buildInterface (contract : AuthoredContract) (mod : Module) :
    AuthoredM InterfaceContract := do
  let env := (← get).env
  let entrypoints ← contract.entrypoints.mapIdxM fun idx ep => do
    let fid : FunctionId := ⟨idx⟩
    let function ← match mod.functions.find? (fun candidate => candidate.id == fid) with
      | some function => pure function
      | none => throw (AuthoredNormalizeError.unknownFunction ep.name)
    unless function.params.size == ep.params.size do
      throw (AuthoredNormalizeError.typeMismatch
        s!"{ep.params.size} interface parameters" s!"{function.params.size} Core parameters")
    let params ← ep.params.mapIdxM fun pidx p => do
      let coreTy ← liftExcept (resolveAuthoredType env.typeIds p.type)
      let valueDef := function.params[pidx]!
      let abiWord := p.abiWord?
      let result : InterfaceParam := {
        valueId := valueDef.id, name := p.name, type := coreTy, abiWord? := abiWord }
      return result
    let retType ← liftExcept (resolveAuthoredType env.typeIds ep.retType)
    return {
      functionId := fid,
      name := ep.name,
      mutability := adaptMutability ep.mutability,
      selector? := ep.selector?,
      params := params,
      retType := retType,
      returnAbiWord? := ep.returnAbiWord?
    : InterfaceEntrypoint }
  let events ← contract.events.mapIdxM fun idx ev => do
    let fields ← ev.fields.mapIdxM fun fidx f => do
      let coreTy ← liftExcept (resolveAuthoredType env.typeIds f.type)
      let abiWord := f.abiWord?
      let result : InterfaceEventField := {
        fieldId := ⟨fidx⟩, name := f.name, type := coreTy,
        indexed := f.indexed, abiWord? := abiWord }
      return result
    return { eventId := ⟨idx⟩, name := ev.name, fields := fields : InterfaceEvent }
  let errors ← mod.errors.mapM fun decl => do
    let surfaceError? := contract.errors[decl.id.value]?
    let displayName := surfaceError?.map (·.name) |>.getD decl.name
    let message := surfaceError?.map (·.message) |>.getD decl.name
    return {
      errorId := decl.id,
      namespace_ := decl.namespace_,
      coreName := decl.name,
      name := displayName,
      userCode? := none,
      code := decl.code,
      message := message,
      params := decl.params
    : InterfaceError }
  return {
    contractName := contract.name,
    entrypoints := entrypoints,
    events := events,
    errors := errors
  }

/-- Build the materialization contract. -/
def buildMaterialization (contract : AuthoredContract) (interface : InterfaceContract) :
    AuthoredM MaterializationContract := do
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
      operation := i.operation,
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

/-- Build canonical evidence from the authored contract.
SourceSpans populate the SourceMap. -/
def buildEvidence (contract : AuthoredContract) : CanonicalEvidence :=
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

private def moduleUsesHostOps (mod : Module) : Bool :=
  mod.functions.any fun function =>
    function.blocks.any fun block =>
      block.instructions.any fun instruction =>
        match instruction.op with
        | .hostCall _ => true
        | _ => false

private def materializationUsesHostOps (materialization : MaterializationContract) : Bool :=
  materialization.intents.any fun intent =>
    match intent.operation with
    | .hostOp _ => true
    | .builtin _ => false

/-- Normalize a authored contract to a CanonicalBundle.
This assigns canonical IDs by declaration order and maps all Authored
constructs to Core IR types. -/
def normalizeAuthored (contract : AuthoredContract) :
    Except AuthoredNormalizeError CanonicalBundle := do
  match validateAuthored contract with
  | Except.error e => Except.error (AuthoredNormalizeError.duplicateName "" e.message)
  | Except.ok _ => pure ()
  let env ← buildEnv contract
  let st := AuthoredState.ofEnv env
  let (mod, finalSt) ← StateT.run (adaptModule contract) st
  let (interface, _) ← StateT.run (buildInterface contract mod) finalSt
  let interfaceExtensions : Array InterfaceExtension :=
    contract.entrypoints.mapIdx (fun index entrypoint =>
      let id? := match entrypoint.kind with
        | .function => none
        | .fallback => some ProofForge.Target.InterfaceOps.Evm.fallbackDispatchId
        | .receive => some ProofForge.Target.InterfaceOps.Evm.receiveDispatchId
      id?.map fun id => { id, subject := .entrypoint ⟨index⟩ })
    |>.filterMap id
  let (materialization, _) ← StateT.run (buildMaterialization contract interface) finalSt
  let evidence := buildEvidence contract
  let hostOpCatalog ← if moduleUsesHostOps mod || materializationUsesHostOps materialization then
    match ProofForge.IR.Core.HostOp.HostOpCatalog.empty.registerAll
        (ProofForge.Target.HostOps.Near.signatures ++
          ProofForge.Target.HostOps.Evm.signatures ++
          ProofForge.Target.HostOps.Solana.signatures) with
    | .ok catalog => pure catalog
    | .error error => throw (.unsupportedAuthored "HostOpCatalog" s!"registration failed: {repr error}")
  else
    pure .empty
  let requirements := deriveCapabilityRequirements mod materialization hostOpCatalog
  let canonical : CanonicalContract := {
    schemaVersion := canonicalSchemaVersion,
    module := mod,
    interface := interface,
    interfaceExtensions := interfaceExtensions,
    materialization := materialization,
    requirements := requirements,
    hostOpCatalog
  }
  match validateCanonical canonical with
  | Except.ok checked => pure { contract := checked, evidence := evidence }
  | Except.error e => Except.error (AuthoredNormalizeError.validation e)

end ProofForge.Frontend.Authored.Canonicalize
