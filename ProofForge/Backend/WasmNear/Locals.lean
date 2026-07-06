/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.LoweringEnv
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Locals

open ProofForge.IR
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.LoweringEnv
open ProofForge.Backend.WasmNear.Types

/-! Local-type collection for EmitWat entrypoint lowering. -/

partial def collectLocalsFrom (acc : LocalTypes) (s : Statement) : Except EmitError LocalTypes := do
  match s with
  | .letBind name t _ | .letMutBind name t _ =>
    if isNumeric t || t == .bool || t == .hash then .ok (acc.push { name := name, vt := t })
    else match t with
      | .fixedArray _ _ | .structType _ => .ok (acc.push { name := name, vt := t })
      | _ => err s!"EmitWat: only U32/U64/Bool/Hash/FixedArray/Struct locals are supported (got `{t.name}`)"
  | .ifElse _ thenBody elseBody =>
    let acc ← thenBody.foldlM (init := acc) collectLocalsFrom
    elseBody.foldlM (init := acc) collectLocalsFrom
  | .boundedFor indexName _ _ body =>
    let acc := acc.push { name := indexName, vt := .u64 }
    body.foldlM (init := acc) collectLocalsFrom
  | .release _ => .ok acc
  | _ => .ok acc

def collectLocals (body : Array Statement) : Except EmitError LocalTypes :=
  body.foldlM (init := #[]) collectLocalsFrom

end ProofForge.Backend.WasmNear.Locals
