/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.NearAbiPlan
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.Params

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.ArrayHeap
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.NearAbiPlan
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

/-! Entrypoint parameter decoding helpers for EmitWat. -/

/-- NEAR Borsh input prologue: `env.input` → register → INPUT_BUF. -/
def nearInputPrologue (expectedBytes : Nat) : Array Insn :=
  #[.i64Const 0, .call "input",
    .i64Const 0, .call "register_len", .i64Const expectedBytes, .plain "i64.ne",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i64Const 0, .i64Const INPUT_BUF, .call "read_register"]

/-- A single dynamic Borsh parameter uses a bounded input region. Its exact
length is checked against the decoded u32 prefix before allocation. -/
def nearDynamicInputPrologue (maximumBytes : Nat) : Array Insn :=
  #[.i64Const 0, .call "input",
    .i64Const 0, .call "register_len", .i64Const maximumBytes, .plain "i64.gt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i64Const 0, .call "register_len", .i64Const 4, .plain "i64.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i64Const 0, .i64Const INPUT_BUF, .call "read_register"]

def rawInputPrologue : Array Insn :=
  #[.i64Const 0, .call "input", .i64Const 0, .i64Const INPUT_BUF, .call "read_register"]

def jsonInputLen64Name : String := "__pf_json_input_len64"
def jsonInputLenName : String := "__pf_json_input_len"
def jsonCursorName : String := "__pf_json_cursor"
def jsonAmountPtrName : String := "__pf_json_amount_ptr"
def jsonAmountLenName : String := "__pf_json_amount_len"
def jsonKeyPtrName : String := "__pf_json_key_ptr"
def jsonKeyLenName : String := "__pf_json_key_len"
def jsonByteName : String := "__pf_json_byte"
def parseU128DecimalName : String := "__pf_parse_u128_decimal"
def parseJsonHex4Name : String := "__pf_json_parse_hex4"
def writeJsonUtf8Name : String := "__pf_json_write_utf8"

/-- Parse an unsigned decimal string into the shared `(lo, hi)` U128 result
buffer. Four base-2^32 limbs keep every `limb * 10 + carry` intermediate below
2^36, so the final carry is an exact overflow check for the full U128 range. -/
def parseU128DecimalFunc : Func :=
  { name := parseU128DecimalName
    params := #[{ name := "p", type := .i32 }, { name := "n", type := .i32 }]
    locals := #[
      { name := "i", type := .i32 }, { name := "byte", type := .i32 },
      { name := "digit", type := .i64 }, { name := "cur", type := .i64 },
      { name := "carry", type := .i64 }, { name := "l0", type := .i64 },
      { name := "l1", type := .i64 }, { name := "l2", type := .i64 },
      { name := "l3", type := .i64 }]
    body := { insns := #[
      .i32Const 0, .localSet "i",
      .i64Const 0, .localSet "l0", .i64Const 0, .localSet "l1",
      .i64Const 0, .localSet "l2", .i64Const 0, .localSet "l3",
      .block_ { insns := #[.loop_ { insns := #[
        .localGet "i", .localGet "n", .plain "i32.ge_u", .brIf 1,
        .localGet "p", .localGet "i", .plain "i32.add", .load "i32.load8_u" 0,
        .localTee "byte", .i32Const 48, .plain "i32.lt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .localGet "byte", .i32Const 57, .plain "i32.gt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .localGet "byte", .i32Const 48, .plain "i32.sub", .plain "i64.extend_i32_u",
        .localSet "digit",
        .localGet "l0", .i64Const 10, .plain "i64.mul", .localGet "digit",
        .plain "i64.add", .localTee "cur", .i64Const 0xffffffff, .plain "i64.and",
        .localSet "l0", .localGet "cur", .i64Const 32, .plain "i64.shr_u", .localSet "carry",
        .localGet "l1", .i64Const 10, .plain "i64.mul", .localGet "carry",
        .plain "i64.add", .localTee "cur", .i64Const 0xffffffff, .plain "i64.and",
        .localSet "l1", .localGet "cur", .i64Const 32, .plain "i64.shr_u", .localSet "carry",
        .localGet "l2", .i64Const 10, .plain "i64.mul", .localGet "carry",
        .plain "i64.add", .localTee "cur", .i64Const 0xffffffff, .plain "i64.and",
        .localSet "l2", .localGet "cur", .i64Const 32, .plain "i64.shr_u", .localSet "carry",
        .localGet "l3", .i64Const 10, .plain "i64.mul", .localGet "carry",
        .plain "i64.add", .localTee "cur", .i64Const 0xffffffff, .plain "i64.and",
        .localSet "l3", .localGet "cur", .i64Const 32, .plain "i64.shr_u",
        .plain "i64.eqz", .if_ { insns := #[] } { insns := #[.unreachable] },
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] }] },
      .i32Const U128_RESULT_BUF, .localGet "l0", .localGet "l1", .i64Const 32,
      .plain "i64.shl", .plain "i64.or", .store "i64.store" 0,
      .i32Const (U128_RESULT_BUF + 8), .localGet "l2", .localGet "l3", .i64Const 32,
      .plain "i64.shl", .plain "i64.or", .store "i64.store" 0
    ] } }

