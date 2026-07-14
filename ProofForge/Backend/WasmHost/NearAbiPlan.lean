/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.WasmHost.AbiPlan
import ProofForge.Backend.WasmHost.StructPlan

namespace ProofForge.Backend.WasmHost.NearAbiPlan

open ProofForge.IR

abbrev Codec := ProofForge.Backend.WasmHost.AbiPlan.Codec
abbrev ValuePlan := ProofForge.Backend.WasmHost.AbiPlan.ValuePlan
abbrev EntrypointPlan := ProofForge.Backend.WasmHost.AbiPlan.EntrypointPlan
abbrev JsonNodeKind := ProofForge.Backend.WasmHost.AbiPlan.JsonNodeKind
abbrev JsonFieldPlan := ProofForge.Backend.WasmHost.AbiPlan.JsonFieldPlan
abbrev JsonNodePlan := ProofForge.Backend.WasmHost.AbiPlan.JsonNodePlan
abbrev JsonSchemaPlan := ProofForge.Backend.WasmHost.AbiPlan.JsonSchemaPlan

partial def borshByteWidth (structs : Array StructDecl) : ValueType → Except String Nat
  | .unit => .ok 0
  | .bool | .u8 => .ok 1
  | .u32 => .ok 4
  | .u64 | .address => .ok 8
  | .u128 => .ok 16
  | .hash => .ok 32
  | .string | .bytes => .ok 260
  | .fixedArray element length => return (← borshByteWidth structs element) * length
  | .structType name => do
      let some decl := structs.find? (fun decl => decl.name == name)
        | .error s!"NEAR ABI references unknown struct `{name}`"
      let mut size := 0
      for field in decl.fields do
        size := size + (← borshByteWidth structs field.type)
      .ok size
  | type => .error s!"NEAR Borsh ABI does not support dynamic `{type.name}` values"

partial def appendJsonValueSchema (structs : Array StructDecl) (type : ValueType)
    (nodes : Array JsonNodePlan) : Except String (Nat × Array JsonNodePlan) := do
  let appendLeaf (kind : JsonNodeKind) : Nat × Array JsonNodePlan :=
    let id := nodes.size
    (id, nodes.push { id, kind, valueType? := some type })
  match type with
  | .unit => return appendLeaf .unit
  | .bool => return appendLeaf .bool
  | .u8 | .u32 | .u64 | .address => return appendLeaf .number
  | .u128 => return appendLeaf .decimalString
  | .string | .bytes | .hash => return appendLeaf .string
  | .fixedArray element length =>
      let (elementId, nodes) ← appendJsonValueSchema structs element nodes
      let id := nodes.size
      return (id, nodes.push {
        id, kind := .fixedArray, valueType? := some type,
        elementNode? := some elementId, fixedLength? := some length })
  | .array element =>
      let (elementId, nodes) ← appendJsonValueSchema structs element nodes
      let id := nodes.size
      return (id, nodes.push {
        id, kind := .array, valueType? := some type, elementNode? := some elementId })
  | .structType name =>
      let some decl := structs.find? (·.name == name)
        | throw s!"NEAR JSON ABI references unknown struct `{name}`"
      let mut nodes := nodes
      let mut fields := #[]
      for field in decl.fields do
        let (nodeId, nextNodes) ← appendJsonValueSchema structs field.type nodes
        nodes := nextNodes
        fields := fields.push {
          wireName := field.id, sourceName? := some field.id, nodeId, required := true }
      let id := nodes.size
      return (id, nodes.push {
        id, kind := .object, valueType? := some type, fields })

def buildJsonObjectSchema (structs : Array StructDecl)
    (params : Array (String × ValueType)) : Except String JsonSchemaPlan := do
  let mut nodes := #[]
  let mut fields := #[]
  for param in params do
    let (nodeId, nextNodes) ← appendJsonValueSchema structs param.snd nodes
    nodes := nextNodes
    fields := fields.push {
      wireName := param.fst, sourceName? := some param.fst, nodeId, required := true }
  let rootNode := nodes.size
  nodes := nodes.push { id := rootNode, kind := .object, fields }
  return { rootNode, nodes, orderIndependent := true, rejectUnknownFields := true }

