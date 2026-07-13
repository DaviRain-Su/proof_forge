/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.WasmHost.AbiPlan

namespace ProofForge.Backend.WasmHost.NearAbiPlan

open ProofForge.IR

abbrev Codec := ProofForge.Backend.WasmHost.AbiPlan.Codec
abbrev ValuePlan := ProofForge.Backend.WasmHost.AbiPlan.ValuePlan
abbrev EntrypointPlan := ProofForge.Backend.WasmHost.AbiPlan.EntrypointPlan

partial def borshByteWidth (structs : Array StructDecl) : ValueType → Except String Nat
  | .unit => .ok 0
  | .bool | .u8 => .ok 1
  | .u32 => .ok 4
  | .u64 | .address => .ok 8
  | .u128 => .ok 16
  | .hash => .ok 32
  | .string | .bytes => .ok 260
  | .fixedArray element length => return (← borshByteWidth structs element) * length
  | .structType name => do
      let some decl := structs.find? (fun decl => decl.name == name)
        | .error s!"NEAR ABI references unknown struct `{name}`"
      let mut size := 0
      for field in decl.fields do
        size := size + (← borshByteWidth structs field.type)
      .ok size
  | type => .error s!"NEAR Borsh ABI does not support dynamic `{type.name}` values"

/-- First wallet-compatible inbound JSON slice. Keep this classification in
the target ABI plan so contract lowering and generated clients consume the same
decision. Additional NEP-141/145 methods join only when their decoder and
real-VM gate land. -/
def usesJsonCodecForSignature (name : String) (params : Array (String × ValueType))
    (returns : ValueType) : Except String Bool := do
  if name != "ft_balance_of" then
    return false
  unless params == #[("account_id", .string)] && returns == .u128 do
    throw "NEAR standard entrypoint `ft_balance_of` must have signature (account_id : String) -> U128"
  return true

def buildSignaturePlan (structs : Array StructDecl) (name : String)
    (signatureParams : Array (String × ValueType)) (returns : ValueType) :
    Except String EntrypointPlan := do
  let useJson ← usesJsonCodecForSignature name signatureParams returns
  let inputCodec : ProofForge.Backend.WasmHost.AbiPlan.Codec :=
    if useJson then .json else .borsh
  let outputCodec : ProofForge.Backend.WasmHost.AbiPlan.Codec :=
    if useJson then .json else .borsh
  let mut offset := 0
  let mut params := #[]
  for param in signatureParams do
    let width ← if useJson then pure 0 else borshByteWidth structs param.snd
    params := params.push { name? := some param.fst, type := param.snd, offset, byteWidth := width }
    offset := offset + width
  let outputByteWidth ← if useJson then pure 0 else borshByteWidth structs returns
  .ok {
    name
    inputCodec
    outputCodec
    params
    inputByteWidth := offset
    returnType := returns
    outputByteWidth
  }

def buildEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint) :
    Except String EntrypointPlan :=
  buildSignaturePlan structs entrypoint.name entrypoint.params entrypoint.returns

def buildModulePlans (module : Module) : Except String (Array EntrypointPlan) :=
  module.entrypoints.mapM (buildEntrypointPlan module.structs)

def validateEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint)
    (plan : EntrypointPlan) : Except String Unit := do
  let expected <- buildEntrypointPlan structs entrypoint
  if plan != expected then
    .error s!"NEAR ABI plan for entrypoint `{entrypoint.name}` does not match its signature"
  .ok ()

end ProofForge.Backend.WasmHost.NearAbiPlan