def parseJsonHex4Func : Func :=
  { name := parseJsonHex4Name
    params := #[{ name := "p", type := .i32 }]
    results := #[.i32]
    locals := #[
      { name := "i", type := .i32 }, { name := "b", type := .i32 },
      { name := "digit", type := .i32 }, { name := "result", type := .i32 }
    ]
    body := { insns := #[
      .i32Const 0, .localSet "i", .i32Const 0, .localSet "result",
      .block_ { insns := #[.loop_ { insns := #[
        .localGet "i", .i32Const 4, .plain "i32.ge_u", .brIf 1,
        .localGet "p", .localGet "i", .plain "i32.add",
        .load "i32.load8_u" 0, .localSet "b",
        .localGet "b", .i32Const 48, .plain "i32.ge_u",
        .localGet "b", .i32Const 57, .plain "i32.le_u", .plain "i32.and",
        .if_ { insns := #[
          .localGet "b", .i32Const 48, .plain "i32.sub", .localSet "digit"
        ] } { insns := #[
          .localGet "b", .i32Const 65, .plain "i32.ge_u",
          .localGet "b", .i32Const 70, .plain "i32.le_u", .plain "i32.and",
          .if_ { insns := #[
            .localGet "b", .i32Const 55, .plain "i32.sub", .localSet "digit"
          ] } { insns := #[
            .localGet "b", .i32Const 97, .plain "i32.ge_u",
            .localGet "b", .i32Const 102, .plain "i32.le_u", .plain "i32.and",
            .if_ { insns := #[
              .localGet "b", .i32Const 87, .plain "i32.sub", .localSet "digit"
            ] } { insns := #[.unreachable] }
          ] }
        ] },
        .localGet "result", .i32Const 4, .plain "i32.shl",
        .localGet "digit", .plain "i32.or", .localSet "result",
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] }] },
      .localGet "result"
    ] } }

def writeJsonUtf8Func : Func :=
  { name := writeJsonUtf8Name
    params := #[{ name := "p", type := .i32 }, { name := "code", type := .i32 }]
    results := #[.i32]
    body := { insns := #[
      .localGet "code", .i32Const 0x7f, .plain "i32.le_u",
      .if_ { insns := #[
        .localGet "p", .localGet "code", .store "i32.store8" 0,
        .i32Const 1, .return_
      ] } { insns := #[] },
      .localGet "code", .i32Const 0x7ff, .plain "i32.le_u",
      .if_ { insns := #[
        .localGet "p", .localGet "code", .i32Const 6, .plain "i32.shr_u",
        .i32Const 0xc0, .plain "i32.or", .store "i32.store8" 0,
        .localGet "p", .i32Const 1, .plain "i32.add",
        .localGet "code", .i32Const 0x3f, .plain "i32.and",
        .i32Const 0x80, .plain "i32.or", .store "i32.store8" 0,
        .i32Const 2, .return_
      ] } { insns := #[] },
      .localGet "code", .i32Const 0xd800, .plain "i32.ge_u",
      .localGet "code", .i32Const 0xdfff, .plain "i32.le_u", .plain "i32.and",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .localGet "code", .i32Const 0xffff, .plain "i32.le_u",
      .if_ { insns := #[
        .localGet "p", .localGet "code", .i32Const 12, .plain "i32.shr_u",
        .i32Const 0xe0, .plain "i32.or", .store "i32.store8" 0,
        .localGet "p", .i32Const 1, .plain "i32.add",
        .localGet "code", .i32Const 6, .plain "i32.shr_u",
        .i32Const 0x3f, .plain "i32.and", .i32Const 0x80, .plain "i32.or",
        .store "i32.store8" 0,
        .localGet "p", .i32Const 2, .plain "i32.add",
        .localGet "code", .i32Const 0x3f, .plain "i32.and",
        .i32Const 0x80, .plain "i32.or", .store "i32.store8" 0,
        .i32Const 3, .return_
      ] } { insns := #[] },
      .localGet "code", .i32Const 0x10ffff, .plain "i32.gt_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .localGet "p", .localGet "code", .i32Const 18, .plain "i32.shr_u",
      .i32Const 0xf0, .plain "i32.or", .store "i32.store8" 0,
      .localGet "p", .i32Const 1, .plain "i32.add",
      .localGet "code", .i32Const 12, .plain "i32.shr_u",
      .i32Const 0x3f, .plain "i32.and", .i32Const 0x80, .plain "i32.or",
      .store "i32.store8" 0,
      .localGet "p", .i32Const 2, .plain "i32.add",
      .localGet "code", .i32Const 6, .plain "i32.shr_u",
      .i32Const 0x3f, .plain "i32.and", .i32Const 0x80, .plain "i32.or",
      .store "i32.store8" 0,
      .localGet "p", .i32Const 3, .plain "i32.add",
      .localGet "code", .i32Const 0x3f, .plain "i32.and",
      .i32Const 0x80, .plain "i32.or", .store "i32.store8" 0,
      .i32Const 4
    ] } }

