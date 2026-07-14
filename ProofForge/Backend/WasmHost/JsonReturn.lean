/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.AbiPlan
import ProofForge.Backend.WasmHost.StructPlan
import ProofForge.Backend.WasmHost.Aggregate
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types

namespace ProofForge.Backend.WasmHost.JsonReturn

open ProofForge.Compiler.Wasm
open ProofForge.IR
open ProofForge.Backend.WasmHost.AbiPlan
open ProofForge.Backend.WasmHost.Aggregate
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Event
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Scalar
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

def ptrGlobal : String := "__pf_json_return_ptr"
def startName : String := "__pf_json_return_start"
def putByteName : String := "__pf_json_return_put_byte"
def putRawName : String := "__pf_json_return_put_raw"
def putStringName : String := "__pf_json_return_put_string"
def putControlName : String := "__pf_json_return_put_control"
def putU64Name : String := "__pf_json_return_put_u64"
def putU128Name : String := "__pf_json_return_put_u128"
def putBoolName : String := "__pf_json_return_put_bool"
def finishName : String := "__pf_json_return_finish"

def ptrGlobalDecl : Global :=
  { name := ptrGlobal, type := .i32, init := toString JSON_RET_BUF, isMutable := true }

def assertCapacity : Array Insn := #[
  .globalGet ptrGlobal, .i32Const JSON_RET_BUF, .plain "i32.sub",
  .i32Const JSON_RET_CAP, .plain "i32.ge_u",
  .if_ { insns := #[.unreachable] } { insns := #[] }
]

def startFunc : Func :=
  { name := startName
    body := { insns := #[.i32Const JSON_RET_BUF, .globalSet ptrGlobal] } }

def putByteFunc : Func :=
  { name := putByteName
    params := #[{ name := "byte", type := .i32 }]
    body := { insns := assertCapacity ++ #[
      .globalGet ptrGlobal, .localGet "byte", .store "i32.store8" 0,
      .globalGet ptrGlobal, .i32Const 1, .plain "i32.add", .globalSet ptrGlobal
    ] } }

def putRawFunc : Func :=
  { name := putRawName
    params := #[{ name := "p", type := .i32 }, { name := "n", type := .i32 }]
    body := { insns := #[
      .globalGet ptrGlobal, .i32Const JSON_RET_BUF, .plain "i32.sub",
      .localGet "n", .plain "i32.add", .i32Const JSON_RET_CAP, .plain "i32.gt_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .globalGet ptrGlobal, .localGet "p", .localGet "n", .call memcpyName,
      .globalGet ptrGlobal, .localGet "n", .plain "i32.add", .globalSet ptrGlobal
    ] } }

def putControlFunc : Func :=
  { name := putControlName
    params := #[{ name := "b", type := .i32 }]
    body := { insns := #[
      .localGet "b", .i32Const 0x08, .plain "i32.eq",
      .if_ { insns := #[
        .i32Const 0x5c, .call putByteName, .i32Const 0x62, .call putByteName, .return_
      ] } { insns := #[] },
      .localGet "b", .i32Const 0x0c, .plain "i32.eq",
      .if_ { insns := #[
        .i32Const 0x5c, .call putByteName, .i32Const 0x66, .call putByteName, .return_
      ] } { insns := #[] },
      .localGet "b", .i32Const 0x0a, .plain "i32.eq",
      .if_ { insns := #[
        .i32Const 0x5c, .call putByteName, .i32Const 0x6e, .call putByteName, .return_
      ] } { insns := #[] },
      .localGet "b", .i32Const 0x0d, .plain "i32.eq",
      .if_ { insns := #[
        .i32Const 0x5c, .call putByteName, .i32Const 0x72, .call putByteName, .return_
      ] } { insns := #[] },
      .localGet "b", .i32Const 0x09, .plain "i32.eq",
      .if_ { insns := #[
        .i32Const 0x5c, .call putByteName, .i32Const 0x74, .call putByteName, .return_
      ] } { insns := #[] },
      .i32Const 0x5c, .call putByteName, .i32Const 0x75, .call putByteName,
      .i32Const 0x30, .call putByteName, .i32Const 0x30, .call putByteName,
      .i32Const HEX_LUT_PTR, .localGet "b", .i32Const 4, .plain "i32.shr_u",
      .plain "i32.add", .load "i32.load8_u" 0, .call putByteName,
      .i32Const HEX_LUT_PTR, .localGet "b", .i32Const 0x0f, .plain "i32.and",
      .plain "i32.add", .load "i32.load8_u" 0, .call putByteName
    ] } }

