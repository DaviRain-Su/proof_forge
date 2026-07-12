/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Plan

namespace ProofForge.Backend.WasmHost.Crosscall

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Event
open ProofForge.Backend.WasmHost.Scalar
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Plan

/-! JSON argument-buffer helper functions for NEAR crosscall promises. -/

def crosscallPtrGlobal : String := "crosscall_ptr"
def crosscallArgsStartName : String := "__pf_crosscall_args_start"
def crosscallArgsPutcName : String := "__pf_crosscall_args_putc"
def crosscallArgsPutu64Name : String := "__pf_crosscall_args_putu64"
def crosscallArgsPutu128Name : String := "__pf_crosscall_args_putu128"
def crosscallArgsPutboolName : String := "__pf_crosscall_args_putbool"
def crosscallArgsPuthashName : String := "__pf_crosscall_args_puthash"

def crosscallPtrGlobalDecl : Global :=
  { name := crosscallPtrGlobal, type := .i32, init := toString CROSSCALL_BUF, isMutable := true }

def crosscallArgsStartFunc : Func :=
  { name := crosscallArgsStartName, body := { insns := #[ .i32Const CROSSCALL_BUF, .globalSet crosscallPtrGlobal ] } }

def crosscallArgsPutcFunc : Func :=
  { name := crosscallArgsPutcName, params := #[{ name := "c", type := .i32 }],
    body := { insns := #[
      .globalGet crosscallPtrGlobal, .localGet "c", .store "i32.store8" 0,
      .globalGet crosscallPtrGlobal, .i32Const 1, .plain "i32.add", .globalSet crosscallPtrGlobal ] } }

def crosscallArgsPutstrName : String := "__pf_crosscall_args_putstr"

def crosscallArgsPutstrFunc : Func :=
  { name := crosscallArgsPutstrName, params := #[{ name := "ptr", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .globalGet crosscallPtrGlobal, .localGet "ptr", .localGet "len", .call memcpyName,
      .globalGet crosscallPtrGlobal, .localGet "len", .plain "i32.add", .globalSet crosscallPtrGlobal ] } }

def crosscallArgsPutu64Func : Func :=
  { name := crosscallArgsPutu64Name, params := #[{ name := "v", type := .i64 }],
    locals := #[{ name := "p", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .localGet "v", .call fmtU64Name, .localSet "p",
      .i32Const (RET_BUF + 20), .localGet "p", .plain "i32.sub", .localSet "len",
      .globalGet crosscallPtrGlobal, .localGet "p", .localGet "len", .call memcpyName,
      .globalGet crosscallPtrGlobal, .localGet "len", .plain "i32.add", .globalSet crosscallPtrGlobal ] } }

