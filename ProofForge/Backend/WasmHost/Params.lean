/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types
import ProofForge.Target.HostBridge

namespace ProofForge.Backend.WasmHost.Params

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmHost.ArrayHeap
open ProofForge.Backend.WasmHost.Common
open ProofForge.Backend.WasmHost.Diagnostics
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.Struct
open ProofForge.Backend.WasmHost.Types

/-! Entrypoint parameter decoding helpers for EmitWat. -/

/-- NEAR Borsh input prologue: `env.input` → register → INPUT_BUF. -/
def nearInputPrologue : Array Insn :=
  #[.i64Const 0, .call "input", .i64Const 0, .i64Const INPUT_BUF, .call "read_register"]

/-- Build the Borsh input prologue and load each param into a local.

* **No params:** empty prologue on all bridges (no residual `input` / `read_register`).
* **NEAR / Soroban:** Borsh decode via `env.input` + `read_register` (Soroban still
  imports these until a Soroban-native param ABI lands).
* **CosmWasm:** reject non-empty params until CosmWasm message decoding lands
  (Counter spike path does not use IR params). -/
def loadParams (structs : Array ProofForge.IR.StructDecl)
    (params : Array (String × ValueType))
    (bridge : ProofForge.Target.HostBridge := .near)
    : Except EmitError (Array Insn × Array Local) := do
  -- CosmWasm: no NEAR input — empty prologue only; reject params for now.
  if bridge == .cosmWasm then
    if params.isEmpty then
      .ok (#[], #[])
    else
      err "EmitWat: entrypoint parameters are not yet lowered on HostBridge.cosmWasm (use Counter spike or zero-param entries)"
  else if params.isEmpty then
    -- Skip host `input` for zero-arg entrypoints (Counter initialize/increment/get,
    -- ValueVault views). Saves a host call with no ABI payload to decode.
    .ok (#[], #[])
  else
  let prologue : Array Insn := nearInputPrologue
  let result ← params.foldlM (init := (prologue, (#[] : Array Local), 0, 0))
    fun (insns, locals, offset, hslot) p =>
      let (name, vt) := p
      match vt with
      | .u32 | .u64 | .bool =>
        let loadInsns := #[.i32Const (INPUT_BUF + offset), .load (loadOpFor vt) 0, .localSet name]
        .ok (insns ++ loadInsns, locals.push { name := name, type := wasmTypeOf vt }, offset + scalarWidth vt, hslot)
      | .u128 =>
        -- U128: 16-byte Borsh LE. Allocate 16 bytes, copy low 8 + high 8 from INPUT_BUF.
        -- Local holds an i32 pointer to the 16-byte buffer.
        let loadInsns :=
          #[.i64Const 16, .call arrAllocName, .localSet name,
            .localGet name, .i32Const (INPUT_BUF + offset), .load "i64.load" 0, .store "i64.store" 0,
            .localGet name, .i32Const (INPUT_BUF + offset + 8), .load "i64.load" 0, .store "i64.store" 8]
        .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + 16, hslot)
      | .hash =>
        let slot := PARAM_HASH_BUF + hslot * 32
        let loadInsns := #[.i32Const slot, .i32Const (INPUT_BUF + offset), .i32Const 32, .call memcpyName,
                           .i32Const slot, .localSet name]
        .ok (insns ++ loadInsns, locals.push { name := name, type := wasmTypeOf vt }, offset + 32, hslot + 1)
      | .fixedArray elemType n =>
        if !(isScalarBorshType elemType) then
          err s!"EmitWat: param `{name}` has unsupported fixedArray element type `{elemType.name}` (only scalar elements supported in Borsh params)"
        else
          let elemWidth := scalarWidth elemType
          let totalBytes := n * elemWidth
          let loadInsns :=
            #[.i64Const totalBytes, .call arrAllocName, .localSet name] ++
            (Array.range n).foldl (fun (acc : Array Insn) i =>
              let srcOff := INPUT_BUF + offset + i * elemWidth
              let dstOff := i * elemWidth
              let loadElem :=
                if elemType == ProofForge.IR.ValueType.hash then
                  #[.i32Const dstOff, .localGet name, .plain "i32.add",
                    .i32Const srcOff, .i32Const 32, .call memcpyName]
                else
                  #[.i32Const dstOff, .localGet name, .plain "i32.add",
                    .i32Const srcOff, .load (loadOpFor elemType) 0,
                    .store (storeOpFor elemType) 0]
              acc ++ loadElem) #[]
          .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + totalBytes, hslot)
      | .structType typeName =>
        match structs.find? (fun s => s.name == typeName) with
        | none => err s!"EmitWat: param `{name}` references unknown struct `{typeName}`"
        | some sd =>
          if !structStorageFieldsSupported sd then
            err s!"EmitWat: param `{name}` struct `{typeName}` has non-scalar fields (only u32/u64/bool/hash supported in Borsh params)"
          else
            let totalBytes := structTotalSize sd
            let loadInsns :=
              #[.i64Const totalBytes, .call arrAllocName, .localSet name] ++
              sd.fields.foldl (fun (acc : Array Insn) f =>
                let fieldOff := structFieldOffset? sd f.id |>.getD 0
                let srcOff := INPUT_BUF + offset + fieldOff
                let dstOff := fieldOff
                let loadField :=
                  if f.type == ProofForge.IR.ValueType.hash then
                    #[.i32Const dstOff, .localGet name, .plain "i32.add",
                      .i32Const srcOff, .i32Const 32, .call memcpyName]
                  else
                    #[.i32Const dstOff, .localGet name, .plain "i32.add",
                      .i32Const srcOff, .load (loadOpFor f.type) 0,
                      .store (storeOpFor f.type) 0]
                acc ++ loadField) #[]
          .ok (insns ++ loadInsns, locals.push { name := name, type := .i32 }, offset + totalBytes, hslot)
      | .bytes | .string =>
        -- Borsh dynamic bytes/string: 4-byte LE length prefix + payload.
        -- Allocate a buffer, copy the 4-byte length prefix + payload from INPUT_BUF.
        -- The local holds an i32 pointer to the payload (length prefix at ptr - 4).
        let lenOff := INPUT_BUF + offset
        let loadInsns :=
          #[.i32Const lenOff, .load "i32.load" 0, .localSet (name ++ "_len"),
            .localGet (name ++ "_len"), .plain "i64.extend_i32_u", .i64Const 4, .plain "i64.add",
            .call arrAllocName, .localSet name,
            .localGet name, .i32Const lenOff, .i32Const 4, .call memcpyName,
            .localGet name, .i32Const 4, .plain "i32.add", .localSet name]
        .ok (insns ++ loadInsns,
            locals.push { name := name ++ "_len", type := .i32 } |>.push { name := name, type := .i32 },
            offset + 260, hslot)
      | _ => err s!"EmitWat: param `{name}` has unsupported Borsh type `{vt.name}`"
  pure (result.fst, result.snd.fst)

end ProofForge.Backend.WasmHost.Params
