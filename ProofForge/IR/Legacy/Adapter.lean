import ProofForge.IR.Legacy.Adapter.Statement
import ProofForge.IR.Legacy.Classification
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec

namespace ProofForge.IR.Legacy.Adapter

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Contract
open ProofForge.Target

/- Convert a legacy `EntrypointKind` to its canonical string identifier. -/

def adaptEntrypointKind (kind : EntrypointKind) : String :=
  match kind with
  | .function => "function"
  | .fallback => "fallback"
  | .receive => "receive"

/- Convert a legacy `ConstructorInitBinding` to a canonical constructor binding.
The deploy-time value is not statically known; the binding records the target
state and a unit placeholder resolved by materialization. -/

def adaptConstructorBinding (env : AdapterEnv) (b : ConstructorInitBinding) : Except CanonicalizeError ConstructorBinding := do
  match Std.HashMap.get? env.stateIds b.stateId with
  | some (stateId, _) =>
      .ok { stateId := stateId, value := .unitLit }
  | none =>
      .error (CanonicalizeError.unknownState b.stateId)

/- Map the legacy `ContractSpec` fields into the canonical materialization
contract. All artifact-affecting metadata is preserved. -/

def adaptMaterialization (spec : ContractSpec) (env : AdapterEnv) : Except CanonicalizeError MaterializationContract := do
  let bindings ← spec.constructorInitBindings.mapM (adaptConstructorBinding env)
  let upgradePolicy := spec.upgradePolicy?.map (·.kind)
  let proxyPattern? := spec.proxyPattern?.map (·.kind)
  let constructorParams : Array ProofForge.IR.Canonical.ConstructorParam :=
    spec.constructorParams.map (fun p => {
      name := p.name
      abiType := p.abiType
    })
  return {
    constructorBindings := bindings,
    constructorParams := constructorParams,
    allocatorRequirement := none,
    upgradePolicy := upgradePolicy,
    proxyPattern? := proxyPattern?,
    intents := spec.intents
  }

/- Map legacy entrypoint metadata into the canonical interface contract. -/

def adaptInterface (m : Module) (env : AdapterEnv) : Except CanonicalizeError InterfaceContract := do
  let entrypoints ← m.entrypoints.mapM (fun ep => do
    match Std.HashMap.get? env.functionIds ep.name with
    | some fid =>
        .ok {
          functionId := fid,
          kind := adaptEntrypointKind ep.kind,
          mutatesState := ep.mutability == EntrypointMutability.call
        }
    | none => .error (CanonicalizeError.unknownFunction ep.name))
  let dispatchHints := m.entrypoints.filterMap (·.selector?)
  return { entrypoints := entrypoints, dispatchHints := dispatchHints }

/- Scan all statements for emitted event names. -/

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

def collectEventNames (m : Module) : Array String :=
  m.entrypoints.foldl (fun acc ep =>
    ep.body.foldl (fun a stmt => collectEventNamesStmt stmt a) acc) #[]

private def findEventArgTypes (functions : Array Function) (eventId : EventId) :
    Option (Array CoreType) :=
  Id.run do
    for function in functions do
      for block in function.blocks do
        for instruction in block.instructions do
          match instruction.op with
          | .emit emittedId args =>
              if emittedId == eventId then return some (args.map (·.type))
          | _ => pure ()
    return none

/- Build all canonical event declarations discovered in the module. -/

def adaptEvents (m : Module) (functions : Array Function) : AdapterM (Array Event) := do
  let names := collectEventNames m
  names.mapM (fun name => do
    let eventId ← lookupEvent name
    let types ← match findEventArgTypes functions eventId with
      | some types => pure types
      | none => throw (CanonicalizeError.unknownEvent name)
    let coreFields ← types.mapM (fun type => do
      let id ← freshValueId
      return { id := id, type := type })
    return { id := eventId, fields := coreFields })

/- Adapt a legacy struct declaration to canonical form. -/

def adaptStruct (decl : StructDecl) : AdapterM Struct := do
  let id ← lookupType decl.name
  let fields ← decl.fields.mapM (fun f => do
    let ty ← liftExcept (adaptType f.type)
    let vid ← freshValueId
    return { id := vid, type := ty })
  return { id := id, fields := fields }

/- Adapt one legacy entrypoint to a canonical function CFG. -/

def adaptFunction (ep : Entrypoint) : AdapterM Function := do
  resetLocals
  let fid ← lookupFunction ep.name
  let params ← ep.params.mapM (fun (name, ty) => do
    let coreTy ← liftExcept (adaptType ty)
    let vid ← freshValueId
    let vdef := { id := vid, type := coreTy }
    bindLocal name { id := vid, type := coreTy }
    return vdef)
  let retType ← liftExcept (adaptType ep.returns)
  let (blocks, entryId) ← normalizeBody ep.body retType
  return { id := fid, params := params, retType := retType, blocks := blocks, entry := entryId }

/- Adapt the runtime portion of a legacy module to canonical Core. -/

def adaptModuleM (m : Module) : AdapterM Core.Module := do
  let structs ← m.structs.mapM adaptStruct
  let state ← m.state.mapM (fun s => do
    let id ← lookupState s.id
    let shape ← liftExcept (adaptStateShape s)
    return { id := id, shape := shape })
  let functions ← m.entrypoints.mapM adaptFunction
  let events ← adaptEvents m functions
  return {
    name := m.name,
    structs := structs,
    state := state,
    functions := functions,
    events := events
  }

/- Verify that every `ContractSpec` field is classified and not rejected. -/

def checkSpecFieldClassification (spec : ContractSpec) : Except CanonicalizeError Unit := do
  for d in classifySpecFields spec do
    match d.disposition with
    | .reject => throw (CanonicalizeError.unsupportedConstructor d.field d.reason)
    | _ => pure ()

/- Build canonical evidence from the legacy spec, including classification and
verification annotations. -/

def adaptEvidence (spec : ContractSpec) : CanonicalEvidence := {
  sourceMap := { entries := #[] },
  verification := {
    invariants := spec.quintInvariants.map (·.fst) ++ spec.leanInvariants.map (·.fst),
    liveness := spec.quintLiveness.map (·.fst)
  },
  legacyClassification :=
    (classifySpecFields spec).map (fun d => {
      nodeTag := d.field,
      decision := d.disposition.toString,
      reason := d.reason
    })
}

/- Convert a `Capability` to a `CapabilityCall` used by the canonical contract. -/

def capabilityRequirements (m : Module) : Array CapabilityCall :=
  m.capabilities.map (fun c => CapabilityCall.fromCapability c)

/- Main entry point: adapt a legacy `ContractSpec` into a checked canonical
bundle. Fails closed on any unsupported constructor, unmapped field, or
validation error. -/

def adaptLegacy (spec : ContractSpec) : Except CanonicalizeError CanonicalBundle := do
  checkSpecFieldClassification spec
  let env ← buildEnv spec.module
  let st := AdapterState.ofEnv env
  let (module, _) ← StateT.run (adaptModuleM spec.module) st
  let interface ← adaptInterface spec.module env
  let materialization ← adaptMaterialization spec env
  let evidence := adaptEvidence spec
  let requirements := capabilityRequirements spec.module
  let canonical : CanonicalContract := {
    schemaVersion := 0,
    module := module,
    interface := interface,
    materialization := materialization,
    requirements := requirements
  }
  match validateCanonical canonical with
  | .error e => throw (CanonicalizeError.other (reprStr e))
  | .ok checked =>
      return { contract := checked, evidence := evidence }

end ProofForge.IR.Legacy.Adapter
