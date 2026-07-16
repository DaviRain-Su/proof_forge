/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# WasmHost JSON encode builder

Compile-time JSON construction for **contract runtime** buffers (NEAR
crosscall args, events). Not a host-side serde library: emits Wasm
`putc` / `putstr` / `putu64` sequences into a scratch buffer.

## Sink

A `Sink` names the start/putc/putstr/putu64 helpers for a buffer
(crosscall vs event). Protocol shapes (NEP-141, …) build `Node` trees and
call `lower` once — no hand-rolled ASCII loops per method.

## Supported nodes (honest subset)

| Node | JSON |
|------|------|
| `null_` | `null` |
| `boolLit` | `true` / `false` |
| `strLit` | `"…"` (static, no escape of quotes in content) |
| `strPoolStatic` | quoted string from compile-time `StringInfo` |
| `strPoolIdx` | quoted string; `idxInsns` leave i64 pool index (duplicated) |
| `u64Num` | unquoted decimal (`putu64`) |
| `u64Str` | quoted decimal string |
| `arr` | `[a,b,…]` |
| `obj` | `{"k":v,…}` |

Unsupported: nested arbitrary dynamic objects from IR, full Unicode escape,
Borsh. Extend `Node` + `lower` rather than packing in call sites.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Layout

namespace ProofForge.Backend.WasmHost.JsonEncode

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Layout

/-- Backend helpers for one JSON scratch buffer. -/
structure Sink where
  /-- Reset write cursor to buffer base. -/
  startName : String
  putcName : String
  putstrName : String
  putu64Name : String
  /-- Optional: pool index (i64) → ptr (i64) for dynamic account ids. -/
  poolPtrName? : Option String := none
  /-- Optional: pool index (i64) → len (i64). -/
  poolLenName? : Option String := none
  deriving Repr

/-- Crosscall args buffer (`__pf_crosscall_args_*`). -/
def crosscallSink : Sink := {
  startName := "__pf_crosscall_args_start"
  putcName := "__pf_crosscall_args_putc"
  putstrName := "__pf_crosscall_args_putstr"
  putu64Name := "__pf_crosscall_args_putu64"
  poolPtrName? := some "__pf_crosscall_pool_ptr"
  poolLenName? := some "__pf_crosscall_pool_len"
}

/-- Event log buffer (`__pf_evt_*`). -/
def eventSink : Sink := {
  startName := "__pf_evt_start"
  putcName := "__pf_evt_putc"
  putstrName := "__pf_evt_putstr"
  putu64Name := "__pf_evt_putu64"
  poolPtrName? := none
  poolLenName? := none
}

/-- Instruction fragment (already-lowered value producers). -/
structure Frag where
  insns : Array Insn

def Frag.append (a b : Frag) : Frag :=
  { insns := a.insns ++ b.insns }

def Frag.concat (frags : Array Frag) : Frag :=
  { insns := frags.foldl (fun acc f => acc ++ f.insns) #[] }

/-- JSON syntax tree. Dynamic leaves carry **already-lowered** Wasm insns. -/
inductive Node where
  | null_
  | boolLit (value : Bool)
  /-- Static UTF-8 text, JSON-quoted (content must not contain `"` / `\`). -/
  | strLit (value : String)
  /-- Quoted string from a static data-pool entry. -/
  | strPoolStatic (si : StringInfo)
  /-- Quoted string: `idxInsns` produce i64 pool index (must be duplicable). -/
  | strPoolIdx (idxInsns : Array Insn)
  /-- Unquoted decimal; `valInsns` leave i64. -/
  | u64Num (valInsns : Array Insn)
  /-- Quoted decimal string; `valInsns` leave i64. -/
  | u64Str (valInsns : Array Insn)
  | arr (items : Array Node)
  | obj (fields : Array (String × Node))

/-- Object field sugar. -/
def field (key : String) (value : Node) : String × Node :=
  (key, value)

def putcInsns (sink : Sink) (c : Nat) : Array Insn :=
  #[.i32Const c, .call sink.putcName]

def putAsciiInsns (sink : Sink) (s : String) : Array Insn :=
  s.foldl
    (fun acc c => acc ++ putcInsns sink c.toNat)
    #[]

def startInsns (sink : Sink) : Array Insn :=
  #[.call sink.startName]

/-- Lower one JSON node (without buffer start). -/
partial def lowerNode (sink : Sink) (node : Node) : Except String (Array Insn) :=
  match node with
  | .null_ => .ok (putAsciiInsns sink "null")
  | .boolLit true => .ok (putAsciiInsns sink "true")
  | .boolLit false => .ok (putAsciiInsns sink "false")
  | .strLit s =>
      .ok (putcInsns sink 0x22 ++ putAsciiInsns sink s ++ putcInsns sink 0x22)
  | .strPoolStatic si =>
      .ok (
        putcInsns sink 0x22 ++
        #[.i32Const si.ptr, .i32Const si.len, .call sink.putstrName] ++
        putcInsns sink 0x22
      )
  | .strPoolIdx idxInsns =>
      match sink.poolPtrName?, sink.poolLenName? with
      | some poolPtr, some poolLen =>
          .ok (
            putcInsns sink 0x22 ++
            idxInsns ++ #[.call poolPtr, .plain "i32.wrap_i64"] ++
            idxInsns ++ #[.call poolLen, .plain "i32.wrap_i64"] ++
            #[.call sink.putstrName] ++
            putcInsns sink 0x22
          )
      | _, _ =>
          .error "JsonEncode: strPoolIdx requires sink.poolPtrName?/poolLenName?"
  | .u64Num valInsns =>
      .ok (valInsns ++ #[.call sink.putu64Name])
  | .u64Str valInsns =>
      .ok (
        putcInsns sink 0x22 ++
        valInsns ++ #[.call sink.putu64Name] ++
        putcInsns sink 0x22
      )
  | .arr items => do
      let mut body := putcInsns sink 0x5B  -- [
      let mut first := true
      for item in items do
        if !first then
          body := body ++ putcInsns sink 0x2C  -- ,
        first := false
        body := body ++ (← lowerNode sink item)
      .ok (body ++ putcInsns sink 0x5D)  -- ]
  | .obj fields => do
      let mut body := putcInsns sink 0x7B  -- {
      let mut first := true
      for (key, value) in fields do
        if !first then
          body := body ++ putcInsns sink 0x2C
        first := false
        -- "key":
        body := body ++ putcInsns sink 0x22 ++ putAsciiInsns sink key ++
          putcInsns sink 0x22 ++ putcInsns sink 0x3A
        body := body ++ (← lowerNode sink value)
      .ok (body ++ putcInsns sink 0x7D)  -- }

/-- Start buffer + encode root node. Returns full insn stream. -/
def lower (sink : Sink) (root : Node) : Except String (Array Insn) := do
  let body ← lowerNode sink root
  .ok (startInsns sink ++ body)

/-- Encode into crosscall args buffer; returns (insns, bufferBase, lenMarker0).
`lenMarker = 0` means caller should use `ptr - base` for length (non-empty). -/
def lowerCrosscallArgs (root : Node) (bufferBase : Nat) :
    Except String (Array Insn × Nat × Nat) := do
  let insns ← lower crosscallSink root
  .ok (insns, bufferBase, 0)

/-- Catalog id for docs / diagnostics. -/
def catalogId : String := "wasmhost.json_encode"

end ProofForge.Backend.WasmHost.JsonEncode
