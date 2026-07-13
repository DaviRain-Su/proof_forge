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
def parseU128DecimalName : String := "__pf_parse_u128_decimal"

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

def assertJsonByteAt (offset expected : Nat) : Array Insn :=
  #[.i32Const (INPUT_BUF + offset), .load "i32.load8_u" 0, .i32Const expected,
    .plain "i32.ne", .if_ { insns := #[.unreachable] } { insns := #[] }]

def assertJsonPrefix (jsonPrefix : String) : Array Insn :=
  (jsonPrefix.toUTF8.data.foldl (init := (#[], 0)) fun (insns, offset) byte =>
    (insns ++ assertJsonByteAt offset byte.toNat, offset + 1)).fst

def assertJsonBytesAtCursor (cursorName : String) (bytes : String) : Array Insn :=
  (bytes.toUTF8.data.foldl (init := (#[], 0)) fun (insns, offset) byte =>
    (insns ++ #[.i32Const INPUT_BUF, .localGet cursorName, .plain "i32.add",
      .i32Const offset, .plain "i32.add", .load "i32.load8_u" 0,
      .i32Const byte.toNat, .plain "i32.ne",
      .if_ { insns := #[.unreachable] } { insns := #[] }], offset + 1)).fst

def resolveJsonWireNames (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan) (wireParamNames? : Option (Array String)) :
    Except EmitError (Array String) :=
  match wireParamNames? with
  | none => .ok (params.map (·.fst))
  | some names =>
      if names.size == params.size then .ok names
      else err s!"EmitWat: JSON entrypoint `{abiPlan.name}` wire-parameter mapping has {names.size} names, expected {params.size}"

/-- Decode the Phase-4a canonical JSON object
`{"account_id":"<NEAR AccountId>"}`. `JSON.stringify` and near-api-js emit this
shape for the one-field object. AccountIds cannot contain JSON quote/escape
characters, so the payload can safely remain a direct `(ptr, len)` view into
`INPUT_BUF`. -/
def loadJsonStringObjectParam (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan) (wireParamNames? : Option (Array String) := none) :
    Except EmitError (Array Insn × Array Local) := do
  let some (name, type) := params[0]?
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` requires one String parameter"
  unless params.size == 1 && type == .string do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` currently supports exactly one String parameter"
  let wireNames ← resolveJsonWireNames params abiPlan wireParamNames?
  let wireName := wireNames[0]!
  let jsonPrefix := "{\"" ++ wireName ++ "\":\""
  let prefixLen := jsonPrefix.toUTF8.size
  let minInputLen := prefixLen + 2 + 2
  let maxInputLen := prefixLen + 64 + 2
  let suffixQuoteAddress := #[.i32Const INPUT_BUF, .localGet jsonInputLenName,
    .plain "i32.add", .i32Const 2, .plain "i32.sub"]
  let suffixBraceAddress := #[.i32Const INPUT_BUF, .localGet jsonInputLenName,
    .plain "i32.add", .i32Const 1, .plain "i32.sub"]
  let prologue := #[
    .i64Const 0, .call "input",
    .i64Const 0, .call "register_len", .localTee jsonInputLen64Name,
    .i64Const minInputLen, .plain "i64.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonInputLen64Name, .i64Const maxInputLen, .plain "i64.gt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonInputLen64Name, .plain "i32.wrap_i64", .localSet jsonInputLenName,
    .i64Const 0, .i64Const INPUT_BUF, .call "read_register"
  ]
  let suffixChecks := suffixQuoteAddress ++ #[.load "i32.load8_u" 0, .i32Const 0x22,
      .plain "i32.ne", .if_ { insns := #[.unreachable] } { insns := #[] }] ++
    suffixBraceAddress ++ #[.load "i32.load8_u" 0, .i32Const 0x7d,
      .plain "i32.ne", .if_ { insns := #[.unreachable] } { insns := #[] }]
  let bindParam := #[
    .i32Const (INPUT_BUF + prefixLen), .localSet name,
    .localGet jsonInputLenName, .i32Const (prefixLen + 2), .plain "i32.sub",
    .localSet (name ++ "_len")
  ]
  .ok (prologue ++ assertJsonPrefix jsonPrefix ++ suffixChecks ++ bindParam, #[
    { name := jsonInputLen64Name, type := .i64 },
    { name := jsonInputLenName, type := .i32 },
    { name := name ++ "_len", type := .i32 },
    { name := name, type := .i32 }
  ])

/-- Decode the Landing-4b canonical JSON object
`{"receiver_id":"<AccountId>","amount":"<U128>"}`. The AccountId remains a
zero-copy string view; the decimal amount is parsed into the standard two-word
U128 locals through `__pf_parse_u128_decimal`. -/
def loadJsonStringU128ObjectParams (params : Array (String × ValueType))
    (abiPlan : EntrypointPlan) (wireParamNames? : Option (Array String) := none) :
    Except EmitError (Array Insn × Array Local) := do
  let #[receiver, amount] := params
    | err s!"EmitWat: JSON entrypoint `{abiPlan.name}` requires String and U128 parameters"
  unless receiver.snd == .string && amount.snd == .u128 do
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` currently supports (String, U128) parameters"
  let wireNames ← resolveJsonWireNames params abiPlan wireParamNames?
  let jsonPrefix := "{\"" ++ wireNames[0]! ++ "\":\""
  let amountDelimiter := "\",\"" ++ wireNames[1]! ++ "\":\""
  let prefixLen := jsonPrefix.toUTF8.size
  let delimiterLen := amountDelimiter.toUTF8.size
  let minInputLen := prefixLen + 2 + delimiterLen + 1 + 2
  let maxInputLen := prefixLen + 64 + delimiterLen + 39 + 2
  let receiverName := receiver.fst
  let amountName := amount.fst
  let prologue := #[
    .i64Const 0, .call "input",
    .i64Const 0, .call "register_len", .localTee jsonInputLen64Name,
    .i64Const minInputLen, .plain "i64.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonInputLen64Name, .i64Const maxInputLen, .plain "i64.gt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonInputLen64Name, .plain "i32.wrap_i64", .localSet jsonInputLenName,
    .i64Const 0, .i64Const INPUT_BUF, .call "read_register",
    .i32Const prefixLen, .localSet jsonCursorName
  ]
  let scanReceiver := #[.block_ { insns := #[.loop_ { insns := #[
    .localGet jsonCursorName, .localGet jsonInputLenName, .plain "i32.ge_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const INPUT_BUF, .localGet jsonCursorName, .plain "i32.add",
    .load "i32.load8_u" 0, .i32Const 0x22, .plain "i32.eq", .brIf 1,
    .localGet jsonCursorName, .i32Const 1, .plain "i32.add", .localTee jsonCursorName,
    .i32Const (prefixLen + 64), .plain "i32.gt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] }, .br 0
  ] }] }]
  let suffixQuoteAddress := #[.i32Const INPUT_BUF, .localGet jsonInputLenName,
    .plain "i32.add", .i32Const 2, .plain "i32.sub"]
  let suffixBraceAddress := #[.i32Const INPUT_BUF, .localGet jsonInputLenName,
    .plain "i32.add", .i32Const 1, .plain "i32.sub"]
  let bindAndParse := #[
    .localGet jsonCursorName, .i32Const prefixLen, .plain "i32.sub",
    .i32Const 2, .plain "i32.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .i32Const (INPUT_BUF + prefixLen), .localSet receiverName,
    .localGet jsonCursorName, .i32Const prefixLen, .plain "i32.sub",
    .localSet (receiverName ++ "_len"),
    .localGet jsonCursorName, .i32Const delimiterLen, .plain "i32.add",
    .localTee jsonAmountPtrName, .i32Const INPUT_BUF, .plain "i32.add",
    .localSet jsonAmountPtrName,
    .localGet jsonInputLenName, .i32Const 2, .plain "i32.sub",
    .localGet jsonCursorName, .i32Const delimiterLen, .plain "i32.add",
    .plain "i32.sub", .localTee jsonAmountLenName,
    .i32Const 1, .plain "i32.lt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonAmountLenName, .i32Const 39, .plain "i32.gt_u",
    .if_ { insns := #[.unreachable] } { insns := #[] },
    .localGet jsonAmountLenName, .i32Const 1, .plain "i32.gt_u",
    .if_ { insns := #[.localGet jsonAmountPtrName, .load "i32.load8_u" 0,
      .i32Const 48, .plain "i32.eq",
      .if_ { insns := #[.unreachable] } { insns := #[] }] } { insns := #[] },
    .localGet jsonAmountPtrName, .localGet jsonAmountLenName, .call parseU128DecimalName,
    .i32Const U128_RESULT_BUF, .load "i64.load" 0, .localSet amountName,
    .i32Const (U128_RESULT_BUF + 8), .load "i64.load" 0,
    .localSet (u128HiName amountName)
  ]
  let suffixChecks := suffixQuoteAddress ++ #[.load "i32.load8_u" 0, .i32Const 0x22,
      .plain "i32.ne", .if_ { insns := #[.unreachable] } { insns := #[] }] ++
    suffixBraceAddress ++ #[.load "i32.load8_u" 0, .i32Const 0x7d,
      .plain "i32.ne", .if_ { insns := #[.unreachable] } { insns := #[] }]
  .ok (prologue ++ assertJsonPrefix jsonPrefix ++ scanReceiver ++
    assertJsonBytesAtCursor jsonCursorName amountDelimiter ++ suffixChecks ++ bindAndParse, #[
      { name := jsonInputLen64Name, type := .i64 }, { name := jsonInputLenName, type := .i32 },
      { name := jsonCursorName, type := .i32 }, { name := jsonAmountPtrName, type := .i32 },
      { name := jsonAmountLenName, type := .i32 },
      { name := receiverName ++ "_len", type := .i32 }, { name := receiverName, type := .i32 },
      { name := amountName, type := .i64 }, { name := u128HiName amountName, type := .i64 }
    ])

def loadJsonParams (params : Array (String × ValueType)) (abiPlan : EntrypointPlan)
    (wireParamNames? : Option (Array String)) :
    Except EmitError (Array Insn × Array Local) := do
  let types : Array ValueType := params.map (·.snd)
  if types == #[.string] then
    loadJsonStringObjectParam params abiPlan wireParamNames?
  else if types == #[.string, .u128] then
    loadJsonStringU128ObjectParams params abiPlan wireParamNames?
  else
    err s!"EmitWat: JSON entrypoint `{abiPlan.name}` has no supported decoder for its parameter signature"

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
  else if params.isEmpty then
    -- Skip host `input` for zero-arg entrypoints (Counter initialize/increment/get,
    -- ValueVault views). Saves a host call with no ABI payload to decode.
    .ok (#[], #[])
  else if abiPlan.inputCodec == .json then
    if bridge != .near then
      err s!"EmitWat: JSON entrypoint `{abiPlan.name}` is only supported on HostBridge.near"
    else
      loadJsonParams params abiPlan wireParamNames?
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