def putStringFunc : Func :=
  { name := putStringName
    params := #[{ name := "p", type := .i32 }, { name := "n", type := .i32 }]
    locals := #[{ name := "i", type := .i32 }, { name := "b", type := .i32 }]
    body := { insns := #[
      .i32Const 0x22, .call putByteName,
      .i32Const 0, .localSet "i",
      .block_ { insns := #[.loop_ { insns := #[
        .localGet "i", .localGet "n", .plain "i32.ge_u", .brIf 1,
        .localGet "p", .localGet "i", .plain "i32.add",
        .load "i32.load8_u" 0, .localSet "b",
        .localGet "b", .i32Const 0x22, .plain "i32.eq",
        .if_ { insns := #[
          .i32Const 0x5c, .call putByteName, .i32Const 0x22, .call putByteName
        ] } { insns := #[
          .localGet "b", .i32Const 0x5c, .plain "i32.eq",
          .if_ { insns := #[
            .i32Const 0x5c, .call putByteName, .i32Const 0x5c, .call putByteName
          ] } { insns := #[
            .localGet "b", .i32Const 0x0a, .plain "i32.eq",
            .if_ { insns := #[
              .i32Const 0x5c, .call putByteName, .i32Const 0x6e, .call putByteName
            ] } { insns := #[
              .localGet "b", .i32Const 0x0d, .plain "i32.eq",
              .if_ { insns := #[
                .i32Const 0x5c, .call putByteName, .i32Const 0x72, .call putByteName
              ] } { insns := #[
                .localGet "b", .i32Const 0x09, .plain "i32.eq",
                .if_ { insns := #[
                  .i32Const 0x5c, .call putByteName, .i32Const 0x74, .call putByteName
                ] } { insns := #[
                  .localGet "b", .i32Const 0x20, .plain "i32.lt_u",
                  .if_ { insns := #[.localGet "b", .call putControlName] }
                    { insns := #[.localGet "b", .call putByteName] }
                ] }
              ] }
            ] }
          ] }
        ] },
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] }] },
      .i32Const 0x22, .call putByteName
    ] } }

def putU64Func : Func :=
  { name := putU64Name
    params := #[{ name := "value", type := .i64 }]
    locals := #[{ name := "p", type := .i32 }]
    body := { insns := #[
      .localGet "value", .call fmtU64Name, .localTee "p",
      .i32Const (RET_BUF + 20), .localGet "p", .plain "i32.sub", .call putRawName
    ] } }

def putU128Func : Func :=
  { name := putU128Name
    params := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 }]
    locals := #[{ name := "p", type := .i32 }]
    body := { insns := #[
      .i32Const 0x22, .call putByteName,
      .localGet "lo", .localGet "hi", .call u128FmtName, .localTee "p",
      .i32Const (RET_BUF + 40), .localGet "p", .plain "i32.sub", .call putRawName,
      .i32Const 0x22, .call putByteName
    ] } }

