import ProofForge.IR.Contract

namespace ProofForge.Backend.WasmHost.AbiPlan

open ProofForge.IR

inductive Codec where
  | borsh
  | json
  deriving Repr, BEq

def Codec.id : Codec -> String
  | .borsh => "borsh"
  | .json => "json"

/-- A flat JSON schema graph keeps target-wire concerns out of portable
`ValueType`. Object fields and container elements refer to nodes by id, so the
plan can represent nested structs, arrays, and optional fields without a
recursive runtime value type. -/
inductive JsonNodeKind where
  | unit
  | bool
  | number
  | decimalString
  | string
  | fixedArray
  | array
  | object
  | optional
  deriving Repr, BEq

def JsonNodeKind.id : JsonNodeKind → String
  | .unit => "unit"
  | .bool => "bool"
  | .number => "number"
  | .decimalString => "decimal-string"
  | .string => "string"
  | .fixedArray => "fixed-array"
  | .array => "array"
  | .object => "object"
  | .optional => "optional"

structure JsonFieldPlan where
  wireName : String
  sourceName? : Option String := none
  nodeId : Nat
  required : Bool := true
  deriving Repr, BEq

structure JsonNodePlan where
  id : Nat
  kind : JsonNodeKind
  valueType? : Option ValueType := none
  fields : Array JsonFieldPlan := #[]
  elementNode? : Option Nat := none
  fixedLength? : Option Nat := none
  deriving Repr, BEq

structure JsonSchemaPlan where
  rootNode : Nat
  nodes : Array JsonNodePlan
  orderIndependent : Bool := false
  rejectUnknownFields : Bool := true
  deriving Repr, BEq

def JsonSchemaPlan.root? (schema : JsonSchemaPlan) : Option JsonNodePlan :=
  schema.nodes.find? (·.id == schema.rootNode)

def JsonSchemaPlan.validate (schema : JsonSchemaPlan) : Except String Unit := do
  unless schema.nodes.any (·.id == schema.rootNode) do
    throw s!"JSON schema root node {schema.rootNode} is missing"
  let mut seenIds : Array Nat := #[]
  for node in schema.nodes do
    if seenIds.contains node.id then
      throw s!"JSON schema node id {node.id} is duplicated"
    seenIds := seenIds.push node.id
    for field in node.fields do
      if field.wireName.isEmpty then
        throw s!"JSON schema object node {node.id} has an empty field name"
      unless schema.nodes.any (·.id == field.nodeId) do
        throw s!"JSON schema field `{field.wireName}` references missing node {field.nodeId}"
    match node.elementNode? with
    | some childId =>
        unless schema.nodes.any (·.id == childId) do
          throw s!"JSON schema node {node.id} references missing element node {childId}"
    | none => pure ()
    match node.kind with
    | .object =>
        if node.elementNode?.isSome || node.fixedLength?.isSome then
          throw s!"JSON object node {node.id} cannot carry element metadata"
        let mut seenNames : Array String := #[]
        for field in node.fields do
          if seenNames.contains field.wireName then
            throw s!"JSON object node {node.id} duplicates field `{field.wireName}`"
          seenNames := seenNames.push field.wireName
    | .fixedArray =>
        unless node.elementNode?.isSome && node.fixedLength?.isSome do
          throw s!"JSON fixed-array node {node.id} requires element and length metadata"
        unless node.fields.isEmpty do
          throw s!"JSON fixed-array node {node.id} cannot carry object fields"
    | .array | .optional =>
        unless node.elementNode?.isSome do
          throw s!"JSON {node.kind.id} node {node.id} requires an element node"
        unless node.fields.isEmpty && node.fixedLength?.isNone do
          throw s!"JSON {node.kind.id} node {node.id} has invalid container metadata"
    | _ =>
        unless node.fields.isEmpty && node.elementNode?.isNone && node.fixedLength?.isNone do
          throw s!"JSON scalar node {node.id} has container metadata"

/-- Wrap one root-object field in an optional wire node. Optionality belongs to
the target ABI schema rather than portable `ValueType`; the target adapter can
map missing/`null` to its chosen carrier convention. -/
def JsonSchemaPlan.withOptionalRootField (schema : JsonSchemaPlan)
    (wireName : String) : Except String JsonSchemaPlan := do
  let some root := schema.root?
    | throw s!"JSON schema root node {schema.rootNode} is missing"
  unless root.kind == .object do
    throw "JSON schema optional root fields require an object root"
  let some field := root.fields.find? (·.wireName == wireName)
    | throw s!"JSON schema root has no field `{wireName}`"
  let optionalId := schema.nodes.foldl (fun next node => max next (node.id + 1)) 0
  let optionalNode : JsonNodePlan := {
    id := optionalId
    kind := .optional
    elementNode? := some field.nodeId
  }
  let updatedRoot := { root with fields := root.fields.map fun candidate =>
    if candidate.wireName == wireName then
      { candidate with nodeId := optionalId, required := false }
    else candidate }
  let nodes := schema.nodes.map fun node =>
    if node.id == schema.rootNode then updatedRoot else node
  let result := { schema with nodes := nodes.push optionalNode }
  result.validate
  pure result

structure ValuePlan where
  name? : Option String := none
  type : ValueType
  offset : Nat
  byteWidth : Nat
  deriving Repr, BEq

structure EntrypointPlan where
  name : String
  inputCodec : Codec
  outputCodec : Codec
  params : Array ValuePlan
  inputByteWidth : Nat
  returnType : ValueType
  outputByteWidth : Nat
  inputJson? : Option JsonSchemaPlan := none
  outputJson? : Option JsonSchemaPlan := none
  deriving Repr, BEq

end ProofForge.Backend.WasmHost.AbiPlan
