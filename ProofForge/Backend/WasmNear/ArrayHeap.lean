/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.Imports
import ProofForge.Backend.WasmNear.Plan

namespace ProofForge.Backend.WasmNear.ArrayHeap

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.Imports
open ProofForge.Backend.WasmNear.Plan

/-! Array-value heap allocator helpers for fixed-array literals and temporaries. -/

def arrPtrGlobal : String := "arr_ptr"
def arrFreeGlobal : String := "arr_free"
def arrAllocName : String := "__pf_arr_alloc"

/-- The `arr_ptr` mutable global holds the bump frontier; only emitted for
    chain-deployment allocators (offline imported allocators have no frontier). -/
def arrPtrGlobalDecl (heapBase : Nat) : Global :=
  { name := arrPtrGlobal, type := .i32, init := toString heapBase, isMutable := true }

def arrFreeGlobalDecl : Global :=
  { name := arrFreeGlobal, type := .i32, init := "0", isMutable := true }

/-- `__pf_arr_alloc(n) -> i32` lowered per allocator mode: no-free deployment
    advances the frontier; NEAR/minimal deployment emits a wasm-internal
    first-fit allocator; offline experiments forward to `pf_alloc`. -/
def arrAllocFunc (cfg : ProofForge.IR.AllocatorConfig) : Func :=
  if cfg.usesMinimalMallocShape then
    { name := arrAllocName, params := #[{ name := "n", type := .i64 }], results := #[.i32],
      locals := #[{ name := "need", type := .i32 }, { name := "prev", type := .i32 },
                  { name := "curr", type := .i32 }, { name := "next", type := .i32 },
                  { name := "block", type := .i32 }, { name := "end", type := .i32 }],
      body := { insns := #[
        -- total block size = align8(payload bytes + 8-byte header)
        .localGet "n", .i64Const 15, .plain "i64.add", .const .i64 "-8", .plain "i64.and",
        .plain "i32.wrap_i64", .localSet "need",
        .i32Const 0, .localSet "prev",
        .globalGet arrFreeGlobal, .localSet "curr",
        .block_ { insns := #[ .loop_ { insns := #[
          .localGet "curr", .plain "i32.eqz", .brIf 1,
          .localGet "curr", .load "i32.load" 0, .localGet "need", .plain "i32.ge_u",
          .if_ { insns := #[
            .localGet "curr", .load "i32.load" 4, .localSet "next",
            .localGet "prev", .plain "i32.eqz",
            .if_ { insns := #[ .localGet "next", .globalSet arrFreeGlobal ] }
                 { insns := #[ .localGet "prev", .localGet "next", .store "i32.store" 4 ] },
            .localGet "curr", .i32Const 8, .plain "i32.add", .return_ ] } { insns := #[] },
          .localGet "curr", .localSet "prev",
          .localGet "curr", .load "i32.load" 4, .localSet "curr",
          .br 0 ] } ] },
        .globalGet arrPtrGlobal, .localSet "block",
        .localGet "block", .localGet "need", .plain "i32.add", .localSet "end",
        .localGet "end", .plain "memory.size", .i32Const 65536, .plain "i32.mul", .plain "i32.gt_u",
        .if_ { insns := #[
          .localGet "end", .plain "memory.size", .i32Const 65536, .plain "i32.mul", .plain "i32.sub",
          .i32Const 65535, .plain "i32.add", .i32Const 16, .plain "i32.shr_u",
          .plain "memory.grow", .const .i32 "-1", .plain "i32.eq",
          .if_ { insns := #[.unreachable] } { insns := #[] } ] } { insns := #[] },
        .localGet "end", .globalSet arrPtrGlobal,
        .localGet "block", .localGet "need", .store "i32.store" 0,
        .localGet "block", .i32Const 0, .store "i32.store" 4,
        .localGet "block", .i32Const 8, .plain "i32.add" ] } }
  else
    { name := arrAllocName, params := #[{ name := "n", type := .i64 }], results := #[.i32],
      body := { insns :=
        if cfg.requiresHost then #[.localGet "n", .call allocImportName]
        else #[ .globalGet arrPtrGlobal,
          .globalGet arrPtrGlobal, .localGet "n", .plain "i32.wrap_i64", .plain "i32.add", .globalSet arrPtrGlobal ] } }

/-- `__pf_arr_dealloc(ptr, n)`: no-op for no-free deployment strategies, host
    forwarder for offline experiments, and wasm-internal free-list update for
    chain deployment allocators with reuse. `Statement.release` lowers to this
    helper for heap-backed locals. -/
def arrDeallocFunc (cfg : ProofForge.IR.AllocatorConfig) : Func :=
  if cfg.usesMinimalMallocShape then
    { name := "__pf_arr_dealloc", params := #[{ name := "p", type := .i32 }, { name := "n", type := .i64 }],
      results := #[], locals := #[{ name := "block", type := .i32 }],
      body := { insns := #[
        .localGet "p", .plain "i32.eqz",
        .if_ { insns := #[.return_] } { insns := #[] },
        .localGet "p", .i32Const 8, .plain "i32.sub", .localSet "block",
        .localGet "block", .globalGet arrFreeGlobal, .store "i32.store" 4,
        .localGet "block", .globalSet arrFreeGlobal ] } }
  else
    { name := "__pf_arr_dealloc", params := #[{ name := "p", type := .i32 }, { name := "n", type := .i64 }],
      results := #[],
      body := { insns := if cfg.requiresHost then #[.localGet "p", .localGet "n", .call deallocImportName] else #[] } }

def modulePlanUsesArrHeap (plan : ModulePlan) : Bool :=
  plan.usesArrAlloc || plan.usesArrDealloc

def arrHeapHelperFuncsForModulePlan (plan : ModulePlan) (cfg : ProofForge.IR.AllocatorConfig) : Array Func :=
  (if plan.usesArrAlloc then #[arrAllocFunc cfg] else #[]) ++
    (if plan.usesArrDealloc then #[arrDeallocFunc cfg] else #[])

end ProofForge.Backend.WasmNear.ArrayHeap
