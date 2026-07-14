import ProofForge.Frontend.Authored.Classification
import Lean

open ProofForge.Frontend.Authored
open Lean Elab Term

private def elabStringArray (values : Array String) : TermElabM Expr := do
  let items := values.map Syntax.mkStrLit
  let stx ← `(#[ $[$items],* ])
  elabTerm stx none

syntax "reflectedCtorTags% " ident : term

elab_rules : term
  | `(reflectedCtorTags% $typeStx:ident) => do
      let typeName ← resolveGlobalConstNoOverload typeStx
      let env ← getEnv
      match env.find? typeName with
      | some (.inductInfo info) =>
          elabStringArray <| info.ctors.toArray.map fun ctor =>
            s!"{typeName.getString!}.{ctor.getString!}"
      | _ => throwError "expected inductive type {typeName}"

syntax "reflectedFieldTags% " ident : term

elab_rules : term
  | `(reflectedFieldTags% $typeStx:ident) => do
      let typeName ← resolveGlobalConstNoOverload typeStx
      let fields := getStructureFields (← getEnv) typeName
      elabStringArray <| fields.map fun field =>
        s!"{typeName.getString!}.{field.getString!}"

syntax "reflectedFieldNames% " ident : term

elab_rules : term
  | `(reflectedFieldNames% $typeStx:ident) => do
      let typeName ← resolveGlobalConstNoOverload typeStx
      elabStringArray <| (getStructureFields (← getEnv) typeName).map Name.getString!

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def nonBlank (s : String) : Bool :=
  s.any (fun c => !c.isWhitespace)

def isUnique (xs : Array String) : Bool :=
  Id.run do
    for i in [0:xs.size] do
      for j in [i+1:xs.size] do
        if xs[i]! == xs[j]! then
          return false
    return true

def requireDecisions (label : String) (decisions : Array NormalizationDecision)
    (expectedTags : Array String) : IO Unit := do
  let tags := decisions.map (·.nodeTag)
  require (tags == expectedTags) s!"{label} classification inventory drift: {repr tags} != {repr expectedTags}"
  require (decisions.all fun decision => nonBlank decision.nodeTag)
    s!"{label} decision without node tag"
  require (decisions.all fun decision => nonBlank decision.reason)
    s!"{label} decision without reason"
  require (decisions.all fun decision => nonBlank decision.owner)
    s!"{label} decision without owner"
  require (isUnique tags) s!"duplicate {label} decision tag"

def emptyLegacyModule : ProofForge.IR.Module := {
  name := "LegacyInventory"
  state := #[]
  entrypoints := #[]
}

