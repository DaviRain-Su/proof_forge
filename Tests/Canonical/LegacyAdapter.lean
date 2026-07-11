import ProofForge.Contract.Spec
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Core
import Std

namespace Tests.Canonical.LegacyAdapter

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Legacy
open ProofForge.IR.Legacy.Adapter
open ProofForge.Contract

def counterSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.Counter.module

def vaultSpec : ContractSpec :=
  ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/- Check that every scalar storage load/store in a function refers to the
state declaration with the matching source name. -/

def checkScalarStorageSourceNames (module : Core.Module) : Bool :=
  module.functions.all (fun f =>
    f.blocks.all (fun b =>
      b.instructions.all (fun i =>
        match i.op with
        | .storageLoad path | .storageStore path _ =>
            match module.state.find? (·.id == path.root) with
            | none => false
            | some decl =>
                match decl.shape with
                | .scalar _ => true
                | _ => false
        | _ => true)))

/- Check that a function contains a context read instruction. -/

def hasContextRead (module : Core.Module) (field : Core.ContextField) : Bool :=
  module.functions.any (fun f =>
    f.blocks.any (fun b =>
      b.instructions.any (fun i =>
        match i.op with
        | .contextRead f => f == field
        | _ => false)))

/- Extract event emission source names in source order across all functions. -/

def eventNamesInOrder (module : Core.Module) (sourceModule : ProofForge.IR.Module) : List String :=
  let nameMap : Std.HashMap Nat String :=
    Id.run do
      let mut map := {}
      let names := collectEventNames sourceModule
      for h : i in [:names.size] do
        map := map.insert i names[i]
      return map
  Id.run do
    let mut names := []
    for f in module.functions do
      for b in f.blocks do
        for i in b.instructions do
          match i.op with
          | .emit eventId _ =>
              match nameMap.get? eventId.value with
              | some name => names := name :: names
              | none => pure ()
          | _ => pure ()
    return names.reverse

/- Extract return values in source order. -/

def returnCount (module : Core.Module) : Nat :=
  module.functions.foldl (fun acc f =>
    f.blocks.foldl (fun acc2 b =>
      match b.terminator with
      | .return _ => acc2 + 1
      | _ => acc2) acc) 0

/- Extract return types in source order. -/

def returnTypesInOrder (module : Core.Module) : List CoreType :=
  module.functions.map (·.retType) |>.toList

/- Check that an `add` expression in the bundle uses the given overflow mode. -/

def hasArithmeticMode (module : Core.Module) (op : ArithmeticOp) (mode : OverflowMode) : Bool :=
  module.functions.any (fun f =>
    f.blocks.any (fun b =>
      b.instructions.any (fun i =>
        match i.op with
        | .pure (.arithmetic o m _ _) => o == op && m == mode
        | _ => false)))

/- Build a minimal contract whose body reads an unknown state name. -/

def unknownStateModule : ProofForge.IR.Module := {
  name := "UnknownState",
  state := #[{ id := "known", kind := .scalar, type := .u64 }],
  entrypoints := #[{
    name := "get",
    body := #[.return (.effect (.storageScalarRead "missing"))]
  }]
}

/- Build a minimal contract with an out-of-range literal. -/

def outOfRangeModule (ty : ValueType) (value : Nat) : ProofForge.IR.Module := {
  name := "OutOfRange",
  state := #[],
  entrypoints := #[{
    name := "get",
    returns := ty,
    body := #[.return (.literal (match ty with
      | .u8 => Literal.u8 value
      | .u32 => Literal.u32 value
      | .u64 => Literal.u64 value
      | .u128 => Literal.u128 value
      | _ => Literal.u8 value))]
  }]
}

def arithmeticModeModule (checked : Bool) : ProofForge.IR.Module := {
  name := if checked then "Checked" else "Wrapping"
  state := #[]
  entrypoints := #[{
    name := "calculate"
    returns := .u64
    body := #[.return (.add (.literal (.u64 1)) (.literal (.u64 2)) checked)]
  }]
}

def mismatchedLetModule : ProofForge.IR.Module := {
  name := "MismatchedLet"
  state := #[]
  entrypoints := #[{
    name := "bad"
    returns := .bool
    body := #[
      .letBind "x" .bool (.literal (.u64 1)),
      .return (.local "x")
    ]
  }]
}

