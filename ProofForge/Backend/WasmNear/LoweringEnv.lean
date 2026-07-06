/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Backend.WasmNear.Diagnostics
import ProofForge.Backend.WasmNear.Layout
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.LoweringEnv

open ProofForge.IR
open ProofForge.Backend.WasmNear.Diagnostics
open ProofForge.Backend.WasmNear.Layout
open ProofForge.Backend.WasmNear.Types

/-! Shared lowering context and local-type environment for EmitWat. -/

structure Ctx where
  scalars : Array StateInfo
  maps    : Array MapInfo
  strings : Array StringInfo
  panics  : Array StringInfo
  crosscallStrings : Array StringInfo
  structs : Array ProofForge.IR.StructDecl
  allocator : ProofForge.IR.AllocatorConfig

structure LBind where
  name : String
  vt : ValueType

abbrev LocalTypes := Array LBind

def lookupLocal? (env : LocalTypes) (name : String) : Option ValueType :=
  match env.find? (fun b => b.name == name) with
  | some b => some b.vt
  | none => none

def assignOpName : AssignOp → String
  | .add => "add" | .sub => "sub" | .mul => "mul" | .div => "div_u" | .mod => "rem_u"
  | .bitAnd => "and" | .bitOr => "or" | .bitXor => "xor"
  | .shiftLeft => "shl" | .shiftRight => "shr_u"

def resolveCrosscallStringRef (ctx : Ctx) (e : Expr) (role : String) : Except EmitError StringInfo :=
  match e with
  | .literal (.address idx) =>
    match ctx.crosscallStrings[idx]? with
    | some si => .ok si
    | none =>
      err s!"EmitWat: NEAR crosscall {role} index `{idx}` is out of range for `module.nearCrosscallStrings`"
  | _ =>
    err s!"EmitWat: NEAR crosscall {role} must be `.literal (.address <index>)` into `module.nearCrosscallStrings`"

end ProofForge.Backend.WasmNear.LoweringEnv
