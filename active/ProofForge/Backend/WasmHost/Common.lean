/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Compiler.Wasm.AST

namespace ProofForge.Backend.WasmHost.Common

open ProofForge.Compiler.Wasm

/-! Shared low-level helper names used across multiple EmitWat helper groups. -/

def memcpyName : String := "__pf_memcpy"

def memcpyFunc : Func :=
  { name := memcpyName,
    params := #[{ name := "dst", type := .i32 }, { name := "src", type := .i32 }, { name := "n", type := .i32 }],
    locals := #[{ name := "i", type := .i32 }],
    body := { insns := #[
      .i32Const 0, .localSet "i",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .localGet "n", .plain "i32.ge_u", .brIf 1,
        .localGet "i", .localGet "dst", .plain "i32.add",
        .localGet "i", .localGet "src", .plain "i32.add", .load "i32.load8_u" 0,
        .store "i32.store8" 0,
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0 ] } ] } ] } }

end ProofForge.Backend.WasmHost.Common