def putBoolFunc : Func :=
  { name := putBoolName
    params := #[{ name := "value", type := .i32 }]
    body := { insns := #[
      .localGet "value",
      .if_ { insns := #[.i32Const TRUE_PTR, .i32Const 4, .call putRawName] }
        { insns := #[.i32Const FALSE_PTR, .i32Const 5, .call putRawName] }
    ] } }

def finishFunc : Func :=
  { name := finishName
    body := { insns := #[
      .globalGet ptrGlobal, .i32Const JSON_RET_BUF, .plain "i32.sub",
      .plain "i64.extend_i32_u", .i64Const JSON_RET_BUF, .call "value_return"
    ] } }

def runtimeFuncs : Array Func := #[
  startFunc, putByteFunc, putRawFunc, putControlFunc, putStringFunc,
  putU64Func, putU128Func, putBoolFunc, finishFunc
]

def helperName (entrypoint : String) : String := "__pf_return_json_" ++ entrypoint

structure Access where
  insns : Array Insn
  type : ValueType
  memory : Bool := false

def staticJsonString (value : String) : Array Insn :=
  let bytes := value.toUTF8.data
  #[.i32Const 0x22, .call putByteName] ++
    bytes.foldl (init := #[]) (fun insns byte =>
      let value := byte.toNat
      if value == 0x22 || value == 0x5c then
        insns ++ #[.i32Const 0x5c, .call putByteName,
          .i32Const value, .call putByteName]
      else
        insns ++ #[.i32Const value, .call putByteName]) ++
    #[.i32Const 0x22, .call putByteName]