def buildJsonValueSchema (structs : Array StructDecl) (type : ValueType) :
    Except String JsonSchemaPlan := do
  let (rootNode, nodes) ← appendJsonValueSchema structs type #[]
  return { rootNode, nodes }

def withOptionalRoot (schema : JsonSchemaPlan) : Except String JsonSchemaPlan := do
  let optionalId := schema.nodes.foldl (fun next node => max next (node.id + 1)) 0
  let result : JsonSchemaPlan := {
    schema with
    rootNode := optionalId
    nodes := schema.nodes.push {
      id := optionalId
      kind := .optional
      elementNode? := some schema.rootNode
    }
  }
  result.validate
  pure result

/-- Wallet-compatible JSON selection plus its explicit wire schemas. Contract
lowering and generated clients consume this single target ABI decision. -/
def jsonSchemasForSignature (structs : Array StructDecl) (name : String)
    (params : Array (String × ValueType)) (returns : ValueType) :
    Except String (Option JsonSchemaPlan × Option JsonSchemaPlan) := do
  if name == "ft_total_supply" then
    unless params.isEmpty && returns == .u128 do
      throw "NEAR standard entrypoint `ft_total_supply` must have signature () -> U128"
    return (some (← buildJsonObjectSchema structs params),
      some (← buildJsonValueSchema structs returns))
  if name == "ft_balance_of" then
    unless params == #[("account_id", .string)] && returns == .u128 do
      throw "NEAR standard entrypoint `ft_balance_of` must have signature (account_id : String) -> U128"
    return (some (← buildJsonObjectSchema structs params),
      some (← buildJsonValueSchema structs returns))
  if name == "ft_metadata" then
    unless params.isEmpty && returns == .structType "FungibleTokenMetadata" do
      throw "NEAR standard entrypoint `ft_metadata` must have signature () -> FungibleTokenMetadata"
    return (some (← buildJsonObjectSchema structs params),
      some (← buildJsonValueSchema structs returns))
  if name == "ft_transfer" then
    unless params == #[("receiver_id", .string), ("amount", .u128), ("memo", .string)] &&
        returns == .unit do
      throw "NEAR standard entrypoint `ft_transfer` must have signature (receiver_id : String, amount : U128, memo : Option<String>) -> Unit"
    let schema ← buildJsonObjectSchema structs params
    return (some (← schema.withOptionalRootField "memo"), none)
  if name == "ft_transfer_call" then
    unless params == #[("receiver_id", .string), ("amount", .u128), ("memo", .string),
        ("msg", .string)] && returns == .u64 do
      throw "NEAR standard entrypoint `ft_transfer_call` must have signature (receiver_id : String, amount : U128, memo : Option<String>, msg : String) -> Promise<U128>"
    let schema ← buildJsonObjectSchema structs params
    return (some (← schema.withOptionalRootField "memo"), none)
  if name == "ft_resolve_transfer" then
    unless params == #[("transfer_id", .u64), ("sender", .string), ("receiver", .string)] &&
        returns == .u128 do
      throw "NEAR private callback `ft_resolve_transfer` must have signature (transfer_id : U64, sender : String, receiver : String) -> U128"
    return (some (← buildJsonObjectSchema structs params),
      some (← buildJsonValueSchema structs returns))
  if name == "storage_balance_bounds" then
    unless params.isEmpty && returns == .structType "StorageBalanceBounds" do
      throw "NEAR standard entrypoint `storage_balance_bounds` must have signature () -> StorageBalanceBounds"
    let output ← buildJsonValueSchema structs returns
    return (some (← buildJsonObjectSchema structs params),
      some (← output.withOptionalRootField "max"))
  if name == "storage_balance_of" then
    unless params == #[("account_id", .string)] && returns == .structType "StorageBalance" do
      throw "NEAR standard entrypoint `storage_balance_of` must have signature (account_id : String) -> Option<StorageBalance>"
    return (some (← buildJsonObjectSchema structs params),
      some (← withOptionalRoot (← buildJsonValueSchema structs returns)))
  if name == "storage_deposit" then
    unless params == #[("account_id", .string), ("registration_only", .bool)] &&
        returns == .structType "StorageBalance" do
      throw "NEAR standard entrypoint `storage_deposit` must have signature (account_id : Option<String>, registration_only : Option<Bool>) -> StorageBalance"
    let input ← buildJsonObjectSchema structs params
    let input ← input.withOptionalRootField "account_id"
    let input ← input.withOptionalRootField "registration_only"
    return (some input, some (← buildJsonValueSchema structs returns))
  if name == "storage_withdraw" then
    unless params == #[("amount", .u128)] && returns == .structType "StorageBalance" do
      throw "NEAR standard entrypoint `storage_withdraw` must have signature (amount : Option<U128>) -> StorageBalance"
    let input ← buildJsonObjectSchema structs params
    return (some (← input.withOptionalRootField "amount"),
      some (← buildJsonValueSchema structs returns))
  if name == "storage_unregister" then
    unless params == #[("force", .bool)] && returns == .bool do
      throw "NEAR standard entrypoint `storage_unregister` must have signature (force : Option<Bool>) -> Bool"
    let input ← buildJsonObjectSchema structs params
    return (some (← input.withOptionalRootField "force"),
      some (← buildJsonValueSchema structs returns))
  return (none, none)

