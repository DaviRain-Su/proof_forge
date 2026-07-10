/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.IR.Contract
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan

namespace ProofForge.Backend.WasmHost.Event

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan

/-! JSON event-buffer helper functions for EmitWat. -/

def fmtU64Name    : String := "__pf_fmt_u64"
def evtPtrGlobal   : String := "evt_ptr"
def evtStartName   : String := "__pf_evt_start"
def evtPutcName    : String := "__pf_evt_putc"
def evtPutstrName  : String := "__pf_evt_putstr"
def evtPutu64Name  : String := "__pf_evt_putu64"
def evtPutboolName : String := "__pf_evt_putbool"
def evtPutHashName : String := "__pf_evt_puthash"
def evtLogName     : String := "__pf_evt_log"

def evtPtrGlobalDecl : Global :=
  { name := evtPtrGlobal, type := .i32, init := toString EVENT_BUF, isMutable := true }

def fmtU64Func : Func :=
  { name := fmtU64Name, params := #[{ name := "v", type := .i64 }], results := #[.i32],
    locals := #[{ name := "tmp", type := .i64 }, { name := "p", type := .i32 }, { name := "d", type := .i32 }],
    body := { insns := #[
      .localGet "v", .localSet "tmp",
      .i32Const (RET_BUF + 20), .localSet "p",
      .localGet "tmp", .plain "i64.eqz",
      .if_ { insns := #[ .i32Const (RET_BUF + 19), .i32Const 48, .store "i32.store8" 0,
                        .i32Const (RET_BUF + 19), .localSet "p" ] }
         { insns := #[ .block_ { insns := #[ .loop_ { insns := #[
            .localGet "tmp", .plain "i64.eqz", .brIf 1,
            .localGet "tmp", .i64Const 10, .plain "i64.rem_u", .plain "i32.wrap_i64", .localSet "d",
            .localGet "tmp", .i64Const 10, .plain "i64.div_u", .localSet "tmp",
            .localGet "p", .i32Const 1, .plain "i32.sub", .localTee "p",
            .i32Const 48, .localGet "d", .plain "i32.add", .store "i32.store8" 0, .br 0 ] } ] } ] },
      .localGet "p" ] } }

def evtStartFunc : Func :=
  { name := evtStartName, body := { insns := #[ .i32Const EVENT_BUF, .globalSet evtPtrGlobal ] } }

def evtPutcFunc : Func :=
  { name := evtPutcName, params := #[{ name := "c", type := .i32 }],
    body := { insns := #[
      .globalGet evtPtrGlobal, .localGet "c", .store "i32.store8" 0,
      .globalGet evtPtrGlobal, .i32Const 1, .plain "i32.add", .globalSet evtPtrGlobal ] } }

def evtPutstrFunc : Func :=
  { name := evtPutstrName, params := #[{ name := "ptr", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .globalGet evtPtrGlobal, .localGet "ptr", .localGet "len", .call memcpyName,
      .globalGet evtPtrGlobal, .localGet "len", .plain "i32.add", .globalSet evtPtrGlobal ] } }

/-- Format a u64 decimal directly into the event buffer (no separate fmt helper
call). Digits are written reverse into `RET_BUF` scratch then memcpy'd once. -/
def evtPutu64Func : Func :=
  { name := evtPutu64Name, params := #[{ name := "v", type := .i64 }],
    locals := #[{ name := "tmp", type := .i64 }, { name := "p", type := .i32 },
                { name := "d", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .localGet "v", .localSet "tmp",
      .localGet "tmp", .plain "i64.eqz",
      .if_ { insns := #[
          .globalGet evtPtrGlobal, .i32Const 48, .store "i32.store8" 0,
          .globalGet evtPtrGlobal, .i32Const 1, .plain "i32.add", .globalSet evtPtrGlobal ] }
         { insns := #[
          .i32Const (RET_BUF + 20), .localSet "p",
          .block_ { insns := #[ .loop_ { insns := #[
            .localGet "tmp", .plain "i64.eqz", .brIf 1,
            .localGet "tmp", .i64Const 10, .plain "i64.rem_u", .plain "i32.wrap_i64", .localSet "d",
            .localGet "tmp", .i64Const 10, .plain "i64.div_u", .localSet "tmp",
            .localGet "p", .i32Const 1, .plain "i32.sub", .localTee "p",
            .i32Const 48, .localGet "d", .plain "i32.add", .store "i32.store8" 0, .br 0 ] } ] },
          .i32Const (RET_BUF + 20), .localGet "p", .plain "i32.sub", .localSet "len",
          .globalGet evtPtrGlobal, .localGet "p", .localGet "len", .call memcpyName,
          .globalGet evtPtrGlobal, .localGet "len", .plain "i32.add", .globalSet evtPtrGlobal ] }
    ] } }

