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

def buildEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint) :
    Except String EntrypointPlan := do
  let mut offset := 0
  let mut params := #[]
  for param in entrypoint.params do
    let width ← borshByteWidth structs param.snd
    params := params.push { name? := some param.fst, type := param.snd, offset, byteWidth := width }
    offset := offset + width
  let outputByteWidth ← borshByteWidth structs entrypoint.returns
  .ok {
    name := entrypoint.name
    inputCodec := .borsh
    outputCodec := .borsh
    params
    inputByteWidth := offset
    returnType := entrypoint.returns
    outputByteWidth
  }

def buildModulePlans (module : Module) : Except String (Array EntrypointPlan) :=
  module.entrypoints.mapM (buildEntrypointPlan module.structs)

def validateEntrypointPlan (structs : Array StructDecl) (entrypoint : Entrypoint)
    (plan : EntrypointPlan) : Except String Unit := do
  let expected <- buildEntrypointPlan structs entrypoint
  if plan != expected then
    .error s!"NEAR ABI plan for entrypoint `{entrypoint.name}` does not match its signature"
  .ok ()

end ProofForge.Backend.WasmHost.NearAbiPlan