def jsonSeenName (name : String) : String := "__pf_json_seen_" ++ name
def jsonOutName (name : String) : String := "__pf_json_out_" ++ name
def jsonEscapeOkName (name : String) : String := "__pf_json_escape_ok_" ++ name
def jsonCodeName (name : String) : String := "__pf_json_code_" ++ name
def jsonLowName (name : String) : String := "__pf_json_low_" ++ name

def skipJsonWhitespace : Array Insn :=
  #[.block_ { insns := #[.loop_ { insns := #[
    .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u", .brIf 1,
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .load "i32.load8_u" 0, .localTee jsonByteName,
    .i32Const 0x20, .plain "i32.eq",
    .localGet jsonByteName, .i32Const 0x09, .plain "i32.eq", .plain "i32.or",
    .localGet jsonByteName, .i32Const 0x0a, .plain "i32.eq", .plain "i32.or",
    .localGet jsonByteName, .i32Const 0x0d, .plain "i32.eq", .plain "i32.or",
    .plain "i32.eqz", .brIf 1,
    .localGet jsonCursorName, .i32Const 1, .plain "i32.add", .localSet jsonCursorName,
    .br 0
  ] }] }]

def expectJsonByte (expected : Nat) : Array Insn := #[
  .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
  .if_ { insns := #[.unreachable] } { insns := #[] },
  .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
  .load "i32.load8_u" 0, .i32Const expected, .plain "i32.ne",
  .if_ { insns := #[.unreachable] } { insns := #[] },
  .localGet jsonCursorName, .i32Const 1, .plain "i32.add", .localSet jsonCursorName
]

/-- Scan a raw JSON string payload. The cursor starts after the opening quote
and stops on its closing quote. Escape decoding is deliberately rejected here
until the schema string decoder copies and unescapes into owned memory. -/
def scanRawJsonString : Array Insn :=
  #[.block_ { insns := #[.loop_ { insns := #[
    .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .load "i32.load8_u" 0, .localTee jsonByteName,
    .i32Const 0x22, .plain "i32.eq", .brIf 1,
    .localGet jsonByteName, .i32Const 0x20, .plain "i32.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonByteName, .i32Const 0x5c, .plain "i32.eq",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonCursorName, .i32Const 1, .plain "i32.add", .localSet jsonCursorName,
    .br 0
  ] }] }]

def decodeJsonEscape (okName : String) : Array Insn :=
  let cases : Array (Nat × Nat) := #[
    (0x22, 0x22), (0x5c, 0x5c), (0x2f, 0x2f),
    (0x62, 0x08), (0x66, 0x0c), (0x6e, 0x0a), (0x72, 0x0d), (0x74, 0x09)
  ]
  let decoded := cases.foldl (init := #[]) fun insns pair =>
    insns ++ #[
      .localGet jsonByteName, .i32Const pair.fst, .plain "i32.eq",
      .if_ { insns := #[
        .i32Const pair.snd, .localSet jsonByteName,
        .i32Const 1, .localSet okName
      ] } { insns := #[] }
    ]
  #[.i32Const 0, .localSet okName] ++ decoded ++ #[
    .localGet okName, .plain "i32.eqz",
    .if_ { insns := #[.unreachable] } { insns := #[] }
  ]