def evtPutboolFunc : Func :=
  { name := evtPutboolName, params := #[{ name := "b", type := .i32 }],
    body := { insns := #[
      .localGet "b", .plain "i32.eqz",
      .if_ { insns := #[ .i32Const FALSE_PTR, .i32Const 5, .call evtPutstrName ] }
         { insns := #[ .i32Const TRUE_PTR, .i32Const 4, .call evtPutstrName ] } ] } }

/-- JSON-encode a 32-byte hash as a quoted lowercase hex string. -/
def evtPutHashFunc : Func :=
  { name := evtPutHashName, params := #[{ name := "v", type := .i32 }],
    locals := #[{ name := "i", type := .i32 }, { name := "b", type := .i32 }, { name := "hi", type := .i32 }, { name := "lo", type := .i32 }],
    body := { insns := #[
      .i32Const 0x22, .call evtPutcName,
      .i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .i32Const 32, .plain "i32.eq", .brIf 1,
        .localGet "v", .localGet "i", .plain "i32.add", .load "i32.load8_u" 0, .localSet "b",
        .localGet "b", .i32Const 4, .plain "i32.shr_u", .i32Const 15, .plain "i32.and", .localSet "hi",
        .i32Const HEX_LUT_PTR, .localGet "hi", .plain "i32.add", .load "i32.load8_u" 0, .call evtPutcName,
        .localGet "b", .i32Const 15, .plain "i32.and", .localSet "lo",
        .i32Const HEX_LUT_PTR, .localGet "lo", .plain "i32.add", .load "i32.load8_u" 0, .call evtPutcName,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] } ] },
      .i32Const 0x22, .call evtPutcName
    ] } }

def evtLogFunc : Func :=
  { name := evtLogName,
    body := { insns := #[
      .globalGet evtPtrGlobal, .i32Const EVENT_BUF, .plain "i32.sub", .plain "i64.extend_i32_u",
      .i64Const EVENT_BUF, .call "log_utf8" ] } }

def evtHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  -- Keep `fmtU64Func` when numeric events are used so Crosscall can share it
  -- (`usesEventNumeric ⇒ skip emitting fmt in Crosscall`). Event putu64 itself
  -- inlines decimal formatting to avoid an extra call per field.
  (if plan.usesEventNumeric then #[fmtU64Func] else #[]) ++
    (if plan.usesEventApi then #[evtStartFunc, evtPutcFunc, evtPutstrFunc] else #[]) ++
    (if plan.usesEventNumeric then #[evtPutu64Func] else #[]) ++
    (if plan.usesEventBool then #[evtPutboolFunc] else #[]) ++
    (if plan.usesEventHash then #[evtPutHashFunc] else #[]) ++
    (if plan.usesEventApi then #[evtLogFunc] else #[])

def evtGlobals : Array Global := #[ evtPtrGlobalDecl ]

def evtPutcInsns (c : Nat) : Array Insn :=
  #[.i32Const c, .call evtPutcName]

def evtPutstrInsns (ptr len : Nat) : Array Insn :=
  #[.i32Const ptr, .i32Const len, .call evtPutstrName]

/-- Emit composite header `{"event":"<name>"` from the string pool (one putstr). -/
def evtHeaderInsns (nameSi : StringInfo) : Array Insn :=
  #[.call evtStartName]
    ++ #[.i32Const nameSi.ptr, .i32Const nameSi.len, .call evtPutstrName]

def evtValueInsnsForType (fieldName : String) (type : ValueType) :
    Except EmitError (Array Insn) :=
  match type with
  | .u64 => .ok #[.call evtPutu64Name]
  | .u32 => .ok #[.plain "i64.extend_i32_u", .call evtPutu64Name]
  | .bool => .ok #[.call evtPutboolName]
  | .hash => .ok #[.call evtPutHashName]
  | _ => err s!"EmitWat: event field `{fieldName}` has unsupported type `{type.name}`"

/-- Emit composite `,"field":` + value (one putstr for the static key fragment). -/
def evtFieldInsns (fieldName : String) (fieldSi : StringInfo)
    (valueInsns : Array Insn) (valueType : ValueType) : Except EmitError (Array Insn) := do
  let valInsns ← evtValueInsnsForType fieldName valueType
  .ok (#[.i32Const fieldSi.ptr, .i32Const fieldSi.len, .call evtPutstrName]
    ++ valueInsns ++ valInsns)

def evtFooterInsns : Array Insn :=
  evtPutstrInsns EVT_CLOSE_PTR 1 ++ #[.call evtLogName]

end ProofForge.Backend.WasmHost.Event