def staticBytes (value : String) : Array Insn :=
  value.toUTF8.data.foldl (init := #[]) fun insns byte =>
    insns ++ #[.i32Const byte.toNat, .call putByteName]

def loadAccess (access : Access) : Except String (Array Insn) :=
  if !access.memory then
    pure access.insns
  else match access.type with
    | .u128 => pure <|
        access.insns ++ #[.load "i64.load" 0] ++
        access.insns ++ #[.load "i64.load" 8]
    | .string | .bytes | .array _ =>
        pure <|
          access.insns ++ #[.load "i32.load" 0] ++
          access.insns ++ #[.load "i32.load" 4]
    | .hash => pure access.insns
    | .fixedArray _ _ | .structType _ =>
        pure <| access.insns ++ #[.load "i32.load" 0]
    | .u8 | .u32 | .bool => pure <| access.insns ++ #[.load (loadOpFor access.type) 0]
    | .u64 | .address => pure <| access.insns ++ #[.load "i64.load" 0]
    | .unit => throw "JSON return cannot load Unit from aggregate memory"

def accessIsAbsent (structs : Array StructPlan.Struct) (access : Access) : Except String (Array Insn) :=
  match access.type with
  | .string | .bytes | .array _ =>
      if access.memory then
        pure <| access.insns ++ #[.load "i32.load" 0, .plain "i32.eqz"]
      else
        pure <| access.insns ++ #[.drop, .plain "i32.eqz"]
  | .u128 => do
      pure <| (← loadAccess access) ++ #[.plain "i64.or", .plain "i64.eqz"]
  | .structType typeName => do
      let some decl := structs.find? (·.name == typeName)
        | throw s!"JSON optional carrier references unknown struct `{typeName}`"
      let some first := decl.fields[0]?
        | throw s!"JSON optional carrier struct `{typeName}` has no sentinel field"
      unless first.type == .u128 do
        throw s!"JSON optional carrier struct `{typeName}` must begin with U128 sentinel"
      let base ← loadAccess access
      pure <| base ++ #[.load "i64.load" 0] ++ base ++
        #[.load "i64.load" 8, .plain "i64.or", .plain "i64.eqz"]
  | _ => throw s!"JSON optional carrier `{access.type.name}` has no absence sentinel"

private def plannedStructFieldType? (plan : StructPlan.Struct)
    (fieldName : String) : Option ValueType :=
  (plan.fields.find? (·.id == fieldName)).map (·.type)

private def plannedStructFieldOffset? (plan : StructPlan.Struct)
    (fieldName : String) : Option Nat :=
  let rec go (index offset : Nat) : Option Nat :=
    if h : index < plan.fields.size then
      let field := plan.fields[index]
      if field.id == fieldName then some offset
      else go (index + 1) (offset + scalarWidth field.type)
    else none
  go 0 0

def structFieldAccess (structs : Array StructPlan.Struct) (base : Access)
    (field : JsonFieldPlan) : Except String Access := do
  let .structType typeName := base.type
    | throw s!"JSON object field `{field.wireName}` requires a struct carrier"
  let some decl := structs.find? (·.name == typeName)
    | throw s!"JSON return references unknown struct `{typeName}`"
  let sourceName := field.sourceName?.getD field.wireName
  let some fieldType := plannedStructFieldType? decl sourceName
    | throw s!"JSON schema field `{field.wireName}` references missing `{typeName}.{sourceName}`"
  let some offset := plannedStructFieldOffset? decl sourceName
    | throw s!"JSON schema field `{field.wireName}` has no offset in `{typeName}`"
  let baseInsns ← loadAccess base
  pure {
    insns := baseInsns ++ #[.i32Const offset, .plain "i32.add"]
    type := fieldType
    memory := true
  }

partial def emitNode (schema : JsonSchemaPlan) (structs : Array StructPlan.Struct)
    (nodeId : Nat) (access : Access) : Except String (Array Insn) := do
  let some node := schema.nodes.find? (·.id == nodeId)
    | throw s!"JSON return schema references missing node {nodeId}"
  match node.kind with
  | .unit => pure <| staticBytes "null"
  | .bool =>
      unless access.type == .bool do
        throw s!"JSON bool node {nodeId} cannot encode `{access.type.name}`"
      pure <| (← loadAccess access) ++ #[.call putBoolName]
  | .number =>
      let value ← loadAccess access
      match access.type with
      | .u8 | .u32 => pure <| value ++ #[.plain "i64.extend_i32_u", .call putU64Name]
      | .u64 | .address => pure <| value ++ #[.call putU64Name]
      | _ => throw s!"JSON number node {nodeId} cannot encode `{access.type.name}`"
  | .decimalString =>
      unless access.type == .u128 do
        throw s!"JSON decimal-string node {nodeId} cannot encode `{access.type.name}`"
      pure <| (← loadAccess access) ++ #[.call putU128Name]
  | .string =>
      unless access.type == .string || access.type == .bytes do
        throw s!"JSON string node {nodeId} cannot encode `{access.type.name}`"
      pure <| (← loadAccess access) ++ #[.call putStringName]
  | .object =>
      let mut body := staticBytes "{"
      for index in Array.range node.fields.size do
        let some field := node.fields[index]?
          | throw s!"JSON object node {nodeId} is missing field index {index}"
        if index > 0 then body := body ++ staticBytes ","
        body := body ++ staticJsonString field.wireName ++ staticBytes ":"
        let fieldAccess ← structFieldAccess structs access field
        let some child := schema.nodes.find? (·.id == field.nodeId)
          | throw s!"JSON field `{field.wireName}` references missing node {field.nodeId}"
        if child.kind == .optional then
          let some childId := child.elementNode?
            | throw s!"JSON optional field `{field.wireName}` has no child node"
          let absent ← accessIsAbsent structs fieldAccess
          body := body ++ absent ++ #[
            .if_ { insns := staticBytes "null" }
              { insns := (← emitNode schema structs childId fieldAccess) }
          ]
        else
          body := body ++ (← emitNode schema structs field.nodeId fieldAccess)
      pure <| body ++ staticBytes "}"
  | .fixedArray =>
      let some elementId := node.elementNode?
        | throw s!"JSON fixed-array node {nodeId} has no element node"
      let some length := node.fixedLength?
        | throw s!"JSON fixed-array node {nodeId} has no length"
      let .fixedArray elementType carrierLength := access.type
        | throw s!"JSON fixed-array node {nodeId} cannot encode `{access.type.name}`"
      unless length == carrierLength do
        throw s!"JSON fixed-array node {nodeId} length {length} does not match carrier {carrierLength}"
      let base ← loadAccess access
      let mut body := staticBytes "["
      for index in Array.range length do
        if index > 0 then body := body ++ staticBytes ","
        let element : Access := {
          insns := base ++ #[.i32Const (index * scalarWidth elementType), .plain "i32.add"]
          type := elementType
          memory := true
        }
        body := body ++ (← emitNode schema structs elementId element)
      pure <| body ++ staticBytes "]"
  | .array =>
      let some elementId := node.elementNode?
        | throw s!"JSON array node {nodeId} has no element node"
      let .array elementType := access.type
        | throw s!"JSON array node {nodeId} cannot encode `{access.type.name}`"
      let pair ← loadAccess access
      let ptrName := s!"__pf_json_array_ptr_{nodeId}"
      let lenName := s!"__pf_json_array_len_{nodeId}"
      let indexName := s!"__pf_json_array_index_{nodeId}"
      let element : Access := {
        insns := #[.localGet ptrName, .localGet indexName, .i32Const (scalarWidth elementType),
          .plain "i32.mul", .plain "i32.add"]
        type := elementType
        memory := true
      }
      let elementBody ← emitNode schema structs elementId element
      pure <| pair ++ #[.localSet lenName, .localSet ptrName] ++ staticBytes "[" ++ #[
        .i32Const 0, .localSet indexName,
        .block_ { insns := #[.loop_ { insns := #[
          .localGet indexName, .localGet lenName, .plain "i32.ge_u", .brIf 1,
          .localGet indexName, .plain "i32.eqz",
          .if_ { insns := #[] } { insns := staticBytes "," }
        ] ++ elementBody ++ #[
          .localGet indexName, .i32Const 1, .plain "i32.add", .localSet indexName,
          .br 0
        ] }] }
      ] ++ staticBytes "]"
  | .optional =>
      let some childId := node.elementNode?
        | throw s!"JSON optional node {nodeId} has no child node"
      let absent ← accessIsAbsent structs access
      pure <| absent ++ #[
        .if_ { insns := staticBytes "null" }
          { insns := (← emitNode schema structs childId access) }
      ]