def ifElseModule : ProofForge.IR.Module := {
  name := "IfElse"
  state := #[{ id := "count", kind := .scalar, type := .u64 }]
  entrypoints := #[{
    name := "choose"
    body := #[.ifElse (.literal (.bool true))
      #[.effect (.storageScalarWrite "count" (.literal (.u64 1)))]
      #[.effect (.storageScalarWrite "count" (.literal (.u64 2)))]]
  }]
}

def boundedForModule : ProofForge.IR.Module := {
  name := "BoundedFor"
  state := #[{ id := "count", kind := .scalar, type := .u64 }]
  entrypoints := #[{
    name := "run"
    body := #[.boundedFor "i" 0 3 #[
      .effect (.storageScalarAssignOp "count" .add (.literal (.u64 1)))
    ]]
  }]
}

def structuredErrorModule : ProofForge.IR.Module := {
  name := "StructuredError"
  state := #[]
  entrypoints := #[{
    name := "fail"
    body := #[.assert (.literal (.bool false)) "denied" (some {
      assertionId := 7
      userCode? := some "Denied"
    })]
  }]
}

def boolEventModule : ProofForge.IR.Module := {
  name := "BoolEvent"
  state := #[]
  entrypoints := #[{
    name := "emit_flag"
    body := #[.effect (.eventEmit "Flag" #[
      ("enabled", .literal (.bool true))
    ])]
  }]
}

def nestedTerminatingIfModule : ProofForge.IR.Module := {
  name := "NestedTerminatingIf"
  state := #[]
  entrypoints := #[{
    name := "choose"
    returns := .u64
    body := #[.ifElse (.literal (.bool true))
      #[.ifElse (.literal (.bool false))
        #[.return (.literal (.u64 1))]
        #[.return (.literal (.u64 2))]]
      #[.return (.literal (.u64 3))]]
  }]
}

def conditionalLocalMutationModule : ProofForge.IR.Module := {
  name := "ConditionalLocalMutation"
  state := #[]
  entrypoints := #[{
    name := "choose"
    params := #[("condition", .bool)]
    returns := .u64
    body := #[
      .letMutBind "value" .u64 (.literal (.u64 0)),
      .ifElse (.local "condition")
        #[.assign (.local "value") (.literal (.u64 1))]
        #[],
      .return (.local "value")
    ]
  }]
}

def loopLocalMutationModule : ProofForge.IR.Module := {
  name := "LoopLocalMutation"
  state := #[]
  entrypoints := #[{
    name := "run"
    returns := .u64
    body := #[
      .letMutBind "value" .u64 (.literal (.u64 0)),
      .boundedFor "i" 0 2 #[
        .assignOp (.local "value") .add (.literal (.u64 1))
      ],
      .return (.local "value")
    ]
  }]
}

def releaseModule : ProofForge.IR.Module := {
  name := "Release"
  state := #[]
  entrypoints := #[{
    name := "run"
    returns := .u64
    body := #[
      .letBind "value" .u64 (.literal (.u64 1)),
      .release "value",
      .return (.local "value")
    ]
  }]
}

def envelopeProbeModule : ProofForge.IR.Module := {
  name := "EnvelopeRuntime"
  structs := #[{
    name := "PrivateRecord"
    isPublic := false
    deriveStorage := true
    fields := #[{
      id := "secret"
      type := .u64
      isPublic := false
    }]
  }]
  state := #[
    { id := "labelLength", kind := .scalar, type := .u64 },
    { id := "labelHash", kind := .scalar, type := .hash },
    { id := "quota", kind := .map .address 17, type := .u64 }
  ]
  entrypoints := #[
    {
      name := "configure"
      selector? := some "11223344"
      params := #[("owner", .address)]
      paramAbiWords := #[some "address"]
      body := #[
        .effect (.eventEmitIndexed "Configured"
          #[("owner", .local "owner")]
          #[("value", .literal (.u64 7))]),
        .assert (.literal (.bool false)) "denied" (some {
          assertionId := 77
          userCode? := some "Denied"
          soliditySelector? := some "DEADBEEF"
          solidityArgWords := #[7]
          solidityArgTypes := #["uint256"]
        })
      ]
    },
    {
      name := "selector_gap"
      mutability := .view
      body := #[]
    }
  ]
  eventAbiWords := #[
    { eventName := "Configured", fieldName := "owner", abiWord := "address" },
    { eventName := "Configured", fieldName := "value", abiWord := "uint256" }
  ]
  allocator := { model := {
    strategy := .hostImport
    region := { base := 4096, size? := some 8192, growable := false }
    release := .reuse
    hostProvided := true
  } }
  proxyPattern? := some "uups"
  nearCrosscallStrings := #["remote.near", "configure"]
}