def main : IO Unit := do
  requireDecisions "ValueType" (valueTypeInventory.map classifyValueType)
    (reflectedCtorTags% ProofForge.IR.ValueType)
  requireDecisions "Literal" (literalInventory.map classifyLiteral)
    (reflectedCtorTags% ProofForge.IR.Literal)
  requireDecisions "AssignOp" (assignOpInventory.map classifyAssignOp)
    (reflectedCtorTags% ProofForge.IR.AssignOp)
  requireDecisions "StoragePathSegment"
    (storagePathSegmentInventory.map classifyStoragePathSegment)
    (reflectedCtorTags% ProofForge.IR.StoragePathSegment)
  requireDecisions "ContextField" (contextFieldInventory.map classifyContextField)
    (reflectedCtorTags% ProofForge.IR.ContextField)
  requireDecisions "EntrypointKind" (entrypointKindInventory.map classifyEntrypointKind)
    (reflectedCtorTags% ProofForge.IR.EntrypointKind)
  requireDecisions "EntrypointMutability"
    (entrypointMutabilityInventory.map classifyEntrypointMutability)
    (reflectedCtorTags% ProofForge.IR.EntrypointMutability)
  requireDecisions "StateKind" (stateKindInventory.map classifyStateKind)
    (reflectedCtorTags% ProofForge.IR.StateKind)
  requireDecisions "StateKind payload"
    (stateKindInventory.flatMap classifyStateKindPayload) #[
      "StateKind.map.keyType", "StateKind.map.capacity", "StateKind.array.length"
    ]
  requireDecisions "StructSemantics" (structSemanticsInventory.map classifyStructSemantics)
    (reflectedCtorTags% ProofForge.IR.StructSemantics)
  requireDecisions "AllocatorStrategy"
    (allocatorStrategyInventory.map classifyAllocatorStrategy)
    (reflectedCtorTags% ProofForge.IR.AllocatorStrategy)
  requireDecisions "AllocatorRelease"
    (allocatorReleaseInventory.map classifyAllocatorRelease)
    (reflectedCtorTags% ProofForge.IR.AllocatorRelease)
  requireDecisions "ConstructorInitKind"
    (constructorInitKindInventory.map classifyConstructorInitKind)
    (reflectedCtorTags% ProofForge.Contract.ConstructorInitKind)
  requireDecisions "IntentKind" (intentKindInventory.map classifyIntentKind)
    (reflectedCtorTags% ProofForge.Contract.IntentKind)
  requireDecisions "UpgradePolicy" (upgradePolicyInventory.map classifyUpgradePolicy)
    (reflectedCtorTags% ProofForge.Contract.UpgradePolicy)
  requireDecisions "UpgradePolicy payload"
    (upgradePolicyInventory.flatMap classifyUpgradePolicyPayload) #[
      "UpgradePolicy.authority.keyRef", "UpgradePolicy.governance.ref"
    ]
  requireDecisions "ProxyPattern" (proxyPatternInventory.map classifyProxyPattern)
    (reflectedCtorTags% ProofForge.Contract.ProxyPattern)
  requireDecisions "Expr" (exprInventory.map classifyExpr)
    (reflectedCtorTags% ProofForge.IR.Expr)
  requireDecisions "Effect" (effectInventory.map classifyEffect)
    (reflectedCtorTags% ProofForge.IR.Effect)
  requireDecisions "Statement" (statementInventory.map classifyStatement)
    (reflectedCtorTags% ProofForge.IR.Statement)

  requireDecisions "StructField fields" (classifyStructFieldFields {
      id := "field", type := .u64, isPublic := true, isRef := false })
    (reflectedFieldTags% ProofForge.IR.StructField)
  requireDecisions "StructDecl fields" (classifyStructDeclFields {
      name := "S", fields := #[], deriveStorage := false,
      isPublic := true, isRecord := false })
    (reflectedFieldTags% ProofForge.IR.StructDecl)
  requireDecisions "StateDecl fields" (classifyStateDeclFields {
      id := "state", kind := .scalar, type := .u64 })
    (reflectedFieldTags% ProofForge.IR.StateDecl)
  requireDecisions "ErrorRef fields" (classifyErrorRefFields {
      assertionId := 0 })
    (reflectedFieldTags% ProofForge.IR.ErrorRef)
  requireDecisions "Entrypoint fields" (classifyEntrypointFields {
      name := "run", body := #[] })
    (reflectedFieldTags% ProofForge.IR.Entrypoint)
  requireDecisions "EventAbiWord fields" (classifyEventAbiWordFields {
      eventName := "E", fieldName := "value", abiWord := "uint64" })
    (reflectedFieldTags% ProofForge.IR.EventAbiWord)
  let moduleDecisions := classifyModuleFields emptyLegacyModule
  requireDecisions "Module fields" moduleDecisions
    (reflectedFieldTags% ProofForge.IR.Module)
  require (moduleDecisions.any fun decision =>
      decision.disposition == .materialization)
    "Module classification masks target materialization fields"
  requireDecisions "AllocatorRegion fields" (classifyAllocatorRegionFields {})
    (reflectedFieldTags% ProofForge.IR.AllocatorRegion)
  requireDecisions "AllocatorModel fields"
    (classifyAllocatorModelFields ProofForge.IR.defaultAllocator.model)
    (reflectedFieldTags% ProofForge.IR.AllocatorModel)
  requireDecisions "AllocatorConfig fields"
    (classifyAllocatorConfigFields ProofForge.IR.defaultAllocator)
    (reflectedFieldTags% ProofForge.IR.AllocatorConfig)
  requireDecisions "ConstructorParam fields" (classifyConstructorParamFields {
      name := "owner", abiType := "address" })
    (reflectedFieldTags% ProofForge.Contract.ConstructorParam)
  requireDecisions "ConstructorInitBinding fields" (classifyConstructorInitBindingFields {
      stateId := "owner", paramName := "owner", kind := .addressWord })
    (reflectedFieldTags% ProofForge.Contract.ConstructorInitBinding)
  requireDecisions "Intent fields" (classifyIntentFields {
      kind := .module, label := "LegacyInventory" })
    (reflectedFieldTags% ProofForge.Contract.Intent)

  require (allDecisions.all fun decision => nonBlank decision.nodeTag)
    "legacy decision without node tag"
  require (allDecisions.all fun decision => nonBlank decision.reason)
    "legacy decision without reason"
  require (allDecisions.all fun decision => nonBlank decision.owner)
    "legacy decision without owner"
  require (isUnique allNodeTags)
    "duplicate legacy node tag"

  let spec := ProofForge.Contract.ContractSpec.fromIR emptyLegacyModule
  let fieldDecisions := classifySpecFields spec
  require (fieldDecisions.map (·.field) ==
      (reflectedFieldNames% ProofForge.Contract.ContractSpec))
    "ContractSpec field inventory drift"
  require (fieldDecisions.all fun decision => nonBlank decision.field)
    "ContractSpec decision without field name"
  require (fieldDecisions.all fun decision => nonBlank decision.reason)
    "ContractSpec decision without reason"
  require (fieldDecisions.all fun decision => nonBlank decision.owner)
    "ContractSpec decision without owner"
  require (isUnique (fieldDecisions.map (·.field)))
    "duplicate ContractSpec field decision"
  require (fieldDecisions.any fun decision =>
      decision.field == "module" && decision.disposition == .normalize)
    "ContractSpec.module must defer to field-by-field Module classification"
  IO.println "canonical-legacy-inventory: ok"
