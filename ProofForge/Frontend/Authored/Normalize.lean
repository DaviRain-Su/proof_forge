import ProofForge.Frontend.Authored.Normalize.Statement
import ProofForge.Frontend.Authored.Classification
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec
import ProofForge.Target.HostOps.Near
import ProofForge.Target.HostOps.Evm
import ProofForge.Target.InterfaceOps.Evm

namespace ProofForge.Frontend.Authored.Normalize

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Contract
open ProofForge.Target

/- Closed source-schema-to-canonical policy mappings. -/

def adaptMutability (mutability : EntrypointMutability) : InterfaceMutability :=
  match mutability with
  | .call => .call
  | .view => .view

def adaptConstructorBindingKind (kind : ConstructorInitKind) : ConstructorBindingKind :=
  match kind with
  | .scalarU64 => .scalarU64
  | .addressWord => .addressWord
  | .addressKeccak => .addressKeccak
  | .stringLength => .stringLength
  | .stringKeccak => .stringKeccak
  | .bytesLength => .bytesLength
  | .bytesKeccak => .bytesKeccak
  | .arrayLength => .arrayLength
  | .arraySumU64 => .arraySumU64

def adaptUpgradePolicy : ProofForge.Contract.UpgradePolicy → CanonicalUpgradePolicy
  | .immutable => .immutable
  | .authority keyRef => .authority keyRef
  | .governance ref => .governance ref

def adaptModuleProxyPattern (pattern? : Option String) :
    Except CanonicalizeError (Option ProofForge.Contract.ProxyPattern) :=
  match pattern? with
  | none => .ok none
  | some "uups" => .ok (some .uups)
  | some "transparent" => .ok (some .transparent)
  | some pattern => .error <| CanonicalizeError.unsupportedConstructor
      "Module.proxyPattern?" s!"unknown proxy pattern `{pattern}`"

def adaptErrorEncodingForm : RegisteredErrorForm → ErrorEncodingForm
  | .assertFallback => .assertFallback
  | .revertMessage => .revertMessage
  | .proofForgeEnvelope => .proofForgeEnvelope
  | .solidityCustom => .proofForgeEnvelope

/- Convert a source constructor binding without dropping the named parameter or
typed initialization operation. -/

def adaptConstructorBinding (env : AdapterEnv) (b : ConstructorInitBinding) : Except CanonicalizeError ConstructorBinding := do
  match Std.HashMap.get? env.stateIds b.stateId with
  | some (stateId, _) =>
      .ok {
        stateId := stateId
        paramName := b.paramName
        kind := adaptConstructorBindingKind b.kind
      }
  | none =>
      .error (CanonicalizeError.unknownState b.stateId)

/- Map `ContractSpec` fields into the canonical materialization
contract. All artifact-affecting metadata is preserved. -/

def adaptStateSymbols (m : ProofForge.IR.Module) (env : AdapterEnv) :
    Except CanonicalizeError (Array StateDisplaySymbol) :=
  m.state.mapM (fun state =>
    match Std.HashMap.get? env.stateIds state.id with
    | some (stateId, _) => .ok { stateId := stateId, name := state.id }
    | none => .error (CanonicalizeError.unknownState state.id))

def adaptTypeLayouts (m : ProofForge.IR.Module) (env : AdapterEnv) :
    Except CanonicalizeError (Array TypeLayoutMetadata) :=
  m.structs.mapM (fun declaration =>
    match Std.HashMap.get? env.typeIds declaration.name with
    | none => .error (CanonicalizeError.unknownType declaration.name)
    | some typeId => .ok {
        typeId := typeId
        name := declaration.name
        isPublic := declaration.isPublic
        deriveStorage := declaration.deriveStorage
        fields := declaration.fields.mapIdx (fun index field => {
          fieldId := ⟨index⟩
          name := field.id
          isPublic := field.isPublic
        })
      })

