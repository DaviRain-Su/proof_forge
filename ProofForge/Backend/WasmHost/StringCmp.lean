/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Plan

namespace ProofForge.Backend.WasmHost.StringCmp

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Plan

/-! ## String equality (Phase 3 NEP-141 interop)

    `__pf_str_eq(ptr1, len1, ptr2, len2) → i32` compares two byte sequences.
    Returns 1 if both lengths match AND every byte matches, else 0. Used by
    the canonical NEAR lowering for `.string` equality (e.g. the FT's
    `requireEq callerAccountId (read mintAuthority)` and
    `requireEq callerAccountId account_id`). The identity is the raw
    predecessor_account_id, so two reads of the same caller compare equal. -/

def strEqName : String := "__pf_str_eq"

def strEqFunc : Func :=
  { name := strEqName,
    params := #[{ name := "p1", type := .i32 }, { name := "l1", type := .i32 },
      { name := "p2", type := .i32 }, { name := "l2", type := .i32 }],
    results := #[.i32],
    locals := #[{ name := "i", type := .i32 }, { name := "r", type := .i32 }],
    body := { insns := #[
      -- Fast path: differing lengths → 0.
      .localGet "l1", .localGet "l2", .plain "i32.ne",
      .if_ { insns := #[.i32Const 0, .return_] } { insns := #[] },
      -- Assume equal; loop over bytes.
      .i32Const 0, .localSet "i",
      .i32Const 1, .localSet "r",
      .block_ { insns := #[
        .loop_ { insns := #[
          -- i >= l1 → done (r stays 1).
          .localGet "i", .localGet "l1", .plain "i32.ge_u", .brIf 1,
          -- byte1 := *(p1 + i); byte2 := *(p2 + i).
          .localGet "p1", .localGet "i", .plain "i32.add", .load "i32.load8_u" 0,
          .localGet "p2", .localGet "i", .plain "i32.add", .load "i32.load8_u" 0,
          .plain "i32.ne",
          .if_ { insns := #[.i32Const 0, .localSet "r", .br 2] } { insns := #[] },
          -- i += 1; continue.
          .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i",
          .br 0
        ] }
      ] },
      .localGet "r" ] } }

/-! Emit the string-equality helper when the module plan uses string-indexed
    comparison. The canonical NEAR lowering gates this on
    `modulePlan.usesStrEq`; the legacy path is not yet wired. -/

def strEqFuncsForModulePlan (modulePlan : ModulePlan) : Array Func :=
  if modulePlan.usesStrEq then #[strEqFunc] else #[]

end ProofForge.Backend.WasmHost.StringCmp