def buildSignaturePlan (structs : Array StructDecl) (name : String)
    (signatureParams : Array (String × ValueType)) (returns : ValueType) :
    Except String EntrypointPlan := do
  let (inputJson?, outputJson?) ←
    jsonSchemasForSignature structs name signatureParams returns
  match inputJson? with
  | some schema => schema.validate
  | none => pure ()
  match outputJson? with
  | some schema => schema.validate
  | none => pure ()
  let useJsonInput := inputJson?.isSome
  let useJsonOutput := outputJson?.isSome
  let inputCodec : ProofForge.Backend.WasmHost.AbiPlan.Codec :=
    if useJsonInput then .json else .borsh
  let outputCodec : ProofForge.Backend.WasmHost.AbiPlan.Codec :=
    if useJsonOutput then .json else .borsh
  let mut offset := 0
  let mut params := #[]
  for param in signatureParams do
    let width ← if useJsonInput then pure 0 else borshByteWidth structs param.snd
    params := params.push { name? := some param.fst, type := param.snd, offset, byteWidth := width }
    offset := offset + width
  let outputByteWidth ← if useJsonOutput then pure 0 else borshByteWidth structs returns
  .ok {
    name
    inputCodec
    outputCodec
    params
    inputByteWidth := offset
    returnType := returns
    outputByteWidth
    inputJson?
    outputJson?
  }

def buildSignaturePlanFromStructPlans
    (structs : Array ProofForge.Backend.WasmHost.StructPlan.Struct) (name : String)
    (signatureParams : Array (String × ValueType)) (returns : ValueType) :
    Except String EntrypointPlan :=
  buildSignaturePlan (structs.map ProofForge.Backend.WasmHost.StructPlan.toIR)
    name signatureParams returns

def buildEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint) :
    Except String EntrypointPlan :=
  buildSignaturePlan structs entrypoint.name entrypoint.params entrypoint.returns

def buildModulePlans (module : Module) : Except String (Array EntrypointPlan) :=
  module.entrypoints.mapM (buildEntrypointPlan module.structs)

def validateEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint)
    (plan : EntrypointPlan) : Except String Unit := do
  let expected <- buildEntrypointPlan structs entrypoint
  if plan != expected then
    .error s!"NEAR ABI plan for entrypoint `{entrypoint.name}` does not match its signature"
  .ok ()

end ProofForge.Backend.WasmHost.NearAbiPlan