def adaptMaterialization (spec : ContractSpec) (env : AdapterEnv)
    (interface : InterfaceContract) (registeredErrors : Array RegisteredError) :
    Except CanonicalizeError MaterializationContract := do
  let bindings ← spec.constructorInitBindings.mapM (adaptConstructorBinding env)
  let constructorParams : Array ProofForge.IR.Canonical.ConstructorParam :=
    spec.constructorParams.map (fun p => {
      name := p.name
      abiType := p.abiType
    })
  let stateSymbols ← adaptStateSymbols spec.module env
  let typeLayouts ← adaptTypeLayouts spec.module env
  let intents : Array MaterializationIntent := spec.intents.map (fun intent => {
    kind := intent.kind
    label := intent.label
    capability? := intent.capability?
    metadata := intent.metadata
  })
  let eventEncodings : Array EventEncoding := interface.events.map (fun event => {
    eventId := event.eventId
    fields := event.fields.filterMap (fun field => field.abiWord?.map (fun abiWord => {
      fieldId := field.fieldId
      abiWord := abiWord
    }))
  })
  let errorEncodings : Array ErrorEncoding := registeredErrors.map (fun error => {
    errorId := error.id
    form := adaptErrorEncodingForm error.form
  })
  return {
    constructorBindings := bindings,
    constructorParams := constructorParams,
    allocator := spec.module.allocator,
    upgradePolicy? := spec.upgradePolicy?.map adaptUpgradePolicy,
    crosscallStrings := spec.module.crosscallStrings,
    stateSymbols := stateSymbols,
    typeLayouts := typeLayouts,
    intents := intents,
    eventEncodings := eventEncodings,
    errorEncodings := errorEncodings
  }

def adaptInterfaceExtensions (spec : ContractSpec) (interface : InterfaceContract)
    (registeredErrors : Array RegisteredError) : Except CanonicalizeError (Array InterfaceExtension) := do
  let moduleProxyPattern? ← adaptModuleProxyPattern spec.module.proxyPattern?
  unless spec.proxyPattern? == moduleProxyPattern? do
    throw <| CanonicalizeError.unsupportedConstructor "proxyPattern?"
      "spec and module proxy patterns disagree"
  let proxyExtensions : Array InterfaceExtension := match spec.proxyPattern? with
    | none => #[]
    | some pattern => #[{
        id := ProofForge.Target.InterfaceOps.Evm.proxyPatternId
        subject := .contract
        args := #[.string pattern.kind]
      }]
  let errorExtensions := registeredErrors.filterMap fun error =>
    error.soliditySelector?.map fun selector => {
      id := ProofForge.Target.InterfaceOps.Evm.solidityCustomErrorId
      subject := .error error.id
      args := #[.string selector, .strings error.solidityArgTypes]
    }
  let mut dispatchExtensions := #[]
  for entrypoint in spec.module.entrypoints do
    let interfaceEntrypoint ← match interface.entrypoints.find? (·.name == entrypoint.name) with
      | some found => pure found
      | none => throw (CanonicalizeError.unknownFunction entrypoint.name)
    let id? := match entrypoint.kind with
      | .function => none
      | .fallback => some ProofForge.Target.InterfaceOps.Evm.fallbackDispatchId
      | .receive => some ProofForge.Target.InterfaceOps.Evm.receiveDispatchId
    if let some id := id? then
      dispatchExtensions := dispatchExtensions.push {
        id
        subject := .entrypoint interfaceEntrypoint.functionId
      }
  return errorExtensions ++ dispatchExtensions ++ proxyExtensions

/- Event catalogue extracted from source traversal. Field ordering is canonical:
indexed fields first, followed by data fields. Every occurrence of a named
event must agree before a Core declaration or interface schema is produced. -/

structure SourceEventField where
  name : String
  indexed : Bool
  deriving Repr, BEq

structure SourceEventSite where
  name : String
  fields : Array SourceEventField
  deriving Repr, BEq

def collectEventNamesStmt (stmt : Statement) (acc : Array String) : Array String :=
  match stmt with
  | .effect (.eventEmit name _) => if acc.contains name then acc else acc.push name
  | .effect (.eventEmitIndexed name _ _) => if acc.contains name then acc else acc.push name
  | .ifElse _ thenBody elseBody =>
      let acc := thenBody.foldl (fun a s => collectEventNamesStmt s a) acc
      elseBody.foldl (fun a s => collectEventNamesStmt s a) acc
  | .boundedFor _ _ _ body => body.foldl (fun a s => collectEventNamesStmt s a) acc
  | .whileLoop _ body => body.foldl (fun a s => collectEventNamesStmt s a) acc
  | _ => acc