def envelopeProbeSpec : ContractSpec := {
  name := "EnvelopeDisplayName"
  module := envelopeProbeModule
  intents := #[{
    kind := .capability
    label := "emit-configured"
    capability? := some .eventsEmit
    source? := some "EnvelopeProbe.lean:42"
    metadata := #[{ key := "event", value := "Configured" }]
  }]
  upgradePolicy? := some (.authority "deployment-admin")
  proxyPattern? := some .uups
  constructorParams := #[{ name := "label", abiType := "string" }]
  constructorInitBindings := #[
    { stateId := "labelLength", paramName := "label", kind := .stringLength },
    { stateId := "labelHash", paramName := "label", kind := .stringKeccak }
  ]
  quintInvariants := #[("label_nonempty", "labelLength > 0")]
  quintLiveness := #[("eventually_configured", "eventually configured")]
  leanInvariants := #[("label_bound", "Envelope.labelBound")]
}

def conflictingEventModule : ProofForge.IR.Module := {
  name := "ConflictingEvent"
  state := #[]
  entrypoints := #[{
    name := "emit_conflict"
    body := #[
      .effect (.eventEmit "Conflict" #[("left", .literal (.u64 1))]),
      .effect (.eventEmitIndexed "Conflict" #[("right", .literal (.u64 2))] #[])
    ]
  }]
}

def duplicateEntrypointModule : ProofForge.IR.Module := {
  name := "DuplicateEntrypoint"
  state := #[]
  entrypoints := #[
    { name := "duplicate", body := #[] },
    { name := "duplicate", body := #[] }
  ]
}

def structReferenceModule : ProofForge.IR.Module := {
  name := "StructReference"
  structs := #[{
    name := "Box"
    fields := #[{ id := "value", type := .u64 }]
  }]
  state := #[{ id := "stored", kind := .scalar, type := .structType "Box" }]
  entrypoints := #[{
    name := "echo"
    params := #[("box", .structType "Box")]
    returns := .structType "Box"
    body := #[.return (.local "box")]
  }]
}

def hasBoundedBackedge (module : Core.Module) : Bool :=
  module.functions.any (fun f => f.blocks.any (fun b =>
    match b.terminator with
    | .jump _ _ (some (.atMost 3)) => true
    | _ => false))

def hasErrorCode (module : Core.Module) (code : Nat) : Bool :=
  module.errors.any (·.code == code) &&
  module.functions.any (fun f => f.blocks.any (fun b =>
    b.instructions.any (fun i => match i.op with
      | .assert _ error =>
          match module.errors.find? (·.id == error.id) with
          | some decl => decl.code == code
          | none => false
      | _ => false)))