def decodeJsonUnicodeEscape (name : String) : Array Insn :=
  let outName := jsonOutName name
  let codeName := jsonCodeName name
  let lowName := jsonLowName name
  #[
    .localGet jsonCursorName, .i32Const 4, .plain "i32.add",
    .localGet jsonInputLenName, .plain "i32.ge_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const (INPUT_BUF + 1), .localGet jsonCursorName, .plain "i32.add",
    .call parseJsonHex4Name, .localSet codeName,
    .localGet jsonCursorName, .i32Const 4, .plain "i32.add", .localSet jsonCursorName,
    .localGet codeName, .i32Const 0xd800, .plain "i32.ge_u",
    .localGet codeName, .i32Const 0xdbff, .plain "i32.le_u", .plain "i32.and",
    .if_ { insns := #[
      .localGet jsonCursorName, .i32Const 6, .plain "i32.add",
      .localGet jsonInputLenName, .plain "i32.ge_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .i32Const (INPUT_BUF + 1), .localGet jsonCursorName, .plain "i32.add",
      .load "i32.load8_u" 0, .i32Const 0x5c, .plain "i32.ne",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .i32Const (INPUT_BUF + 2), .localGet jsonCursorName, .plain "i32.add",
      .load "i32.load8_u" 0, .i32Const 0x75, .plain "i32.ne",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .i32Const (INPUT_BUF + 3), .localGet jsonCursorName, .plain "i32.add",
      .call parseJsonHex4Name, .localTee lowName,
      .i32Const 0xdc00, .plain "i32.lt_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .localGet lowName, .i32Const 0xdfff, .plain "i32.gt_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .localGet codeName, .i32Const 0xd800, .plain "i32.sub",
      .i32Const 10, .plain "i32.shl",
      .localGet lowName, .i32Const 0xdc00, .plain "i32.sub", .plain "i32.add",
      .i32Const 0x10000, .plain "i32.add", .localSet codeName,
      .localGet jsonCursorName, .i32Const 6, .plain "i32.add", .localSet jsonCursorName
    ] } { insns := #[
      .localGet codeName, .i32Const 0xdc00, .plain "i32.ge_u",
      .localGet codeName, .i32Const 0xdfff, .plain "i32.le_u", .plain "i32.and",
      .if_ { insns := #[.unreachable] } { insns := #[] }
    ] },
    .localGet name, .localGet outName, .plain "i32.add",
    .localGet codeName, .call writeJsonUtf8Name,
    .localGet outName, .plain "i32.add", .localSet outName
  ]

/-- Decode a JSON string payload into owned UTF-8 bytes. The cursor starts
after the opening quote and stops on its closing quote. Standard one-byte
escapes and `\uXXXX` (including surrogate pairs) are materialized. -/
def decodeJsonString (name : String) : Array Insn :=
  let outName := jsonOutName name
  let okName := jsonEscapeOkName name
  let storeByte := #[
    .localGet name, .localGet outName, .plain "i32.add",
    .localGet jsonByteName, .store "i32.store8" 0,
    .localGet outName, .i32Const 1, .plain "i32.add", .localSet outName
  ]
  #[
    .localGet jsonInputLenName, .localGet jsonCursorName, .plain "i32.sub",
    .plain "i64.extend_i32_u", .call arrAllocName, .localSet name,
    .i32Const 0, .localSet outName,
    .block_ { insns := #[.loop_ { insns := #[
      .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
      .load "i32.load8_u" 0, .localTee jsonByteName,
      .i32Const 0x22, .plain "i32.eq", .brIf 1,
      .localGet jsonByteName, .i32Const 0x5c, .plain "i32.eq",
      .if_ { insns := #[
        .localGet jsonCursorName, .i32Const 1, .plain "i32.add",
        .localTee jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
        .load "i32.load8_u" 0, .localSet jsonByteName
      ] ++ #[
        .localGet jsonByteName, .i32Const 0x75, .plain "i32.eq",
        .if_ { insns := decodeJsonUnicodeEscape name }
          { insns := decodeJsonEscape okName ++ storeByte }
      ] } { insns := #[
        .localGet jsonByteName, .i32Const 0x20, .plain "i32.lt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] }
      ] ++ storeByte },
      .localGet jsonCursorName, .i32Const 1, .plain "i32.add", .localSet jsonCursorName,
      .br 0
    ] }] },
    .localGet outName, .localSet (name ++ "_len")
  ]

def jsonKeyMatchesAt (wireName : String) : Array Insn :=
  (wireName.toUTF8.data.foldl (init := (#[
      .localGet jsonKeyLenName, .i32Const wireName.toUTF8.size, .plain "i32.eq"
    ], 0)) fun (insns, offset) byte =>
      (insns ++ #[
        .localGet jsonKeyPtrName, .i32Const offset, .plain "i32.add",
        .load "i32.load8_u" 0, .i32Const byte.toNat, .plain "i32.eq", .plain "i32.and"
      ], offset + 1)).fst

def resolveJsonWireNames (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan) (wireParamNames? : Option (Array String)) :
    Except EmitError (Array String) :=
  match wireParamNames? with
  | none => .ok (params.map (·.fst))
  | some names =>
      if names.size == params.size then .ok names
      else err s!"EmitWat: JSON entrypoint `{abiPlan.name}` wire-parameter mapping has {names.size} names, expected {params.size}"

def jsonObjectFields (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan) (wireParamNames? : Option (Array String)) :
    Except EmitError (Array JsonFieldPlan) := do
  let some schema := abiPlan.inputJson?
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` is missing its input schema"
  let some root := schema.root?
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` schema is missing root node {schema.rootNode}"
  unless root.kind == .object do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` input schema root must be an object"
  unless root.fields.size == params.size do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` schema has {root.fields.size} root fields, expected {params.size}"
  let mappedNames ← resolveJsonWireNames params abiPlan wireParamNames?
  unless root.fields.map (·.wireName) == mappedNames do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` schema fields do not match its wire-parameter mapping"
  pure root.fields

def jsonFieldKinds (abiPlan : EntrypointPlan) (fields : Array JsonFieldPlan) :
    Except EmitError (Array JsonNodeKind) := do
  let some schema := abiPlan.inputJson?
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` is missing its input schema"
  fields.mapM fun field =>
    match schema.nodes.find? (·.id == field.nodeId) with
    | some node => pure node.kind
    | none => err s!"EmitWat: JSON entrypoint `{abiPlan.name}` field `{field.wireName}` references missing node {field.nodeId}"