def collectEventNames (m : ProofForge.IR.Module) : Array String :=
  m.entrypoints.foldl (fun acc ep =>
    ep.body.foldl (fun a stmt => collectEventNamesStmt stmt a) acc) #[]

private def collectEventSitesStmt (stmt : Statement)
    (sites : Array SourceEventSite) : Array SourceEventSite :=
  match stmt with
  | .effect (.eventEmit name fields) => sites.push {
      name := name
      fields := fields.map (fun field => { name := field.fst, indexed := false })
    }
  | .effect (.eventEmitIndexed name indexedFields dataFields) => sites.push {
      name := name
      fields :=
        indexedFields.map (fun field => { name := field.fst, indexed := true }) ++
        dataFields.map (fun field => { name := field.fst, indexed := false })
    }
  | .ifElse _ thenBody elseBody =>
      let sites := thenBody.foldl (fun acc nested => collectEventSitesStmt nested acc) sites
      elseBody.foldl (fun acc nested => collectEventSitesStmt nested acc) sites
  | .boundedFor _ _ _ body | .whileLoop _ body =>
      body.foldl (fun acc nested => collectEventSitesStmt nested acc) sites
  | _ => sites

private def collectEventSites (m : ProofForge.IR.Module) : Array SourceEventSite :=
  m.entrypoints.foldl (fun sites ep =>
    ep.body.foldl (fun acc stmt => collectEventSitesStmt stmt acc) sites) #[]