def rootParams (type : ValueType) : Array Local := match type with
  | .u128 => #[{ name := "value", type := .i64 }, { name := "value__hi", type := .i64 }]
  | .string | .bytes | .array _ => #[
      { name := "value", type := .i32 }, { name := "value_len", type := .i32 }
    ]
  | .u64 | .address => #[{ name := "value", type := .i64 }]
  | _ => #[{ name := "value", type := wasmTypeOf type }]

def rootAccess (type : ValueType) : Access :=
  { insns := match type with
      | .u128 => #[.localGet "value", .localGet "value__hi"]
      | .string | .bytes | .array _ => #[.localGet "value", .localGet "value_len"]
      | _ => #[.localGet "value"]
    type }

def arrayLocals (schema : JsonSchemaPlan) : Array Local :=
  schema.nodes.flatMap fun node => if node.kind == .array then #[
    { name := s!"__pf_json_array_ptr_{node.id}", type := .i32 },
    { name := s!"__pf_json_array_len_{node.id}", type := .i32 },
    { name := s!"__pf_json_array_index_{node.id}", type := .i32 }
  ] else #[]

def buildReturnFunc (entrypoint : String) (structs : Array StructPlan.Struct)
    (schema : JsonSchemaPlan) (type : ValueType) : Except String Func := do
  schema.validate
  let body ← emitNode schema structs schema.rootNode (rootAccess type)
  pure {
    name := helperName entrypoint
    params := rootParams type
    locals := arrayLocals schema
    body := { insns := #[.call startName] ++ body ++ #[.call finishName] }
  }

end ProofForge.Backend.WasmHost.JsonReturn
