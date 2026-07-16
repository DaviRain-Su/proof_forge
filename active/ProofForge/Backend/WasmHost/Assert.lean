/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.Layout

namespace ProofForge.Backend.WasmHost.Assert

open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.Layout

/-! Assertion failure helpers for EmitWat statement lowering. -/

def assertFailInsns (panics : Array StringInfo) (errorRef? : Option ProofForge.IR.ErrorRef) :
    Array Insn :=
  match errorRef? with
  | none => #[.unreachable]
  | some ref =>
    let msg := panicMessage ref
    match panics.find? (fun si => si.str == msg) with
    | none => #[.unreachable]
    | some si => #[.i64Const si.len, .i64Const si.ptr, .call "panic"]

end ProofForge.Backend.WasmHost.Assert