private def sourceEventFields (m : ProofForge.IR.Module) (name : String) :
    Except CanonicalizeError (Array SourceEventField) := do
  let sites := (collectEventSites m).filter (·.name == name)
  let fields ← match sites[0]? with
    | some site => pure site.fields
    | none => throw (CanonicalizeError.unknownEvent name)
  for site in sites do
    unless site.fields == fields do
      throw <| CanonicalizeError.conflictingEventSchema name
        "field names, order, or indexed flags differ across emit sites"
  if fields.any (·.name.isEmpty) then
    throw <| CanonicalizeError.conflictingEventSchema name "event field name is empty"
  if fields.map (·.name) |>.foldl (fun seen field =>
      if seen.1.contains field then (seen.1, true) else (seen.1.push field, seen.2))
      (#[], false) |>.2 then
    throw <| CanonicalizeError.conflictingEventSchema name "duplicate event field name"
  return fields

private def findEventArgTypes (functions : Array Function) (eventId : EventId) :
    Array (Array CoreType) :=
  Id.run do
    let mut schemas := #[]
    for function in functions do
      for block in function.blocks do
        for instruction in block.instructions do
          match instruction.op with
          | .emit emittedId args =>
              if emittedId == eventId then schemas := schemas.push (args.map (·.type))
          | _ => pure ()
    return schemas

/- Build all canonical event declarations discovered in the module. -/

def adaptEvents (m : ProofForge.IR.Module) (functions : Array Function) : AdapterM (Array Event) := do
  let names := collectEventNames m
  names.mapM (fun name => do
    let eventId ← lookupEvent name
    let schemas := findEventArgTypes functions eventId
    let types ← match schemas[0]? with
      | some types => pure types
      | none => throw (CanonicalizeError.unknownEvent name)
    for schema in schemas do
      unless schema == types do
        throw <| CanonicalizeError.conflictingEventSchema name
          s!"field types differ across normalized emit sites: expected {repr types}, got {repr schema}"
    let sourceFields ← liftExcept (sourceEventFields m name)
    unless sourceFields.size == types.size do
      throw <| CanonicalizeError.conflictingEventSchema name
        "source field count differs from normalized Core arguments"
    let coreFields ← types.mapIdxM (fun index type =>
      pure { id := ⟨index⟩, type := type })
    return { id := eventId, fields := coreFields })

private def validateEventAbiWords (m : ProofForge.IR.Module) : Except CanonicalizeError Unit := do
  for override in m.eventAbiWords do
    let fields ← sourceEventFields m override.eventName
    unless fields.any (·.name == override.fieldName) do
      throw <| CanonicalizeError.conflictingEventSchema override.eventName
        s!"ABI override references unknown field `{override.fieldName}`"
    unless (m.eventAbiWords.filter (fun candidate =>
        candidate.eventName == override.eventName &&
        candidate.fieldName == override.fieldName)).size == 1 do
      throw <| CanonicalizeError.conflictingEventSchema override.eventName
        s!"duplicate ABI override for field `{override.fieldName}`"

private def eventAbiWord? (m : ProofForge.IR.Module) (eventName fieldName : String) : Option String :=
  (m.eventAbiWords.find? (fun override =>
    override.eventName == eventName && override.fieldName == fieldName)).map (·.abiWord)

def adaptInterface (spec : ContractSpec) (module : Core.Module) (env : AdapterEnv)
    (registeredErrors : Array RegisteredError) : Except CanonicalizeError InterfaceContract := do
  let m := spec.module
  validateEventAbiWords m
  let entrypoints ← m.entrypoints.mapM (fun ep => do
    if ep.paramAbiWords.size > ep.params.size then
      throw <| CanonicalizeError.unsupportedConstructor "Entrypoint.paramAbiWords"
        s!"entrypoint `{ep.name}` has more ABI overrides than parameters"
    let fid ← match Std.HashMap.get? env.functionIds ep.name with
      | some fid => pure fid
      | none => throw (CanonicalizeError.unknownFunction ep.name)
    let function ← match module.functions.find? (·.id == fid) with
      | some function => pure function
      | none => throw (CanonicalizeError.unknownFunction ep.name)
    let params ← ep.params.mapIdxM (fun index param => do
      let (name, ty) := param
      let coreType ← adaptType env.typeIds ty
      let valueId ← match function.params[index]? with
        | some value => pure value.id
        | none => throw (CanonicalizeError.typeMismatch
            "Core function parameter" s!"missing parameter {index} in `{ep.name}`")
      let abiWord? := match ep.paramAbiWords[index]? with
        | some abiWord? => abiWord?
        | none => none
      return { valueId := valueId, name := name, type := coreType, abiWord? := abiWord? })
    let retType ← adaptType env.typeIds ep.returns
    return {
      functionId := fid
      name := ep.name
      mutability := adaptMutability ep.mutability
      selector? := ep.selector?
      params := params
      retType := retType
      returnAbiWord? := ep.returnAbiWord?
    })
  let events ← (collectEventNames m).mapM (fun name => do
    let eventId ← match Std.HashMap.get? env.eventIds name with
      | some eventId => pure eventId
      | none => throw (CanonicalizeError.unknownEvent name)
    let declaration ← match module.events.find? (·.id == eventId) with
      | some declaration => pure declaration
      | none => throw (CanonicalizeError.unknownEvent name)
    let sourceFields ← sourceEventFields m name
    let fields ← sourceFields.mapIdxM (fun index sourceField =>
      match declaration.fields[index]? with
      | none => throw <| CanonicalizeError.conflictingEventSchema name
          "interface field has no matching Core declaration"
      | some field => pure {
          fieldId := field.id
          name := sourceField.name
          type := field.type
          indexed := sourceField.indexed
          abiWord? := eventAbiWord? m name sourceField.name
        })
    return { eventId := eventId, name := name, fields := fields })
  let errors ← registeredErrors.mapM (fun error => do
    let declaration ← match module.errors.find? (·.id == error.id) with
      | some declaration => pure declaration
      | none => throw (CanonicalizeError.conflictingErrorSchema error.name
          "registered error has no matching Core declaration")
    return {
      errorId := error.id
      namespace_ := error.namespace_
      coreName := declaration.name
      name := error.name
      userCode? := error.userCode?
      code := error.code
      message := error.message
      params := declaration.params
    })
  return {
    contractName := spec.name
    entrypoints := entrypoints
    events := events
    errors := errors
  }

/- Normalize a source struct declaration to canonical form. -/

def adaptStruct (decl : StructDecl) : AdapterM Struct := do
  let id ← lookupType decl.name
  let typeIds := (← get).env.typeIds
  let fields ← decl.fields.mapIdxM (fun index f => do
    let ty ← liftExcept (adaptType typeIds f.type)
    return {
      id := ⟨index⟩
      type := ty
      ownership := if f.isRef then .reference else .value
    })
  return {
    id := id
    fields := fields
    semantics := if decl.isRecord then .linearRecord else .value
  }

/- Normalize one source entrypoint to a canonical function CFG. -/

def adaptFunction (ep : Entrypoint) : AdapterM Function := do
  resetLocals
  let fid ← lookupFunction ep.name
  let typeIds := (← get).env.typeIds
  let params ← ep.params.mapM (fun (name, ty) => do
    let coreTy ← liftExcept (adaptType typeIds ty)
    let vid ← freshValueId
    let vdef := { id := vid, type := coreTy }
    bindLocal name { id := vid, type := coreTy }
    return vdef)
  let retType ← liftExcept (adaptType typeIds ep.returns)
  let (blocks, entryId) ← normalizeBody ep.body retType
  return { id := fid, params := params, retType := retType, blocks := blocks, entry := entryId }

/- Normalize the runtime portion of a source module to canonical Core. -/

def adaptModuleM (m : ProofForge.IR.Module) : AdapterM Core.Module := do
  let structs ← m.structs.mapM adaptStruct
  let state ← m.state.mapM (fun s => do
    let id ← lookupState s.id
    let shape ← liftExcept (adaptStateShape (← get).env.typeIds s)
    return { id := id, shape := shape })
  let functions ← m.entrypoints.mapM adaptFunction
  let events ← adaptEvents m functions
  return {
    name := m.name,
    structs := structs,
    state := state,
    functions := functions,
    events := events,
    errors := (← get).env.errorDecls
  }

/- Verify that every `ContractSpec` field is classified and not rejected. -/

def checkSpecFieldClassification (spec : ContractSpec) : Except CanonicalizeError Unit := do
  for d in classifySpecFields spec do
    match d.disposition with
    | .reject => throw (CanonicalizeError.unsupportedConstructor d.field d.reason)
    | _ => pure ()

/- Build canonical evidence from the source spec, including classification and
verification annotations. -/

def adaptEvidence (spec : ContractSpec) : CanonicalEvidence := {
  sourceMap := { entries := #[] },
  verification := {
    quintInvariants := spec.quintInvariants.map (fun (name, body) =>
      { name := name, body := body }),
    quintLiveness := spec.quintLiveness.map (fun (name, body) =>
      { name := name, body := body }),
    leanInvariants := spec.leanInvariants.map (fun (name, body) =>
      { name := name, body := body })
  },
  intentSources := spec.intents.mapIdx (fun intentIndex intent =>
    intent.source?.map (fun source => { intentIndex := intentIndex, source := source }))
    |>.filterMap id,
  legacyClassification :=
    (classifySpecFields spec).map (fun d => {
      nodeTag := d.field,
      decision := d.disposition.toString,
      reason := d.reason
    })
}

/- Main entry point: normalize an authored `ContractSpec` into a checked canonical
bundle. Fails closed on any unsupported constructor, unmapped field, or
validation error. -/

def normalizeContractSpec (spec : ContractSpec) : Except CanonicalizeError CanonicalBundle := do
  checkSpecFieldClassification spec
  let env ← buildEnv spec.module
  let st := AdapterState.ofEnv env
  let (module, finalSt) ← StateT.run (adaptModuleM spec.module) st
  let registeredErrors := finalSt.env.registeredErrors
  let interface ← adaptInterface spec module finalSt.env registeredErrors
  let materialization ← adaptMaterialization spec finalSt.env interface registeredErrors
  let interfaceExtensions ← adaptInterfaceExtensions spec interface registeredErrors
  let evidence := adaptEvidence spec
  let hostOpCatalog ← match ProofForge.IR.Core.HostOp.HostOpCatalog.empty.registerAll
      (ProofForge.Target.HostOps.Near.signatures ++ ProofForge.Target.HostOps.Evm.signatures) with
    | .ok catalog => pure catalog
    | .error error => throw (.other s!"HostOp catalog registration failed: {repr error}")
  let requirements := ProofForge.IR.Canonical.deriveCapabilityRequirements
    module materialization hostOpCatalog
  let canonical : CanonicalContract := {
    schemaVersion := canonicalSchemaVersion,
    module := module,
    interface := interface,
    interfaceExtensions := interfaceExtensions,
    materialization := materialization,
    requirements := requirements,
    hostOpCatalog
  }
  match validateCanonical canonical with
  | .error e => throw (CanonicalizeError.validation e)
  | .ok checked =>
      return { contract := checked, evidence := evidence }

end ProofForge.Frontend.Authored.Normalize