def crosscallArgsPutboolFunc : Func :=
  { name := crosscallArgsPutboolName, params := #[{ name := "b", type := .i32 }],
    body := { insns := #[
      .localGet "b", .plain "i32.eqz",
      .if_ { insns := #[ .i32Const FALSE_PTR, .i32Const 5, .call crosscallArgsPutstrName ] }
         { insns := #[ .i32Const TRUE_PTR, .i32Const 4, .call crosscallArgsPutstrName ] } ] } }

/-! `__pf_crosscall_args_putu128(lo, hi)`: append the u128 decimal string
    (via `__pf_fmt_u128`) to the crosscall JSON arg buffer. -/
def crosscallArgsPutu128Func : Func :=
  { name := crosscallArgsPutu128Name,
    params := #[{ name := "lo", type := .i64 }, { name := "hi", type := .i64 }],
    locals := #[{ name := "p", type := .i32 }, { name := "len", type := .i32 }],
    body := { insns := #[
      .localGet "lo", .localGet "hi", .call u128FmtName, .localSet "p",
      .i32Const (RET_BUF + 40), .localGet "p", .plain "i32.sub", .localSet "len",
      .globalGet crosscallPtrGlobal, .localGet "p", .localGet "len", .call memcpyName,
      .globalGet crosscallPtrGlobal, .localGet "len", .plain "i32.add", .globalSet crosscallPtrGlobal ] } }

def crosscallArgsPuthashFunc : Func :=
  { name := crosscallArgsPuthashName, params := #[{ name := "v", type := .i32 }],
    locals := #[{ name := "i", type := .i32 }, { name := "b", type := .i32 }, { name := "hi", type := .i32 }, { name := "lo", type := .i32 }],
    body := { insns := #[
      .i32Const 0x22, .call crosscallArgsPutcName,
      .i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .i32Const 32, .plain "i32.eq", .brIf 1,
        .localGet "v", .localGet "i", .plain "i32.add", .load "i32.load8_u" 0, .localSet "b",
        .localGet "b", .i32Const 4, .plain "i32.shr_u", .i32Const 15, .plain "i32.and", .localSet "hi",
        .i32Const HEX_LUT_PTR, .localGet "hi", .plain "i32.add", .load "i32.load8_u" 0, .call crosscallArgsPutcName,
        .localGet "b", .i32Const 15, .plain "i32.and", .localSet "lo",
        .i32Const HEX_LUT_PTR, .localGet "lo", .plain "i32.add", .load "i32.load8_u" 0, .call crosscallArgsPutcName,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] } ] },
      .i32Const 0x22, .call crosscallArgsPutcName
    ] } }

def crosscallArgsHelperFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  if !plan.usesCrosscallArgs then
    #[]
  else
    (if plan.usesEventNumeric then #[] else if plan.usesFmtU64 then #[fmtU64Func] else #[]) ++
      #[crosscallArgsStartFunc, crosscallArgsPutcFunc, crosscallArgsPutstrFunc, crosscallArgsPutu64Func,
        crosscallArgsPutu128Func, crosscallArgsPutboolFunc] ++
      -- putu128 references __pf_fmt_u128 / __pf_u128_divmod10; emit them
      -- alongside so the helper set is self-contained regardless of whether
      -- the surrounding path includes u128ArithFuncs.
      #[u128Divmod10Func, u128FmtFunc] ++
      (if plan.usesCrosscallHash then #[crosscallArgsPuthashFunc] else #[])

def crosscallGlobalsForModulePlan (plan : ModulePlan) : Array Global :=
  if plan.usesCrosscallArgs then #[crosscallPtrGlobalDecl] else #[]

/-! Crosscall string-pool lookup helpers. -/

def poolLookupSetBody (strings : Array StringInfo) (field : StringInfo → Nat) : Array Insn :=
  (Array.range strings.size).foldl (fun acc i =>
    match strings[i]? with
    | none => acc
    | some si =>
      acc ++ #[.localGet "idx", .i64Const i, .plain "i64.eq",
        .if_ { insns := #[.i64Const (field si), .localSet "result"] } { insns := #[] }]) #[]

def crosscallPoolPtrFunc (strings : Array StringInfo) : Func :=
  { name := crosscallPoolPtrName,
    params := #[{ name := "idx", type := .i64 }],
    results := #[.i64],
    locals := #[{ name := "result", type := .i64 }],
    body := { insns :=
      #[.i64Const 0, .localSet "result"] ++
        poolLookupSetBody strings (fun si => si.ptr) ++
        #[.localGet "result"] } }

def crosscallPoolLenFunc (strings : Array StringInfo) : Func :=
  { name := crosscallPoolLenName,
    params := #[{ name := "idx", type := .i64 }],
    results := #[.i64],
    locals := #[{ name := "result", type := .i64 }],
    body := { insns :=
      #[.i64Const 0, .localSet "result"] ++
        poolLookupSetBody strings (fun si => si.len) ++
        #[.localGet "result"] } }

def crosscallPoolHelperFuncs (strings : Array StringInfo) : Array Func :=
  if strings.isEmpty then #[] else #[crosscallPoolPtrFunc strings, crosscallPoolLenFunc strings]

end ProofForge.Backend.WasmHost.Crosscall