def runAssertions : IO Unit := do
  -- Counter adapts successfully.
  let counterBundle ← match adaptLegacy counterSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"Counter adapt failed: {repr e}"

  let counterModule := counterBundle.contract.contract.module
  require (counterModule.state.size == 1) s!"Counter state count: {counterModule.state.size}"
  require (counterModule.functions.size == 3) s!"Counter function count: {counterModule.functions.size}"
  require (checkScalarStorageSourceNames counterModule) "Counter scalar storage names diverged"
  require (returnCount counterModule == 3) s!"Counter terminator count: {returnCount counterModule}"
  require (eventNamesInOrder counterModule counterSpec.module == []) "Counter event emission order"
  require (returnTypesInOrder counterModule == [.unit, .unit, .u64]) "Counter return type order"
  match counterModule.functions.find? (·.id == ⟨2⟩) with
  | some counterGet =>
      require (counterGet.blocks.any (fun b => match b.terminator with
        | .return values => values.size == 1
        | _ => false)) "Counter get return value was not preserved"
  | none => throw <| IO.userError "Counter get function missing"
  require (hasArithmeticMode counterModule .add .checked) "Counter checked add not preserved"

  let wrappingBundle ← match adaptLegacy (ContractSpec.fromIR (arithmeticModeModule false)) with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"wrapping arithmetic adapt failed: {repr e}"
  require (hasArithmeticMode wrappingBundle.contract.contract.module .add .wrapping)
    "explicit wrapping add not preserved"

  -- ValueVault adapts successfully.
  let vaultBundle ← match adaptLegacy vaultSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"ValueVault adapt failed: {repr e}"

  let vaultModule := vaultBundle.contract.contract.module
  require (vaultModule.state.size == 6) s!"ValueVault state count: {vaultModule.state.size}"
  let stateIdSet : Std.HashSet Nat :=
    vaultModule.state.foldl (fun acc s => acc.insert s.id.value) {}
  require (stateIdSet.size == 6) s!"ValueVault distinct StateId count: {stateIdSet.size}"
  require (vaultModule.functions.size == 7) s!"ValueVault function count: {vaultModule.functions.size}"
  require (checkScalarStorageSourceNames vaultModule) "ValueVault scalar storage names diverged"
  require (hasContextRead vaultModule .blockNumber) "checkpointId did not become context read"
  require (returnCount vaultModule == 7) s!"ValueVault terminator count: {returnCount vaultModule}"
  require (eventNamesInOrder vaultModule vaultSpec.module == ["VaultInitialized", "ValueDeposited", "ValueCharged", "ValueReleased", "ValueSnapshot"])
    "ValueVault event emission order"
  require (returnTypesInOrder vaultModule == [.unit, .unit, .unit, .unit, .u64, .u64, .u64])
    "ValueVault return type order"

  -- Interface contract preserves entrypoint metadata.
  let interface := vaultBundle.contract.contract.interface
  require (interface.contractName == vaultSpec.name) "interface contract name"
  require (interface.entrypoints.size == 7) "interface entrypoint count"
  let initEp? := interface.entrypoints.find? (·.functionId == ⟨0⟩)
  match initEp? with
  | some ep =>
      require (ep.name == "initialize") "initialize name"
      require (ep.kind == .function) "initialize kind"
      require (ep.mutability == .call) "initialize mutability"
      require (ep.params.map (·.type) == #[.u64]) "initialize params"
      require (ep.retType == .unit) "initialize return type"
  | none => throw <| IO.userError "initialize entrypoint missing from interface"
  let counterInterface := counterBundle.contract.contract.interface
  let counterGetEp? := counterInterface.entrypoints.find? (·.functionId == ⟨2⟩)
  match counterGetEp? with
  | some ep =>
      require (ep.name == "get") "Counter get name"
      require (ep.kind == .function) "Counter get kind"
      require (ep.mutability == .view) "Counter get should be view"
      require (ep.params == #[]) "Counter get params"
      require (ep.retType == .u64) "Counter get return type"
  | none => throw <| IO.userError "Counter get entrypoint missing from interface"
  require ((interface.entrypoints.filterMap (·.selector?)).size == 7) "selector count"

  -- Materialization and evidence cover the spec fields.
  let materialization := vaultBundle.contract.contract.materialization
  require (materialization.upgradePolicy? == none) "upgrade policy should be empty for fixture"
  let evidence := vaultBundle.evidence
  require (evidence.legacyClassification.size == 10) "legacy classification evidence count"
  let expectedClassification : List (String × LegacyDisposition) := [
    ("name", .preserve),
    ("module", .normalize),
    ("intents", .materialization),
    ("upgradePolicy?", .materialization),
    ("proxyPattern?", .materialization),
    ("constructorParams", .materialization),
    ("constructorInitBindings", .materialization),
    ("quintInvariants", .evidence),
    ("quintLiveness", .evidence),
    ("leanInvariants", .evidence)
  ]
  for (field, disp) in expectedClassification do
    match evidence.legacyClassification.find? (·.nodeTag == field) with
    | some d =>
        require (d.decision == disp.toString) s!"classification for {field}: {d.decision} ≠ {disp.toString}"
    | none => throw <| IO.userError s!"missing classification for {field}"
  require (evidence.legacyClassification.all (fun d => d.decision != LegacyDisposition.reject.toString))
    "legacy classification contains a reject disposition"
  require (evidence.verification.quintInvariants.isEmpty) "fixture has no Quint invariants"
  require (evidence.verification.quintLiveness.isEmpty) "fixture has no Quint liveness"
  require (evidence.verification.leanInvariants.isEmpty) "fixture has no Lean invariants"

  -- Non-default envelope metadata is readable from the canonical bundle alone.
  let probeBundle ← match adaptLegacy envelopeProbeSpec with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"envelope probe adapt failed: {repr e}"
  let probe := probeBundle.contract.contract
  require (probe.schemaVersion == ProofForge.IR.Canonical.canonicalSchemaVersion)
    "canonical schema version changed"
  require (probe.interface.contractName == "EnvelopeDisplayName")
    "ContractSpec name was not preserved"
  let configure ← match probe.interface.entrypoints.find? (·.name == "configure") with
    | some entrypoint => pure entrypoint
    | none => throw <| IO.userError "configure interface entrypoint missing"
  require (configure.selector? == some "11223344") "selector was not preserved"
  require (configure.params.size == 1) "configure parameter count"
  require (configure.params[0]!.name == "owner" &&
      configure.params[0]!.type == .address &&
      configure.params[0]!.abiWord? == some "address")
    "parameter identity/type/ABI was not preserved"
  let selectorGap ← match probe.interface.entrypoints.find? (·.name == "selector_gap") with
    | some entrypoint => pure entrypoint
    | none => throw <| IO.userError "selector-gap entrypoint missing"
  require (selectorGap.selector?.isNone && selectorGap.mutability == .view)
    "optional selector gap or mutability was changed"

  let configuredEvent ← match probe.interface.events.find? (·.name == "Configured") with
    | some event => pure event
    | none => throw <| IO.userError "Configured interface event missing"
  require (configuredEvent.fields.map (·.name) == #["owner", "value"])
    "event field names/order changed"
  require (configuredEvent.fields.map (·.indexed) == #[true, false])
    "indexed event partition changed"
  require (configuredEvent.fields.map (·.abiWord?) == #[some "address", some "uint256"])
    "event ABI overrides changed"

  let configuredError ← match probe.interface.errors.find? (·.name == "Denied") with
    | some error => pure error
    | none => throw <| IO.userError "Denied interface error missing"
  require (configuredError.userCode? == some "Denied" &&
      configuredError.code == 77 && configuredError.message == "denied")
    "portable error catalogue changed"
  let errorEncoding ← match probe.materialization.errorEncodings.find?
      (·.errorId == configuredError.errorId) with
    | some encoding => pure encoding
    | none => throw <| IO.userError "Denied materialization encoding missing"
  require (errorEncoding.form == .solidityCustom &&
      errorEncoding.soliditySelector? == some "deadbeef" &&
      errorEncoding.solidityArgTypes == #["uint256"] &&
      errorEncoding.solidityArgWords == #[7])
    "custom error selector/schema/words changed"

  let probeMaterialization := probe.materialization
  require (probeMaterialization.constructorParams == #[{
    name := "label", abiType := "string"
  }]) "dynamic constructor parameter changed"
  require (probeMaterialization.constructorBindings == #[
    { stateId := ⟨0⟩, paramName := "label", kind := .stringLength },
    { stateId := ⟨1⟩, paramName := "label", kind := .stringKeccak }
  ]) "typed constructor bindings changed"
  require (probeMaterialization.allocator.model.strategy == .hostImport &&
      probeMaterialization.allocator.model.region.base == 4096 &&
      probeMaterialization.allocator.model.region.size? == some 8192 &&
      !probeMaterialization.allocator.model.region.growable &&
      probeMaterialization.allocator.model.release == .reuse &&
      probeMaterialization.allocator.model.hostProvided)
    "allocator configuration changed"
  require (probeMaterialization.upgradePolicy? == some (.authority "deployment-admin"))
    "upgrade authority keyRef changed"
  require (probeMaterialization.proxyPattern? == some .uups &&
      probeMaterialization.moduleProxyPattern? == some .uups)
    "spec/module proxy policy changed"
  require (probeMaterialization.nearHostStrings == #["remote.near", "configure"])
    "NEAR host string pool changed"
  require (probeMaterialization.stateSymbols.map (·.name) ==
      #["labelLength", "labelHash", "quota"])
    "state display symbols changed"
  let quotaSymbol ← match probeMaterialization.stateSymbols.find? (·.name == "quota") with
    | some symbol => pure symbol
    | none => throw <| IO.userError "quota state symbol missing"
  match probe.module.state.find? (·.id == quotaSymbol.stateId) with
  | some { shape := .map .address .u64 (some 17), .. } => pure ()
  | some state => throw <| IO.userError s!"quota map capacity changed: {repr state.shape}"
  | none => throw <| IO.userError "quota Core state missing"
  let privateLayout ← match probeMaterialization.typeLayouts.find? (·.name == "PrivateRecord") with
    | some layout => pure layout
    | none => throw <| IO.userError "type layout metadata missing"
  require (!privateLayout.isPublic && privateLayout.deriveStorage &&
      privateLayout.fields.map (·.name) == #["secret"] &&
      privateLayout.fields.all (fun field => !field.isPublic))
    "struct/field materialization metadata changed"
  require (probeMaterialization.intents == #[{
      kind := .capability
      label := "emit-configured"
      capability? := some .eventsEmit
      metadata := #[{ key := "event", value := "Configured" }]
    }]) "source-free materialization intent changed"
  require (probe.requirements == #[
      {
        capability := .eventsEmit
        operation := .builtin "emit-configured"
        source? := none
        metadata := #[{ key := "event", value := "Configured" }]
      },
      ProofForge.Target.CapabilityCall.fromCapability .dataStruct,
      ProofForge.Target.CapabilityCall.fromCapability .storageScalar,
      ProofForge.Target.CapabilityCall.fromCapability .storageMap,
      ProofForge.Target.CapabilityCall.fromCapability .eventsEmit,
      ProofForge.Target.CapabilityCall.fromCapability .assertions
    ]) "canonical capability requirement union changed"
  require (probe.requirements == ProofForge.IR.Canonical.deriveCapabilityRequirements
      probe.module probe.materialization)
    "requirements were not derived from canonical payload"
  require (probeBundle.evidence.intentSources == #[{
    intentIndex := 0, source := "EnvelopeProbe.lean:42"
  }]) "intent source evidence changed"
  require (probeBundle.evidence.verification.quintInvariants == #[{
    name := "label_nonempty", body := "labelLength > 0"
  }]) "Quint invariant body changed"
  require (probeBundle.evidence.verification.quintLiveness == #[{
    name := "eventually_configured", body := "eventually configured"
  }]) "Quint liveness body changed"
  require (probeBundle.evidence.verification.leanInvariants == #[{
    name := "label_bound", body := "Envelope.labelBound"
  }]) "Lean invariant body changed"

  let structBundle ← match adaptLegacy (ContractSpec.fromIR structReferenceModule) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"named struct reference adapt failed: {repr e}"
  let structContract := structBundle.contract.contract
  let boxLayout ← match structContract.materialization.typeLayouts.find? (·.name == "Box") with
    | some layout => pure layout
    | none => throw <| IO.userError "Box layout missing"
  let storedState ← match structContract.module.state.find? (·.id == ⟨0⟩) with
    | some state => pure state
    | none => throw <| IO.userError "stored struct state missing"
  match storedState.shape with
  | .scalar (.structType typeId) =>
      require (typeId == boxLayout.typeId) "state struct TypeId diverged from layout"
  | shape => throw <| IO.userError s!"named struct state changed shape: {repr shape}"
  let echoFunction ← match structContract.module.functions.find? (·.id == ⟨0⟩) with
    | some function => pure function
    | none => throw <| IO.userError "echo Core function missing"
  require (echoFunction.params.map (·.type) == #[.structType boxLayout.typeId] &&
      echoFunction.retType == .structType boxLayout.typeId)
    "function param/return struct TypeId was not resolved"
  let echoInterface ← match structContract.interface.entrypoints.find? (·.functionId == ⟨0⟩) with
    | some entrypoint => pure entrypoint
    | none => throw <| IO.userError "echo interface entrypoint missing"
  require (echoInterface.params.map (·.type) == #[.structType boxLayout.typeId])
    "interface struct TypeId diverged from Core"

  -- Literal range rejection before numeric narrowing.
  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u8 256)) with
  | .error (.literalOutOfRange "u8" _) => pure ()
  | .error e => throw <| IO.userError s!"u8 256 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u8 256 should have rejected"

  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u32 4294967296)) with
  | .error (.literalOutOfRange "u32" _) => pure ()
  | .error e => throw <| IO.userError s!"u32 2^32 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u32 2^32 should have rejected"

  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u64 18446744073709551616)) with
  | .error (.literalOutOfRange "u64" _) => pure ()
  | .error e => throw <| IO.userError s!"u64 2^64 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u64 2^64 should have rejected"

  match adaptLegacy (ContractSpec.fromIR (outOfRangeModule .u128 340282366920938463463374607431768211456)) with
  | .error (.literalOutOfRange "u128" _) => pure ()
  | .error e => throw <| IO.userError s!"u128 2^128 wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "u128 2^128 should have rejected"

  -- Unknown state name returns `unknownState`, never state zero.
  match adaptLegacy (ContractSpec.fromIR unknownStateModule) with
  | .error (.unknownState "missing") => pure ()
  | .error e => throw <| IO.userError s!"unknown state wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "unknown state should have rejected"

  match adaptLegacy (ContractSpec.fromIR mismatchedLetModule) with
  | .error (.typeMismatch _ _) => pure ()
  | .error e => throw <| IO.userError s!"mismatched let wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "mismatched let type should have rejected"

  let ifBundle ← match adaptLegacy (ContractSpec.fromIR ifElseModule) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"ifElse adapt failed: {repr e}"
  let ifFunction := ifBundle.contract.contract.module.functions.find? (·.id == ⟨0⟩)
  require (ifFunction.map (·.blocks.size) == some 4) "ifElse did not retain entry/branches/continuation"

  let loopBundle ← match adaptLegacy (ContractSpec.fromIR boundedForModule) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"boundedFor adapt failed: {repr e}"
  require (hasBoundedBackedge loopBundle.contract.contract.module)
    "boundedFor did not retain its atMost bound"

  let errorBundle ← match adaptLegacy (ContractSpec.fromIR structuredErrorModule) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"structured error adapt failed: {repr e}"
  require (hasErrorCode errorBundle.contract.contract.module 7)
    "structured ErrorRef assertionId was not preserved"

  let boolEventBundle ← match adaptLegacy (ContractSpec.fromIR boolEventModule) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"bool event adapt failed: {repr e}"
  match boolEventBundle.contract.contract.module.events.find? (·.id == ⟨0⟩) with
  | some event =>
      require (event.fields.map (·.type) == #[.bool]) "bool event schema was not inferred"
  | none => throw <| IO.userError "bool event declaration missing"
  match boolEventBundle.contract.contract.interface.events.find? (·.eventId == ⟨0⟩) with
  | some event =>
      require (event.name == "Flag") "bool event name was not preserved"
      require (event.fields.map (·.name) == #["enabled"]) "bool event field name was not preserved"
      require (event.fields.map (·.indexed) == #[false]) "bool event indexed flag changed"
  | none => throw <| IO.userError "bool event interface schema missing"

  let nestedBundle ← match adaptLegacy (ContractSpec.fromIR nestedTerminatingIfModule) with
    | .ok bundle => pure bundle
    | .error e => throw <| IO.userError s!"nested terminating if adapt failed: {repr e}"
  require (returnCount nestedBundle.contract.contract.module == 3)
    "nested terminating branches were not retained"

  match adaptLegacy (ContractSpec.fromIR conditionalLocalMutationModule) with
  | .error (.unsupportedConstructor "Statement.ifElse" _) => pure ()
  | .error e => throw <| IO.userError s!"conditional local mutation wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "conditional local mutation was silently accepted"

  match adaptLegacy (ContractSpec.fromIR loopLocalMutationModule) with
  | .error (.unsupportedConstructor "Statement.boundedFor" _) => pure ()
  | .error e => throw <| IO.userError s!"loop local mutation wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "loop-carried local mutation was silently accepted"

  match adaptLegacy (ContractSpec.fromIR releaseModule) with
  | .error (.unsupportedConstructor "Statement.release" _) => pure ()
  | .error e => throw <| IO.userError s!"release wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "release was silently lowered to a no-op"

  match adaptLegacy (ContractSpec.fromIR conflictingEventModule) with
  | .error (.conflictingEventSchema "Conflict" _) => pure ()
  | .error e => throw <| IO.userError s!"conflicting event schema wrong error: {repr e}"
  | .ok _ => throw <| IO.userError "conflicting event schema was silently accepted"

  match adaptLegacy (ContractSpec.fromIR duplicateEntrypointModule) with
  | .error (.validation error) =>
      require (error.tag == .duplicateId) "structured validation error tag changed"
  | .error e => throw <| IO.userError s!"duplicate entrypoint lost validation error: {repr e}"
  | .ok _ => throw <| IO.userError "duplicate entrypoint unexpectedly validated"

end Tests.Canonical.LegacyAdapter

def main : IO UInt32 := do
  Tests.Canonical.LegacyAdapter.runAssertions
  IO.println "Tests.Canonical.LegacyAdapter: ok"
  return 0