def jsonFieldBinding (abiPlan : EntrypointPlan) (field : JsonFieldPlan) :
    Except EmitError (JsonNodeKind × Bool) := do
  let some schema := abiPlan.inputJson?
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` is missing its input schema"
  let some node := schema.nodes.find? (·.id == field.nodeId)
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` field `{field.wireName}` references missing node {field.nodeId}"
  if node.kind != .optional then
    pure (node.kind, false)
  else
    let some childId := node.elementNode?
      | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` optional field `{field.wireName}` has no child node"
    let some child := schema.nodes.find? (·.id == childId)
      | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` optional field `{field.wireName}` references missing child node {childId}"
    if child.kind == .optional then
      err s!"EmitWat: JSON entrypoint `{abiPlan.name}` field `{field.wireName}` has nested optional nodes"
    else
      pure (child.kind, true)

def parseFlatJsonField (param : String × ValueType) (field : JsonFieldPlan)
    (kind : JsonNodeKind) (isOptional : Bool) :
    Except EmitError (Array Insn × Array Local) := do
  let name := param.fst
  let seen := jsonSeenName name
  let rejectDuplicate := #[
    .localGet seen,
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const 1, .localSet seen
  ]
  let (valueInsns, valueLocals) ← match kind, param.snd with
  | .string, .string =>
      let accountIdBounds :=
        if field.wireName.endsWith "_id" then #[
          .localGet (name ++ "_len"), .i32Const 2, .plain "i32.lt_u",
          .if_ { insns := #[.unreachable] } { insns := #[] },
          .localGet (name ++ "_len"), .i32Const 64, .plain "i32.gt_u",
          .if_ { insns := #[.unreachable] } { insns := #[] }
        ] else #[]
      pure (expectJsonByte 0x22 ++ decodeJsonString name ++
        accountIdBounds ++ expectJsonByte 0x22, #[
        { name := jsonOutName name, type := .i32 },
        { name := jsonEscapeOkName name, type := .i32 },
        { name := jsonCodeName name, type := .i32 },
        { name := jsonLowName name, type := .i32 },
        { name := name ++ "_len", type := .i32 }, { name := name, type := .i32 }
      ])
  | .decimalString, .u128 =>
      pure (expectJsonByte 0x22 ++ #[
        .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
        .localSet jsonAmountPtrName
      ] ++ scanRawJsonString ++ #[
        .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
        .localGet jsonAmountPtrName, .plain "i32.sub", .localTee jsonAmountLenName,
        .i32Const 1, .plain "i32.lt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .localGet jsonAmountLenName, .i32Const 39, .plain "i32.gt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .localGet jsonAmountLenName, .i32Const 1, .plain "i32.gt_u",
        .if_ { insns := #[
          .localGet jsonAmountPtrName, .load "i32.load8_u" 0,
          .i32Const 48, .plain "i32.eq",
          .if_ { insns := #[.unreachable] } { insns := #[] }
        ] } { insns := #[] },
        .localGet jsonAmountPtrName, .localGet jsonAmountLenName,
        .call parseU128DecimalName,
        .i32Const U128_RESULT_BUF, .load "i64.load" 0, .localSet name,
        .i32Const (U128_RESULT_BUF + 8), .load "i64.load" 0,
        .localSet (u128HiName name)
      ] ++ expectJsonByte 0x22, #[
        { name := name, type := .i64 }, { name := u128HiName name, type := .i64 }
      ])
  | .number, .u64 =>
      pure (#[] ++ #[
        .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
        .localSet jsonAmountPtrName,
        .block_ { insns := #[.loop_ { insns := #[
          .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
          .brIf 1,
          .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
          .load "i32.load8_u" 0, .localTee jsonByteName,
          .i32Const 48, .plain "i32.lt_u", .brIf 1,
          .localGet jsonByteName, .i32Const 57, .plain "i32.gt_u", .brIf 1,
          .localGet jsonCursorName, .i32Const 1, .plain "i32.add",
          .localSet jsonCursorName, .br 0
        ] }] },
        .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
        .localGet jsonAmountPtrName, .plain "i32.sub", .localTee jsonAmountLenName,
        .i32Const 1, .plain "i32.lt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .localGet jsonAmountLenName, .i32Const 20, .plain "i32.gt_u",
        .if_ { insns := #[.unreachable] } { insns := #[] },
        .localGet jsonAmountLenName, .i32Const 1, .plain "i32.gt_u",
        .if_ { insns := #[
          .localGet jsonAmountPtrName, .load "i32.load8_u" 0,
          .i32Const 48, .plain "i32.eq",
          .if_ { insns := #[.unreachable] } { insns := #[] }
        ] } { insns := #[] },
        .localGet jsonAmountPtrName, .localGet jsonAmountLenName,
        .call parseU128DecimalName,
        .i32Const (U128_RESULT_BUF + 8), .load "i64.load" 0, .plain "i64.eqz",
        .if_ { insns := #[] } { insns := #[.unreachable] },
        .i32Const U128_RESULT_BUF, .load "i64.load" 0, .localSet name
      ], #[{ name := name, type := .i64 }])
  | .bool, .bool =>
      pure (#[] ++ #[
        .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
        .load "i32.load8_u" 0, .i32Const 0x74, .plain "i32.eq",
        .if_ {
          insns := expectJsonByte 0x74 ++ expectJsonByte 0x72 ++
            expectJsonByte 0x75 ++ expectJsonByte 0x65 ++
            #[.i32Const 1, .localSet name]
        } {
          insns := expectJsonByte 0x66 ++ expectJsonByte 0x61 ++
            expectJsonByte 0x6c ++ expectJsonByte 0x73 ++ expectJsonByte 0x65 ++
            #[.i32Const 0, .localSet name]
        }
      ], #[{ name := name, type := .i32 }])
  | _, _ =>
      err s!"EmitWat: JSON field `{field.wireName}` node `{kind.id}` cannot bind portable parameter `{name} : {param.snd.name}`"
  let parseValue :=
    if isOptional then #[
      .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
      .load "i32.load8_u" 0, .i32Const 0x6e, .plain "i32.eq",
      .if_ { insns := expectJsonByte 0x6e ++ expectJsonByte 0x75 ++
        expectJsonByte 0x6c ++ expectJsonByte 0x6c } { insns := valueInsns }
    ] else valueInsns
  pure (rejectDuplicate ++ parseValue,
    #[{ name := seen, type := .i32 }] ++ valueLocals)

/-- Schema-driven top-level JSON object decoder for the scalar nodes used by
the executable NEP-141 boundary. It accepts insignificant whitespace and any
field order, rejects unknown/duplicate fields, and validates every required
field before the entrypoint body runs. -/
def loadJsonFlatObjectParams (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan) (wireParamNames? : Option (Array String)) :
    Except EmitError (Array Insn × Array Local) := do
  let fields ← jsonObjectFields params abiPlan wireParamNames?
  let some schema := abiPlan.inputJson?
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` is missing its input schema"
  unless schema.orderIndependent do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` requires an order-independent object schema"
  unless schema.rejectUnknownFields do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` unknown-field skipping is not implemented"
  let mut dispatch : Array Insn := #[.unreachable]
  let mut valueLocals : Array Local := #[]
  for index in (Array.range params.size).reverse do
    let some param := params[index]?
      | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` parameter index {index} is missing"
    let some field := fields[index]?
      | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` schema field index {index} is missing"
    let (kind, isOptional) ← jsonFieldBinding abiPlan field
    let (parseInsns, locals) ← parseFlatJsonField param field kind isOptional
    valueLocals := locals ++ valueLocals
    dispatch := jsonKeyMatchesAt field.wireName ++
      #[.if_ { insns := parseInsns } { insns := dispatch }]
  let prologue : Array Insn := #[
    .i64Const 0, .call "input",
    .i64Const 0, .call "register_len", .localTee jsonInputLen64Name,
    .i64Const 2, .plain "i64.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonInputLen64Name, .i64Const 4096, .plain "i64.gt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonInputLen64Name, .plain "i32.wrap_i64", .localSet jsonInputLenName,
    .i64Const 0, .i64Const INPUT_BUF, .call "read_register",
    .i32Const 0, .localSet jsonCursorName
  ] ++ skipJsonWhitespace ++ expectJsonByte 0x7b
  let parseKey := expectJsonByte 0x22 ++ #[
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .localSet jsonKeyPtrName
  ] ++ scanRawJsonString ++ #[
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .localGet jsonKeyPtrName, .plain "i32.sub", .localSet jsonKeyLenName
  ] ++ expectJsonByte 0x22 ++ skipJsonWhitespace ++ expectJsonByte 0x3a ++ skipJsonWhitespace
  let separator := skipJsonWhitespace ++ #[
    .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .load "i32.load8_u" 0, .localTee jsonByteName,
    .i32Const 0x2c, .plain "i32.eq",
    .if_ { insns := expectJsonByte 0x2c ++ skipJsonWhitespace ++ #[
      .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
      .load "i32.load8_u" 0, .i32Const 0x7d, .plain "i32.eq",
      .if_ { insns := #[.unreachable] } { insns := #[] },
      .br 2
    ] } { insns := #[] },
    .localGet jsonByteName, .i32Const 0x7d, .plain "i32.eq",
    .if_ { insns := expectJsonByte 0x7d ++ #[.br 3] } { insns := #[.unreachable] }
  ]
  let objectLoopBody := skipJsonWhitespace ++ #[
    .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .load "i32.load8_u" 0, .i32Const 0x7d, .plain "i32.eq",
    .if_ { insns := expectJsonByte 0x7d ++ #[.br 2] }
      { insns := parseKey ++ dispatch ++ separator }
  ]
  let objectLoop : Array Insn := #[
    .block_ { insns := #[.loop_ { insns := objectLoopBody }] }
  ]
  let mut requiredChecks : Array Insn := #[]
  for index in Array.range params.size do
    let some param := params[index]?
      | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` parameter index {index} is missing"
    let some field := fields[index]?
      | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` schema field index {index} is missing"
    if field.required then
      requiredChecks := requiredChecks ++ #[
        .localGet (jsonSeenName param.fst), .plain "i32.eqz",
        .if_ { insns := #[.unreachable] } { insns := #[] }
      ]
  let epilogue := skipJsonWhitespace ++ #[
    .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ne",
    .if_ { insns := #[.unreachable] } { insns := #[] }
  ] ++ requiredChecks
  pure (prologue ++ objectLoop ++ epilogue, #[
    { name := jsonInputLen64Name, type := .i64 },
    { name := jsonInputLenName, type := .i32 },
    { name := jsonCursorName, type := .i32 },
    { name := jsonKeyPtrName, type := .i32 },
    { name := jsonKeyLenName, type := .i32 },
    { name := jsonByteName, type := .i32 },
    { name := jsonAmountPtrName, type := .i32 },
    { name := jsonAmountLenName, type := .i32 }
  ] ++ valueLocals)

def loadJsonParams (params : Array (String × ValueType)) (abiPlan : EntrypointPlan)
    (wireParamNames? : Option (Array String)) :
    Except EmitError (Array Insn × Array Local) := do
  loadJsonFlatObjectParams params abiPlan wireParamNames?

/-- Build the Borsh input prologue and load each param into a local.

* **No params:** empty prologue on all bridges (no residual `input` / `read_register`).
* **NEAR / Soroban:** Borsh decode via `env.input` + `read_register` (Soroban still
  imports these until a Soroban-native param ABI lands).
* **CosmWasm:** reject non-empty params until CosmWasm message decoding lands
  (Counter spike path does not use IR params). -/
def loadParams (structs : Array ProofForge.IR.StructDecl)
    (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan)
    (bridge : ProofForge.Target.HostBridge := .near)
    (wireParamNames? : Option (Array String) := none)
    : Except EmitError (Array Insn × Array Local) := do
  let plannedParams := abiPlan.params.map fun param => (param.name?.getD "", param.type)
  if abiPlan.name.isEmpty || plannedParams != params then
    err s!"EmitWat: entrypoint `{abiPlan.name}` NEAR ABI plan does not match its parameter signature"
  -- CosmWasm: no NEAR input — empty prologue only; reject params for now.
  if bridge == .cosmWasm then
    if params.isEmpty then
      .ok (#[], #[])
    else
      err "EmitWat: entrypoint parameters are not yet lowered on HostBridge.cosmWasm (use Counter spike or zero-param entries)"
  else if abiPlan.inputCodec == .json then
    if bridge != .near then
      err s!"EmitWat: JSON entrypoint `{abiPlan.name}` is only supported on HostBridge.near"
    else
      loadJsonParams params abiPlan wireParamNames?
  else if params.isEmpty then
    -- Skip host `input` only for zero-arg Borsh entrypoints
    -- (Counter initialize/increment/get, ValueVault views).
    .ok (#[], #[])
  else
  if abiPlan.inputCodec != .borsh || abiPlan.inputByteWidth == 0 then
    err s!"EmitWat: entrypoint `{abiPlan.name}` has an invalid NEAR input codec plan"
  let dynamicCount := params.foldl (fun count (_, type) =>
    if type == .bytes || type == .string then count + 1 else count) 0
  if dynamicCount > 0 && params.size != 1 then
    err s!"EmitWat: entrypoint `{abiPlan.name}` supports a dynamic bytes/string parameter only as its sole parameter"
  let prologue : Array Insn :=
    if bridge == .near then
      if dynamicCount == 1 then nearDynamicInputPrologue abiPlan.inputByteWidth
      else nearInputPrologue abiPlan.inputByteWidth
    else rawInputPrologue
  let result ← params.foldlM (init := (prologue, (#[] : Array Local), 0, 0))
    fun (insns, locals, offset, hslot) p =>
      let (name, vt) := p
      match vt with
      | .u32 | .u64 | .bool =>
        let loadInsns := #[.i32Const (INPUT_BUF + offset), .load (loadOpFor vt) 0, .localSet name]
        .ok (insns ++ loadInsns, locals.push { name := name, type := wasmTypeOf vt }, offset + scalarWidth vt, hslot)
      | .u128 =>
        -- U128: 16-byte Borsh LE. Two-word local convention (name = lo,
        -- `name__hi` = hi), matching let-bound u128 locals and arithmetic.
        let loadInsns :=
          #[.i32Const (INPUT_BUF + offset), .load "i64.load" 0, .localSet name,
            .i32Const (INPUT_BUF + offset + 8), .load "i64.load" 0, .localSet (u128HiName name)]
        .ok (insns ++ loadInsns,
          locals.push { name := name, type := .i64 } |>.push { name := u128HiName name, type := .i64 },
          offset + 16, hslot)
      | .hash =>
        let slot := PARAM_HASH_BUF + hslot * 32
        let loadInsns := #[.i32Const slot, .i32Const (INPUT_BUF + offset), .i32Const 32, .call memcpyName,
                           .i32Const slot, .localSet name]
        .ok (insns ++ loadInsns, locals.push { name := name, type := wasmTypeOf vt }, offset + 32, hslot + 1)
      | .fixedArray elemType n =>
        if !(isScalarBorshType elemType) then
          err s!"EmitWat: param `{name}` has unsupported fixedArray element type `{elemType.name}` (only scalar elements supported in Borsh params)"
        else
          let elemWidth := scalarWidth elemType
          let totalBytes := n * elemWidth
          let loadInsns :=
            #[.i64Const totalBytes, .call arrAllocName, .localSet name] ++
            (Array.range n).foldl (fun (acc : Array Insn) i =>
              let srcOff := INPUT_BUF + offset + i * elemWidth
              let dstOff := i * elemWidth
              let loadElem :=
                if elemType == ProofForge.IR.ValueType.hash then
                  #[.i32Const dstOff, .localGet name, .plain "i32.add",
                    .i32Const srcOff, .i32Const 32, .call memcpyName]
                else
                  #[.i32Const dstOff, .localGet name, .plain "i32.add",
                    .i32Const srcOff, .load (loadOpFor elemType) 0,
                    .store (storeOpFor elemType) 0]
              acc ++ loadElem) #[]
          .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + totalBytes, hslot)
      | .structType typeName =>
        match structs.find? (fun s => s.name == typeName) with
        | none => err s!"EmitWat: param `{name}` references unknown struct `{typeName}`"
        | some sd =>
          if !structStorageFieldsSupported sd then
            err s!"EmitWat: param `{name}` struct `{typeName}` has non-scalar fields (only u32/u64/bool/hash supported in Borsh params)"
          else
            let totalBytes := structTotalSize sd
            let loadInsns :=
              #[.i64Const totalBytes, .call arrAllocName, .localSet name] ++
              sd.fields.foldl (fun (acc : Array Insn) f =>
                let fieldOff := structFieldOffset? sd f.id |>.getD 0
                let srcOff := INPUT_BUF + offset + fieldOff
                let dstOff := fieldOff
                let loadField :=
                  if f.type == ProofForge.IR.ValueType.hash then
                    #[.i32Const dstOff, .localGet name, .plain "i32.add",
                      .i32Const srcOff, .i32Const 32, .call memcpyName]
                  else
                    #[.i32Const dstOff, .localGet name, .plain "i32.add",
                      .i32Const srcOff, .load (loadOpFor f.type) 0,
                      .store (storeOpFor f.type) 0]
                acc ++ loadField) #[]
          .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + totalBytes, hslot)
      | .bytes | .string =>
        -- Borsh dynamic bytes/string: 4-byte LE length prefix + payload.
        -- Allocate a buffer, copy the 4-byte length prefix + payload from INPUT_BUF.
        -- The local holds an i32 pointer to the payload (length prefix at ptr - 4).
        let lenOff := INPUT_BUF + offset
        let loadInsns :=
          #[.i32Const lenOff, .load "i32.load" 0, .localSet (name ++ "_len"),
            .localGet (name ++ "_len"), .plain "i64.extend_i32_u", .i64Const 4,
            .plain "i64.add", .i64Const 0, .call "register_len", .plain "i64.ne",
            .if_ { insns := #[.unreachable] } { insns := #[] },
            .localGet (name ++ "_len"), .plain "i64.extend_i32_u", .i64Const 4, .plain "i64.add",
            .call arrAllocName, .localSet name,
            .localGet name, .i32Const lenOff, .localGet (name ++ "_len"),
            .i32Const 4, .plain "i32.add", .call memcpyName,
            .localGet name, .i32Const 4, .plain "i32.add", .localSet name]
        .ok (insns ++ loadInsns,
            locals.push { name := name ++ "_len", type := .i32 } |>.push { name := name, type := .i32 },
            offset + 260, hslot)
      | _ => err s!"EmitWat: param `{name}` has unsupported Borsh type `{vt.name}`"
  pure (result.fst, result.snd.fst)

end ProofForge.Backend.WasmHost.Params
